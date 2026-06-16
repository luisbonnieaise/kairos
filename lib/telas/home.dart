import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/cache.dart';
import '../core/datas.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';
import '../core/widget_sync.dart';
import '../widgets/kairo_avatar.dart';
import '../main.dart' show cartaNovaNotifier, jardimNovaNotifier;
import 'mentor.dart';
import 'dojo.dart';
import 'jardim.dart';
import 'perfil.dart';
import 'silencio.dart';
import 'dormir.dart';
import 'biblioteca.dart';

class TelaHome extends StatefulWidget {
  const TelaHome({super.key});

  @override
  State<TelaHome> createState() => _TelaHomeState();
}

class _TelaHomeState extends State<TelaHome> {
  int _aba = 0;

  // Todas as abas ficam MONTADAS via IndexedStack: carregam de uma vez no boot
  // (incluindo a pergunta do Jardim) e a troca entre elas é instantânea, sem
  // recarregar a cada toque. Instâncias const = estado preservado entre trocas.
  final _telas = const [
    _AbaPatio(),
    TelaMentor(),
    TelaDojo(),
    TelaJardim(),
    TelaBiblioteca(),
  ];

  // (chave, titulo, texto) do tutorial de cada aba, por índice. O disparo é
  // centralizado aqui (não no initState de cada aba): com IndexedStack todas
  // montam no boot, então mostramos o tutorial só quando o usuário CHEGA na
  // aba — preservando a descoberta progressiva e evitando 5 modais de uma vez.
  List<List<String>> get _tutoriais => [
        ['patio', T.tutorialPatioTitulo, T.tutorialPatioTexto],
        ['mentor', T.tutorialMentorTitulo, T.tutorialMentorTexto],
        ['dojo', T.tutorialDojoTitulo, T.tutorialDojoTexto],
        ['jardim', T.tutorialJardimTitulo, T.tutorialJardimTexto],
        ['biblioteca', T.tutorialBibliotecaTitulo, T.tutorialBibliotecaTexto],
      ];

  @override
  void initState() {
    super.initState();
    // Tutorial da aba inicial (Início) após o primeiro frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _mostrarTutorialAba(0));
  }

  void _mostrarTutorialAba(int i) {
    if (i < 0 || i >= _tutoriais.length) return;
    final t = _tutoriais[i];
    Tutorial.mostrar(context: context, chave: t[0], titulo: t[1], texto: t[2]);
  }

