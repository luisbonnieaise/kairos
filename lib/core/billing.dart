import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../main.dart';

/// Camada de billing do client (Fase 07 — multiplataforma).
///
/// A verdade do entitlement vive em `public.subscriptions` (escrita SÓ pelos
/// webhooks/verify-purchase via service role). Esta classe:
///   • lê o próprio estado (SELECT own, autorizado por RLS) — só p/ display;
///   • vende a assinatura via IAP nativo (StoreKit 2 no iOS, Play Billing no
///     Android), carregando a identidade Supabase (user.id) na compra;
///   • após a compra, confirma no `verify-purchase` (desbloqueio imediato).
///
/// **Nunca** decida Premium localmente para liberar recurso pago — quem decide
/// é o servidor via `is_premium()`. `isPremium()` aqui é só para a UI.
class Billing {
  Billing._();
  static final Billing instance = Billing._();

  /// IDs de produto configurados nas lojas (ver docs/08-guia-consoles-luis.md).
  /// iOS: dois produtos de assinatura. Android: um produto `premium` com base
  /// plans mensal/anual (o offer é escolhido no fluxo de compra).
  static const _idsApple = {'app.kairo.premium.monthly', 'app.kairo.premium.yearly'};
  static const _idsGoogle = {'premium'};

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _assinaturaStream;

  bool? _cache;
  DateTime? _periodoFim;
  String? _statusBruto;

  /// SOMENTE para testes/screenshots (integration_test). Quando setado, [produtos]
  /// devolve esta lista em vez de consultar a loja — assim a paywall renderiza
  /// com preços de exemplo no Simulador iOS, sem depender de StoreKit/Play.
  /// NUNCA afeta entitlement: [refresh]/[isPremium] continuam vindo do servidor.
  @visibleForTesting
  List<ProductDetails>? debugProdutosOverride;

  /// Pinga a cada [refresh] — a UI escuta para re-renderizar quando o estado
  /// converge (ex.: após o verify-purchase confirmar a compra).
  final ValueNotifier<int> mudancas = ValueNotifier<int>(0);

  bool? get cachePremium => _cache;
  DateTime? get periodoFim => _periodoFim;
  String? get statusBruto => _statusBruto;

  Set<String> get _idsProdutos =>
      Platform.isIOS ? _idsApple : _idsGoogle;

  String get _providerAtual => Platform.isIOS ? 'apple' : 'google';

  /// Inicia o listener do fluxo de compras. Idempotente — chame no boot.
  /// Cada evento purchased/restored é verificado no servidor antes de liberar.
  void iniciar() {
    _assinaturaStream ??= _iap.purchaseStream.listen(
      _aoAtualizarCompras,
      onError: (Object e) => debugPrint('[Billing] purchaseStream erro: $e'),
    );
  }

  void dispose() {
    _assinaturaStream?.cancel();
    _assinaturaStream = null;
  }

