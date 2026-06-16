// Supabase Edge Function — restore-stripe
// "Já comprei na web": reconcilia a assinatura Stripe do usuário LOGADO pelo
// PRÓPRIO e-mail (do JWT). Cobre quem assinou na landing (checkout-first) e o
// stripe-webhook ainda não convergiu — ou um pending que não reconciliou no
// signup. Deploy NORMAL (verify-jwt): exige o JWT do usuário.
//
// Contrato:
//   POST {}   (sem corpo; a identidade vem do JWT)
//   200 { premium: boolean, current_period_end: string|null, encontrado: boolean }
//   401 sem/!JWT · 500 interno
//
// Segurança: usa SÓ o e-mail autenticado (user.email). NÃO há campo de e-mail
// livre — assim ninguém reivindica a assinatura de e-mail de terceiros. O caso
// raro de e-mail divergente (pagou com um, conta com outro) fica para suporte.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';
import { corsHeaders, json } from '../_shared/cors.ts';
import { aplicarEstado } from '../_shared/billing.ts';

const STRIPE_API_VERSION = '2024-12-18.acacia';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const supabaseUrl     = Deno.env.get('SUPABASE_URL');
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const stripeSecret    = Deno.env.get('STRIPE_SECRET_KEY');
    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey || !stripeSecret) {
      console.error('Config ausente: SUPABASE_URL/ANON_KEY/SERVICE_ROLE_KEY/STRIPE_SECRET_KEY');
      return json({ error: 'erro_interno' }, 500);
    }

    // ── Auth do usuário (JWT encaminhado pelo functions.invoke) ────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'nao_autorizado' }, 401);

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) return json({ error: 'sessao_invalida' }, 401);

    const email = (user.email ?? '').trim().toLowerCase();
    if (!email) {
      return json({ premium: false, current_period_end: null, encontrado: false }, 200);
    }

    // ── Stripe: melhor subscription CONCEDENTE para esse e-mail ────────────
    // Só consideramos status que concedem acesso (active|trialing) — assim o
    // restore nunca rebaixa nada; se não houver concedente, é "nada a restaurar".
    const stripe = new Stripe(stripeSecret, {
      apiVersion: STRIPE_API_VERSION,
      httpClient: Stripe.createFetchHttpClient(),
    });

    const customers = await stripe.customers.list({ email, limit: 10 });
    let melhor: Stripe.Subscription | null = null;
    let melhorCustomer: string | null = null;
    for (const c of customers.data) {
      const subs = await stripe.subscriptions.list({
        customer: c.id,
        status: 'all',
        limit: 10,
      });
      for (const s of subs.data) {
        if (s.status !== 'active' && s.status !== 'trialing') continue;
        if (!melhor || (s.created ?? 0) > (melhor.created ?? 0)) {
          melhor = s;
          melhorCustomer = c.id;
        }
      }
    }

    if (!melhor) {
      return json({ premium: false, current_period_end: null, encontrado: false }, 200);
    }

    // ── Escrita canônica via RPC + fixa stripe_customer_id ─────────────────
    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const priceId = melhor.items?.data?.[0]?.price?.id ?? null;
    const periodEnd =
      melhor.current_period_end != null
        ? new Date(melhor.current_period_end * 1000).toISOString()
        : null;

    const resultado = await aplicarEstado(supabaseService, {
      userId: user.id,
      provider: 'stripe',
      status: melhor.status,
      productId: priceId,
      currentPeriodEnd: periodEnd,
      cancelAtPeriodEnd: !!melhor.cancel_at_period_end,
      providerSubId: melhor.id,
    });

    if (melhorCustomer) {
      await supabaseService
        .from('subscriptions')
        .upsert(
          {
            user_id: user.id,
            stripe_customer_id: melhorCustomer,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'user_id' },
        );
    }
    // Pendência residual desse e-mail já não é necessária (a conta existe).
    await supabaseService.from('pending_entitlements').delete().eq('email', email);

    return json({ ...resultado, encontrado: true }, 200);
  } catch (e) {
    console.error('restore-stripe erro interno:', (e as Error).message);
    return json({ error: 'erro_interno' }, 500);
  }
});
