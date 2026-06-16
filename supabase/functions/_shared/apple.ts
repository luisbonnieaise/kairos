// Integração Apple (App Store Server API V1 + App Store Server Notifications V2).
// Reaproveitado por apple-webhook (verifica a notificação) e verify-purchase
// (re-busca o estado canônico). Toda decisão de entitlement vem do RE-FETCH no
// servidor da Apple — nunca confiamos no client.
import * as jose from 'https://esm.sh/jose@5.9.6';
import type { CanonicalStatus } from './billing.ts';

export interface AppleEnv {
  privateKey: string;   // conteúdo do .p8 (PEM PKCS8)
  keyId: string;        // APPLE_KEY_ID
  issuerId: string;     // APPLE_ISSUER_ID
  bundleId: string;     // APPLE_BUNDLE_ID (com.thekairo.app)
  environment: 'Sandbox' | 'Production';
}

export function lerAppleEnv(): AppleEnv {
  const privateKey  = Deno.env.get('APPLE_PRIVATE_KEY');
  const keyId       = Deno.env.get('APPLE_KEY_ID');
  const issuerId    = Deno.env.get('APPLE_ISSUER_ID');
  const bundleId    = Deno.env.get('APPLE_BUNDLE_ID');
  const environment = (Deno.env.get('APPLE_ENV') ?? 'Sandbox') as 'Sandbox' | 'Production';
  if (!privateKey || !keyId || !issuerId || !bundleId) {
    throw new Error('Config Apple ausente: APPLE_PRIVATE_KEY/KEY_ID/ISSUER_ID/BUNDLE_ID');
  }
  return { privateKey, keyId, issuerId, bundleId, environment };
}

// ── JWT de autenticação da App Store Server API (ES256) ─────────────────────
async function tokenApi(env: AppleEnv): Promise<string> {
  const key = await jose.importPKCS8(env.privateKey, 'ES256');
  return await new jose.SignJWT({ bid: env.bundleId })
    .setProtectedHeader({ alg: 'ES256', kid: env.keyId, typ: 'JWT' })
    .setIssuer(env.issuerId)
    .setIssuedAt()
    .setExpirationTime('10m')
    .setAudience('appstoreconnect-v1')
    .sign(key);
}

function baseUrl(env: AppleEnv): string {
  return env.environment === 'Production'
    ? 'https://api.storekit.itunes.apple.com'
    : 'https://api.storekit-sandbox.itunes.apple.com';
}

// Decodifica o payload de um JWS SEM verificar assinatura. Uso restrito a
// respostas da App Store Server API (já autenticadas e sobre TLS da Apple).
// Para NOTIFICAÇÕES use verificarNotificacao().
function payloadJws<T>(jws: string): T {
  const parte = jws.split('.')[1];
  return JSON.parse(new TextDecoder().decode(jose.base64url.decode(parte))) as T;
}

interface JwsTransaction {
  appAccountToken?: string;
  originalTransactionId: string;
  productId: string;
  expiresDate?: number;       // epoch ms
  offerType?: number;         // 1 = introductory (trial)
  revocationDate?: number;
}
interface JwsRenewal {
  autoRenewStatus?: number;   // 0 = off (cancel at period end), 1 = on
  productId?: string;
}

// status (subscription group) da App Store Server API:
//   1 Active · 2 Expired · 3 Billing Retry · 4 Billing Grace Period · 5 Revoked
export function mapAppleStatus(code: number, offerType?: number): CanonicalStatus {
  switch (code) {
    case 1: return offerType === 1 ? 'trialing' : 'active';
    case 2: return 'expired';
    case 3: return 'past_due';   // retry: acesso suspenso, Apple ainda tenta
    case 4: return 'grace';      // grace period: ainda concede acesso
    case 5: return 'expired';    // revogada
    default: return 'none';
  }
}

export interface EstadoApple {
  userId: string | null;         // appAccountToken
  status: CanonicalStatus;
  productId: string | null;
  currentPeriodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  originalTransactionId: string;
}

