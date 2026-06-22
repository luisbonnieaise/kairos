import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/audio.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';

// ── RELAXA E DURMA ───────────────────────────────────────────────────────────
// Adormecer ouvindo um som. O áudio continua tocando com a tela desligada
// (player dedicado em KairoAudio) e desliga sozinho ao fim do tempo, com um
// fade suave. Toque longo na tela ativa também encerra.

class _SomDormir {
  final String nome;
  final String arquivo;
  const _SomDormir(this.nome, this.arquivo);
}

class _DuracaoDormir {
  final int minutos;
  final String rotulo;
  const _DuracaoDormir(this.minutos, this.rotulo);
}

// Listas construídas dinamicamente para refletir o idioma atual.
List<_SomDormir> get _ambientes => [
  _SomDormir(T.somChuva, 'chuva.mp3'),
  _SomDormir(T.somVento, 'vento.mp3'),
  _SomDormir(T.somSelva, 'selva.mp3'),
  _SomDormir(T.somBambu, 'bambu.mp3'),
];

List<_SomDormir> get _frequencias => [
  _SomDormir(T.freq432, 'freq-432.mp3'),
  _SomDormir(T.freq528, 'freq-528.mp3'),
  _SomDormir(T.freq396, 'freq-396.mp3'),
  _SomDormir(T.freq639, 'freq-639.mp3'),
  _SomDormir(T.freq783, 'freq-783.mp3'),
];

List<_DuracaoDormir> get _duracoes => [
  _DuracaoDormir(30, T.minutos(30)),
  _DuracaoDormir(60, T.horas(1)),
  _DuracaoDormir(120, T.horas(2)),
  _DuracaoDormir(480, T.aNoiteToda),
];

// ── TELA DE SELEÇÃO ──────────────────────────────────────────────────────────

class TelaDormirSelecao extends StatefulWidget {
  const TelaDormirSelecao({super.key});

  @override
  State<TelaDormirSelecao> createState() => _TelaDormirSelecaoState();
}

