// Captura screenshots da paywall (TelaPremium) no Simulador iOS, no tamanho
// nativo do device escolhido (ex.: iPhone 16 Pro Max = 1320×2868, o set 6.9"
// exigido pela App Store, e o screenshot de review obrigatório de cada IAP).
//
// Como rodar (no Mac/Codemagic, com o simulador booted):
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshot_test.dart \
//     -d <UDID-do-simulador>
//
// O PNG sai em build/screenshots/ (escrito pelo driver). O render é 100% iOS;
// só os preços são de exemplo (injetados via Billing.debugProdutosOverride),
// o que é inevitável para um produto ainda não publicado nas lojas.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kairo/core/billing.dart';
import 'package:kairo/core/i18n.dart';
import 'package:kairo/core/kairo_tema.dart';
import 'package:kairo/telas/premium.dart';

// Produtos de exemplo (mesmos IDs/preços do plano — ver Billing._idsApple).
ProductDetails _fake({
  required String id,
  required String title,
  required String price,
  required double rawPrice,
}) =>
    ProductDetails(
      id: id,
      title: title,
      description: 'Kairo Premium',
      price: price,
      rawPrice: rawPrice,
      currencyCode: 'BRL',
      currencySymbol: r'R$',
    );

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paywall premium', (tester) async {
    // Boot mínimo (subconjunto do main.dart): só o necessário pra TelaPremium
    // renderizar. Supabase com placeholder — sem sessão, nenhuma chamada de rede;
    // refresh() vê currentUser == null e devolve "não premium" (estado de oferta).
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
    await T.carregarLocal();
    await KC.carregar();

    Billing.instance.debugProdutosOverride = [
      _fake(
        id: 'app.kairo.premium.monthly',
        title: 'Premium Mensal',
        price: r'R$ 19,90',
        rawPrice: 19.90,
      ),
      _fake(
        id: 'app.kairo.premium.yearly',
        title: 'Premium Anual',
        price: r'R$ 149,90',
        rawPrice: 149.90,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: kairoTema(),
        home: const TelaPremium(),
      ),
    );

    // Aguarda refresh() + produtos() resolverem e os botões de oferta surgirem.
    // Evitamos pumpAndSettle (timers do Supabase poderiam atrapalhar) — pumps
    // temporizados com saída antecipada quando a oferta já está na tela.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(ElevatedButton).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 600));

    // Android exige converter a surface antes de capturar (no iOS é dispensável).
    // Permite um pré-voo local em emulador Android antes de rodar no Codemagic.
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }

    await binding.takeScreenshot('paywall-premium');
  });
}
