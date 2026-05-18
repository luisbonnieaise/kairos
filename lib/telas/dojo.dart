import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/i18n.dart';
import '../core/tutorial.dart';

class TelaDojo extends StatefulWidget {
  const TelaDojo({super.key});

  @override
  State<TelaDojo> createState() => _TelaDojoState();
}

class _TelaDojoState extends State<TelaDojo> {
  List<_Pratica> _praticas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Tutorial.mostrar(
        context: context,
        chave: 'dojo',
        titulo: T.tutorialDojoTitulo,
        texto: T.tutorialDojoTexto,
      );
    });
  }

  Future<void> _carregar() async {
    try {
      final dados = await BancoPraticas.carregar();

      // Paraleliza as queries de últimos 7 dias (uma por prática)
      final praticasFutures = dados.map((d) async {
        final ultimos = await BancoPraticas.ultimos7Dias(d['id'] as String);
        return _Pratica(
          id: d['id'] as String,
          nome: d['nome'] as String,
          duracao: (d['duracao'] as String?) ?? '',
          categoria: (d['categoria'] as String?) ?? '',
          ultimos7Dias: ultimos,
        );
      });
      final praticas = await Future.wait(praticasFutures);

      if (!mounted) return;
      setState(() {
        _praticas = praticas;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  void _abrirBiblioteca() {
    if (_praticas.length >= 5) {
      _mostrarLimite();
      return;
    }

    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _BibliotecaPraticas(
        aoAdicionar: (nome, duracao, categoria) async {
          Navigator.pop(context);
          await BancoPraticas.adicionar(
            nome: nome,
            duracao: duracao,
            categoria: categoria,
          );
          await _carregar();
        },
      ),
    );
  }

  void _mostrarLimite() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(T.limite, style: KT.micro(cor: KC.kin)),
              const SizedBox(height: 12),
              Text(T.cincoPraticasLimite, style: KT.bodySerif()),
              const SizedBox(height: 12),
              Text(T.removaUma, style: KT.body(cor: KC.cinza)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KC.washi,
                    side: BorderSide(color: KC.grafite, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.entendi, style: KT.body()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remover(String id) async {
    HapticFeedback.lightImpact();

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
              Text(T.confirmarExcluirPratica, style: KT.titulo()),
              const SizedBox(height: 12),
              Text(T.perdaEvolucao, style: KT.bodySerif(cor: KC.cinza)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KC.aka,
                    foregroundColor: KC.washi,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.excluir, style: KT.body(cor: KC.washi)),
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
                  child: Text(T.cancelar, style: KT.body()),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmou != true) return;
    await BancoPraticas.remover(id);
    await _carregar();
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

              KT.tituloGradiente(T.dojo),
              const SizedBox(height: 8),
              Text(T.dojoNPraticasAtivas(_praticas.length), style: KT.caption()),

              const SizedBox(height: 40),
              KT.divisor(),
              const SizedBox(height: 32),

              if (_carregando)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(T.carregando, style: KT.caption()),
                  ),
                )
              else if (_praticas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(T.semPraticas, style: KT.bodySerif(cor: KC.cinza)),
                )
              else
                ..._praticas.map((p) => _ItemPratica(
                      pratica: p,
                      aoRemover: () => _remover(p.id),
                    )),

              const SizedBox(height: 16),

              GestureDetector(
                onTap: _abrirBiblioteca,
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
                            Icons.add,
                            size: 28,
                            color: KC.acento.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(T.escolhaPratica, style: KT.body()),
                          ],
                        ),
                      ),
                    ],
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

// ── ITEM DE PRÁTICA ──────────────────────────────────────────────────────────

class _ItemPratica extends StatelessWidget {
  final _Pratica pratica;
  final VoidCallback aoRemover;

