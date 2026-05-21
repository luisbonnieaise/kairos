// Testes das funções puras de data (lib/core/datas.dart).
// Cobrem: formato YMD, ordem cronológica de ultimos7DiasFlags, semana_inicio
// do client (convenção: semana_fim = domingo mais recente), e bordas críticas
// (virada de mês e ano).

import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/core/datas.dart';

void main() {
  group('formatarDataYMD', () {
    test('formata data simples com padding correto', () {
      expect(formatarDataYMD(DateTime(2025, 1, 5)), '2025-01-05');
      expect(formatarDataYMD(DateTime(2025, 12, 31)), '2025-12-31');
    });

    test('preserva ano de 4 dígitos para anos < 1000', () {
      expect(formatarDataYMD(DateTime(99, 1, 1)), '0099-01-01');
    });

    test('é estável sob componente de hora', () {
      // A formatação ignora hora — duas DateTime no mesmo dia formatam igual.
      expect(formatarDataYMD(DateTime(2025, 6, 15, 0, 0, 0)),
          formatarDataYMD(DateTime(2025, 6, 15, 23, 59, 59)));
    });
  });

  group('semanaInicioISO (lógica do client da carta semanal)', () {
    test('em domingo, semana_inicio = domingo - 6 dias (segunda passada)', () {
      // 2025-06-15 é domingo → semana_fim = 15/06; inicio = 09/06 (segunda).
      expect(semanaInicioISO(DateTime(2025, 6, 15)), '2025-06-09');
    });

    test('em segunda, semana_inicio = domingo passado - 6 = segunda anterior', () {
      // 2025-06-16 é segunda → fim = 15/06 (domingo); inicio = 09/06 (segunda).
      expect(semanaInicioISO(DateTime(2025, 6, 16)), '2025-06-09');
    });

    test('em sábado, semana_inicio = segunda da MESMA semana corrente', () {
      // 2025-06-21 é sábado → fim = 15/06 (domingo passado); inicio = 09/06.
      // (Convenção: a "carta da semana" só vira no próximo domingo.)
      expect(semanaInicioISO(DateTime(2025, 6, 21)), '2025-06-09');
    });

    test('borda: domingo virando o ano cai na segunda da semana anterior', () {
      // 2023-01-01 era domingo → semana_inicio = 26/12/2022 (segunda).
      expect(semanaInicioISO(DateTime(2023, 1, 1)), '2022-12-26');
    });

    test('borda: virada de mês', () {
      // 2024-03-03 é domingo → segunda = 26/02 (mês anterior).
      expect(semanaInicioISO(DateTime(2024, 3, 3)), '2024-02-26');
    });

    test('o resultado é sempre uma segunda-feira em pt do app', () {
      // Verifica meia dúzia de pontos espalhados ao longo do ano.
      for (final d in [
        DateTime(2025, 1, 1),
        DateTime(2025, 3, 14),
        DateTime(2025, 7, 4),
        DateTime(2025, 11, 30),
        DateTime(2024, 2, 29), // ano bissexto
      ]) {
        final s = semanaInicioISO(d);
        final partes = s.split('-').map(int.parse).toList();
        final reconst = DateTime(partes[0], partes[1], partes[2]);
        expect(reconst.weekday, DateTime.monday,
            reason: 'semanaInicioISO($d) -> $s não é segunda-feira');
      }
    });
  });

  group('inicioJanela7Dias', () {
    test('retorna hoje - 6 dias em YYYY-MM-DD', () {
      expect(inicioJanela7Dias(DateTime(2025, 6, 15)), '2025-06-09');
    });

    test('atravessa virada de mês', () {
      expect(inicioJanela7Dias(DateTime(2025, 3, 3)), '2025-02-25');
    });

    test('atravessa virada de ano', () {
      expect(inicioJanela7Dias(DateTime(2025, 1, 3)), '2024-12-28');
    });
  });

  group('ultimos7DiasFlags', () {
    test('ordem cronológica ASCENDENTE: posição 0 = 6 dias atrás, 6 = hoje', () {
      // Apenas o último dia (hoje) é feito.
      final flags = ultimos7DiasFlags(
        agora: DateTime(2025, 6, 15),
        datasFeitas: {'2025-06-15'},
      );
      expect(flags.length, 7);
      expect(flags.last, isTrue);
      expect(flags.take(6).every((b) => b == false), isTrue);
    });

    test('todos os 7 marcados quando o set tem os 7 dias', () {
      final agora = DateTime(2025, 6, 15);
      final datas = {
        for (int i = 0; i <= 6; i++)
          formatarDataYMD(DateTime(agora.year, agora.month, agora.day)
              .subtract(Duration(days: i))),
      };
      expect(
          ultimos7DiasFlags(agora: agora, datasFeitas: datas), List.filled(7, true));
    });

    test('nenhum marcado quando o set é vazio', () {
      expect(
          ultimos7DiasFlags(
              agora: DateTime(2025, 6, 15), datasFeitas: <String>{}),
          List.filled(7, false));
    });

    test('virada de mês: dia da virada cai na posição correta', () {
      // hoje = 2025-03-03 (terça). Janela: 25/02 a 03/03.
      // datasFeitas contém só 28/02 (fevereiro).
      final flags = ultimos7DiasFlags(
        agora: DateTime(2025, 3, 3),
        datasFeitas: {'2025-02-28'},
      );
      // 25/02 26/02 27/02 28/02 01/03 02/03 03/03  → flags[3] deve ser true.
      expect(flags, [false, false, false, true, false, false, false]);
    });

    test('virada de ano: ano anterior cai nos primeiros índices', () {
      // hoje = 2025-01-03 (sexta). Janela: 28/12/2024 a 03/01/2025.
      final flags = ultimos7DiasFlags(
        agora: DateTime(2025, 1, 3),
        datasFeitas: {'2024-12-31', '2025-01-01'},
      );
      // 28/12 29/12 30/12 31/12 01/01 02/01 03/01 → flags[3], flags[4] true.
      expect(flags, [false, false, false, true, true, false, false]);
    });

    test('ignora componente de hora em agora', () {
      final manha = DateTime(2025, 6, 15, 1, 0);
      final noite = DateTime(2025, 6, 15, 23, 59);
      expect(
        ultimos7DiasFlags(agora: manha, datasFeitas: {'2025-06-15'}),
        ultimos7DiasFlags(agora: noite, datasFeitas: {'2025-06-15'}),
      );
    });
  });
}
