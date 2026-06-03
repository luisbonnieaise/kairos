// Helpers Apple App Store (compartilhados por apple-webhook e verify-purchase).
//   • verificarJws()        — valida a assinatura JWS e a cadeia x5c até a
//                             Apple Root CA - G3 (pinada). Devolve o payload.
//   • estadoCanonicoApple() — re-busca o estado real via App Store Server API
//                             (getAllSubscriptionStatuses) e mapeia p/ o
//                             vocabulário canônico de public.subscriptions.
//
// Segredos esperados (🟦 Supabase, ver docs/08-guia-consoles-luis.md §2):
//   APPLE_BUNDLE_ID, APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (.p8),
//   APPLE_ENV ('Sandbox'|'Production').
//   APPLE_ROOT_CA_G3 (base64 DER da AppleRootCA-G3.cer) — pin da raiz. Baixe em
//   https://www.apple.com/certificateauthority/ e cole; sem ela a verificação
//   FALHA FECHADA (não há fallback inseguro).

import * as jose from 'https://esm.sh/jose@5.9.6';
import {
  b64ToBytes,
  b64urlToBytes,
  ecdsaDerToRaw,
  parseCertificate,
} from './asn1.ts';

// OIDs ECDSA → (hash Web Crypto, tamanho de cada metade r/s).
const ECDSA_OID: Record<string, { hash: string; size: number }> = {
  '1.2.840.10045.4.3.2': { hash: 'SHA-256', size: 32 }, // ecdsa-with-SHA256
  '1.2.840.10045.4.3.3': { hash: 'SHA-384', size: 48 }, // ecdsa-with-SHA384
};

function pemDe(derB64: string): string {
  const linhas = derB64.match(/.{1,64}/g)?.join('\n') ?? derB64;
  return `-----BEGIN CERTIFICATE-----\n${linhas}\n-----END CERTIFICATE-----`;
}

function rootG3Bytes(): Uint8Array {
  const b64 = (Deno.env.get('APPLE_ROOT_CA_G3') ?? '').replace(/\s+/g, '');
  if (!b64) {
    throw new Error('APPLE_ROOT_CA_G3 ausente — pin da raiz Apple não configurado');
  }
  return b64ToBytes(b64);
}

function bytesIguais(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// Verifica que `cert` foi assinado pela chave pública de `issuer` (ambos DER).
async function certAssinadoPor(certDer: Uint8Array, issuerDer: Uint8Array): Promise<boolean> {
  const cert = parseCertificate(certDer);
  const alg = ECDSA_OID[cert.sigAlgOid];
  if (!alg) throw new Error(`sigAlg não suportado: ${cert.sigAlgOid}`);

  const issuer = parseCertificate(issuerDer);
  const namedCurve = alg.size === 32 ? 'P-256' : 'P-384';
  const chave = await crypto.subtle.importKey(
    'spki',
    issuer.spki,
    { name: 'ECDSA', namedCurve },
    false,
    ['verify'],
  );
  const sigRaw = ecdsaDerToRaw(cert.sigValue, alg.size);
  return crypto.subtle.verify({ name: 'ECDSA', hash: alg.hash }, chave, sigRaw, cert.tbs);
}

// Valida a assinatura do JWS compacto e a cadeia x5c até a Apple Root CA - G3
// pinada; devolve o payload decodificado. Lança em qualquer falha.
export async function verificarJws<T = Record<string, unknown>>(jws: string): Promise<T> {
  const [headerB64] = jws.split('.');
  if (!headerB64) throw new Error('JWS malformado');
  const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(headerB64))) as {
    alg?: string;
    x5c?: string[];
  };
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) throw new Error('JWS sem cadeia x5c');

  // 1) A assinatura do JWS é feita pela chave da folha (x5c[0]).
  const leafKey = await jose.importX509(pemDe(x5c[0]), header.alg ?? 'ES256');
  const { payload } = await jose.compactVerify(jws, leafKey);

  // 2) Cada cert é assinado pelo seguinte na cadeia.
  const certs = x5c.map((c) => b64ToBytes(c));
  for (let i = 0; i < certs.length - 1; i++) {
    const ok = await certAssinadoPor(certs[i], certs[i + 1]);
    if (!ok) throw new Error(`Cadeia x5c quebrada no índice ${i}`);
  }

  // 3) A raiz apresentada (último cert) DEVE ser exatamente a Root CA - G3
  //    pinada — não basta estar presente; comparamos os bytes DER.
  const raiz = certs[certs.length - 1];
  if (!bytesIguais(raiz, rootG3Bytes())) {
    throw new Error('Raiz da cadeia não é a Apple Root CA - G3 pinada');
  }

  return JSON.parse(new TextDecoder().decode(payload)) as T;
}

// Decodifica um JWS confiável (cadeia já validada externamente) sem re-verificar.
// Usado para os JWS aninhados (signedTransactionInfo/signedRenewalInfo) cuja
// integridade já está coberta pela verificação do payload externo.
export function decodificarJwsPayload<T = Record<string, unknown>>(jws: string): T {
  const partes = jws.split('.');
  if (partes.length !== 3) throw new Error('JWS aninhado malformado');
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(partes[1]))) as T;
}

