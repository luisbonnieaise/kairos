// Helpers DER/ASN.1 mínimos para validação de cadeia X.509 (Apple ASSN V2).
// Vivem aqui (em vez de inline) para serem testáveis via `deno test` sem rede.
//
// Não é um parser ASN.1 completo — só o suficiente para:
//   • fatiar um Certificate (SEQUENCE { tbsCertificate, sigAlg, sigValue }),
//   • extrair o OID do algoritmo de assinatura,
//   • extrair o subjectPublicKeyInfo (SPKI) p/ importar a chave do issuer,
//   • converter uma assinatura ECDSA DER (SEQUENCE{r,s}) para o formato raw
//     (r||s) exigido pelo Web Crypto.
//
// Referência: RFC 5280 (Certificate) e RFC 3279 (ECDSA-Sig-Value).

export type Tlv = {
  tag: number;
  // bytes do CONTEÚDO (sem header tag+length)
  content: Uint8Array;
  // bytes do elemento INTEIRO (header + conteúdo) — útil p/ TBS, que é
  // assinado byte-a-byte como aparece no certificado.
  full: Uint8Array;
  // offset (no buffer original) logo após este elemento
  end: number;
};

// Lê um TLV começando em `offset`. Lança se o length for malformado.
export function lerTlv(buf: Uint8Array, offset: number): Tlv {
  if (offset + 2 > buf.length) throw new Error('ASN.1: buffer curto');
  const tag = buf[offset];
  let pos = offset + 1;
  let len = buf[pos++];
  if (len & 0x80) {
    const nBytes = len & 0x7f;
    if (nBytes === 0 || nBytes > 4) throw new Error('ASN.1: length inválido');
    len = 0;
    for (let i = 0; i < nBytes; i++) len = (len << 8) | buf[pos++];
  }
  const contentStart = pos;
  const contentEnd = contentStart + len;
  if (contentEnd > buf.length) throw new Error('ASN.1: length excede buffer');
  return {
    tag,
    content: buf.subarray(contentStart, contentEnd),
    full: buf.subarray(offset, contentEnd),
    end: contentEnd,
  };
}

// Lê todos os filhos de um SEQUENCE/SET (a partir do conteúdo dado).
export function lerFilhos(content: Uint8Array): Tlv[] {
  const filhos: Tlv[] = [];
  let off = 0;
  while (off < content.length) {
    const t = lerTlv(content, off);
    filhos.push(t);
    off = t.end;
  }
  return filhos;
}

export type CertParts = {
  tbs: Uint8Array;          // tbsCertificate INTEIRO (header+conteúdo) — o que é assinado
  sigAlgOid: string;        // OID do algoritmo de assinatura (ex.: 1.2.840.10045.4.3.2)
  sigValue: Uint8Array;     // valor da assinatura (conteúdo do BIT STRING, sem o byte de unused-bits)
  spki: Uint8Array;         // subjectPublicKeyInfo INTEIRO (p/ importKey 'spki')
};

// Fatia um Certificate DER nas partes necessárias para verificar a cadeia.
export function parseCertificate(der: Uint8Array): CertParts {
  const cert = lerTlv(der, 0);                 // SEQUENCE Certificate
  const [tbs, sigAlg, sigBitStr] = lerFilhos(cert.content);
  if (!tbs || !sigAlg || !sigBitStr) throw new Error('Cert: estrutura inesperada');

  // tbsCertificate ::= SEQUENCE { version[0]?, serial, sigAlg, issuer, validity,
  //                               subject, subjectPublicKeyInfo, ... }
  const tbsFilhos = lerFilhos(tbs.content);
  // Pula o version EXPLICIT [0] se presente (tag 0xA0).
  let idx = 0;
  if (tbsFilhos[idx]?.tag === 0xa0) idx++;
  // serial, sigAlg, issuer, validity, subject, SPKI
  const spki = tbsFilhos[idx + 5];
  if (!spki) throw new Error('Cert: SPKI não encontrado');

  // signatureAlgorithm ::= SEQUENCE { algorithm OID, parameters? }
  const algOid = lerFilhos(sigAlg.content)[0];
  if (!algOid || algOid.tag !== 0x06) throw new Error('Cert: OID de sigAlg ausente');

  // BIT STRING: 1º byte do conteúdo = nº de unused bits (0 p/ assinatura).
  const bits = sigBitStr.content;
  const sigValue = bits.subarray(1);

  return {
    tbs: tbs.full,
    sigAlgOid: oidToString(algOid.content),
    sigValue,
    spki: spki.full,
  };
}

// Decodifica o conteúdo de um OBJECT IDENTIFIER para a forma "1.2.840...".
export function oidToString(content: Uint8Array): string {
  const partes: number[] = [];
  const first = content[0];
  partes.push(Math.floor(first / 40), first % 40);
  let val = 0;
  for (let i = 1; i < content.length; i++) {
    const b = content[i];
    val = (val << 7) | (b & 0x7f);
    if (!(b & 0x80)) {
      partes.push(val);
      val = 0;
    }
  }
  return partes.join('.');
}

// Converte assinatura ECDSA DER (SEQUENCE{r INTEGER, s INTEGER}) para raw r||s,
// com cada metade preenchida/cortada para `size` bytes (32=P-256, 48=P-384).
export function ecdsaDerToRaw(der: Uint8Array, size: number): Uint8Array {
  const seq = lerTlv(der, 0);
  const [r, s] = lerFilhos(seq.content);
  if (!r || !s) throw new Error('ECDSA-Sig: r/s ausentes');
  const out = new Uint8Array(size * 2);
  copiarInteiro(r.content, out, 0, size);
  copiarInteiro(s.content, out, size, size);
  return out;
}

// Copia um INTEGER DER (big-endian, possivelmente com 0x00 de sinal à esquerda)
// alinhado à direita num campo de `size` bytes.
function copiarInteiro(intBytes: Uint8Array, out: Uint8Array, dstOffset: number, size: number) {
  let src = intBytes;
  // remove 0x00 de sinal à esquerda
  while (src.length > size && src[0] === 0x00) src = src.subarray(1);
  if (src.length > size) throw new Error('ECDSA-Sig: integer maior que o campo');
  out.set(src, dstOffset + (size - src.length));
}

// Base64 (padrão, com +/ e padding) → Uint8Array.
export function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Base64URL (sem padding, com -_) → Uint8Array.
export function b64urlToBytes(b64url: string): Uint8Array {
  const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/').padEnd(
    b64url.length + ((4 - (b64url.length % 4)) % 4),
    '=',
  );
  return b64ToBytes(b64);
}
