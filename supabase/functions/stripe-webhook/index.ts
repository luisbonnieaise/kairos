// Supabase Edge Function — Stripe Webhook (billing multiplataforma)
// Recebe eventos da Stripe, verifica a assinatura HMAC, deduplica via
// billing_events (provider='stripe') e converge public.subscriptions
// RE-BUSCANDO o estado real na Stripe e chamando a RPC canônica
// aplicar_estado_assinatura(). Deploy OBRIGATÓRIO com --no-verify-jwt: a Stripe
// não envia JWT do Supabase; a segurança é a assinatura do payload.
//
// Princípios (docs/00-visao-arquitetura.md §5 e docs/07-billing-multiplataforma.md §0):
//   • Idempotência: INSERT em billing_events ON CONFLICT DO NOTHING ANTES de
//     processar. Se nada foi inserido (evento já visto) → 200 sem reprocessar.
//   • Canonicidade (anti fora-de-ordem): NÃO confiar nos campos do evento.
//     Re-buscar a subscription na Stripe e aplicar via RPC (UPSERT atômico).
//   • Convergência: a RPC impede que a Stripe rebaixe um Premium ativo de
//     outro provider (e vice-versa). Aqui só passamos o estado canônico Stripe.
//   • Resposta rápida (<5s): processado/ignorado = 200; assinatura ruim = 400;
//     falha real = 500 (Stripe re-tenta — a dedupe + re-fetch absorvem).
//   • Nunca devolver detalhe de erro ao chamador.
//
// Eventos processados:
//   checkout.session.completed
//   customer.subscription.created | updated | deleted
//   invoice.paid | invoice.payment_failed

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';

const STRIPE_API_VERSION = '2024-12-18.acacia';

// O webhook não precisa de CORS (Stripe chama server-to-server).
const minimalHeaders = { 'Content-Type': 'application/json' };

function resp(body: string, status = 200): Response {
  return new Response(body, { status, headers: minimalHeaders });
}