// ── App Store Server API ──────────────────────────────────────────────────
function appleHost(): string {
  const env = Deno.env.get('APPLE_ENV') ?? 'Sandbox';
  return env === 'Production'
    ? 'https://api.storekit.itunes.apple.com'
    : 'https://api.storekit-sandbox.itunes.apple.com';
}

// Assina o JWT ES256 exigido pela App Store Server API (header com kid; claims
// iss=issuerId, aud='appstoreconnect-v1', bid=bundleId, exp ~ +20min).
async function tokenServerApi(): Promise<string> {
  const issuerId   = Deno.env.get('APPLE_ISSUER_ID');
  const keyId      = Deno.env.get('APPLE_KEY_ID');
  const bundleId   = Deno.env.get('APPLE_BUNDLE_ID');
  const privateKey = Deno.env.get('APPLE_PRIVATE_KEY');
  if (!issuerId || !keyId || !bundleId || !privateKey) {
    throw new Error('Config Apple ausente (ISSUER_ID/KEY_ID/BUNDLE_ID/PRIVATE_KEY)');
  }
  const pk = await jose.importPKCS8(privateKey, 'ES256');
  return new jose.SignJWT({ bid: bundleId })
    .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
    .setIssuer(issuerId)
    .setAudience('appstoreconnect-v1')
    .setIssuedAt()
    .setExpirationTime('20m')
    .sign(pk);
}

export type EstadoCanonico = {
  status: string;                      // active|trialing|past_due|canceled|expired|grace
  productId: string | null;
  currentPeriodEnd: string | null;     // ISO
  cancelAtPeriodEnd: boolean;
  providerSubId: string;               // originalTransactionId
  appAccountToken: string | null;      // = supabase user_id
};

// Re-busca o estado canônico de uma assinatura via getAllSubscriptionStatuses
// e mapeia para o vocabulário de public.subscriptions. `transactionId` pode ser
// o originalTransactionId ou um transactionId — a Apple resolve ambos.
export async function estadoCanonicoApple(transactionId: string): Promise<EstadoCanonico | null> {
  const token = await tokenServerApi();
  const url = `${appleHost()}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`;
  const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) {
    throw new Error(`App Store Server API ${r.status}`);
  }
  const body = await r.json() as {
    data?: Array<{
      lastTransactions?: Array<{
        status?: number;
        originalTransactionId?: string;
        signedTransactionInfo?: string;
        signedRenewalInfo?: string;
      }>;
    }>;
  };

  // Pega a transação mais recente do grupo (Apple devolve por subscription group).
  const last = body.data?.[0]?.lastTransactions?.[0];
  if (!last?.signedTransactionInfo) return null;

  const tx = decodificarJwsPayload<{
    originalTransactionId?: string;
    productId?: string;
    expiresDate?: number;
    appAccountToken?: string;
    offerType?: number;          // 1 = introdutória (free trial costuma vir aqui)
    offerDiscountType?: string;  // 'FREE_TRIAL' | 'PAY_AS_YOU_GO' | 'PAY_UP_FRONT'
  }>(last.signedTransactionInfo);

  let autoRenew = true;
  let renewalTrial = false;
  if (last.signedRenewalInfo) {
    const ri = decodificarJwsPayload<{
      autoRenewStatus?: number;
      offerType?: number;
      offerDiscountType?: string;
    }>(last.signedRenewalInfo);
    autoRenew = ri.autoRenewStatus !== 0;
    renewalTrial = ri.offerDiscountType === 'FREE_TRIAL' || ri.offerType === 1;
  }

  const emTrial = renewalTrial || tx.offerType === 1 || tx.offerDiscountType === 'FREE_TRIAL';

  // Mapeamento (Apple lastTransactions[].status):
  //   1 Active        -> trialing (se em trial) | active (cancel flag se autoRenew off)
  //   2 Expired       -> expired
  //   3 Billing retry -> grace  (a Apple ainda tenta recobrar; mantém acesso)
  //   4 Grace period  -> grace
  //   5 Revoked       -> canceled (inclui reembolso)
  let status: string;
  let cancelAtPeriodEnd = false;
  switch (last.status) {
    case 1:
      status = emTrial ? 'trialing' : 'active';
      cancelAtPeriodEnd = !autoRenew;
      break;
    case 3:
    case 4:
      status = 'grace';
      break;
    case 2:
      status = 'expired';
      break;
    case 5:
      status = 'canceled';
      break;
    default:
      status = 'canceled';
  }

  return {
    status,
    productId: tx.productId ?? null,
    currentPeriodEnd: tx.expiresDate != null ? new Date(tx.expiresDate).toISOString() : null,
    cancelAtPeriodEnd,
    providerSubId: tx.originalTransactionId ?? last.originalTransactionId ?? transactionId,
    appAccountToken: tx.appAccountToken ?? null,
  };
}
