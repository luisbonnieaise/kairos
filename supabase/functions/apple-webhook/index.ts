// Supabase Edge Function — Apple App Store Server Notifications V2
// Recebe { signedPayload } (JWS), VERIFICA a assinatura e a cadeia x5c até a
// Apple Root CA - G3, deduplica via billing_events (provider='apple') e
// converge public.subscriptions RE-BUSCANDO o estado real na App Store Server
// API. Deploy OBRIGATÓRIO com --no-verify-jwt: a segurança é a assinatura JWS
// da Apple, não o JWT do Supabase.
//
// Princípios (docs/00-visao-arquitetura.md §5 e docs/07-billing-multiplataforma.md):
//   • Assinatura verificada ANTES de tocar o banco (cadeia pinada na raiz).
//   • Idempotência: billing_events (provider='apple', event_id=notificationUUID).
//   • Canonicidade: NÃO confiar só na notificação — re-buscar o estado e aplicar
//     via RPC (convergência multiplataforma: refund/expiração só rebaixa se a
//     Apple for o provider vigente).
//   • Nunca devolver detalhe de erro ao chamador.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import {
  decodificarJwsPayload,
  estadoCanonicoApple,
  verificarJws,
} from '../_shared/apple.ts';

const headers = { 'Content-Type': 'application/json' };
function resp(body: string, status = 200): Response {
  return new Response(body, { status, headers });
}

type Payload = {
  notificationUUID?: string;
  notificationType?: string;
  subtype?: string;
  data?: {
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
};

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return resp('"method_not_allowed"', 405);

  try {
    const supabaseUrl    = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      console.error('Config ausente: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY');
      return resp('"erro_interno"', 500);
    }

    let body: { signedPayload?: string };
    try { body = await req.json(); } catch { return resp('"corpo_invalido"', 400); }
    if (!body.signedPayload) return resp('"corpo_invalido"', 400);

    // ── 1. Verificar a assinatura JWS + cadeia x5c ─────────────────────────
    let payload: Payload;
    try {
      payload = await verificarJws<Payload>(body.signedPayload);
    } catch (e) {
      console.error('JWS inválido:', (e as Error).message);
      return resp('"assinatura_invalida"', 400);
    }

    const notificationUUID = payload.notificationUUID;
    if (!notificationUUID) {
      console.error('Notificação sem notificationUUID');
      return resp('"ok"', 200);
    }

    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // ── 2. Idempotência (insert-first) ─────────────────────────────────────
    const { data: inserido, error: dedupeErr } = await supabaseService
      .from('billing_events')
      .upsert(
        { provider: 'apple', event_id: notificationUUID, type: payload.notificationType ?? 'unknown' },
        { onConflict: 'provider,event_id', ignoreDuplicates: true },
      )
      .select();
    if (dedupeErr) {
      console.error('billing_events falhou:', dedupeErr.message);
      return resp('"erro_interno"', 500);
    }
    if (!inserido || inserido.length === 0) {
      return resp('"ok"', 200);
    }

    // ── 3. Identidade: originalTransactionId + appAccountToken da transação ─
    const txInfo = payload.data?.signedTransactionInfo;
    if (!txInfo) {
      console.log('Notificação sem signedTransactionInfo:', payload.notificationType);
      return resp('"ok"', 200);
    }
    const tx = decodificarJwsPayload<{
      originalTransactionId?: string;
      appAccountToken?: string;
    }>(txInfo);
    const originalTransactionId = tx.originalTransactionId;
    if (!originalTransactionId) {
      console.error('Transação sem originalTransactionId');
      return resp('"ok"', 200);
    }

    // ── 4. Canonicidade: re-buscar o estado real ───────────────────────────
    let estado;
    try {
      estado = await estadoCanonicoApple(originalTransactionId);
    } catch (e) {
      console.error('Re-fetch Apple falhou:', (e as Error).message);
      return resp('"erro_interno"', 500);  // Apple re-tenta; dedupe absorve
    }
    if (!estado) {
      console.log('Sem estado p/ originalTransactionId', originalTransactionId);
      return resp('"ok"', 200);
    }

    // user_id: appAccountToken (re-fetch > transação); fallback lookup por sub.
    let userId = estado.appAccountToken ?? tx.appAccountToken ?? null;
    if (!userId) {
      const { data: row } = await supabaseService
        .from('subscriptions')
        .select('user_id')
        .eq('provider', 'apple')
        .eq('provider_sub_id', originalTransactionId)
        .maybeSingle();
      userId = (row?.user_id as string | null) ?? null;
    }
    if (!userId) {
      console.error('Sem user_id p/ assinatura Apple', originalTransactionId);
      return resp('"ok"', 200);
    }

    // ── 5. Persistência canônica via RPC ───────────────────────────────────
    const { error: rpcErr } = await supabaseService.rpc('aplicar_estado_assinatura', {
      p_user_id:              userId,
      p_provider:             'apple',
      p_status:               estado.status,
      p_product_id:           estado.productId,
      p_current_period_end:   estado.currentPeriodEnd,
      p_cancel_at_period_end: estado.cancelAtPeriodEnd,
      p_stripe_customer_id:   null,
      p_provider_sub_id:      estado.providerSubId,
    });
    if (rpcErr) {
      console.error('aplicar_estado_assinatura falhou:', rpcErr.message);
      return resp('"erro_interno"', 500);
    }

    return resp('"ok"', 200);
  } catch (e) {
    console.error('apple-webhook erro interno:', (e as Error).message);
    return resp('"erro_interno"', 500);
  }
});