// Mapeia status da Stripe → vocabulário canônico de public.subscriptions.
// Apenas active/trialing concedem acesso (grace não existe na Stripe).
function mapearStatus(s: string): string {
  switch (s) {
    case 'trialing':           return 'trialing';
    case 'active':             return 'active';
    case 'past_due':           return 'past_due';
    case 'canceled':           return 'canceled';
    case 'incomplete':         return 'incomplete';
    case 'incomplete_expired': return 'incomplete';
    case 'unpaid':             return 'past_due';  // em dunning: não concede
    case 'paused':             return 'past_due';
    default:                   return 'canceled';
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return resp('"method_not_allowed"', 405);

  try {
    const serviceRoleKey      = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const supabaseUrl         = Deno.env.get('SUPABASE_URL');
    const stripeSecret        = Deno.env.get('STRIPE_SECRET_KEY');
    const stripeWebhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');

    if (!serviceRoleKey || !supabaseUrl || !stripeSecret || !stripeWebhookSecret) {
      console.error('Config ausente: SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL / STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET');
      return resp('"erro_interno"', 500);
    }

    // ── 1. Ler corpo BRUTO + verificar assinatura ──────────────────────────
    // req.text() preserva o payload exato pra constructEventAsync conferir o
    // HMAC. Qualquer parse/serialize quebraria a verificação.
    const rawBody   = await req.text();
    const sigHeader = req.headers.get('stripe-signature');
    if (!sigHeader) {
      console.error('Webhook sem header stripe-signature');
      return resp('"assinatura_invalida"', 400);
    }

    const stripe = new Stripe(stripeSecret, {
      apiVersion: STRIPE_API_VERSION,
      httpClient: Stripe.createFetchHttpClient(),
    });

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        rawBody,
        sigHeader,
        stripeWebhookSecret,
        undefined,
        Stripe.createSubtleCryptoProvider(),
      );
    } catch (e) {
      // Assinatura ruim, secret errado, payload adulterado: 400 e ZERO toque
      // no banco. Não logar o secret.
      console.error('constructEventAsync falhou:', (e as Error).message);
      return resp('"assinatura_invalida"', 400);
    }

    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // ── 2. Idempotência (insert-first): registra o evento ANTES de processar ─
    // ON CONFLICT DO NOTHING + .select(): se voltou vazio, o evento já foi
    // processado → 200 sem reprocessar. A canonicidade (re-fetch) + o fato de
    // a Stripe emitir vários eventos por mudança garantem convergência mesmo
    // que um processamento isolado falhe após esta marcação.
    const { data: inserido, error: dedupeErr } = await supabaseService
      .from('billing_events')
      .upsert(
        { provider: 'stripe', event_id: event.id, type: event.type },
        { onConflict: 'provider,event_id', ignoreDuplicates: true },
      )
      .select();
    if (dedupeErr) {
      console.error('Falha ao gravar billing_events:', dedupeErr.message);
      return resp('"erro_interno"', 500);
    }
    if (!inserido || inserido.length === 0) {
      console.log('Evento já processado (idempotente):', event.id, event.type);
      return resp('"ok"', 200);
    }

    // ── 3. Filtrar tipos relevantes ────────────────────────────────────────
    const tiposRelevantes = new Set([
      'checkout.session.completed',
      'customer.subscription.created',
      'customer.subscription.updated',
      'customer.subscription.deleted',
      'invoice.paid',
      'invoice.payment_failed',
    ]);
    if (!tiposRelevantes.has(event.type)) {
      return resp('"ok"', 200);
    }

    // ── 4. Resolver customer_id e (se houver) subscription_id do evento ────
    // NÃO confiamos nos demais campos — só nos dois identificadores. O estado
    // real vem do re-fetch logo abaixo.
    let customerId: string | null = null;
    let subscriptionId: string | null = null;

    const obj = event.data.object as Record<string, unknown>;
    switch (event.type) {
      case 'checkout.session.completed': {
        customerId     = (obj.customer as string | null) ?? null;
        subscriptionId = (obj.subscription as string | null) ?? null;
        break;
      }
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        customerId     = (obj.customer as string | null) ?? null;
        subscriptionId = (obj.id as string | null) ?? null;
        break;
      }
      case 'invoice.paid':
      case 'invoice.payment_failed': {
        customerId     = (obj.customer as string | null) ?? null;
        subscriptionId = (obj.subscription as string | null) ?? null;
        break;
      }
    }

    if (!customerId) {
      console.error('Evento sem customer:', event.id, event.type);
      return resp('"ok"', 200);
    }

    // ── 5. Re-fetch canônico: o estado real está na Stripe ─────────────────
    // Com subscription_id, vamos direto nele; senão, listamos a sub mais
    // recente do customer (cobre fora-de-ordem em que `updated` chega antes de
    // `created` e ainda não temos id em mãos).
    let sub: Stripe.Subscription | null = null;
    try {
      if (subscriptionId) {
        sub = await stripe.subscriptions.retrieve(subscriptionId);
      } else {
        const list = await stripe.subscriptions.list({
          customer: customerId,
          status: 'all',
          limit: 1,
        });
        sub = list.data[0] ?? null;
      }
    } catch (e) {
      console.error('Re-fetch da subscription falhou:', (e as Error).message);
      return resp('"erro_interno"', 500);
    }

    if (!sub) {
      // Sem subscription resolvível (ex.: customer recém-criado sem sub).
      // Nada a convergir; evento já está dedupe-ado.
      console.log('Sem subscription p/ customer', customerId, '— nada a aplicar.');
      return resp('"ok"', 200);
    }

    // ── 6. Resolver supabase_user_id (ancoragem em cascata) ────────────────
    // 1º subscription.metadata (gravado pela rota /api/checkout da LP),
    // 2º customer.metadata, 3º lookup em subscriptions por stripe_customer_id.
    let supabaseUserId: string | null = null;
    const subMeta = (sub.metadata ?? {})['supabase_user_id'];
    if (typeof subMeta === 'string' && subMeta.length > 0) {
      supabaseUserId = subMeta;
    }

    if (!supabaseUserId) {
      try {
        const customer = await stripe.customers.retrieve(customerId);
        if (customer && !('deleted' in customer && customer.deleted)) {
          const md = (customer as Stripe.Customer).metadata ?? {};
          const fromMeta = md['supabase_user_id'];
          if (typeof fromMeta === 'string' && fromMeta.length > 0) {
            supabaseUserId = fromMeta;
          }
        }
      } catch (e) {
        console.error('customers.retrieve falhou:', (e as Error).message);
      }
    }

    if (!supabaseUserId) {
      const { data: row } = await supabaseService
        .from('subscriptions')
        .select('user_id')
        .eq('stripe_customer_id', customerId)
        .maybeSingle();
      supabaseUserId = (row?.user_id as string | null) ?? null;
    }

    if (!supabaseUserId) {
      console.error('Não foi possível resolver supabase_user_id p/ customer', customerId);
      return resp('"ok"', 200);
    }

    // ── 7. Persistência canônica via RPC ───────────────────────────────────
    const priceId  = sub.items?.data?.[0]?.price?.id ?? null;
    const periodEnd =
      sub.current_period_end != null
        ? new Date(sub.current_period_end * 1000).toISOString()
        : null;

    const { error: rpcErr } = await supabaseService.rpc('aplicar_estado_assinatura', {
      p_user_id:              supabaseUserId,
      p_provider:             'stripe',
      p_status:               mapearStatus(sub.status),
      p_product_id:           priceId,
      p_current_period_end:   periodEnd,
      p_cancel_at_period_end: !!sub.cancel_at_period_end,
      p_stripe_customer_id:   customerId,
      p_provider_sub_id:      sub.id,
    });

    if (rpcErr) {
      console.error('aplicar_estado_assinatura falhou:', rpcErr.message);
      return resp('"erro_interno"', 500);
    }

    return resp('"ok"', 200);
  } catch (e) {
    console.error('stripe-webhook erro interno:', (e as Error).message);
    return resp('"erro_interno"', 500);
  }
});
