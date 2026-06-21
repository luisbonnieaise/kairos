// Testes da derivação pura de premium no client (lib/core/billing.dart).
// Mantém paridade EXATA com public.is_premium() no banco: premium ⇔
// status ∈ {active, trialing, grace} AND current_period_end > now.
// ('grace' = janela de retry de cobrança Apple/Google que ainda dá acesso.)

import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/core/billing.dart';

void main() {
  final agora = DateTime(2025, 6, 15, 12, 0);

  group('Billing.derivarPremium — status habilitantes', () {
    test('active + period_end no futuro → true', () {
      expect(
        Billing.derivarPremium(
          status: 'active',
          periodoFim: agora.add(const Duration(days: 7)),
          agora: agora,
        ),
        isTrue,
      );
    });

    test('trialing + period_end no futuro → true', () {
      expect(
        Billing.derivarPremium(
          status: 'trialing',
          periodoFim: agora.add(const Duration(hours: 1)),
          agora: agora,
        ),
        isTrue,
      );
    });

    test('grace + period_end no futuro → true', () {
      expect(
        Billing.derivarPremium(
          status: 'grace',
          periodoFim: agora.add(const Duration(days: 3)),
          agora: agora,
        ),
        isTrue,
      );
    });
  });

  group('Billing.derivarPremium — status NÃO habilitantes', () {
    for (final s in [
      'none',
      'incomplete',
      'incomplete_expired',
      'past_due',
      'canceled',
      'unpaid',
      'paused',
      'expired',
    ]) {
      test('$s → false mesmo com period_end no futuro', () {
        expect(
          Billing.derivarPremium(
            status: s,
            periodoFim: agora.add(const Duration(days: 30)),
            agora: agora,
          ),
          isFalse,
        );
      });
    }

    test('null → false', () {
      expect(
        Billing.derivarPremium(
          status: null,
          periodoFim: agora.add(const Duration(days: 30)),
          agora: agora,
        ),
        isFalse,
      );
    });
  });

  group('Billing.derivarPremium — vencimento', () {
    test('active com period_end no passado (expirado) → false', () {
      expect(
        Billing.derivarPremium(
          status: 'active',
          periodoFim: agora.subtract(const Duration(seconds: 1)),
          agora: agora,
        ),
        isFalse,
      );
    });

    test('active com period_end exatamente == agora → false (estrita)', () {
      // Critério SQL é `> now()`, estritamente — testamos a mesma fronteira.
      expect(
        Billing.derivarPremium(
          status: 'active',
          periodoFim: agora,
          agora: agora,
        ),
        isFalse,
      );
    });

    test('active sem period_end (null) → false', () {
      expect(
        Billing.derivarPremium(
          status: 'active',
          periodoFim: null,
          agora: agora,
        ),
        isFalse,
      );
    });

    test('trialing expirado → false', () {
      expect(
        Billing.derivarPremium(
          status: 'trialing',
          periodoFim: agora.subtract(const Duration(minutes: 1)),
          agora: agora,
        ),
        isFalse,
      );
    });
  });
}
