import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/audio.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';

// ── TELA DE SELEÇÃO DO MODO SILÊNCIO ────────────────────────────────────────

// Opções de som ambiente
class _SomOpcao {
  final String nome;
  final String? arquivo; // null = silêncio
  const _SomOpcao(this.nome, this.arquivo);
}

// Lista construída dinamicamente para refletir o idioma atual
List<_SomOpcao> get _sons => [
  _SomOpcao(T.somSilencio, null),
  _SomOpcao(T.somChuva, 'chuva.mp3'),
  _SomOpcao(T.somVento, 'vento.mp3'),
  _SomOpcao(T.somBambu, 'bambu.mp3'),
];

class TelaSilencioSelecao extends StatefulWidget {
  const TelaSilencioSelecao({super.key});

  @override
  State<TelaSilencioSelecao> createState() => _TelaSilencioSelecaoState();
}

class _TelaSilencioSelecaoState extends State<TelaSilencioSelecao> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Tutorial.mostrar(
        context: context,
        chave: 'silencio',
        titulo: T.tutorialSilencioTitulo,
        texto: T.tutorialSilencioTexto,
      );
    });
  }

  void _iniciar(BuildContext context, TipoSilencio tipo, int minutos, String? som) {
    HapticFeedback.lightImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => TelaSilencio(
          tipo: tipo,
          minutos: minutos,
          somAmbiente: som,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KC.sumi,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: KC.cinza, size: 22),
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(T.modoSilencioTitulo, style: KT.displayL()),
                    const SizedBox(height: 8),
                    Text(T.pausaFocoPresenca, style: KT.caption()),

                    const SizedBox(height: 48),
                    Divider(color: KC.grafite, height: 1, thickness: 1),
                    const SizedBox(height: 32),

                    Text(T.variante, style: KT.micro()),
                    const SizedBox(height: 16),

                    _OpcaoSilencio(
                      titulo: T.focoProfundo,
                      descricao: T.focoProfundoDesc,
                      aoTocar: () => _mostrarDuracoes(context, TipoSilencio.focoProfundo),
                    ),
                    _OpcaoSilencio(
                      titulo: T.meditacao,
                      descricao: T.meditacaoDesc,
                      aoTocar: () => _mostrarDuracoes(context, TipoSilencio.meditacao),
                    ),
                    _OpcaoSilencio(
                      titulo: T.pausaEstrategica,
                      descricao: T.pausaEstrategicaDesc,
                      aoTocar: () => _mostrarSons(context, TipoSilencio.pausaEstrategica, 10),
                    ),
                    _OpcaoSilencio(
                      titulo: T.resetEmocional,
                      descricao: T.resetEmocionalDesc,
                      aoTocar: () => _mostrarSons(context, TipoSilencio.resetEmocional, 4),
                    ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDuracoes(BuildContext context, TipoSilencio tipo) {
    final tituloTraduzido = switch (tipo) {
      TipoSilencio.focoProfundo => T.focoProfundo,
      TipoSilencio.meditacao => T.meditacao,
      TipoSilencio.pausaEstrategica => T.pausaEstrategica,
      TipoSilencio.resetEmocional => T.resetEmocional,
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: KC.grafite,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(tituloTraduzido, style: KT.titulo()),
              const SizedBox(height: 4),
              Text(T.quantoTempo, style: KT.caption()),
              const SizedBox(height: 24),
              for (final m in [5, 15, 30, 60])
                _ItemDuracao(
                  minutos: m,
                  aoTocar: () {
                    Navigator.pop(ctx);
                    _mostrarSons(context, tipo, m);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarSons(BuildContext context, TipoSilencio tipo, int minutos) {
    final tituloTraduzido = switch (tipo) {
      TipoSilencio.focoProfundo => T.focoProfundo,
      TipoSilencio.meditacao => T.meditacao,
      TipoSilencio.pausaEstrategica => T.pausaEstrategica,
      TipoSilencio.resetEmocional => T.resetEmocional,
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: KC.grafite,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(tituloTraduzido, style: KT.titulo()),
              const SizedBox(height: 4),
              Text(T.somAmbientePergunta(minutos), style: KT.caption()),
              const SizedBox(height: 24),
              for (final s in _sons)
                _ItemSom(
                  som: s,
                  aoTocar: () {
                    Navigator.pop(ctx);
                    _iniciar(context, tipo, minutos, s.arquivo);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemSom extends StatelessWidget {
  final _SomOpcao som;
  final VoidCallback aoTocar;

  const _ItemSom({required this.som, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: aoTocar,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: KC.grafite, width: 1),
          ),
        ),
        child: Row(
          children: [
            Text(som.nome, style: KT.body()),
            const Spacer(),
            Icon(Icons.arrow_forward, size: 16, color: KC.fumo),
          ],
        ),
      ),
    );
  }
}

class _OpcaoSilencio extends StatelessWidget {
  final String titulo;
  final String descricao;
  final VoidCallback aoTocar;

  const _OpcaoSilencio({
    required this.titulo,
    required this.descricao,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: aoTocar,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: KT.body()),
            const SizedBox(height: 4),
            Text(descricao, style: KT.caption(cor: KC.fumo)),
          ],
        ),
      ),
    );
  }
}

class _ItemDuracao extends StatelessWidget {
  final int minutos;
  final VoidCallback aoTocar;

  const _ItemDuracao({required this.minutos, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: aoTocar,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: KC.grafite, width: 1),
          ),
        ),
        child: Row(
          children: [
            Text(T.minutos(minutos), style: KT.body()),
            const Spacer(),
            Icon(Icons.arrow_forward, size: 16, color: KC.fumo),
          ],
        ),
      ),
    );
  }
}

