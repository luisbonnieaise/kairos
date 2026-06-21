import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'i18n.dart';

// ── ÁUDIO DO MENTOR (mensagens de voz) ───────────────────────────────────────
// Upload e leitura dos áudios no bucket privado `audios-mentor`. O áudio fica
// em {uid}/{timestamp}.m4a; a RLS do Storage garante que cada usuário só acessa
// a própria pasta (a Edge Function transcrever-audio baixa via service role).

class BancoAudios {
  static const _bucket = 'audios-mentor';
  // MIME na lista allowed_mime_types do bucket (ver migration). AAC LC em
  // contêiner m4a → audio/mp4 é o tipo canônico.
  static const _mime = 'audio/mp4';

  /// Envia o arquivo local de voz ao Storage e retorna o caminho ({uid}/...).
  static Future<String> enviar(String caminhoLocal) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final bytes = await File(caminhoLocal).readAsBytes();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final caminho = '${user.id}/$ts.m4a';

    debugPrint('[Audio] upload → bucket=$_bucket path=$caminho bytes=${bytes.length}');

    await supabase.storage.from(_bucket).uploadBinary(
          caminho,
          bytes,
          fileOptions: const FileOptions(contentType: _mime, upsert: false),
        );

    return caminho;
  }

  /// URL assinada de curta duração para reproduzir um áudio do bucket privado.
  /// Usada ao reabrir o histórico (a gravação recém-feita toca do arquivo local).
  static Future<String> urlAssinada(String caminho, {int validadeSegundos = 3600}) {
    return supabase.storage.from(_bucket).createSignedUrl(caminho, validadeSegundos);
  }

  /// Remove um áudio (best-effort; ignora arquivo inexistente).
  static Future<void> remover(String caminho) async {
    try {
      await supabase.storage.from(_bucket).remove([caminho]);
    } catch (e) {
      debugPrint('[Audio] erro ao remover $caminho: $e');
    }
  }
}

// ── TRANSCRIÇÃO (fala → texto via Edge Function) ──────────────────────────────

class Transcricao {
  /// Chama a Edge Function `transcrever-audio` (Groq Whisper no servidor) e
  /// devolve o texto transcrito (pode vir vazio se o áudio for silêncio).
  ///
  /// Lança `Exception` com o código de erro do servidor ('precisa_assinar',
  /// 'rate_limit', 'transcricao_erro', ...) para a UI mapear a mensagem.
  static Future<String> transcrever({
    required String audioPath,
    int? duracaoMs,
  }) async {
    try {
      final resposta = await supabase.functions.invoke(
        'transcrever-audio',
        body: {
          'audio_path': audioPath,
          if (duracaoMs != null) 'duracao_ms': duracaoMs,
          'idioma': T.idioma,
        },
      );

      final data = resposta.data as Map<String, dynamic>?;
      if (resposta.status != 200 || data == null) {
        debugPrint('transcrever-audio status ${resposta.status}: ${resposta.data}');
        throw Exception(_codigo(data) ?? 'transcricao_erro');
      }
      if (data['error'] != null) {
        debugPrint('transcrever-audio error: ${data['error']}');
        throw Exception(data['error'] as String);
      }
      return (data['text'] as String?) ?? '';
    } on FunctionException catch (e) {
      // Em versões recentes do functions_client, invoke lança em status >= 400;
      // o corpo JSON da função vem em e.details.
      debugPrint('transcrever-audio FunctionException ${e.status}: ${e.details}');
      final det = e.details;
      final codigo = det is Map ? det['error'] as String? : null;
      throw Exception(codigo ?? 'transcricao_erro');
    }
  }

  static String? _codigo(Map<String, dynamic>? data) =>
      data != null ? data['error'] as String? : null;
}
