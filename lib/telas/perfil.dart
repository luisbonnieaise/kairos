import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/notificacoes.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';
import '../core/billing.dart';
import '../core/cache.dart';
import '../widgets/kairo_avatar.dart';
import '../main.dart';
import 'premium.dart';

class TelaPerfil extends StatefulWidget {
  const TelaPerfil({super.key});

  @override
  State<TelaPerfil> createState() => _TelaPerfilState();
}

class _TelaPerfilState extends State<TelaPerfil> {
  Map<String, dynamic>? _perfil;
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
        chave: 'perfil',
        titulo: T.tutorialPerfilTitulo,
        texto: T.tutorialPerfilTexto,
      );
    });
  }

  Future<void> _carregar() async {
    try {
      final perfil = await BancoPerfil.carregar();
      if (!mounted) return;
      setState(() {
        _perfil    = perfil;
        _avatarUrl = perfil?['avatar_url'] as String?;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  void _editarCampo({
    required String titulo,
    required String? valorAtual,
    required Future<void> Function(String) aoSalvar,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SheetEditar(
        titulo: titulo,
        valorInicial: valorAtual ?? '',
        aoSalvar: (texto) async {
          await aoSalvar(texto);
          await _carregar();
        },
      ),
    );
  }

  void _mudarSenha() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SheetMudarSenha(
        aoSalvar: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: KC.grafite,
              content: Text(T.senhaAtualizada, style: KT.caption(cor: KC.washi)),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  Future<void> _trocarIdioma() async {
    HapticFeedback.lightImpact();

    final escolhido = await showModalBottomSheet<String>(
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
              Text(T.escolhaIdioma, style: KT.titulo()),
              const SizedBox(height: 24),
              for (final idioma in T.idiomasDisponiveis)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, idioma['codigo']),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: KC.grafite, width: 1)),
                    ),
                    child: Row(
                      children: [
                        Text(idioma['nomeNativo']!, style: KT.body()),
                        const Spacer(),
                        if (T.idioma == idioma['codigo'])
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
                ),
            ],
          ),
        ),
      ),
    );

    if (escolhido == null || escolhido == T.idioma) return;

    // Salva local (dispara T.idiomaNotifier → MaterialApp reconstrói toda a
    // árvore) e persiste no perfil para que o backend (Mentor/Carta) também
    // veja o novo idioma. Não precisa mais reiniciar a navegação: o
    // ValueListenableBuilder em main.dart já refaz o rebuild com a ValueKey
    // do MaterialApp incluindo o idioma, e os getters de `T.*` re-resolvem.
    await T.definir(escolhido);
    await BancoPerfil.atualizar(idioma: escolhido);
  }

  Future<void> _escolherHorario() async {
    HapticFeedback.lightImpact();

    // Pede permissão primeiro
    final temPermissao = await KairoNotificacoes.temPermissao();
    if (!temPermissao) {
      final concedida = await KairoNotificacoes.pedirPermissao();
      if (!concedida) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: KC.grafite,
            content: Text(T.semPermissao, style: KT.caption(cor: KC.washi)),
          ),
        );
        return;
      }
    }

    final horarioAtual = _perfil?['horario_lembrete'] as String?;
    TimeOfDay inicial = const TimeOfDay(hour: 7, minute: 0);
    if (horarioAtual != null && horarioAtual.contains(':')) {
      final partes = horarioAtual.split(':');
      inicial = TimeOfDay(
        hour: int.tryParse(partes[0]) ?? 7,
        minute: int.tryParse(partes[1]) ?? 0,
      );
    }

    final escolhido = await showTimePicker(
      context: context,
      initialTime: inicial,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: KC.acento,
              surface: KC.fundo,
              onSurface: KC.texto,
            ),
          ),
          child: child!,
        );
      },
    );

    if (escolhido == null) return;

    final horarioStr =
        '${escolhido.hour.toString().padLeft(2, '0')}:'
        '${escolhido.minute.toString().padLeft(2, '0')}:00';

    await BancoPerfil.atualizar(horarioLembrete: horarioStr);
    await KairoNotificacoes.agendarLembreteDiario(escolhido.hour, escolhido.minute);
    await KairoNotificacoes.agendarCartaSemanal();
    await KairoNotificacoes.agendarJardim();
    await _carregar();
  }

  Future<void> _desativarLembrete() async {
    HapticFeedback.lightImpact();
    await KairoNotificacoes.cancelarLembrete();
    await BancoPerfil.atualizar(limparHorarioLembrete: true);
    await _carregar();
  }

  Future<void> _toggleNotifJardim() async {
    HapticFeedback.lightImpact();
    final ativo = (_perfil?['notif_jardim'] as bool?) ?? true;
    final novoEstado = !ativo;

    if (novoEstado) {
      // Pede permissão se necessário e agenda
      final temPermissao = await KairoNotificacoes.temPermissao();
      if (!temPermissao) {
        final concedida = await KairoNotificacoes.pedirPermissao();
        if (!concedida) return;
      }
      await KairoNotificacoes.agendarJardim();
    } else {
      await KairoNotificacoes.cancelarJardim();
    }

    await BancoPerfil.atualizar(notifJardim: novoEstado);
    await _carregar();
  }

  Future<void> _sair() async {
    final confirmou = await showModalBottomSheet<bool>(
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
              Text(T.sairContaPergunta, style: KT.titulo()),
              const SizedBox(height: 12),
              Text(T.dadosContinuam, style: KT.bodySerif(cor: KC.cinza)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KC.washi,
                    foregroundColor: KC.sumi,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.sair, style: KT.body(cor: KC.sumi)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KC.washi,
                    side: BorderSide(color: KC.grafite, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.ficar, style: KT.body()),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmou != true) return;

    HapticFeedback.mediumImpact();
    // Limpa cache local (enquanto o user.id ainda existe) antes de sair.
    await CacheLocal.limparUsuario();
    Billing.instance.limparCache();
    await supabase.auth.signOut();

    if (!mounted) return;
    // Substitui toda a pilha pela tela de Boas-Vindas
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const TelaBoasVindas(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '—';

    return Scaffold(
      backgroundColor: KC.sumi,
      body: SafeArea(
        child: Column(
          children: [
            // Cabeçalho com botão voltar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: KC.cinza, size: 22),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),

                    // Avatar editável centralizado
                    Center(
                      child: KairoAvatar(
                        tamanho: 84,
                        url: _avatarUrl,
                        nome: (_perfil?['nome'] as String?) ?? '',
                        editavel: true,
                        aoAtualizar: (novaUrl) => setState(
                          () => _avatarUrl = novaUrl.isEmpty ? null : novaUrl,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    Text(T.perfil, style: KT.displayL()),

                    const SizedBox(height: 32),

                    // Conta
                    Text(T.conta, style: KT.micro()),
                    const SizedBox(height: 12),
                    Text(email, style: KT.body()),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _mudarSenha,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(T.mudarSenha, style: KT.caption(cor: KC.acento)),
                      ),
                    ),

                    const SizedBox(height: 40),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    // Kairo Premium (Fase 03)
                    Text(T.premiumTitulo, style: KT.micro()),
                    const SizedBox(height: 12),
                    _LinhaPremium(),

                    const SizedBox(height: 40),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    Text(T.identidadeLabel, style: KT.micro()),
                    const SizedBox(height: 12),

                    if (_carregando)
                      Text(T.carregando, style: KT.caption())
                    else ...[
                      _CampoEditavel(
                        rotulo: T.nome,
                        valor: _perfil?['nome'] as String?,
                        aoEditar: () => _editarCampo(
                          titulo: T.comoTeChamarErro,
                          valorAtual: _perfil?['nome'] as String?,
                          aoSalvar: (v) => BancoPerfil.atualizar(nome: v),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _CampoEditavel(
                        rotulo: T.quemQuerSeTornar,
                        valor: _perfil?['identidade'] as String?,
                        aoEditar: () => _editarCampo(
                          titulo: T.quemQuerSeTornar,
                          valorAtual: _perfil?['identidade'] as String?,
                          aoSalvar: (v) => BancoPerfil.atualizar(identidade: v),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _CampoEditavel(
                        rotulo: T.oQueTiraEixo,
                        valor: _perfil?['desequilibrio'] as String?,
                        aoEditar: () => _editarCampo(
                          titulo: T.oQueTiraEixo,
                          valorAtual: _perfil?['desequilibrio'] as String?,
                          aoSalvar: (v) => BancoPerfil.atualizar(desequilibrio: v),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _CampoEditavel(
                        rotulo: T.areaReordenar,
                        valor: _perfil?['area_foco'] as String?,
                        aoEditar: () => _editarCampo(
                          titulo: T.areaReordenar,
                          valorAtual: _perfil?['area_foco'] as String?,
                          aoSalvar: (v) => BancoPerfil.atualizar(areaFoco: v),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _CampoEditavel(
                        rotulo: T.ritmoEvolucao,
                        valor: _perfil?['ritmo'] as String?,
                        aoEditar: () => _editarCampo(
                          titulo: T.ritmoEvolucao,
                          valorAtual: _perfil?['ritmo'] as String?,
                          aoSalvar: (v) => BancoPerfil.atualizar(ritmo: v),
                        ),
                      ),
                    ],

                    const SizedBox(height: 48),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    // Tema (claro/escuro)
                    Text(T.temaLabel, style: KT.micro()),
                    const SizedBox(height: 12),
                    _TemaRow(),

                    const SizedBox(height: 48),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    // Idioma
                    Text(T.idiomaLabel, style: KT.micro()),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _trocarIdioma,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  T.idiomasDisponiveis.firstWhere(
                                    (i) => i['codigo'] == T.idioma,
                                    orElse: () => T.idiomasDisponiveis.first,
                                  )['nomeNativo']!,
                                  style: KT.body(),
                                ),
                              ),
                              Icon(Icons.edit_outlined, size: 14, color: KC.fumo),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    // Lembrete diário
                    Text(T.lembreteDiario, style: KT.micro()),
                    const SizedBox(height: 12),
                    if (_carregando)
                      Text(T.carregando, style: KT.caption())
                    else
                      _LembreteRow(
                        horarioAtual: _perfil?['horario_lembrete'] as String?,
                        aoEscolher: _escolherHorario,
                        aoDesativar: _desativarLembrete,
                      ),

                    const SizedBox(height: 48),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    // Notificações do Jardim
                    Text(T.notifJardimLabel, style: KT.micro()),
                    const SizedBox(height: 12),
                    if (_carregando)
                      Text(T.carregando, style: KT.caption())
                    else
                      _NotifJardimRow(
                        ativo: (_perfil?['notif_jardim'] as bool?) ?? true,
                        aoToggle: _toggleNotifJardim,
                      ),

                    const SizedBox(height: 48),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    // Tutoriais (rever)
                    Text(T.tutoriaisLabel, style: KT.micro()),
                    const SizedBox(height: 12),
                    _LinhaTutorial(
                      nome: T.tutorialPatioTitulo,
                      onTap: () => Tutorial.mostrarForcado(
                        context: context,
                        titulo: T.tutorialPatioTitulo,
                        texto: T.tutorialPatioTexto,
                      ),
                    ),
                    _LinhaTutorial(
                      nome: T.tutorialMentorTitulo,
                      onTap: () => Tutorial.mostrarForcado(
                        context: context,
                        titulo: T.tutorialMentorTitulo,
                        texto: T.tutorialMentorTexto,
                      ),
                    ),
                    _LinhaTutorial(
                      nome: T.tutorialDojoTitulo,
                      onTap: () => Tutorial.mostrarForcado(
                        context: context,
                        titulo: T.tutorialDojoTitulo,
                        texto: T.tutorialDojoTexto,
                      ),
                    ),
                    _LinhaTutorial(
                      nome: T.tutorialJardimTitulo,
                      onTap: () => Tutorial.mostrarForcado(
                        context: context,
                        titulo: T.tutorialJardimTitulo,
                        texto: T.tutorialJardimTexto,
                      ),
                    ),
                    _LinhaTutorial(
                      nome: T.tutorialBibliotecaTitulo,
                      onTap: () => Tutorial.mostrarForcado(
                        context: context,
                        titulo: T.tutorialBibliotecaTitulo,
                        texto: T.tutorialBibliotecaTexto,
                      ),
                    ),
                    _LinhaTutorial(
                      nome: T.tutorialSilencioTitulo,
                      onTap: () => Tutorial.mostrarForcado(
                        context: context,
                        titulo: T.tutorialSilencioTitulo,
                        texto: T.tutorialSilencioTexto,
                      ),
                    ),
                    _LinhaTutorial(
                      nome: T.tutorialPerfilTitulo,
                      onTap: () => Tutorial.mostrarForcado(
                        context: context,
                        titulo: T.tutorialPerfilTitulo,
                        texto: T.tutorialPerfilTexto,
                      ),
                    ),

                    const SizedBox(height: 48),
                    KT.divisor(),
                    const SizedBox(height: 32),

                    // Sair
                    GestureDetector(
                      onTap: _sair,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(T.sairConta, style: KT.body(cor: KC.aka)),
                      ),
                    ),

                    const SizedBox(height: 64),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── LINHA DO KAIRO PREMIUM (status + entrada do paywall) ─────────────────────

class _LinhaPremium extends StatefulWidget {
  @override
  State<_LinhaPremium> createState() => _LinhaPremiumState();
}

class _LinhaPremiumState extends State<_LinhaPremium> {
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    await Billing.instance.refresh();
    if (!mounted) return;
    setState(() => _carregando = false);
  }

  Future<void> _abrirPaywall() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TelaPremium()),
    );
    if (!mounted) return;
    // Pode ter mudado de estado (assinou/cancelou) — re-render.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final billing = Billing.instance;
    final premium = billing.cachePremium == true;
    final periodoFim = billing.periodoFim;

    return GestureDetector(
      onTap: _abrirPaywall,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _carregando
                      ? T.carregando
                      : (premium ? T.premiumAtivo : T.premiumGratuito),
                  style: KT.body(cor: premium ? KC.kin : null),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: KC.fumo),
            ],
          ),
          if (premium && periodoFim != null) ...[
            const SizedBox(height: 4),
            Text(
              '${T.premiumAtivoAte} ${T.formatarData(periodoFim)}',
              style: KT.caption(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── LINHA DO TOGGLE DE TEMA (claro/escuro) ───────────────────────────────────

class _TemaRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(T.temaDescricao, style: KT.bodySerif(cor: KC.textoSuave)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _BotaoTema(
              rotulo: T.temaClaro,
              escuro: false,
              selecionado: !KC.escuro,
            )),
            const SizedBox(width: 12),
            Expanded(child: _BotaoTema(
              rotulo: T.temaEscuro,
              escuro: true,
              selecionado: KC.escuro,
            )),
          ],
        ),
      ],
    );
  }
}

class _BotaoTema extends StatelessWidget {
  final String rotulo;
  final bool escuro;
  final bool selecionado;
  const _BotaoTema({
    required this.rotulo,
    required this.escuro,
    required this.selecionado,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        await KC.alternar(escuro);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selecionado ? KC.card : Colors.transparent,
          border: Border.all(
            color: selecionado ? KC.acento : KC.linha,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            rotulo,
            style: KT.body(cor: selecionado ? KC.acento : KC.textoSuave),
          ),
        ),
      ),
    );
  }
}

// ── LINHA DO TOGGLE DE NOTIFICAÇÕES DO JARDIM ────────────────────────────────

class _NotifJardimRow extends StatelessWidget {
  final bool ativo;
  final VoidCallback aoToggle;

  const _NotifJardimRow({required this.ativo, required this.aoToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                T.notifJardimDescricao,
                style: KT.bodySerif(cor: KC.cinza),
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: ativo,
              onChanged: (_) => aoToggle(),
              activeTrackColor: KC.kin,
              activeThumbColor: KC.washi,
              inactiveTrackColor: KC.grafite,
              inactiveThumbColor: KC.fumo,
            ),
          ],
        ),
      ],
    );
  }
}

