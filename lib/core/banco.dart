import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'datas.dart';
import 'i18n.dart';

// ── PERFIL DO USUÁRIO ────────────────────────────────────────────────────────

class BancoPerfil {
  static Future<Map<String, dynamic>?> carregar() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final dados = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    return dados;
  }

  static Future<void> atualizar({
    String? nome,
    String? identidade,
    String? desequilibrio,
    String? areaFoco,
    String? ritmo,
    String? horarioLembrete, // formato "HH:MM:SS" ou null para apagar
    bool limparHorarioLembrete = false,
    String? idioma,
    bool? notifJardim,
    String? avatarUrl, // URL pública do avatar; string vazia = remover
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }

    final dados = <String, dynamic>{
      'id': user.id,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (nome != null) dados['nome'] = nome;
    if (identidade != null) dados['identidade'] = identidade;
    if (desequilibrio != null) dados['desequilibrio'] = desequilibrio;
    if (areaFoco != null) dados['area_foco'] = areaFoco;
    if (ritmo != null) dados['ritmo'] = ritmo;
    if (horarioLembrete != null) dados['horario_lembrete'] = horarioLembrete;
    if (limparHorarioLembrete) dados['horario_lembrete'] = null;
    if (idioma != null) dados['idioma'] = idioma;
    if (notifJardim != null) dados['notif_jardim'] = notifJardim;
    if (avatarUrl != null) {
      dados['avatar_url'] = avatarUrl.isEmpty ? null : avatarUrl;
    }

    await supabase.from('profiles').upsert(dados);
  }
}

// ── AVATAR DO USUÁRIO ────────────────────────────────────────────────────────

class BancoAvatar {
  static const _bucket = 'profire';

  /// Carrega a URL pública do avatar a partir do perfil.
  static Future<String?> carregarUrl() async {
    final perfil = await BancoPerfil.carregar();
    return perfil?['avatar_url'] as String?;
  }

  /// Faz upload dos bytes ao Storage e persiste a URL no perfil.
  /// Retorna a URL pública com cache-buster para forçar recarregamento.
  static Future<String> enviar(Uint8List bytes, String extensao) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final ext     = extensao.toLowerCase().isEmpty ? 'jpg' : extensao.toLowerCase();
    final caminho = '${user.id}/avatar.$ext';
    final mime    = 'image/${ext == 'jpg' ? 'jpeg' : ext}';

    debugPrint('[Avatar] upload → bucket=$_bucket path=$caminho mime=$mime bytes=${bytes.length}');

    try {
      await supabase.storage
          .from(_bucket)
          .uploadBinary(
            caminho,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
    } catch (e) {
      debugPrint('[Avatar] ERRO no upload ao Storage: $e');
      rethrow;
    }

    final ts  = DateTime.now().millisecondsSinceEpoch;
    final url = '${supabase.storage.from(_bucket).getPublicUrl(caminho)}?t=$ts';
    debugPrint('[Avatar] URL gerada: $url');

    try {
      await BancoPerfil.atualizar(avatarUrl: url);
    } catch (e) {
      debugPrint('[Avatar] ERRO ao salvar avatar_url no perfil: $e');
      rethrow;
    }

    return url;
  }

  /// Remove o arquivo do Storage e limpa a URL no perfil.
  static Future<void> remover() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Tentativa silenciosa — ignora erros de arquivo inexistente
    try {
      await supabase.storage.from(_bucket).remove([
        '${user.id}/avatar.jpg',
        '${user.id}/avatar.jpeg',
        '${user.id}/avatar.png',
        '${user.id}/avatar.webp',
      ]);
    } catch (_) {}

    await BancoPerfil.atualizar(avatarUrl: '');
  }
}

// ── TUTORIAIS (vistos por usuário, salvos no perfil) ─────────────────────────

class BancoTutoriais {
  /// Carrega quais tutoriais o usuário já viu.
  /// Retorna um map tipo {'patio': true, 'mentor': true, ...}
  static Future<Map<String, bool>> carregarVistos() async {
    final user = supabase.auth.currentUser;
    if (user == null) return {};

    final dados = await supabase
        .from('profiles')
        .select('tutoriais_vistos')
        .eq('id', user.id)
        .maybeSingle();

    final raw = dados?['tutoriais_vistos'];
    if (raw == null) return {};
    final mapa = raw as Map<String, dynamic>;
    return mapa.map((k, v) => MapEntry(k, v == true));
  }

