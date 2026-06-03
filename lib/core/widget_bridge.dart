import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ponte Flutter → widgets nativos (MethodChannel 'kairo.widget').
///
/// O app empurra os dados; o lado nativo grava no storage compartilhado
/// (App Group UserDefaults no iOS, DataStore no Android) e recarrega os
/// widgets. A lógica pura (truncamento, stones, payload) vive aqui e é
/// espelhada bit-a-bit em Swift (KairoFormat) e Kotlin (KairoFormat) — os
/// testes em test/widget_bridge_test.dart cobrem esta fonte.
class WidgetBridge {
  WidgetBridge._();

  static const _canal = MethodChannel('kairo.widget');
  static const maxStones = 7;

  /// Atualiza os dados dos widgets. Campos `null` NÃO são enviados (preservam
  /// o valor anterior no storage nativo) — exceção: ao informar
  /// [nextPracticeTitle], o [nextPracticeTime] sempre acompanha (null limpa).
  static Future<void> enviar({
    String? phraseToday,
    String? nextPracticeTitle,
    String? nextPracticeTime, // ISO8601 ou null
    int? streakCount,
  }) async {
    final payload = montarPayload(
      phraseToday: phraseToday,
      nextPracticeTitle: nextPracticeTitle,
      nextPracticeTime: nextPracticeTime,
      streakCount: streakCount,
    );
    if (payload.isEmpty) return;
    try {
      await _canal.invokeMethod('updateWidgetData', payload);
    } on MissingPluginException {
      // Plataforma sem handler (web/desktop) — silencioso.
    } on PlatformException catch (e) {
      debugPrint('[WidgetBridge] updateWidgetData falhou: ${e.message}');
    }
  }

  /// Força um reload dos widgets sem alterar dados.
  static Future<void> recarregar() async {
    try {
      await _canal.invokeMethod('reloadWidgets');
    } on MissingPluginException {
      // ignora
    } on PlatformException catch (e) {
      debugPrint('[WidgetBridge] reloadWidgets falhou: ${e.message}');
    }
  }

  // ── Lógica pura (testável) ────────────────────────────────────────────────

  /// Monta o mapa enviado ao nativo a partir dos campos não-nulos.
  static Map<String, dynamic> montarPayload({
    String? phraseToday,
    String? nextPracticeTitle,
    String? nextPracticeTime,
    int? streakCount,
  }) {
    final m = <String, dynamic>{};
    if (phraseToday != null) m['phrase_today'] = phraseToday;
    if (nextPracticeTitle != null) {
      m['next_practice_title'] = nextPracticeTitle;
      // O tempo acompanha o título (null = sem horário definido).
      m['next_practice_time'] = nextPracticeTime;
    }
    if (streakCount != null) m['streak_count'] = streakCount;
    return m;
  }

  /// Trunca a frase com EM-DASH (nunca "..."). Recua à borda de palavra quando
  /// possível. Espelha KairoFormat.truncar (Swift/Kotlin).
  static String truncarFrase(String texto, int max) {
    final limpo = texto.trim();
    if (limpo.length <= max || max <= 1) return limpo;
    final corte = limpo.substring(0, max - 1);
    final ultimoEspaco = corte.lastIndexOf(' ');
    if (ultimoEspaco >= max ~/ 2) {
      final palavra = corte.substring(0, ultimoEspaco);
      return '${_trimDireita(palavra)}—';
    }
    return '${corte.trimRight()}—';
  }

  static String _trimDireita(String s) {
    var fim = s.length;
    while (fim > 0 && ' ,;:'.contains(s[fim - 1])) {
      fim--;
    }
    return s.substring(0, fim);
  }

  /// (stones cheios, overflow?) — streak > 7 vira 6 stones + "·".
  static ({int cheios, bool overflow}) stones(int streak) {
    if (streak <= 0) return (cheios: 0, overflow: false);
    if (streak <= maxStones) return (cheios: streak, overflow: false);
    return (cheios: maxStones - 1, overflow: true);
  }
}
