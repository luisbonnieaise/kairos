// Supabase Edge Function — Relatório Semanal do Mentor
// Analisa os últimos 7 dias do usuário (práticas, reflexões, conversas)
// e gera uma carta personalizada usando Claude Sonnet.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';

const MODELO_SONNET = 'claude-sonnet-4-6';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

function dataString(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Não autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl     = Deno.env.get('SUPABASE_URL')!;
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const anthropicKey    = Deno.env.get('ANTHROPIC_API_KEY');

    if (!anthropicKey) {
      return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY não configurada' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Sessão inválida' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Carrega perfil
    const { data: perfil } = await supabaseClient
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

    // Calcula a semana da carta:
    // semana_fim = domingo mais recente (ou hoje se hoje é domingo)
    // semana_inicio = segunda anterior = semana_fim - 6 dias
    const hoje = new Date();
    const diaSemana = hoje.getDay(); // 0=domingo, 1=segunda, ... 6=sábado
    const fim = new Date(hoje);
    if (diaSemana !== 0) {
      fim.setDate(hoje.getDate() - diaSemana);
    }
    const inicio = new Date(fim);
    inicio.setDate(fim.getDate() - 6);

    const dataInicio = dataString(inicio);
    const dataFim    = dataString(fim);

    // Idempotência: se já existe carta dessa semana, retorna sem chamar Claude
    const { data: cartaExistente } = await supabaseClient
      .from('relatorios_semanais')
      .select()
      .eq('user_id', user.id)
      .eq('semana_inicio', dataInicio)
      .maybeSingle();

    if (cartaExistente) {
      return new Response(JSON.stringify({ relatorio: cartaExistente }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Práticas ativas
    const { data: praticas } = await supabaseClient
      .from('praticas')
      .select('id, nome, categoria')
      .eq('user_id', user.id)
      .eq('ativa', true);

    // Completadas da semana
    const { data: completadas } = await supabaseClient
      .from('pratica_completadas')
      .select('pratica_id, data')
      .eq('user_id', user.id)
      .gte('data', dataInicio)
      .lte('data', dataFim);

    // Reflexões da semana
    const { data: reflexoes } = await supabaseClient
      .from('reflexoes')
      .select('momento, pergunta, resposta, created_at')
      .eq('user_id', user.id)
      .gte('created_at', `${dataInicio}T00:00:00Z`)
      .order('created_at', { ascending: true });

    // Conversas com o Mentor (mensagens do usuário) — só pra contagem
    const { data: msgsUsuario } = await supabaseClient
      .from('mensagens')
      .select('id')
      .eq('user_id', user.id)
      .eq('role', 'user')
      .gte('created_at', `${dataInicio}T00:00:00Z`);

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
      return new Response(JSON.stringify({ error: claudeData }), {
        status: claudeResp.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const textoCru = claudeData.content[0].text as string;

    // Extrai JSON da resposta (caso venha com texto extra)
    const matchJson = textoCru.match(/\{[\s\S]*\}/);
    if (!matchJson) {
      return new Response(JSON.stringify({ error: 'Resposta sem JSON', raw: textoCru }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let relatorio: { observacoes: string; padroes: string; conquistas: string; pergunta: string };
    try {
      relatorio = JSON.parse(matchJson[0]);
    } catch (e) {
      return new Response(JSON.stringify({ error: 'JSON inválido', raw: textoCru }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Salva no banco (upsert: se já existe relatório dessa semana, substitui)
    const { data: salvo, error: salvoErro } = await supabaseClient
      .from('relatorios_semanais')
      .upsert({
        user_id: user.id,
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
      return new Response(JSON.stringify({ error: salvoErro.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ relatorio: salvo }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
