// Supabase Edge Function — Stripe Webhook
// Recebe eventos da Stripe, verifica assinatura, deduplica via billing_events
// (provider='stripe') e mantém public.subscriptions canônica RE-BUSCANDO o
// estado real na Stripe (tolerante a fora-de-ordem) e gravando via a RPC
// canônica aplicar_estado_assinatura (mesma porta dos webhooks Apple/Google).
// Deploy OBRIGATÓRIO com --no-verify-jwt: a Stripe não envia JWT do Supabase;
// a segurança é a assinatura do payload.
//
// Princípios (ver docs/00-visao-arquitetura.md §5 e docs/03-stripe-billing.md):
//   • Idempotência: SELECT em stripe_events antes; se já visto, 200 sem
//     reprocessar. Gravação acontece SÓ APÓS o UPSERT bem-sucedido — assim,
//     uma falha de processamento NÃO marca o evento como visto, e a Stripe
//     reentrega. (Inversão proposital: prefere reprocesso duplo ao silêncio.)
//   • Canonicidade: NÃO confiar nos campos do evento. Re-buscar a
//     subscription na Stripe e fazer UPSERT atômico (sem read-modify-write).
//     UPSERT em si é idempotente — reprocesso duplo é seguro.
//   • Resposta rápida (<5s): processado/ignorado = 200; assinatura ruim = 400;
//     falha real = 500 (a Stripe re-tenta).
//   • Nunca devolver detalhe de erro ao chamador.
//
// Eventos processados:
//   checkout.session.completed
//   customer.subscription.created | updated | deleted
//   invoice.payment_failed
// Demais: 200 'ok' silencioso (e marcado em stripe_events pra não revisitar).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';

const STRIPE_API_VERSION = '2024-12-18.acacia';

// O webhook não precisa de CORS (Stripe chama server-to-server).
const minimalHeaders = { 'Content-Type': 'application/json' };

function resp(body: string, status = 200): Response {
  return new Response(body, { status, headers: minimalHeaders });
}

