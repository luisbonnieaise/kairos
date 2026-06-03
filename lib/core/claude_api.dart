import 'package:flutter/foundation.dart';
import '../main.dart';
import 'i18n.dart';

class ClaudeAPI {
  /// Chama a Edge Function 'mentor-chat' no Supabase.
  /// A chave ANTHROPIC_API_KEY fica protegida no servidor.
  /// Lança exceção sem detalhes técnicos pra UI tratar.
  ///
  /// [prefereSonnet] é apenas uma PREFERÊNCIA do client, não uma ordem: o
  /// servidor decide o modelo conforme a assinatura (`is_premium`, que já
  /// reflete os 3 providers — Stripe/Apple/Google). Clientes não-premium
  /// recebem SEMPRE Haiku, independente do valor enviado aqui; por isso o
  /// default é `true` (Fase 07): assinante ativo em qualquer canal → Sonnet.
  ///
  /// O idioma da UI atual é enviado em `idioma`. O servidor prefere esse valor
  /// sobre `profiles.idioma` para evitar descasamento quando o perfil ainda
  /// não foi sincronizado (ex.: primeiro login pós-confirmação de e-mail).
  static Future<String> mentor({
    required List<Map<String, String>> mensagens,
    bool prefereSonnet = true,
  }) async {
    final resposta = await supabase.functions.invoke(
      'mentor-chat',
      body: {
        'messages': mensagens,
        'prefereSonnet': prefereSonnet,
        'idioma': T.idioma,
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
