import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../main.dart';

/// Eventos de compra observáveis pela UI (TelaPremium escuta [Billing.eventos]).
/// `nadaParaRestaurar`: restauração concluída sem nenhuma compra anterior —
/// caso comum em conta nova; sem ele a UI ficaria muda (exigência de UX e de
/// review da Apple: "Restore" precisa dar feedback sempre).
enum BillingEvento { processando, sucesso, restaurado, cancelada, erro, nadaParaRestaurar }

/// Camada de billing do client (In-App Purchase). A verdade da assinatura vive
/// em `public.subscriptions` (escrita só por service role via webhooks /
/// verify-purchase). Esta classe:
///   • lê o próprio estado (SELECT own, autorizado por RLS) — só display;
///   • lista os produtos das lojas e dispara a compra IAP nativa;
///   • após a compra, chama a Edge Function `verify-purchase` para desbloqueio
///     imediato (os webhooks Apple/Google são a fonte de verdade de renovação).
///
/// **Nunca** use `isPremium()` para decisão de cobrança/recurso pago — quem
/// decide é o servidor via `is_premium()` (ex.: gating no mentor-chat). Este
/// getter é só para exibição.
///
/// Conformidade Apple/Google: a compra é SEMPRE via IAP. Nenhum link externo de
/// pagamento (anti-steering). Um Premium comprado na web (Stripe) é honrado
/// silenciosamente pela leitura do entitlement.
class Billing {
  Billing._();
  static final Billing instance = Billing._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Product IDs por loja. iOS usa dois produtos de assinatura; Android usa um
  /// produto de assinatura (`premium`) cujos base plans mensal/anual vêm como
  /// ofertas. Devem casar com a App Store Connect / Play Console.
  static const Set<String> _idsApple  = {
    'app.kairo.premium.monthly',
    'app.kairo.premium.yearly',
  };
  static const Set<String> _idsGoogle = {'premium'};

  bool? _cache;
  DateTime? _periodoFim;
  String? _statusBruto;

  // Estado da restauração em andamento (ver [restaurar]).
  bool _restaurando = false;
  bool _streamAtivoNaRestauracao = false;

  /// Estado da última operação de compra, para a UI reagir (snackbar/aviso).
  final ValueNotifier<BillingEvento?> eventos = ValueNotifier<BillingEvento?>(null);

  /// Emite um evento garantindo a notificação mesmo quando repetido:
  /// ValueNotifier não notifica valor igual ao anterior, então dois "erro"
  /// seguidos deixariam a UI muda. O null intermediário é ignorado pelos
  /// listeners (todos fazem early-return em null).
  void _emitir(BillingEvento e) {
    eventos.value = null;
    eventos.value = e;
  }

  /// Última leitura conhecida do premium. `null` enquanto não consultado.
  bool? get cachePremium => _cache;
  /// Fim do período pago (apenas display).
  DateTime? get periodoFim => _periodoFim;
  /// Status bruto do entitlement (active/trialing/grace/...). Diagnóstico.
  String? get statusBruto => _statusBruto;

  Set<String> get _ids =>
      defaultTargetPlatform == TargetPlatform.android ? _idsGoogle : _idsApple;

