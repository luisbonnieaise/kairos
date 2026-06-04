import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sistema de tradução do Kairo.
/// 4 idiomas: pt (português), en (inglês), es (espanhol), de (alemão).
///
/// Uso: `T.bomDia` retorna a string no idioma atual.
class T {
  static String _l = 'pt';
  static String get idioma => _l;

  /// Notifica qualquer parte da árvore que precise reconstruir ao trocar idioma.
  /// O `MaterialApp` em main.dart escuta isso — assim toda a UI reflete a
  /// mudança imediatamente, sem precisar destruir a pilha de navegação.
  static final ValueNotifier<String> idiomaNotifier = ValueNotifier<String>('pt');

  static const List<Map<String, String>> idiomasDisponiveis = [
    {'codigo': 'pt', 'nome': 'Português', 'nomeNativo': 'Português'},
    {'codigo': 'en', 'nome': 'Inglês',    'nomeNativo': 'English'},
    {'codigo': 'es', 'nome': 'Espanhol',  'nomeNativo': 'Español'},
    {'codigo': 'de', 'nome': 'Alemão',    'nomeNativo': 'Deutsch'},
  ];

  static bool _valido(String codigo) =>
      const ['pt', 'en', 'es', 'de'].contains(codigo);

  static Future<void> carregarLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getString('idioma');
    if (salvo != null && _valido(salvo)) {
      _l = salvo;
      idiomaNotifier.value = salvo;
    }
  }

  static Future<void> definir(String codigo) async {
    if (!_valido(codigo)) return;
    _l = codigo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('idioma', codigo);
    // Dispara o rebuild global. ValueNotifier só notifica se o valor mudar,
    // então redefinir o mesmo idioma é no-op.
    idiomaNotifier.value = codigo;
  }

  static String _g(String pt, String en, String es, String de) {
    switch (_l) {
      case 'en': return en;
      case 'es': return es;
      case 'de': return de;
      default:   return pt;
    }
  }

  // ── SAUDAÇÕES ──────────────────────────────────────────────────────────────
  static String get bomDia    => _g('Bom dia,',    'Good morning,',   'Buenos días,',  'Guten Morgen,');
  static String get boaTarde  => _g('Boa tarde,',  'Good afternoon,', 'Buenas tardes,','Guten Tag,');
  static String get boaNoite  => _g('Boa noite,',  'Good evening,',   'Buenas noches,','Guten Abend,');
  static String get bemVindo  => _g('Bem-vindo',   'Welcome',         'Bienvenido',    'Willkommen');

  // ── SELEÇÃO DE IDIOMA ──────────────────────────────────────────────────────
  static String get escolhaIdioma => _g(
    'Escolha seu idioma',
    'Choose your language',
    'Elige tu idioma',
    'Wähle deine Sprache',
  );
  static String get continuar => _g('Continuar', 'Continue', 'Continuar', 'Weiter');

  // ── BOAS-VINDAS ────────────────────────────────────────────────────────────
  static String get tagline => _g(
    'Seu sistema de\nevolução pessoal.',
    'Your system of\npersonal evolution.',
    'Tu sistema de\nevolución personal.',
    'Dein System der\npersönlichen Entwicklung.',
  );
  static String get comecar  => _g('Começar', 'Begin', 'Comenzar', 'Beginnen');
  static String get jaTenhoConta => _g(
    'Já tenho uma conta',
    'I already have an account',
    'Ya tengo una cuenta',
    'Ich habe bereits ein Konto',
  );

  // ── AUTENTICAÇÃO ───────────────────────────────────────────────────────────
  static String get criarConta => _g('Criar conta', 'Create account', 'Crear cuenta', 'Konto erstellen');
  static String get entrar     => _g('Entrar', 'Sign in', 'Iniciar sesión', 'Anmelden');
  static String get comoTeChamar => _g(
    'COMO PODEMOS TE CHAMAR',
    'WHAT SHOULD WE CALL YOU',
    'CÓMO PODEMOS LLAMARTE',
    'WIE SOLLEN WIR DICH NENNEN',
  );
  static String get email => _g('EMAIL', 'EMAIL', 'CORREO', 'E-MAIL');
  static String get senha => _g('SENHA', 'PASSWORD', 'CONTRASEÑA', 'PASSWORT');
  static String get confirmarSenha => _g(
    'CONFIRMAR SENHA',
    'CONFIRM PASSWORD',
    'CONFIRMAR CONTRASEÑA',
    'PASSWORT BESTÄTIGEN',
  );
  static String get senhasNaoCoincidem => _g(
    'As senhas não coincidem.',
    'Passwords do not match.',
    'Las contraseñas no coinciden.',
    'Die Passwörter stimmen nicht überein.',
  );
  static String get criarNovaConta => _g(
    'Criar nova conta',
    'Create new account',
    'Crear nueva cuenta',
    'Neues Konto erstellen',
  );
  static String get esqueciSenha => _g(
    'Esqueci minha senha',
    'Forgot my password',
    'Olvidé mi contraseña',
    'Passwort vergessen',
  );
  static String get preenchaEmailSenha => _g(
    'Preencha email e senha.',
    'Fill in email and password.',
    'Completa correo y contraseña.',
    'E-Mail und Passwort ausfüllen.',
  );
  static String get senhaRegra => _g(
    'A senha precisa ter ao menos 8 caracteres, com letras e números.',
    'Password must have at least 8 characters, with letters and numbers.',
    'La contraseña debe tener al menos 8 caracteres, con letras y números.',
    'Das Passwort muss mindestens 8 Zeichen mit Buchstaben und Zahlen haben.',
  );
  static String get comoTeChamarErro => _g(
    'Como podemos te chamar?',
    'What should we call you?',
    '¿Cómo podemos llamarte?',
    'Wie sollen wir dich nennen?',
  );
  static String get emailSenhaIncorretos => _g(
    'Email ou senha incorretos.',
    'Email or password incorrect.',
    'Correo o contraseña incorrectos.',
    'E-Mail oder Passwort falsch.',
  );
  static String get emailJaCadastrado => _g(
    'Esse email já está cadastrado. Toque em "Já tenho uma conta".',
    'This email is already registered. Tap "I already have an account".',
    'Este correo ya está registrado. Toca "Ya tengo una cuenta".',
    'Diese E-Mail ist bereits registriert. Tippe auf "Ich habe bereits ein Konto".',
  );
  static String get muitasTentativas => _g(
    'Muitas tentativas. Aguarde alguns minutos.',
    'Too many attempts. Wait a few minutes.',
    'Demasiados intentos. Espera unos minutos.',
    'Zu viele Versuche. Warte einige Minuten.',
  );
  static String get senhaMuitoFraca => _g(
    'Senha muito fraca. Use ao menos 8 caracteres, com letras e números.',
    'Password too weak. Use at least 8 characters, with letters and numbers.',
    'Contraseña muy débil. Usa al menos 8 caracteres, con letras y números.',
    'Passwort zu schwach. Mindestens 8 Zeichen mit Buchstaben und Zahlen.',
  );
  static String get emailInvalido => _g(
    'Email inválido.',
    'Invalid email.',
    'Correo inválido.',
    'Ungültige E-Mail.',
  );
  static String get erroGenerico => _g(
    'Algo se perdeu no caminho. Tente novamente.',
    'Something got lost along the way. Try again.',
    'Algo se perdió en el camino. Inténtalo de nuevo.',
    'Etwas ging verloren. Versuche es erneut.',
  );

  // Confirmação de e-mail (signup com confirmation ligada)
  static String get confirmeSeuEmail => _g(
    'CONFIRME SEU E-MAIL',
    'CONFIRM YOUR EMAIL',
    'CONFIRMA TU CORREO',
    'BESTÄTIGE DEINE E-MAIL',
  );
  static String get enviamosConfirmacao => _g(
    'Enviamos um link de confirmação para o seu e-mail. Toque no link para ativar a sua conta e depois faça login.',
    'We sent a confirmation link to your email. Tap the link to activate your account, then sign in.',
    'Te enviamos un enlace de confirmación a tu correo. Toca el enlace para activar tu cuenta y luego inicia sesión.',
    'Wir haben einen Bestätigungslink an deine E-Mail gesendet. Tippe auf den Link, um dein Konto zu aktivieren, und melde dich dann an.',
  );
  static String get voltarAoLogin => _g(
    'Voltar ao login',
    'Back to sign in',
    'Volver al inicio de sesión',
    'Zurück zur Anmeldung',
  );
  static String get emailNaoConfirmado => _g(
    'E-mail ainda não confirmado. Verifique sua caixa de entrada.',
    'Email not confirmed yet. Check your inbox.',
    'Correo aún no confirmado. Revisa tu bandeja de entrada.',
    'E-Mail noch nicht bestätigt. Prüfe deinen Posteingang.',
  );
  static String get reenviarConfirmacao => _g(
    'Reenviar e-mail de confirmação',
    'Resend confirmation email',
    'Reenviar correo de confirmación',
    'Bestätigungs-E-Mail erneut senden',
  );
  static String get confirmacaoReenviada => _g(
    'E-mail de confirmação reenviado. Verifique sua caixa de entrada.',
    'Confirmation email resent. Check your inbox.',
    'Correo de confirmación reenviado. Revisa tu bandeja de entrada.',
    'Bestätigungs-E-Mail erneut gesendet. Prüfe deinen Posteingang.',
  );

  // Recuperar senha
  static String get recuperarSenha => _g(
    'Recuperar senha',
    'Recover password',
    'Recuperar contraseña',
    'Passwort zurücksetzen',
  );
  static String get enviaremosLink => _g(
    'Vamos enviar um link para o seu email.',
    'We will send a link to your email.',
    'Te enviaremos un enlace al correo.',
    'Wir senden einen Link an deine E-Mail.',
  );
  static String get enviarLink => _g(
    'Enviar link',
    'Send link',
    'Enviar enlace',
    'Link senden',
  );
  static String get verifiqueEmail => _g(
    'VERIFIQUE SEU EMAIL',
    'CHECK YOUR EMAIL',
    'REVISA TU CORREO',
    'PRÜFE DEINE E-MAIL',
  );
  static String get linkEnviado => _g(
    'Se houver uma conta com esse email, enviamos um link para você criar uma nova senha.',
    'If there is an account with this email, we sent you a link to create a new password.',
    'Si hay una cuenta con este correo, te enviamos un enlace para crear una nueva contraseña.',
    'Wenn ein Konto mit dieser E-Mail existiert, haben wir dir einen Link gesendet, um ein neues Passwort zu erstellen.',
  );
  static String get fechar => _g('Fechar', 'Close', 'Cerrar', 'Schließen');
  static String get digiteEmailValido => _g(
    'Digite um email válido.',
    'Enter a valid email.',
    'Ingresa un correo válido.',
    'Gib eine gültige E-Mail ein.',
  );
  static String get salvar => _g('Salvar', 'Save', 'Guardar', 'Speichern');
  static String get salvando => _g('Salvando...', 'Saving...', 'Guardando...', 'Speichern...');

  // ── KAIRO PREMIUM (IAP — StoreKit / Play Billing) ──────────────────────────
  static String get premiumTitulo => _g(
    'Kairo Premium',
    'Kairo Premium',
    'Kairo Premium',
    'Kairo Premium',
  );
  static String get premiumChamada => _g(
    'O Mentor mais profundo, a carta semanal garantida, limites ampliados.',
    'A deeper Mentor, guaranteed weekly letter, expanded limits.',
    'El Mentor más profundo, la carta semanal garantizada, límites ampliados.',
    'Ein tieferer Mentor, garantierter Wochenbrief, erweiterte Grenzen.',
  );
  static String get premiumBeneficioMentor => _g(
    'Mentor com o modelo mais sábio (Claude Sonnet).',
    'Mentor with the wisest model (Claude Sonnet).',
    'Mentor con el modelo más sabio (Claude Sonnet).',
    'Mentor mit dem weisesten Modell (Claude Sonnet).',
  );
  static String get premiumBeneficioCarta => _g(
    'Carta semanal garantida, mesmo em semanas cheias.',
    'Weekly letter guaranteed, even in busy weeks.',
    'Carta semanal garantizada, incluso en semanas llenas.',
    'Wochenbrief garantiert, auch in vollen Wochen.',
  );
  static String get premiumBeneficioLimites => _g(
    'Limites ampliados de conversa com o Mentor.',
    'Expanded conversation limits with the Mentor.',
    'Límites ampliados de conversación con el Mentor.',
    'Erweiterte Gesprächslimits mit dem Mentor.',
  );
  static String get premiumAssinar => _g(
    'Assinar',
    'Subscribe',
    'Suscribirse',
    'Abonnieren',
  );
  static String get premiumAtivo => _g(
    'Ativo',
    'Active',
    'Activo',
    'Aktiv',
  );
  static String get premiumGratuito => _g(
    'Gratuito',
    'Free',
    'Gratuito',
    'Kostenlos',
  );
  static String get premiumAtivoAte => _g(
    'Ativo até',
    'Active until',
    'Activo hasta',
    'Aktiv bis',
  );
  static String get premiumCompraSucesso => _g(
    'Assinatura ativada. Bem-vindo ao Premium.',
    'Subscription activated. Welcome to Premium.',
    'Suscripción activada. Bienvenido a Premium.',
    'Abo aktiviert. Willkommen bei Premium.',
  );
  static String get premiumCompraCancelada => _g(
    'Compra cancelada. Você pode assinar quando quiser.',
    'Purchase canceled. You can subscribe anytime.',
    'Compra cancelada. Puedes suscribirte cuando quieras.',
    'Kauf abgebrochen. Du kannst jederzeit abonnieren.',
  );
  static String get premiumRestaurar => _g(
    'Restaurar compras',
    'Restore purchases',
    'Restaurar compras',
    'Käufe wiederherstellen',
  );
  static String get premiumRestaurado => _g(
    'Compras restauradas.',
    'Purchases restored.',
    'Compras restauradas.',
    'Käufe wiederhergestellt.',
  );
  static String get premiumSemProdutos => _g(
    'Não foi possível carregar os planos agora. Tente novamente em instantes.',
    'Could not load the plans right now. Please try again shortly.',
    'No se pudieron cargar los planes ahora. Inténtalo de nuevo en unos instantes.',
    'Die Pläne konnten gerade nicht geladen werden. Bitte versuche es gleich erneut.',
  );
  static String get assinaturaErro => _g(
    'Não foi possível concluir a compra. Tente novamente.',
    'Could not complete the purchase. Try again.',
    'No se pudo completar la compra. Inténtalo de nuevo.',
    'Kauf konnte nicht abgeschlossen werden. Versuche es erneut.',
  );

  // ── PÁTIO (INÍCIO) ─────────────────────────────────────────────────────────
  static String get mentorLabel => _g('MENTOR', 'MENTOR', 'MENTOR', 'MENTOR');
  static String get mentorFoque => _g(
    'Foque em completar suas práticas hoje. O ritmo se constrói um dia de cada vez.',
    'Focus on completing your practices today. Rhythm is built one day at a time.',
    'Concéntrate en completar tus prácticas hoy. El ritmo se construye un día a la vez.',
    'Konzentriere dich darauf, deine Übungen heute zu vollenden. Rhythmus entsteht Tag für Tag.',
  );
  static String get praticasDeHoje => _g(
    'Práticas de Hoje',
    'Today\'s Practices',
    'Prácticas de Hoy',
    'Heutige Übungen',
  );
  static String get nenhumaPraticaAtiva => _g(
    'Nenhuma prática ativa. Vá ao Dôjo para começar.',
    'No active practices. Go to the Dojo to begin.',
    'Sin prácticas activas. Ve al Dojo para comenzar.',
    'Keine aktiven Übungen. Gehe zum Dojo, um zu beginnen.',
  );
  static String praticasDeY(int feitas, int total) {
    if (_l == 'en') return '$feitas of $total practices';
    if (_l == 'es') return '$feitas de $total prácticas';
    if (_l == 'de') return '$feitas von $total Übungen';
    return '$feitas de $total práticas';
  }
  static String get modoSilencio => _g('MODO SILÊNCIO', 'SILENT MODE', 'MODO SILENCIO', 'STILLE-MODUS');
  static String get pausaFocoPresenca => _g(
    'Pausa, foco, presença.',
    'Pause, focus, presence.',
    'Pausa, enfoque, presencia.',
    'Pause, Fokus, Präsenz.',
  );
  static String get carregando => _g(
    'carregando...',
    'loading...',
    'cargando...',
    'wird geladen...',
  );

  // ── NAVEGAÇÃO ──────────────────────────────────────────────────────────────
  static String get inicio     => _g('Início',     'Home',      'Inicio',    'Start');
  static String get mentor     => _g('Mentor',     'Mentor',    'Mentor',    'Mentor');
  static String get praticas   => _g('Práticas',   'Practices', 'Prácticas', 'Übungen');
  static String get jardim     => _g('Jardim',     'Garden',    'Jardín',    'Garten');
  static String get biblioteca => _g('Biblioteca', 'Library',   'Biblioteca','Bibliothek');

  // ── MENTOR (CHAT) ──────────────────────────────────────────────────────────
  static String get mentorSubtitulo => _g(
    'Reflexões e orientações para seu caminho',
    'Reflections and guidance for your path',
    'Reflexiones y orientación para tu camino',
    'Reflexionen und Orientierung für deinen Weg',
  );
  static String get vocelLabel => _g('VOCÊ', 'YOU', 'TÚ', 'DU');
  static String mentorSaudacao(String nome) {
    if (nome.isEmpty) {
      return _g(
        'Estou aqui. O que você gostaria de explorar agora?',
        'I am here. What would you like to explore now?',
        'Estoy aquí. ¿Qué te gustaría explorar ahora?',
        'Ich bin hier. Was möchtest du jetzt erkunden?',
      );
    }
    return _g(
      'Estou aqui, $nome. O que você gostaria de explorar agora?',
      'I am here, $nome. What would you like to explore now?',
      'Estoy aquí, $nome. ¿Qué te gustaría explorar ahora?',
      'Ich bin hier, $nome. Was möchtest du jetzt erkunden?',
    );
  }
  static String get escreva => _g('Escreva...', 'Write...', 'Escribe...', 'Schreibe...');
  static String get mentorErro => _g(
    'Algo se perdeu no caminho. Tente novamente em alguns instantes.',
    'Something got lost along the way. Try again in a moment.',
    'Algo se perdió en el camino. Inténtalo de nuevo en unos instantes.',
    'Etwas ging verloren. Versuche es gleich erneut.',
  );

  // ── DOJÔ (PRÁTICAS) ────────────────────────────────────────────────────────
  static String get dojo => _g('Dôjo', 'Dojo', 'Dojo', 'Dojo');
  static String dojoNPraticasAtivas(int n) {
    if (_l == 'en') return '$n of 5 active practices';
    if (_l == 'es') return '$n de 5 prácticas activas';
    if (_l == 'de') return '$n von 5 aktiven Übungen';
    return '$n de 5 práticas ativas';
  }
  static String get semPraticas => _g(
    'Você ainda não tem práticas. Comece adicionando uma.',
    'You don\'t have any practices yet. Start by adding one.',
    'Aún no tienes prácticas. Comienza añadiendo una.',
    'Du hast noch keine Übungen. Beginne mit dem Hinzufügen einer.',
  );
  static String get adicionarPratica => _g(
    '+  Adicionar prática',
    '+  Add practice',
    '+  Añadir práctica',
    '+  Übung hinzufügen',
  );
  static String get ultimos7Dias => _g(
    'últimos 7 dias',
    'last 7 days',
    'últimos 7 días',
    'letzte 7 Tage',
  );

  // weekday: DateTime.weekday (1=Mon … 7=Sun)
  static String diaSemanaAbrev(int weekday) {
    const pt = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
    const en = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const es = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    const de = ['M', 'D', 'M', 'D', 'F', 'S', 'S'];
    final list = switch (_l) { 'en' => en, 'es' => es, 'de' => de, _ => pt };
    return list[(weekday - 1).clamp(0, 6)];
  }
  static String get limite => _g('LIMITE', 'LIMIT', 'LÍMITE', 'GRENZE');
  static String get cincoPraticasLimite => _g(
    'Cinco práticas é o limite. Mais que isso é dispersão.',
    'Five practices is the limit. More than that is dispersion.',
    'Cinco prácticas es el límite. Más que eso es dispersión.',
    'Fünf Übungen sind das Limit. Mehr ist Zerstreuung.',
  );
  static String get removaUma => _g(
    'Remova uma antes de adicionar outra.',
    'Remove one before adding another.',
    'Quita una antes de añadir otra.',
    'Entferne eine, bevor du eine weitere hinzufügst.',
  );
  static String get entendi => _g('Entendi', 'Got it', 'Entendido', 'Verstanden');
  static String get cancelar => _g('Cancelar', 'Cancel', 'Cancelar', 'Abbrechen');
  static String get excluir => _g('Excluir', 'Delete', 'Eliminar', 'Löschen');
  static String get confirmarExcluirPratica => _g(
    'Deseja realmente excluir a prática?',
    'Do you really want to delete this practice?',
    '¿Realmente quieres eliminar esta práctica?',
    'Möchtest du diese Übung wirklich löschen?',
  );
  static String get perdaEvolucao => _g(
    'Você perderá toda a evolução.',
    'You will lose all the progress.',
    'Perderás todo el progreso.',
    'Du verlierst den gesamten Fortschritt.',
  );
  static String get adicionarPersonalizada => _g(
    'Adicionar prática personalizada',
    'Add custom practice',
    'Añadir práctica personalizada',
    'Eigene Übung hinzufügen',
  );
  static String get novaPraticaPersonalizada => _g(
    'Nova prática personalizada',
    'New custom practice',
    'Nueva práctica personalizada',
    'Neue eigene Übung',
  );
  static String get nomeDaPratica => _g(
    'NOME DA PRÁTICA',
    'PRACTICE NAME',
    'NOMBRE DE LA PRÁCTICA',
    'NAME DER ÜBUNG',
  );
  static String get duracaoOpcional => _g(
    'DURAÇÃO (OPCIONAL)',
    'DURATION (OPTIONAL)',
    'DURACIÓN (OPCIONAL)',
    'DAUER (OPTIONAL)',
  );
  static String get exemploDuracao => _g(
    'ex: 10 min',
    'e.g: 10 min',
    'ej: 10 min',
    'z.B: 10 min',
  );
  static String get adicionar => _g('Adicionar', 'Add', 'Añadir', 'Hinzufügen');
  static String get bibliotecaPratica => _g(
    'Biblioteca',
    'Library',
    'Biblioteca',
    'Bibliothek',
  );
  static String get escolhaPratica => _g(
    'Escolha uma prática',
    'Choose a practice',
    'Elige una práctica',
    'Wähle eine Übung',
  );

  // Categorias de práticas
  static String get catMente       => _g('Mente',      'Mind',       'Mente',     'Geist');
  static String get catCorpo       => _g('Corpo',      'Body',       'Cuerpo',    'Körper');
  static String get catDisciplina  => _g('Disciplina', 'Discipline', 'Disciplina','Disziplin');
  static String get catRelacoes    => _g('Relações',   'Relations',  'Relaciones','Beziehungen');
  static String get catTrabalho    => _g('Trabalho',   'Work',       'Trabajo',   'Arbeit');

  // ── JARDIM ─────────────────────────────────────────────────────────────────
  static String get jardimTitulo => _g('Jardim', 'Garden', 'Jardín', 'Garten');
  static String get reflexaoGuiada => _g(
    'Reflexão guiada',
    'Guided reflection',
    'Reflexión guiada',
    'Geführte Reflexion',
  );
  static String get manha     => _g('Manhã',    'Morning',   'Mañana', 'Morgen');
  static String get meiodia   => _g('Tarde',    'Afternoon', 'Tarde',   'Nachmittag');
  static String get noite     => _g('Noite',    'Night',     'Noche',  'Abend');
  static String get escrever     => _g('Escrever',       'Write',            'Escribir',        'Schreiben');
  static String get jaRespondida => _g('Já respondida',  'Already answered',  'Ya respondida',   'Bereits beantwortet');
  static String get novaPerguntaEmBreve => _g(
    'Nova pergunta no próximo período',
    'New question in the next period',
    'Nueva pregunta en el próximo período',
    'Neue Frage in der nächsten Periode',
  );
  static String get reflexoesAnteriores => _g(
    'REFLEXÕES ANTERIORES',
    'PREVIOUS REFLECTIONS',
    'REFLEXIONES ANTERIORES',
    'FRÜHERE REFLEXIONEN',
  );
  static String get vazioComece => _g(
    'Vazio. Comece hoje.',
    'Empty. Start today.',
    'Vacío. Empieza hoy.',
    'Leer. Beginne heute.',
  );
  static String get escrevaSemPressa => _g(
    'Escreva sem pressa...',
    'Write without rushing...',
    'Escribe sin prisa...',
    'Schreibe ohne Eile...',
  );
  static String get hoje  => _g('Hoje',  'Today',     'Hoy',  'Heute');
  static String get ontem => _g('Ontem', 'Yesterday', 'Ayer', 'Gestern');
  static String diasAtras(int n) {
    if (_l == 'en') return n == 1 ? '1 day ago' : '$n days ago';
    if (_l == 'es') return n == 1 ? 'hace 1 día' : 'hace $n días';
    if (_l == 'de') return n == 1 ? 'vor 1 Tag' : 'vor $n Tagen';
    return '$n dias atrás';
  }

  // ── BIBLIOTECA ─────────────────────────────────────────────────────────────
  static String get bibTitulo => _g('Biblioteca', 'Library', 'Biblioteca', 'Bibliothek');
  static String get estudoSiMesmo => _g(
    'Seu estudo de si mesmo.',
    'Your study of yourself.',
    'Tu estudio de ti mismo.',
    'Dein Studium deiner selbst.',
  );
  static String get cartaMentor => _g(
    'CARTA DO MENTOR',
    'MENTOR\'S LETTER',
    'CARTA DEL MENTOR',
    'BRIEF DES MENTORS',
  );
  static String get cartaNovaBadge => _g('NOVA', 'NEW', 'NUEVA', 'NEU');
  static String get cartaDomingoChegou => _g(
    'Sua carta de domingo chegou. Abra para ler.',
    'Your Sunday letter has arrived. Open to read.',
    'Tu carta del domingo llegó. Abre para leer.',
    'Dein Sonntagsbrief ist da. Öffne zum Lesen.',
  );

  // ── FORMATAÇÃO DE DATA LOCALIZADA ───────────────────────────────────────────

  /// Data calendário no formato local (`dd/MM/yyyy`, `MM/dd/yyyy`, `dd.MM.yyyy`).
  /// Usado em telas de identidade/assinatura. Para datas relativas (hoje/ontem)
  /// use `T.hoje`, `T.ontem`, `T.diasAtras(n)`.
  static String formatarData(DateTime d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final dd = pad(d.day);
    final mm = pad(d.month);
    final yyyy = d.year.toString();
    switch (_l) {
      case 'en': return '$mm/$dd/$yyyy';
      case 'de': return '$dd.$mm.$yyyy';
      // pt e es usam dd/MM/yyyy
      default:   return '$dd/$mm/$yyyy';
    }
  }

  /// Forma curta "dia + mês abreviado" usada nos cards de carta semanal.
  /// PT/ES: "15 jan"; EN: "Jan 15"; DE: "15. Jan.".
  static String formatarDiaMes(int dia, int mes) {
    final mesAbrev = mesAbreviado(mes);
    switch (_l) {
      case 'en': return '$mesAbrev $dia';
      case 'de': return '$dia. $mesAbrev.';
      default:   return '$dia $mesAbrev';
    }
  }

  /// Nome curto do mês no idioma atual (1=jan, 12=dez).
  static String mesAbreviado(int mes) {
    const meses = {
      'pt': ['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'],
      'en': ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'],
      'es': ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'],
      'de': ['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'],
    };
    final lista = meses[_l] ?? meses['pt']!;
    final i = (mes - 1).clamp(0, 11);
    return lista[i];
  }
  static String get explicacaoCarta => _g(
    'Toda semana, aos domingos às 21:00, o Mentor escreve uma análise da sua semana — padrões detectados, conquistas silenciosas e uma pergunta para os próximos sete dias.',
    'Every Sunday at 9:00 PM, the Mentor writes an analysis of your week — patterns detected, silent achievements and a question for the next seven days.',
    'Cada domingo a las 21:00, el Mentor escribe un análisis de tu semana — patrones detectados, logros silenciosos y una pregunta para los próximos siete días.',
    'Jeden Sonntag um 21:00 schreibt der Mentor eine Analyse deiner Woche — erkannte Muster, stille Erfolge und eine Frage für die nächsten sieben Tage.',
  );
  static String get mentorEscrevendo => _g(
    'O Mentor está escrevendo sua carta...',
    'The Mentor is writing your letter...',
    'El Mentor está escribiendo tu carta...',
    'Der Mentor schreibt deinen Brief...',
  );
  static String get erroGerarCarta => _g(
    'Não foi possível gerar agora. Puxe para baixo para tentar novamente.',
    'Could not generate now. Pull down to try again.',
    'No fue posible generar ahora. Desliza hacia abajo para intentar de nuevo.',
    'Konnte jetzt nicht erstellen. Ziehe nach unten, um es erneut zu versuchen.',
  );
  static String get proximaCarta => _g(
    'PRÓXIMA CARTA',
    'NEXT LETTER',
    'PRÓXIMA CARTA',
    'NÄCHSTER BRIEF',
  );
  static String get primeiraCartaPronta => _g(
    'Sua primeira carta chega no domingo às 21h. Continue cultivando os hábitos.',
    'Your first letter arrives on Sunday at 9pm. Keep cultivating your habits.',
    'Tu primera carta llega el domingo a las 21h. Sigue cultivando los hábitos.',
    'Dein erster Brief kommt am Sonntag um 21 Uhr. Pflege weiter deine Gewohnheiten.',
  );
  static String get bemvindoPratica => _g(
    'Bem-vindo. Pratique alguns dias e a primeira carta do Mentor virá no próximo domingo.',
    'Welcome. Practice for a few days and the Mentor\'s first letter will arrive next Sunday.',
    'Bienvenido. Practica unos días y la primera carta del Mentor llegará el próximo domingo.',
    'Willkommen. Übe einige Tage und der erste Brief des Mentors kommt nächsten Sonntag.',
  );
  static String get lerCarta => _g(
    'Ler carta completa',
    'Read full letter',
    'Leer carta completa',
    'Vollständigen Brief lesen',
  );
  static String get cartasAnteriores => _g(
    'CARTAS ANTERIORES',
    'PREVIOUS LETTERS',
    'CARTAS ANTERIORES',
    'FRÜHERE BRIEFE',
  );
  static String semanaDe(String inicio, String fim) {
    if (_l == 'en') return 'WEEK OF $inicio → $fim';
    if (_l == 'es') return 'SEMANA DE $inicio → $fim';
    if (_l == 'de') return 'WOCHE VOM $inicio → $fim';
    return 'SEMANA DE $inicio → $fim';
  }
  static String get observacoes  => _g('OBSERVAÇÕES', 'OBSERVATIONS', 'OBSERVACIONES', 'BEOBACHTUNGEN');
  static String get padroes      => _g('PADRÕES', 'PATTERNS', 'PATRONES', 'MUSTER');
  static String get conquistas   => _g(
    'CONQUISTAS SILENCIOSAS',
    'SILENT ACHIEVEMENTS',
    'LOGROS SILENCIOSOS',
    'STILLE ERFOLGE',
  );
  static String get paraProximaSemana => _g(
    'PARA A PRÓXIMA SEMANA',
    'FOR NEXT WEEK',
    'PARA LA PRÓXIMA SEMANA',
    'FÜR NÄCHSTE WOCHE',
  );
  static String get estaSemana => _g(
    'ESTA SEMANA',
    'THIS WEEK',
    'ESTA SEMANA',
    'DIESE WOCHE',
  );
  static String praticasCumpridas(int n) {
    if (_l == 'en') return n == 1 ? 'practice completed' : 'practices completed';
    if (_l == 'es') return n == 1 ? 'práctica cumplida' : 'prácticas cumplidas';
    if (_l == 'de') return n == 1 ? 'erfüllte Übung' : 'erfüllte Übungen';
    return n == 1 ? 'prática cumprida' : 'práticas cumpridas';
  }
  static String get sequencias => _g('SEQUÊNCIAS', 'STREAKS', 'SECUENCIAS', 'SERIEN');
  static String get semPraticasAtivas => _g(
    'Sem práticas ativas.',
    'No active practices.',
    'Sin prácticas activas.',
    'Keine aktiven Übungen.',
  );
  static String diasStreak(int n) {
    if (_l == 'en') return n == 1 ? 'day' : 'days';
    if (_l == 'es') return n == 1 ? 'día' : 'días';
    if (_l == 'de') return n == 1 ? 'Tag' : 'Tage';
    return n == 1 ? 'dia' : 'dias';
  }
  static String get totais => _g('TOTAIS', 'TOTALS', 'TOTALES', 'GESAMT');
  static String reflexoesEscritas(int n) {
    if (_l == 'en') return n == 1 ? 'reflection written' : 'reflections written';
    if (_l == 'es') return n == 1 ? 'reflexión escrita' : 'reflexiones escritas';
    if (_l == 'de') return n == 1 ? 'geschriebene Reflexion' : 'geschriebene Reflexionen';
    return n == 1 ? 'reflexão escrita' : 'reflexões escritas';
  }
  static String conversasMentor(int n) {
    if (_l == 'en') return n == 1 ? 'conversation with the Mentor' : 'conversations with the Mentor';
    if (_l == 'es') return n == 1 ? 'conversación con el Mentor' : 'conversaciones con el Mentor';
    if (_l == 'de') return n == 1 ? 'Gespräch mit dem Mentor' : 'Gespräche mit dem Mentor';
    return n == 1 ? 'conversa com o Mentor' : 'conversas com o Mentor';
  }
  static String diasNoKairo(int n) {
    if (_l == 'en') return n == 1 ? 'day in Kairo' : 'days in Kairo';
    if (_l == 'es') return n == 1 ? 'día en Kairo' : 'días en Kairo';
    if (_l == 'de') return n == 1 ? 'Tag in Kairo' : 'Tage in Kairo';
    return n == 1 ? 'dia no Kairo' : 'dias no Kairo';
  }

  // ── PERFIL ─────────────────────────────────────────────────────────────────
  static String get perfil => _g('Perfil', 'Profile', 'Perfil', 'Profil');
  static String get conta  => _g('CONTA', 'ACCOUNT', 'CUENTA', 'KONTO');
  static String get identidadeLabel => _g('IDENTIDADE', 'IDENTITY', 'IDENTIDAD', 'IDENTITÄT');
  static String get idiomaLabel => _g('IDIOMA', 'LANGUAGE', 'IDIOMA', 'SPRACHE');
  static String get temaLabel  => _g('TEMA', 'THEME', 'TEMA', 'ERSCHEINUNGSBILD');
  static String get temaClaro  => _g('Claro', 'Light', 'Claro', 'Hell');
  static String get temaEscuro => _g('Escuro', 'Dark', 'Oscuro', 'Dunkel');
  static String get temaDescricao => _g(
    'Escolha como o Kairo se apresenta.',
    'Choose how Kairo appears.',
    'Elige cómo aparece Kairo.',
    'Wähle, wie Kairo erscheint.',
  );
  static String get nome   => _g('Nome', 'Name', 'Nombre', 'Name');
  static String get quemQuerSeTornar => _g(
    'Quem você quer se tornar',
    'Who you want to become',
    'Quién quieres llegar a ser',
    'Wer du werden möchtest',
  );
  static String get oQueTiraEixo => _g(
    'O que mais te tira do eixo',
    'What throws you off balance most',
    'Lo que más te desequilibra',
    'Was dich am meisten aus dem Gleichgewicht bringt',
  );
  static String get areaReordenar => _g(
    'Área que quer reordenar',
    'Area you want to reorder',
    'Área que quieres reordenar',
    'Bereich, den du neu ordnen möchtest',
  );
  static String get ritmoEvolucao => _g(
    'Ritmo de evolução',
    'Pace of evolution',
    'Ritmo de evolución',
    'Tempo der Entwicklung',
  );
  static String get lembreteDiario => _g(
    'LEMBRETE DIÁRIO',
    'DAILY REMINDER',
    'RECORDATORIO DIARIO',
    'TÄGLICHE ERINNERUNG',
  );
  static String get lembrete => _g('Lembrete diário', 'Daily reminder', 'Recordatorio diario', 'Tägliche Erinnerung');
  static String get notifJardimLabel => _g(
    'NOTIFICAÇÕES DO JARDIM',
    'GARDEN NOTIFICATIONS',
    'NOTIFICACIONES DEL JARDÍN',
    'GARTEN-BENACHRICHTIGUNGEN',
  );
  static String get notifJardimDescricao => _g(
    'Três perguntas por dia, às 8h, 13h e 20h.',
    'Three questions a day, at 8am, 1pm and 8pm.',
    'Tres preguntas al día, a las 8h, 13h y 20h.',
    'Drei Fragen am Tag, um 8, 13 und 20 Uhr.',
  );
  static String get ativar    => _g('Ativar', 'Enable',  'Activar',   'Aktivieren');
  static String get desativar => _g('Desativar', 'Disable', 'Desactivar', 'Deaktivieren');
  static String get ativarLembrete => _g(
    'Ativar lembrete diário',
    'Enable daily reminder',
    'Activar recordatorio diario',
    'Tägliche Erinnerung aktivieren',
  );
  static String get desativarLembrete => _g(
    'Desativar lembrete',
    'Disable reminder',
    'Desactivar recordatorio',
    'Erinnerung deaktivieren',
  );
  static String get semPermissao => _g(
    'Sem permissão de notificações. Ative nas configurações do celular.',
    'No notification permission. Enable it in your phone settings.',
    'Sin permiso de notificaciones. Actívalo en los ajustes del teléfono.',
    'Keine Benachrichtigungsberechtigung. Aktiviere sie in den Telefoneinstellungen.',
  );
  static String get mudarSenha => _g('Mudar senha', 'Change password', 'Cambiar contraseña', 'Passwort ändern');
  static String get novaSenha  => _g('Nova senha',  'New password',    'Nueva contraseña',   'Neues Passwort');
  static String get senhaMinimoCaracteres => _g(
    'Mínimo 6 caracteres',
    'Minimum 6 characters',
    'Mínimo 6 caracteres',
    'Mindestens 6 Zeichen',
  );
  static String get senhaAtualizada => _g(
    'Senha atualizada',
    'Password updated',
    'Contraseña actualizada',
    'Passwort aktualisiert',
  );

  static String get sairConta => _g(
    'Sair da conta',
    'Sign out',
    'Cerrar sesión',
    'Abmelden',
  );
  static String get sairContaPergunta => _g(
    'Sair da conta?',
    'Sign out?',
    '¿Cerrar sesión?',
    'Abmelden?',
  );
  static String get dadosContinuam => _g(
    'Seus dados continuam aqui. Você só sai do app.',
    'Your data stays here. You only leave the app.',
    'Tus datos siguen aquí. Solo sales de la app.',
    'Deine Daten bleiben hier. Du verlässt nur die App.',
  );
  static String get sair  => _g('Sair', 'Sign out', 'Salir', 'Abmelden');
  static String get ficar => _g('Ficar', 'Stay', 'Quedarme', 'Bleiben');

  // ── AVATAR ─────────────────────────────────────────────────────────────────
  static String get trocarFoto    => _g('Trocar foto',    'Change photo',   'Cambiar foto',   'Foto ändern');
  static String get adicionarFoto => _g('Adicionar foto', 'Add photo',      'Agregar foto',   'Foto hinzufügen');
  static String get galeria       => _g('Galeria',        'Gallery',        'Galería',        'Galerie');
  static String get camera        => _g('Câmera',         'Camera',         'Cámara',         'Kamera');
  static String get removerFoto   => _g('Remover foto',   'Remove photo',   'Eliminar foto',  'Foto entfernen');

  // ── MODO SILÊNCIO ──────────────────────────────────────────────────────────
  static String get modoSilencioTitulo => _g('Modo Silêncio', 'Silent Mode', 'Modo Silencio', 'Stille-Modus');
  static String get variante => _g('VARIANTE', 'VARIANT', 'VARIANTE', 'VARIANTE');
  static String get focoProfundo => _g(
    'Foco profundo',
    'Deep focus',
    'Foco profundo',
    'Tiefer Fokus',
  );
  static String get focoProfundoDesc => _g(
    'Para trabalhar sem distrações.',
    'To work without distractions.',
    'Para trabajar sin distracciones.',
    'Um ohne Ablenkung zu arbeiten.',
  );
  static String get meditacao => _g('Meditação', 'Meditation', 'Meditación', 'Meditation');
  static String get meditacaoDesc => _g(
    'Sentar em silêncio. Apenas presença.',
    'Sit in silence. Just presence.',
    'Sentarse en silencio. Solo presencia.',
    'In Stille sitzen. Nur Präsenz.',
  );
  static String get pausaEstrategica => _g(
    'Pausa estratégica',
    'Strategic pause',
    'Pausa estratégica',
    'Strategische Pause',
  );
  static String get pausaEstrategicaDesc => _g(
    'Dez minutos com uma única pergunta.',
    'Ten minutes with a single question.',
    'Diez minutos con una sola pregunta.',
    'Zehn Minuten mit einer einzigen Frage.',
  );
  static String get resetEmocional => _g(
    'Reset emocional',
    'Emotional reset',
    'Reset emocional',
    'Emotionaler Reset',
  );
  static String get resetEmocionalDesc => _g(
    'Respiração guiada de 4 minutos.',
    'Guided 4-minute breathing.',
    'Respiración guiada de 4 minutos.',
    'Geführte 4-Minuten-Atmung.',
  );
  static String get quantoTempo => _g(
    'Quanto tempo?',
    'How long?',
    '¿Cuánto tiempo?',
    'Wie lange?',
  );
  static String somAmbientePergunta(int min) {
    if (_l == 'en') return '$min minutes · Ambient sound?';
    if (_l == 'es') return '$min minutos · ¿Sonido ambiente?';
    if (_l == 'de') return '$min Minuten · Hintergrundgeräusch?';
    return '$min minutos · Som ambiente?';
  }
  static String minutos(int n) {
    if (_l == 'en') return '$n minutes';
    if (_l == 'es') return '$n minutos';
    if (_l == 'de') return '$n Minuten';
    return '$n minutos';
  }
  static String get somSilencio => _g('Silêncio', 'Silence', 'Silencio', 'Stille');
  static String get somChuva    => _g('Chuva',    'Rain',    'Lluvia',   'Regen');
  static String get somVento    => _g('Vento',    'Wind',    'Viento',   'Wind');
  static String get somBambu    => _g('Bambu',    'Bamboo',  'Bambú',    'Bambus');
  static String get encerrar    => _g('Encerrar', 'End',     'Terminar', 'Beenden');
  static String get dndTitulo => _g(
    'Silêncio total',
    'Total silence',
    'Silencio total',
    'Totale Stille',
  );
  static String get dndExplicacao => _g(
    'O Modo Silêncio existe para criar um espaço de presença real.\n\nPara honrar esse momento por completo, o Kairo precisa ativar o Não Perturbe do seu aparelho. Durante a sessão, nenhuma notificação chegará — sem mensagens, sem chamadas, sem alertas.\n\nAo encerrar, o aparelho volta ao estado anterior automaticamente.',
    'Silent Mode exists to create a space of real presence.\n\nTo fully honor this moment, Kairo needs to activate Do Not Disturb on your device. During the session, no notifications will arrive — no messages, no calls, no alerts.\n\nWhen the session ends, the device returns to its previous state automatically.',
    'El Modo Silencio existe para crear un espacio de presencia real.\n\nPara honrar este momento por completo, Kairo necesita activar No Molestar en tu dispositivo. Durante la sesión, no llegará ninguna notificación — sin mensajes, sin llamadas, sin alertas.\n\nAl terminar, el dispositivo vuelve a su estado anterior automáticamente.',
    'Der Stille-Modus existiert, um einen Raum echter Präsenz zu schaffen.\n\nUm diesen Moment vollständig zu ehren, muss Kairo Nicht stören auf deinem Gerät aktivieren. Während der Sitzung werden keine Benachrichtigungen eingehen — keine Nachrichten, keine Anrufe, keine Warnungen.\n\nWenn die Sitzung endet, kehrt das Gerät automatisch in seinen vorherigen Zustand zurück.',
  );
  static String get dndConceder => _g(
    'Conceder acesso',
    'Grant access',
    'Conceder acceso',
    'Zugriff gewähren',
  );
  static String get dndPular => _g(
    'Continuar sem',
    'Continue without',
    'Continuar sin',
    'Weiter ohne',
  );
  static String get inspire     => _g('inspire',  'inhale',  'inhala',   'einatmen');
  static String get expire      => _g('expire',   'exhale',  'exhala',   'ausatmen');
  static String get oQueImportaAgora => _g(
    'O que mais importa agora?',
    'What matters most now?',
    '¿Qué importa más ahora?',
    'Was zählt jetzt am meisten?',
  );
  static String get ritmoSeSustenta => _g(
    'O ritmo se sustenta.',
    'The rhythm sustains itself.',
    'El ritmo se sostiene.',
    'Der Rhythmus trägt sich.',
  );
  static String get volteAoDia => _g(
    'Volte ao dia com presença.',
    'Return to the day with presence.',
    'Vuelve al día con presencia.',
    'Kehre mit Präsenz zum Tag zurück.',
  );
  static String get voltar => _g('Voltar', 'Back', 'Volver', 'Zurück');

  // ── RELAXA E DURMA ─────────────────────────────────────────────────────────
  static String get relaxaEDurmaTitulo => _g(
    'Relaxa e Durma',
    'Relax & Sleep',
    'Relájate y Duerme',
    'Entspannen & Schlafen',
  );
  static String get relaxaEDurmaSubtitulo => _g(
    'Adormeça com som, mesmo de tela desligada.',
    'Fall asleep to sound, even with the screen off.',
    'Duérmete con sonido, incluso con la pantalla apagada.',
    'Schlafe mit Klang ein, auch bei ausgeschaltetem Bildschirm.',
  );
  static String get escolhaSom => _g(
    'Escolha um som',
    'Choose a sound',
    'Elige un sonido',
    'Wähle einen Klang',
  );
  static String get porQuantoTempo => _g(
    'Por quanto tempo?',
    'For how long?',
    '¿Por cuánto tiempo?',
    'Für wie lange?',
  );
  static String get gruposAmbientes => _g(
    'AMBIENTES',
    'AMBIENT',
    'AMBIENTES',
    'UMGEBUNG',
  );
  static String get gruposFrequencias => _g(
    'FREQUÊNCIAS',
    'FREQUENCIES',
    'FRECUENCIAS',
    'FREQUENZEN',
  );
  static String get somSelva => _g('Selva', 'Jungle', 'Selva', 'Dschungel');
  static String get freq432 => _g(
    '432 Hz · Harmonia',
    '432 Hz · Harmony',
    '432 Hz · Armonía',
    '432 Hz · Harmonie',
  );
  static String get freq528 => _g(
    '528 Hz · Cura emocional',
    '528 Hz · Emotional healing',
    '528 Hz · Sanación emocional',
    '528 Hz · Emotionale Heilung',
  );
  static String get freq396 => _g(
    '396 Hz · Liberação',
    '396 Hz · Release',
    '396 Hz · Liberación',
    '396 Hz · Befreiung',
  );
  static String get freq639 => _g(
    '639 Hz · Conexão',
    '639 Hz · Connection',
    '639 Hz · Conexión',
    '639 Hz · Verbindung',
  );
  static String get freq783 => _g(
    '7.83 Hz · Schumann',
    '7.83 Hz · Schumann',
    '7.83 Hz · Schumann',
    '7.83 Hz · Schumann',
  );
  static String get aNoiteToda => _g(
    'A noite toda',
    'All night',
    'Toda la noche',
    'Die ganze Nacht',
  );
  static String horas(int h) {
    if (_l == 'en') return h == 1 ? '1 hour' : '$h hours';
    if (_l == 'es') return h == 1 ? '1 hora' : '$h horas';
    if (_l == 'de') return h == 1 ? '1 Stunde' : '$h Stunden';
    return h == 1 ? '1 hora' : '$h horas';
  }
  static String get bomSono => _g(
    'Bom sono.',
    'Sleep well.',
    'Buen descanso.',
    'Schlaf gut.',
  );
  // Notificação do serviço em primeiro plano enquanto o som de dormir toca.
  static String get dormirNotifTitulo => _g(
    'Relaxa e Durma',
    'Relax & Sleep',
    'Relájate y Duerme',
    'Entspannen & Schlafen',
  );
  static String get dormirNotifTexto => _g(
    'Tocando para o seu sono.',
    'Playing for your sleep.',
    'Sonando para tu descanso.',
    'Klingt für deinen Schlaf.',
  );
  static String get tutorialDormirTitulo => _g(
    'Relaxa e Durma',
    'Relax & Sleep',
    'Relájate y Duerme',
    'Entspannen & Schlafen',
  );
  static String get tutorialDormirTexto => _g(
    'Escolha um som (ambiente ou frequência) e um tempo. O áudio continua tocando mesmo com a tela desligada e desliga sozinho com um fade suave no fim. Toque longo na tela para parar.',
    'Choose a sound (ambient or frequency) and a duration. The audio keeps playing even with the screen off and fades out on its own at the end. Long-press the screen to stop.',
    'Elige un sonido (ambiente o frecuencia) y un tiempo. El audio sigue sonando incluso con la pantalla apagada y se apaga solo con un suave fundido al final. Mantén pulsada la pantalla para detener.',
    'Wähle einen Klang (Umgebung oder Frequenz) und eine Dauer. Der Ton spielt auch bei ausgeschaltetem Bildschirm weiter und blendet am Ende von selbst aus. Lange auf den Bildschirm tippen zum Stoppen.',
  );

  // ── ONBOARDING ─────────────────────────────────────────────────────────────
  static String get prov1 => _g('Você não precisa', 'You don\'t need', 'No necesitas', 'Du brauchst nicht');
  static String get prov2 => _g('de mais um app.',  'another app.',     'otra app.',     'noch eine App.');
  static String get prov3 => _g('Você precisa',     'You need',         'Necesitas',     'Du brauchst');
  static String get prov4 => _g('de mais silêncio.','more silence.',    'más silencio.', 'mehr Stille.');
  static String get toquePraContinuar => _g(
    'toque para continuar',
    'tap to continue',
    'toca para continuar',
    'zum Fortfahren tippen',
  );
  static String get deslizePraContinuar => _g(
    'deslize para continuar',
    'swipe to continue',
    'desliza para continuar',
    'wischen, um fortzufahren',
  );
  static String get quemSeTornar => _g(
    'Quem você quer\nse tornar?',
    'Who do you\nwant to become?',
    '¿Quién quieres\nllegar a ser?',
    'Wer willst du\nwerden?',
  );
  static String get apenasUmaFrase => _g(
    'Escreva apenas uma frase. Sem pressa.',
    'Write just one sentence. Take your time.',
    'Escribe solo una frase. Sin prisa.',
    'Schreibe nur einen Satz. Ohne Eile.',
  );
  static String get oQueTiraEixoHoje => _g(
    'O que mais te tira\ndo eixo hoje?',
    'What throws you off\nbalance most today?',
    '¿Qué te saca\nmás del eje hoy?',
    'Was bringt dich\nheute am meisten aus dem Gleichgewicht?',
  );
  static String get qualArea => _g(
    'Qual área da sua vida\nvocê quer reordenar primeiro?',
    'Which area of your life\ndo you want to reorder first?',
    '¿Qué área de tu vida\nquieres reordenar primero?',
    'Welchen Bereich deines Lebens\nmöchtest du zuerst neu ordnen?',
  );
  static String get qualRitmo => _g(
    'Com que ritmo você\nquer evoluir?',
    'At what pace do you\nwant to evolve?',
    '¿A qué ritmo quieres\nevolucionar?',
    'In welchem Tempo\nmöchtest du dich entwickeln?',
  );

  // Opções Q1 (desequilibrio)
  static String get optAnsiedade        => _g('Ansiedade',         'Anxiety',          'Ansiedad',           'Angst');
  static String get optFaltaFoco        => _g('Falta de foco',     'Lack of focus',    'Falta de enfoque',   'Mangel an Fokus');
  static String get optImpulsos         => _g('Impulsos',          'Impulses',         'Impulsos',           'Impulse');
  static String get optFaltaDirecao     => _g('Falta de direção',  'Lack of direction','Falta de dirección', 'Mangel an Richtung');
  static String get optExcessoTela      => _g('Excesso de tela',   'Screen excess',    'Exceso de pantalla', 'Bildschirmüberlastung');

  // Opções Q3 (ritmo)
  static String get optLentoSustentavel => _g(
    'Lento e sustentável',
    'Slow and sustainable',
    'Lento y sostenible',
    'Langsam und nachhaltig',
  );
  static String get optMedioConstante => _g(
    'Médio e constante',
    'Medium and constant',
    'Medio y constante',
    'Mittel und konstant',
  );
  static String get optAcelerado => _g(
    'Acelerado e exigente',
    'Accelerated and demanding',
    'Acelerado y exigente',
    'Beschleunigt und fordernd',
  );

  // Tela 5: apresentação do Mentor
  static String get souMentor       => _g('Sou o Mentor.', 'I am the Mentor.', 'Soy el Mentor.', 'Ich bin der Mentor.');
  static String get naoVouEmpurrar  => _g(
    'Não vou te empurrar.',
    'I will not push you.',
    'No te empujaré.',
    'Ich werde dich nicht drängen.',
  );
  static String get lembrarQuemQuer => _g(
    'Vou te lembrar de quem\nvocê quer ser.',
    'I will remind you who\nyou want to be.',
    'Te recordaré quién\nquieres ser.',
    'Ich werde dich daran erinnern,\nwer du sein willst.',
  );

  // Tela 7: primeira prática
  static String get suaPrimeiraPratica => _g(
    'Sua primeira\nprática:',
    'Your first\npractice:',
    'Tu primera\npráctica:',
    'Deine erste\nÜbung:',
  );
  static String get cincoMinSilencio => _g(
    'Cinco minutos de silêncio ao acordar. Sem celular. Apenas presença.',
    'Five minutes of silence upon waking. No phone. Just presence.',
    'Cinco minutos de silencio al despertar. Sin teléfono. Solo presencia.',
    'Fünf Minuten Stille beim Aufwachen. Kein Handy. Nur Präsenz.',
  );
  static String get por7Dias => _g('Por 7 dias.', 'For 7 days.', 'Durante 7 días.', 'Für 7 Tage.');
  static String get aceitoCompromisso => _g(
    'Aceito este compromisso',
    'I accept this commitment',
    'Acepto este compromiso',
    'Ich nehme diese Verpflichtung an',
  );

  // Tela 8: boas-vindas final
  static String bemVindoAoKairo(String nome) {
    if (nome.isEmpty) {
      return _g(
        'Bem-vindo ao Kairo.',
        'Welcome to Kairo.',
        'Bienvenido a Kairo.',
        'Willkommen bei Kairo.',
      );
    }
    return _g(
      'Bem-vindo, $nome.',
      'Welcome, $nome.',
      'Bienvenido, $nome.',
      'Willkommen, $nome.',
    );
  }
  static String get pequenosPassos => _g(
    'Pequenos passos.\nVida inteira.',
    'Small steps.\nA whole life.',
    'Pequeños pasos.\nUna vida entera.',
    'Kleine Schritte.\nEin ganzes Leben.',
  );
  static String get entrarNoTemplo => _g(
    'Entrar no templo',
    'Enter the temple',
    'Entrar al templo',
    'Den Tempel betreten',
  );

  static String get tutoriaisLabel => _g(
    'TUTORIAIS',
    'TUTORIALS',
    'TUTORIALES',
    'TUTORIALS',
  );

  // ── CANAIS DE NOTIFICAÇÃO ANDROID ───────────────────────────────────────────
  // Visíveis ao usuário em Configurações do telefone → Apps → Kairo → Notificações.
  // Atenção: o Android fixa nome/descrição na PRIMEIRA criação do canal — para
  // refletir mudança de idioma, é preciso recriá-lo (deleteNotificationChannel
  // antes de criar). Isso está implementado em `core/notificacoes.dart`.
  static String get canalLembreteNome => _g(
    'Lembrete de prática',
    'Practice reminder',
    'Recordatorio de práctica',
    'Übungserinnerung',
  );
  static String get canalLembreteDesc => _g(
    'Lembrete diário do Mentor',
    'Daily reminder from the Mentor',
    'Recordatorio diario del Mentor',
    'Tägliche Erinnerung vom Mentor',
  );
  static String get canalCartaNome => _g(
    'Carta semanal',
    'Weekly letter',
    'Carta semanal',
    'Wochenbrief',
  );
  static String get canalCartaDesc => _g(
    'A carta de domingo do Mentor',
    'The Mentor\'s Sunday letter',
    'La carta del domingo del Mentor',
    'Der Sonntagsbrief des Mentors',
  );
  static String get canalJardimNome => _g(
    'Jardim',
    'Garden',
    'Jardín',
    'Garten',
  );
  static String get canalJardimDesc => _g(
    'Perguntas do Mentor no Jardim',
    'Questions from the Mentor in the Garden',
    'Preguntas del Mentor en el Jardín',
    'Fragen vom Mentor im Garten',
  );

  // ── TUTORIAIS (mostrados na primeira visita de cada tela) ───────────────────
  static String get tutorialPatioTitulo => _g(
    'Pátio',
    'Courtyard',
    'Patio',
    'Hof',
  );
  static String get tutorialPatioTexto => _g(
    'Aqui é a entrada do seu templo. Veja sua saudação do dia, mensagem do Mentor, suas práticas de hoje e o Modo Silêncio. Toque no ícone de pessoa no canto superior direito para acessar seu Perfil.',
    'This is the entrance of your temple. See your daily greeting, message from the Mentor, today\'s practices, and Silent Mode. Tap the person icon at the top right to access your Profile.',
    'Esta es la entrada de tu templo. Mira tu saludo del día, mensaje del Mentor, tus prácticas de hoy y el Modo Silencio. Toca el ícono de persona en la esquina superior derecha para acceder a tu Perfil.',
    'Dies ist der Eingang zu deinem Tempel. Sieh deinen täglichen Gruß, die Nachricht des Mentors, die heutigen Übungen und den Stille-Modus. Tippe auf das Personen-Symbol oben rechts, um zu deinem Profil zu gelangen.',
  );

  static String get tutorialMentorTitulo => _g(
    'Mentor',
    'Mentor',
    'Mentor',
    'Mentor',
  );
  static String get tutorialMentorTexto => _g(
    'Converse com o Mentor. Ele conhece sua identidade e te ajuda a refletir, sem empurrar. Pergunte qualquer coisa, ou apenas conte como você está.',
    'Talk to the Mentor. He knows your identity and helps you reflect, without pushing. Ask anything, or just tell how you are.',
    'Habla con el Mentor. Él conoce tu identidad y te ayuda a reflexionar, sin empujar. Pregunta cualquier cosa, o solo cuenta cómo estás.',
    'Sprich mit dem Mentor. Er kennt deine Identität und hilft dir, zu reflektieren, ohne zu drängen. Frage alles, oder erzähle einfach, wie es dir geht.',
  );

  static String get tutorialDojoTitulo => _g(
    'Dôjo',
    'Dojo',
    'Dojo',
    'Dojo',
  );
  static String get tutorialDojoTexto => _g(
    'Aqui você cultiva até 5 práticas. Cada dia praticado vira uma pedra de consistência. Mais do que 5 é dispersão — o Mentor recusa adicionar a sexta.',
    'Here you cultivate up to 5 practices. Each practiced day becomes a stone of consistency. More than 5 is dispersion — the Mentor refuses to add a sixth.',
    'Aquí cultivas hasta 5 prácticas. Cada día practicado se vuelve una piedra de consistencia. Más de 5 es dispersión — el Mentor se niega a añadir una sexta.',
    'Hier kultivierst du bis zu 5 Übungen. Jeder geübte Tag wird zu einem Stein der Beständigkeit. Mehr als 5 ist Zerstreuung — der Mentor weigert sich, eine sechste hinzuzufügen.',
  );

  static String get tutorialJardimTitulo => _g(
    'Jardim',
    'Garden',
    'Jardín',
    'Garten',
  );
  static String get tutorialJardimTexto => _g(
    'Reflexão guiada. O Mentor escolhe uma pergunta para cada momento do dia: manhã, tarde e noite. Escreva sem pressa.',
    'Guided reflection. The Mentor chooses a question for each moment of the day: morning, afternoon and night. Write without rushing.',
    'Reflexión guiada. El Mentor elige una pregunta para cada momento del día: mañana, tarde y noche. Escribe sin prisa.',
    'Geführte Reflexion. Der Mentor wählt eine Frage für jeden Moment des Tages: Morgen, Nachmittag und Abend. Schreibe ohne Eile.',
  );

  static String get tutorialBibliotecaTitulo => _g(
    'Biblioteca',
    'Library',
    'Biblioteca',
    'Bibliothek',
  );
  static String get tutorialBibliotecaTexto => _g(
    'Seu estudo de si mesmo. Todos os domingos às 21h, o Mentor escreve uma carta sobre sua semana — padrões, conquistas silenciosas e uma pergunta para os próximos sete dias.',
    'Your study of yourself. Every Sunday at 9pm, the Mentor writes a letter about your week — patterns, silent achievements and a question for the next seven days.',
    'Tu estudio de ti mismo. Todos los domingos a las 21h, el Mentor escribe una carta sobre tu semana — patrones, logros silenciosos y una pregunta para los próximos siete días.',
    'Dein Studium deiner selbst. Jeden Sonntag um 21 Uhr schreibt der Mentor einen Brief über deine Woche — Muster, stille Erfolge und eine Frage für die nächsten sieben Tage.',
  );

  static String get tutorialSilencioTitulo => _g(
    'Modo Silêncio',
    'Silent Mode',
    'Modo Silencio',
    'Stille-Modus',
  );
  static String get tutorialSilencioTexto => _g(
    'Quatro variantes de pausa: foco profundo, meditação, pausa estratégica e reset emocional. Escolha a variante, o tempo e o som ambiente. Sem contador visível durante a sessão.',
    'Four variants of pause: deep focus, meditation, strategic pause and emotional reset. Choose the variant, time and ambient sound. No visible counter during the session.',
    'Cuatro variantes de pausa: foco profundo, meditación, pausa estratégica y reset emocional. Elige la variante, el tiempo y el sonido ambiente. Sin contador visible durante la sesión.',
    'Vier Pausen-Varianten: tiefer Fokus, Meditation, strategische Pause und emotionaler Reset. Wähle die Variante, die Zeit und das Hintergrundgeräusch. Kein sichtbarer Zähler während der Sitzung.',
  );

  static String get tutorialPerfilTitulo => _g(
    'Perfil',
    'Profile',
    'Perfil',
    'Profil',
  );
  static String get tutorialPerfilTexto => _g(
    'Suas respostas, idioma, e lembrete diário. Tudo editável a qualquer momento. Aqui você também sai da conta.',
    'Your answers, language, and daily reminder. All editable at any time. Here you also sign out.',
    'Tus respuestas, idioma y recordatorio diario. Todo editable en cualquier momento. Aquí también cierras sesión.',
    'Deine Antworten, Sprache und tägliche Erinnerung. Alles jederzeit editierbar. Hier meldest du dich auch ab.',
  );

  // ── PERGUNTAS DO JARDIM POR MOMENTO DO DIA (20 cada × 4 idiomas) ────────────
  static List<String> get perguntasJardimManha {
    if (_l == 'en') return const [
      'Who would you be if no one was watching today?',
      'What do you want to be today?',
      'What is the first thing that deserves your attention?',
      'What will you not negotiate today?',
      'Who do you need to become in the coming hours?',
      'What will be your anchor if the day gets heavy?',
      'What are you willing to let go of?',
      'What small gesture would change the tone of your day?',
      'What do you want to avoid repeating from yesterday?',
      'Where do you want to start?',
      'What presence do you want to bring with you?',
      'What word guides your day?',
      'What kind of silence do you need today?',
      'Who needs your attention first?',
      'What is your clearest intention for this morning?',
      'What boundary are you willing to maintain?',
      'What might throw you off balance, and what brings you back?',
      'What good thing do you want to make happen today?',
      'What needs to end in the coming hours?',
      'How do you want to arrive at the evening?',
    ];
    if (_l == 'es') return const [
      '¿Quién serías si nadie te estuviera mirando hoy?',
      '¿Quién quieres ser hoy?',
      '¿Cuál es la primera cosa que merece tu atención?',
      '¿Qué no vas a negociar hoy?',
      '¿En quién necesitas convertirte en las próximas horas?',
      '¿Cuál será tu ancla si el día se vuelve pesado?',
      '¿Qué estás dispuesto a soltar?',
      '¿Qué pequeño gesto cambiaría el tono de tu día?',
      '¿Qué quieres evitar repetir de ayer?',
      '¿Por dónde quieres empezar?',
      '¿Qué presencia quieres llevar contigo?',
      '¿Qué palabra guía tu día?',
      '¿Qué tipo de silencio necesitas hoy?',
      '¿Quién necesita tu atención primero?',
      '¿Cuál es tu intención más clara para esta mañana?',
      '¿Qué límite estás dispuesto a mantener?',
      '¿Qué puede sacarte del eje, y qué te trae de vuelta?',
      '¿Qué cosa buena quieres hacer realidad hoy?',
      '¿Qué necesita terminar en las próximas horas?',
      '¿Cómo quieres llegar a la noche?',
    ];
    if (_l == 'de') return const [
      'Wer wärst du, wenn dich heute niemand beobachten würde?',
      'Wer willst du heute sein?',
      'Was verdient als Erstes deine Aufmerksamkeit?',
      'Worüber wirst du heute nicht verhandeln?',
      'Wer musst du in den nächsten Stunden werden?',
      'Was wird dein Anker sein, wenn der Tag schwer wird?',
      'Was bist du bereit loszulassen?',
      'Welche kleine Geste würde den Ton deines Tages ändern?',
      'Was möchtest du nicht von gestern wiederholen?',
      'Wo möchtest du anfangen?',
      'Welche Präsenz möchtest du mitnehmen?',
      'Welches Wort leitet deinen Tag?',
      'Welche Art von Stille brauchst du heute?',
      'Wer braucht zuerst deine Aufmerksamkeit?',
      'Was ist deine klarste Absicht für diesen Morgen?',
      'Welche Grenze bist du bereit zu wahren?',
      'Was könnte dich aus dem Gleichgewicht bringen, und was bringt dich zurück?',
      'Welche gute Sache möchtest du heute geschehen lassen?',
      'Was muss in den nächsten Stunden enden?',
      'Wie möchtest du am Abend ankommen?',
    ];
    return const [
      'Quem você seria se ninguém estivesse olhando hoje?',
      'O que você quer ser hoje?',
      'Qual a primeira coisa que merece sua atenção?',
      'O que você não vai negociar hoje?',
      'Em quem você precisa se tornar nas próximas horas?',
      'Qual será a sua âncora se o dia ficar pesado?',
      'O que você está disposto a soltar?',
      'Que pequeno gesto mudaria o tom do seu dia?',
      'O que você quer evitar repetir de ontem?',
      'Por onde você quer começar?',
      'Qual presença você quer levar contigo?',
      'Que palavra guia o seu dia?',
      'Que tipo de silêncio você precisa hoje?',
      'Quem precisa receber sua atenção primeiro?',
      'Qual é a sua intenção mais clara para esta manhã?',
      'Que limite você está disposto a manter?',
      'O que pode te tirar do eixo, e o que te traz de volta?',
      'Qual coisa boa você quer fazer acontecer hoje?',
      'O que precisa terminar nas próximas horas?',
      'Como você quer chegar à noite?',
    ];
  }

  static List<String> get perguntasJardimTarde {
    if (_l == 'en') return const [
      'What internal conversation are you avoiding?',
      'What is costing you energy without yielding results?',
      'What feeling did you ignore in the last few hours?',
      'How are you now, truly?',
      'What has changed in you since this morning?',
      'Where did your energy go?',
      'Are you still aligned with who you wanted to be today?',
      'What small victory has already happened?',
      'What is weighing on you in this very moment?',
      'Where in the body is the day accumulating?',
      'Do you need a pause or presence?',
      'What are you postponing right now?',
      'Which emotion is asking to be named?',
      'What deserves to be interrupted?',
      'Are you reacting or responding?',
      'What part of you has been missing so far?',
      'What do you need to give thanks for now?',
      'At what rhythm are you walking?',
      'Is something asking for a yes or a no?',
      'What is the next important micro-decision?',
    ];
    if (_l == 'es') return const [
      '¿Qué conversación interna estás evitando?',
      '¿Qué te está costando energía sin dar resultado?',
      '¿Qué sentimiento ignoraste en las últimas horas?',
      '¿Cómo estás ahora, de verdad?',
      '¿Qué ha cambiado en ti desde la mañana?',
      '¿A dónde fue tu energía?',
      '¿Sigues alineado con quien querías ser hoy?',
      '¿Qué pequeña victoria ya ha sucedido?',
      '¿Qué te pesa en este preciso momento?',
      '¿En qué parte del cuerpo se está acumulando el día?',
      '¿Necesitas una pausa o presencia?',
      '¿Qué estás aplazando ahora mismo?',
      '¿Qué emoción pide ser nombrada?',
      '¿Qué merece ser interrumpido?',
      '¿Estás reaccionando o respondiendo?',
      '¿Qué parte de ti ha faltado hasta ahora?',
      '¿Qué necesitas agradecer ahora?',
      '¿A qué ritmo estás caminando?',
      '¿Algo está pidiendo un sí o un no?',
      '¿Cuál es la próxima micro-decisión importante?',
    ];
    if (_l == 'de') return const [
      'Welches innere Gespräch vermeidest du?',
      'Was kostet dich Energie, ohne Ergebnisse zu bringen?',
      'Welches Gefühl hast du in den letzten Stunden ignoriert?',
      'Wie geht es dir jetzt, wirklich?',
      'Was hat sich in dir seit dem Morgen verändert?',
      'Wohin ist deine Energie gegangen?',
      'Bist du noch im Einklang mit dem, wer du heute sein wolltest?',
      'Welcher kleine Sieg ist bereits geschehen?',
      'Was lastet auf dir in genau diesem Moment?',
      'An welchem Ort im Körper sammelt sich der Tag?',
      'Brauchst du eine Pause oder Präsenz?',
      'Was schiebst du gerade auf?',
      'Welche Emotion bittet darum, benannt zu werden?',
      'Was verdient unterbrochen zu werden?',
      'Reagierst du oder antwortest du?',
      'Welcher Teil von dir hat bisher gefehlt?',
      'Wofür musst du dich jetzt bedanken?',
      'In welchem Rhythmus gehst du?',
      'Bittet etwas um ein Ja oder ein Nein?',
      'Was ist die nächste wichtige Mikro-Entscheidung?',
    ];
    return const [
      'Que conversa interna você está evitando?',
      'O que está te custando energia sem dar resultado?',
      'Qual sentimento você ignorou nas últimas horas?',
      'Como você está agora, de verdade?',
      'O que mudou em você desde de manhã?',
      'Onde sua energia foi parar?',
      'Você ainda está alinhado com quem queria ser hoje?',
      'Que pequena vitória já aconteceu?',
      'O que está pesando neste exato momento?',
      'Em qual lugar do corpo o dia está se acumulando?',
      'Você precisa de uma pausa ou de presença?',
      'O que você está adiando agora mesmo?',
      'Qual emoção pede para ser nomeada?',
      'O que merece ser interrompido?',
      'Você está reagindo ou respondendo?',
      'O que faltou de você até agora?',
      'O que você precisa agradecer agora?',
      'Em qual ritmo você está caminhando?',
      'Algo está pedindo um sim ou um não?',
      'Qual a próxima micro-decisão importante?',
    ];
  }

  static List<String> get perguntasJardimNoite {
    if (_l == 'en') return const [
      'What did you postpone today that you shouldn\'t have?',
      'In what moment of today were you who you want to be?',
      'If today were a sentence, what would it be?',
      'What deserved your attention today?',
      'What do you need to let go of to sleep in peace?',
      'Where were you strong today, even without realizing it?',
      'Which conversation did not happen today?',
      'What cost and what was worth it?',
      'Which emotion dominated your day?',
      'What pattern repeated itself once again?',
      'Would you have liked to walk slower or faster?',
      'What did you discover about yourself in the last few hours?',
      'Where were you most human today?',
      'What small thing was important and almost went unnoticed?',
      'Did you end the day as you wanted to begin it?',
      'What deserves to be carried into tomorrow?',
      'Who do you need to forgive before sleeping, including yourself?',
      'What did you not do out of fear?',
      'Which of your gestures today will echo?',
      'If you could redo 10 minutes of the day, which would they be?',
    ];
    if (_l == 'es') return const [
      '¿Qué aplazaste hoy que no deberías?',
      '¿En qué momento de hoy fuiste quien quieres ser?',
      'Si hoy fuera una frase, ¿cuál sería?',
      '¿Qué mereció tu atención hoy?',
      '¿Qué necesitas soltar para dormir en paz?',
      '¿Dónde fuiste fuerte hoy, incluso sin darte cuenta?',
      '¿Qué conversación no ocurrió hoy?',
      '¿Qué costó y qué valió la pena?',
      '¿Qué emoción dominó tu día?',
      '¿Qué patrón se repitió una vez más?',
      '¿Te hubiera gustado caminar más despacio o más rápido?',
      '¿Qué descubriste sobre ti mismo en las últimas horas?',
      '¿Dónde fuiste más humano hoy?',
      '¿Qué pequeña cosa fue importante y casi pasó desapercibida?',
      '¿Terminaste el día como querías empezarlo?',
      '¿Qué merece ser llevado para mañana?',
      '¿A quién necesitas perdonar antes de dormir, incluyéndote?',
      '¿Qué no hiciste por miedo?',
      '¿Qué gesto tuyo de hoy hará eco?',
      'Si pudieras rehacer 10 minutos del día, ¿cuáles serían?',
    ];
    if (_l == 'de') return const [
      'Was hast du heute aufgeschoben, was du nicht hättest aufschieben sollen?',
      'In welchem Moment des heutigen Tages warst du, wer du sein willst?',
      'Wenn heute ein Satz wäre, welcher wäre es?',
      'Was hat heute deine Aufmerksamkeit verdient?',
      'Was musst du loslassen, um in Frieden zu schlafen?',
      'Wo warst du heute stark, ohne es zu merken?',
      'Welches Gespräch hat heute nicht stattgefunden?',
      'Was hat dich gekostet und was war es wert?',
      'Welche Emotion hat deinen Tag beherrscht?',
      'Welches Muster hat sich erneut wiederholt?',
      'Wärst du gerne langsamer oder schneller gegangen?',
      'Was hast du in den letzten Stunden über dich selbst entdeckt?',
      'Wo warst du heute am menschlichsten?',
      'Welche kleine Sache war wichtig und wurde fast übersehen?',
      'Hast du den Tag so beendet, wie du ihn beginnen wolltest?',
      'Was verdient es, in den morgigen Tag mitgenommen zu werden?',
      'Wem musst du vor dem Schlafengehen vergeben, dich selbst eingeschlossen?',
      'Was hast du aus Angst nicht getan?',
      'Welche deiner heutigen Gesten wird widerhallen?',
      'Wenn du 10 Minuten des Tages wiederholen könntest, welche wären es?',
    ];
    return const [
      'O que você adiou hoje que não deveria?',
      'Em qual momento de hoje você foi quem você quer ser?',
      'Se hoje fosse uma frase, qual seria?',
      'O que mereceu sua atenção hoje?',
      'O que você precisa soltar para dormir em paz?',
      'Onde você foi forte hoje, mesmo sem perceber?',
      'Qual conversa não aconteceu hoje?',
      'O que custou e o que valeu?',
      'Qual emoção dominou o seu dia?',
      'Que padrão se repetiu mais uma vez?',
      'Você gostaria de ter andado mais devagar ou mais rápido?',
      'O que você descobriu sobre si mesmo nas últimas horas?',
      'Onde você foi mais humano hoje?',
      'Que pequena coisa foi importante e quase passou despercebida?',
      'Você terminou o dia como queria começá-lo?',
      'O que merece ser carregado para amanhã?',
      'Quem você precisa perdoar antes de dormir, incluindo você?',
      'O que você não fez por medo?',
      'Qual gesto seu hoje vai ecoar?',
      'Se você pudesse refazer 10 minutos do dia, quais seriam?',
    ];
  }

  // Frases das notificações do Jardim (uma por momento)
  static String get notifJardimManha => _g(
    'Sua pergunta da manhã chegou no Jardim.',
    'Your morning question has arrived in the Garden.',
    'Tu pregunta de la mañana llegó al Jardín.',
    'Deine Morgenfrage ist im Garten angekommen.',
  );
  static String get notifJardimTarde => _g(
    'Sua pergunta da tarde te espera no Jardim.',
    'Your afternoon question awaits in the Garden.',
    'Tu pregunta de la tarde te espera en el Jardín.',
    'Deine Nachmittagsfrage wartet im Garten.',
  );
  static String get notifJardimNoite => _g(
    'Sua pergunta da noite chegou. Reflexão antes de dormir.',
    'Your night question has arrived. Reflection before sleep.',
    'Tu pregunta de la noche llegó. Reflexión antes de dormir.',
    'Deine Abendfrage ist da. Reflexion vor dem Schlafen.',
  );

  // ── FRASES DAS NOTIFICAÇÕES DIÁRIAS (30 por idioma) ─────────────────────────
  static List<String> get frasesNotificacao {
    if (_l == 'en') return const [
      'Return to the center. The stones wait.',
      'Small step, every day. It is time.',
      'The rhythm is built now.',
      'Discipline is decision, not mood. Today is today.',
      'Five minutes can change the shape of the day.',
      'Your practice waits. Without rush, without excuse.',
      'Today you choose who you are becoming.',
      'The path does not demand force. It demands rhythm.',
      'Return to the body. Return to now.',
      'Practice. The rest adjusts itself.',
      'It is not today that defines. It is today that builds.',
      'You promised yourself. Keep it.',
      'The practice you delay also delays you.',
      'Five minutes without noise. Begin.',
      'Who you want to be begins now.',
      'Do not wait to feel ready. Do.',
      'The temple is built one stone at a time.',
      'Today, choose presence over haste.',
      'Small gesture, long walk.',
      'Practice is the way. Not the destination.',
      'Feel the weight of the decision. Then decide.',
      'Return. As if for the first time.',
      'What you cultivate today, you harvest tomorrow.',
      'Silence. Before anything else.',
      'You know what you need to do. Do it.',
      'Simple movement, a whole life.',
      'Honor the commitment you made to yourself.',
      'Now. Not soon. Not later. Now.',
      'Consistency heals. Intensity tires.',
      'Your practice is your silent prayer.',
    ];
    if (_l == 'es') return const [
      'Vuelve al centro. Las piedras esperan.',
      'Pequeño paso, todos los días. Es la hora.',
      'El ritmo se construye ahora.',
      'Disciplina es decisión, no ánimo. Hoy es hoy.',
      'Cinco minutos pueden cambiar la forma del día.',
      'Tu práctica espera. Sin prisa, sin excusa.',
      'Hoy eliges en quién te estás convirtiendo.',
      'El camino no exige fuerza. Exige ritmo.',
      'Vuelve al cuerpo. Vuelve al ahora.',
      'Practica. Lo demás se ajusta.',
      'No es hoy lo que define. Es hoy lo que construye.',
      'Te lo prometiste. Cúmplelo.',
      'La práctica que aplazas también te aplaza.',
      'Cinco minutos sin ruido. Comienza.',
      'Quien quieres ser empieza ahora.',
      'No esperes a sentirte listo. Hazlo.',
      'El templo se construye una piedra a la vez.',
      'Hoy, elige presencia en lugar de prisa.',
      'Pequeño gesto, larga caminata.',
      'La práctica es el camino. No el destino.',
      'Siente el peso de la decisión. Después, decide.',
      'Vuelve. Como si fuera la primera vez.',
      'Lo que cultivas hoy, cosechas mañana.',
      'Silencio. Antes de cualquier otra cosa.',
      'Sabes lo que tienes que hacer. Hazlo.',
      'Movimiento simple, vida entera.',
      'Honra el compromiso que hiciste contigo.',
      'Ahora. No pronto. No después. Ahora.',
      'La consistencia cura. La intensidad cansa.',
      'Tu práctica es tu oración silenciosa.',
    ];
    if (_l == 'de') return const [
      'Kehre zur Mitte zurück. Die Steine warten.',
      'Kleiner Schritt, jeden Tag. Es ist Zeit.',
      'Der Rhythmus entsteht jetzt.',
      'Disziplin ist Entscheidung, nicht Stimmung. Heute ist heute.',
      'Fünf Minuten können die Form des Tages verändern.',
      'Deine Übung wartet. Ohne Eile, ohne Ausrede.',
      'Heute wählst du, wer du wirst.',
      'Der Weg verlangt keine Kraft. Er verlangt Rhythmus.',
      'Kehre zum Körper zurück. Kehre zum Jetzt zurück.',
      'Übe. Der Rest passt sich an.',
      'Es ist nicht heute, das definiert. Es ist heute, das aufbaut.',
      'Du hast es dir versprochen. Halte es.',
      'Die Übung, die du aufschiebst, schiebt dich auch auf.',
      'Fünf Minuten ohne Lärm. Beginne.',
      'Wer du sein willst, beginnt jetzt.',
      'Warte nicht, bis du dich bereit fühlst. Mache.',
      'Der Tempel wird Stein für Stein gebaut.',
      'Heute, wähle Präsenz statt Hast.',
      'Kleine Geste, langer Weg.',
      'Die Übung ist der Weg. Nicht das Ziel.',
      'Spüre das Gewicht der Entscheidung. Dann entscheide.',
      'Kehre zurück. Wie beim ersten Mal.',
      'Was du heute pflegst, erntest du morgen.',
      'Stille. Vor allem anderen.',
      'Du weißt, was du tun musst. Tu es.',
      'Einfache Bewegung, ein ganzes Leben.',
      'Ehre die Verpflichtung, die du dir gegeben hast.',
      'Jetzt. Nicht bald. Nicht später. Jetzt.',
      'Beständigkeit heilt. Intensität ermüdet.',
      'Deine Übung ist dein stilles Gebet.',
    ];
    // Português padrão
    return const [
      'Volte ao centro. As pedras esperam.',
      'Pequeno passo, todos os dias. É hora.',
      'O ritmo se constrói agora.',
      'Disciplina é decisão, não ânimo. Hoje é hoje.',
      'Cinco minutos podem mudar a forma do dia.',
      'Sua prática espera. Sem pressa, sem desculpa.',
      'Hoje você escolhe quem está se tornando.',
      'O caminho não exige força. Exige ritmo.',
      'Volte ao corpo. Volte ao agora.',
      'Pratique. O resto se ajusta.',
      'Não é hoje que define. É hoje que constrói.',
      'Você prometeu a si mesmo. Cumpra.',
      'A prática que você adia, te adia também.',
      'Cinco minutos sem barulho. Comece.',
      'Quem você quer ser começa agora.',
      'Não espere se sentir pronto. Faça.',
      'O templo se constrói uma pedra de cada vez.',
      'Hoje, escolha presença em vez de pressa.',
      'Pequeno gesto, longa caminhada.',
      'A prática é o caminho. Não o destino.',
      'Sinta o peso da decisão. Depois, decida.',
      'Volte. Como se fosse a primeira vez.',
      'O que você cultiva hoje, colhe amanhã.',
      'Silêncio. Antes de qualquer outra coisa.',
      'Você sabe o que precisa fazer. Faça.',
      'Movimento simples, vida inteira.',
      'Honre o compromisso que fez consigo.',
      'Agora. Não em breve. Não depois. Agora.',
      'A consistência cura. A intensidade cansa.',
      'Sua prática é sua oração silenciosa.',
    ];
  }

  // ── BIBLIOTECA DE PRÁTICAS PRÉ-DEFINIDAS ────────────────────────────────────
  // Chaves de categoria são enums ASCII estáveis (mind/body/discipline/
  // relations/work) — salvas no banco em `praticas.categoria`. A exibição
  // passa por `T.catMente/...` em dojo.dart, que aceita também as chaves
  // antigas em PT para não quebrar dados existentes.
  //
  // Ordem de iteração das chaves é estável (Dart preserva insertion order),
  // então a UI mostra sempre Mente → Corpo → Disciplina → Relações → Trabalho.
  static const String catKeyMente      = 'mind';
  static const String catKeyCorpo      = 'body';
  static const String catKeyDisciplina = 'discipline';
  static const String catKeyRelacoes   = 'relations';
  static const String catKeyTrabalho   = 'work';

  /// Retorna o nome traduzido da categoria a partir de QUALQUER chave —
  /// nova (enum ASCII) ou antiga (PT). Fallback: devolve a chave como veio
  /// (útil pra categorias personalizadas que o usuário criou).
  static String nomeCategoria(String chave) {
    switch (chave) {
      case catKeyMente:
      case 'Mente':
        return catMente;
      case catKeyCorpo:
      case 'Corpo':
        return catCorpo;
      case catKeyDisciplina:
      case 'Disciplina':
        return catDisciplina;
      case catKeyRelacoes:
      case 'Relações':
        return catRelacoes;
      case catKeyTrabalho:
      case 'Trabalho':
        return catTrabalho;
      default:
        return chave;
    }
  }

  static Map<String, List<Map<String, String>>> get bibliotecaPraticas {
    if (_l == 'en') return const {
      catKeyMente: [
        {'nome': '5 minutes of silence', 'duracao': '5 min'},
        {'nome': 'Reading', 'duracao': '20 min'},
        {'nome': 'Calligraphy', 'duracao': '15 min'},
        {'nome': 'Journaling 3 questions', 'duracao': '10 min'},
        {'nome': 'Cold shower', 'duracao': '3 min'},
      ],
      catKeyCorpo: [
        {'nome': 'Workout', 'duracao': '45 min'},
        {'nome': 'Mobility', 'duracao': '15 min'},
        {'nome': 'Walk', 'duracao': '30 min'},
        {'nome': '100 push-ups', 'duracao': '—'},
        {'nome': 'Stretching', 'duracao': '10 min'},
      ],
      catKeyDisciplina: [
        {'nome': 'Wake before 6am', 'duracao': '—'},
        {'nome': 'No screens in the first hour', 'duracao': '60 min'},
        {'nome': 'Limited eating window', 'duracao': '—'},
        {'nome': 'No social media until noon', 'duracao': '—'},
      ],
      catKeyRelacoes: [
        {'nome': 'Genuine message to someone', 'duracao': '—'},
        {'nome': 'Call to family', 'duracao': '15 min'},
        {'nome': 'Time without phone', 'duracao': '60 min'},
      ],
      catKeyTrabalho: [
        {'nome': '2h of deep focus', 'duracao': '120 min'},
        {'nome': 'Inbox zero', 'duracao': '—'},
        {'nome': 'Weekly review', 'duracao': '30 min'},
        {'nome': '1 learning action', 'duracao': '—'},
      ],
    };
    if (_l == 'es') return const {
      catKeyMente: [
        {'nome': '5 minutos de silencio', 'duracao': '5 min'},
        {'nome': 'Lectura', 'duracao': '20 min'},
        {'nome': 'Caligrafía', 'duracao': '15 min'},
        {'nome': 'Journaling de 3 preguntas', 'duracao': '10 min'},
        {'nome': 'Ducha fría', 'duracao': '3 min'},
      ],
      catKeyCorpo: [
        {'nome': 'Entrenamiento', 'duracao': '45 min'},
        {'nome': 'Movilidad', 'duracao': '15 min'},
        {'nome': 'Caminata', 'duracao': '30 min'},
        {'nome': '100 flexiones', 'duracao': '—'},
        {'nome': 'Estiramiento', 'duracao': '10 min'},
      ],
      catKeyDisciplina: [
        {'nome': 'Despertar antes de las 6h', 'duracao': '—'},
        {'nome': 'Sin pantallas en la primera hora', 'duracao': '60 min'},
        {'nome': 'Ventana de comida limitada', 'duracao': '—'},
        {'nome': 'Sin redes sociales hasta el mediodía', 'duracao': '—'},
      ],
      catKeyRelacoes: [
        {'nome': 'Mensaje genuino a alguien', 'duracao': '—'},
        {'nome': 'Llamada a la familia', 'duracao': '15 min'},
        {'nome': 'Tiempo sin teléfono', 'duracao': '60 min'},
      ],
      catKeyTrabalho: [
        {'nome': '2h de foco profundo', 'duracao': '120 min'},
        {'nome': 'Inbox zero', 'duracao': '—'},
        {'nome': 'Revisión semanal', 'duracao': '30 min'},
        {'nome': '1 acción de aprendizaje', 'duracao': '—'},
      ],
    };
    if (_l == 'de') return const {
      catKeyMente: [
        {'nome': '5 Minuten Stille', 'duracao': '5 min'},
        {'nome': 'Lesen', 'duracao': '20 min'},
        {'nome': 'Kalligraphie', 'duracao': '15 min'},
        {'nome': 'Journaling mit 3 Fragen', 'duracao': '10 min'},
        {'nome': 'Kalte Dusche', 'duracao': '3 min'},
      ],
      catKeyCorpo: [
        {'nome': 'Training', 'duracao': '45 min'},
        {'nome': 'Mobilität', 'duracao': '15 min'},
        {'nome': 'Spaziergang', 'duracao': '30 min'},
        {'nome': '100 Liegestütze', 'duracao': '—'},
        {'nome': 'Dehnen', 'duracao': '10 min'},
      ],
      catKeyDisciplina: [
        {'nome': 'Vor 6 Uhr aufstehen', 'duracao': '—'},
        {'nome': 'Keine Bildschirme in der ersten Stunde', 'duracao': '60 min'},
        {'nome': 'Begrenztes Essensfenster', 'duracao': '—'},
        {'nome': 'Kein Social Media bis Mittag', 'duracao': '—'},
      ],
      catKeyRelacoes: [
        {'nome': 'Aufrichtige Nachricht an jemanden', 'duracao': '—'},
        {'nome': 'Anruf bei der Familie', 'duracao': '15 min'},
        {'nome': 'Zeit ohne Handy', 'duracao': '60 min'},
      ],
      catKeyTrabalho: [
        {'nome': '2h tiefe Konzentration', 'duracao': '120 min'},
        {'nome': 'Inbox zero', 'duracao': '—'},
        {'nome': 'Wöchentlicher Review', 'duracao': '30 min'},
        {'nome': '1 Lernaktion', 'duracao': '—'},
      ],
    };
    // Português padrão
    return const {
      catKeyMente: [
        {'nome': '5 minutos de silêncio', 'duracao': '5 min'},
        {'nome': 'Leitura', 'duracao': '20 min'},
        {'nome': 'Caligrafia', 'duracao': '15 min'},
        {'nome': 'Journaling de 3 perguntas', 'duracao': '10 min'},
        {'nome': 'Banho frio', 'duracao': '3 min'},
      ],
      catKeyCorpo: [
        {'nome': 'Treino', 'duracao': '45 min'},
        {'nome': 'Mobilidade', 'duracao': '15 min'},
        {'nome': 'Caminhada', 'duracao': '30 min'},
        {'nome': '100 flexões', 'duracao': '—'},
        {'nome': 'Alongamento', 'duracao': '10 min'},
      ],
      catKeyDisciplina: [
        {'nome': 'Acordar antes das 6h', 'duracao': '—'},
        {'nome': 'Sem telas na primeira hora', 'duracao': '60 min'},
        {'nome': 'Janela de comida limitada', 'duracao': '—'},
        {'nome': 'Sem rede social até meio-dia', 'duracao': '—'},
      ],
      catKeyRelacoes: [
        {'nome': 'Mensagem genuína para alguém', 'duracao': '—'},
        {'nome': 'Ligação para família', 'duracao': '15 min'},
        {'nome': 'Tempo sem celular', 'duracao': '60 min'},
      ],
      catKeyTrabalho: [
        {'nome': '2h de foco profundo', 'duracao': '120 min'},
        {'nome': 'Inbox zero', 'duracao': '—'},
        {'nome': 'Review semanal', 'duracao': '30 min'},
        {'nome': '1 ação de aprendizado', 'duracao': '—'},
      ],
    };
  }

  // ── ESPERA DA CARTA (Biblioteca refresh) ───────────────────────────────────
  static List<String> get frasesEspera {
    if (_l == 'en') return [
      'This week\'s letter is already yours. The next one comes Sunday at 9pm.',
      'Wait. The next letter has its own Sunday.',
      'Your letter is already in your hand. Come back on Sunday.',
      'The Mentor\'s next words will come when Sunday arrives.',
      'Everything in its time. Sunday, 9pm.',
      'You already have it. Cultivate the week. The next letter waits for Sunday.',
    ];
    if (_l == 'es') return [
      'La carta de esta semana ya es tuya. La próxima viene el domingo a las 21h.',
      'Espera. La próxima carta tiene su propio domingo.',
      'Tu carta ya está en tu mano. Vuelve el domingo.',
      'La próxima palabra del Mentor llegará cuando llegue el domingo.',
      'Todo a su tiempo. Domingo, 21h.',
      'Ya la tienes. Cultiva la semana. La próxima carta espera al domingo.',
    ];
    if (_l == 'de') return [
      'Der Brief dieser Woche gehört bereits dir. Der nächste kommt am Sonntag um 21 Uhr.',
      'Warte. Der nächste Brief hat seinen eigenen Sonntag.',
      'Dein Brief ist bereits in deiner Hand. Komm am Sonntag wieder.',
      'Die nächsten Worte des Mentors kommen, wenn der Sonntag kommt.',
      'Alles zu seiner Zeit. Sonntag, 21 Uhr.',
      'Du hast ihn bereits. Kultiviere die Woche. Der nächste Brief wartet auf den Sonntag.',
    ];
    return const [
      'A carta desta semana já é sua. A próxima vem no próximo domingo, 21h.',
      'Espere. A próxima carta tem seu próprio domingo.',
      'Sua carta já está em sua mão. Volte no domingo.',
      'A próxima palavra do Mentor virá quando o domingo chegar.',
      'Tudo no seu tempo. Domingo, 21h.',
      'Você já a tem. Cultive a semana. A próxima carta espera o domingo.',
    ];
  }
}
