// Supabase Edge Function — apple-webhook
// Recebe App Store Server Notifications V2, VERIFICA o JWS (cadeia x5c até o
// Apple Root CA - G3), deduplica por notificationUUID e converge o entitlement
// via a RPC canônica. Deploy OBRIGATÓRIO com --no-verify-jwt: a Apple não envia
// JWT do Supabase; a segurança é a assinatura do payload.
//
// Princípios (iguais ao stripe-webhook): re-fetch canônico no provider,
// idempotência por evento, resposta rápida, nunca confiar no corpo cru.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import { aplicarEstado, eventoJaVisto, marcarEvento } from '../_shared/billing.ts';
import { lerAppleEnv, verificarNotificacao } from '../_shared/apple.ts';

const headers = { 'Content-Type': 'application/json' };
const resp = (body: string, status = 200) => new Response(body, { status, headers });

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return resp('"method_not_allowed"', 405);

  try {
    const supabaseUrl    = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      console.error('Config ausente: SUPABASE_URL/SERVICE_ROLE_KEY');
      return resp('"erro_interno"', 500);
    }

    // Corpo: { signedPayload }
    let signedPayload: string;
    try {
      const corpo = await req.json() as { signedPayload?: unknown };
      if (typeof corpo.signedPayload !== 'string') throw new Error('signedPayload ausente');
      signedPayload = corpo.signedPayload;
    } catch {
      return resp('"corpo_invalido"', 400);
    }

    // Verifica assinatura + cadeia e re-busca o estado canônico. Qualquer
    // falha de verificação = 400, ZERO toque no banco.
    let notif;
    try {
      notif = await verificarNotificacao(lerAppleEnv(), signedPayload);
    } catch (e) {
      console.error('Verificação da notificação Apple falhou:', (e as Error).message);
      return resp('"assinatura_invalida"', 400);
    }

    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Idempotência por notificationUUID.
    if (await eventoJaVisto(supabaseService, 'apple', notif.notificationUUID)) {
      return resp('"ok"', 200);
    }

    // Sem appAccountToken não há como ancorar no usuário — registra e ignora.
    if (!notif.estado.userId) {
      console.error('Notificação Apple sem appAccountToken; ignorada', notif.notificationType);
      await marcarEvento(supabaseService, 'apple', notif.notificationUUID, notif.notificationType);
      return resp('"ok"', 200);
    }

    try {
      await aplicarEstado(supabaseService, {
        userId: notif.estado.userId,
        provider: 'apple',
        status: notif.estado.status,
        productId: notif.estado.productId,
        currentPeriodEnd: notif.estado.currentPeriodEnd,
        cancelAtPeriodEnd: notif.estado.cancelAtPeriodEnd,
        providerSubId: notif.estado.originalTransactionId,
      });
    } catch (e) {
      console.error('aplicarEstado (apple) falhou:', (e as Error).message);
      // Não marca visto → Apple re-entrega (RPC idempotente).
      return resp('"erro_interno"', 500);
    }

    // Marca visto SÓ APÓS sucesso (mesma inversão proposital do stripe-webhook).
    await marcarEvento(supabaseService, 'apple', notif.notificationUUID, notif.notificationType);
    return resp('"ok"', 200);
  } catch (e) {
    console.error('apple-webhook erro interno:', (e as Error).message);
    return resp('"erro_interno"', 500);
  }
});