class _TelaDormirSelecaoState extends State<TelaDormirSelecao> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Tutorial.mostrar(
        context: context,
        chave: 'dormir',
        titulo: T.tutorialDormirTitulo,
        texto: T.tutorialDormirTexto,
      );
    });
  }

  void _iniciar(BuildContext context, _SomDormir som, int minutos) {
    HapticFeedback.lightImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => TelaDormir(
          arquivo: som.arquivo,
          nomeSom: som.nome,
          minutos: minutos,
        ),
        transitionsBuilder: (_, anim, _, child) =>
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
                    KT.tituloGradiente(T.relaxaEDurmaTitulo),
                    const SizedBox(height: 8),
                    Text(T.relaxaEDurmaSubtitulo, style: KT.caption()),

                    const SizedBox(height: 48),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    Text(T.gruposAmbientes, style: KT.micro()),
                    const SizedBox(height: 8),
                    for (final s in _ambientes)
                      _ItemSomDormir(
                        som: s,
                        aoTocar: () => _mostrarDuracoes(context, s),
                      ),

                    const SizedBox(height: 32),
                    Text(T.gruposFrequencias, style: KT.micro()),
                    const SizedBox(height: 8),
                    for (final s in _frequencias)
                      _ItemSomDormir(
                        som: s,
                        aoTocar: () => _mostrarDuracoes(context, s),
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

  void _mostrarDuracoes(BuildContext context, _SomDormir som) {
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
              Text(som.nome, style: KT.titulo()),
              const SizedBox(height: 4),
              Text(T.porQuantoTempo, style: KT.caption()),
              const SizedBox(height: 24),
              for (final d in _duracoes)
                _ItemDuracaoDormir(
                  duracao: d,
                  aoTocar: () {
                    Navigator.pop(ctx);
                    _iniciar(context, som, d.minutos);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemSomDormir extends StatelessWidget {
  final _SomDormir som;
  final VoidCallback aoTocar;

  const _ItemSomDormir({required this.som, required this.aoTocar});

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

class _ItemDuracaoDormir extends StatelessWidget {
  final _DuracaoDormir duracao;
  final VoidCallback aoTocar;

  const _ItemDuracaoDormir({required this.duracao, required this.aoTocar});

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
            Text(duracao.rotulo, style: KT.body()),
            const Spacer(),
            Icon(Icons.arrow_forward, size: 16, color: KC.fumo),
          ],
        ),
      ),
    );
  }
}

// ── SESSÃO ATIVA ─────────────────────────────────────────────────────────────

class TelaDormir extends StatefulWidget {
  final String arquivo;
  final String nomeSom;
  final int minutos;

  const TelaDormir({
    super.key,
    required this.arquivo,
    required this.nomeSom,
    required this.minutos,
  });

  @override
  State<TelaDormir> createState() => _TelaDormirState();
}

class _TelaDormirState extends State<TelaDormir>
    with TickerProviderStateMixin {
  static const double _volume = 0.7;
  Timer? _timer;
  bool _encerrando = false;
  late AnimationController _pulsoCtrl;
  late AnimationController _entradaCtrl;

  @override
  void initState() {
    super.initState();

    // Pulso lento e discreto no ícone (efeito calmante, sem brilho).
    _pulsoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    // Entrada da lua: surge pequena e apagada, cresce com o luar brotando.
    // Toca uma vez, em sincronia com o início do som.
    _entradaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      // Não inicia o áudio se a sessão já está sendo encerrada (ex.: toque
      // longo nos primeiros 400ms) — evitaria um "blip" de som no fade-out.
      if (!mounted || _encerrando) return;
      _entradaCtrl.forward();
      KairoAudio.tocarDormir(widget.arquivo, volume: _volume);
    });

    // Ao fim do tempo, encerra com fade suave.
    _timer = Timer(Duration(minutes: widget.minutos), () => _encerrar(suave: true));

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  Future<void> _encerrar({bool suave = false}) async {
    if (_encerrando) return;
    _encerrando = true;
    _timer?.cancel();

    // Fade-out: 8s ao fim do tempo, ~1,2s no encerramento manual.
    const passos = 20;
    final totalMs = suave ? 8000 : 1200;
    final intervalo = Duration(milliseconds: (totalMs / passos).round());
    for (int i = passos - 1; i >= 0; i--) {
      await KairoAudio.definirVolumeDormir(_volume * (i / passos));
      await Future.delayed(intervalo);
    }
    await KairoAudio.pararDormir();

    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulsoCtrl.dispose();
    _entradaCtrl.dispose();
    KairoAudio.pararDormir();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _encerrar(),
      child: Scaffold(
        backgroundColor: KC.sumi,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_entradaCtrl, _pulsoCtrl]),
                  builder: (_, child) {
                    // entrada: 0 -> 1 (uma vez); respiro: pulso contínuo.
                    final entrada =
                        Curves.easeOutCubic.transform(_entradaCtrl.value);
                    final t = Curves.easeInOut.transform(_pulsoCtrl.value);

                    // Escala: cresce de 0.6 ao tamanho cheio e depois respira
                    // de leve (±0.02), só após ter entrado.
                    final scale =
                        (0.6 + 0.4 * entrada) * (1.0 + 0.02 * (t * 2 - 1) * entrada);

                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            // Halo de luar: brota na entrada e pulsa devagar.
                            BoxShadow(
                              color: KC.acento
                                  .withValues(alpha: entrada * (0.10 + 0.16 * t)),
                              blurRadius: (8 + 18 * t) * entrada,
                              spreadRadius: 1 + 3 * entrada,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.nightlight_round,
                          size: 96,
                          color: KC.acento
                              .withValues(alpha: entrada * (0.45 + 0.25 * t)),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 48),
                Text(widget.nomeSom, style: KT.bodySerif(cor: KC.cinza)),
                const SizedBox(height: 8),
                Text(T.bomSono, style: KT.caption(cor: KC.fumo)),

                const SizedBox(height: 80),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Container(
                    decoration: BoxDecoration(
                      color: KC.card,
                      borderRadius: BorderRadius.circular(8),
                      border: KC.escuro ? null : Border.all(color: KC.linha, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: KC.escuro ? 0.22 : 0.07),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _encerrar(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KC.washi,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(T.encerrar, style: KT.body()),
                      ),
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
