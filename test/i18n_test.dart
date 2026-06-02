// Testes de regressão da camada de tradução (lib/core/i18n.dart).
// Garantem que:
//   1. cada idioma anunciado em T.idiomasDisponiveis pode ser definido;
//   2. um conjunto representativo de getters muda quando o idioma muda
//      (i.e., não estão pregados em PT por descuido);
//   3. formatadores localizados (formatarData, formatarDiaMes) produzem
//      o resultado certo por idioma;
//   4. o mapeamento de categoria aceita tanto chaves antigas (PT) quanto
//      novas (enum ASCII).
//
// Esses testes não cobrem o conteúdo de cada string — só garantem que a
// estrutura está coerente entre os 4 idiomas e que os helpers funcionam.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kairo/core/i18n.dart';

void main() {
  // T.definir/carregarLocal usa SharedPreferences — precisa de mock no harness
  // de testes (não há Android/iOS plugin disponível).
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('idiomasDisponiveis × T.definir', () {
    test('cada idioma listado pode ser definido e fica refletido em T.idioma',
        () async {
      for (final m in T.idiomasDisponiveis) {
        final codigo = m['codigo']!;
        await T.definir(codigo);
        expect(T.idioma, codigo, reason: 'definir($codigo) não atualizou T.idioma');
      }
    });

    test('definir com código inválido é no-op (não troca T.idioma)', () async {
      await T.definir('pt');
      await T.definir('xx');
      expect(T.idioma, 'pt');
    });

    test('idiomaNotifier emite quando idioma muda', () async {
      await T.definir('pt');
      String? recebido;
      void listener() { recebido = T.idiomaNotifier.value; }
      T.idiomaNotifier.addListener(listener);
      try {
        await T.definir('en');
        expect(recebido, 'en');
      } finally {
        T.idiomaNotifier.removeListener(listener);
      }
    });
  });

  group('cobertura mínima por idioma (não-PT difere de PT)', () {
    // Conjunto representativo de getters de UI. Se algum cair fora porque
    // um idioma copiou o PT por engano, este teste pega.
    test('saudações, navegação, premium e tutorial diferem entre idiomas',
        () async {
      await T.definir('pt');
      final amostraPt = {
        'bomDia': T.bomDia,
        'salvar': T.salvar,
        'premiumChamada': T.premiumChamada,
        'tutorialPatioTexto': T.tutorialPatioTexto,
        'canalLembreteNome': T.canalLembreteNome,
      };

      for (final lang in ['en', 'es', 'de']) {
        await T.definir(lang);
        final amostra = {
          'bomDia': T.bomDia,
          'salvar': T.salvar,
          'premiumChamada': T.premiumChamada,
          'tutorialPatioTexto': T.tutorialPatioTexto,
          'canalLembreteNome': T.canalLembreteNome,
        };

        // Frases compostas/longas que devem diferir do PT em qualquer outro
        // idioma. Não incluímos cognatos curtos legítimos (ex.: "Continuar"
        // em PT e ES é a mesma palavra) nem nomes próprios ("Mentor",
        // "Biblioteca"/"Bibliothek" parcial, etc.).
        for (final chave in [
          'bomDia',
          'salvar',
          'premiumChamada',
          'tutorialPatioTexto',
          'canalLembreteNome',
        ]) {
          expect(amostra[chave], isNot(equals(amostraPt[chave])),
              reason: '$chave em "$lang" é idêntico ao PT — provável copy-paste');
        }
      }
    });
  });

  group('formatarData (calendário)', () {
    final d = DateTime(2025, 3, 7);

    test('PT/ES usam dd/MM/yyyy', () async {
      await T.definir('pt');
      expect(T.formatarData(d), '07/03/2025');
      await T.definir('es');
      expect(T.formatarData(d), '07/03/2025');
    });

    test('EN usa MM/dd/yyyy', () async {
      await T.definir('en');
      expect(T.formatarData(d), '03/07/2025');
    });

    test('DE usa dd.MM.yyyy', () async {
      await T.definir('de');
      expect(T.formatarData(d), '07.03.2025');
    });
  });

  group('formatarDiaMes (dia + mês abreviado)', () {
    test('PT/ES: "DD mes"', () async {
      await T.definir('pt');
      expect(T.formatarDiaMes(15, 1), '15 jan');
      await T.definir('es');
      expect(T.formatarDiaMes(15, 1), '15 ene');
    });

    test('EN: "Mes DD"', () async {
      await T.definir('en');
      expect(T.formatarDiaMes(15, 1), 'Jan 15');
    });

    test('DE: "DD. Mes."', () async {
      await T.definir('de');
      expect(T.formatarDiaMes(15, 1), '15. Jan.');
    });
  });

  group('nomeCategoria (compat enum novo + chave PT antiga)', () {
    test('enums ASCII (mind/body/discipline/relations/work) → tradução', () async {
      await T.definir('en');
      expect(T.nomeCategoria('mind'), T.catMente);
      expect(T.nomeCategoria('body'), T.catCorpo);
      expect(T.nomeCategoria('discipline'), T.catDisciplina);
      expect(T.nomeCategoria('relations'), T.catRelacoes);
      expect(T.nomeCategoria('work'), T.catTrabalho);
    });

    test('chaves antigas em PT (Mente/Corpo/...) ainda funcionam', () async {
      await T.definir('en');
      expect(T.nomeCategoria('Mente'), T.catMente);
      expect(T.nomeCategoria('Corpo'), T.catCorpo);
      expect(T.nomeCategoria('Disciplina'), T.catDisciplina);
      expect(T.nomeCategoria('Relações'), T.catRelacoes);
      expect(T.nomeCategoria('Trabalho'), T.catTrabalho);
    });

    test('categoria desconhecida volta como veio (categoria personalizada)',
        () async {
      await T.definir('pt');
      expect(T.nomeCategoria('Personalizado'), 'Personalizado');
    });
  });

  group('listas localizadas têm 4 idiomas com tamanho consistente', () {
    test('perguntasJardimManha tem 20 itens em cada idioma', () async {
      for (final lang in ['pt', 'en', 'es', 'de']) {
        await T.definir(lang);
        expect(T.perguntasJardimManha.length, 20,
            reason: 'perguntasJardimManha em "$lang" deveria ter 20 itens');
      }
    });

    test('frasesNotificacao tem 30 itens em cada idioma', () async {
      for (final lang in ['pt', 'en', 'es', 'de']) {
        await T.definir(lang);
        expect(T.frasesNotificacao.length, 30,
            reason: 'frasesNotificacao em "$lang" deveria ter 30 itens');
      }
    });

    test('bibliotecaPraticas tem as 5 categorias-enum em cada idioma',
        () async {
      for (final lang in ['pt', 'en', 'es', 'de']) {
        await T.definir(lang);
        expect(T.bibliotecaPraticas.keys.toSet(), {
          T.catKeyMente,
          T.catKeyCorpo,
          T.catKeyDisciplina,
          T.catKeyRelacoes,
          T.catKeyTrabalho,
        }, reason: 'chaves de bibliotecaPraticas em "$lang" estão fora do enum');
      }
    });
  });
}
