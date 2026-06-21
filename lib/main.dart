import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/kairo_tema.dart';
import 'core/audio.dart';
import 'core/banco.dart';
import 'core/billing.dart';
import 'core/cache.dart';
import 'core/widget_sync.dart';
import 'core/notificacoes.dart';
import 'core/i18n.dart';
import 'telas/auth.dart';
import 'telas/portao.dart';
import 'telas/selecao_idioma.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_KEY']!,
  );

  // Inicia o listener de compras IAP (purchaseStream) o quanto antes — compras
  // pendentes/retomadas são entregues no boot.
  Billing.instance.init();

  // Carrega o idioma salvo localmente (ou padrão pt)
  await T.carregarLocal();

  // Carrega tema (claro/escuro)
  await KC.carregar();

  // Pré-carrega o cache local (leitura síncrona nas abas → paint instantâneo).
  await CacheLocal.init();

  // Inicializa o sistema de notificações (timezone, plugin etc.)
  await KairoNotificacoes.inicializar();

  // Pré-carrega o som antes de mostrar a tela — elimina o crackling inicial
  KairoAudio.precarregar();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const KairoApp());
}

// Atalho global para acessar o cliente Supabase de qualquer lugar
final supabase = Supabase.instance.client;

// Notifica a navbar quando há uma carta semanal não lida
final cartaNovaNotifier = ValueNotifier<bool>(false);

// Notifica a navbar quando há uma pergunta do Jardim não respondida
final jardimNovaNotifier = ValueNotifier<bool>(false);

// Notifica o último deep link recebido (kairo://...). Usado por fluxos de
// auth (confirmação de e-mail / reset de senha). Guarda o último URI, sem fila.
// (O Premium não usa mais deep link: a compra é IAP nativa — Fase 07.)
final ValueNotifier<Uri?> deepLinkNotifier = ValueNotifier<Uri?>(null);

class KairoApp extends StatefulWidget {
  const KairoApp({super.key});

  @override
  State<KairoApp> createState() => _KairoAppState();
}

