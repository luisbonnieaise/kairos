import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/i18n.dart';
import '../core/banco.dart';
import '../core/notificacoes.dart';
import 'portao.dart';

class TelaOnboarding extends StatefulWidget {
  const TelaOnboarding({super.key});

  @override
  State<TelaOnboarding> createState() => _TelaOnboardingState();
}

class _TelaOnboardingState extends State<TelaOnboarding> {
  final _controller = PageController();
  int _pagina = 0;

  // Respostas
  String _nome = '';
  String _identidade = '';
  String _desequilibrio = '';
  String _area = '';
  String _ritmo = '';

  static const _totalPaginas = 5;

  void _avancar() {
    HapticFeedback.lightImpact();

    if (_pagina < _totalPaginas - 1) {
      final proxima = _pagina + 1;
      // Páginas 2, 3 e 4 são de escolha (sem digitação) — esconde o teclado
      if (proxima >= 2) {
        FocusScope.of(context).unfocus();
      }
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      FocusScope.of(context).unfocus();
      _finalizar();
    }
  }

  Future<void> _finalizar() async {
    // Salva tudo no perfil
    try {
      await BancoPerfil.atualizar(
        nome: _nome,
        identidade: _identidade,
        desequilibrio: _desequilibrio,
        areaFoco: _area,
        ritmo: _ritmo,
      );
    } catch (_) {}

    // Configura lembrete padrão às 7:00 + carta semanal
    try {
      final concedida = await KairoNotificacoes.pedirPermissao();
      if (concedida) {
        await BancoPerfil.atualizar(horarioLembrete: '07:00:00');
        await KairoNotificacoes.agendarLembreteDiario(7, 0);
        await KairoNotificacoes.agendarCartaSemanal();
        await KairoNotificacoes.agendarJardim();
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        // Novo usuário entra pelo PORTÃO (hard paywall) antes do app.
        pageBuilder: (_, _, _) => const TelaPortao(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KC.sumi,
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _pagina = i),
        children: [
          // 1. Nome
          _PerguntaTexto(
            pergunta: T.comoTeChamarErro, // "Como podemos te chamar?"
            valorAtual: _nome,
            aoMudar: (v) => _nome = v,
            aoConfirmar: () {
              if (_nome.trim().isEmpty) return;
              _avancar();
            },
            indicadorPagina: '${_pagina + 1} / $_totalPaginas',
          ),
          // 2. Identidade
          _PerguntaTexto(
            pergunta: T.quemSeTornar,
            valorAtual: _identidade,
            aoMudar: (v) => _identidade = v,
            aoConfirmar: () {
              if (_identidade.trim().isEmpty) return;
              _avancar();
            },
            indicadorPagina: '${_pagina + 1} / $_totalPaginas',
            multiline: true,
            sublabel: T.apenasUmaFrase,
          ),
          // 3. Desequilíbrio
          _PerguntaEscolha(
            pergunta: T.oQueTiraEixoHoje,
            opcoes: [
              T.optAnsiedade,
              T.optFaltaFoco,
              T.optImpulsos,
              T.optFaltaDirecao,
              T.optExcessoTela,
            ],
            aoEscolher: (v) {
              _desequilibrio = v;
              _avancar();
            },
            indicadorPagina: '${_pagina + 1} / $_totalPaginas',
          ),
          // 4. Área
          _PerguntaEscolha(
            pergunta: T.qualArea,
            opcoes: [
              T.catMente,
              T.catCorpo,
              T.catDisciplina,
              T.catRelacoes,
              T.catTrabalho,
            ],
            aoEscolher: (v) {
              _area = v;
              _avancar();
            },
            indicadorPagina: '${_pagina + 1} / $_totalPaginas',
          ),
          // 5. Ritmo
          _PerguntaEscolha(
            pergunta: T.qualRitmo,
            opcoes: [
              T.optLentoSustentavel,
              T.optMedioConstante,
              T.optAcelerado,
            ],
            aoEscolher: (v) {
              _ritmo = v;
              _avancar();
            },
            indicadorPagina: '${_pagina + 1} / $_totalPaginas',
          ),
        ],
      ),
    );
  }
}

// ── PERGUNTA COM TEXTO LIVRE ─────────────────────────────────────────────────

class _PerguntaTexto extends StatefulWidget {
  final String pergunta;
  final String valorAtual;
  final ValueChanged<String> aoMudar;
  final VoidCallback aoConfirmar;
  final String indicadorPagina;
  final bool multiline;
  final String? sublabel;

  const _PerguntaTexto({
    required this.pergunta,
    required this.valorAtual,
    required this.aoMudar,
    required this.aoConfirmar,
    required this.indicadorPagina,
    this.multiline = false,
    this.sublabel,
  });

  @override
  State<_PerguntaTexto> createState() => _PerguntaTextoState();
}

class _PerguntaTextoState extends State<_PerguntaTexto> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.valorAtual);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preenchido = _ctrl.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 40,
          right: 40,
          top: 40,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.indicadorPagina, style: KT.micro(cor: KC.fumo)),
            const SizedBox(height: 48),
            Text(widget.pergunta, style: KT.displayL()),
            const SizedBox(height: 40),
            TextField(
              controller: _ctrl,
              style: KT.bodySerif(),
              cursorColor: KC.kin,
              cursorWidth: 1,
              autofocus: true,
              maxLines: widget.multiline ? 4 : 1,
              maxLength: widget.multiline ? 200 : 50,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) {
                widget.aoMudar(v);
                setState(() {});
              },
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
            if (widget.sublabel != null) ...[
              const SizedBox(height: 16),
              Text(widget.sublabel!, style: KT.caption()),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: preenchido ? widget.aoConfirmar : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KC.washi,
                  foregroundColor: KC.sumi,
                  disabledBackgroundColor: KC.grafite,
                  disabledForegroundColor: KC.fumo,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  T.continuar,
                  style: KT.body(cor: preenchido ? KC.sumi : KC.fumo),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PERGUNTA COM ESCOLHA ÚNICA ───────────────────────────────────────────────

class _PerguntaEscolha extends StatelessWidget {
  final String pergunta;
  final List<String> opcoes;
  final ValueChanged<String> aoEscolher;
  final String indicadorPagina;

  const _PerguntaEscolha({
    required this.pergunta,
    required this.opcoes,
    required this.aoEscolher,
    required this.indicadorPagina,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(indicadorPagina, style: KT.micro(cor: KC.fumo)),
            const SizedBox(height: 48),
            Text(pergunta, style: KT.displayL()),
            const SizedBox(height: 32),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: opcoes.length,
                itemBuilder: (_, i) {
                  return GestureDetector(
                    onTap: () => aoEscolher(opcoes[i]),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: KC.grafite, width: 1),
                        ),
                      ),
                      child: Text(opcoes[i], style: KT.body()),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
