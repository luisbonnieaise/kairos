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

  // Estado "aguardando confirmação" — ativado quando o signup retorna user
  // sem session (i.e., confirmação de e-mail está LIGADA no Supabase Auth).
  // Quando true, a Scaffold renderiza a sub-vista de "confirme seu e-mail"
  // e nenhuma chamada autenticada é disparada (não há sessão).
  bool _aguardandoConfirmacao = false;
  String _emailParaConfirmacao = '';

  // Estado "login bloqueado por e-mail não confirmado": mostra ação extra
  // de reenviar o link. Só fica true após signInWithPassword devolver o
  // AuthApiException 'email not confirmed'.
  bool _podeReenviarConfirmacao = false;
  bool _reenviando = false;

  // Senha forte (P2.2): mín 8 caracteres com letra e número.
  static final _regexLetra  = RegExp(r'[A-Za-z]');
  static final _regexNumero = RegExp(r'\d');
  bool _senhaForte(String s) =>
      s.length >= 8 && _regexLetra.hasMatch(s) && _regexNumero.hasMatch(s);

  Future<void> _autenticar() async {
    final email = _email.text.trim();
    final senha = _senha.text;

    if (email.isEmpty || senha.isEmpty) {
      setState(() => _erro = T.preenchaEmailSenha);
      return;
    }

    if (!_senhaForte(senha)) {
      setState(() => _erro = T.senhaRegra);
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
      _podeReenviarConfirmacao = false;
    });

    try {
      if (widget.ehCadastro) {
        final resp = await supabase.auth.signUp(email: email, password: senha);

        // Supabase Auth com "Confirm email" LIGADO: signUp devolve user mas
        // session == null — a sessão só nasce após o usuário clicar no link.
        // NÃO chame BancoPerfil.atualizar() aqui (não há sessão; a inserção
        // falharia silenciosamente por RLS) e NÃO navegue para o onboarding.
        if (resp.session == null && resp.user != null) {
          if (!mounted) return;
          setState(() {
            _aguardandoConfirmacao = true;
            _emailParaConfirmacao = email;
            _carregando = false;
          });
          return;
        }

        // Caminho com "Confirm email" DESLIGADO: já há sessão, prossegue
        // como antes — salva o idioma escolhido e vai para o onboarding.
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
        // Sincroniza o idioma do perfil (caso o usuário tenha trocado de aparelho).
        // Se o perfil veio sem idioma — pode ter sido criado em signup com
        // Confirm Email ligado, que não chega a chamar `atualizar(idioma:)` —
        // persistimos o atual. Sem isso, o backend (Mentor/Carta) cai sempre
        // no default 'pt' e o usuário vê resposta em PT mesmo com app em outro
        // idioma.
        try {
          final perfil = await BancoPerfil.carregar();
          final idiomaSalvo = perfil?['idioma'] as String?;
          if (idiomaSalvo == null || idiomaSalvo.isEmpty) {
            await BancoPerfil.atualizar(idioma: T.idioma);
          } else if (idiomaSalvo != T.idioma) {
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
      final msg = e.message.toLowerCase();
      // E-mail não confirmado no login: troca a UX para mostrar o botão de
      // reenviar (em vez de só uma mensagem genérica de credencial errada).
      if (msg.contains('email not confirmed') || msg.contains('not confirmed')) {
        setState(() {
          _erro = T.emailNaoConfirmado;
          _podeReenviarConfirmacao = true;
          _carregando = false;
        });
        return;
      }
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

  Future<void> _reenviarConfirmacao() async {
    final email = _emailParaConfirmacao.isNotEmpty
        ? _emailParaConfirmacao
        : _email.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _reenviando = true;
      _erro = null;
    });
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
      if (!mounted) return;
      // Mensagem positiva curta. Mantém _podeReenviarConfirmacao true caso
      // o usuário queira reenviar novamente após a janela do Supabase.
      setState(() {
        _erro = T.confirmacaoReenviada;
        _reenviando = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _traduzirErro(e.message);
        _reenviando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = T.erroGenerico;
        _reenviando = false;
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

  // Sub-vista pós-signup quando "Confirm email" está LIGADO no Supabase Auth.
  // Mesma linguagem visual de _SheetRecuperarSenha: titulo em KT.titulo(),
  // corpo em bodySerif/caption, botão "voltar ao login" no estilo outlined.
  Widget _construirAguardandoConfirmacao() {
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
              const SizedBox(height: 48),

              Text(T.confirmeSeuEmail, style: KT.micro(cor: KC.kin)),
              const SizedBox(height: 16),
              Text(T.enviamosConfirmacao, style: KT.bodySerif()),
              const SizedBox(height: 16),
              if (_emailParaConfirmacao.isNotEmpty)
                Text(_emailParaConfirmacao, style: KT.body(cor: KC.washi)),

              if (_erro != null) ...[
                const SizedBox(height: 24),
                Text(_erro!, style: KT.caption(cor: KC.aka)),
              ],

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _reenviando ? null : _reenviarConfirmacao,
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
                  child: _reenviando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: KC.fundo,
                          ),
                        )
                      : Text(T.reenviarConfirmacao, style: KT.body(cor: KC.fundo)),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    // Volta ao login (modo cadastro -> modo login).
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) =>
                            const TelaAuth(ehCadastro: false),
                        transitionDuration: Duration.zero,
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KC.washi,
                    side: BorderSide(color: KC.grafite, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.voltarAoLogin, style: KT.body()),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sub-vista "Confirme seu e-mail" — aparece após signup quando o
    // Supabase Auth está com confirmação ligada (response.session == null).
    if (_aguardandoConfirmacao) return _construirAguardandoConfirmacao();

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

              // Login bloqueado por e-mail não confirmado: ação de reenvio
              // do link. Aparece junto da mensagem de erro acima.
              if (_podeReenviarConfirmacao && !widget.ehCadastro) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _reenviando ? null : _reenviarConfirmacao,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _reenviando ? T.salvando : T.reenviarConfirmacao,
                      style: KT.caption(cor: KC.kin),
                    ),
                  ),
                ),
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
