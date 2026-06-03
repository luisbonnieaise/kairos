// Supabase Edge Function — Google Play Real-Time Developer Notifications (RTDN)
// Recebe o push do Pub/Sub, VERIFICA o token OIDC (assinatura Google + audience),
// deduplica via billing_events (provider='google') e converge
// public.subscriptions RE-BUSCANDO o estado em purchases.subscriptionsv2.get.
// Deploy OBRIGATÓRIO com --no-verify-jwt: a segurança é o OIDC do push, não o
// JWT do Supabase.
//
// Princípios (docs/00-visao-arquitetura.md §5 e docs/07-billing-multiplataforma.md):
//   • Push autenticado ANTES de tocar o banco (audience exata).
//   • Idempotência: billing_events (provider='google', event_id=messageId).
//   • Canonicidade: re-buscar via subscriptionsv2.get e aplicar via RPC.
//   • Compra nova é reconhecida (acknowledge) p/ não ser reembolsada em ~3 dias.
//   • Nunca devolver detalhe de erro ao chamador.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import {
  acknowledgeSeNecessario,
  estadoCanonicoGoogle,
  verificarPushOidc,
} from '../_shared/google.ts';

const headers = { 'Content-Type': 'application/json' };
function resp(body: string, status = 200): Response {
  return new Response(body, { status, headers });
}

type DeveloperNotification = {
  subscriptionNotification?: { purchaseToken?: string; subscriptionId?: string; notificationType?: number };
  voidedPurchaseNotification?: { purchaseToken?: string; orderId?: string };
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

    // ── 1. Autenticar o push do Pub/Sub (OIDC) ─────────────────────────────
    try {
      await verificarPushOidc(req.headers.get('Authorization'));
    } catch (e) {
      console.error('Push OIDC inválido:', (e as Error).message);
      return resp('"nao_autorizado"', 401);
    }

    let envelope: { message?: { data?: string; messageId?: string } };
    try { envelope = await req.json(); } catch { return resp('"corpo_invalido"', 400); }
    const message = envelope.message;
    if (!message?.data || !message.messageId) return resp('"corpo_invalido"', 400);

    // ── 2. Decodificar a DeveloperNotification ─────────────────────────────
    let notif: DeveloperNotification;
    try {
      notif = JSON.parse(atob(message.data));
    } catch {
      return resp('"corpo_invalido"', 400);
    }
    const sub = notif.subscriptionNotification;
    const voided = notif.voidedPurchaseNotification;
    const purchaseToken = sub?.purchaseToken ?? voided?.purchaseToken;
    if (!purchaseToken) {
      // Notificação de teste ou tipo sem token (ex.: OneTimeProduct) — ignora.
      return resp('"ok"', 200);
    }
    const tipo = sub?.notificationType != null ? String(sub.notificationType) : (voided ? 'voided' : 'unknown');

    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // ── 3. Idempotência (insert-first) ─────────────────────────────────────
    const { data: inserido, error: dedupeErr } = await supabaseService
      .from('billing_events')
      .upsert(
        { provider: 'google', event_id: message.messageId, type: tipo },
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

    // ── 4. Canonicidade: re-buscar o estado real ───────────────────────────
    let estado;
    try {
      estado = await estadoCanonicoGoogle(purchaseToken);
    } catch (e) {
      console.error('Re-fetch Google falhou:', (e as Error).message);
      return resp('"erro_interno"', 500);  // Pub/Sub re-tenta; dedupe absorve
    }
    if (!estado) {
      console.log('Sem estado p/ purchaseToken');
      return resp('"ok"', 200);
    }

    // Reembolso (voided) sobrepõe: cancela o acesso.
    const status = voided ? 'canceled' : estado.status;

    // ── 5. Identidade ──────────────────────────────────────────────────────
    let userId = estado.obfuscatedAccountId;
    if (!userId) {
      const { data: row } = await supabaseService
        .from('subscriptions')
        .select('user_id')
        .eq('provider', 'google')
        .eq('provider_sub_id', purchaseToken)
        .maybeSingle();
      userId = (row?.user_id as string | null) ?? null;
    }
    if (!userId) {
      console.error('Sem user_id p/ assinatura Google');
      return resp('"ok"', 200);
    }

    // ── 6. Persistência canônica via RPC ───────────────────────────────────
    const { error: rpcErr } = await supabaseService.rpc('aplicar_estado_assinatura', {
      p_user_id:              userId,
      p_provider:             'google',
      p_status:               status,
      p_product_id:           estado.productId,
      p_current_period_end:   estado.currentPeriodEnd,
      p_cancel_at_period_end: estado.cancelAtPeriodEnd,
      p_stripe_customer_id:   null,
      p_provider_sub_id:      purchaseToken,
    });
    if (rpcErr) {
      console.error('aplicar_estado_assinatura falhou:', rpcErr.message);
      return resp('"erro_interno"', 500);
    }

    // ── 7. Acknowledge da compra nova (evita reembolso automático) ─────────
    if (!estado.acknowledged && !voided && estado.productIdParaAck) {
      try {
        await acknowledgeSeNecessario(purchaseToken, estado.productIdParaAck);
      } catch (e) {
        // Não falha o webhook por isso; loga p/ investigação.
        console.error('acknowledge falhou:', (e as Error).message);
      }
    }

    return resp('"ok"', 200);
  } catch (e) {
    console.error('google-webhook erro interno:', (e as Error).message);
    return resp('"erro_interno"', 500);
  }
});
