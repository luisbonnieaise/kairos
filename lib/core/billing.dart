import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

/// Camada de billing do client. A verdade da assinatura vive em
/// `public.subscriptions` (escrita só pelo webhook). Esta classe apenas:
///   • lê o próprio estado (SELECT own, autorizado por RLS),
///   • aciona o Stripe Checkout via Edge Function (sem segredo no client),
///   • mantém um cache de sessão pra evitar 1 round-trip por tela.
///
/// **Nunca** use `isPremium()` para decisão de cobrança/modelo — quem decide
/// é o servidor via `is_premium()`. Este getter é só pra display.
class Billing {
  Billing._();
  static final Billing instance = Billing._();

  /// Deep links de retorno do Checkout. Devem casar com o scheme `kairo://`
  /// declarado em AndroidManifest.xml e Info.plist e com o whitelist de
  /// `urlPermitida` na Edge Function stripe-checkout.
  static const successUrl = 'kairo://premium/sucesso';
  static const cancelUrl  = 'kairo://premium/cancelado';

  bool? _cache;
  DateTime? _periodoFim;
  String? _statusBruto;

  /// Última leitura conhecida. `null` enquanto ainda não foi consultado.
  bool? get cachePremium => _cache;
  /// Data de fim do período pago (apenas display).
  DateTime? get periodoFim => _periodoFim;
  /// Status bruto da Stripe (active, trialing, past_due, ...). Para diagnóstico.
  String? get statusBruto => _statusBruto;

  /// Lê o estado atual da assinatura. Sem cache.
  /// Critério premium: status in ('active','trialing') AND current_period_end > now.
  /// É o MESMO critério da função SQL `is_premium()` — mantemos paridade
  /// pra evitar inconsistência entre display e gating real.
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
      final ativo = (status == 'active' || status == 'trialing')
          && fim != null
          && fim.isAfter(DateTime.now());
      _cache = ativo;
      return ativo;
    } catch (e) {
      debugPrint('[Billing] refresh falhou: $e');
      // Mantém o cache anterior (se houver) para não regredir a UI por
      // erro transitório de rede. Se nunca leu, fica null.
      return _cache ?? false;
    }
  }

  /// Retorna o premium do cache se disponível; senão dispara um refresh.
  Future<bool> isPremium() async {
    final c = _cache;
    if (c != null) return c;
    return refresh();
  }

  /// Cria a Checkout Session via Edge Function e retorna a URL hospedada
  /// na Stripe. O caller é responsável por abrir essa URL no navegador
  /// externo (ver [abrirCheckout]).
  Future<String> iniciarCheckout() async {
    final resposta = await supabase.functions.invoke(
      'stripe-checkout',
      body: {
        'success_url': successUrl,
        'cancel_url':  cancelUrl,
      },
    );

    if (resposta.status != 200) {
      debugPrint('[Billing] stripe-checkout retornou ${resposta.status}: ${resposta.data}');
      throw Exception('assinatura_erro');
    }
    final data = resposta.data as Map<String, dynamic>?;
    if (data == null || data['error'] != null) {
      debugPrint('[Billing] stripe-checkout error: ${data?['error']}');
      throw Exception('assinatura_erro');
    }
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('assinatura_erro');
    }
    return url;
  }

  /// Conveniência: inicia o checkout e abre a URL no navegador externo.
  /// Devolve `true` se conseguiu abrir.
  Future<bool> abrirCheckout() async {
    final url = await iniciarCheckout();
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Customer Portal (gerenciar/cancelar assinatura). Ainda não implementado
  /// — exige Edge Function `stripe-portal` que crie a billing_portal.Session.
  /// Por enquanto, o usuário cancela direto pela Stripe (e-mail de recibo
  /// traz o link "Manage subscription") ou via suporte.
  Future<void> abrirPortal() async {
    throw UnimplementedError(
      'Customer Portal: criar Edge Function stripe-portal e implementar aqui.',
    );
  }

  /// Limpa o cache. Útil em logout, ou após o webhook ter convergido.
  void limparCache() {
    _cache = null;
    _periodoFim = null;
    _statusBruto = null;
  }
}
