import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/i18n.dart';
import '../main.dart';
import 'onboarding.dart';
import 'portao.dart';

/// Regex de e-mail compartilhado entre a tela de auth e a folha de recuperação
/// de senha — uma única fonte de verdade para a validação leve do campo.
final RegExp _regexEmailAuth = RegExp(r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$');

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

  // Ordem de foco: email → senha → confirmar. Vivem no State (não na subárvore
  // trocada pelo AnimatedSwitcher), então sobrevivem ao toggle login↔cadastro.
  final _fnEmail = FocusNode();
  final _fnSenha = FocusNode();
  final _fnConfirma = FocusNode();

  // Modo da tela. Promovido a estado para que o toggle login↔cadastro seja
  // in-place (setState), sem troca de rota / flash.
  late bool _ehCadastro;

  // Um único controle de visibilidade governa ambos os campos de senha.
  bool _senhaVisivel = false;

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

  // Sinal positivo do campo de e-mail — um check cobre quando válido (nunca um
  // X vermelho; a ausência do check é o único sinal negativo).
  bool get _emailValido => _regexEmailAuth.hasMatch(_email.text.trim());

  @override
  void initState() {
    super.initState();
    _ehCadastro = widget.ehCadastro;
  }

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
    if (_ehCadastro && senha != _senhaConfirma.text) {
      setState(() => _erro = T.senhasNaoCoincidem);
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
      _podeReenviarConfirmacao = false;
    });

    try {
      if (_ehCadastro) {
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
            pageBuilder: (_, _, _) => const TelaOnboarding(),
            transitionsBuilder: (_, anim, _, child) =>
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
            // Entra pelo PORTÃO (hard paywall): libera TelaHome só com assinatura.
            pageBuilder: (_, _, _) => const TelaPortao(),
            transitionsBuilder: (_, anim, _, child) =>
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
    _fnEmail.dispose();
    _fnSenha.dispose();
    _fnConfirma.dispose();
    super.dispose();
  }

  // ── SHELL ROBUSTO A TECLADO ─────────────────────────────────────────────────
  // SingleChildScrollView + ConstrainedBox(minHeight) + IntrinsicHeight permite
  // que o `Spacer()` fixe o botão na base em telas altas E que a página role
  // (em vez de estourar a RenderFlex) no cadastro com 3 campos + teclado + erro.
  Widget _shell({required List<Widget> children}) {
    return Scaffold(
      backgroundColor: KC.sumi,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _botaoVoltar() {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
        icon: Icon(Icons.arrow_back, color: KC.cinza, size: 22),
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context);
        },
      ),
    );
  }

  // Olho de mostrar/ocultar — o MESMO controle governa os dois campos de senha.
  Widget _olhoSenha() {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: _senhaVisivel ? T.ocultarSenha : T.mostrarSenha,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        splashRadius: 22,
        icon: Icon(
          _senhaVisivel
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
          color: KC.cinza,
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          setState(() => _senhaVisivel = !_senhaVisivel);
        },
      ),
    );
  }

  // ── SUB-VISTA: "CONFIRME SEU E-MAIL" ─────────────────────────────────────────
  // Pós-signup quando "Confirm email" está LIGADO no Supabase Auth
  // (response.session == null). Mesma gramática de cabeçalho das telas
  // principais (ensō + título em degradê + subtítulo + divisor).
  Widget _construirAguardandoConfirmacao() {
    return _shell(
      children: [
        _botaoVoltar(),
        const SizedBox(height: 24),

        // Cabeçalho — escala de seção (KT.titulo) para diferenciar do título
        // principal das telas de login/cadastro.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            KairoEnso(
              tamanho: 36,
              cor: KC.acento.withValues(alpha: 0.75),
              duracao: const Duration(seconds: 12),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: KT.tituloGradiente(
                T.confirmeSeuEmailTitulo,
                estilo: KT.titulo(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(T.confirmeSeuEmailSub, style: KT.caption()),
        const SizedBox(height: 32),
        KT.divisor(),
        const SizedBox(height: 32),

        Text(T.enviamosConfirmacao, style: KT.bodySerif()),
        const SizedBox(height: 16),

        // O e-mail vira um dado destacado num cartão (linguagem de card do app).
        if (_emailParaConfirmacao.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: KC.card,
              borderRadius: BorderRadius.circular(12),
              border: KC.escuro ? null : Border.all(color: KC.linha, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.mail_outline, size: 18, color: KC.kin),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _emailParaConfirmacao,
                    style: KT.body(cor: KC.washi),
                  ),
                ),
              ],
            ),
          ),

        // Erro / confirmação reenviada
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _erro != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(_erro!, style: KT.caption(cor: KC.aka)),
                )
              : const SizedBox.shrink(),
        ),

        const Spacer(),
        const SizedBox(height: 24),

        // Reenviar confirmação
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _reenviando
                  ? SizedBox(
                      key: const ValueKey('load'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: KC.fundo,
                      ),
                    )
                  : Text(
                      T.reenviarConfirmacao,
                      key: const ValueKey('label'),
                      style: KT.body(cor: KC.fundo),
                    ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Voltar ao login — in-place (sem flash de rota).
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _aguardandoConfirmacao = false;
                _ehCadastro = false;
                _erro = null;
                _senhaConfirma.clear();
              });
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

        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sub-vista "Confirme seu e-mail".
    if (_aguardandoConfirmacao) return _construirAguardandoConfirmacao();

    return _shell(
      children: [
        _botaoVoltar(),
        const SizedBox(height: 24),

        // ── Cabeçalho canônico: ensō + título em degradê + subtítulo + divisor ──
        // Não envolto em widget animado: o ensō gira continuamente como âncora
        // de marca e só o texto do título/subtítulo troca via setState.
        _AuthHeader(
          titulo: _ehCadastro ? T.criarConta : T.entrar,
          subtitulo:
              _ehCadastro ? T.authSubtituloCadastro : T.authSubtituloEntrar,
        ),
        const SizedBox(height: 32),

        // Email
        _AuthField(
          controller: _email,
          label: T.email,
          keyboardType: TextInputType.emailAddress,
          focusNode: _fnEmail,
          action: TextInputAction.next,
          onSubmitted: (_) => _fnSenha.requestFocus(),
          validaListenable: _email,
          validador: () => _emailValido,
        ),
        const SizedBox(height: 28),

        // Senha
        _AuthField(
          controller: _senha,
          label: T.senha,
          focusNode: _fnSenha,
          obscure: !_senhaVisivel,
          suffix: _olhoSenha(),
          action:
              _ehCadastro ? TextInputAction.next : TextInputAction.done,
          onSubmitted: _ehCadastro
              ? (_) => _fnConfirma.requestFocus()
              : (_) => _autenticar(),
        ),

        // Confirmar senha (somente cadastro) — surge/recolhe suavemente.
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _ehCadastro
                ? Column(
                    key: const ValueKey('confirma'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 28),
                      _AuthField(
                        controller: _senhaConfirma,
                        label: T.confirmarSenha,
                        focusNode: _fnConfirma,
                        obscure: !_senhaVisivel,
                        suffix: _olhoSenha(),
                        action: TextInputAction.done,
                        onSubmitted: (_) => _autenticar(),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('vazio')),
          ),
        ),

        // Erro
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _erro != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(_erro!, style: KT.caption(cor: KC.aka)),
                )
              : const SizedBox.shrink(),
        ),

        // Login bloqueado por e-mail não confirmado: ação de reenvio do link.
        if (_podeReenviarConfirmacao && !_ehCadastro) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _reenviando ? null : _reenviarConfirmacao,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(0, 44),
              ),
              child: Text(
                _reenviando ? T.salvando : T.reenviarConfirmacao,
                style: KT.caption(cor: KC.kin),
              ),
            ),
          ),
        ],

        // Esqueci minha senha (somente login).
        if (!_ehCadastro) ...[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _esqueciSenha,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(0, 44),
              ),
              child: Text(T.esqueciSenha, style: KT.caption(cor: KC.kin)),
            ),
          ),
        ],

        const Spacer(),
        const SizedBox(height: 24),

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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _carregando
                  ? SizedBox(
                      key: const ValueKey('load'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: KC.fundo,
                      ),
                    )
                  : Text(
                      _ehCadastro ? T.criarConta : T.entrar,
                      key: const ValueKey('label'),
                      style: KT.body(cor: KC.fundo),
                    ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Alternar login ↔ cadastro — in-place, com cross-fade do texto.
        Center(
          child: TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _ehCadastro = !_ehCadastro;
                _erro = null;
                _podeReenviarConfirmacao = false;
                _senhaConfirma.clear();
                _senhaVisivel = false;
              });
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                _ehCadastro ? T.jaTenhoConta : T.criarNovaConta,
                key: ValueKey(_ehCadastro),
                style: KT.caption(),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── CABEÇALHO DE AUTENTICAÇÃO ─────────────────────────────────────────────────
