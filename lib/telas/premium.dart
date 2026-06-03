import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../core/kairo_tema.dart';
import '../core/billing.dart';
import '../core/i18n.dart';

/// Paywall do Kairo Premium (Fase 07 — IAP nativo).
///
/// CONFORMIDADE (crítico, Apple 3.1.1 / Google):
///   • No mobile mostra SOMENTE a compra via IAP (produtos das lojas).
///   • ZERO menção/link ao site, preço da web ou "assine mais barato fora".
///   • Se o usuário já é Premium (inclusive comprado na web via Stripe), mostra
///     "Ativo até <data>" e ESCONDE a oferta de compra (honra multiplataforma).
///
/// O preço exibido vem do `ProductDetails` da loja — nunca hardcoded.
class TelaPremium extends StatefulWidget {
  const TelaPremium({super.key});

  @override
  State<TelaPremium> createState() => _TelaPremiumState();
}

class _TelaPremiumState extends State<TelaPremium> {
  bool _carregando = true;
  bool _processando = false;
  String? _erro;
  String? _aviso;
  List<ProductDetails> _produtos = const [];

  @override
  void initState() {
    super.initState();
    Billing.instance.mudancas.addListener(_aoMudarEstado);
    _carregar();
  }

  @override
  void dispose() {
    Billing.instance.mudancas.removeListener(_aoMudarEstado);
    super.dispose();
  }

  void _aoMudarEstado() {
    if (!mounted) return;
    // O estado convergiu (ex.: verify-purchase confirmou). Re-renderiza e tira
    // o "processando" se já virou Premium.
    setState(() {
      if (Billing.instance.cachePremium == true) {
        _processando = false;
        _aviso = T.premiumRetornoSucesso;
      }
    });
  }

  Future<void> _carregar() async {
    await Billing.instance.refresh();
    final produtos = await Billing.instance.produtos();
    if (!mounted) return;
    setState(() {
      _produtos = produtos;
      _carregando = false;
    });
  }

  Future<void> _assinar(ProductDetails produto) async {
    setState(() {
      _processando = true;
      _erro = null;
      _aviso = null;
    });
    try {
      await Billing.instance.comprar(produto);
      // O resultado chega assíncrono pelo purchaseStream → verify-purchase →
      // refresh → _aoMudarEstado. Não setamos Premium aqui.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _processando = false;
        _erro = T.assinaturaErro;
      });
    }
  }

  Future<void> _restaurar() async {
    setState(() {
      _erro = null;
      _aviso = null;
    });
    try {
      await Billing.instance.restaurar();
      if (!mounted) return;
      setState(() => _aviso = T.premiumRestaurado);
    } catch (_) {
      if (!mounted) return;
      setState(() => _erro = T.assinaturaErro);
    }
  }

  String _rotuloProduto(ProductDetails p) => '${p.title} · ${p.price}';

  @override
  Widget build(BuildContext context) {
    final billing = Billing.instance;
    final premium = billing.cachePremium == true;
    final periodoFim = billing.periodoFim;
    final lojaIndisponivel = !_carregando && !premium && _produtos.isEmpty;

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
                          '${T.premiumAtivoAte} ${T.formatarData(periodoFim)}',
                          style: KT.body(),
                        ),
                        const SizedBox(height: 12),
                        Text(T.premiumGerenciarLoja, style: KT.caption()),
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

                      if (lojaIndisponivel) ...[
                        const SizedBox(height: 32),
                        Text(T.premiumIndisponivel, style: KT.caption(cor: KC.fumo)),
                      ],
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

              // Oferta de compra — oculta quando já é Premium (honra web/IAP).
              if (!_carregando && !premium) ...[
                for (final produto in _produtos) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _processando ? null : () => _assinar(produto),
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
                      child: _processando
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: KC.fundo,
                              ),
                            )
                          : Text('${T.premiumAssinar} · ${_rotuloProduto(produto)}',
                              style: KT.body(cor: KC.fundo)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_produtos.isNotEmpty) ...[
                  Center(
                    child: TextButton(
                      onPressed: _processando ? null : _restaurar,
                      child: Text(T.premiumRestaurar, style: KT.caption(cor: KC.cinza)),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
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
