import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'i18n.dart';

class KairoNotificacoes {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inicializado = false;

  // IDs dos canais Android. Centralizados para serem usados pelos
  // `AndroidNotificationDetails` e pela rotina de recriação ao trocar idioma.
  static const _canalLembreteId = 'kairo_pratica';
  static const _canalCartaId    = 'kairo_carta';
  static const _canalJardimId   = 'kairo_jardim';

  // Frases curtas do Mentor (vem do i18n no idioma atual)
  static String _fraseAleatoria() {
    final frases = T.frasesNotificacao;
    return frases[math.Random().nextInt(frases.length)];
  }

  static Future<void> inicializar() async {
    if (_inicializado) return;

    tz.initializeTimeZones();
    // Define o timezone local (sem isso, todas as notificações disparam em UTC)
    try {
      final nomeFuso = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(nomeFuso));
    } catch (e) {
      debugPrint('Erro ao detectar timezone: $e — usando UTC');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Garante que os canais existam com nomes no idioma atual. Ao trocar
    // idioma o listener abaixo recria os canais para refletir a mudança no
    // painel de Configurações do Android.
    await _recriarCanais();
    T.idiomaNotifier.addListener(_aoTrocarIdioma);

    _inicializado = true;
  }

  // Disparado pelo `T.idiomaNotifier` quando o usuário troca de idioma.
  // O ValueNotifier não aceita listener async, então delegamos ao future.
  static void _aoTrocarIdioma() {
    _recriarCanais();
  }

  /// Recria os três canais Android com nomes/descrições no idioma atual.
  /// Necessário porque o Android FIXA nome/descrição na primeira criação —
  /// trocar idioma exige deletar e recriar. iOS não tem channel; no-op.
  static Future<void> _recriarCanais() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return; // iOS, web ou desktop

    Future<void> recriar(String id, String nome, String desc) async {
      // Falhas individuais (canal não existia, etc.) não devem quebrar o app.
      try { await android.deleteNotificationChannel(id); } catch (_) {}
      await android.createNotificationChannel(AndroidNotificationChannel(
        id, nome,
        description: desc,
        importance: Importance.high,
      ));
    }

