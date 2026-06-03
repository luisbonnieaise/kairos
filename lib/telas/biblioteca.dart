import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/cache.dart';
import '../core/datas.dart';
import '../core/i18n.dart';
import '../main.dart';

class TelaBiblioteca extends StatefulWidget {
  const TelaBiblioteca({super.key});

  @override
  State<TelaBiblioteca> createState() => _TelaBibliotecaState();
}

class _TelaBibliotecaState extends State<TelaBiblioteca> {
  bool _carregando = true;
  bool _gerandoCarta = false;
  bool _temCartaNova = false;
  String? _erroCarta;

  static const _prefKeyCartaLida = 'carta_ultima_lida';

  int _completadasSemana = 0;
  int _totalReflexoes = 0;
  int _totalMensagens = 0;
  int _diasDesdeIngresso = 0;
  List<_PraticaComStreak> _praticas = [];
  List<Map<String, dynamic>> _cartas = [];

  @override
  void initState() {
    super.initState();
    _lerCache();   // paint instantâneo de estatísticas e cartas cacheadas
    _carregar();   // revalida do Supabase em segundo plano
    // Tutorial é disparado pelo Home ao chegar na aba.
  }

  // Pinta estatísticas, streaks e cartas do cache local. Números são
  // revalidados em seguida (poucos ms) — pequena defasagem é aceitável.
  void _lerCache() {
    final c = CacheLocal.lerMapa('biblioteca');
    if (c == null) return;
    final praticas = ((c['praticas'] as List?) ?? const []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return _PraticaComStreak(nome: m['nome'] as String, streak: m['streak'] as int? ?? 0);
    }).toList();
    final cartas = ((c['cartas'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      _completadasSemana = c['completadasSemana'] as int? ?? 0;
      _totalReflexoes = c['totalReflexoes'] as int? ?? 0;
      _totalMensagens = c['totalMensagens'] as int? ?? 0;
      _diasDesdeIngresso = c['diasIngresso'] as int? ?? 0;
      _temCartaNova = c['temCartaNova'] == true;
      _praticas = praticas;
      _cartas = cartas;
      _carregando = false;
    });
    cartaNovaNotifier.value = _temCartaNova;
  }

  void _gravarCache() {
    CacheLocal.gravar('biblioteca', {
      'completadasSemana': _completadasSemana,
      'totalReflexoes': _totalReflexoes,
      'totalMensagens': _totalMensagens,
      'diasIngresso': _diasDesdeIngresso,
      'temCartaNova': _temCartaNova,
      'praticas': _praticas.map((p) => {'nome': p.nome, 'streak': p.streak}).toList(),
      'cartas': _cartas,
    });
  }

  bool _ehHoraDeNovaCarta() {
    final agora = DateTime.now();
    // Domingo local após 21:00 — janela primária de geração
    if (agora.weekday == DateTime.sunday && agora.hour >= 21) return true;
    // Segunda a sexta — fallback caso o usuário não tenha aberto no domingo
    if (agora.weekday >= DateTime.monday && agora.weekday <= DateTime.friday) return true;
    // Sábado: só permite se já passaram pelo menos 21h desde o domingo anterior,
    // ou seja, a semana anterior está completamente encerrada (hora local >= 21
    // não se aplica ao sábado — sábado pertence à semana em andamento até domingo).
    // Sábado é excluído para evitar que a carta seja gerada com a semana incompleta.
    return false;
  }

  /// semana_inicio da carta atual (segunda) no formato YYYY-MM-DD.
  /// Lógica em core/datas.dart::semanaInicioISO (testável, mesma convenção
  /// do servidor: semana_fim = domingo mais recente, semana_inicio = -6 dias).
  String _semanaInicioAtual() => semanaInicioISO(DateTime.now());

