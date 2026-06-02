// Supabase Edge Function — Relatório Semanal do Mentor
// Analisa os últimos 7 dias do usuário (práticas, reflexões, conversas)
// e gera uma carta personalizada usando Claude Sonnet.
//
// Contrato de erro com o client (PROMPT 2.4 — varredura):
//   { error: 'nao_autorizado' }     401 — sem Authorization header (modo usuário)
//   { error: 'sessao_invalida' }    401 — JWT inválido / getUser falhou
//   { error: 'data_invalida' }      400 — semana_inicio inválida (modo CRON ou usuário)
//   { error: 'user_id_invalido' }   400 — modo CRON sem user_id válido
//   { error: 'rate_limit' }         429 — bateu uso_ia (3/24h, só modo usuário)
//   { error: 'relatorio_erro' }     502 — Anthropic falhou ou resposta sem JSON
//   { error: 'erro_interno' }       500 — config ausente, save falhou ou exceção
// Detalhes técnicos da causa NUNCA são devolvidos ao client — só vão para
// console.error (logs do Supabase, acessíveis ao operador).
//
// Dois modos de operação:
//   1) Modo USUÁRIO (fallback manual): Authorization JWT do usuário, rate limit
//      via uso_ia (3/24h), validação estrita de semana_inicio. Idempotente por
//      (user_id, semana_inicio).
//   2) Modo CRON (geração em lote no domingo): header x-cron-secret == CRON_SECRET.
//      Recebe { user_id, semana_inicio }, usa SERVICE ROLE para tudo (sem JWT
//      de usuário), MANTÉM a mesma idempotência. Não aplica rate limit
//      por-usuário (o espalhamento do dispatcher é a defesa, e bater o limite
//      pelo cron geraria timeout em massa). Sempre grava no ledger uso_ia
//      (auditoria de custo permanece consistente entre os dois modos).
//
// O secret nunca deve ser logado nem exposto em erro ao client.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import {
  ISO_DATE,
  UUID_RE,
  MODELO_SONNET,
  validarSemanaInicio,
  extrairCarta,
} from '../_shared/validacao.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function sistemaRelatorio(idioma: string): string {
  const lingua = {
    'pt': 'português brasileiro',
    'en': 'English',
    'es': 'español',
    'de': 'Deutsch',
  }[idioma] ?? 'português brasileiro';

  return `You are the Mentor of Kairo. It is Sunday. You are writing the WEEKLY LETTER for the user — the most important moment of the app.

LANGUAGE (CRITICAL — NO EXCEPTION)
Write everything in ${lingua}. Never mix languages.
The user message below uses English labels (Week, USER PROFILE, etc.) as operational metadata. That is for your reading only. Every field you produce in the JSON MUST be in ${lingua}, not English (unless ${lingua} happens to be English).

TONE
- Calm, deep, contemplative. Zen mentor tone.
- Short, direct sentences. No flourish.
- No emojis. No markdown. No lists.
- May call the user by name occasionally (not in every sentence).
- Connect with the identity they declared wanting to build.

PUNCTUATION
Questions end with "?". Statements with ".". Always.

STRUCTURE — you MUST respond with valid JSON containing 4 fields (all in ${lingua}):
{
  "observacoes": "3 to 5 sentences observing how the week went. Tone of a mentor who watched from afar. Concrete, based on the data.",
  "padroes": "1 or 2 emotional or behavioral patterns you detected in the week. Can be cutting when useful, without being aggressive.",
  "conquistas": "Facts about what was sustained. No hype, no exclamation. Just dignified observation.",
  "pergunta": "ONE single provocative question to guide the coming week. Strong. Direct. Ends in ?."
}

WRITE NOTHING OUTSIDE THE JSON. Just the pure JSON, no code fences.`;
}

