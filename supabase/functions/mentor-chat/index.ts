// Supabase Edge Function — Mentor Chat
// Recebe mensagens, carrega o perfil do usuário, chama Claude API e retorna a resposta.
// A chave ANTHROPIC_API_KEY fica protegida no servidor.
//
// Contrato de erro com o client (PROMPT 2.4 — varredura):
//   { error: 'nao_autorizado' }    401 — sem Authorization header
//   { error: 'sessao_invalida' }   401 — JWT inválido / getUser falhou
//   { error: 'corpo_invalido' }    400 — validação do body (tamanho, roles, etc.)
//   { error: 'rate_limit' }        429 — bateu uso_ia por janela
//   { error: 'mentor_erro' }       502 — falha upstream da Anthropic
//   { error: 'erro_interno' }      500 — config ausente ou exceção não tratada
// Detalhes técnicos da causa NUNCA são devolvidos ao client — só vão para
// console.error (logs do Supabase, acessíveis ao operador).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import { decidirModelo } from '../_shared/validacao.ts';

function sistemaBase(idioma: string, contagemMsgsUsuario: number): string {
  const lingua = {
    'pt': 'português brasileiro',
    'en': 'English',
    'es': 'español',
    'de': 'Deutsch',
  }[idioma] ?? 'português brasileiro';

  // Após ~6 mensagens do usuário, o Mentor deve fechar com definição clara
  const faseFechamento = contagemMsgsUsuario >= 6;

  const blocoFechamento = faseFechamento ? `

⚠️ CLOSING PHASE (CRITICAL — this conversation already has ${contagemMsgsUsuario} user messages)
Stop asking questions. The user has reflected enough. Now you MUST:
1. Synthesize what you captured from the conversation (one sentence).
2. Give clear, practical direction on how to act in the next 24 hours (one or two concrete actions).
3. Connect with their personal purpose (the identity they chose to build).
4. Close the conversation with serene firmness, no more questions.

Tone: a mentor who has seen, heard, and now offers. Not an investigative therapist. Focus on SOLUTION and action.
` : '';

  return `You are the Mentor of Kairo — a personal evolution app.

LANGUAGE (CRITICAL — NO EXCEPTION)
You MUST respond ONLY in ${lingua}. Never mix languages. Even if the user writes in another language, respond in ${lingua}.
The instructions and user metadata below are written in English for your benefit — this is purely operational context. Your reply to the user MUST be in ${lingua}, not English (unless ${lingua} happens to be English).

PUNCTUATION RULE (CRITICAL, NO EXCEPTION)
Every sentence that asks a question MUST end with a question mark "?". Always.
"When did this start?" — correct.
"When did this start." — WRONG, never do this.

PERSONALITY
- Calm, deep, contemplative. Never euphoric or overly enthusiastic.
- Zen mentor tone, not a shouting motivational coach.
- You do not push. You remind the user of who they want to be.

STYLE
- Short, direct sentences. No flourish.
- Maximum 3-4 sentences per response.
- No emojis. No markdown. No lists. No exclamations.
- May use Eastern metaphors subtly (temple, garden, stone, rhythm, silence).
- In early messages (1-5), you may return a question before answering — to deepen reflection.
- After 6 messages, transition to giving CLEAR direction and action. Stop asking questions. Synthesize and conclude.
- Can be cutting when the user is in repetitive patterns of excuses, but never aggressive.
- Treat the user with adult seriousness.

CONVERSATION ARC
- Messages 1-3: listen deeply, return a clarifying question.
- Messages 4-5: connect what you hear with their identity/values.
- Messages 6+: SYNTHESIS + ACTION. Give a clear definition of how to act. Focus on personal purpose and concrete next step. Close the conversation with serenity.

NOT
- Not therapy. Does not give medical diagnoses or clinical advice.
- Not a noisy coach. No "let's go!", "you can do it!", "amazing!".
- Not a helpful chatbot. You are a silent mentor who guides reflection AND offers direction.

TONE EXAMPLES (translated to ${lingua} mentally)
"Anxiety usually comes when the mind is in what hasn't happened yet. Return to the body. Tell me more — when did this start today?"
"You said this three times this month. What is really stopping you?"
"Focus is not force. It is absence of noise. What would you need to silence?"
"The body knows what it feels. Where do you feel this now — chest, throat, stomach?"
${blocoFechamento}`;
}