// Re-fetch canônico: dado um transactionId/originalTransactionId, busca o
// estado real da assinatura na Apple e o reduz ao formato canônico.
// Tenta Production e cai para Sandbox (e vice-versa) — o ambiente pode diferir
// do APPLE_ENV durante testes (recomendação da própria Apple).
export async function estadoApple(env: AppleEnv, transactionId: string): Promise<EstadoApple> {
  const token = await tokenApi(env);
  const tentar = async (e: AppleEnv) => {
    const res = await fetch(`${baseUrl(e)}/inApps/v1/subscriptions/${transactionId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    return res;
  };

  let res = await tentar(env);
  if (res.status === 404) {
    // Tenta o ambiente oposto.
    const alt: AppleEnv = {
      ...env,
      environment: env.environment === 'Production' ? 'Sandbox' : 'Production',
    };
    res = await tentar(alt);
  }
  if (!res.ok) {
    throw new Error(`App Store Server API ${res.status}`);
  }

  const body = await res.json() as {
    data?: Array<{ lastTransactions?: Array<{
      status: number;
      signedTransactionInfo: string;
      signedRenewalInfo?: string;
      originalTransactionId: string;
    }> }>;
  };

  const last = body.data?.[0]?.lastTransactions?.[0];
  if (!last) throw new Error('App Store Server API: sem lastTransactions');

  const tx = payloadJws<JwsTransaction>(last.signedTransactionInfo);
  const renewal = last.signedRenewalInfo ? payloadJws<JwsRenewal>(last.signedRenewalInfo) : null;

  return {
    userId: tx.appAccountToken ?? null,
    status: mapAppleStatus(last.status, tx.offerType),
    productId: tx.productId ?? null,
    currentPeriodEnd: tx.expiresDate ? new Date(tx.expiresDate).toISOString() : null,
    cancelAtPeriodEnd: renewal?.autoRenewStatus === 0,
    originalTransactionId: last.originalTransactionId ?? tx.originalTransactionId,
  };
}

// ── Verificação da App Store Server Notification V2 ─────────────────────────
// O signedPayload é um JWS assinado pela Apple com a cadeia x5c no header.
// Verificamos a assinatura com o certificado-folha e validamos que a cadeia
// termina no Apple Root CA - G3 (pinado pelo certificado, via env).
//
// Nota de segurança: o pino do root + assinatura do leaf são defesa-em-
// profundidade. A fonte de verdade do entitlement é o RE-FETCH autenticado
// em estadoApple() (App Store Server API, com a nossa chave) — é ele que
// impede um atacante de se autoconceder Premium forjando notificação.
//
// APPLE_ROOT_CA_G3 = certificado "Apple Root CA - G3" em base64 DER
// (https://www.apple.com/certificateauthority/). Pinamos por igualdade do cert.
const APPLE_ROOT_CA_G3 = Deno.env.get('APPLE_ROOT_CA_G3');

function pemDe(b64: string): string {
  const linhas = b64.match(/.{1,64}/g)?.join('\n') ?? b64;
  return `-----BEGIN CERTIFICATE-----\n${linhas}\n-----END CERTIFICATE-----`;
}

// Normaliza base64 (remove espaços/quebras) para comparação byte-a-byte do DER.
function normB64(s: string): string {
  return s.replace(/\s+/g, '');
}

export interface NotificacaoApple {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  estado: EstadoApple;
}

// Verifica e decodifica a notificação; devolve o tipo + o estado canônico
// re-buscado a partir do transactionId embutido (fonte de verdade).
export async function verificarNotificacao(
  env: AppleEnv, signedPayload: string,
): Promise<NotificacaoApple> {
  if (!APPLE_ROOT_CA_G3) throw new Error('APPLE_ROOT_CA_G3 não configurado');

  const header = jose.decodeProtectedHeader(signedPayload);
  const x5c = header.x5c as string[] | undefined;
  if (!x5c || x5c.length < 2) throw new Error('Notificação Apple sem cadeia x5c');

  // 1. Pino do root: o último cert da cadeia tem de ser exatamente o
  //    Apple Root CA - G3 que configuramos.
  if (normB64(x5c[x5c.length - 1]) !== normB64(APPLE_ROOT_CA_G3)) {
    throw new Error('Notificação Apple: root CA não confiável');
  }

  // 2. Assinatura do JWS contra a chave pública do certificado-folha.
  const leaf = await jose.importX509(pemDe(x5c[0]), 'ES256');
  const { payload } = await jose.compactVerify(signedPayload, leaf);
  const dados = JSON.parse(new TextDecoder().decode(payload)) as {
    notificationType: string;
    subtype?: string;
    notificationUUID: string;
    data?: { signedTransactionInfo?: string };
  };

  // 3. Re-fetch canônico a partir do originalTransactionId da transação.
  const txInfo = dados.data?.signedTransactionInfo
    ? payloadJws<JwsTransaction>(dados.data.signedTransactionInfo)
    : null;
  if (!txInfo) throw new Error('Notificação Apple sem signedTransactionInfo');

  const estado = await estadoApple(env, txInfo.originalTransactionId);
  return {
    notificationType: dados.notificationType,
    subtype: dados.subtype,
    notificationUUID: dados.notificationUUID,
    estado,
  };
}