  void _mostrarMensagemEspera() {
    if (!mounted) return;
    final frases = T.frasesEspera;
    final frase = frases[math.Random().nextInt(frases.length)];

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: KC.grafite,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(T.mentorLabel, style: KT.micro(cor: KC.kin)),
            const SizedBox(height: 6),
            Text(frase, style: KT.bodySerif(cor: KC.washi)),
          ],
        ),
      ),
    );
  }

  Future<void> _carregar({bool ehRefresh = false}) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Práticas e completadas da semana
      final agora = DateTime.now();
      final inicio = DateTime(agora.year, agora.month, agora.day)
          .subtract(const Duration(days: 6));
      final dataInicioStr = '${inicio.year.toString().padLeft(4, '0')}-'
          '${inicio.month.toString().padLeft(2, '0')}-'
          '${inicio.day.toString().padLeft(2, '0')}';

      // 5 queries em paralelo — economiza ~70% do tempo total
      final futures = await Future.wait<dynamic>([
        supabase
            .from('pratica_completadas')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .gte('data', dataInicioStr),
        supabase
            .from('reflexoes')
            .count(CountOption.exact)
            .eq('user_id', user.id),
        supabase
            .from('mensagens')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .eq('role', 'user'),
        BancoPraticas.carregar(),
        BancoRelatorios.carregar(),
      ]);

      final totalCompletadasSemana = futures[0] as int;
      final totalReflexoesCount   = futures[1] as int;
      final totalMensagensCount   = futures[2] as int;
      final praticasDados         = futures[3] as List<Map<String, dynamic>>;
      final cartas                = futures[4] as List<Map<String, dynamic>>;

      // Streak de cada prática em paralelo
      final streakFutures = praticasDados.map((p) async {
        final ultimos7 = await BancoPraticas.ultimos7Dias(p['id'] as String);
        int streak = 0;
        for (int i = ultimos7.length - 1; i >= 0; i--) {
          if (ultimos7[i]) {
            streak++;
          } else {
            break;
          }
        }
        return _PraticaComStreak(
          nome: p['nome'] as String,
          streak: streak,
        );
      });
      final praticasComStreak = await Future.wait(streakFutures);

      DateTime criadoEm;
      try {
        criadoEm = DateTime.parse(user.createdAt);
      } catch (_) {
        criadoEm = agora;
      }
      final diasIngresso = agora.difference(criadoEm).inDays;

      // Detecta carta nova (não lida)
      final prefs = await SharedPreferences.getInstance();
      final ultimaLida = prefs.getString(_prefKeyCartaLida) ?? '';
      final temNova = cartas.isNotEmpty &&
          (cartas.first['semana_inicio'] as String? ?? '') != ultimaLida;

      if (!mounted) return;
      setState(() {
        _completadasSemana = totalCompletadasSemana;
        _totalReflexoes = totalReflexoesCount;
        _totalMensagens = totalMensagensCount;
        _diasDesdeIngresso = diasIngresso;
        _praticas = praticasComStreak;
        _cartas = cartas;
        _temCartaNova = temNova;
        _carregando = false;
      });
      cartaNovaNotifier.value = temNova;
      _gravarCache();

      // Se for hora de uma nova carta e não existe carta dessa semana, gera automaticamente
      final semanaAtual = _semanaInicioAtual();
      final temCartaDessaSemana = cartas.any((c) => c['semana_inicio'] == semanaAtual);
      if (_ehHoraDeNovaCarta() && !temCartaDessaSemana && diasIngresso >= 1) {
        _gerarCarta();
      } else if (ehRefresh && temCartaDessaSemana) {
        // Já tem a carta da semana — mostra mensagem contemplativa do Mentor
        _mostrarMensagemEspera();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  Future<void> _gerarCarta() async {
    if (_gerandoCarta) return;
    setState(() {
      _gerandoCarta = true;
      _erroCarta = null;
    });
    try {
      await BancoRelatorios.gerar(semanaInicio: _semanaInicioAtual());
      final cartas = await BancoRelatorios.carregar();
      if (!mounted) return;
      setState(() {
        _cartas = cartas;
        _gerandoCarta = false;
      });
    } catch (_) {
      // Erro técnico não vai pra UI — só uma flag (mensagem traduzida exibida)
      if (!mounted) return;
      setState(() {
        _gerandoCarta = false;
        _erroCarta = 'erro';
      });
    }
  }

  Future<void> _abrirCarta(Map<String, dynamic> carta) async {
    HapticFeedback.lightImpact();

    // Marca como lida antes de abrir
    final semanaInicio = carta['semana_inicio'] as String? ?? '';
    if (_temCartaNova && semanaInicio.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyCartaLida, semanaInicio);
      if (mounted) setState(() => _temCartaNova = false);
      cartaNovaNotifier.value = false;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => _TelaCartaCompleta(carta: carta),
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
        onRefresh: () => _carregar(ehRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              KT.tituloGradiente(T.bibTitulo),
              const SizedBox(height: 8),
              Text(T.estudoSiMesmo, style: KT.caption()),

              const SizedBox(height: 48),
              KT.divisor(),
              const SizedBox(height: 32),

              if (_carregando)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text(T.carregando, style: KT.caption()),
                )
              else ...[
                // ── CARTA DO MENTOR ─────────────────────────────────
                Text(T.cartaMentor, style: KT.micro(cor: KC.kin)),
                const SizedBox(height: 12),
                Text(T.explicacaoCarta, style: KT.bodySerif(cor: KC.cinza)),
                const SizedBox(height: 24),

                if (_gerandoCarta)
                  _CardCartaCarregando()
                else if (_cartas.isEmpty)
                  _CardSemCarta(diasDesdeIngresso: _diasDesdeIngresso)
                else
                  _CardCarta(
                    carta: _cartas.first,
                    nova: _temCartaNova,
                    aoAbrir: () => _abrirCarta(_cartas.first),
                  ),

                if (_erroCarta != null) ...[
                  const SizedBox(height: 12),
                  Text(T.erroGerarCarta, style: KT.caption(cor: KC.aka)),
                ],

                if (_cartas.length > 1) ...[
                  const SizedBox(height: 32),
                  Text(T.cartasAnteriores, style: KT.micro()),
                  const SizedBox(height: 12),
                  for (final c in _cartas.skip(1))
                    _LinhaCartaAntiga(carta: c, aoAbrir: () => _abrirCarta(c)),
                ],

                const SizedBox(height: 48),
                KT.divisor(),
                const SizedBox(height: 32),

                // ── ESTATÍSTICAS ─────────────────────────────────────
                Text(T.estaSemana, style: KT.micro()),
                const SizedBox(height: 20),
                _LinhaMetrica(
                  numero: _completadasSemana.toString(),
                  rotulo: T.praticasCumpridas(_completadasSemana),
                ),

                const SizedBox(height: 40),
                KT.divisor(),
                const SizedBox(height: 32),

                Text(T.sequencias, style: KT.micro()),
                const SizedBox(height: 20),
                if (_praticas.isEmpty)
                  Text(T.semPraticasAtivas, style: KT.caption())
                else
                  ..._praticas.map((p) => _LinhaSequencia(pratica: p)),

                const SizedBox(height: 32),
                KT.divisor(),
                const SizedBox(height: 32),

                Text(T.totais, style: KT.micro()),
                const SizedBox(height: 20),
                _LinhaMetrica(
                  numero: _totalReflexoes.toString(),
                  rotulo: T.reflexoesEscritas(_totalReflexoes),
                ),
                const SizedBox(height: 16),
                _LinhaMetrica(
                  numero: _totalMensagens.toString(),
                  rotulo: T.conversasMentor(_totalMensagens),
                ),
                const SizedBox(height: 16),
                _LinhaMetrica(
                  numero: _diasDesdeIngresso.toString(),
                  rotulo: T.diasNoKairo(_diasDesdeIngresso),
                ),

                const SizedBox(height: 64),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── CARD DA CARTA DA SEMANA ──────────────────────────────────────────────────

class _CardCarta extends StatelessWidget {
  final Map<String, dynamic> carta;
  final bool nova;
  final VoidCallback aoAbrir;

  const _CardCarta({required this.carta, required this.nova, required this.aoAbrir});

  String _formatarData(String? data) {
    if (data == null) return '';
    final partes = data.split('-');
    if (partes.length < 3) return '';
    final dia = int.tryParse(partes[2]) ?? 1;
    final mes = int.tryParse(partes[1]) ?? 1;
    return T.formatarDiaMes(dia, mes);
  }

  @override
  Widget build(BuildContext context) {
    final inicio = _formatarData(carta['semana_inicio'] as String?);
    final fim    = _formatarData(carta['semana_fim'] as String?);

    return GestureDetector(
      onTap: aoAbrir,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: KC.card,
          border: Border.all(
            color: KC.kin,
            width: nova ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: nova
                  ? KC.kin.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: KC.escuro ? 0.22 : 0.07),
              blurRadius: nova ? 28 : 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                KairoEnso(tamanho: 24, cor: KC.acento),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(T.semanaDe(inicio, fim), style: KT.micro(cor: KC.kin)),
                ),
                if (nova)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: KC.kin.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(T.cartaNovaBadge, style: KT.micro(cor: KC.kin)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              (carta['observacoes'] as String?) ?? '',
              style: KT.bodySerif(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(T.lerCarta, style: KT.caption(cor: KC.kin)),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward, color: KC.kin, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardCartaCarregando extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: KC.grafite, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: KC.acento,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(T.mentorEscrevendo, style: KT.bodySerif(cor: KC.cinza)),
          ),
        ],
      ),
    );
  }
}

class _CardSemCarta extends StatelessWidget {
  final int diasDesdeIngresso;
  const _CardSemCarta({required this.diasDesdeIngresso});

  @override
  Widget build(BuildContext context) {
    final pronto = diasDesdeIngresso >= 1;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: KC.grafite, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(T.proximaCarta, style: KT.micro()),
          const SizedBox(height: 8),
          Text(
            pronto ? T.primeiraCartaPronta : T.bemvindoPratica,
            style: KT.bodySerif(cor: KC.cinza),
          ),
        ],
      ),
    );
  }
}

