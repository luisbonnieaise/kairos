// Supabase Edge Function — Stripe Checkout
// Cria/reutiliza um Stripe Customer para o usuário autenticado e abre uma
// sessão de Checkout (modo subscription) retornando a URL pra o app abrir
// no navegador externo. Nenhum dado de cartão passa por aqui — fica com a
// Stripe (PCI safe).
//
// Contrato de erro com o client:
//   { error: 'nao_autorizado' }   401 — sem Authorization header
//   { error: 'sessao_invalida' }  401 — JWT inválido / getUser falhou
//   { error: 'corpo_invalido' }   400 — success_url/cancel_url fora do esperado
//   { error: 'checkout_erro' }    502 — falha upstream da Stripe
//   { error: 'erro_interno' }     500 — config ausente ou exceção
// Detalhes técnicos só em console.error (logs server-side).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';

const STRIPE_API_VERSION = '2024-12-18.acacia';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResp(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Aceita só o deep link do app. Pra dev manual, dá pra adicionar prefixos
// extras via env APP_DEEP_LINK_EXTRA (separados por vírgula). Sem isso,
// qualquer URL externa é rejeitada — o vetor é um atacante passando uma
// success_url para o seu domínio e capturando o subscription_id na query.
function urlPermitida(u: string): boolean {
  if (typeof u !== 'string' || u.length === 0 || u.length > 2000) return false;
  const padroes = ['kairo://'];
  const extra = (Deno.env.get('APP_DEEP_LINK_EXTRA') ?? '').trim();
  if (extra.length > 0) {
    for (const p of extra.split(',')) {
      const t = p.trim();
      if (t.length > 0) padroes.push(t);
    }
  }
  return padroes.some((p) => u.startsWith(p));
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl       = Deno.env.get('SUPABASE_URL')!;
    const supabaseAnonKey   = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const stripeSecret      = Deno.env.get('STRIPE_SECRET_KEY');
    const stripePricePrem   = Deno.env.get('STRIPE_PRICE_PREMIUM');

    if (!serviceRoleKey || !stripeSecret || !stripePricePrem) {
      console.error('Config ausente: SUPABASE_SERVICE_ROLE_KEY / STRIPE_SECRET_KEY / STRIPE_PRICE_PREMIUM');
      return jsonResp({ error: 'erro_interno' }, 500);
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonResp({ error: 'nao_autorizado' }, 401);

    // Client autenticado por JWT — só para obter o user (RLS preservado).
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    // Service role — lê/grava subscriptions (sem policies de write).
    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) return jsonResp({ error: 'sessao_invalida' }, 401);

    let body: { success_url?: string; cancel_url?: string } = {};
    try { body = await req.json(); } catch { /* corpo vazio */ }

    if (!urlPermitida(body.success_url ?? '') || !urlPermitida(body.cancel_url ?? '')) {
      return jsonResp({ error: 'corpo_invalido' }, 400);
    }

    // Stripe SDK (Deno): fetch http client + apiVersion fixada.
    const stripe = new Stripe(stripeSecret, {
      apiVersion: STRIPE_API_VERSION,
      httpClient: Stripe.createFetchHttpClient(),
    });

    // ── 1. Resolver/criar Stripe Customer (idempotente por user_id) ──────────
    // Reuso pelo stripe_customer_id já gravado em subscriptions; se ausente,
    // cria um customer novo e UPSERT em subscriptions com status='none'.
    const { data: subRow } = await supabaseService
      .from('subscriptions')
      .select('stripe_customer_id')
      .eq('user_id', user.id)
      .maybeSingle();

    let customerId = subRow?.stripe_customer_id as string | null;
    if (!customerId) {
      const customer = await stripe.customers.create(
        {
          email: user.email ?? undefined,
          metadata: { supabase_user_id: user.id },
        },
        // Idempotência da criação do customer: se o usuário clicar 2x antes
        // de a primeira chamada gravar em subscriptions, a 2ª retorna o mesmo
        // customer da Stripe em vez de criar duplicado.
        { idempotencyKey: `customer:${user.id}` },
      );
      customerId = customer.id;

      const { error: upErr } = await supabaseService
        .from('subscriptions')
        .upsert({
          user_id: user.id,
          stripe_customer_id: customerId,
          status: 'none',
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id' });
      if (upErr) {
        console.error('Falha ao gravar subscriptions inicial:', upErr.message);
        return jsonResp({ error: 'erro_interno' }, 500);
      }
    }

    // ── 2. Criar Checkout Session ────────────────────────────────────────────
    // client_reference_id e subscription_data.metadata.supabase_user_id são
    // âncoras redundantes para o webhook resolver o usuário mesmo se um deles
    // sumir/atrasar. allow_promotion_codes deixa o usuário aplicar cupom.
    const session = await stripe.checkout.sessions.create(
      {
        mode: 'subscription',
        customer: customerId!,
        line_items: [{ price: stripePricePrem, quantity: 1 }],
        success_url: body.success_url!,
        cancel_url:  body.cancel_url!,
        client_reference_id: user.id,
        subscription_data: { metadata: { supabase_user_id: user.id } },
        allow_promotion_codes: true,
      },
      // Idempotência: duplo clique do usuário no botão "Assinar" → mesma URL
      // da primeira chamada (em vez de duas sessions na Stripe).
      { idempotencyKey: `checkout:${user.id}:${stripePricePrem}` },
    );

    if (!session.url) {
      console.error('Stripe devolveu session sem url:', session.id);
      return jsonResp({ error: 'checkout_erro' }, 502);
    }

    return jsonResp({ url: session.url });
  } catch (e) {
    console.error('stripe-checkout erro interno:', (e as Error).message);
    // Stripe SDK lança erros tipados; o cliente recebe sempre o código curto.
    return jsonResp({ error: 'checkout_erro' }, 502);
  }
});