// (decidirModelo importado de _shared/validacao.ts; ele encapsula MODELO_HAIKU/SONNET)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function montarContexto(perfil: Record<string, unknown> | null): string {
  if (!perfil) return '';

  const partes: string[] = [];
  const nome          = perfil.nome as string | null;
  const identidade    = perfil.identidade as string | null;
  const desequilibrio = perfil.desequilibrio as string | null;
  const areaFoco      = perfil.area_foco as string | null;
  const ritmo         = perfil.ritmo as string | null;

  // Labels in English so they don't bias the LLM toward Portuguese.
  // Values come from the user (any language) — that's fine; the system prompt
  // already mandates the response language.
  if (nome && nome.trim())                   partes.push(`Name: ${nome}`);
  if (identidade && identidade.trim())       partes.push(`Identity they want to build: "${identidade}"`);
  if (desequilibrio && desequilibrio.trim()) partes.push(`What throws them off balance most: ${desequilibrio}`);
  if (areaFoco && areaFoco.trim())           partes.push(`Area they want to reorder first: ${areaFoco}`);
  if (ritmo && ritmo.trim())                 partes.push(`Chosen evolution pace: ${ritmo}`);

  if (partes.length === 0) return '';

  return `

USER CONTEXT (use wisely — don't recite everything at once)
${partes.join('\n')}

Use this to personalize responses. You may address them by name occasionally, not in every message. When relevant, remind them of the identity they chose to build. Connect what they say with the focus area or what destabilizes them. But be subtle — don't recite their profile, let it surface naturally.
`;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'nao_autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl      = Deno.env.get('SUPABASE_URL')!;
    const supabaseAnonKey  = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anthropicKey     = Deno.env.get('ANTHROPIC_API_KEY');

    if (!anthropicKey || !serviceRoleKey) {
      // Falha de configuração do servidor — não detalhar ao client.
      console.error('Config ausente: ANTHROPIC_API_KEY ou SUPABASE_SERVICE_ROLE_KEY');
      return new Response(JSON.stringify({ error: 'erro_interno' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Cliente autenticado com o JWT do usuário — usado SÓ para ler dados do
    // usuário (profiles), mantendo RLS. Nunca decide modelo nem grava ledger.
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Cliente service role — bypassa RLS. Usado APENAS para o gating
    // (is_premium) e para gravar o ledger uso_ia. É o que torna o limite
    // não-burlável: a contagem lê uma tabela que só a função escreve.
    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Confirma que o usuário existe e está logado
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'sessao_invalida' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Carrega o perfil do usuário (RLS garante que só vê o próprio)
    const { data: perfil } = await supabaseClient
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

    const corpo = await req.json();
    const messages = corpo.messages;
    // prefereSonnet é apenas uma INTENÇÃO do client. Só tem efeito se o
    // usuário for premium (decidido server-side abaixo). Não-premium = Haiku.
    const prefereSonnet = corpo.prefereSonnet === true;
    // `idioma` é o que o usuário está VENDO no app neste momento. Tem
    // precedência sobre `profiles.idioma` para evitar resposta em PT quando
    // o perfil ainda não foi sincronizado (ex.: primeiro login pós-confirmação
    // de e-mail, ou troca recente que ainda não chegou ao DB).
    const idiomasValidos = ['pt', 'en', 'es', 'de'];
    const idiomaCliente = typeof corpo.idioma === 'string' && idiomasValidos.includes(corpo.idioma)
      ? corpo.idioma
      : null;

    // Validação de entrada (proteção contra abuso)
    // Códigos estáveis: o client agrupa tudo em 'mentor_erro' genérico
    // (lib/core/claude_api.dart); detalhes da causa ficam só em console.error.
    if (!Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: 'corpo_invalido' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (messages.length > 60) {
      return new Response(JSON.stringify({ error: 'corpo_invalido' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    for (const m of messages) {
      if (typeof m?.content !== 'string' || m.content.length > 4000) {
        return new Response(JSON.stringify({ error: 'corpo_invalido' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      if (m.role !== 'user' && m.role !== 'assistant') {
        return new Response(JSON.stringify({ error: 'corpo_invalido' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    // ── Gating server-side: assinatura + MODELO, decididos aqui (nunca client) ─
    // premium vem da função canônica is_premium (via service role): status in
    // (active,trialing,grace) AND current_period_end > now.
    const { data: premiumData, error: premiumErr } = await supabaseService
      .rpc('is_premium', { uid: user.id });
    if (premiumErr) {
      console.error('Erro ao avaliar is_premium:', premiumErr.message);
    }
    const premium = premiumData === true;

    // Hard paywall: sem plano free — o recurso de IA exige assinatura
    // ativa/trial. Defesa em profundidade: com o portão no app, um não-assinante
    // não chega aqui; este 403 cobre chamadas diretas à função.
    if (!premium) {
      return new Response(JSON.stringify({ error: 'precisa_assinar' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const modelo = decidirModelo(premium, prefereSonnet);

    // ── Rate limit não-burlável: conta o ledger uso_ia (escrito só por esta
    // função via service role), não a tabela mensagens preenchida pelo client.
    const limitePorHora = premium ? 120 : 20;
    const umaHoraAtras = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count: usoRecente } = await supabaseService
      .from('uso_ia')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('funcao', 'mentor-chat')
      .gte('created_at', umaHoraAtras);

    if ((usoRecente ?? 0) >= limitePorHora) {
      return new Response(JSON.stringify({ error: 'rate_limit' }), {
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Precedência: idioma do body (UI atual) > perfil.idioma (DB) > 'pt' (default).
    const idioma = idiomaCliente ?? (perfil?.idioma as string) ?? 'pt';
    // Conta quantas mensagens do USUÁRIO (não do mentor) nesta conversa
    const contagemUsuario = messages.filter((m: any) => m.role === 'user').length;
    const sistemaCompleto = sistemaBase(idioma, contagemUsuario) + montarContexto(perfil);

    const claudeResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'prompt-caching-2024-07-31',
      },
      body: JSON.stringify({
        model: modelo,
        max_tokens: 400,
        system: [
          {
            type: 'text',
            text: sistemaCompleto,
            cache_control: { type: 'ephemeral' },
          },
        ],
        messages,
      }),
    });

    const claudeData = await claudeResp.json();

    if (!claudeResp.ok) {
      // Não vazar o objeto de erro da Anthropic ao client.
      console.error('Anthropic falhou:', claudeResp.status, JSON.stringify(claudeData));
      return new Response(JSON.stringify({ error: 'mentor_erro' }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Resposta OK: registra 1 linha no ledger via service role. É a escrita
    // pela função (não pelo client) que torna o rate limit não-burlável.
    const { error: ledgerErr } = await supabaseService
      .from('uso_ia')
      .insert({ user_id: user.id, funcao: 'mentor-chat', modelo });
    if (ledgerErr) {
      // Não bloquear a resposta do usuário por falha de auditoria; só logar.
      console.error('Falha ao gravar uso_ia:', ledgerErr.message);
    }

    // `premium` é APENAS para display na UI (badge/estado da assinatura).
    // O modelo já foi decidido server-side via is_premium() acima; o client
    // nunca deve usar este campo para decisões de segurança/cobrança.
    return new Response(JSON.stringify({
      text: claudeData.content[0].text,
      premium,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('mentor-chat erro interno:', (e as Error).message);
    return new Response(JSON.stringify({ error: 'erro_interno' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