  static Future<bool> jaVisto(String chave) async {
    final vistos = await carregarVistos();
    return vistos[chave] == true;
  }

  static Future<void> marcarVisto(String chave) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final vistos = await carregarVistos();
    vistos[chave] = true;

    await supabase
        .from('profiles')
        .update({'tutoriais_vistos': vistos})
        .eq('id', user.id);
  }

  /// Apaga todos os tutoriais vistos — útil pra "rever tutoriais" no Perfil.
  static Future<void> resetar() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('profiles')
        .update({'tutoriais_vistos': {}})
        .eq('id', user.id);
  }
}

// ── MENSAGENS DO MENTOR ──────────────────────────────────────────────────────

class BancoMensagens {
  /// Tamanho de página do histórico (cada "puxar pra carregar mais antigas").
  static const int pagina = 50;

  /// Diz se há QUALQUER mensagem salva para o usuário, sem trazer o conteúdo.
  /// Usado ao abrir o Mentor: a conversa anterior fica oculta, mas o hint de
  /// "puxe pra baixo" e o gesto só aparecem quando há histórico a revelar.
  static Future<bool> existeHistorico() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final dados = await supabase
        .from('mensagens')
        .select('user_id')
        .eq('user_id', user.id)
        .limit(1);

    return (dados as List).isNotEmpty;
  }

  /// Carrega até [limite] mensagens ANTERIORES a [antesDe] (paginação reversa
  /// do histórico — usada ao puxar a conversa pra baixo). Devolve em ordem
  /// cronológica; lista vazia significa que não há mais histórico.
  static Future<List<Map<String, dynamic>>> carregarAntigas({
    required DateTime antesDe,
    int limite = pagina,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final dados = await supabase
        .from('mensagens')
        .select()
        .eq('user_id', user.id)
        .lt('created_at', antesDe.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limite);

    final lista = List<Map<String, dynamic>>.from(dados);
    return lista.reversed.toList();
  }

  /// Salva uma mensagem. Para mensagens de voz, passe [audioPath] (caminho no
  /// bucket privado audios-mentor) e [audioDuracaoMs]; o [conteudo] recebe a
  /// transcrição. Mensagens de texto deixam ambos nulos.
  static Future<void> salvar({
    required String role,
    required String conteudo,
    String? audioPath,
    int? audioDuracaoMs,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('mensagens').insert({
      'user_id': user.id,
      'role': role,
      'conteudo': conteudo,
      if (audioPath != null) 'audio_path': audioPath,
      if (audioDuracaoMs != null) 'audio_duracao_ms': audioDuracaoMs,
    });
  }

  static Future<void> limparTudo() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('mensagens').delete().eq('user_id', user.id);
  }
}

// ── PRÁTICAS ─────────────────────────────────────────────────────────────────

class BancoPraticas {
  // Funções de data são puras e vivem em core/datas.dart (testáveis sem
  // mockar Supabase). Mantidas como wrappers locais por compat de chamada.
  static String _hoje() => formatarDataYMD(DateTime.now());

