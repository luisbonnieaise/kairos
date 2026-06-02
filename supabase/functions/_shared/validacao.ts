// Funções puras compartilhadas pelas Edge Functions. Vivem aqui (em vez de
// inline nos handlers) para serem testáveis via `deno test` sem subir HTTP
// nem tocar Supabase/Anthropic. Mantemos comportamento BIT-PERFEITO ao que
// estava antes da extração — qualquer mudança de semântica deve ser
// deliberada e ter teste correspondente.

export const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
export const UUID_RE  = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const MODELO_HAIKU  = 'claude-haiku-4-5-20251001';
export const MODELO_SONNET = 'claude-sonnet-4-6';

// ── Validação de semana_inicio (relatorio-semanal) ──────────────────────────
// Convenção do app (lib/telas/biblioteca.dart::_semanaInicioAtual e
// lib/core/datas.dart::semanaInicioISO): semana_inicio = segunda-feira em UTC
// (getUTCDay()===1). Regras: formato ISO, segunda-feira, não-futuro, ≤ 366
// dias no passado. Retorna a data validada ou null.
//
// `agora` é injetado para teste — produção passa Date.now().
export function validarSemanaInicio(
  s: unknown,
  agora: number = Date.now(),
): string | null {
  if (typeof s !== 'string') return null;
  if (!ISO_DATE.test(s)) return null;
  const d = new Date(`${s}T12:00:00Z`); // meio-dia UTC elimina DST
  if (Number.isNaN(d.getTime())) return null;
  if (d.getUTCDay() !== 1) return null;
  if (d.getTime() > agora) return null;
  if (agora - d.getTime() > 366 * 24 * 60 * 60 * 1000) return null;
  return s;
}

// ── Extração do JSON da carta (relatorio-semanal) ───────────────────────────
// O modelo pode embrulhar o JSON em texto/markdown. A regex pega o primeiro
// bloco entre chaves (greedy via [\s\S]*). Retorna o objeto tipado ou null
// se não houver JSON ou ele estiver malformado.
//
// O contrato com o sistema-prompt exige os 4 campos abaixo; aqui apenas
// confirmamos que vieram strings (validação de domínio fica fora — esta
// camada é "estrutura, não conteúdo").
export type Carta = {
  observacoes: string;
  padroes: string;
  conquistas: string;
  pergunta: string;
};

export function extrairCarta(texto: string): Carta | null {
  const m = texto.match(/\{[\s\S]*\}/);
  if (!m) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(m[0]);
  } catch {
    return null;
  }
  if (parsed === null || typeof parsed !== 'object') return null;
  const obj = parsed as Record<string, unknown>;
  const campos = ['observacoes', 'padroes', 'conquistas', 'pergunta'] as const;
  for (const k of campos) {
    if (typeof obj[k] !== 'string') return null;
  }
  return {
    observacoes: obj['observacoes'] as string,
    padroes:     obj['padroes']     as string,
    conquistas:  obj['conquistas']  as string,
    pergunta:    obj['pergunta']    as string,
  };
}

// ── Decisão de modelo (mentor-chat) ─────────────────────────────────────────
// O servidor é fonte da verdade: `premium` vem do is_premium() server-side.
// `prefereSonnet` é só uma INTENÇÃO do client — só tem efeito se premium=true.
// Não-premium SEMPRE Haiku, independente da flag.
export function decidirModelo(
  premium: boolean,
  prefereSonnet: boolean,
): typeof MODELO_HAIKU | typeof MODELO_SONNET {
  return (premium && prefereSonnet) ? MODELO_SONNET : MODELO_HAIKU;
}