  void _selecionar(int i) {
    if (i == _aba) return;
    HapticFeedback.selectionClick();
    setState(() => _aba = i);
    _mostrarTutorialAba(i);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: KC.sumi,
      extendBody: true,
      body: IndexedStack(index: _aba, children: _telas),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 12),
        child: _NavBar(
          selecionado: _aba,
          aoSelecionar: _selecionar,
        ),
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
    // Sombra fora do clip para não ser cortada
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: KC.escuro ? 0.30 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: KC.escuro
                  ? Colors.black.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: KC.escuro
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  _ItemNav(icone: Icons.home_outlined,             label: T.inicio,     index: 0, selecionado: selecionado, aoTocar: aoSelecionar),
                  _ItemNav(icone: Icons.chat_bubble_outline,       label: T.mentor,     index: 1, selecionado: selecionado, aoTocar: aoSelecionar),
                  _ItemNav(icone: Icons.self_improvement_outlined, label: T.dojo,       index: 2, selecionado: selecionado, aoTocar: aoSelecionar),
                  ValueListenableBuilder<bool>(
                    valueListenable: jardimNovaNotifier,
                    builder: (_, temNova, _) => _ItemNav(
                      icone: Icons.eco_outlined,
                      label: T.jardim,
                      index: 3,
                      selecionado: selecionado,
                      aoTocar: aoSelecionar,
                      notificacao: temNova,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: cartaNovaNotifier,
                    builder: (_, temNova, _) => _ItemNav(
                      icone: Icons.menu_book_outlined,
                      label: T.biblioteca,
                      index: 4,
                      selecionado: selecionado,
                      aoTocar: aoSelecionar,
                      notificacao: temNova,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemNav extends StatefulWidget {
  final IconData icone;
  final String label;
  final int index;
  final int selecionado;
  final ValueChanged<int> aoTocar;
  final bool notificacao;

  const _ItemNav({
    required this.icone,
    required this.label,
    required this.index,
    required this.selecionado,
    required this.aoTocar,
    this.notificacao = false,
  });

  @override
  State<_ItemNav> createState() => _ItemNavState();
}

class _ItemNavState extends State<_ItemNav> with SingleTickerProviderStateMixin {
  // "Pop": saltinho elástico do ícone quando a aba passa a estar selecionada.
  late final AnimationController _pop;
  late final Animation<double> _popEscala;

  // Afundar ao pressionar — feedback tátil de toque, separado do pop.
  bool _pressionado = false;

  bool get _ativo => widget.index == widget.selecionado;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // 1.0 → 1.28 → 1.0 com overshoot suave (saltinho que assenta).
    _popEscala = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.28), weight: 40),
      TweenSequenceItem(
        tween: Tween(begin: 1.28, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_pop);
  }

  @override
  void didUpdateWidget(_ItemNav old) {
    super.didUpdateWidget(old);
    // Dispara o pop só na transição para "ativo" (não a cada rebuild).
    final eraAtivo = old.index == old.selecionado;
    if (_ativo && !eraAtivo) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cor = _ativo ? KC.acento : KC.textoSuave.withValues(alpha: 0.7);
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.aoTocar(widget.index),
        onTapDown: (_) => setState(() => _pressionado = true),
        onTapUp: (_) => setState(() => _pressionado = false),
        onTapCancel: () => setState(() => _pressionado = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          // Afundar ao toque; volta com leve overshoot ao soltar.
          scale: _pressionado ? 0.86 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  width: _ativo ? 18 : 0,
                  height: 2,
                  color: KC.acento,
                ),
                const SizedBox(height: 6),
                ScaleTransition(
                  scale: _popEscala,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(widget.icone, size: 20, color: cor),
                      if (widget.notificacao)
                        Positioned(
                          top: -2,
                          right: -5,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE53935),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(widget.label, style: KT.tabLabel(cor: cor)),
              ],
            ),
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
    _lerCache();   // paint instantâneo do cache local (se houver)
    _carregar();   // revalida do Supabase em segundo plano
    // Tutorial é disparado pelo Home ao chegar na aba (ver _mostrarTutorialAba).
  }

  // Pinta nome/avatar e práticas a partir do cache local, sem rede. As marcas
  // de "feito" só são reaproveitadas se o cache for de HOJE.
  void _lerCache() {
    final perfil = CacheLocal.lerMapa('patio_perfil');
    final hab = CacheLocal.lerMapa('patio_habitos');
    if (perfil == null && hab == null) return;
    setState(() {
      if (perfil != null) {
        _nomeUsuario = (perfil['nome'] as String?)?.trim() ?? '';
        _avatarUrl = perfil['avatar_url'] as String?;
      }
      if (hab != null) {
        final mesmaData = hab['data'] == formatarDataYMD(DateTime.now());
        final itens = (hab['itens'] as List?) ?? const [];
        _habitos = itens.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return _Habito(
            id: m['id'] as String,
            nome: m['nome'] as String,
            duracao: (m['duracao'] as String?) ?? '',
            feito: mesmaData && m['feito'] == true,
          );
        }).toList();
      }
      _carregando = false;
    });
  }

  void _gravarCache() {
    CacheLocal.gravar('patio_perfil', {'nome': _nomeUsuario, 'avatar_url': _avatarUrl});
    CacheLocal.gravar('patio_habitos', {
      'data': formatarDataYMD(DateTime.now()),
      'itens': _habitos
          .map((h) => {'id': h.id, 'nome': h.nome, 'duracao': h.duracao, 'feito': h.feito})
          .toList(),
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
      _gravarCache();
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

  Widget _buildCabecalhoTexto() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Saudação como sobrescrito discreto — dá contexto sem competir
          Text(
            _saudacao().toUpperCase(),
            style: KT.micro(),
          ),
          const SizedBox(height: 3),
          // Nome do usuário — elemento focal, com o degradê de assinatura
          KT.tituloGradiente(
            _nomeUsuario.isEmpty ? T.bemVindo : _nomeUsuario,
            estilo: KT.titulo().copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );

  Future<void> _marcarHabito(int index) async {
    HapticFeedback.mediumImpact();
    final habito = _habitos[index];
    final novoEstado = !habito.feito;

    // Atualização otimista da UI
    setState(() => _habitos[index].feito = novoEstado);
    _gravarCache();

    try {
      if (novoEstado) {
        await BancoPraticas.marcarFeita(habito.id);
      } else {
        await BancoPraticas.desmarcarFeita(habito.id);
      }
      // Reflete streak / próxima prática nos widgets de tela inicial.
      WidgetSync.sincronizar();
    } catch (_) {
      // Reverte estado se falhar (rede caiu, RLS, etc.)
      if (!mounted) return;
      setState(() => _habitos[index].feito = !novoEstado);
      _gravarCache();
    }
  }

  void _abrir(Widget tela) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => tela,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final concluidos = _habitos.where((h) => h.feito).length;
    final total = _habitos.length;
    final temHabitos = !_carregando && _habitos.isNotEmpty;

    // viewPadding.bottom = safe area físico (não afetado pelo extendBody).
    // navbar (~64) + gap (12) + folga generosa (52) — para os cards nunca
    // encostarem na barra de navegação flutuante.
    final navBarClearance = MediaQuery.of(context).viewPadding.bottom + 128;

    // Tela estática: cabeçalho fixo no topo, cards de ação fixos na base e a
    // lista de práticas ocupando o meio (rola internamente só se transbordar).
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 24,
        24,
        navBarClearance,
      ),
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
                      pageBuilder: (_, _, _) => const TelaPerfil(),
                      transitionsBuilder: (_, anim, _, child) =>
                          FadeTransition(opacity: anim, child: child),
                      transitionDuration: const Duration(milliseconds: 320),
                    ),
                  );
                  if (mounted) await _carregar();
                },
                child: KairoAvatar(
                  tamanho: 48,
                  url: _avatarUrl,
                  nome: _nomeUsuario,
                  editavel: false,
                ),
              ),

              const SizedBox(width: 16),

              // Saudação + nome
              Expanded(child: _buildCabecalhoTexto()),
            ],
          ),

          const SizedBox(height: 14),

          // Frase do dia (rotativa, determinística) — italic com aspas.
          Text(
            '"${T.fraseDoDia()}" — ${T.mentor}',
            style: KT.bodyItalic(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 24),
          KT.divisor(),
          const SizedBox(height: 20),

          // ── Seção Práticas: título + contador na mesma linha ──────────
          Row(
            children: [
              Text(T.praticasDeHoje, style: KT.titulo()),
              const Spacer(),
              if (temHabitos)
                Text('$concluidos/$total', style: KT.caption(cor: KC.textoSuave)),
            ],
          ),

          // Barra de progresso ultra-fina (2px), logo abaixo do título
          if (temHabitos) ...[
            const SizedBox(height: 12),
            SizedBox(
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
          ],

          const SizedBox(height: 16),

          // Lista flexível — preenche o meio e rola sozinha se houver práticas
          // demais. Pull-to-refresh fica só aqui, sem mover o resto da tela.
          Expanded(
            child: RefreshIndicator(
              color: KC.acento,
              backgroundColor: KC.fundo,
              onRefresh: _carregar,
              child: _carregando
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(T.carregando, style: KT.caption()),
                        ),
                      ],
                    )
                  : _habitos.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Text(
                              T.nenhumaPraticaAtiva,
                              style: KT.caption(cor: KC.textoSuave),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: _habitos.length,
                          itemBuilder: (_, i) => _PedraHabito(
                            habito: _habitos[i],
                            aoMarcar: () => _marcarHabito(i),
                          ),
                        ),
            ),
          ),

          const SizedBox(height: 20),
          KT.divisor(),
          const SizedBox(height: 20),

          // ── Cards de ação: empilhados, fixos na base ──────────────────
          _CardAcao(
            icone: KairoEnso(tamanho: 38, cor: KC.acento.withValues(alpha: 0.6)),
            titulo: T.modoSilencioTitulo,
            subtitulo: T.pausaFocoPresenca,
            aoTocar: () => _abrir(const TelaSilencioSelecao()),
          ),
          const SizedBox(height: 12),
          _CardAcao(
            icone: const _LuaAnimada(),
            titulo: T.relaxaEDurmaTitulo,
            subtitulo: T.relaxaEDurmaSubtitulo,
            aoTocar: () => _abrir(const TelaDormirSelecao()),
          ),
        ],
      ),
    );
  }
}

