import 'package:flutter/material.dart';
import '../core/kairo_tema.dart';
import '../core/billing.dart';
import '../core/i18n.dart';
import '../main.dart';

/// Paywall do Kairo Premium. Estado lido de `subscriptions` via [Billing];
/// pagamento via Stripe Checkout (URL externa, navegador do sistema).
///
/// Retorno via deep link `kairo://premium/sucesso|cancelado` é processado
/// pelo handler global em [KairoApp]; esta tela só ouve [deepLinkNotifier]
/// pra re-sincronizar via [Billing.refresh] e exibir feedback.
class TelaPremium extends StatefulWidget {
  const TelaPremium({super.key});

  @override
  State<TelaPremium> createState() => _TelaPremiumState();
}

class _TelaPremiumState extends State<TelaPremium> {
  bool _carregando = true;
  bool _abrindoCheckout = false;
  String? _erro;
  String? _aviso;
  late final VoidCallback _deepLinkListener;

  @override
  void initState() {
    super.initState();
    _carregarStatus();
    // Escuta retorno do Checkout (sucesso/cancelado).
    _deepLinkListener = _aoReceberDeepLink;
    deepLinkNotifier.addListener(_deepLinkListener);
  }

  @override
  void dispose() {
    deepLinkNotifier.removeListener(_deepLinkListener);
    super.dispose();
  }

  Future<void> _carregarStatus() async {
    await Billing.instance.refresh();
    if (!mounted) return;
    setState(() => _carregando = false);
  }

  void _aoReceberDeepLink() {
    final uri = deepLinkNotifier.value;
    if (uri == null) return;
    if (uri.scheme != 'kairo' || uri.host != 'premium') return;

    final sucesso = uri.path == '/sucesso';
    setState(() {
      _aviso = sucesso ? T.premiumRetornoSucesso : T.premiumRetornoCancelado;
      _erro = null;
    });
    if (sucesso) {
      // O webhook é assíncrono — em condição de corrida pode demorar alguns
      // segundos a propagar status='active'. Mostramos o aviso imediato e
      // damos um refresh agora; se ainda não convergiu, o cache será
      // atualizado na próxima abertura da tela.
      _carregarStatus();
    }
  }

  Future<void> _assinar() async {
    setState(() {
      _abrindoCheckout = true;
      _erro = null;
      _aviso = null;
    });
    try {
      final ok = await Billing.instance.abrirCheckout();
      if (!mounted) return;
      setState(() => _abrindoCheckout = false);
      if (!ok) setState(() => _erro = T.assinaturaErro);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _abrindoCheckout = false;
        _erro = T.assinaturaErro;
      });
    }
  }

  String _formatarData(DateTime d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final billing = Billing.instance;
    final premium = billing.cachePremium == true;
    final periodoFim = billing.periodoFim;

    return Scaffold(
      backgroundColor: KC.sumi,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back, color: KC.cinza, size: 22),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),

                      Text(T.premiumTitulo, style: KT.displayL()),
                      const SizedBox(height: 16),
                      Text(T.premiumChamada, style: KT.bodySerif(cor: KC.cinza)),

                      const SizedBox(height: 40),

                      // Estado atual
                      Text(
                        premium ? T.premiumAtivo : T.premiumGratuito,
                        style: KT.micro(cor: premium ? KC.kin : KC.fumo),
                      ),
                      if (premium && periodoFim != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${T.premiumAtivoAte} ${_formatarData(periodoFim)}',
                          style: KT.body(),
                        ),
                        const SizedBox(height: 12),
                        Text(T.premiumGerenciarStripe, style: KT.caption()),
                      ],

                      const SizedBox(height: 40),
                      KT.divisor(),
                      const SizedBox(height: 32),

                      // Benefícios
                      _Beneficio(texto: T.premiumBeneficioMentor),
                      const SizedBox(height: 16),
                      _Beneficio(texto: T.premiumBeneficioCarta),
                      const SizedBox(height: 16),
                      _Beneficio(texto: T.premiumBeneficioLimites),

                      if (_aviso != null) ...[
                        const SizedBox(height: 32),
                        Text(_aviso!, style: KT.caption(cor: KC.kin)),
                      ],
                      if (_erro != null) ...[
                        const SizedBox(height: 24),
                        Text(_erro!, style: KT.caption(cor: KC.aka)),
                      ],
                    ],
                  ),
                ),
              ),

              // Botão de assinatura (oculto quando já premium)
              if (!_carregando && !premium) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _abrindoCheckout ? null : _assinar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KC.washi,
                      foregroundColor: KC.sumi,
                      disabledBackgroundColor: KC.grafite,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _abrindoCheckout
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: KC.fundo,
                            ),
                          )
                        : Text(T.premiumAssinar, style: KT.body(cor: KC.fundo)),
                  ),
                ),
                const SizedBox(height: 32),
              ] else
                const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Beneficio extends StatelessWidget {
  final String texto;
  const _Beneficio({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 12),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: KC.kin,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Expanded(child: Text(texto, style: KT.body())),
      ],
    );
  }
}
