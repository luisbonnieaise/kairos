import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';

// (perguntas vêm de T.perguntasJardim* — i18n.dart)


class TelaJardim extends StatefulWidget {
  const TelaJardim({super.key});

  @override
  State<TelaJardim> createState() => _TelaJardimState();
}

class _TelaJardimState extends State<TelaJardim> {
  List<_Reflexao> _reflexoes = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Tutorial.mostrar(
        context: context,
        chave: 'jardim',
        titulo: T.tutorialJardimTitulo,
        texto: T.tutorialJardimTexto,
      );
    });
  }

  Future<void> _carregar() async {
    try {
      final dados = await BancoReflexoes.carregar();

      if (!mounted) return;
      setState(() {
        _reflexoes = dados.map((d) => _Reflexao(
              data: DateTime.tryParse(d['created_at'] as String? ?? '') ?? DateTime.now(),
              momento: d['momento'] as String,
              pergunta: d['pergunta'] as String,
              resposta: d['resposta'] as String,
            )).toList();
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  String _momentoAtual() {
    final hora = DateTime.now().hour;
    // Antes das 8 → ainda na "noite" (carta da noite passada)
    if (hora < 8) return T.noite;
    // 8h-13h → manhã
    if (hora < 13) return T.manha;
    // 13h-20h → tarde
    if (hora < 20) return T.meiodia;
    // 20h+ → noite
    return T.noite;
  }

  String _perguntaDoMomento() {
    final agora = DateTime.now();
    final hora = agora.hour;

    // Antes das 8h → mostra a pergunta da NOITE do dia anterior
    if (hora < 8) {
      final ontem = agora.subtract(const Duration(days: 1));
      final seedOntem = ontem.year * 1000 + ontem.month * 50 + ontem.day;
      final banco = T.perguntasJardimNoite;
      return banco[seedOntem % banco.length];
    }

    // Pergunta muda a cada dia (seed determinístico)
    final seed = agora.year * 1000 + agora.month * 50 + agora.day;

    List<String> banco;
    if (hora < 13) {
      banco = T.perguntasJardimManha;     // 8h-13h
    } else if (hora < 20) {
      banco = T.perguntasJardimTarde;     // 13h-20h
    } else {
      banco = T.perguntasJardimNoite;     // 20h+
    }
    return banco[seed % banco.length];
  }

  void _abrirEscrita() {
    HapticFeedback.lightImpact();
    final momento = _momentoAtual();
    final pergunta = _perguntaDoMomento();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _TelaEscrita(
          momento: momento,
          pergunta: pergunta,
          aoSalvar: (resposta) async {
            await BancoReflexoes.salvar(
              momento: momento,
              pergunta: pergunta,
              resposta: resposta,
            );
            await _carregar();
          },
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        color: KC.kin,
        backgroundColor: KC.sumi,
        onRefresh: _carregar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text(T.jardimTitulo, style: KT.displayL()),
              const SizedBox(height: 8),
              Text(T.reflexaoGuiada, style: KT.caption()),

              const SizedBox(height: 40),
              Divider(color: KC.grafite, height: 1, thickness: 1),
              const SizedBox(height: 32),

              Text(_momentoAtual().toUpperCase(), style: KT.micro(cor: KC.kin)),
              const SizedBox(height: 12),
              Text(_perguntaDoMomento(), style: KT.bodySerif()),

              const SizedBox(height: 24),

              GestureDetector(
                onTap: _abrirEscrita,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    border: Border.all(color: KC.grafite, width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text(T.escrever, style: KT.body())),
                ),
              ),

              const SizedBox(height: 48),

              Text(T.reflexoesAnteriores, style: KT.micro()),
              const SizedBox(height: 24),

              if (_carregando)
                Text(T.carregando, style: KT.caption())
              else if (_reflexoes.isEmpty)
                Text(T.vazioComece, style: KT.caption())
              else
                ..._reflexoes.map((r) => _ItemReflexao(reflexao: r)),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemReflexao extends StatelessWidget {
  final _Reflexao reflexao;
  const _ItemReflexao({required this.reflexao});

  String _formatarData(DateTime data) {
    final agora = DateTime.now();
    final dataLocal = data.toLocal();
    final dif = DateTime(agora.year, agora.month, agora.day)
        .difference(DateTime(dataLocal.year, dataLocal.month, dataLocal.day))
        .inDays;
    if (dif == 0) return T.hoje;
    if (dif == 1) return T.ontem;
    return T.diasAtras(dif);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(reflexao.momento.toUpperCase(), style: KT.micro()),
              const SizedBox(width: 16),
              Text(_formatarData(reflexao.data), style: KT.micro(cor: KC.fumo)),
            ],
          ),
          const SizedBox(height: 8),
          Text(reflexao.pergunta, style: KT.caption(cor: KC.cinza)),
          const SizedBox(height: 8),
          Text(reflexao.resposta, style: KT.bodySerif()),
          const SizedBox(height: 16),
          Divider(color: KC.grafite, height: 1, thickness: 1),
        ],
      ),
    );
  }
}

class _TelaEscrita extends StatefulWidget {
  final String momento;
  final String pergunta;
  final Future<void> Function(String) aoSalvar;

  const _TelaEscrita({
    required this.momento,
    required this.pergunta,
    required this.aoSalvar,
  });

  @override
  State<_TelaEscrita> createState() => _TelaEscritaState();
}

class _TelaEscritaState extends State<_TelaEscrita> {
  final _controller = TextEditingController();
  bool _salvando = false;

  Future<void> _salvar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _salvando) return;
    HapticFeedback.mediumImpact();
    setState(() => _salvando = true);
    try {
      await widget.aoSalvar(texto);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _salvando = false);
    }
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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: KC.cinza, size: 22),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _salvando ? null : _salvar,
                    child: Text(
                      _salvando ? T.salvando : T.salvar,
                      style: KT.body(cor: _salvando ? KC.fumo : KC.kin),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.momento.toUpperCase(), style: KT.micro(cor: KC.kin)),
                    const SizedBox(height: 16),
                    Text(widget.pergunta, style: KT.bodySerif()),
                    const SizedBox(height: 32),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: KT.bodySerif(cor: KC.washi),
                        cursorColor: KC.kin,
                        cursorWidth: 1,
                        maxLines: null,
                        maxLength: 5000,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: T.escrevaSemPressa,
                          hintStyle: KT.bodySerif(cor: KC.fumo),
                        ),
                      ),
                    ),
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

class _Reflexao {
  final DateTime data;
  final String momento;
  final String pergunta;
  final String resposta;

  _Reflexao({
    required this.data,
    required this.momento,
    required this.pergunta,
    required this.resposta,
  });
}
