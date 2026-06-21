import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import '../core/kairo_tema.dart';
import '../core/claude_api.dart';
import '../core/banco.dart';
import '../core/transcricao.dart';
import '../core/i18n.dart';
import 'premium.dart';

class TelaMentor extends StatefulWidget {
  const TelaMentor({super.key});

  @override
  State<TelaMentor> createState() => _TelaMentorState();
}

class _TelaMentorState extends State<TelaMentor> {
  // Teto de gravação: 2 minutos. Casa com o limite de tamanho do bucket/função.
  static const _maxGravacaoMs = 120 * 1000;
  // Abaixo disso a gravação é descartada (toque acidental no microfone).
  static const _minGravacaoMs = 1000;

  final List<_Mensagem> _mensagens = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _pensando = false;

  // Paginação reversa do histórico (puxar a conversa pra baixo carrega o mais
  // antigo). `_maisAntiga` é o cursor (created_at da mensagem mais antiga em
  // tela); `_temMaisHistorico` vira false quando uma página vem incompleta.
  DateTime? _maisAntiga;
  bool _temMaisHistorico = true;
  bool _carregandoAntigas = false;

  // Estado de texto (alterna entre o botão de microfone e o de enviar).
  bool _temTexto = false;

  // Estado de gravação de voz.
  final _gravador = AudioRecorder();
  bool _gravando = false;
  Timer? _timerGravacao;
  int _msGravacao = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextoMudou);
    _carregarHistorico();
    // Tutorial é disparado pelo Home ao chegar na aba.
  }

  void _onTextoMudou() {
    final tem = _controller.text.trim().isNotEmpty;
    if (tem != _temTexto) setState(() => _temTexto = tem);
  }

  Future<void> _carregarHistorico() async {
    try {
      final perfil = await BancoPerfil.carregar();
      final nome = (perfil?['nome'] as String?)?.trim() ?? '';
      // Ao abrir, a conversa anterior fica OCULTA (começa limpa). Só checamos
      // se há histórico — pra ligar o hint e o gesto de puxar pra baixo.
      final temHistorico = await BancoMensagens.existeHistorico();

      if (!mounted) return;

      setState(() {
        if (temHistorico) {
          // Cursor = agora: a primeira puxada traz as mensagens mais recentes,
          // e cada puxada seguinte vai mais pra trás no tempo.
          _maisAntiga = DateTime.now();
          _temMaisHistorico = true;
        } else {
          // Sem histórico: saudação de boas-vindas, sem hint nem gesto.
          _mensagens.add(_Mensagem(texto: T.mentorSaudacao(nome), doMentor: true));
          _temMaisHistorico = false;
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
        _temMaisHistorico = false;
      });
    }
  }

  /// Puxar a conversa pra baixo (no topo) carrega a página anterior do
  /// histórico e a prepende. Cursor = `_maisAntiga`; para quando uma página
  /// vier incompleta (`_temMaisHistorico` = false).
  Future<void> _carregarMaisAntigas() async {
    if (_carregandoAntigas || !_temMaisHistorico || _maisAntiga == null) return;
    setState(() => _carregandoAntigas = true);
    try {
      final antigas = await BancoMensagens.carregarAntigas(antesDe: _maisAntiga!);
      if (!mounted) return;
      setState(() {
        if (antigas.isEmpty) {
          _temMaisHistorico = false;
        } else {
          _mensagens.insertAll(0, antigas.map(_mensagemDeRegistro));
          _maisAntiga = _createdAt(antigas.first);
          _temMaisHistorico = antigas.length >= BancoMensagens.pagina;
        }
      });
    } catch (_) {
      // Falha silenciosa: mantém o que já está em tela.
    } finally {
      if (mounted) setState(() => _carregandoAntigas = false);
    }
  }

  _Mensagem _mensagemDeRegistro(Map<String, dynamic> m) => _Mensagem(
        texto: (m['conteudo'] as String?) ?? '',
        doMentor: m['role'] == 'assistant',
        audioPathRemoto: m['audio_path'] as String?,
        audioDuracaoMs: m['audio_duracao_ms'] as int?,
      );

  DateTime? _createdAt(Map<String, dynamic> m) =>
      DateTime.tryParse((m['created_at'] as String?) ?? '');

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _pensando || _gravando) return;

    HapticFeedback.lightImpact();

    setState(() {
      _mensagens.add(_Mensagem(texto: texto, doMentor: false));
      _controller.clear();
    });

    _rolarParaBaixo();

    // Salva a mensagem do usuário em paralelo (não bloqueia a resposta)
    BancoMensagens.salvar(role: 'user', conteudo: texto);

    await _responderMentor();
  }

  /// Pede ao Mentor a próxima resposta a partir do histórico atual em tela.
  /// Compartilhado pelo envio de texto e pelo de voz (após transcrever).
  Future<void> _responderMentor() async {
    setState(() => _pensando = true);
    _rolarParaBaixo();

    try {
      final inicio = DateTime.now();

      final historico = _mensagens
          .where((m) => !(m == _mensagens.first && m.doMentor))
          // Bolhas de voz sem transcrição (silêncio) não vão pro contexto.
          .where((m) => m.texto.trim().isNotEmpty)
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
      if (e.toString().contains('precisa_assinar')) {
        setState(() => _pensando = false);
        _abrirPaywall();
      } else {
        setState(() {
          _mensagens.add(_Mensagem(texto: T.mentorErro, doMentor: true));
          _pensando = false;
        });
      }
    }

    _rolarParaBaixo();
  }

  // ── GRAVAÇÃO DE VOZ ─────────────────────────────────────────────────────────

  Future<void> _iniciarGravacao() async {
    if (_pensando || _gravando) return;
    try {
      if (!await _gravador.hasPermission()) {
        _snack(T.mentorMicNegado);
        return;
      }
      final caminho =
          '${Directory.systemTemp.path}/kairo_voz_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // AAC LC mono — leve e suficiente para fala (entrada do Whisper).
      await _gravador.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: caminho,
      );

      HapticFeedback.lightImpact();
      setState(() {
        _gravando = true;
        _msGravacao = 0;
      });

      _timerGravacao = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _msGravacao += 200);
        if (_msGravacao >= _maxGravacaoMs) _pararEEnviarGravacao();
      });
    } catch (e) {
      debugPrint('Erro ao iniciar gravação: $e');
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _cancelarGravacao() async {
    _timerGravacao?.cancel();
    try {
      await _gravador.cancel(); // descarta o arquivo
    } catch (_) {}
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() => _gravando = false);
  }

  Future<void> _pararEEnviarGravacao() async {
    if (!_gravando) return;
    _timerGravacao?.cancel();
    final duracaoMs = _msGravacao;

    String? caminho;
    try {
      caminho = await _gravador.stop();
    } catch (e) {
      debugPrint('Erro ao parar gravação: $e');
    }

    if (!mounted) return;
    setState(() => _gravando = false);

    if (caminho == null) return;

    if (duracaoMs < _minGravacaoMs) {
      _snack(T.mentorAudioCurto);
      try {
        await File(caminho).delete();
      } catch (_) {}
      return;
    }

    HapticFeedback.lightImpact();
    await _processarAudio(caminho, duracaoMs);
  }

  /// Faz upload do áudio, transcreve via Edge Function e — havendo texto —
  /// segue para a resposta do Mentor. A bolha de voz aparece imediatamente,
  /// já tocável, no estado "transcrevendo".
  Future<void> _processarAudio(String caminhoLocal, int duracaoMs) async {
    final msg = _Mensagem(
      texto: '',
      doMentor: false,
      audioPathLocal: caminhoLocal,
      audioDuracaoMs: duracaoMs,
      transcrevendo: true,
    );
    setState(() => _mensagens.add(msg));
    _rolarParaBaixo();

    try {
      final remoto = await BancoAudios.enviar(caminhoLocal);
      final texto = await Transcricao.transcrever(
        audioPath: remoto,
        duracaoMs: duracaoMs,
      );

      if (!mounted) return;

      // Persiste a bolha de voz (mesmo sem transcrição, para poder reouvir).
      BancoMensagens.salvar(
        role: 'user',
        conteudo: texto.trim(),
        audioPath: remoto,
        audioDuracaoMs: duracaoMs,
      );

      setState(() {
        msg.transcrevendo = false;
        msg.texto = texto.trim();
        msg.audioPathRemoto = remoto;
      });

      if (texto.trim().isEmpty) {
        _snack(T.mentorAudioVazio);
        _rolarParaBaixo();
        return;
      }

      await _responderMentor();
    } catch (e) {
      if (!mounted) return;
      setState(() => msg.transcrevendo = false);
      final codigo = e.toString();
      if (codigo.contains('precisa_assinar')) {
        _abrirPaywall();
      } else {
        _snack(codigo.contains('rate_limit') ? T.mentorAudioLimite : T.mentorAudioErro);
      }
      _rolarParaBaixo();
    }
  }

  /// Recurso premium acionado sem assinatura ativa (403 do servidor): avisa e
  /// leva ao paywall. Cobre tanto o chat de texto quanto a mensagem de voz.
  void _abrirPaywall() {
    if (!mounted) return;
    _snack(T.mentorPrecisaAssinar);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TelaPremium()),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: KT.body()),
      backgroundColor: KC.card,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
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

  /// Mensagem sutil (baixa opacidade) no topo do fluxo: indica que puxar pra
  /// baixo revela as conversas anteriores. Some quando o histórico acaba.
  Widget _hintHistorico() => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Center(
          child: Opacity(
            opacity: 0.45,
            child: Text(
              T.mentorPuxarHistorico,
              style: KT.caption(),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );

  @override
  void dispose() {
    _timerGravacao?.cancel();
    _gravador.dispose();
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

          // Fluxo de mensagens — sem balões, texto puro. Puxar pra baixo no
          // topo carrega o histórico mais antigo (conversas anteriores).
          Expanded(
            child: RefreshIndicator(
              onRefresh: _carregarMaisAntigas,
              color: KC.acento,
              backgroundColor: KC.card,
              edgeOffset: 8,
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                itemCount: (_temMaisHistorico ? 1 : 0) +
                    _mensagens.length +
                    (_pensando ? 1 : 0),
                itemBuilder: (context, i) {
                  // Hint sutil no topo enquanto houver histórico a revelar.
                  if (_temMaisHistorico && i == 0) return _hintHistorico();
                  final idx = _temMaisHistorico ? i - 1 : i;
                  if (_pensando && idx == _mensagens.length) {
                    return const _IndicadorPensando();
                  }
                  return _BolhaMensagem(mensagem: _mensagens[idx]);
                },
              ),
            ),
          ),

          // Campo de entrada — alterna entre texto e barra de gravação
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 16,
            ),
            child: _gravando ? _barraGravacao() : _barraEntrada(),
          ),
        ],
      ),
    );
  }

  // Barra de entrada padrão (texto). O botão à direita vira microfone quando
  // não há texto digitado, e seta de enviar quando há.
  Widget _barraEntrada() {
    return Container(
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
            onTap: _pensando ? null : (_temTexto ? _enviar : _iniciarGravacao),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _temTexto ? Icons.arrow_upward : Icons.mic_none_rounded,
                color: _pensando ? KC.textoSuave : KC.acento,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Barra exibida durante a gravação: cancelar · ponto pulsante · tempo · enviar.
  Widget _barraGravacao() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          GestureDetector(
            onTap: _cancelarGravacao,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, color: KC.textoSuave, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          const _PontoGravando(),
          const SizedBox(width: 12),
          Text(_formatarTempo(_msGravacao), style: KT.body()),
          const Spacer(),
          GestureDetector(
            onTap: _pararEEnviarGravacao,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KC.acento,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatarTempo(int ms) {
    final totalSeg = ms ~/ 1000;
    final m = (totalSeg ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeg % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── PONTO PULSANTE DE GRAVAÇÃO ────────────────────────────────────────────────

class _PontoGravando extends StatefulWidget {
  const _PontoGravando();

  @override
  State<_PontoGravando> createState() => _PontoGravandoState();
}

class _PontoGravandoState extends State<_PontoGravando>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_ctrl),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFE05A4E),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── PLAYER DE VOZ (balão reproduzível) ────────────────────────────────────────

class _PlayerAudio extends StatefulWidget {
  final String? caminhoLocal; // arquivo recém-gravado (toca do disco)
  final String? caminhoRemoto; // caminho no bucket (replay do histórico)
  final int? duracaoMs;

  const _PlayerAudio({
    super.key,
    this.caminhoLocal,
    this.caminhoRemoto,
    this.duracaoMs,
  });

  @override
  State<_PlayerAudio> createState() => _PlayerAudioState();
}

class _PlayerAudioState extends State<_PlayerAudio> {
  final _player = AudioPlayer();
  PlayerState _estado = PlayerState.stopped;
  Duration _posicao = Duration.zero;
  Duration _total = Duration.zero;
  Source? _fonte;
  bool _carregando = false;

  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    // Categoria playback para o áudio ser audível mesmo com o switch de
    // silêncio no iOS (mensagem de voz é conteúdo deliberado, não ambiente).
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {},
      ),
    ));

    _subs = [
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _estado = s);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _total = d);
      }),
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _posicao = p);
      }),
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _estado = PlayerState.completed;
            _posicao = Duration.zero;
          });
        }
      }),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _alternar() async {
    if (_estado == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (_estado == PlayerState.paused && _fonte != null) {
      await _player.resume();
      return;
    }
    // Primeira reprodução ou após concluir: resolve a fonte e toca do início.
    try {
      if (_fonte == null) {
        setState(() => _carregando = true);
        _fonte = await _resolverFonte();
        if (mounted) setState(() => _carregando = false);
      }
      final fonte = _fonte;
      if (fonte == null) return;
      await _player.play(fonte);
    } catch (e) {
      debugPrint('Erro ao tocar áudio: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<Source?> _resolverFonte() async {
    final local = widget.caminhoLocal;
    if (local != null && await File(local).exists()) {
      return DeviceFileSource(local);
    }
    final remoto = widget.caminhoRemoto;
    if (remoto != null) {
      final url = await BancoAudios.urlAssinada(remoto);
      return UrlSource(url);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _total.inMilliseconds > 0
        ? _total.inMilliseconds
        : (widget.duracaoMs ?? 0);
    final progresso = totalMs > 0
        ? (_posicao.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final tocando = _estado == PlayerState.playing;
    final tempoMs = tocando ? _posicao.inMilliseconds : totalMs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: KC.card,
        borderRadius: BorderRadius.circular(20),
        border: KC.escuro ? null : Border.all(color: KC.linha, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _alternar,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 28,
              height: 28,
              child: _carregando
                  ? Padding(
                      padding: const EdgeInsets.all(5),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(KC.acento),
                      ),
                    )
                  : Icon(
                      tocando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: KC.acento,
                      size: 26,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progresso,
                minHeight: 3,
                backgroundColor: KC.linha,
                valueColor: AlwaysStoppedAnimation(KC.acento),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(_formatarTempo(tempoMs), style: KT.caption()),
        ],
      ),
    );
  }

  static String _formatarTempo(int ms) {
    final totalSeg = ms ~/ 1000;
    final m = (totalSeg ~/ 60).toString().padLeft(1, '0');
    final s = (totalSeg % 60).toString().padLeft(2, '0');
    return '$m:$s';
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

// ── BOLHA DE MENSAGEM (sem balão — só texto; voz ganha player) ───────────────

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mensagem.temAudio)
                _PlayerAudio(
                  key: ValueKey(
                    mensagem.audioPathLocal ?? mensagem.audioPathRemoto,
                  ),
                  caminhoLocal: mensagem.audioPathLocal,
                  caminhoRemoto: mensagem.audioPathRemoto,
                  duracaoMs: mensagem.audioDuracaoMs,
                ),
              if (mensagem.transcrevendo)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    T.mentorTranscrevendo,
                    style: KT.caption(),
                    textAlign: TextAlign.right,
                  ),
                ),
              if (!mensagem.transcrevendo && mensagem.texto.trim().isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: mensagem.temAudio ? 8 : 0),
                  child: Text(
                    mensagem.texto,
                    style: KT.body(),
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
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
  String texto;
  final bool doMentor;
  final String? audioPathLocal; // arquivo local recém-gravado
  String? audioPathRemoto; // caminho no bucket audios-mentor
  final int? audioDuracaoMs;
  bool transcrevendo;

  _Mensagem({
    required this.texto,
    required this.doMentor,
    this.audioPathLocal,
    this.audioPathRemoto,
    this.audioDuracaoMs,
    this.transcrevendo = false,
  });

  bool get temAudio => audioPathLocal != null || audioPathRemoto != null;
}
