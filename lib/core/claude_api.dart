import 'package:flutter/foundation.dart';
import '../main.dart';

class ClaudeAPI {
  /// Chama a Edge Function 'mentor-chat' no Supabase.
  /// A chave ANTHROPIC_API_KEY fica protegida no servidor.
  /// Lança exceção sem detalhes técnicos pra UI tratar.
  ///
  /// [prefereSonnet] é apenas uma PREFERÊNCIA do client, não uma ordem: o
  /// servidor decide o modelo conforme a assinatura (`is_premium`). Clientes
  /// não-premium recebem SEMPRE Haiku, independente do valor enviado aqui.
  static Future<String> mentor({
    required List<Map<String, String>> mensagens,
    bool prefereSonnet = false,
  }) async {
    final resposta = await supabase.functions.invoke(
      'mentor-chat',
      body: {
        'messages': mensagens,
        'prefereSonnet': prefereSonnet,
      },
    );

    if (resposta.status != 200) {
      debugPrint('mentor-chat retornou ${resposta.status}: ${resposta.data}');
      throw Exception('mentor_erro');
    }

    final data = resposta.data as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('mentor_erro');
    }

    if (data['error'] != null) {
      debugPrint('mentor-chat error: ${data['error']}');
      throw Exception('mentor_erro');
    }

    final texto = data['text'] as String?;
    if (texto == null || texto.isEmpty) {
      throw Exception('mentor_erro');
    }
    return texto;
  }
}