// ── TELA ATIVA: SESSÃO DE SILÊNCIO ───────────────────────────────────────────

/// Chaves internas pra identificar o tipo de variante (não traduzido).
enum TipoSilencio { focoProfundo, meditacao, pausaEstrategica, resetEmocional }

class TelaSilencio extends StatefulWidget {
  final TipoSilencio tipo;
  final int minutos;
  final String? somAmbiente;

  const TelaSilencio({
    super.key,
    required this.tipo,
    required this.minutos,
    this.somAmbiente,
  });

  String get tituloTraduzido => switch (tipo) {
        TipoSilencio.focoProfundo => T.focoProfundo,
        TipoSilencio.meditacao => T.meditacao,
        TipoSilencio.pausaEstrategica => T.pausaEstrategica,
        TipoSilencio.resetEmocional => T.resetEmocional,
      };

  @override
  State<TelaSilencio> createState() => _TelaSilencioState();
}

class _TelaSilencioState extends State<TelaSilencio>
    with TickerProviderStateMixin {
  Timer? _timer;
  late DateTime _inicio;
  bool _encerrando = false;
  bool _inspirando = true;

  late AnimationController _ensoCtrl;
  late AnimationController _respiracaoCtrl;

  @override
  void initState() {
    super.initState();
    _inicio = DateTime.now();

    _ensoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // Padrão 4-6 (4s inspira, 6s expira) — exalação estendida ativa o
    // parassimpático e induz estado de calma. Baseado em pesquisa de
    // respiração ressonante / vagal.
    _respiracaoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),         // inspira
      reverseDuration: const Duration(seconds: 6),  // expira
    );
    _respiracaoCtrl.addStatusListener((status) {
      if (!mounted) return;
      if (status == AnimationStatus.forward) {
        setState(() => _inspirando = true);
      } else if (status == AnimationStatus.reverse) {
        setState(() => _inspirando = false);
      }
    });
    _respiracaoCtrl.repeat(reverse: true);

    // Toca som ambiente em loop (se selecionado)
    if (widget.somAmbiente != null) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        KairoAudio.tocarAmbiente(widget.somAmbiente);
      });
    }

    // Timer pra encerrar automaticamente
    _timer = Timer(Duration(minutes: widget.minutos), _encerrar);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  Future<void> _encerrar() async {
    if (_encerrando) return;
    _encerrando = true;

    _timer?.cancel();
    await KairoAudio.pararAmbiente();
    HapticFeedback.mediumImpact();

    final duracao = DateTime.now().difference(_inicio);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _TelaFim(
          tipo: widget.tituloTraduzido,
          duracao: duracao,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    KairoAudio.pararAmbiente();
    _ensoCtrl.dispose();
    _respiracaoCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ehReset = widget.tipo == TipoSilencio.resetEmocional;
    final ehPausa = widget.tipo == TipoSilencio.pausaEstrategica;

    return GestureDetector(
      onLongPress: _encerrar,
      child: Scaffold(
        backgroundColor: KC.sumi,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (ehPausa) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      T.oQueImportaAgora,
                      style: KT.displayL(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 64),
                ],

                // Ensō girando ou círculo de respiração
                if (ehReset)
                  _CirculoRespiracao(controller: _respiracaoCtrl)
                else
                  _EnsoGirando(controller: _ensoCtrl),

                if (ehReset) ...[
                  const SizedBox(height: 48),
                  Text(
                    _inspirando ? T.inspire : T.expire,
                    style: KT.bodySerif(cor: KC.cinza),
                  ),
                ],

                const SizedBox(height: 80),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _encerrar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KC.washi,
                        side: BorderSide(color: KC.grafite, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(T.encerrar, style: KT.body()),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── ENSŌ GIRANDO LENTAMENTE ──────────────────────────────────────────────────

class _EnsoGirando extends StatelessWidget {
  final AnimationController controller;
  const _EnsoGirando({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Transform.rotate(
          angle: controller.value * 2 * math.pi,
          child: SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _EnsoPainter(),
            ),
          ),
        );
      },
    );
  }
}

class _EnsoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = KC.kin
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(2),
      -math.pi / 2,
      2 * math.pi * 0.92, // ensō aberto (8% de abertura)
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── CÍRCULO DE RESPIRAÇÃO ────────────────────────────────────────────────────

class _CirculoRespiracao extends StatelessWidget {
  final AnimationController controller;
  const _CirculoRespiracao({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(controller.value);
        final raio = 60.0 + t * 60.0; // 60 a 120

        return SizedBox(
          width: 200,
          height: 200,
          child: Center(
            child: Container(
              width: raio * 2,
              height: raio * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: KC.kin, width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── TELA DE FIM ──────────────────────────────────────────────────────────────

class _TelaFim extends StatelessWidget {
  final String tipo;
  final Duration duracao;

  const _TelaFim({required this.tipo, required this.duracao});

  String _formatarDuracao() {
    final mins = duracao.inMinutes;
    if (mins == 0) return T.minutos(0);
    return T.minutos(mins);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KC.sumi,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: KC.kin, width: 1.5),
                ),
              ),
              const SizedBox(height: 32),

              Text(_formatarDuracao().toUpperCase(), style: KT.micro(cor: KC.kin)),
              const SizedBox(height: 12),

              Text(T.ritmoSeSustenta, style: KT.displayL()),
              const SizedBox(height: 16),
              Text(T.volteAoDia, style: KT.bodySerif(cor: KC.cinza)),

              const SizedBox(height: 64),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KC.washi,
                    side: BorderSide(color: KC.grafite, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.voltar, style: KT.body()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