  const _ItemPratica({required this.pratica, required this.aoRemover});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pratica.categoria.isNotEmpty) ...[
                      Text(
                        switch (pratica.categoria) {
                          'Mente'      => T.catMente,
                          'Corpo'      => T.catCorpo,
                          'Disciplina' => T.catDisciplina,
                          'Relações'   => T.catRelacoes,
                          'Trabalho'   => T.catTrabalho,
                          _ => pratica.categoria,
                        }.toUpperCase(),
                        style: KT.micro(),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(pratica.nome, style: KT.body()),
                    if (pratica.duracao.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(pratica.duracao, style: KT.caption()),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: aoRemover,
                icon: Icon(Icons.close, size: 18, color: KC.fumo),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),

          const SizedBox(height: 12),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(T.ultimos7Dias, style: KT.micro(cor: KC.fumo)),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(7, (i) {
                  final dia   = DateTime.now().subtract(Duration(days: 6 - i));
                  final letra = T.diaSemanaAbrev(dia.weekday);
                  final feito = pratica.ultimos7Dias[i];
                  final eHoje = i == 6;
                  final corLetra = eHoje ? KC.acento : KC.fumo;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(
                      children: [
                        Text(letra, style: KT.micro(cor: corLetra)),
                        const SizedBox(height: 4),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: feito ? KC.matcha : Colors.transparent,
                            border: Border.all(
                              color: feito ? KC.matcha : KC.grafite,
                              width: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),

          const SizedBox(height: 16),
          KT.divisor(),
        ],
      ),
    );
  }
}

// ── BIBLIOTECA DE PRÁTICAS ───────────────────────────────────────────────────

class _PraticaSugerida {
  final String nome;
  final String duracao;
  const _PraticaSugerida(this.nome, this.duracao);
}

// Carregada dinamicamente do i18n para refletir o idioma atual.
Map<String, List<_PraticaSugerida>> get _biblioteca {
  final fonte = T.bibliotecaPraticas;
  return fonte.map((cat, lista) => MapEntry(
    cat,
    lista.map((p) => _PraticaSugerida(p['nome']!, p['duracao']!)).toList(),
  ));
}

class _BibliotecaPraticas extends StatefulWidget {
  final void Function(String nome, String duracao, String categoria) aoAdicionar;
  const _BibliotecaPraticas({required this.aoAdicionar});

  @override
  State<_BibliotecaPraticas> createState() => _BibliotecaPraticasState();
}

class _BibliotecaPraticasState extends State<_BibliotecaPraticas> {
  String _categoriaAtiva = 'Mente';

  void _abrirPersonalizada(BuildContext ctxPai) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: ctxPai,
      backgroundColor: KC.sumi,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SheetPersonalizada(
        categoria: _categoriaAtiva,
        aoAdicionar: (nome, duracao) {
          widget.aoAdicionar(nome, duracao.isEmpty ? '—' : duracao, _categoriaAtiva);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final praticas = _biblioteca[_categoriaAtiva] ?? const <_PraticaSugerida>[];

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
              child: Column(
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
                  const SizedBox(height: 24),
                  Text(T.bibliotecaPratica, style: KT.titulo()),
                  const SizedBox(height: 4),
                  Text(T.escolhaPratica, style: KT.caption()),
                ],
              ),
            ),

            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                children: _biblioteca.keys.map((cat) {
                  final ativo = cat == _categoriaAtiva;
                  final nomeTraduzido = switch (cat) {
                    'Mente'      => T.catMente,
                    'Corpo'      => T.catCorpo,
                    'Disciplina' => T.catDisciplina,
                    'Relações'   => T.catRelacoes,
                    'Trabalho'   => T.catTrabalho,
                    _ => cat,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: GestureDetector(
                      onTap: () => setState(() => _categoriaAtiva = cat),
                      child: Column(
                        children: [
                          Text(
                            nomeTraduzido.toUpperCase(),
                            style: KT.micro(cor: ativo ? KC.washi : KC.fumo),
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: ativo ? 20 : 0,
                            height: 1,
                            color: KC.kin,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),
            KT.divisor(),

            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                itemCount: praticas.length + 1, // +1 pro botão de personalizada
                separatorBuilder: (_, _) => KT.divisor(),
                itemBuilder: (_, i) {
                  // Último item: botão de adicionar personalizada
                  if (i == praticas.length) {
                    return GestureDetector(
                      onTap: () => _abrirPersonalizada(context),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                T.adicionarPersonalizada,
                                style: KT.body(cor: KC.kin),
                              ),
                            ),
                            Icon(Icons.add, color: KC.kin, size: 18),
                          ],
                        ),
                      ),
                    );
                  }

                  final p = praticas[i];
                  return GestureDetector(
                    onTap: () => widget.aoAdicionar(p.nome, p.duracao, _categoriaAtiva),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.nome, style: KT.body()),
                                if (p.duracao != '—') ...[
                                  const SizedBox(height: 4),
                                  Text(p.duracao, style: KT.caption()),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.add, color: KC.fumo, size: 18),
                        ],
                      ),
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

// ── SHEET DE ADICIONAR PRÁTICA PERSONALIZADA ─────────────────────────────────

class _SheetPersonalizada extends StatefulWidget {
  final String categoria;
  final void Function(String nome, String duracao) aoAdicionar;

  const _SheetPersonalizada({
    required this.categoria,
    required this.aoAdicionar,
  });

  @override
  State<_SheetPersonalizada> createState() => _SheetPersonalizadaState();
}

class _SheetPersonalizadaState extends State<_SheetPersonalizada> {
  final _nome = TextEditingController();
  final _duracao = TextEditingController();

  String _categoriaTraduzida() => switch (widget.categoria) {
        'Mente' => T.catMente,
        'Corpo' => T.catCorpo,
        'Disciplina' => T.catDisciplina,
        'Relações' => T.catRelacoes,
        'Trabalho' => T.catTrabalho,
        _ => widget.categoria,
      };

  void _adicionar() {
    final nome = _nome.text.trim();
    if (nome.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.aoAdicionar(nome, _duracao.text.trim());
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nome.dispose();
    _duracao.dispose();
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
            Text(_categoriaTraduzida().toUpperCase(), style: KT.micro(cor: KC.kin)),
            const SizedBox(height: 8),
            Text(T.novaPraticaPersonalizada, style: KT.titulo()),
            const SizedBox(height: 32),

            // Nome
            Text(T.nomeDaPratica, style: KT.micro()),
            const SizedBox(height: 8),
            TextField(
              controller: _nome,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              style: KT.body(),
              cursorColor: KC.kin,
              cursorWidth: 1,
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
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 32),

            // Duração
            Text(T.duracaoOpcional, style: KT.micro()),
            const SizedBox(height: 8),
            TextField(
              controller: _duracao,
              maxLength: 15,
              style: KT.body(),
              cursorColor: KC.kin,
              cursorWidth: 1,
              decoration: InputDecoration(
                hintText: T.exemploDuracao,
                hintStyle: KT.body(cor: KC.fumo),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: KC.grafite, width: 1),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: KC.grafite, width: 1),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: KC.cinza, width: 1),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _adicionar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KC.washi,
                  foregroundColor: KC.sumi,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(T.adicionar, style: KT.body(cor: KC.sumi)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── MODELO ────────────────────────────────────────────────────────────────────

class _Pratica {
  final String id;
  final String nome;
  final String duracao;
  final String categoria;
  final List<bool> ultimos7Dias;

  _Pratica({
    required this.id,
    required this.nome,
    required this.duracao,
    required this.categoria,
    required this.ultimos7Dias,
  });
}
