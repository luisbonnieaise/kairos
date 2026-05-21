// Supabase Edge Function — Relatório Semanal do Mentor
// Analisa os últimos 7 dias do usuário (práticas, reflexões, conversas)
// e gera uma carta personalizada usando Claude Sonnet.
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

const MODELO_SONNET = 'claude-sonnet-4-6';

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

LANGUAGE (CRITICAL)
Write everything in ${lingua}. Never mix languages.

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

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const UUID_RE  = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Validação de semana_inicio — defesa contra custo ilimitado.
// Convenção do app (lib/telas/biblioteca.dart::_semanaInicioAtual): semana_fim
// é o domingo mais recente; semana_inicio = domingo - 6 dias → SEMPRE uma
// SEGUNDA-FEIRA. Em UTC, segunda = getUTCDay() === 1.
// Regras: formato ISO, ser segunda-feira, não estar no futuro nem mais de
// 366 dias no passado. Retorna a data normalizada ou null se inválida.
function validarSemanaInicio(s: string): string | null {
  if (!ISO_DATE.test(s)) return null;
  const d = new Date(`${s}T12:00:00Z`); // meio-dia UTC elimina ambiguidade de DST
  if (Number.isNaN(d.getTime())) return null;
  if (d.getUTCDay() !== 1) return null; // não é segunda-feira

  const agora = Date.now();
  if (d.getTime() > agora) return null; // futuro
  if (agora - d.getTime() > 366 * 24 * 60 * 60 * 1000) return null; // > 366 dias atrás
  return s;
}

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
};

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

  // Monta sumário de práticas
  const praticasInfo: string[] = [];
  if (praticas) {
    for (const p of praticas) {
      const dias = (completadas ?? [])
        .filter((c: any) => c.pratica_id === p.id)
        .length;
      praticasInfo.push(`- ${p.nome} (${p.categoria ?? 'sem categoria'}): ${dias}/7 dias`);
    }
  }

  const reflexoesTexto = (reflexoes ?? []).map((r: any) =>
    `[${r.momento}] ${r.pergunta}\n   → ${r.resposta}`
  ).join('\n\n');

  const contextoPerfil: string[] = [];
  if (perfil?.nome)          contextoPerfil.push(`Nome: ${perfil.nome}`);
  if (perfil?.identidade)    contextoPerfil.push(`Identidade que ele quer construir: "${perfil.identidade}"`);
  if (perfil?.desequilibrio) contextoPerfil.push(`O que mais o tira do eixo: ${perfil.desequilibrio}`);
  if (perfil?.area_foco)     contextoPerfil.push(`Área que quer reordenar: ${perfil.area_foco}`);
  if (perfil?.ritmo)         contextoPerfil.push(`Ritmo: ${perfil.ritmo}`);

  const promptUsuario = `Semana de ${dataInicio} a ${dataFim}.

PERFIL DO USUÁRIO
${contextoPerfil.length > 0 ? contextoPerfil.join('\n') : '(perfil incompleto)'}

PRÁTICAS DA SEMANA
${praticasInfo.length > 0 ? praticasInfo.join('\n') : '(nenhuma prática ativa)'}

REFLEXÕES ESCRITAS (${(reflexoes ?? []).length})
${reflexoesTexto || '(nenhuma reflexão escrita esta semana)'}

CONVERSAS COM O MENTOR
${(msgsUsuario ?? []).length} mensagens enviadas pelo usuário esta semana.

Agora escreva a carta semanal seguindo a estrutura JSON.`;

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
      system: sistemaRelatorio((perfil?.idioma as string) ?? 'pt'),
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

  const textoCru = claudeData.content[0].text as string;

  // Extrai JSON da resposta (caso venha com texto extra)
  const matchJson = textoCru.match(/\{[\s\S]*\}/);
  if (!matchJson) {
    console.error('Relatório sem JSON na resposta do modelo:', textoCru.slice(0, 500));
    return jsonResp({ error: 'relatorio_erro' }, 502);
  }

  let relatorio: { observacoes: string; padroes: string; conquistas: string; pergunta: string };
  try {
    relatorio = JSON.parse(matchJson[0]);
  } catch {
    console.error('Relatório com JSON inválido:', matchJson[0].slice(0, 500));
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
        { aplicarRateLimit: false },
      );
    }

    // ── Modo USUÁRIO (fallback manual) ────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonResp({ error: 'Não autorizado' }, 401);

    // Client autenticado por JWT do usuário — lê dados do usuário com RLS.
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) return jsonResp({ error: 'Sessão inválida' }, 401);

    // Lê semana_inicio enviado pelo cliente (calculado em tempo local do usuário).
    let bodyData: { semana_inicio?: string } = {};
    try { bodyData = await req.json(); } catch { /* corpo vazio ou não-JSON */ }

    return await gerarCarta(
      supabaseClient,
      supabaseService,
      anthropicKey,
      user.id,
      bodyData.semana_inicio,
      { aplicarRateLimit: true },
    );
  } catch (e) {
    console.error('relatorio-semanal erro interno:', (e as Error).message);
    return jsonResp({ error: 'erro_interno' }, 500);
  }
});