  /// Lê o estado atual da assinatura (sem cache). Critério premium idêntico ao
  /// SQL `is_premium()`: status in (active,trialing,grace) AND period_end > now.
  Future<bool> refresh() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _cache = false;
      _periodoFim = null;
      _statusBruto = null;
      mudancas.value++;
      return false;
    }
    try {
      final row = await supabase
          .from('subscriptions')
          .select('status, current_period_end')
          .eq('user_id', user.id)
          .maybeSingle();

      if (row == null) {
        _cache = false;
        _periodoFim = null;
        _statusBruto = 'none';
        mudancas.value++;
        return false;
      }

      final status = row['status'] as String?;
      final fimRaw = row['current_period_end'] as String?;
      final fim = fimRaw != null ? DateTime.tryParse(fimRaw) : null;

      _statusBruto = status;
      _periodoFim = fim;
      final ativo = derivarPremium(status: status, periodoFim: fim, agora: DateTime.now());
      _cache = ativo;
      mudancas.value++;
      return ativo;
    } catch (e) {
      debugPrint('[Billing] refresh falhou: $e');
      return _cache ?? false;
    }
  }

  /// Premium do cache se disponível; senão dispara um refresh.
  Future<bool> isPremium() async {
    final c = _cache;
    if (c != null) return c;
    return refresh();
  }

  /// Produtos de assinatura disponíveis nas lojas. Vazio se IAP indisponível.
  Future<List<ProductDetails>> produtos() async {
    final override = debugProdutosOverride;
    if (override != null) return override;
    final disponivel = await _iap.isAvailable();
    if (!disponivel) return const [];
    final resposta = await _iap.queryProductDetails(_idsProdutos);
    if (resposta.error != null) {
      debugPrint('[Billing] queryProductDetails: ${resposta.error}');
    }
    return resposta.productDetails;
  }

  /// Inicia a compra de uma assinatura. Carrega a identidade Supabase:
  ///   • iOS (StoreKit 2): appAccountToken = user.id (UUID).
  ///   • Android (Play Billing): obfuscatedAccountId = user.id (via
  ///     applicationUserName, mapeado pelo plugin).
  /// O resultado chega de forma assíncrona em [_aoAtualizarCompras].
  Future<void> comprar(ProductDetails produto) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('sessao_invalida');

    late final PurchaseParam param;
    if (Platform.isIOS) {
      // StoreKit 2: appAccountToken (UUID) viaja com a transação e volta na
      // App Store Server API — é como o verify-purchase amarra a compra ao user.
      param = AppStorePurchaseParam(
        productDetails: produto,
        applicationUserName: user.id,
      );
    } else {
      param = PurchaseParam(
        productDetails: produto,
        applicationUserName: user.id,
      );
    }
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Reassocia compras já feitas (troca de aparelho, reinstalação).
  Future<void> restaurar() => _iap.restorePurchases();

  /// Limpa o cache (logout / pós-convergência do webhook).
  void limparCache() {
    _cache = null;
    _periodoFim = null;
    _statusBruto = null;
  }

  // ── Fluxo de compras ────────────────────────────────────────────────────
  Future<void> _aoAtualizarCompras(List<PurchaseDetails> compras) async {
    for (final compra in compras) {
      switch (compra.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verificarNoServidor(compra);
          break;
        case PurchaseStatus.error:
          debugPrint('[Billing] compra erro: ${compra.error}');
          break;
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
      // Sempre finalizar pendências para destravar a fila da loja.
      if (compra.pendingCompletePurchase) {
        await _iap.completePurchase(compra);
      }
    }
  }

  /// Envia o token da compra ao verify-purchase (desbloqueio imediato) e
  /// atualiza o cache. A fonte de verdade segue sendo o webhook assíncrono.
  Future<void> _verificarNoServidor(PurchaseDetails compra) async {
    final token = _tokenDe(compra);
    if (token == null) {
      debugPrint('[Billing] sem token verificável na compra ${compra.productID}');
      return;
    }
    try {
      final resposta = await supabase.functions.invoke(
        'verify-purchase',
        body: {'provider': _providerAtual, 'token': token},
      );
      if (resposta.status != 200) {
        debugPrint('[Billing] verify-purchase ${resposta.status}: ${resposta.data}');
      }
    } catch (e) {
      debugPrint('[Billing] verify-purchase falhou: $e');
    }
    await refresh();
  }

  /// Extrai o token que o verify-purchase precisa:
  ///   • Apple: transactionId (a App Store Server API resolve original/
  ///     transactionId indistintamente).
  ///   • Google: purchaseToken.
  String? _tokenDe(PurchaseDetails compra) {
    if (Platform.isIOS) {
      final id = compra.purchaseID;
      return (id != null && id.isNotEmpty) ? id : null;
    }
    if (compra is GooglePlayPurchaseDetails) {
      return compra.billingClientPurchase.purchaseToken;
    }
    return null;
  }

  /// Função pura, testável. Paridade EXATA com `public.is_premium()`:
  /// premium = status in (active, trialing, grace) AND current_period_end > now.
  static bool derivarPremium({
    required String? status,
    required DateTime? periodoFim,
    required DateTime agora,
  }) {
    if (status != 'active' && status != 'trialing' && status != 'grace') return false;
    if (periodoFim == null) return false;
    return periodoFim.isAfter(agora);
  }
}