    await recriar(_canalLembreteId, T.canalLembreteNome, T.canalLembreteDesc);
    await recriar(_canalCartaId,    T.canalCartaNome,    T.canalCartaDesc);
    await recriar(_canalJardimId,   T.canalJardimNome,   T.canalJardimDesc);
  }

  // Helper para AndroidNotificationDetails dinâmico (não pode ser `const`
  // porque depende do idioma atual). Cria-se um por chamada — é barato.
  static AndroidNotificationDetails _detalhesLembrete() => AndroidNotificationDetails(
    _canalLembreteId,
    T.canalLembreteNome,
    channelDescription: T.canalLembreteDesc,
    importance: Importance.high,
    priority: Priority.high,
  );

  static AndroidNotificationDetails _detalhesCarta() => AndroidNotificationDetails(
    _canalCartaId,
    T.canalCartaNome,
    channelDescription: T.canalCartaDesc,
    importance: Importance.high,
    priority: Priority.high,
  );

  static AndroidNotificationDetails _detalhesJardim() => AndroidNotificationDetails(
    _canalJardimId,
    T.canalJardimNome,
    channelDescription: T.canalJardimDesc,
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<bool> pedirPermissao() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<bool> temPermissao() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Agenda um lembrete diário no horário informado.
  /// Cancela o anterior antes de criar o novo.
  static Future<void> agendarLembreteDiario(int hora, int minuto) async {
    await inicializar();
    await cancelarLembrete();

    final agora = tz.TZDateTime.now(tz.local);
    var quando = tz.TZDateTime(
      tz.local,
      agora.year,
      agora.month,
      agora.day,
      hora,
      minuto,
    );

    // Se o horário já passou hoje, agenda pra amanhã
    if (quando.isBefore(agora)) {
      quando = quando.add(const Duration(days: 1));
    }

    final detalhes = NotificationDetails(
      android: _detalhesLembrete(),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      1, // id fixo pro lembrete de prática (futuras notifs usam outros ids)
      T.mentor,
      _fraseAleatoria(),
      quando,
      detalhes,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repete diariamente
    );
  }

  static Future<void> cancelarLembrete() async {
    await inicializar();
    await _plugin.cancel(1);
  }

  /// Agenda a carta semanal — todo domingo às 21:00.
  static Future<void> agendarCartaSemanal() async {
    await inicializar();
    await _plugin.cancel(2);

    final agora = tz.TZDateTime.now(tz.local);
    // domingo às 21:00. weekday: 1 = segunda ... 7 = domingo
    var quando = tz.TZDateTime(tz.local, agora.year, agora.month, agora.day, 21, 0);

    // Avança até o próximo domingo
    while (quando.weekday != DateTime.sunday || quando.isBefore(agora)) {
      quando = quando.add(const Duration(days: 1));
    }

    final detalhes = NotificationDetails(
      android: _detalhesCarta(),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      2,
      T.mentor,
      T.cartaDomingoChegou,
      quando,
      detalhes,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // toda semana
    );
  }

  static Future<void> cancelarCartaSemanal() async {
    await inicializar();
    await _plugin.cancel(2);
  }

  /// Agenda as 3 notificações do Jardim:
  /// - Manhã: 8:00
  /// - Tarde: 13:00
  /// - Noite: 20:00
  static Future<void> agendarJardim() async {
    await inicializar();
    await _plugin.cancel(3);
    await _plugin.cancel(4);
    await _plugin.cancel(5);

    await _agendarJardimMomento(3, 8, 0, T.notifJardimManha);
    await _agendarJardimMomento(4, 13, 0, T.notifJardimTarde);
    await _agendarJardimMomento(5, 20, 0, T.notifJardimNoite);
  }

  static Future<void> _agendarJardimMomento(
    int id,
    int hora,
    int minuto,
    String corpo,
  ) async {
    final agora = tz.TZDateTime.now(tz.local);
    var quando = tz.TZDateTime(
      tz.local, agora.year, agora.month, agora.day, hora, minuto,
    );
    if (quando.isBefore(agora)) {
      quando = quando.add(const Duration(days: 1));
    }

    final detalhes = NotificationDetails(
      android: _detalhesJardim(),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id,
      T.mentor,
      corpo,
      quando,
      detalhes,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repete diariamente
    );
  }

  static Future<void> cancelarJardim() async {
    await inicializar();
    await _plugin.cancel(3);
    await _plugin.cancel(4);
    await _plugin.cancel(5);
  }

  // ── MODO SILÊNCIO ─────────────────────────────────────────────────────────

  /// Cancela todas as notificações do Kairo enquanto o Modo Silêncio estiver ativo.
  /// IDs conhecidos: 1=lembrete diário, 2=carta semanal, 3-5=jardim.
  static Future<void> suspenderTodas() async {
    await inicializar();
    await _plugin.cancel(1);
    await _plugin.cancel(2);
    await _plugin.cancel(3);
    await _plugin.cancel(4);
    await _plugin.cancel(5);
  }

  /// Reativa todas as notificações que estavam configuradas pelo usuário.
  /// Deve ser chamada ao encerrar o Modo Silêncio.
  ///
  /// [horarioLembrete] — "HH:MM:SS" salvo no perfil; null = lembrete desativado.
  /// [notifJardim]     — flag do perfil; true = reagendar Jardim.
  static Future<void> restaurarTodas({
    required String? horarioLembrete,
    required bool notifJardim,
  }) async {
    await inicializar();

    // Carta semanal — sempre reagendar (não tem toggle de usuário)
    await agendarCartaSemanal();

    // Jardim — só se o usuário não desativou
    if (notifJardim) {
      await agendarJardim();
    }

    // Lembrete diário — só se o usuário configurou um horário
    if (horarioLembrete != null && horarioLembrete.isNotEmpty) {
      final partes = horarioLembrete.split(':');
      if (partes.length >= 2) {
        final hora   = int.tryParse(partes[0]) ?? 7;
        final minuto = int.tryParse(partes[1]) ?? 0;
        await agendarLembreteDiario(hora, minuto);
      }
    }
  }
}
