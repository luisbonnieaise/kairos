import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/claude_api.dart';
import '../core/banco.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';

class TelaMentor extends StatefulWidget {
  const TelaMentor({super.key});

  @override
  State<TelaMentor> createState() => _TelaMentorState();
}

class _TelaMentorState extends State<TelaMentor> {
  final List<_Mensagem> _mensagens = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _pensando = false;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Tutorial.mostrar(
        context: context,
        chave: 'mentor',
        titulo: T.tutorialMentorTitulo,
        texto: T.tutorialMentorTexto,
      );
    });
  }

  Future<void> _carregarHistorico() async {
    try {
      final salvas = await BancoMensagens.carregar();
      final perfil = await BancoPerfil.carregar();
      final nome = (perfil?['nome'] as String?)?.trim() ?? '';

      if (!mounted) return;

      setState(() {
        if (salvas.isEmpty) {
          _mensagens.add(_Mensagem(texto: T.mentorSaudacao(nome), doMentor: true));
        } else {
          for (final m in salvas) {
            _mensagens.add(_Mensagem(
              texto: m['conteudo'] as String,
              doMentor: m['role'] == 'assistant',
            ));
          }
        }
      });

      _rolarParaBaixo();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mensagens.add(_Mensagem(
          texto: T.mentorSaudacao(''),
          doMentor: true,
        ));
      });
    }
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _pensando) return;

    HapticFeedback.lightImpact();

    setState(() {
      _mensagens.add(_Mensagem(texto: texto, doMentor: false));
      _controller.clear();
      _pensando = true;
    });

    _rolarParaBaixo();

    // Salva a mensagem do usuário em paralelo (não bloqueia a resposta)
    BancoMensagens.salvar(role: 'user', conteudo: texto);

    try {
      final inicio = DateTime.now();

      final historico = _mensagens
          .where((m) => !(m == _mensagens.first && m.doMentor))
          .map((m) => {
                'role': m.doMentor ? 'assistant' : 'user',
                'content': m.texto,
              })
          .toList();

      final resposta = await ClaudeAPI.mentor(mensagens: historico);

      final tempoGasto = DateTime.now().difference(inicio).inMilliseconds;
      if (tempoGasto < 1200) {
        await Future.delayed(Duration(milliseconds: 1200 - tempoGasto));
      }

      if (!mounted) return;

      setState(() {
        _mensagens.add(_Mensagem(texto: resposta, doMentor: true));
        _pensando = false;
      });

      // Salva a resposta do Mentor
      BancoMensagens.salvar(role: 'assistant', conteudo: resposta);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensagens.add(_Mensagem(
          texto: T.mentorErro,
          doMentor: true,
        ));
        _pensando = false;
      });
    }

    _rolarParaBaixo();
  }

  void _rolarParaBaixo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Cabeçalho — mesmo padrão visual do Dojô
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    KairoEnso(
                      tamanho: 36,
                      cor: KC.acento.withValues(alpha: 0.75),
                      duracao: const Duration(seconds: 12),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: KT.tituloGradiente(T.mentor)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(T.mentorSubtitulo, style: KT.caption()),
                const SizedBox(height: 32),
                KT.divisor(),
              ],
            ),
          ),

          // Fluxo de mensagens — sem balões, texto puro
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              itemCount: _mensagens.length + (_pensando ? 1 : 0),
              itemBuilder: (context, i) {
                if (_pensando && i == _mensagens.length) {
                  return const _IndicadorPensando();
                }
                return _BolhaMensagem(mensagem: _mensagens[i]);
              },
            ),
          ),

          // Campo de entrada — fino, sem botão circular
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 16,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                color: KC.card,
                borderRadius: BorderRadius.circular(24),
                border: KC.escuro ? null : Border.all(color: KC.linha, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: KC.escuro ? 0.22 : 0.07),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: KT.body(),
                      cursorColor: KC.acento,
                      cursorWidth: 1,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: T.escreva,
                        hintStyle: KT.body(cor: KC.textoSuave),
                        border: InputBorder.none,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onSubmitted: (_) => _enviar(),
                    ),
                  ),
                  GestureDetector(
                    onTap: _pensando ? null : _enviar,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_upward,
                        color: _pensando ? KC.textoSuave : KC.acento,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── INDICADOR "PENSANDO" — Ensō desenhando + três pontos ─────────────────────

class _IndicadorPensando extends StatefulWidget {
  const _IndicadorPensando();

  @override
  State<_IndicadorPensando> createState() => _IndicadorPensandoState();
}

class _IndicadorPensandoState extends State<_IndicadorPensando>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              return SizedBox(
                width: 30,
                height: 30,
                child: CustomPaint(
                  painter: _EnsoCarregando(
                    progresso: _ctrl.value,
                    cor: KC.acento,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 14),
          _PontosAnimados(animacao: _ctrl),
        ],
      ),
    );
  }
}

