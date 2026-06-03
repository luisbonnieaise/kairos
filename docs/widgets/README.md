# Widgets do Kairo — guia técnico

Widgets de tela inicial (iOS + Android) e tela bloqueada (iOS) para o Kairo.
Objetos silenciosos que o usuário possui — sem notificação, sem alarde, sem cor
fora da paleta. A âncora visual é sempre o selo **回路**.

## Mapa dos arquivos

```
ios/KairoWidgetExtension/
  DesignTokens/KairoTokens.swift        paleta, tipografia, marca, deep links
  Data/KairoWidgetData.swift            modelo + leitura do App Group + truncar/stones (puro)
  Providers/KairoTimelineProvider.swift timeline (entries de 1h)
  Views/KairoSharedViews.swift          peças: símbolo, frase, próxima prática, stones, vazio, hairline
  Widgets/KairoSmallWidget.swift        Home 2x2
  Widgets/KairoLargeWidget.swift        Home 4x4 (3 zonas tocáveis)
  Widgets/KairoLockWidgets.swift        Lock rectangular / inline / circular (iOS 16+)
  KairoWidgetBundle.swift               @main (lock só em iOS 16+)
  Info.plist, KairoWidgetExtension.entitlements

ios/Runner/
  KairoWidgetBridge.swift               lado iOS do MethodChannel('kairo.widget')
  Runner.entitlements                   App Group group.com.kairo.shared
  AppDelegate.swift                     registra a bridge

android/app/src/main/
  kotlin/com/example/kairo/widget/
    data/KairoWidgetData.kt             DataStore "kairo_widget" + truncar/stones (puro)
    providers/KairoWidgetProviders.kt   AppWidgetProvider Small/Large (RemoteViews)
    providers/KairoWidgetRefresh.kt     WorkManager horário + atualizar todos + cleanup
  kotlin/com/example/kairo/MainActivity.kt   lado Android do MethodChannel
  res/layout/kairo_widget_small.xml, kairo_widget_large.xml
  res/xml/kairo_widget_small_info.xml, kairo_widget_large_info.xml
  res/drawable/kairo_stone.xml
  res/values/colors_kairo.xml, res/values-night/colors_kairo.xml

lib/core/widget_bridge.dart             ponte Flutter (MethodChannel + lógica pura)
lib/main.dart                            hook de lifecycle (push ao ir p/ background)
test/widget_bridge_test.dart             testes da lógica pura (serialização/truncar/stones/vazio)
```

> **IDs reais do projeto** (a spec assumia `com.kairo`):
> iOS bundle `com.kairo.app` → extensão `com.kairo.app.KairoWidgetExtension`;
> Android `com.example.kairo`. App Group: `group.com.kairo.shared`.
> Deep links `kairo://today|mentor|practices|progress` já registrados em
> `Info.plist` e `AndroidManifest.xml` (roteados no Flutter via `app_links`).

---

## Setup iOS (passos MANUAIS no Xcode — não dá para automatizar via pbxproj)

O código Swift está pronto, mas a Widget Extension precisa de um **target** e da
**capability de App Group**, criados no Xcode:

1. `open ios/Runner.xcworkspace`.
2. **File → New → Target → Widget Extension**. Nome: `KairoWidgetExtension`.
   Desmarque "Include Configuration Intent" (usamos `StaticConfiguration`).
   Bundle id resultante: `com.kairo.app.KairoWidgetExtension`.
3. O Xcode cria uma pasta com arquivos de exemplo — **apague-os** e
   **adicione os arquivos de `ios/KairoWidgetExtension/`** (Add Files to…,
   marcando o target da extensão, NÃO o Runner). Use o Info.plist e o
   `.entitlements` desta pasta.
4. **Signing & Capabilities** → no target **Runner** e no target
   **KairoWidgetExtension**: **+ Capability → App Groups** → marque
   `group.com.kairo.shared` (crie-o no portal de provisioning se ainda não
   existir). Os `.entitlements` já apontam para esse grupo.
5. Garanta que `KairoWidgetBridge.swift` está no target **Runner** (a bridge
   roda no app, não na extensão).
6. Build no device. Adicione o widget pela galeria do iOS.

> iOS 15: o bundle não expõe os widgets de lock (guardados por
> `@available(iOS 16+)`), degradando graciosamente. Always-On (iOS 18): o
> sistema já reduz a opacidade dos widgets de lock automaticamente.

---

## Setup Android (já fiável via arquivos)

Nada manual além de `flutter pub get` / rebuild — manifest, gradle e recursos já
estão no repositório:

- Receivers registrados no `AndroidManifest.xml`.
- Dependências em `android/app/build.gradle.kts` (DataStore, WorkManager,
  coroutines).
- Funciona em Android 12+ **e** abaixo (RemoteViews é universal). Long-press na
  tela inicial → Widgets → Kairo.

### Por que RemoteViews e não Glance?