class _LinhaCartaAntiga extends StatelessWidget {
  final Map<String, dynamic> carta;
  final VoidCallback aoAbrir;

  const _LinhaCartaAntiga({required this.carta, required this.aoAbrir});

  String _formatarData(String? data) {
    if (data == null) return '';
    final partes = data.split('-');
    if (partes.length < 3) return '';
    final dia = int.tryParse(partes[2]) ?? 1;
    final mes = int.tryParse(partes[1]) ?? 1;
    return T.formatarDiaMes(dia, mes);
  }

  @override
  Widget build(BuildContext context) {
    final inicio = _formatarData(carta['semana_inicio'] as String?);
    final fim    = _formatarData(carta['semana_fim'] as String?);

    return GestureDetector(
      onTap: aoAbrir,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$inicio → $fim', style: KT.body()),
                  const SizedBox(height: 4),
                  Text(
                    (carta['observacoes'] as String?) ?? '',
                    style: KT.caption(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: KC.fumo, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── TELA DE CARTA COMPLETA ───────────────────────────────────────────────────

class _TelaCartaCompleta extends StatelessWidget {
  final Map<String, dynamic> carta;
  const _TelaCartaCompleta({required this.carta});

  String _formatarPeriodo() {
    final partesIni = (carta['semana_inicio'] as String? ?? '').split('-');
    final partesFim = (carta['semana_fim'] as String? ?? '').split('-');
    if (partesIni.length < 3 || partesFim.length < 3) return '';
    final diaI = int.tryParse(partesIni[2]) ?? 1;
    final mesI = int.tryParse(partesIni[1]) ?? 1;
    final diaF = int.tryParse(partesFim[2]) ?? 1;
    final mesF = int.tryParse(partesFim[1]) ?? 1;
    return '${T.formatarDiaMes(diaI, mesI)} → ${T.formatarDiaMes(diaF, mesF)}';
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
                    const SizedBox(height: 16),

                    KairoEnso(tamanho: 48, cor: KC.acento),
                    const SizedBox(height: 24),

                    Text(T.cartaMentor, style: KT.micro(cor: KC.kin)),
                    const SizedBox(height: 8),
                    Text(_formatarPeriodo(), style: KT.caption()),

                    const SizedBox(height: 40),

                    _Secao(rotulo: T.observacoes, texto: carta['observacoes'] as String?),
                    if ((carta['padroes'] as String?)?.isNotEmpty ?? false)
                      _Secao(rotulo: T.padroes, texto: carta['padroes'] as String?),
                    if ((carta['conquistas'] as String?)?.isNotEmpty ?? false)
                      _Secao(rotulo: T.conquistas, texto: carta['conquistas'] as String?),
                    if ((carta['pergunta'] as String?)?.isNotEmpty ?? false)
                      _Secao(rotulo: T.paraProximaSemana, texto: carta['pergunta'] as String?, destaque: true),

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

class _Secao extends StatelessWidget {
  final String rotulo;
  final String? texto;
  final bool destaque;

  const _Secao({
    required this.rotulo,
    required this.texto,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: KT.micro(cor: destaque ? KC.kin : KC.cinza)),
          const SizedBox(height: 12),
          Text(
            texto ?? '',
            style: KT.bodySerif(cor: destaque ? KC.washi : KC.washi),
          ),
        ],
      ),
    );
  }
}

// ── COMPONENTES AUXILIARES (estatísticas) ────────────────────────────────────

class _LinhaMetrica extends StatelessWidget {
  final String numero;
  final String rotulo;

  const _LinhaMetrica({required this.numero, required this.rotulo});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(numero, style: KT.displayL()),
        const SizedBox(width: 12),
        Expanded(child: Text(rotulo, style: KT.bodySerif(cor: KC.cinza))),
      ],
    );
  }
}

class _LinhaSequencia extends StatelessWidget {
  final _PraticaComStreak pratica;

  const _LinhaSequencia({required this.pratica});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(child: Text(pratica.nome, style: KT.body())),
          if (pratica.streak == 0)
            Text('—', style: KT.body(cor: KC.fumo))
          else ...[
            Text(pratica.streak.toString(), style: KT.body(cor: KC.matcha)),
            const SizedBox(width: 6),
            Text(T.diasStreak(pratica.streak), style: KT.caption(cor: KC.fumo)),
          ],
        ],
      ),
    );
  }
}

class _PraticaComStreak {
  final String nome;
  final int streak;
  _PraticaComStreak({required this.nome, required this.streak});
}
