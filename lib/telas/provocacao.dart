import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/i18n.dart';
import '../main.dart';

class TelaProvocacao extends StatefulWidget {
  const TelaProvocacao({super.key});

  @override
  State<TelaProvocacao> createState() => _TelaProvocacaoState();
}

class _TelaProvocacaoState extends State<TelaProvocacao>
    with SingleTickerProviderStateMixin {
  int _linhasVisiveis = 0;
  bool _liberado = false;
  late final List<String> _linhas;
  late final AnimationController _pulsoCtrl;

  @override
  void initState() {
    super.initState();
    _linhas = [T.prov1, T.prov2, T.prov3, T.prov4];

    _pulsoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _animarLinhas();
  }

  Future<void> _animarLinhas() async {
    final inicio = DateTime.now();

    // Linhas aparecem com 600ms entre cada uma
    for (int i = 0; i < _linhas.length; i++) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _linhasVisiveis = i + 1);
    }

    // Garante mínimo de 5 segundos antes de liberar swipe
    final passado = DateTime.now().difference(inicio).inMilliseconds;
    final restante = 5000 - passado;
    if (restante > 0) {
      await Future.delayed(Duration(milliseconds: restante));
    }

    if (mounted) setState(() => _liberado = true);
  }

  void _avancar() {
    if (!_liberado) return;
    HapticFeedback.lightImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const TelaBoasVindas(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _pulsoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Swipe vertical (qualquer direção)
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 100) _avancar();
      },
      // Swipe horizontal também avança (UX mais flexível)
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 100) _avancar();
      },
      child: Scaffold(
        backgroundColor: KC.sumi,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_linhas.length, (i) {
                    return AnimatedOpacity(
                      opacity: i < _linhasVisiveis ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 600),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _linhas[i],
                          style: KT.displayL(
                            cor: i % 2 == 0 ? KC.washi : KC.cinza,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 100),

              // Linha pulsante (só aparece quando liberado)
              AnimatedOpacity(
                opacity: _liberado ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 800),
                child: Column(
                  children: [
                    Text(T.deslizePraContinuar, style: KT.micro(cor: KC.fumo)),
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: Tween(begin: 0.25, end: 1.0).animate(
                        CurvedAnimation(parent: _pulsoCtrl, curve: Curves.easeInOut),
                      ),
                      child: Container(width: 48, height: 1, color: KC.cinza),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
