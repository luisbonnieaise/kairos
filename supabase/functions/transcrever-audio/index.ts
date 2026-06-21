// Supabase Edge Function — Transcrever Áudio (mensagem de voz do Mentor)
// Recebe o caminho de um áudio que o usuário acabou de enviar ao bucket privado
// `audios-mentor`, baixa via service role, manda pro Groq Whisper e devolve o
// texto. O Claude/Anthropic não aceita áudio, então toda voz vira texto aqui
// antes de chegar ao mentor-chat. A chave GROQ_API_KEY fica protegida no servidor.
//
// Mesmo esqueleto de segurança do mentor-chat:
//   auth → is_premium (hard paywall) → rate-limit no ledger uso_ia → trabalho.
//
// Contrato de erro com o client (espelha mentor-chat):
//   { error: 'nao_autorizado' }    401 — sem Authorization header
//   { error: 'sessao_invalida' }   401 — JWT inválido / getUser falhou
//   { error: 'corpo_invalido' }    400 — audio_path ausente/ inválido/ de outro usuário
//   { error: 'precisa_assinar' }   403 — usuário não-premium
//   { error: 'rate_limit' }        429 — bateu uso_ia por janela
//   { error: 'transcricao_erro' }  502 — falha ao baixar áudio ou no Groq
//   { error: 'erro_interno' }      500 — config ausente ou exceção não tratada
// Detalhes técnicos da causa NUNCA vão ao client — só para console.error.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';
import { corsHeaders, json } from '../_shared/cors.ts';

const BUCKET = 'audios-mentor';
// Modelo do Groq Whisper. Configurável via secret GROQ_WHISPER_MODEL (ex.:
// 'whisper-large-v3-turbo', mais rápido/barato) com fallback para o large-v3.
const MODELO_WHISPER = Deno.env.get('GROQ_WHISPER_MODEL') ?? 'whisper-large-v3';
const TAMANHO_MAX = 10 * 1024 * 1024; // 10 MB — alinhado ao file_size_limit do bucket
const IDIOMAS_VALIDOS = ['pt', 'en', 'es', 'de'];
// Caminho esperado: {uuid}/{timestamp}.{ext}. Trava o usuário na própria pasta
// e barra path traversal antes mesmo de tocar no Storage.
const PATH_RE = /^[0-9a-f-]{36}\/[A-Za-z0-9_-]+\.(m4a|aac|mp4|mp3|webm)$/i;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: 'nao_autorizado' }, 401);
    }

    const supabaseUrl     = Deno.env.get('SUPABASE_URL')!;
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const groqKey         = Deno.env.get('GROQ_API_KEY');

    if (!groqKey || !serviceRoleKey) {
      console.error('Config ausente: GROQ_API_KEY ou SUPABASE_SERVICE_ROLE_KEY');
      return json({ error: 'erro_interno' }, 500);
    }

    // Cliente autenticado com o JWT do usuário — usado só para confirmar quem é.
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    // Cliente service role — bypassa RLS. Usado para gating, baixar o áudio e
    // gravar o ledger. É o que torna o rate-limit não-burlável.
    const supabaseService = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return json({ error: 'sessao_invalida' }, 401);
    }

    const corpo = await req.json().catch(() => null);
    const audioPath = corpo?.audio_path;
    const idiomaCliente =
      typeof corpo?.idioma === 'string' && IDIOMAS_VALIDOS.includes(corpo.idioma)
        ? corpo.idioma
        : null;

    // Validação de entrada: formato do caminho + dono. O usuário só pode pedir
    // transcrição de áudio dentro da própria pasta {uid}/.
    if (typeof audioPath !== 'string' || !PATH_RE.test(audioPath)) {
      return json({ error: 'corpo_invalido' }, 400);
    }
    if (!audioPath.startsWith(`${user.id}/`)) {
      console.error(`Tentativa de transcrever áudio de outra pasta: user=${user.id} path=${audioPath}`);
      return json({ error: 'corpo_invalido' }, 400);
    }

    // ── Hard paywall: recurso de IA exige assinatura ativa/trial ─────────────
    const { data: premiumData, error: premiumErr } = await supabaseService
      .rpc('is_premium', { uid: user.id });
    if (premiumErr) {
      console.error('Erro ao avaliar is_premium:', premiumErr.message);
    }
    if (premiumData !== true) {
      return json({ error: 'precisa_assinar' }, 403);
    }

    // ── Rate limit não-burlável: conta o ledger uso_ia (escrito só por funções
    // via service role). Transcrição é mais cara que um turno de chat, então o
    // teto por hora é menor que o do mentor-chat.
    const limitePorHora = 60;
    const umaHoraAtras = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count: usoRecente } = await supabaseService
      .from('uso_ia')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('funcao', 'transcrever-audio')
      .gte('created_at', umaHoraAtras);

    if ((usoRecente ?? 0) >= limitePorHora) {
      return json({ error: 'rate_limit' }, 429);
    }

    // ── Baixa o áudio via service role (ignora RLS) ──────────────────────────
    const { data: blob, error: dlErr } = await supabaseService.storage
      .from(BUCKET)
      .download(audioPath);

    if (dlErr || !blob) {
      console.error('Falha ao baixar áudio:', dlErr?.message ?? 'blob nulo', audioPath);
      return json({ error: 'transcricao_erro' }, 502);
    }
    if (blob.size === 0 || blob.size > TAMANHO_MAX) {
      console.error(`Áudio com tamanho inválido: ${blob.size} bytes (${audioPath})`);
      return json({ error: 'corpo_invalido' }, 400);
    }

    // ── Groq Whisper (API estilo OpenAI, multipart) ──────────────────────────
    const nomeArquivo = audioPath.split('/').pop() ?? 'audio.m4a';
    const form = new FormData();
    form.append('file', blob, nomeArquivo);
    form.append('model', MODELO_WHISPER);
    form.append('response_format', 'json');
    form.append('temperature', '0');
    // Dica de idioma melhora a acurácia; só envia se for um dos suportados.
    if (idiomaCliente) form.append('language', idiomaCliente);

    const groqResp = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${groqKey}` },
      body: form,
    });

    const groqData = await groqResp.json().catch(() => null);

    if (!groqResp.ok || !groqData) {
      console.error('Groq falhou:', groqResp.status, JSON.stringify(groqData));
      return json({ error: 'transcricao_erro' }, 502);
    }

    const texto = typeof groqData.text === 'string' ? groqData.text.trim() : '';

    // Sucesso (mesmo que silêncio → texto vazio): registra 1 linha no ledger.
    // A escrita pela função (não pelo client) torna o rate-limit não-burlável.
    const { error: ledgerErr } = await supabaseService
      .from('uso_ia')
      .insert({ user_id: user.id, funcao: 'transcrever-audio', modelo: MODELO_WHISPER });
    if (ledgerErr) {
      console.error('Falha ao gravar uso_ia:', ledgerErr.message);
    }

    return json({ text: texto });
  } catch (e) {
    console.error('transcrever-audio erro interno:', (e as Error).message);
    return json({ error: 'erro_interno' }, 500);
  }
});
