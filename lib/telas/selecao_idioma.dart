import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/i18n.dart';
import 'provocacao.dart';

/// Seta minimalista em estilo de pincel oriental — uma linha fina horizontal
/// com uma pequena ponta angular do lado direito. Sem curvas, sem peso visual.
class _SetaOriental extends CustomPainter {
  final Color cor;
  _SetaOriental({required this.cor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final meio = size.height / 2;
    final inicio = Offset(0, meio);
    final fim = Offset(size.width, meio);
    // Linha horizontal
    canvas.drawLine(inicio, fim, paint);
    // Ponta — duas linhas curtas formando o ângulo
    final ponta = size.width;
    final altura = size.height * 0.45;
    canvas.drawLine(Offset(ponta - altura, meio - altura), fim, paint);
    canvas.drawLine(Offset(ponta - altura, meio + altura), fim, paint);
  }

  @override
  bool shouldRepaint(_SetaOriental old) => old.cor != cor;
}

class TelaSelecaoIdioma extends StatefulWidget {
  const TelaSelecaoIdioma({super.key});

  @override
  State<TelaSelecaoIdioma> createState() => _TelaSelecaoIdiomaState();
}

class _TelaSelecaoIdiomaState extends State<TelaSelecaoIdioma> {
  String _selecionado = T.idioma;

  Future<void> _confirmar() async {
    HapticFeedback.lightImpact();
    await T.definir(_selecionado);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const TelaProvocacao(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KC.sumi,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              ...T.idiomasDisponiveis.map((idioma) {
                final codigo = idioma['codigo']!;
                final nomeNativo = idioma['nomeNativo']!;
                final selecionado = _selecionado == codigo;
                return _OpcaoIdioma(
                  nome: nomeNativo,
                  selecionado: selecionado,
                  aoTocar: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selecionado = codigo);
                  },
                );
              }),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirmar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KC.washi,
                    foregroundColor: KC.sumi,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: CustomPaint(
                    size: const Size(36, 14),
                    painter: _SetaOriental(cor: KC.sumi),
                  ),
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpcaoIdioma extends StatelessWidget {
  final String nome;
  final bool selecionado;
  final VoidCallback aoTocar;

  const _OpcaoIdioma({
    required this.nome,
    required this.selecionado,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: aoTocar,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          border: Border.all(
            color: selecionado ? KC.kin : KC.grafite,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(child: Text(nome, style: KT.body())),
            if (selecionado)
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: KC.kin, width: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
