import 'dart:math' as math;
// CupertinoPageTransitionsBuilder migrou de material.dart para cupertino.dart
// no Flutter 3.44 (PR flutter#179776). Import explícito mantém compatibilidade
// com 3.44+ e versões anteriores (onde o Material ainda o exporta).
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sistema de tema do Kairo — Light/Dark.
///
/// Paleta:
/// - LIGHT "Washi Paper & Charcoal": fundo off-white quente
/// - DARK "Sumi Ink & Stone": preto fosco / cinza pedra
///
/// Acento cirúrgico: cobre/madeira queimada (raro, só destaques importantes).
class KC {
  /// Notifica mudança de tema. Use ValueListenableBuilder no topo da árvore.
  static final temaEscuro = ValueNotifier<bool>(true);

  static bool get escuro => temaEscuro.value;

  // ── LIGHT: "Washi Paper & Charcoal" ────────────────────────────────────────
  static const _luzFundo        = Color(0xFFF7F4EB); // canvas off-white quente
  static const _luzTexto        = Color(0xFF1E1E1E); // charcoal (não preto puro)
  static const _luzTextoSuave   = Color(0xFF766E65); // cinza terroso
  static const _luzAcento       = Color(0xFFC28B63); // cobre / madeira queimada
  static const _luzCard         = Color(0xFFEFEBE0); // ligeiramente mais escuro que fundo
  static const _luzLinha        = Color(0xFFE5E1D6); // divisor sutil (quase invisível)

  // ── DARK: "Sumi Ink & Stone" ───────────────────────────────────────────────
  static const _escFundo        = Color(0xFF1C1E20); // preto fosco / cinza pedra
  static const _escTexto        = Color(0xFFE5E3DC); // off-white suave
  static const _escTextoSuave   = Color(0xFF8A8E93); // cinza ardósia
  static const _escAcento       = Color(0xFFD4A373); // cobre iluminado
  static const _escCard         = Color(0xFF24272A); // contraste sutil
  static const _escLinha        = Color(0xFF2A2A2A); // divisor sutil

  // ── COMUM (independe de tema) ──────────────────────────────────────────────
  static const aka  = Color(0xFF8B2E2E); // vermelho (alertas críticos — raríssimo)

  // ── GETTERS SEMÂNTICOS ─────────────────────────────────────────────────────
  static Color get fundo      => escuro ? _escFundo      : _luzFundo;
  static Color get texto      => escuro ? _escTexto      : _luzTexto;
  static Color get textoSuave => escuro ? _escTextoSuave : _luzTextoSuave;
  static Color get acento     => escuro ? _escAcento     : _luzAcento;
  static Color get card       => escuro ? _escCard       : _luzCard;
  static Color get linha      => escuro ? _escLinha      : _luzLinha;

  // ── ALIASES (compatibilidade com código já existente) ──────────────────────
  static Color get sumi    => fundo;        // canvas
  static Color get washi   => texto;        // foreground / botões claros
  static Color get cinza   => textoSuave;   // texto secundário
  static Color get fumo    => textoSuave;   // texto suave
  static Color get grafite => linha;        // divisores
  static Color get kin     => acento;       // cobre
  static Color get matcha  => acento;       // cobre (no novo design não há verde)

  // ── PERSISTÊNCIA ───────────────────────────────────────────────────────────
  static Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getBool('tema_escuro');
    if (salvo != null) {
      temaEscuro.value = salvo;
    }
  }

  static Future<void> alternar(bool valor) async {
    temaEscuro.value = valor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tema_escuro', valor);
  }
}

// ── TIPOGRAFIA ───────────────────────────────────────────────────────────────
//
// Filosofia: títulos em fonte SERIFADA (Lora) — carrega o peso emocional.
// Texto, botões e labels em fonte SANS-SERIF (Inter) — limpa e neutra.
//
class KT {
  // Display XL — serif elegante, leve. Onboarding hero, splash.
  static TextStyle displayXL({Color? cor}) => GoogleFonts.lora(
    fontSize: 48,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.08,
    color: cor ?? KC.texto,
  );

  // Display L — títulos principais das telas (32sp w400 conforme spec)
  static TextStyle displayL({Color? cor}) => GoogleFonts.lora(
    fontSize: 32,
    fontWeight: FontWeight.w400,
    height: 1.15,
    color: cor ?? KC.texto,
  );

  // Título de seção (20sp w500 — serif)
  static TextStyle titulo({Color? cor}) => GoogleFonts.lora(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: cor ?? KC.texto,
  );