// Marca o evento como visto no ledger unificado billing_events
// (provider='stripe'). Falha silenciosa: na pior das hipóteses a Stripe
// re-entrega e o UPSERT idempotente da RPC absorve.
async function marcarVisto(
  supabaseService: ReturnType<typeof createClient>,
  eventId: string,
  type: string,
): Promise<void> {
  const { error } = await supabaseService
    .from('billing_events')
    .insert({ provider: 'stripe', event_id: eventId, type });
  if (error && (error as { code?: string }).code !== '23505') {
    console.error('Falha ao gravar billing_events:', error.message);
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
    // req.text() preserva o payload exato pra constructEventAsync conferir
    // o HMAC. Qualquer parse/serialize quebraria a verificação.
    const rawBody  = await req.text();
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

    // ── 2. Idempotência (pré-check): evento já visto? ──────────────────────
    // SELECT por PK é O(1). Se sim, retorna 200 sem reprocessar.
    // Race entre dois workers paralelos no mesmo event.id: o UPSERT
    // idempotente em subscriptions absorve sem dano (re-fetch idêntico).
    const { data: jaVisto } = await supabaseService
      .from('billing_events')
      .select('event_id')
      .eq('provider', 'stripe')
      .eq('event_id', event.id)
      .maybeSingle();
    if (jaVisto) {
      console.log('Evento já processado (idempotente):', event.id, event.type);
      return resp('"ok"', 200);
    }

    // ── 3. Filtrar tipos relevantes ────────────────────────────────────────
    const tiposRelevantes = new Set([
      'checkout.session.completed',
      'customer.subscription.created',
      'customer.subscription.updated',
      'customer.subscription.deleted',
      'invoice.payment_failed',
    ]);
    if (!tiposRelevantes.has(event.type)) {
      await marcarVisto(supabaseService, event.id, event.type);
      return resp('"ok"', 200);
    }

    // ── 4. Resolver customer_id e (se houver) subscription_id do evento ────
    // NÃO confiamos nos demais campos — só nos dois identificadores. O
    // estado real vem do re-fetch logo abaixo.
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
      case 'invoice.payment_failed': {
        customerId     = (obj.customer as string | null) ?? null;
        subscriptionId = (obj.subscription as string | null) ?? null;
        break;
      }
    }

    if (!customerId) {
      console.error('Evento sem customer:', event.id, event.type);
      await marcarVisto(supabaseService, event.id, event.type);
      return resp('"ok"', 200);
    }

    // ── 5. Resolver identidade: user_id ancorado OU e-mail (checkout-first) ─
    // Preferir user_id já conhecido: customer.metadata.supabase_user_id
    // (carimbado quando o checkout parte do app logado) → senão lookup em
    // subscriptions por stripe_customer_id. Se nenhum, cair pro e-mail do
    // customer (coletado pelo Stripe Checkout): o passo 7 concede por e-mail
    // se a conta existe, ou guarda pendente se ainda não existe.
    let supabaseUserId: string | null = null;
    let customerEmail: string | null = null;
    try {
      const customer = await stripe.customers.retrieve(customerId);
      if (customer && !('deleted' in customer && customer.deleted)) {
        const c = customer as Stripe.Customer;
        const fromMeta = (c.metadata ?? {})['supabase_user_id'];
        if (typeof fromMeta === 'string' && fromMeta.length > 0) {
          supabaseUserId = fromMeta;
        }
        if (typeof c.email === 'string' && c.email.length > 0) {
          customerEmail = c.email;
        }
      }
    } catch (e) {
      console.error('customers.retrieve falhou:', (e as Error).message);
    }

    if (!supabaseUserId) {
      const { data: row } = await supabaseService
        .from('subscriptions')
        .select('user_id')
        .eq('stripe_customer_id', customerId)
        .maybeSingle();
      supabaseUserId = (row?.user_id as string | null) ?? null;
    }

    // Sem user_id E sem e-mail não há como vincular: marca visto e abandona.
    if (!supabaseUserId && !customerEmail) {
      console.error('Sem user_id e sem e-mail p/ customer', customerId);
      await marcarVisto(supabaseService, event.id, event.type);
      return resp('"ok"', 200);
    }

    // ── 6. Re-fetch canônico: o estado real está na Stripe ─────────────────
    // Se temos um subscription_id, vamos direto nele (o mais recente do
    // ponto de vista do evento). Senão, listamos a sub mais recente do
    // customer (cobre fora-de-ordem em que `updated` chega antes de
    // `created` e ainda não temos id em mãos).
    let sub: Stripe.Subscription | null = null;
    try {
      if (subscriptionId) {
        sub = await stripe.subscriptions.retrieve(subscriptionId);
      } else {
        const list = await stripe.subscriptions.list({
          customer: customerId,
          status: 'all',
          limit: 3,
        });
        if (list.data.length > 0) {
          sub = list.data
            .slice()
            .sort((a, b) => (b.created ?? 0) - (a.created ?? 0))[0];
        }
      }
    } catch (e) {
      console.error('Re-fetch da subscription falhou:', (e as Error).message);
      // Não marca visto → próxima retry da Stripe reprocessa.
      return resp('"erro_interno"', 500);
    }

    // ── 7. Escrita canônica do entitlement ─────────────────────────────────
    // Toda escrita passa por uma RPC (única porta, com a regra de convergência
    // multiplataforma). Só escreve se há `sub` (estado real). Dois caminhos:
    //   • user_id ancorado → aplicar_estado_assinatura (direto pelo id) e fixa
    //     o stripe_customer_id pra resolução futura.
    //   • sem user_id, com e-mail (checkout-first) → aplicar_estado_por_email:
    //     concede se a conta existe, senão guarda pending_entitlements (o
    //     trigger de signup reconcilia). A própria RPC fixa o customer_id.
    // Sem `sub` (ex.: payment_failed sem subscription resolvível): no caminho
    // ancorado, só garante o stripe_customer_id; no caminho e-mail, nada a fazer.
    if (sub) {
      const priceId  = sub.items?.data?.[0]?.price?.id ?? null;
      const periodEnd =
        sub.current_period_end != null
          ? new Date(sub.current_period_end * 1000).toISOString()
          : null;

      if (supabaseUserId) {
        const { error: rpcErr } = await supabaseService.rpc(
          'aplicar_estado_assinatura',
          {
            p_user_id:              supabaseUserId,
            p_provider:             'stripe',
            p_status:               sub.status,
            p_product_id:           priceId,
            p_current_period_end:   periodEnd,
            p_cancel_at_period_end: !!sub.cancel_at_period_end,
            p_provider_sub_id:      sub.id,
          },
        );
        if (rpcErr) {
          console.error('RPC aplicar_estado_assinatura falhou:', rpcErr.message);
          // Não marca visto → próxima retry reprocessa (RPC é idempotente).
          return resp('"erro_interno"', 500);
        }
      } else {
        const { error: emailErr } = await supabaseService.rpc(
          'aplicar_estado_por_email',
          {
            p_email:                customerEmail,
            p_provider:             'stripe',
            p_status:               sub.status,
            p_product_id:           priceId,
            p_current_period_end:   periodEnd,
            p_cancel_at_period_end: !!sub.cancel_at_period_end,
            p_provider_sub_id:      sub.id,
            p_stripe_customer_id:   customerId,
          },
        );
        if (emailErr) {
          console.error('RPC aplicar_estado_por_email falhou:', emailErr.message);
          return resp('"erro_interno"', 500);
        }
      }
    }

    // stripe_customer_id auxiliar (Stripe-only) p/ resolver customer→user no
    // passo 5 de eventos futuros. Só no caminho ancorado: no caminho e-mail a
    // própria RPC já o fixou (ou guardou no pending). Upsert parcial: no
    // conflito atualiza só o customer; sem linha (payment_failed como 1º
    // evento) cria uma mínima (status default 'none').
    if (supabaseUserId) {
      const { error: custErr } = await supabaseService
        .from('subscriptions')
        .upsert(
          {
            user_id: supabaseUserId,
            stripe_customer_id: customerId,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'user_id' },
        );
      if (custErr) {
        console.error('Upsert stripe_customer_id falhou:', custErr.message);
        return resp('"erro_interno"', 500);
      }
    }

    // ── 8. Marca visto SÓ APÓS sucesso ─────────────────────────────────────
    // Inversão proposital: se algo falhar antes daqui, a Stripe re-entrega
    // e o UPSERT idempotente refaz o estado sem dano. Marcar antes correria
    // o risco de "evento visto mas estado não persistido".
    await marcarVisto(supabaseService, event.id, event.type);

    return resp('"ok"', 200);
  } catch (e) {
    console.error('stripe-webhook erro interno:', (e as Error).message);
    return resp('"erro_interno"', 500);
  }
});
