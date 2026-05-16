import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/i18n.dart';
import '../main.dart';
import 'onboarding.dart';
import 'home.dart';

class TelaAuth extends StatefulWidget {
  final bool ehCadastro;
  const TelaAuth({super.key, required this.ehCadastro});

  @override
  State<TelaAuth> createState() => _TelaAuthState();
}

class _TelaAuthState extends State<TelaAuth> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _senhaConfirma = TextEditingController();
  bool _carregando = false;
  String? _erro;

  Future<void> _autenticar() async {
    final email = _email.text.trim();
    final senha = _senha.text;

    if (email.isEmpty || senha.isEmpty) {
      setState(() => _erro = T.preenchaEmailSenha);
      return;
    }

    if (senha.length < 6) {
      setState(() => _erro = T.senhaMin6);
      return;
    }

    // Confirmação de senha só no cadastro
    if (widget.ehCadastro && senha != _senhaConfirma.text) {
      setState(() => _erro = T.senhasNaoCoincidem);
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      if (widget.ehCadastro) {
        await supabase.auth.signUp(email: email, password: senha);
        // Salva apenas o idioma escolhido (o nome será perguntado no onboarding)
        try {
          await BancoPerfil.atualizar(idioma: T.idioma);
        } catch (_) {}

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const TelaOnboarding(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      } else {
        await supabase.auth.signInWithPassword(email: email, password: senha);
        // Sincroniza o idioma do perfil (caso o usuário tenha trocado de aparelho)
        try {
          final perfil = await BancoPerfil.carregar();
          final idiomaSalvo = perfil?['idioma'] as String?;
          if (idiomaSalvo != null && idiomaSalvo != T.idioma) {
            await T.definir(idiomaSalvo);
          }
        } catch (_) {}
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const TelaHome(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _traduzirErro(e.message);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = T.erroGenerico;
        _carregando = false;
      });
    }
  }

  Future<void> _esqueciSenha() async {
    final email = _email.text.trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SheetRecuperarSenha(emailInicial: email),
    );
  }

  String _traduzirErro(String original) {
    final l = original.toLowerCase();
    if (l.contains('invalid login') || l.contains('invalid credentials')) {
      return T.emailSenhaIncorretos;
    }
    if (l.contains('already registered') || l.contains('already exists')) {
      return T.emailJaCadastrado;
    }
    if (l.contains('rate limit')) {
      return T.muitasTentativas;
    }
    if (l.contains('weak password')) {
      return T.senhaMuitoFraca;
    }
    if (l.contains('invalid email') || (l.contains('email') && l.contains('invalid'))) {
      return T.emailInvalido;
    }
    return original;
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    _senhaConfirma.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.ehCadastro ? T.criarConta : T.entrar;
    final botao = widget.ehCadastro ? T.criarConta : T.entrar;
    final linkOposto = widget.ehCadastro
        ? T.jaTenhoConta
        : T.criarNovaConta;

    return Scaffold(
      backgroundColor: KC.sumi,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back, color: KC.cinza, size: 22),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),

              const SizedBox(height: 32),

              Text(titulo, style: KT.displayL()),
              const SizedBox(height: 48),

              // Email
              Text(T.email, style: KT.micro()),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
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

              // Senha
              Text(T.senha, style: KT.micro()),
              const SizedBox(height: 8),
              TextField(
                controller: _senha,
                obscureText: true,
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

              if (widget.ehCadastro) ...[
                const SizedBox(height: 32),
                Text(T.confirmarSenha, style: KT.micro()),
                const SizedBox(height: 8),
                TextField(
                  controller: _senhaConfirma,
                  obscureText: true,
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
              ],

              if (_erro != null) ...[
                const SizedBox(height: 24),
                Text(_erro!, style: KT.caption(cor: KC.aka)),
              ],

              if (!widget.ehCadastro) ...[
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _esqueciSenha,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(T.esqueciSenha, style: KT.caption(cor: KC.kin)),
                  ),
                ),
              ],

              const Spacer(),

              // Botão principal
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _carregando ? null : _autenticar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KC.washi,
                    foregroundColor: KC.sumi,
                    disabledBackgroundColor: KC.grafite,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _carregando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: KC.fundo,
                          ),
                        )
                      : Text(botao, style: KT.body(cor: KC.fundo)),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => TelaAuth(ehCadastro: !widget.ehCadastro),
                        transitionDuration: Duration.zero,
                      ),
                    );
                  },
                  child: Text(linkOposto, style: KT.caption()),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SHEET: RECUPERAR SENHA ───────────────────────────────────────────────────

class _SheetRecuperarSenha extends StatefulWidget {
  final String emailInicial;
  const _SheetRecuperarSenha({required this.emailInicial});

  @override
  State<_SheetRecuperarSenha> createState() => _SheetRecuperarSenhaState();
}

class _SheetRecuperarSenhaState extends State<_SheetRecuperarSenha> {
  late final TextEditingController _email;
  bool _enviando = false;
  bool _enviado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.emailInicial);
  }

  // Regex simples mas robusto para email
  static final _regexEmail = RegExp(r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$');

  Future<void> _enviar() async {
    final email = _email.text.trim();

    if (email.isEmpty || !_regexEmail.hasMatch(email)) {
      setState(() => _erro = T.digiteEmailValido);
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() {
        _enviado = true;
        _enviando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = T.erroGenerico;
        _enviando = false;
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
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

            if (_enviado) ...[
              Text(T.verifiqueEmail, style: KT.micro(cor: KC.kin)),
              const SizedBox(height: 12),
              Text(T.linkEnviado, style: KT.bodySerif()),
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
                  child: Text(T.fechar, style: KT.body()),
                ),
              ),
            ] else ...[
              Text(T.recuperarSenha, style: KT.titulo()),
              const SizedBox(height: 8),
              Text(T.enviaremosLink, style: KT.caption()),
              const SizedBox(height: 32),

              Text(T.email, style: KT.micro()),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: KT.body(),
                cursorColor: KC.kin,
                cursorWidth: 1,
                autofocus: widget.emailInicial.isEmpty,
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

              if (_erro != null) ...[
                const SizedBox(height: 16),
                Text(_erro!, style: KT.caption(cor: KC.aka)),
              ],

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _enviando ? null : _enviar,
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
                  child: _enviando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: KC.fundo,
                          ),
                        )
                      : Text(T.enviarLink, style: KT.body(cor: KC.fundo)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