class _KairoAppState extends State<KairoApp> with WidgetsBindingObserver {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLinks = AppLinks();
    // Cold start: o sistema pode ter aberto o app com um link.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) deepLinkNotifier.value = uri;
    }).catchError((Object e) {
      debugPrint('AppLinks.getInitialLink falhou: $e');
    });
    // Warm: enquanto o app está aberto.
    _linkSub = _appLinks.uriLinkStream.listen(
      (uri) => deepLinkNotifier.value = uri,
      onError: (Object e) => debugPrint('AppLinks stream erro: $e'),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Empurra os dados aos widgets quando o app vai para segundo plano
    // (estratégia de refresh da spec dos widgets).
    if (state == AppLifecycleState.paused) {
      atualizarWidgets();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  /// Empurra os dados aos widgets nativos (frase, próxima prática, streak).
  /// Delegado ao [WidgetSync] — mesma derivação usada pelos demais gatilhos.
  Future<void> atualizarWidgets() => WidgetSync.sincronizar();

  @override
  Widget build(BuildContext context) {
    // Reage a mudanças de tema (claro/escuro) E de idioma. Quando o usuário
    // troca qualquer um no Perfil, toda a árvore reconstrói. A `ValueKey`
    // inclui ambos para garantir remount quando o tema muda (algumas cores
    // são lidas no `initState`); para idioma, o rebuild dos `Text(T.X)` já
    // re-resolve os getters, mas mantemos no key para consistência.
    return ValueListenableBuilder<bool>(
      valueListenable: KC.temaEscuro,
      builder: (context, _, _) {
        return ValueListenableBuilder<String>(
          valueListenable: T.idiomaNotifier,
          builder: (context, idioma, _) {
            return MaterialApp(
              key: ValueKey('kairo-${KC.escuro}-$idioma'),
              title: 'Kairo',
              debugShowCheckedModeBanner: false,
              theme: kairoTema(),
              home: const TelaSplash(),
            );
          },
        );
      },
    );
  }
}

// ── SPLASH: kanji + wordmark ──────────────────────────────────────────────────

class TelaSplash extends StatefulWidget {
  const TelaSplash({super.key});

  @override
  State<TelaSplash> createState() => _TelaSplashState();
}

class _TelaSplashState extends State<TelaSplash>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _kanjiOpacity;
  late Animation<double> _wordmarkOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _kanjiOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _wordmarkOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    // Sino toca apenas na primeira vez que o app abre, sem usuário logado
    _tocarSinoSeForPrimeiraVez();

    _ctrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      final logado = supabase.auth.currentSession != null;

      // Se está logado, sincroniza o idioma do perfil e reagenda lembrete.
      // Entra pelo PORTÃO de assinatura (hard paywall): ele decide se libera
      // o TelaHome (entitlement ativo) ou exibe o paywall obrigatório.
      if (logado) {
        _sincronizarIdioma();
        _reagendarLembrete();
        _irPara(const TelaPortao());
        return;
      }

      // Se ainda não escolheu idioma, abre seleção; senão, boas-vindas
      final prefs = await SharedPreferences.getInstance();
      final temIdioma = prefs.getString('idioma') != null;
      _irPara(temIdioma ? const TelaBoasVindas() : const TelaSelecaoIdioma());
    });
  }

  void _irPara(Widget tela) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => tela,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  Future<void> _tocarSinoSeForPrimeiraVez() async {
    // Se já está logado, não toca
    if (supabase.auth.currentSession != null) return;

    final prefs = await SharedPreferences.getInstance();
    final jaTocou = prefs.getBool('sino_tocado') ?? false;
    if (jaTocou) return;

    // Espera o kanji aparecer (400ms) e toca
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    KairoAudio.tocarOrin();
    await prefs.setBool('sino_tocado', true);
  }

  Future<void> _sincronizarIdioma() async {
    try {
      final perfil = await BancoPerfil.carregar();
      final idiomaSalvo = perfil?['idioma'] as String?;
      if (idiomaSalvo == null || idiomaSalvo.isEmpty) {
        // Perfil sem idioma — pode ter sido criado em fluxo onde a coluna
        // ficou null (signup com Confirm Email ligado). Preenche com o que
        // o usuário está usando agora. Sem isso, o backend (mentor/carta)
        // sempre cai no default 'pt'.
        await BancoPerfil.atualizar(idioma: T.idioma);
      } else if (idiomaSalvo != T.idioma) {
        await T.definir(idiomaSalvo);
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar idioma: $e');
    }
  }

  Future<void> _reagendarLembrete() async {
    try {
      final perfil = await BancoPerfil.carregar();
      final horario = perfil?['horario_lembrete'] as String?;
      if (horario == null || horario.isEmpty) return;

      final partes = horario.split(':');
      if (partes.length < 2) return;

      final hora = int.tryParse(partes[0]) ?? 7;
      final minuto = int.tryParse(partes[1]) ?? 0;

      await KairoNotificacoes.agendarLembreteDiario(hora, minuto);
    } catch (e) {
      debugPrint('Erro ao reagendar lembrete: $e');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KC.sumi,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Kanji 回路 em dourado (grande)
            FadeTransition(
              opacity: _kanjiOpacity,
              child: Text(
                '回路',
                style: GoogleFonts.notoSerifJp(
                  fontSize: 96,
                  fontWeight: FontWeight.w500,
                  color: KC.kin,
                  letterSpacing: 8,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Wordmark KAIRO — mais encorpado, menos espaçamento
            FadeTransition(
              opacity: _wordmarkOpacity,
              child: Text(
                'KAIRO',
                style: GoogleFonts.inter(
                  fontSize: 48,
                  fontWeight: FontWeight.w600,
                  color: KC.washi,
                  letterSpacing: 6,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── TELA DE BOAS-VINDAS ───────────────────────────────────────────────────────

class TelaBoasVindas extends StatelessWidget {
  const TelaBoasVindas({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KC.sumi,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              Text(
                'KAIRO',
                style: GoogleFonts.inter(
                  fontSize: 48,
                  fontWeight: FontWeight.w600,
                  color: KC.washi,
                  letterSpacing: 6,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              Text(T.tagline, style: KT.bodySerif(cor: KC.cinza)),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, _, _) =>
                            const TelaAuth(ehCadastro: true),
                        transitionsBuilder: (_, anim, _, child) =>
                            FadeTransition(opacity: anim, child: child),
                        transitionDuration: const Duration(milliseconds: 400),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KC.washi,
                    foregroundColor: KC.sumi,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.comecar, style: KT.body(cor: KC.sumi)),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, _, _) =>
                            const TelaAuth(ehCadastro: false),
                        transitionsBuilder: (_, anim, _, child) =>
                            FadeTransition(opacity: anim, child: child),
                        transitionDuration: const Duration(milliseconds: 400),
                      ),
                    );
                  },
                  child: Text(T.jaTenhoConta, style: KT.caption()),
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