// ── LINHA DE TUTORIAL (no Perfil, pra rever) ─────────────────────────────────

class _LinhaTutorial extends StatelessWidget {
  final String nome;
  final VoidCallback onTap;

  const _LinhaTutorial({required this.nome, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(nome, style: KT.body())),
            Icon(Icons.arrow_forward, size: 14, color: KC.fumo),
          ],
        ),
      ),
    );
  }
}

// ── LINHA DO LEMBRETE ─────────────────────────────────────────────────────────

class _LembreteRow extends StatelessWidget {
  final String? horarioAtual;
  final VoidCallback aoEscolher;
  final VoidCallback aoDesativar;

  const _LembreteRow({
    required this.horarioAtual,
    required this.aoEscolher,
    required this.aoDesativar,
  });

  String _formatar(String? h) {
    if (h == null || h.isEmpty) return '—';
    if (h.length >= 5) return h.substring(0, 5);
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final ativo = horarioAtual != null && horarioAtual!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: aoEscolher,
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ativo ? T.lembrete : T.ativarLembrete,
                      style: KT.caption(),
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 14, color: KC.fumo),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatar(horarioAtual),
                style: KT.bodySerif(cor: ativo ? KC.washi : KC.fumo),
              ),
            ],
          ),
        ),
        if (ativo) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: aoDesativar,
            behavior: HitTestBehavior.opaque,
            child: Text(T.desativarLembrete, style: KT.caption(cor: KC.aka)),
          ),
        ],
      ],
    );
  }
}