  // Body grande (16sp Inter — texto principal)
  static TextStyle body({Color? cor}) => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: cor ?? KC.texto,
  );

  // Body em itálico — para frases do Mentor inseridas no Pátio
  static TextStyle bodyItalic({Color? cor}) => GoogleFonts.inter(
    fontSize: 14,
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: cor ?? KC.textoSuave,
  );

  // Compatibilidade com chamadas antigas (KT.bodySerif) — agora também é Inter
  // mas com tamanho 16 mantido para minimizar quebra visual.
  static TextStyle bodySerif({Color? cor}) => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: cor ?? KC.texto,
  );

  // Caption — 13sp Inter
  static TextStyle caption({Color? cor}) => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: cor ?? KC.textoSuave,
  );

  // Micro / labels uppercase — 11sp Inter w500 + tracking generoso
  static TextStyle micro({Color? cor}) => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.4,
    height: 1.45,
    color: cor ?? KC.textoSuave,
  );

  // Label de tab inferior — 10sp Inter
  static TextStyle tabLabel({Color? cor}) => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.2,
    color: cor ?? KC.textoSuave,
  );

  // Divisor com sombra abaixo — cria sensação de profundidade
  static Widget divisor() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: KC.linha),
        Container(
          height: 10,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: KC.escuro ? 0.18 : 0.06),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Degradê marrom — mesmo efeito do "Boa noite" na tela inicial
  static Widget tituloGradiente(
    String texto, {
    TextStyle? estilo,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    final colors = KC.escuro
        ? const [Color(0xFFA06A3A), Color(0xFFD4A373)]
        : const [Color(0xFF8C5A30), Color(0xFFC28B63)];
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Padding(
        // Padding expande o layout bounds do ShaderMask, forçando o saveLayer
        // a incluir a área do descender do "j" (e outros: g, p, y…)
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          texto,
          maxLines: maxLines,
          overflow: overflow,
          style: (estilo ?? KT.displayL()).copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

// ── TEMA GLOBAL DO FLUTTER ────────────────────────────────────────────────────

ThemeData kairoTema() {
  final escuro = KC.escuro;
  return ThemeData(
    brightness: escuro ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: KC.fundo,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    colorScheme: escuro
        ? ColorScheme.dark(
            surface: KC.fundo,
            primary: KC.texto,
            secondary: KC.acento,
            error: KC.aka,
            onSurface: KC.texto,
          )
        : ColorScheme.light(
            surface: KC.fundo,
            primary: KC.texto,
            secondary: KC.acento,
            error: KC.aka,
            onSurface: KC.texto,
          ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

// ── ENSŌ ANIMADO ──────────────────────────────────────────────────────────────
//
// Widget público reutilizável em qualquer tela.
// O traço é calligráfico (espessura variável) e escala proporcionalmente
// ao tamanho via raiz quadrada — fino em tamanhos pequenos, ainda delicado
// nos maiores.

class KairoEnso extends StatefulWidget {
  final double tamanho;
  final Color? cor;
  final Duration duracao;

  const KairoEnso({
    super.key,
    required this.tamanho,
    this.cor,
    this.duracao = const Duration(seconds: 8),
  });

  @override
  State<KairoEnso> createState() => _KairoEnsoState();
}

class _KairoEnsoState extends State<KairoEnso>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duracao)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cor = widget.cor ?? KC.acento;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: SizedBox(
          width: widget.tamanho,
          height: widget.tamanho,
          child: CustomPaint(painter: _EnsoPainterFino(cor: cor)),
        ),
      ),
    );
  }
}

class _EnsoPainterFino extends CustomPainter {
  final Color cor;
  _EnsoPainterFino({required this.cor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final raio = (size.shortestSide / 2) - size.shortestSide * 0.06;
    // Escala de traço via raiz quadrada: fino em sizes pequenos, delicado nos grandes
    final fator = math.sqrt(size.shortestSide / 48);

    const passos = 80;
    const inicio = -1.35; // ~-77° (abertura topo-direito)
    const arco   = 5.60;  // ~321°

    for (int i = 0; i < passos; i++) {
      final t  = i / passos;
      final t2 = (i + 1) / passos;

      final pico    = (t < 0.3) ? (t / 0.3) : (1.0 - ((t - 0.3) / 0.7));
      final largura = (fator * (0.6 + pico * 1.6)).clamp(0.4, 5.0);
      final alpha   = (0.45 + pico * 0.55).clamp(0.0, 1.0);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: raio),
        inicio + arco * t,
        arco * (t2 - t),
        false,
        Paint()
          ..color      = cor.withValues(alpha: alpha)
          ..style      = PaintingStyle.stroke
          ..strokeWidth = largura
          ..strokeCap  = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_EnsoPainterFino old) => old.cor != cor;
}