  /// Inicia o listener global do `purchaseStream`. Chamar uma vez no boot
  /// (após `Supabase.initialize`). Idempotente.
  void init() {
    _sub ??= _iap.purchaseStream.listen(
      _aoAtualizarCompras,
      onError: (e) => debugPrint('[Billing] purchaseStream erro: $e'),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Lojas disponíveis (false em emulador sem conta/loja configurada).
  Future<bool> disponivel() => _iap.isAvailable();

  /// Lista os produtos de assinatura ofertados, ordenados por preço crescente
  /// (mensal antes de anual). Vazio se a loja estiver indisponível.
  Future<List<ProductDetails>> produtos() async {
    if (!await _iap.isAvailable()) {
      debugPrint('[Billing] loja indisponível (sem conta da loja no aparelho?)');
      return const [];
    }
    final resp = await _iap.queryProductDetails(_ids);
    if (resp.error != null) {
      debugPrint('[Billing] queryProductDetails: ${resp.error}');
    }
    if (resp.notFoundIDs.isNotEmpty) {
      // A loja respondeu mas não reconheceu estes IDs. No iOS as causas
      // típicas são: Paid Apps Agreement inativo, produto sem metadata
      // completa ("Ready to Submit"), ou produto recém-criado (propagação).
      debugPrint('[Billing] produtos NÃO encontrados na loja: ${resp.notFoundIDs}');
    }
    final lista = resp.productDetails.toList()
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    return lista;
  }

  /// Dispara a compra nativa do produto. A identidade do usuário viaja na
  /// compra: iOS `appAccountToken` / Android `obfuscatedAccountId` (ambos
  /// mapeados de `applicationUserName = user.id`, que é o UUID do Supabase).
  /// O resultado chega pelo `purchaseStream` ([_aoAtualizarCompras]).
  Future<void> comprar(ProductDetails p) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _emitir(BillingEvento.erro);
      return;
    }
    final param = PurchaseParam(productDetails: p, applicationUserName: user.id);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Reassocia compras anteriores (troca de aparelho / reinstalação). Os
  /// resultados chegam pelo `purchaseStream` como `restored` — mas quando NÃO
  /// há compra anterior o iOS não entrega NADA no stream (o plugin não expõe
  /// o "restore finished" do StoreKit). Por isso: emitimos `processando` já,
  /// e se o stream ficar mudo por uma janela curta, `nadaParaRestaurar` — a
  /// UI nunca fica sem resposta. Um `restored` que chegue depois da janela
  /// ainda é processado normalmente pelo handler.
  Future<void> restaurar() async {
    if (_restaurando) return; // ignora toque duplo durante a janela
    _restaurando = true;
    _streamAtivoNaRestauracao = false;
    _emitir(BillingEvento.processando);
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[Billing] restorePurchases falhou: $e');
      _restaurando = false;
      _emitir(BillingEvento.erro);
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    _restaurando = false;
    if (!_streamAtivoNaRestauracao) {
      _emitir(BillingEvento.nadaParaRestaurar);
    }
  }

  // ── Handler do purchaseStream ──────────────────────────────────────────────
  Future<void> _aoAtualizarCompras(List<PurchaseDetails> compras) async {
    // Qualquer entrega do stream durante uma restauração cancela o fallback
    // "nadaParaRestaurar" — o resultado real (restaurado/erro) prevalece.
    if (compras.isNotEmpty) _streamAtivoNaRestauracao = true;
    for (final c in compras) {
      switch (c.status) {
        case PurchaseStatus.pending:
          _emitir(BillingEvento.processando);
          break;
        case PurchaseStatus.error:
          _emitir(BillingEvento.erro);
          if (c.pendingCompletePurchase) await _iap.completePurchase(c);
          break;
        case PurchaseStatus.canceled:
          _emitir(BillingEvento.cancelada);
          if (c.pendingCompletePurchase) await _iap.completePurchase(c);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final ok = await _verificarNoServidor(c);
          if (c.pendingCompletePurchase) await _iap.completePurchase(c);
          _emitir(ok
              ? (c.status == PurchaseStatus.restored
                  ? BillingEvento.restaurado
                  : BillingEvento.sucesso)
              : BillingEvento.erro);
          break;
      }
    }
  }

  /// Envia o token à `verify-purchase` (re-busca o estado no provider, valida
  /// ownership e grava o entitlement) e atualiza o cache. Retorna true se o
  /// usuário ficou premium.
  Future<bool> _verificarNoServidor(PurchaseDetails c) async {
    try {
      final isGoogle = c is GooglePlayPurchaseDetails;
      final provider = isGoogle ? 'google' : 'apple';
      final token = isGoogle
          ? c.billingClientPurchase.purchaseToken
          : (c.purchaseID ?? '');
      if (token.isEmpty) {
        debugPrint('[Billing] compra sem token utilizável');
        return false;
      }
      final resp = await supabase.functions.invoke(
        'verify-purchase',
        body: {'provider': provider, 'token': token},
      );
      if (resp.status != 200) {
        debugPrint('[Billing] verify-purchase ${resp.status}: ${resp.data}');
        return false;
      }
      await refresh();
      return _cache == true;
    } catch (e) {
      debugPrint('[Billing] _verificarNoServidor falhou: $e');
      return false;
    }
  }

  // ── Leitura do entitlement (display) ───────────────────────────────────────

  /// Lê o estado atual da assinatura (sem cache). Critério premium idêntico ao
  /// `public.is_premium()`: status in ('active','trialing','grace') AND
  /// current_period_end > now.
  Future<bool> refresh() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _cache = false;
      _periodoFim = null;
      _statusBruto = null;
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
        return false;
      }

      final status = row['status'] as String?;
      final fimRaw = row['current_period_end'] as String?;
      final fim = fimRaw != null ? DateTime.tryParse(fimRaw) : null;

      _statusBruto = status;
      _periodoFim = fim;
      final ativo = derivarPremium(
        status: status,
        periodoFim: fim,
        agora: DateTime.now(),
      );
      _cache = ativo;
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

  /// Limpa o cache. Útil em logout, ou após o webhook ter convergido.
  void limparCache() {
    _cache = null;
    _periodoFim = null;
    _statusBruto = null;
  }

  /// Função pura — testável sem mockar Supabase. Mantém paridade EXATA com
  /// `public.is_premium()`: premium = status in (active, trialing, grace) AND
  /// current_period_end > now. Demais status (past_due/canceled/incomplete/
  /// unpaid/paused/expired/none) e período expirado NÃO concedem premium.
  /// `grace` = janela de retry de cobrança (Apple/Google) que ainda dá acesso.
  static bool derivarPremium({
    required String? status,
    required DateTime? periodoFim,
    required DateTime agora,
  }) {
    if (status != 'active' && status != 'trialing' && status != 'grace') {
      return false;
    }
    if (periodoFim == null) return false;
    return periodoFim.isAfter(agora);
  }
}
