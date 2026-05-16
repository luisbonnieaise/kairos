import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

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
  /// Carrega as últimas [limite] mensagens em ordem cronológica.
  /// Limitado por padrão para evitar payload grande e contexto inflado pro Mentor.
  static Future<List<Map<String, dynamic>>> carregar({int limite = 50}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    // Pega as últimas N em ordem descendente, depois inverte pra cronológica
    final dados = await supabase
        .from('mensagens')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limite);

    final lista = List<Map<String, dynamic>>.from(dados);
    return lista.reversed.toList();
  }

  static Future<void> salvar({
    required String role,
    required String conteudo,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('mensagens').insert({
      'user_id': user.id,
      'role': role,
      'conteudo': conteudo,
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
  static String _hoje() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String _dataString(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

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

  // Retorna lista [true, false, true, ...] dos últimos 7 dias
  // Posição 0 = hoje, posição 6 = 6 dias atrás
  static Future<List<bool>> ultimos7Dias(String praticaId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return List.filled(7, false);

    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, agora.day)
        .subtract(const Duration(days: 6));

    final dados = await supabase
        .from('pratica_completadas')
        .select('data')
        .eq('user_id', user.id)
        .eq('pratica_id', praticaId)
        .gte('data', _dataString(inicio));

    final datasFeitas = dados.map<String>((r) => r['data'] as String).toSet();

    final resultado = <bool>[];
    for (int i = 6; i >= 0; i--) {
      final d = DateTime(agora.year, agora.month, agora.day)
          .subtract(Duration(days: i));
      resultado.add(datasFeitas.contains(_dataString(d)));
    }
    return resultado;
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
  static Future<Map<String, dynamic>?> gerar() async {
    final resposta = await supabase.functions.invoke('relatorio-semanal');

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
