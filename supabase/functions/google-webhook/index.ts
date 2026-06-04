// Supabase Edge Function — google-webhook
// Recebe Real-time Developer Notifications (RTDN) do Google Play via Pub/Sub
// push, RE-BUSCA o estado real (subscriptionsv2.get) e converge o entitlement
// via a RPC canônica. Deploy OBRIGATÓRIO com --no-verify-jwt.
//
// A confiança vem do re-fetch autenticado na Android Publisher API — o corpo
// do Pub/Sub só carrega o purchaseToken a consultar. Idempotência por messageId.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import { aplicarEstado, eventoJaVisto, marcarEvento } from '../_shared/billing.ts';
import { decodificarRtdn, estadoGoogle, lerGoogleEnv } from '../_shared/google.ts';

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

    // Decodifica o envelope Pub/Sub. Mensagens não-assinatura (test/voided) =>
    // 200 sem processar (e o Pub/Sub não re-entrega).
    let notif;
    try {
      const corpo = await req.json();
      notif = decodificarRtdn(corpo);
    } catch {
      return resp('"corpo_invalido"', 400);
    }
    if (!notif) return resp('"ok"', 200);

    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Idempotência por messageId do Pub/Sub.
    if (await eventoJaVisto(supabaseService, 'google', notif.messageId)) {
      return resp('"ok"', 200);
    }

    // Re-fetch canônico no Google.
    let estado;
    try {
      estado = await estadoGoogle(lerGoogleEnv(), notif.purchaseToken);
    } catch (e) {
      console.error('estadoGoogle falhou:', (e as Error).message);
      // Não marca visto → Pub/Sub re-entrega.
      return resp('"erro_interno"', 500);
    }

    if (!estado.userId) {
      console.error('Compra Google sem obfuscatedExternalAccountId; ignorada');
      await marcarEvento(supabaseService, 'google', notif.messageId, String(notif.notificationType));
      return resp('"ok"', 200);
    }

    try {
      await aplicarEstado(supabaseService, {
        userId: estado.userId,
        provider: 'google',
        status: estado.status,
        productId: estado.productId,
        currentPeriodEnd: estado.currentPeriodEnd,
        cancelAtPeriodEnd: estado.cancelAtPeriodEnd,
        providerSubId: estado.purchaseToken,
      });
    } catch (e) {
      console.error('aplicarEstado (google) falhou:', (e as Error).message);
      return resp('"erro_interno"', 500);
    }

    await marcarEvento(supabaseService, 'google', notif.messageId, String(notif.notificationType));
    return resp('"ok"', 200);
  } catch (e) {
    console.error('google-webhook erro interno:', (e as Error).message);
    return resp('"erro_interno"', 500);
  }
});