A spec pede Glance. Glance compila `@Composable`, exigindo o **compilador
Compose** no Gradle do host Flutter — sensível à versão do Kotlin e arriscado de
introduzir sem quebrar o build. RemoteViews entrega o mesmo design, cobre todas
as versões e não adiciona Compose. **Para migrar a Glance no futuro:** aplique
`org.jetbrains.kotlin.plugin.compose`, adicione
`androidx.glance:glance-appwidget`, e reescreva os providers como
`GlanceAppWidget` + `GlanceAppWidgetReceiver` reaproveitando `KairoWidgetData`
(a camada de dados e a lógica pura não mudam).

---

## Fluxo de dados

```
app Flutter  --MethodChannel('kairo.widget')-->  nativo
   WidgetBridge.enviar(...)                       iOS:  grava App Group UserDefaults + WidgetCenter.reloadAllTimelines()
                                                  Android: grava DataStore + sendBroadcast(APPWIDGET_UPDATE)
nativo lê o storage --> renderiza (TimelineProvider / AppWidgetProvider)
```

Chaves (iguais nos dois lados): `phrase_today`, `next_practice_title`,
`next_practice_time` (ISO8601 opcional), `streak_count`, `last_updated` (epoch).

### Refresh
- iOS: timeline reentrega a cada 1h (`getTimeline` `.after`).
- Android: `WorkManager` periódico de 1h (agendado em `onEnabled`, cancelado em
  `onDisabled` quando some o último widget — edge case 8).
- Imediato: o app chama `WidgetBridge.enviar(...)` (hoje no `paused` do
  lifecycle, em `lib/main.dart::atualizarWidgets`).

### Gatilhos de refresh (ligados)
A derivação dos dados é centralizada em `lib/core/widget_sync.dart`
(`WidgetSync.sincronizar()`), chamada em:
- **app → background** (`main.dart`, lifecycle `paused`);
- **completar/desmarcar prática** (`home.dart::_marcarHabito`);
- **criar/remover prática** (`dojo.dart`).

O **streak** é real: `BancoPraticas.streakDiario()` conta dias consecutivos com
≥1 prática concluída (função pura `streakConsecutivo` em `datas.dart`, coberta
por `test/datas_test.dart`). A **frase do dia** é rotativa e determinística:
`T.fraseDoDia()` escolhe do banco `T.frasesDoDia` por seed de data (mesmo
critério do Jardim) — igual no app e no widget, muda a cada dia, nos 4 idiomas
(coberta por `test/i18n_test.dart`). Para empurrar outros campos pontualmente,
use `WidgetBridge.enviar(...)` diretamente.

---

## Como adicionar um novo tamanho de widget

**iOS:** crie `Widgets/KairoXWidget.swift` com uma `View` + um `Widget`
(`StaticConfiguration` + `.supportedFamilies([...])`), reusando as subviews de
`KairoSharedViews`, e registre em `KairoWidgetBundle`.

**Android:** crie `res/layout/kairo_widget_x.xml` + `res/xml/..._info.xml`, um
`AppWidgetProvider` em `providers/` (reusando `KairoStore`/`KairoFormat`), e
registre o `<receiver>` no `AndroidManifest.xml`. Inclua-o em
`KairoWidgetRefresh.atualizarTodos` (lista de classes).

## Como adicionar um novo campo de dado

1. Acrescente a chave nos **três** lados: `KairoStore`/`KairoWidgetData` (Swift),
   `KairoKeys`/`KairoWidgetData` (Kotlin) e `WidgetBridge.montarPayload` (Dart).
2. Trate-o nos handlers das bridges (`KairoWidgetBridge.swift`,
   `MainActivity.kt`).
3. Renderize onde fizer sentido nas views/layouts.
4. Cubra com teste em `test/widget_bridge_test.dart` (e espelhe a lógica pura).

## Depurando refresh

- **iOS:** confirme que app e extensão compartilham o **mesmo App Group**
  (capability marcada nos dois targets). Cheque os valores em
  `UserDefaults(suiteName: "group.com.kairo.shared")`. Force reload chamando
  `WidgetBridge.recarregar()`. Logs do `WidgetCenter` no Console.app.
- **Android:** verifique que os `<receiver>` estão no manifest e que o
  DataStore "kairo_widget" recebeu os valores. `adb shell dumpsys appwidget`
  lista os widgets ativos. Logcat filtra `KairoWidget`.
- **Geral:** dados defasados (>24h) mostram um `·` discreto no canto — sinal de
  que o app não empurrou updates (verifique o gatilho de lifecycle).

## Regras de marca (não negociáveis)

Sem badges/pontos vermelhos, sem emojis (só 回路 e o bullet `·`), sem "!", sem
animação/pulsação, sem CTA, sem cor fora da paleta. Frase do Mentor em **serif**;
labels/metadados em **sans-serif**. Hairlines de **1pt** em `#DCD8CF`. Truncar
sempre com **em-dash** (nunca `...`). Padding mínimo 16pt (24pt no large).
