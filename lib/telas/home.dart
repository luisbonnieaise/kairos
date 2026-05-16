import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';
import '../widgets/kairo_avatar.dart';
import 'mentor.dart';
import 'dojo.dart';
import 'jardim.dart';
import 'perfil.dart';
import 'silencio.dart';
import 'biblioteca.dart';

class TelaHome extends StatefulWidget {
  const TelaHome({super.key});

  @override
  State<TelaHome> createState() => _TelaHomeState();
}

class _TelaHomeState extends State<TelaHome> {
  int _aba = 0;

  final _telas = const [
    _AbaPatio(),
    TelaMentor(),
    TelaDojo(),
    TelaJardim(),
    TelaBiblioteca(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KC.sumi,
      body: _telas[_aba],
      bottomNavigationBar: _NavBar(
        selecionado: _aba,
        aoSelecionar: (i) => setState(() => _aba = i),
      ),
    );
  }
}

// ── BARRA DE NAVEGAÇÃO ────────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  final int selecionado;
  final ValueChanged<int> aoSelecionar;

  const _NavBar({required this.selecionado, required this.aoSelecionar});

  @override
  Widget build(BuildContext context) {
    return Container(
      // Mesmo fundo da tela — ícones parecem flutuar
      color: KC.fundo,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              _ItemNav(icone: Icons.home_outlined,              label: T.inicio,     index: 0, selecionado: selecionado, aoTocar: aoSelecionar),
              _ItemNav(icone: Icons.chat_bubble_outline,        label: T.mentor,     index: 1, selecionado: selecionado, aoTocar: aoSelecionar),
              _ItemNav(icone: Icons.self_improvement_outlined,  label: T.dojo,       index: 2, selecionado: selecionado, aoTocar: aoSelecionar),
              _ItemNav(icone: Icons.eco_outlined,               label: T.jardim,     index: 3, selecionado: selecionado, aoTocar: aoSelecionar),
              _ItemNav(icone: Icons.menu_book_outlined,         label: T.biblioteca, index: 4, selecionado: selecionado, aoTocar: aoSelecionar),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemNav extends StatelessWidget {
  final IconData icone;
  final String label;
  final int index;
  final int selecionado;
  final ValueChanged<int> aoTocar;

  const _ItemNav({
    required this.icone,
    required this.label,
    required this.index,
    required this.selecionado,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final ativo = index == selecionado;
    final cor = ativo ? KC.acento : KC.textoSuave.withValues(alpha: 0.7);
    return Expanded(
      child: GestureDetector(
        onTap: () => aoTocar(index),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Indicador de aba selecionada — linha curta de cobre ACIMA do ícone
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                width: ativo ? 18 : 0,
                height: 2,
                color: KC.acento,
              ),
              const SizedBox(height: 6),
              Icon(icone, size: 20, color: cor),
              const SizedBox(height: 4),
              Text(
                label,
                style: KT.tabLabel(cor: cor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── PÁTIO: TELA INÍCIO ────────────────────────────────────────────────────────

class _AbaPatio extends StatefulWidget {
  const _AbaPatio();

  @override
  State<_AbaPatio> createState() => _AbaPatioState();
}

class _AbaPatioState extends State<_AbaPatio> {
  List<_Habito> _habitos = [];
  String _nomeUsuario = '';
  String? _avatarUrl;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Tutorial.mostrar(
        context: context,
        chave: 'patio',
        titulo: T.tutorialPatioTitulo,
        texto: T.tutorialPatioTexto,
      );
    });
  }

  Future<void> _carregar() async {
    try {
      final praticas = await BancoPraticas.carregar();
      final completadas = await BancoPraticas.completadasHoje();
      final perfil = await BancoPerfil.carregar();

      if (!mounted) return;

      setState(() {
        _habitos = praticas.map((p) => _Habito(
              id: p['id'] as String,
              nome: p['nome'] as String,
              duracao: (p['duracao'] as String?) ?? '',
              feito: completadas.contains(p['id']),
            )).toList();
        _nomeUsuario = (perfil?['nome'] as String?)?.trim() ?? '';
        _avatarUrl   = perfil?['avatar_url'] as String?;
        _carregando  = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  String _saudacao() {
    final hora = DateTime.now().hour;
    if (hora < 12) return T.bomDia;
    if (hora < 18) return T.boaTarde;
    return T.boaNoite;
  }

  // Dark → cinza elegante. Light → gradiente cobre diagonal.
  Widget _buildSaudacao() {
    final texto = _saudacao();
    if (KC.escuro) {
      return Text(
        texto,
        style: KT.displayL(cor: KC.textoSuave),
      );
    }
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: const [Color(0xFF8C5A30), Color(0xFFC28B63)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        texto,
        style: KT.displayL(cor: Colors.white),
      ),
    );
  }

  Future<void> _marcarHabito(int index) async {
    HapticFeedback.mediumImpact();
    final habito = _habitos[index];
    final novoEstado = !habito.feito;

    // Atualização otimista da UI
    setState(() => _habitos[index].feito = novoEstado);

    try {
      if (novoEstado) {
        await BancoPraticas.marcarFeita(habito.id);
      } else {
        await BancoPraticas.desmarcarFeita(habito.id);
      }
    } catch (_) {
      // Reverte estado se falhar (rede caiu, RLS, etc.)
      if (!mounted) return;
      setState(() => _habitos[index].feito = !novoEstado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final concluidos = _habitos.where((h) => h.feito).length;
    final total = _habitos.length;

    return RefreshIndicator(
      color: KC.acento,
      backgroundColor: KC.fundo,
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho: Avatar + saudação em linha ─────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar — toca para ir ao Perfil
                GestureDetector(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const TelaPerfil(),
                        transitionsBuilder: (_, anim, __, child) =>
                            FadeTransition(opacity: anim, child: child),
                        transitionDuration: const Duration(milliseconds: 320),
                      ),
                    );
                    if (mounted) await _carregar();
                  },
                  child: KairoAvatar(
                    tamanho: 52,
                    url: _avatarUrl,
                    nome: _nomeUsuario,
                    editavel: false,
                  ),
                ),

                const SizedBox(width: 18),

                // Saudação + nome
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSaudacao(),
                      const SizedBox(height: 2),
                      Text(
                        _nomeUsuario.isEmpty ? T.bemVindo : _nomeUsuario,
                        style: KT.displayL(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Frase do Mentor — italic com aspas, cor secundária
            Text(
              '"${T.mentorFoque}" — ${T.mentor}',
              style: KT.bodyItalic(),
            ),

            const SizedBox(height: 60),

            // ── Seção Práticas ───────────────────────────────────────────
            Text(T.praticasDeHoje, style: KT.titulo()),
            const SizedBox(height: 6),
            Text(
              _habitos.isEmpty
                  ? T.nenhumaPraticaAtiva
                  : 'Hábitos limitados (até 5)',
              style: KT.caption(cor: KC.textoSuave),
            ),
            const SizedBox(height: 24),

            if (_carregando)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(T.carregando, style: KT.caption()),
              )
            else if (_habitos.isNotEmpty)
              ..._habitos.asMap().entries.map((entry) {
                return _PedraHabito(
                  habito: entry.value,
                  aoMarcar: () => _marcarHabito(entry.key),
                );
              }),

            if (_habitos.isNotEmpty) ...[
              const SizedBox(height: 32),

              // Barra de progresso ultra-fina (2px) + indicador numérico
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 2,
                      child: Stack(
                        children: [
                          Container(color: KC.linha),
                          FractionallySizedBox(
                            widthFactor: total == 0 ? 0 : (concluidos / total).clamp(0.0, 1.0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeInOutCubic,
                              color: KC.acento,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('$concluidos/$total', style: KT.caption(cor: KC.textoSuave)),
                ],
              ),
            ],

            const SizedBox(height: 80),

            // ── Card Modo Silêncio ────────────────────────────────────────
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const TelaSilencioSelecao(),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: const Duration(milliseconds: 320),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                decoration: BoxDecoration(
                  color: KC.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // Ensō (círculo zen) na esquerda — pincelada imperfeita
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CustomPaint(
                        painter: _EnsoPainter(cor: KC.acento.withValues(alpha: 0.6)),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(T.modoSilencioTitulo, style: KT.titulo()),
                          const SizedBox(height: 4),
                          Text(
                            T.pausaFocoPresenca,
                            style: KT.caption(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Painter do ensō — círculo zen com pincelada de caligrafia.
// Stroke grosso no início (entrada do pincel), mais fino nas pontas,
// com variação de opacidade para autenticidade. Abertura no topo-direito.
class _EnsoPainter extends CustomPainter {
  final Color cor;
  _EnsoPainter({required this.cor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final raio = (size.shortestSide / 2) - 4;

    const passos = 120;
    const inicio = -1.35;   // ~-77° (topo-direito)
    const arco = 5.60;       // ~321° — deixa ~7% aberto

    for (int i = 0; i < passos; i++) {
      final t = i / passos;
      final t2 = (i + 1) / passos;

      // Perfil de peso: atinge pico em ~30% e afina suavemente até o fim.
      // Isso imita a entrada rápida de um pincel plano e a saída em ponta.
      final pico = (t < 0.3) ? (t / 0.3) : (1.0 - ((t - 0.3) / 0.7));
      final largura = 2.0 + pico * 5.5;

      // Opacidade levemente variável: mais densa no centro da pincelada
      final alpha = (0.65 + pico * 0.35).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = cor.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = largura
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: raio),
        inicio + arco * t,
        arco * (t2 - t),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EnsoPainter old) => old.cor != cor;
}

// ── PEDRA DE HÁBITO ───────────────────────────────────────────────────────────

class _PedraHabito extends StatelessWidget {
  final _Habito habito;
  final VoidCallback aoMarcar;

  const _PedraHabito({required this.habito, required this.aoMarcar});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: aoMarcar,
      onTap: aoMarcar,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(
          children: [
            // Checkbox circular minimalista
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: habito.feito ? KC.acento : Colors.transparent,
                border: Border.all(
                  color: habito.feito ? KC.acento : KC.textoSuave,
                  width: 1,
                ),
              ),
              child: habito.feito
                  ? Icon(Icons.check, size: 13, color: KC.fundo)
                  : null,
            ),

            const SizedBox(width: 16),

            // Nome
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 320),
                style: KT.body(
                  cor: habito.feito ? KC.textoSuave : KC.texto,
                ),
                child: Text(habito.nome),
              ),
            ),

            // Duração — sutil, some quando marcado
            if (habito.duracao.isNotEmpty)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 320),
                opacity: habito.feito ? 0.0 : 1.0,
                child: Text(habito.duracao, style: KT.caption()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Habito {
  final String id;
  final String nome;
  final String duracao;
  bool feito;

  _Habito({
    required this.id,
    required this.nome,
    required this.duracao,
    this.feito = false,
  });
}

// ── ABAS PLACEHOLDER ──────────────────────────────────────────────────────────

