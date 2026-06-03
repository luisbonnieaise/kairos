import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/cache.dart';
import '../core/i18n.dart';
import '../main.dart' show jardimNovaNotifier;

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
    _lerCache();   // paint instantâneo das reflexões cacheadas
    _carregar();   // revalida do Supabase em segundo plano
    // Tutorial é disparado pelo Home ao chegar na aba.
  }

  _Reflexao _mapear(Map<String, dynamic> d) => _Reflexao(
        data: DateTime.tryParse(d['created_at'] as String? ?? '') ?? DateTime.now(),
        momento: d['momento'] as String,
        pergunta: d['pergunta'] as String,
        resposta: d['resposta'] as String,
      );

  void _lerCache() {
    final raw = CacheLocal.lerLista('jardim_reflexoes');
    if (raw == null) return;
    setState(() {
      _reflexoes = raw.map(_mapear).toList();
      _carregando = false;
    });
    jardimNovaNotifier.value = !_jaRespondeuAtual;
  }

  Future<void> _carregar() async {
    try {
      final dados = await BancoReflexoes.carregar();

      if (!mounted) return;
      setState(() {
        _reflexoes = dados.map(_mapear).toList();
        _carregando = false;
      });
      CacheLocal.gravar('jardim_reflexoes', dados);
      // Notifica a navbar: ponto vermelho quando pergunta não respondida
      jardimNovaNotifier.value = !_jaRespondeuAtual;
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

  bool get _jaRespondeuAtual {
    if (_carregando) return false;
    final atual = _perguntaDoMomento();
    return _reflexoes.any((r) => r.pergunta == atual);
  }

  void _abrirEscrita() {
    HapticFeedback.lightImpact();
    final momento = _momentoAtual();
    final pergunta = _perguntaDoMomento();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => _TelaEscrita(
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
        transitionsBuilder: (_, anim, _, child) =>
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
              KT.tituloGradiente(T.jardimTitulo),
              const SizedBox(height: 8),
              Text(T.reflexaoGuiada, style: KT.caption()),

              const SizedBox(height: 40),
              KT.divisor(),
              const SizedBox(height: 32),

              Text(_momentoAtual().toUpperCase(), style: KT.micro(cor: KC.kin)),
              const SizedBox(height: 12),
              Text(_perguntaDoMomento(), style: KT.bodySerif()),

              const SizedBox(height: 24),

              GestureDetector(
                onTap: _jaRespondeuAtual ? null : _abrirEscrita,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _jaRespondeuAtual ? 0.55 : 1.0,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
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
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Icon(
                              _jaRespondeuAtual
                                  ? Icons.check_circle_outline
                                  : Icons.edit_outlined,
                              size: 22,
                              color: _jaRespondeuAtual
                                  ? KC.matcha
                                  : KC.acento.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _jaRespondeuAtual ? T.jaRespondida : T.escrever,
                                style: KT.body(),
                              ),
                              if (_jaRespondeuAtual) ...[
                                const SizedBox(height: 4),
                                Text(T.novaPerguntaEmBreve, style: KT.caption()),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
          KT.divisor(),
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
