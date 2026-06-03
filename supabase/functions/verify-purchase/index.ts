// Supabase Edge Function — verify-purchase
// Desbloqueio IMEDIATO de Premium logo após uma compra IAP, sem esperar a
// notificação assíncrona (Apple ASSN / Google RTDN), que pode atrasar. Os
// webhooks apple-webhook/google-webhook continuam sendo a fonte de verdade
// para renovações/cancelamentos. Deploy NORMAL (verify-jwt): exige o JWT do
// usuário — só o dono da sessão pode desbloquear a própria conta.
//
// Contrato de erro com o client:
//   { error: 'nao_autorizado' }   401 — sem Authorization
//   { error: 'sessao_invalida' }  401 — JWT inválido
//   { error: 'corpo_invalido' }   400 — provider/token ausente ou inválido
//   { error: 'compra_alheia' }    403 — a compra não pertence a este usuário
//   { error: 'verificacao_erro' } 502 — falha ao re-buscar no provider
//   { error: 'erro_interno' }     500 — config ausente ou exceção

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import { estadoCanonicoApple } from '../_shared/apple.ts';
import { acknowledgeSeNecessario, estadoCanonicoGoogle } from '../_shared/google.ts';

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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const supabaseUrl     = Deno.env.get('SUPABASE_URL')!;
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!serviceRoleKey) {
      console.error('Config ausente: SUPABASE_SERVICE_ROLE_KEY');
      return jsonResp({ error: 'erro_interno' }, 500);
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonResp({ error: 'nao_autorizado' }, 401);

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) return jsonResp({ error: 'sessao_invalida' }, 401);

    let body: { provider?: string; token?: string };
    try { body = await req.json(); } catch { return jsonResp({ error: 'corpo_invalido' }, 400); }
    const provider = body.provider;
    const token = body.token;
    if ((provider !== 'apple' && provider !== 'google') || typeof token !== 'string' || token.length === 0) {
      return jsonResp({ error: 'corpo_invalido' }, 400);
    }

    // ── Re-buscar o estado canônico no provider + validar pertencimento ────
    let status: string;
    let productId: string | null;
    let currentPeriodEnd: string | null;
    let cancelAtPeriodEnd: boolean;
    let providerSubId: string;
    let donoId: string | null;

    try {
      if (provider === 'apple') {
        const estado = await estadoCanonicoApple(token);
        if (!estado) return jsonResp({ error: 'verificacao_erro' }, 502);
        status = estado.status;
        productId = estado.productId;
        currentPeriodEnd = estado.currentPeriodEnd;
        cancelAtPeriodEnd = estado.cancelAtPeriodEnd;
        providerSubId = estado.providerSubId;
        donoId = estado.appAccountToken;
      } else {
        const estado = await estadoCanonicoGoogle(token);
        if (!estado) return jsonResp({ error: 'verificacao_erro' }, 502);
        status = estado.status;
        productId = estado.productId;
        currentPeriodEnd = estado.currentPeriodEnd;
        cancelAtPeriodEnd = estado.cancelAtPeriodEnd;
        providerSubId = token;
        donoId = estado.obfuscatedAccountId;
        // Acknowledge imediato (evita reembolso automático em ~3 dias).
        if (!estado.acknowledged && estado.productIdParaAck) {
          try { await acknowledgeSeNecessario(token, estado.productIdParaAck); }
          catch (e) { console.error('acknowledge falhou:', (e as Error).message); }
        }
      }
    } catch (e) {
      console.error('Re-fetch no provider falhou:', (e as Error).message);
      return jsonResp({ error: 'verificacao_erro' }, 502);
    }

    // A compra DEVE pertencer a este usuário (appAccountToken /
    // obfuscatedExternalAccountId == user.id). Sem isso, 403 e nada gravado.
    if (donoId !== user.id) {
      console.error('Compra não pertence ao usuário', { provider });
      return jsonResp({ error: 'compra_alheia' }, 403);
    }

    // ── Persistência canônica via RPC (mesma lógica dos webhooks) ──────────
    const { error: rpcErr } = await supabaseService.rpc('aplicar_estado_assinatura', {
      p_user_id:              user.id,
      p_provider:             provider,
      p_status:               status,
      p_product_id:           productId,
      p_current_period_end:   currentPeriodEnd,
      p_cancel_at_period_end: cancelAtPeriodEnd,
      p_stripe_customer_id:   null,
      p_provider_sub_id:      providerSubId,
    });
    if (rpcErr) {
      console.error('aplicar_estado_assinatura falhou:', rpcErr.message);
      return jsonResp({ error: 'erro_interno' }, 500);
    }

    const premium = ['active', 'trialing', 'grace'].includes(status)
      && currentPeriodEnd != null && new Date(currentPeriodEnd) > new Date();

    return jsonResp({ premium, current_period_end: currentPeriodEnd });
  } catch (e) {
    console.error('verify-purchase erro interno:', (e as Error).message);
    return jsonResp({ error: 'erro_interno' }, 500);
  }
});