// ── CARD DE AÇÃO ──────────────────────────────────────────────────────────────
// Card horizontal compacto, empilhado na base da tela Início (Modo Silêncio em
// cima, Relaxa e Durma embaixo). Ícone à esquerda, texto no meio, seta à direita.

class _CardAcao extends StatelessWidget {
  final Widget icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback aoTocar;

  const _CardAcao({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: aoTocar,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: KC.card,
          borderRadius: BorderRadius.circular(16),
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
            SizedBox(width: 44, child: Center(child: icone)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titulo,
                    style: KT.titulo().copyWith(fontSize: 17),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitulo,
                    style: KT.caption(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              size: 13,
              color: KC.textoSuave.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── LUA ANIMADA ───────────────────────────────────────────────────────────────
// Lua do card "Relaxa e Durma" com uma respiração lenta e calmante: leve
// variação de escala + opacidade e um brilho suave de luar pulsando. ~4s,
// vai-e-volta contínuo — discreto, sem chamar atenção demais.

class _LuaAnimada extends StatefulWidget {
  const _LuaAnimada();

  @override
  State<_LuaAnimada> createState() => _LuaAnimadaState();
}

class _LuaAnimadaState extends State<_LuaAnimada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Transform.scale(
          scale: 0.97 + 0.06 * t,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: KC.acento.withValues(alpha: 0.22 * t),
                  blurRadius: 4 + 12 * t,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              Icons.nightlight_round,
              size: 34,
              color: KC.acento.withValues(alpha: 0.5 + 0.35 * t),
            ),
          ),
        );
      },
    );
  }
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