// Réplica da gramática de cabeçalho das telas Mentor / Dôjo: ensō + título em
// degradê de cobre + subtítulo + divisor. É o que faz login/cadastro lerem como
// telas de primeira classe do app.

class _AuthHeader extends StatelessWidget {
  final String titulo;
  final String subtitulo;

  const _AuthHeader({required this.titulo, required this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return Column(
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
            Expanded(
              child: KT.tituloGradiente(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(subtitulo, style: KT.caption()),
        const SizedBox(height: 32),
        KT.divisor(),
      ],
    );
  }
}

// ── CAMPO DE AUTENTICAÇÃO ─────────────────────────────────────────────────────
// Tratamento único de campo (rótulo micro em maiúsculas + TextField sublinhado)
// usado em login, cadastro, confirme-seu-email e na folha de recuperação — para
// que nunca divirjam. Quando `validador` é fornecido, um check cobre aparece no
// slot do sufixo (sinal positivo apenas) e é recomputado de forma reativa via
// ListenableBuilder — sem rebuild da tela inteira.

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final FocusNode? focusNode;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Listenable? validaListenable;
  final bool Function()? validador;

  const _AuthField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.focusNode,
    this.action = TextInputAction.next,
    this.onSubmitted,
    this.autofocus = false,
    this.validaListenable,
    this.validador,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: KT.micro()),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscure,
          autofocus: autofocus,
          style: KT.body(),
          cursorColor: KC.kin,
          cursorWidth: 1,
          textInputAction: action,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: KC.grafite, width: 1),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: KC.grafite, width: 1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: KC.cinza, width: 1),
            ),
            suffixIcon: suffix ??
                ((validador != null && validaListenable != null)
                    ? ListenableBuilder(
                        listenable: validaListenable!,
                        builder: (_, _) => validador!()
                            ? Icon(Icons.check, size: 18, color: KC.kin)
                            : const SizedBox.shrink(),
                      )
                    : null),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
      ],
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

  Future<void> _enviar() async {
    final email = _email.text.trim();

    if (email.isEmpty || !_regexEmailAuth.hasMatch(email)) {
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

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: _enviado
                  ? Column(
                      key: const ValueKey('enviado'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check, size: 18, color: KC.kin),
                            const SizedBox(width: 8),
                            Text(T.verifiqueEmail, style: KT.micro(cor: KC.kin)),
                          ],
                        ),
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
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(T.fechar, style: KT.body()),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('form'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(T.recuperarSenhaEyebrow,
                            style: KT.micro(cor: KC.kin)),
                        const SizedBox(height: 8),
                        Text(T.recuperarSenha, style: KT.titulo()),
                        const SizedBox(height: 8),
                        Text(T.enviaremosLink, style: KT.caption()),
                        const SizedBox(height: 32),

                        _AuthField(
                          controller: _email,
                          label: T.email,
                          keyboardType: TextInputType.emailAddress,
                          action: TextInputAction.done,
                          onSubmitted: (_) => _enviar(),
                          autofocus: widget.emailInicial.isEmpty,
                        ),

                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _erro != null
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(_erro!,
                                      style: KT.caption(cor: KC.aka)),
                                )
                              : const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 32),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _enviando ? null : _enviar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: KC.washi,
                              foregroundColor: KC.sumi,
                              disabledBackgroundColor: KC.grafite,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _enviando
                                  ? SizedBox(
                                      key: const ValueKey('load'),
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: KC.fundo,
                                      ),
                                    )
                                  : Text(
                                      T.enviarLink,
                                      key: const ValueKey('label'),
                                      style: KT.body(cor: KC.fundo),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
