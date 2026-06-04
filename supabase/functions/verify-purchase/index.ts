// Supabase Edge Function — verify-purchase
// Desbloqueio IMEDIATO do Premium logo após a compra IAP, sem esperar a
// notificação assíncrona (apple-webhook/google-webhook continuam sendo a fonte
// de verdade para renovação/cancelamento). Deploy NORMAL (verify-jwt): exige o
// JWT do usuário.
//
// Contrato:
//   POST { provider: 'apple'|'google', token }
//     token = originalTransactionId (Apple) | purchaseToken (Google)
//   200 { premium: boolean, current_period_end: string|null }
//   401 sem/!JWT · 400 corpo inválido · 403 compra de outro usuário · 500 interno
//
// Segurança: RE-BUSCA o estado no provider e EXIGE que a compra pertença a
// este usuário (appAccountToken / obfuscatedExternalAccountId == user.id).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import { corsHeaders, json } from '../_shared/cors.ts';
import { aplicarEstado } from '../_shared/billing.ts';
import { estadoApple, lerAppleEnv } from '../_shared/apple.ts';
import { estadoGoogle, lerGoogleEnv } from '../_shared/google.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const supabaseUrl     = Deno.env.get('SUPABASE_URL');
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      console.error('Config ausente: SUPABASE_URL/ANON_KEY/SERVICE_ROLE_KEY');
      return json({ error: 'erro_interno' }, 500);
    }

    // ── Autenticação do usuário ────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'nao_autorizado' }, 401);

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) return json({ error: 'sessao_invalida' }, 401);

    // ── Corpo ──────────────────────────────────────────────────────────────
    let corpo: { provider?: unknown; token?: unknown };
    try {
      corpo = await req.json();
    } catch {
      return json({ error: 'corpo_invalido' }, 400);
    }
    const provider = corpo.provider;
    const token = corpo.token;
    if ((provider !== 'apple' && provider !== 'google') ||
        typeof token !== 'string' || token.length === 0) {
      return json({ error: 'corpo_invalido' }, 400);
    }

    // ── Re-fetch canônico no provider ──────────────────────────────────────
    const estado = provider === 'apple'
      ? await estadoApple(lerAppleEnv(), token)
      : await estadoGoogle(lerGoogleEnv(), token);

    // ── Ownership: a compra tem de ser deste usuário ───────────────────────
    if (!estado.userId || estado.userId !== user.id) {
      console.error('verify-purchase: ownership mismatch', { provider, user: user.id });
      return json({ error: 'proibido' }, 403);
    }

    // ── Escrita canônica via RPC ───────────────────────────────────────────
    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const providerSubId = provider === 'apple'
      ? estado.originalTransactionId
      : estado.purchaseToken;

    const resultado = await aplicarEstado(supabaseService, {
      userId: user.id,
      provider,
      status: estado.status,
      productId: estado.productId,
      currentPeriodEnd: estado.currentPeriodEnd,
      cancelAtPeriodEnd: estado.cancelAtPeriodEnd,
      providerSubId,
    });

    return json(resultado, 200);
  } catch (e) {
    console.error('verify-purchase erro interno:', (e as Error).message);
    return json({ error: 'erro_interno' }, 500);
  }
});