// ── CAMPO EDITÁVEL ────────────────────────────────────────────────────────────

class _CampoEditavel extends StatelessWidget {
  final String rotulo;
  final String? valor;
  final VoidCallback aoEditar;

  const _CampoEditavel({
    required this.rotulo,
    required this.valor,
    required this.aoEditar,
  });

  @override
  Widget build(BuildContext context) {
    final vazio = valor == null || valor!.trim().isEmpty;

    return GestureDetector(
      onTap: aoEditar,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(rotulo, style: KT.caption()),
              ),
              Icon(Icons.edit_outlined, size: 14, color: KC.fumo),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            vazio ? '—' : valor!,
            style: KT.bodySerif(cor: vazio ? KC.fumo : KC.washi),
          ),
        ],
      ),
    );
  }
}

// ── SHEET DE EDIÇÃO ──────────────────────────────────────────────────────────

class _SheetEditar extends StatefulWidget {
  final String titulo;
  final String valorInicial;
  final Future<void> Function(String) aoSalvar;

  const _SheetEditar({
    required this.titulo,
    required this.valorInicial,
    required this.aoSalvar,
  });

  @override
  State<_SheetEditar> createState() => _SheetEditarState();
}

class _SheetEditarState extends State<_SheetEditar> {
  late final TextEditingController _controller;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valorInicial);
  }

  String? _erro;

  Future<void> _salvar() async {
    final texto = _controller.text.trim();
    if (_salvando) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await widget.aoSalvar(texto);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() {
        _salvando = false;
        _erro = T.erroGenerico;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 32,
          right: 32,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
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
            Text(widget.titulo, style: KT.titulo()),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              style: KT.bodySerif(),
              cursorColor: KC.kin,
              cursorWidth: 1,
              autofocus: true,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: KC.grafite, width: 1),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: KC.grafite, width: 1),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: KC.cinza, width: 1),
                ),
              ),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 16),
              Text(_erro!, style: KT.caption(cor: KC.aka)),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KC.washi,
                  foregroundColor: KC.sumi,
                  disabledBackgroundColor: KC.grafite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _salvando
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: KC.fundo,
                        ),
                      )
                    : Text(T.salvar, style: KT.body(cor: KC.fundo)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SHEET DE MUDAR SENHA ──────────────────────────────────────────────────────

class _SheetMudarSenha extends StatefulWidget {
  final VoidCallback aoSalvar;
  const _SheetMudarSenha({required this.aoSalvar});

  @override
  State<_SheetMudarSenha> createState() => _SheetMudarSenhaState();
}

class _SheetMudarSenhaState extends State<_SheetMudarSenha> {
  final _novaSenhaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _verNova        = false;
  bool _verConfirmar   = false;
  bool _salvando       = false;
  String? _erro;

  @override
  void dispose() {
    _novaSenhaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nova      = _novaSenhaCtrl.text.trim();
    final confirmar = _confirmarCtrl.text.trim();

    if (nova.length < 6) {
      setState(() => _erro = T.senhaMinimoCaracteres);
      return;
    }
    if (nova != confirmar) {
      setState(() => _erro = T.senhasNaoCoincidem);
      return;
    }

    setState(() { _salvando = true; _erro = null; });

    try {
      await supabase.auth.updateUser(UserAttributes(password: nova));
      if (mounted) {
        Navigator.pop(context);
        widget.aoSalvar();
      }
    } catch (_) {
      if (mounted) setState(() { _salvando = false; _erro = T.erroGenerico; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 32,
          right: 32,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32, height: 3,
                decoration: BoxDecoration(color: KC.grafite, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 32),
            Text(T.mudarSenha, style: KT.titulo()),
            const SizedBox(height: 24),

            TextField(
              controller: _novaSenhaCtrl,
              obscureText: !_verNova,
              style: KT.bodySerif(),
              cursorColor: KC.acento,
              cursorWidth: 1,
              autofocus: true,
              decoration: InputDecoration(
                labelText: T.novaSenha,
                labelStyle: KT.caption(),
                border: UnderlineInputBorder(borderSide: BorderSide(color: KC.grafite, width: 1)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: KC.grafite, width: 1)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: KC.cinza, width: 1)),
                suffixIcon: GestureDetector(
                  onTap: () => setState(() => _verNova = !_verNova),
                  child: Icon(
                    _verNova ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18, color: KC.fumo,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _confirmarCtrl,
              obscureText: !_verConfirmar,
              style: KT.bodySerif(),
              cursorColor: KC.acento,
              cursorWidth: 1,
              onSubmitted: (_) => _salvar(),
              decoration: InputDecoration(
                labelText: T.confirmarSenha,
                labelStyle: KT.caption(),
                border: UnderlineInputBorder(borderSide: BorderSide(color: KC.grafite, width: 1)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: KC.grafite, width: 1)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: KC.cinza, width: 1)),
                suffixIcon: GestureDetector(
                  onTap: () => setState(() => _verConfirmar = !_verConfirmar),
                  child: Icon(
                    _verConfirmar ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18, color: KC.fumo,
                  ),
                ),
              ),
            ),

            if (_erro != null) ...[
              const SizedBox(height: 16),
              Text(_erro!, style: KT.caption(cor: KC.aka)),
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KC.washi,
                  foregroundColor: KC.sumi,
                  disabledBackgroundColor: KC.grafite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _salvando
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: KC.fundo),
                      )
                    : Text(T.salvar, style: KT.body(cor: KC.fundo)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