// Três pontos com opacidade pulsante desfasada — mais expressivo que "..."
class _PontosAnimados extends StatelessWidget {
  final Animation<double> animacao;
  const _PontosAnimados({required this.animacao});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animacao,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Cada ponto atrasa 120ms em relação ao anterior
            final fase = ((animacao.value - i * 0.12) % 1.0).clamp(0.0, 1.0);
            final alpha = (0.25 + (fase < 0.5 ? fase * 2 : (1 - fase) * 2) * 0.75).clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: Text(
                '·',
                style: KT.titulo(cor: KC.acento.withValues(alpha: alpha)),
              ),
            );
          }),
        );
      },
    );
  }
}

class _EnsoCarregando extends CustomPainter {
  final double progresso;
  final Color cor;
  _EnsoCarregando({required this.progresso, required this.cor});

  @override
  void paint(Canvas canvas, Size size) {
    // Traço base — o círculo completo em opacidade baixa (trilha)
    final trilha = Paint()
      ..color = cor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final rect = Offset.zero & size;
    canvas.drawArc(rect.deflate(2), 0, 6.28, false, trilha);

    // Arco ativo com peso variável (pico no meio da progressão)
    const passos = 60;
    const inicio = -1.5708; // -π/2 (topo)
    final sweepTotal = progresso * 5.78;

    for (int i = 0; i < passos; i++) {
      final t = i / passos;
      final t2 = (i + 1) / passos;
      if (sweepTotal * t > sweepTotal) break;

      final pico = (t < 0.4) ? (t / 0.4) : (1.0 - (t - 0.4) / 0.6);
      final largura = 1.5 + pico * 2.0;

      final paint = Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = largura
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect.deflate(2),
        inicio + sweepTotal * t,
        sweepTotal * (t2 - t),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EnsoCarregando old) => old.progresso != progresso;
}

// ── BOLHA DE MENSAGEM (sem balão — só texto) ─────────────────────────────────

class _BolhaMensagem extends StatelessWidget {
  final _Mensagem mensagem;

  const _BolhaMensagem({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;

    if (mensagem.doMentor) {
      // Mensagem do Mentor — esquerda, máx 75% da largura
      return Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: largura * 0.75),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _TextoAnimado(texto: mensagem.texto),
          ),
        ),
      );
    }

    // Mensagem do usuário — direita, máx 70% da largura
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: largura * 0.70),
          child: Text(
            mensagem.texto,
            style: KT.body(),
            textAlign: TextAlign.right,
          ),
        ),
      ),
    );
  }
}

class _TextoAnimado extends StatefulWidget {
  final String texto;
  const _TextoAnimado({required this.texto});

  @override
  State<_TextoAnimado> createState() => _TextoAnimadoState();
}

class _TextoAnimadoState extends State<_TextoAnimado>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacidade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacidade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Todas as respostas do mentor em cobre — voz singular e reconhecível.
    return FadeTransition(
      opacity: _opacidade,
      child: Text(
        widget.texto,
        style: KT.body(cor: KC.acento),
      ),
    );
  }
}


// ── MODELO DE MENSAGEM ───────────────────────────────────────────────────────

class _Mensagem {
  final String texto;
  final bool doMentor;
  const _Mensagem({required this.texto, required this.doMentor});
}