// Sempre usa métodos UTC para evitar comportamento dependente do timezone do servidor.
function dataStringUTC(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

// Adiciona N dias a uma data sem alterar o objeto original.
function addDias(d: Date, n: number): Date {
  const r = new Date(d);
  r.setUTCDate(r.getUTCDate() + n);
  return r;
}

// Calcula semana a partir de semana_inicio fornecido pelo cliente (tempo local do usuário).
// O cliente passa "YYYY-MM-DD" calculado em seu timezone local — garantia de semana correta.
function calcularSemanaDoCliente(semanaInicioParam: string): { dataInicio: string; dataFim: string } {
  const inicio = new Date(`${semanaInicioParam}T12:00:00Z`); // noon UTC elimina ambiguidade de DST
  const fim = addDias(inicio, 6);
  return { dataInicio: dataStringUTC(inicio), dataFim: dataStringUTC(fim) };
}

// Fallback: calcula semana pelo relógio UTC do servidor (menos preciso para fusos UTC-N).
function calcularSemanaUTC(): { dataInicio: string; dataFim: string } {
  const hoje = new Date();
  const diaSemana = hoje.getUTCDay(); // 0=domingo … 6=sábado
  const fim = new Date(hoje);
  if (diaSemana !== 0) {
    fim.setUTCDate(hoje.getUTCDate() - diaSemana);
  }
  const inicio = addDias(fim, -6);
  return { dataInicio: dataStringUTC(inicio), dataFim: dataStringUTC(fim) };
}

// (ISO_DATE, UUID_RE, validarSemanaInicio importados de _shared/validacao.ts)

// Resposta JSON utilitária.
function jsonResp(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

type GerarOpts = {
  // Se true, aplica rate limit por janela (modo usuário). Se false, pula
  // (modo cron — espalhamento é a defesa, e bater o limite via cron geraria
  // falha em massa).
  aplicarRateLimit: boolean;
  // Idioma vindo do client (UI atual). `null` em modo CRON ou quando o
  // client não enviou. Tem precedência sobre `profiles.idioma` quando válido —
  // evita carta em PT enquanto o perfil ainda não foi sincronizado.
  idiomaCliente: string | null;
};

const IDIOMAS_VALIDOS = ['pt', 'en', 'es', 'de'];

function normalizarIdioma(valor: unknown): string | null {
  if (typeof valor !== 'string') return null;
  return IDIOMAS_VALIDOS.includes(valor) ? valor : null;
}

// Gera a carta semanal de um usuário (passos comuns aos dois modos).
// `clienteLeitura` é o client usado para ler/escrever dados do usuário:
//   - modo usuário: client autenticado por JWT (respeita RLS).
//   - modo cron:    service role (não há JWT; filtra por user_id explícito).
// `supabaseService` é SEMPRE o service role — usado para o ledger uso_ia
// (que não tem policy de INSERT) e para os dois modos.
async function gerarCarta(
  clienteLeitura: SupabaseClient,
  supabaseService: SupabaseClient,
  anthropicKey: string,
  userId: string,
  semanaInicioParam: string | undefined,
  opts: GerarOpts,
): Promise<Response> {
  // Resolve datas. Se semana_inicio veio (modo usuário com client multi-fuso,
  // ou modo cron sempre), valida estritamente. Se não veio (modo usuário com
  // client antigo), usa fallback UTC do servidor.
  let dataInicio: string;
  let dataFim: string;
  if (semanaInicioParam !== undefined && semanaInicioParam !== null) {
    const valida = validarSemanaInicio(String(semanaInicioParam));
    if (!valida) return jsonResp({ error: 'data_invalida' }, 400);
    ({ dataInicio, dataFim } = calcularSemanaDoCliente(valida));
  } else {
    ({ dataInicio, dataFim } = calcularSemanaUTC());
  }

  // Idempotência: se já existe carta dessa semana, retorna sem chamar Claude
  // e sem gravar no ledger. Filtramos por user_id manualmente para que o
  // mesmo código funcione tanto sob RLS (modo usuário) quanto via service
  // role (modo cron) — service role bypassa RLS, então o filtro explícito é
  // a única salvaguarda.
  const { data: cartaExistente } = await clienteLeitura
    .from('relatorios_semanais')
    .select()
    .eq('user_id', userId)
    .eq('semana_inicio', dataInicio)
    .maybeSingle();

  if (cartaExistente) {
    return jsonResp({ relatorio: cartaExistente });
  }

  // ── Rate limit não-burlável (apenas modo usuário): conta o ledger uso_ia
  // (escrito só por esta função via service role). A idempotência por semana
  // já evita custo repetido da MESMA semana; este limite cobre datas
  // distintas (ex.: varrer 52 segundas do ano). Máx 3 gerações por usuário
  // por 24h. O modo cron pula esta verificação — o dispatcher já espalha as
  // chamadas, e bater o limite pelo cron geraria fila/timeout em massa.
  if (opts.aplicarRateLimit) {
    const vinteQuatroHorasAtras = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count: usoRecente } = await supabaseService
      .from('uso_ia')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('funcao', 'relatorio-semanal')
      .gte('created_at', vinteQuatroHorasAtras);

    if ((usoRecente ?? 0) >= 3) return jsonResp({ error: 'rate_limit' }, 429);
  }

  // Carrega perfil
  const { data: perfil } = await clienteLeitura
    .from('profiles')
    .select()
    .eq('id', userId)
    .maybeSingle();

  // Práticas ativas
  const { data: praticas } = await clienteLeitura
    .from('praticas')
    .select('id, nome, categoria')
    .eq('user_id', userId)
    .eq('ativa', true);

  // Completadas da semana
  const { data: completadas } = await clienteLeitura
    .from('pratica_completadas')
    .select('pratica_id, data')
    .eq('user_id', userId)
    .gte('data', dataInicio)
    .lte('data', dataFim);

  // Reflexões da semana — filtro completo início e fim para não vazar dados de outras semanas
  const { data: reflexoes } = await clienteLeitura
    .from('reflexoes')
    .select('momento, pergunta, resposta, created_at')
    .eq('user_id', userId)
    .gte('created_at', `${dataInicio}T00:00:00Z`)
    .lte('created_at', `${dataFim}T23:59:59Z`)
    .order('created_at', { ascending: true });

  // Conversas com o Mentor (mensagens do usuário) — só pra contagem, também com filtro fim
  const { data: msgsUsuario } = await clienteLeitura
    .from('mensagens')
    .select('id')
    .eq('user_id', userId)
    .eq('role', 'user')
    .gte('created_at', `${dataInicio}T00:00:00Z`)
    .lte('created_at', `${dataFim}T23:59:59Z`);

  // Monta sumário de práticas. Labels em inglês para não enviesar o LLM ao PT.
  const praticasInfo: string[] = [];
  if (praticas) {
    for (const p of praticas) {
      const dias = (completadas ?? [])
        .filter((c: any) => c.pratica_id === p.id)
        .length;
      praticasInfo.push(`- ${p.nome} (${p.categoria ?? 'uncategorized'}): ${dias}/7 days`);
    }
  }

  const reflexoesTexto = (reflexoes ?? []).map((r: any) =>
    `[${r.momento}] ${r.pergunta}\n   → ${r.resposta}`
  ).join('\n\n');

  const contextoPerfil: string[] = [];
  if (perfil?.nome)          contextoPerfil.push(`Name: ${perfil.nome}`);
  if (perfil?.identidade)    contextoPerfil.push(`Identity they want to build: "${perfil.identidade}"`);
  if (perfil?.desequilibrio) contextoPerfil.push(`What throws them off balance most: ${perfil.desequilibrio}`);
  if (perfil?.area_foco)     contextoPerfil.push(`Area they want to reorder: ${perfil.area_foco}`);
  if (perfil?.ritmo)         contextoPerfil.push(`Pace: ${perfil.ritmo}`);

  const promptUsuario = `Week from ${dataInicio} to ${dataFim}.

USER PROFILE
${contextoPerfil.length > 0 ? contextoPerfil.join('\n') : '(profile incomplete)'}

WEEK'S PRACTICES
${praticasInfo.length > 0 ? praticasInfo.join('\n') : '(no active practices)'}

REFLECTIONS WRITTEN (${(reflexoes ?? []).length})
${reflexoesTexto || '(no reflections written this week)'}

CONVERSATIONS WITH THE MENTOR
${(msgsUsuario ?? []).length} messages sent by the user this week.

Now write the weekly letter following the JSON structure.`;

  const claudeResp = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': anthropicKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: MODELO_SONNET,
      max_tokens: 1200,
      // Precedência: idioma do body (UI atual) > perfil.idioma (DB) > 'pt'.
      // No modo CRON `idiomaCliente` é sempre null e cai em perfil.idioma,
      // que é a única fonte disponível quando não há cliente.
      system: sistemaRelatorio(opts.idiomaCliente ?? (perfil?.idioma as string) ?? 'pt'),
      messages: [{ role: 'user', content: promptUsuario }],
    }),
  });

  const claudeData = await claudeResp.json();

  if (!claudeResp.ok) {
    // Não vazar o objeto de erro da Anthropic ao client.
    console.error('Anthropic falhou:', claudeResp.status, JSON.stringify(claudeData));
    return jsonResp({ error: 'relatorio_erro' }, 502);
  }

  // Chamada à Anthropic efetivada (evento faturável): registra 1 linha no
  // ledger via service role. É a escrita pela função — não pelo client —
  // que torna o rate limit não-burlável. Falha de auditoria não bloqueia
  // a resposta do usuário; só loga.
  const { error: ledgerErr } = await supabaseService
    .from('uso_ia')
    .insert({ user_id: userId, funcao: 'relatorio-semanal', modelo: MODELO_SONNET });
  if (ledgerErr) {
    console.error('Falha ao gravar uso_ia:', ledgerErr.message);
  }

  // Extrai/valida estrutura da carta (função pura — testada em _shared).
  const textoCru = claudeData.content[0].text as string;
  const relatorio = extrairCarta(textoCru);
  if (!relatorio) {
    console.error('Carta do modelo sem JSON válido:', textoCru.slice(0, 500));
    return jsonResp({ error: 'relatorio_erro' }, 502);
  }

  // Salva no banco (upsert: se já existe relatório dessa semana, substitui)
  const { data: salvo, error: salvoErro } = await clienteLeitura
    .from('relatorios_semanais')
    .upsert({
      user_id: userId,
      semana_inicio: dataInicio,
      semana_fim: dataFim,
      observacoes: relatorio.observacoes,
      padroes: relatorio.padroes,
      conquistas: relatorio.conquistas,
      pergunta: relatorio.pergunta,
    }, { onConflict: 'user_id,semana_inicio' })
    .select()
    .single();

  if (salvoErro) {
    console.error('Falha ao salvar relatorio_semanal:', salvoErro.message);
    return jsonResp({ error: 'erro_interno' }, 500);
  }

  return jsonResp({ relatorio: salvo });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl     = Deno.env.get('SUPABASE_URL')!;
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anthropicKey    = Deno.env.get('ANTHROPIC_API_KEY');
    const cronSecret      = Deno.env.get('CRON_SECRET');

    if (!anthropicKey || !serviceRoleKey) {
      // Falha de configuração do servidor — não detalhar ao client.
      console.error('Config ausente: ANTHROPIC_API_KEY ou SUPABASE_SERVICE_ROLE_KEY');
      return jsonResp({ error: 'erro_interno' }, 500);
    }

    // Service role: usado pelo ledger uso_ia em ambos os modos e como
    // cliente principal de leitura/escrita no modo cron (não há JWT).
    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // ── Detecção de modo ──────────────────────────────────────────────────
    // Modo CRON: header x-cron-secret presente e CRON_SECRET configurado e
    // ambos não-vazios e iguais. Falha em qualquer um → cai pro modo usuário.
    const headerSecret = req.headers.get('x-cron-secret');
    const isCronMode   = !!cronSecret && !!headerSecret && headerSecret === cronSecret;

    if (isCronMode) {
      // Modo CRON: recebe { user_id, semana_inicio }. Sem JWT. Não loga o
      // secret. Não chama getUser(). Usa service role para tudo. Mantém a
      // mesma idempotência por (user_id, semana_inicio).
      // Não há cliente no modo CRON, então `idiomaCliente` é sempre null —
      // a função cai em `perfil.idioma` no banco.
      let bodyData: { user_id?: string; semana_inicio?: string } = {};
      try { bodyData = await req.json(); } catch { /* ignore */ }

      const userId = bodyData.user_id;
      const semana = bodyData.semana_inicio;

      if (!userId || !UUID_RE.test(String(userId))) {
        return jsonResp({ error: 'user_id_invalido' }, 400);
      }
      if (!semana || !ISO_DATE.test(String(semana))) {
        return jsonResp({ error: 'data_invalida' }, 400);
      }

      return await gerarCarta(
        supabaseService,
        supabaseService,
        anthropicKey,
        String(userId),
        String(semana),
        { aplicarRateLimit: false, idiomaCliente: null },
      );
    }

    // ── Modo USUÁRIO (fallback manual) ────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonResp({ error: 'nao_autorizado' }, 401);

    // Client autenticado por JWT do usuário — lê dados do usuário com RLS.
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) return jsonResp({ error: 'sessao_invalida' }, 401);

    // Lê semana_inicio enviado pelo cliente (calculado em tempo local do usuário).
    // `idioma` também vem do cliente — é o idioma da UI atual e tem precedência
    // sobre o que está no perfil.
    let bodyData: { semana_inicio?: string; idioma?: string } = {};
    try { bodyData = await req.json(); } catch { /* corpo vazio ou não-JSON */ }

    return await gerarCarta(
      supabaseClient,
      supabaseService,
      anthropicKey,
      user.id,
      bodyData.semana_inicio,
      { aplicarRateLimit: true, idiomaCliente: normalizarIdioma(bodyData.idioma) },
    );
  } catch (e) {
    console.error('relatorio-semanal erro interno:', (e as Error).message);
    return jsonResp({ error: 'erro_interno' }, 500);
  }
});
