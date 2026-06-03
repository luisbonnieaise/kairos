// Helpers Google Play Billing (compartilhados por google-webhook e
// verify-purchase).
//   • verificarPushOidc() — valida o token OIDC do push do Pub/Sub (assinatura
//                           Google + audience == GOOGLE_PUBSUB_AUDIENCE).
//   • estadoCanonicoGoogle() — re-busca o estado real via Play Developer API
//                              (purchases.subscriptionsv2.get) e mapeia p/ o
//                              vocabulário canônico de public.subscriptions.
//   • acknowledgeSeNecessario() — confirma a compra p/ não ser reembolsada
//                                 automaticamente em ~3 dias.
//
// Segredos esperados (🟦 Supabase, ver docs/08-guia-consoles-luis.md §3):
//   GOOGLE_PACKAGE_NAME, GOOGLE_SERVICE_ACCOUNT_JSON, GOOGLE_PUBSUB_AUDIENCE.

import * as jose from 'https://esm.sh/jose@5.9.6';

const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const ANDROID_PUBLISHER = 'https://androidpublisher.googleapis.com/androidpublisher/v3';
const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

// JWKS de verificação dos tokens OIDC emitidos pelo Pub/Sub (chaves Google).
const GOOGLE_JWKS = jose.createRemoteJWKSet(
  new URL('https://www.googleapis.com/oauth2/v3/certs'),
);

// Valida o token OIDC do push do Pub/Sub. O header chega como
// "Authorization: Bearer <jwt>"; exigimos assinatura Google + audience exata.
export async function verificarPushOidc(authHeader: string | null): Promise<void> {
  const audience = Deno.env.get('GOOGLE_PUBSUB_AUDIENCE');
  if (!audience) throw new Error('GOOGLE_PUBSUB_AUDIENCE ausente');
  if (!authHeader?.startsWith('Bearer ')) throw new Error('push sem Bearer token');
  const token = authHeader.slice('Bearer '.length).trim();
  await jose.jwtVerify(token, GOOGLE_JWKS, {
    audience,
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
  });
}

type ServiceAccount = {
  client_email: string;
  private_key: string;
  private_key_id?: string;
};

function lerServiceAccount(): ServiceAccount {
  const raw = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  if (!raw) throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON ausente');
  const sa = JSON.parse(raw) as ServiceAccount;
  if (!sa.client_email || !sa.private_key) throw new Error('service account inválida');
  return sa;
}

// Troca um JWT assinado pela service account por um access token OAuth2 com
// escopo androidpublisher.
async function accessToken(): Promise<string> {
  const sa = lerServiceAccount();
  const pk = await jose.importPKCS8(sa.private_key, 'RS256');
  const assertion = await new jose.SignJWT({ scope: SCOPE })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT', kid: sa.private_key_id })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience(GOOGLE_TOKEN_URL)
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(pk);

  const r = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!r.ok) throw new Error(`OAuth2 token ${r.status}`);
  const j = await r.json() as { access_token?: string };
  if (!j.access_token) throw new Error('OAuth2 sem access_token');
  return j.access_token;
}

export type EstadoCanonicoGoogle = {
  status: string;                      // active|past_due|canceled|expired|grace
  productId: string | null;
  currentPeriodEnd: string | null;     // ISO
  cancelAtPeriodEnd: boolean;
  obfuscatedAccountId: string | null;  // = supabase user_id
  acknowledged: boolean;
  productIdParaAck: string | null;     // subscriptionId p/ acknowledge (v3)
};

type SubscriptionV2 = {
  subscriptionState?: string;
  acknowledgementState?: string;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  lineItems?: Array<{
    productId?: string;
    expiryTime?: string;
    autoRenewingPlan?: { autoRenewEnabled?: boolean };
  }>;
};

// Re-busca o estado canônico de uma assinatura pelo purchaseToken.
export async function estadoCanonicoGoogle(purchaseToken: string): Promise<EstadoCanonicoGoogle | null> {
  const pkg = Deno.env.get('GOOGLE_PACKAGE_NAME');
  if (!pkg) throw new Error('GOOGLE_PACKAGE_NAME ausente');
  const tok = await accessToken();

  const url = `${ANDROID_PUBLISHER}/applications/${encodeURIComponent(pkg)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const r = await fetch(url, { headers: { Authorization: `Bearer ${tok}` } });
  if (!r.ok) throw new Error(`subscriptionsv2.get ${r.status}`);
  const sub = await r.json() as SubscriptionV2;

  const line = sub.lineItems?.[0];
  const autoRenew = line?.autoRenewingPlan?.autoRenewEnabled !== false;

  // Mapeamento subscriptionState -> canônico:
  //   ACTIVE          -> active (cancel flag conforme autoRenew)
  //   IN_GRACE_PERIOD -> grace
  //   ON_HOLD/PAUSED  -> past_due
  //   CANCELED        -> active + cancel_at_period_end (mantém até expirar)
  //   EXPIRED         -> expired
  let status: string;
  let cancelAtPeriodEnd = false;
  switch (sub.subscriptionState) {
    case 'SUBSCRIPTION_STATE_ACTIVE':
      status = 'active';
      cancelAtPeriodEnd = !autoRenew;
      break;
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
      status = 'grace';
      break;
    case 'SUBSCRIPTION_STATE_ON_HOLD':
    case 'SUBSCRIPTION_STATE_PAUSED':
      status = 'past_due';
      break;
    case 'SUBSCRIPTION_STATE_CANCELED':
      status = 'active';
      cancelAtPeriodEnd = true;
      break;
    case 'SUBSCRIPTION_STATE_EXPIRED':
      status = 'expired';
      break;
    default:
      status = 'canceled';
  }

  return {
    status,
    productId: line?.productId ?? null,
    currentPeriodEnd: line?.expiryTime ?? null,
    cancelAtPeriodEnd,
    obfuscatedAccountId: sub.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    acknowledged: sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    productIdParaAck: line?.productId ?? null,
  };
}

// Reconhece (acknowledge) uma compra de assinatura ainda pendente, evitando o
// reembolso automático do Google em ~3 dias. Idempotente: só chama se preciso.
export async function acknowledgeSeNecessario(
  purchaseToken: string,
  subscriptionId: string,
): Promise<void> {
  const pkg = Deno.env.get('GOOGLE_PACKAGE_NAME');
  if (!pkg) throw new Error('GOOGLE_PACKAGE_NAME ausente');
  const tok = await accessToken();
  const url = `${ANDROID_PUBLISHER}/applications/${encodeURIComponent(pkg)}/purchases/subscriptions/${encodeURIComponent(subscriptionId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const r = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
  // 200 = ok; já reconhecida pode vir 400 com motivo — não é erro fatal.
  if (!r.ok && r.status !== 400) {
    throw new Error(`acknowledge ${r.status}`);
  }
}
