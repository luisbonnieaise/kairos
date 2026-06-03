import 'package:flutter/foundation.dart';
import '../main.dart' show supabase;
import 'banco.dart';
import 'i18n.dart';
import 'widget_bridge.dart';

/// Coleta os dados do app e empurra aos widgets nativos. Best-effort: nunca
/// lança. Sem sessão → no-op. Reúne num só lugar a derivação dos dados para
/// não duplicar nas telas/gatilhos.
class WidgetSync {
  WidgetSync._();

  static Future<void> sincronizar() async {
    if (supabase.auth.currentUser == null) return;
    try {
      final praticas = await BancoPraticas.carregar();
      final feitas = await BancoPraticas.completadasHoje();

      // Próxima prática = primeira não concluída hoje; senão a primeira da lista.
      Map<String, dynamic>? proxima;
      for (final p in praticas) {
        if (!feitas.contains(p['id'])) {
          proxima = p;
          break;
        }
      }
      proxima ??= praticas.isNotEmpty ? praticas.first : null;

      final streak = await BancoPraticas.streakDiario();

      await WidgetBridge.enviar(
        phraseToday: T.fraseDoDia(),
        nextPracticeTitle: (proxima?['nome'] as String?) ?? '',
        nextPracticeTime: null,
        streakCount: streak,
      );
    } catch (e) {
      debugPrint('[WidgetSync] sincronizar falhou: $e');
    }
  }
}
