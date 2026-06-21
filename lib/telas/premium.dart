import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/kairo_tema.dart';
import '../core/billing.dart';
import '../core/i18n.dart';
import 'portao.dart' show kUrlTermos, kUrlPrivacidade;

/// Paywall do Kairo Premium — compra via IAP nativo (StoreKit / Play Billing).
///
/// Conformidade Apple/Google (crítico): mostra SOMENTE a compra in-app, com
/// preço vindo das lojas (`ProductDetails`). NENHUM preço de site, link externo
/// ou menção a checkout web (anti-steering). Inclui "Restaurar compras". Se o
/// usuário já é Premium (inclusive comprado na web/Stripe), a oferta sai e
/// mostramos só o estado "Ativo até <data>".
class TelaPremium extends StatefulWidget {
  const TelaPremium({super.key});

  @override
  State<TelaPremium> createState() => _TelaPremiumState();
}

class _TelaPremiumState extends State<TelaPremium> {
  bool _carregando = true;
  bool _processando = false;
  List<ProductDetails> _produtos = const [];
  String? _erro;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    Billing.instance.eventos.addListener(_aoEvento);
    _carregar();
  }

  @override
  void dispose() {
    Billing.instance.eventos.removeListener(_aoEvento);
    super.dispose();
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

  // Reage aos eventos do purchaseStream (Billing.eventos).
  void _aoEvento() {
    final ev = Billing.instance.eventos.value;
    if (ev == null || !mounted) return;
    switch (ev) {
      case BillingEvento.processando:
        setState(() {
          _processando = true;
          _erro = null;
          _aviso = null;
        });
        break;
      case BillingEvento.sucesso:
        setState(() {
          _processando = false;
          _aviso = T.premiumCompraSucesso;
          _erro = null;
        });
        Billing.instance.refresh().then((_) {
          if (mounted) setState(() {});
        });
        break;
      case BillingEvento.restaurado:
        setState(() {
          _processando = false;
          _aviso = T.premiumRestaurado;
          _erro = null;
        });
        Billing.instance.refresh().then((_) {
          if (mounted) setState(() {});
        });
        break;
      case BillingEvento.cancelada:
        setState(() {
          _processando = false;
          _aviso = T.premiumCompraCancelada;
          _erro = null;
        });
        break;
      case BillingEvento.nadaParaRestaurar:
        // Restauração sem compra anterior: aviso neutro, não erro.
        setState(() {
          _processando = false;
          _aviso = T.premiumNadaRestaurar;
          _erro = null;
        });
        break;
      case BillingEvento.erro:
        setState(() {
          _processando = false;
          _erro = T.assinaturaErro;
          _aviso = null;
        });
        break;
    }
  }

  Future<void> _assinar(ProductDetails p) async {
    setState(() {
      _erro = null;
      _aviso = null;
    });
    await Billing.instance.comprar(p);
  }

  Future<void> _restaurar() async {
    setState(() {
      _erro = null;
      _aviso = null;
    });
    await Billing.instance.restaurar();
  }

  Future<void> _abrirLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                          '${T.premiumAtivoAte} ${T.formatarData(periodoFim)}',
                          style: KT.body(),
                        ),
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

                      // Oferta de planos (oculta quando já premium)
                      if (!_carregando && !premium) ...[
                        const SizedBox(height: 40),
                        if (_produtos.isEmpty) ...[
                          Text(T.premiumSemProdutos, style: KT.caption(cor: KC.fumo)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _processando
                                ? null
                                : () {
                                    setState(() => _carregando = true);
                                    _carregar();
                                  },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                            ),
                            child: Text(
                              T.premiumTentarNovamente,
                              style: KT.caption(cor: KC.kin),
                            ),
                          ),
                        ] else ...[
                          ..._produtos.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _CartaoPlano(
                                produto: p,
                                habilitado: !_processando,
                                onTap: () => _assinar(p),
                              ),
                            ),
                          ),
                          // Disclosure obrigatório (Apple 3.1.2): trial grátis +
                          // renovação automática + Termos de Uso/Privacidade.
                          const SizedBox(height: 16),
                          Text(T.premiumTermosRenovacao,
                              style: KT.caption(cor: KC.fumo)),
                          const SizedBox(height: 12),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('${T.portaoAoAssinar} ',
                                  style: KT.caption(cor: KC.fumo)),
                              GestureDetector(
                                onTap: () => _abrirLink(kUrlTermos),
                                child: Text(T.termosDeUso,
                                    style: KT.caption(cor: KC.cinza)),
                              ),
                              Text(' ${T.conector_e} ',
                                  style: KT.caption(cor: KC.fumo)),
                              GestureDetector(
                                onTap: () => _abrirLink(kUrlPrivacidade),
                                child: Text(T.politicaPrivacidade,
                                    style: KT.caption(cor: KC.cinza)),
                              ),
                              Text('.', style: KT.caption(cor: KC.fumo)),
                            ],
                          ),
                        ],
                      ],

                      if (_aviso != null) ...[
                        const SizedBox(height: 24),
                        Text(_aviso!, style: KT.caption(cor: KC.kin)),
                      ],
                      if (_erro != null) ...[
                        const SizedBox(height: 16),
                        Text(_erro!, style: KT.caption(cor: KC.aka)),
                      ],
                    ],
                  ),
                ),
              ),

              // Restaurar compras (sempre disponível; exigência das lojas).
              if (!_carregando) ...[
                Center(
                  child: TextButton(
                    onPressed: _processando ? null : _restaurar,
                    child: Text(T.premiumRestaurar, style: KT.caption(cor: KC.cinza)),
                  ),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de um plano de assinatura. Título e preço vêm do `ProductDetails`
/// (nunca hardcoded — exigência de conformidade e de moeda/localização).
class _CartaoPlano extends StatelessWidget {
  final ProductDetails produto;
  final bool habilitado;
  final VoidCallback onTap;
  const _CartaoPlano({
    required this.produto,
    required this.habilitado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: habilitado ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: KC.washi,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(produto.title, style: KT.body(cor: KC.fundo)),
                    const SizedBox(height: 4),
                    Text(produto.price, style: KT.caption(cor: KC.sumi)),
                  ],
                ),
              ),
              Text(T.premiumAssinar, style: KT.body(cor: KC.fundo)),
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
