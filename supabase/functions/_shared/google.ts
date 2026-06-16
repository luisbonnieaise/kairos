// Integração Google Play (Android Publisher API + Real-time Developer
// Notifications via Pub/Sub). Reaproveitado por google-webhook e verify-purchase.
// Como na Apple: o entitlement vem do RE-FETCH no servidor do Google.
import * as jose from 'https://esm.sh/jose@5.9.6';
import type { CanonicalStatus } from './billing.ts';

interface ServiceAccount {
  client_email: string;
  private_key: string;
}

export interface GoogleEnv {
  serviceAccount: ServiceAccount;
  packageName: string; // com.thekairo.app
}

export function lerGoogleEnv(): GoogleEnv {
  const raw = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  const packageName = Deno.env.get('GOOGLE_PACKAGE_NAME');
  if (!raw || !packageName) {
    throw new Error('Config Google ausente: GOOGLE_SERVICE_ACCOUNT_JSON/GOOGLE_PACKAGE_NAME');
  }
  const sa = JSON.parse(raw) as ServiceAccount;
  if (!sa.client_email || !sa.private_key) {
    throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON inválido');
  }
  return { serviceAccount: sa, packageName };
}

// OAuth2 server-to-server via JWT do service account (RS256).
async function accessToken(sa: ServiceAccount): Promise<string> {
  const key = await jose.importPKCS8(sa.private_key, 'RS256');
  const assertion = await new jose.SignJWT({
    scope: 'https://www.googleapis.com/auth/androidpublisher',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(key);

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`OAuth Google ${res.status}`);
  const j = await res.json() as { access_token?: string };
  if (!j.access_token) throw new Error('OAuth Google sem access_token');
  return j.access_token;
}

// subscriptionState (subscriptionsv2) -> status canônico.
export function mapGoogleStatus(state: string): CanonicalStatus {
  switch (state) {
    case 'SUBSCRIPTION_STATE_ACTIVE':         return 'active';
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD': return 'grace';
    case 'SUBSCRIPTION_STATE_ON_HOLD':        return 'past_due';
    case 'SUBSCRIPTION_STATE_PAUSED':         return 'paused';
    case 'SUBSCRIPTION_STATE_CANCELED':       return 'active'; // acesso até expiry
    case 'SUBSCRIPTION_STATE_EXPIRED':        return 'expired';
    default:                                  return 'none';   // PENDING/desconhecido
  }
}

export interface EstadoGoogle {
  userId: string | null; // obfuscatedExternalAccountId
  status: CanonicalStatus;
  productId: string | null;
  currentPeriodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  purchaseToken: string;
}

interface SubscriptionV2 {
  subscriptionState: string;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  acknowledgementState?: string;
  lineItems?: Array<{ productId?: string; expiryTime?: string }>;
}

// Re-fetch canônico de uma assinatura pelo purchaseToken. Faz acknowledge se
// ainda pendente (exigência do Google p/ não estornar automaticamente).
export async function estadoGoogle(env: GoogleEnv, purchaseToken: string): Promise<EstadoGoogle> {
  const token = await accessToken(env.serviceAccount);
  const pkg = env.packageName;
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;

  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`subscriptionsv2.get ${res.status}`);
  const sub = await res.json() as SubscriptionV2;

  const ultimo = sub.lineItems?.[sub.lineItems.length - 1];

  // Acknowledge se pendente.
  if (sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING') {
    const ack =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}` +
      `/purchases/subscriptions/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
    // productId é exigido pelo endpoint de acknowledge (subscriptions v1).
    await fetch(ack, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    }).catch((e) => console.error('acknowledge Google falhou:', (e as Error).message));
  }

  return {
    userId: sub.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    status: mapGoogleStatus(sub.subscriptionState),
    productId: ultimo?.productId ?? null,
    currentPeriodEnd: ultimo?.expiryTime ?? null,
    cancelAtPeriodEnd: sub.subscriptionState === 'SUBSCRIPTION_STATE_CANCELED',
    purchaseToken,
  };
}

// ── RTDN (Real-time Developer Notification via Pub/Sub push) ─────────────────
export interface NotificacaoGoogle {
  messageId: string;
  notificationType: number;
  purchaseToken: string;
}

// Decodifica o envelope Pub/Sub push. A mensagem real vem base64 em
// message.data (DeveloperNotification). Devolve null para mensagens que não
// são de assinatura (test/voided/oneTimeProduct).
export function decodificarRtdn(body: unknown): NotificacaoGoogle | null {
  const env = body as { message?: { data?: string; messageId?: string } };
  const data = env.message?.data;
  const messageId = env.message?.messageId;
  if (!data || !messageId) return null;

  const json = JSON.parse(atob(data)) as {
    subscriptionNotification?: { notificationType: number; purchaseToken: string };
  };
  const sn = json.subscriptionNotification;
  if (!sn) return null;
  return { messageId, notificationType: sn.notificationType, purchaseToken: sn.purchaseToken };
}