  static Future<List<Map<String, dynamic>>> carregar() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final dados = await supabase
        .from('praticas')
        .select()
        .eq('user_id', user.id)
        .eq('ativa', true)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(dados);
  }

  static Future<Map<String, dynamic>?> adicionar({
    required String nome,
    String? duracao,
    String? categoria,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final resultado = await supabase
        .from('praticas')
        .insert({
          'user_id': user.id,
          'nome': nome,
          if (duracao != null) 'duracao': duracao,
          if (categoria != null) 'categoria': categoria,
        })
        .select()
        .single();

    return resultado;
  }

  static Future<void> remover(String praticaId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase
        .from('praticas')
        .delete()
        .eq('id', praticaId)
        .eq('user_id', user.id);
  }

  // Retorna lista de IDs de práticas completadas hoje
  static Future<Set<String>> completadasHoje() async {
    final user = supabase.auth.currentUser;
    if (user == null) return {};

    final dados = await supabase
        .from('pratica_completadas')
        .select('pratica_id')
        .eq('user_id', user.id)
        .eq('data', _hoje());

    return dados.map<String>((r) => r['pratica_id'] as String).toSet();
  }

  static Future<void> marcarFeita(String praticaId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('pratica_completadas').insert({
        'user_id': user.id,
        'pratica_id': praticaId,
        'data': _hoje(),
      });
    } on PostgrestException catch (e) {
      // Código 23505 = unique violation (já marcou hoje), ignora silenciosamente
      if (e.code != '23505') {
        debugPrint('Erro ao marcar prática: ${e.message}');
        rethrow;
      }
    } catch (e) {
      debugPrint('Erro ao marcar prática: $e');
      rethrow;
    }
  }

  static Future<void> desmarcarFeita(String praticaId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase
        .from('pratica_completadas')
        .delete()
        .eq('user_id', user.id)
        .eq('pratica_id', praticaId)
        .eq('data', _hoje());
  }

  // Retorna 7 flags em ordem cronológica ASCENDENTE:
  // posição 0 = 6 dias atrás, posição 6 = hoje.
  // (Consumidores em dojo.dart e biblioteca.dart dependem dessa ordem.)
  static Future<List<bool>> ultimos7Dias(String praticaId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return List.filled(7, false);

    final agora = DateTime.now();
    final dados = await supabase
        .from('pratica_completadas')
        .select('data')
        .eq('user_id', user.id)
        .eq('pratica_id', praticaId)
        .gte('data', inicioJanela7Dias(agora));

    final datasFeitas = dados.map<String>((r) => r['data'] as String).toSet();
    return ultimos7DiasFlags(agora: agora, datasFeitas: datasFeitas);
  }

  /// Streak diário (dias consecutivos com ≥1 prática concluída), terminando no
  /// dia ativo mais recente. Usado pelos widgets de tela inicial.
  static Future<int> streakDiario({int janelaDias = 90}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return 0;

    final agora = DateTime.now();
    final inicio = formatarDataYMD(
      DateTime(agora.year, agora.month, agora.day).subtract(Duration(days: janelaDias)),
    );
    final dados = await supabase
        .from('pratica_completadas')
        .select('data')
        .eq('user_id', user.id)
        .gte('data', inicio);

    final datas = dados.map<String>((r) => r['data'] as String).toSet();
    return streakConsecutivo(agora: agora, datasFeitas: datas);
  }
}

// ── RELATÓRIOS SEMANAIS (CARTAS DO MENTOR) ───────────────────────────────────

class BancoRelatorios {
  /// Carrega as últimas [limite] cartas semanais.
  static Future<List<Map<String, dynamic>>> carregar({int limite = 24}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final dados = await supabase
        .from('relatorios_semanais')
        .select()
        .eq('user_id', user.id)
        .order('semana_inicio', ascending: false)
        .limit(limite);

    return List<Map<String, dynamic>>.from(dados);
  }

  /// Gera a carta da semana atual via Edge Function.
  /// [semanaInicio] é a data calculada em tempo LOCAL pelo Flutter (YYYY-MM-DD).
  /// Passar esse valor evita que o edge function use UTC e calcule a semana errada.
  ///
  /// O `idioma` da UI atual é enviado para o servidor — ele prefere esse valor
  /// sobre `profiles.idioma` para evitar carta em PT quando o perfil ainda não
  /// foi sincronizado.
  static Future<Map<String, dynamic>?> gerar({required String semanaInicio}) async {
    final resposta = await supabase.functions.invoke(
      'relatorio-semanal',
      body: {
        'semana_inicio': semanaInicio,
        'idioma': T.idioma,
      },
    );

    if (resposta.status != 200) {
      throw Exception('Erro ${resposta.status}: ${resposta.data}');
    }

    final data = resposta.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception('${data['error']}');
    }

    return data['relatorio'] as Map<String, dynamic>?;
  }
}

// ── REFLEXÕES (JARDIM) ───────────────────────────────────────────────────────

class BancoReflexoes {
  /// Carrega as últimas [limite] reflexões. Sem limite, com 3/dia em 1 ano = 1000+ rows.
  static Future<List<Map<String, dynamic>>> carregar({int limite = 50}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final dados = await supabase
        .from('reflexoes')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limite);

    return List<Map<String, dynamic>>.from(dados);
  }

  static Future<void> salvar({
    required String momento,
    required String pergunta,
    required String resposta,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('reflexoes').insert({
      'user_id': user.id,
      'momento': momento,
      'pergunta': pergunta,
      'resposta': resposta,
    });
  }
}
