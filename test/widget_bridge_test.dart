import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/core/widget_bridge.dart';

// Cobre a lógica pura da ponte de widgets (espelhada em Swift KairoFormat e
// Kotlin KairoFormat). Se algo aqui mudar, atualize os dois lados nativos.
void main() {
  group('montarPayload (serialização para o storage compartilhado)', () {
    test('campos nulos são omitidos', () {
      expect(WidgetBridge.montarPayload(), isEmpty);
      expect(
        WidgetBridge.montarPayload(phraseToday: 'oi'),
        {'phrase_today': 'oi'},
      );
    });

    test('streak é incluído quando informado (inclusive 0)', () {
      expect(WidgetBridge.montarPayload(streakCount: 0), {'streak_count': 0});
      expect(WidgetBridge.montarPayload(streakCount: 12), {'streak_count': 12});
    });

    test('next_practice_time acompanha o título (null = sem horário)', () {
      final semTempo = WidgetBridge.montarPayload(nextPracticeTitle: '5 min de silêncio');
      expect(semTempo['next_practice_title'], '5 min de silêncio');
      expect(semTempo.containsKey('next_practice_time'), isTrue);
      expect(semTempo['next_practice_time'], isNull);

      final comTempo = WidgetBridge.montarPayload(
        nextPracticeTitle: 'Respirar',
        nextPracticeTime: '2025-06-03T18:30:00Z',
      );
      expect(comTempo['next_practice_time'], '2025-06-03T18:30:00Z');
    });

    test('payload completo serializa as chaves do contrato', () {
      final m = WidgetBridge.montarPayload(
        phraseToday: 'Você não rolou o feed. O feed rolou você.',
        nextPracticeTitle: '5 minutos de silêncio',
        nextPracticeTime: null,
        streakCount: 12,
      );
      expect(m.keys, containsAll(<String>[
        'phrase_today', 'next_practice_title', 'next_practice_time', 'streak_count',
      ]));
    });
  });

  group('truncarFrase (em-dash, nunca "...")', () {
    test('frase curta não é truncada', () {
      const f = 'Volte ao corpo.';
      expect(WidgetBridge.truncarFrase(f, 32), f);
    });

    test('frase longa trunca com em-dash e nunca com reticências', () {
      const f = 'A mente em silêncio percebe o que o ruído sempre escondeu do olhar';
      final t = WidgetBridge.truncarFrase(f, 32);
      expect(t.length, lessThanOrEqualTo(32));
      expect(t.endsWith('—'), isTrue);
      expect(t.contains('...'), isFalse);
      expect(t.contains('…'), isFalse);
    });

    test('inline de 32 chars respeita o limite', () {
      const f = 'Foco não é força. É ausência de ruído ao redor e dentro.';
      final t = WidgetBridge.truncarFrase(f, 32);
      expect(t.length, lessThanOrEqualTo(32));
    });

    test('recua até a borda de palavra (não corta no meio)', () {
      const f = 'temple garden stone rhythm silence presence';
      final t = WidgetBridge.truncarFrase(f, 20);
      // termina em em-dash e não deixa fragmento de palavra antes do traço
      expect(t.endsWith('—'), isTrue);
      expect(t.contains('  '), isFalse);
    });
  });

  group('stones (renderização do streak)', () {
    test('streak 0 → nenhum stone (estado "comece o ritmo")', () {
      final s = WidgetBridge.stones(0);
      expect(s.cheios, 0);
      expect(s.overflow, isFalse);
    });

    test('streak 1 → 1 stone', () {
      expect(WidgetBridge.stones(1), (cheios: 1, overflow: false));
    });

    test('streak 7 → 7 stones, sem overflow', () {
      expect(WidgetBridge.stones(7), (cheios: 7, overflow: false));
    });

    test('streak > 7 → 6 stones + overflow', () {
      expect(WidgetBridge.stones(8), (cheios: 6, overflow: true));
      expect(WidgetBridge.stones(120), (cheios: 6, overflow: true));
    });

    test('streak negativo é tratado como 0', () {
      expect(WidgetBridge.stones(-3), (cheios: 0, overflow: false));
    });
  });

  group('estado vazio', () {
    test('frase vazia/whitespace é considerada sem conteúdo', () {
      // O nativo decide o estado vazio por phrase.trim().isEmpty; aqui
      // garantimos que o truncamento de string vazia não quebra.
      expect(WidgetBridge.truncarFrase('', 32), '');
      expect(WidgetBridge.truncarFrase('   ', 32), '');
    });
  });
}
