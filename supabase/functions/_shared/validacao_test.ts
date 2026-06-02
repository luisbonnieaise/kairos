// Testes das funções puras compartilhadas pelas Edge Functions.
//
// Rodar:
//   deno test supabase/functions/_shared/validacao_test.ts
// ou para tudo:
//   deno test --allow-none supabase/functions/
//
// Sem rede, sem Supabase, sem Anthropic.

import {
  assert,
  assertEquals,
  assertNotEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';

import {
  ISO_DATE,
  UUID_RE,
  MODELO_HAIKU,
  MODELO_SONNET,
  validarSemanaInicio,
  extrairCarta,
  decidirModelo,
} from './validacao.ts';

// ── ISO_DATE / UUID_RE ──────────────────────────────────────────────────────
Deno.test('ISO_DATE aceita YYYY-MM-DD bem-formado', () => {
  assert(ISO_DATE.test('2025-06-09'));
  assert(ISO_DATE.test('0001-01-01'));
});

Deno.test('ISO_DATE rejeita variações comuns', () => {
  assert(!ISO_DATE.test('2025-6-9'));
  assert(!ISO_DATE.test('2025/06/09'));
  assert(!ISO_DATE.test('2025-06-09T00:00:00Z'));
  assert(!ISO_DATE.test(''));
});

Deno.test('UUID_RE aceita uuid v4 lowercase e uppercase', () => {
  assert(UUID_RE.test('123e4567-e89b-12d3-a456-426614174000'));
  assert(UUID_RE.test('123E4567-E89B-12D3-A456-426614174000'));
});

Deno.test('UUID_RE rejeita strings sem estrutura', () => {
  assert(!UUID_RE.test('123e4567e89b12d3a456426614174000'));
  assert(!UUID_RE.test('not-a-uuid'));
  assert(!UUID_RE.test(''));
});

// ── validarSemanaInicio ─────────────────────────────────────────────────────
// "agora" canônico: terça-feira 2025-06-17T10:00:00Z → janela [≤ 366 dias atrás, ≤ agora]
const AGORA = new Date('2025-06-17T10:00:00Z').getTime();

Deno.test('validarSemanaInicio: segunda válida na janela passa', () => {
  // 2025-06-09 é segunda em UTC.
  assertEquals(validarSemanaInicio('2025-06-09', AGORA), '2025-06-09');
});

Deno.test('validarSemanaInicio: domingo é rejeitado', () => {
  // 2025-06-15 é domingo.
  assertEquals(validarSemanaInicio('2025-06-15', AGORA), null);
});

Deno.test('validarSemanaInicio: data no futuro é rejeitada', () => {
  // 2025-06-23 é segunda mas futura em relação a AGORA.
  assertEquals(validarSemanaInicio('2025-06-23', AGORA), null);
});

Deno.test('validarSemanaInicio: data > 366 dias no passado é rejeitada', () => {
  // 2024-06-10 é segunda; está mais de 366 dias antes de AGORA (2025-06-17).
  assertEquals(validarSemanaInicio('2024-06-10', AGORA), null);
});

Deno.test('validarSemanaInicio: formato malformado é rejeitado', () => {
  assertEquals(validarSemanaInicio('2025/06/09', AGORA), null);
  assertEquals(validarSemanaInicio('06-09-2025', AGORA), null);
  assertEquals(validarSemanaInicio('', AGORA), null);
});

Deno.test('validarSemanaInicio: tipos não-string são rejeitados', () => {
  assertEquals(validarSemanaInicio(null, AGORA), null);
  assertEquals(validarSemanaInicio(undefined, AGORA), null);
  assertEquals(validarSemanaInicio(20250609, AGORA), null);
  assertEquals(validarSemanaInicio({}, AGORA), null);
});

// ── extrairCarta ────────────────────────────────────────────────────────────
const CARTA_OK = {
  observacoes: 'A semana teve ritmo.',
  padroes: 'Disciplina antes de motivação.',
  conquistas: 'Cinco práticas sustentadas.',
  pergunta: 'O que você silenciou para chegar até aqui?',
};

Deno.test('extrairCarta: JSON puro é parseado', () => {
  const r = extrairCarta(JSON.stringify(CARTA_OK));
  assertEquals(r, CARTA_OK);
});

Deno.test('extrairCarta: JSON com texto extra antes/depois ainda funciona', () => {
  const sujo = `Aqui está a carta:\n\n${JSON.stringify(CARTA_OK)}\n\nFim.`;
  assertEquals(extrairCarta(sujo), CARTA_OK);
});

Deno.test('extrairCarta: JSON envolto em code fence markdown ainda funciona', () => {
  const fence = '```json\n' + JSON.stringify(CARTA_OK) + '\n```';
  assertEquals(extrairCarta(fence), CARTA_OK);
});

Deno.test('extrairCarta: sem chaves → null', () => {
  assertEquals(extrairCarta('Apenas texto cru, sem JSON.'), null);
});

Deno.test('extrairCarta: JSON malformado → null', () => {
  assertEquals(extrairCarta('{"observacoes": "incompleto'), null);
});

Deno.test('extrairCarta: faltando campos obrigatórios → null', () => {
  const incompleto = { observacoes: 'a', padroes: 'b', conquistas: 'c' };
  assertEquals(extrairCarta(JSON.stringify(incompleto)), null);
});

Deno.test('extrairCarta: campo com tipo errado → null', () => {
  const tipoErrado = { ...CARTA_OK, pergunta: 42 };
  assertEquals(extrairCarta(JSON.stringify(tipoErrado)), null);
});

Deno.test('extrairCarta: null literal → null', () => {
  assertEquals(extrairCarta('null'), null);
});

// ── decidirModelo ───────────────────────────────────────────────────────────
Deno.test('decidirModelo: não-premium sempre recebe Haiku (mesmo querendo Sonnet)', () => {
  assertEquals(decidirModelo(false, true), MODELO_HAIKU);
  assertEquals(decidirModelo(false, false), MODELO_HAIKU);
});

Deno.test('decidirModelo: premium + prefereSonnet=true → Sonnet', () => {
  assertEquals(decidirModelo(true, true), MODELO_SONNET);
});

Deno.test('decidirModelo: premium sem preferência → Haiku (default mais barato)', () => {
  assertEquals(decidirModelo(true, false), MODELO_HAIKU);
});

Deno.test('decidirModelo: constantes são distintas', () => {
  assertNotEquals(MODELO_HAIKU, MODELO_SONNET);
});
