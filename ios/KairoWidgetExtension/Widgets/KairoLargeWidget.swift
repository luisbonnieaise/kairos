// KairoLargeWidget.swift — Home Screen 4x4 (systemLarge).
// 3 zonas verticais separadas por hairlines de 1pt. Cada zona é tocável:
//   A → /mentor   B → /practices   C → /progress
// Link por zona requer iOS 17+; em iOS 16 o widgetURL(/today) cobre o toque.

import WidgetKit
import SwiftUI

struct KairoLargeView: View {
    let entry: KairoEntry

    var body: some View {
        Group {
            if entry.data.isEmpty {
                KairoEmptyState(simbolo: 26)
            } else {
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: 0) {
                        // Zona A — Frase do dia (40%)
                        zonaTocavel(KairoDeepLink.mentor) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .top) {
                                    KairoSymbol(size: 12)
                                    Spacer()
                                    StalenessDot(stale: entry.data.isStale)
                                }
                                Spacer(minLength: 8)
                                PhraseView(phrase: entry.data.phrase, font: KairoTypography.bodyL, lines: 4)
                                Spacer(minLength: 0)
                            }
                            .frame(height: geo.size.height * 0.40, alignment: .topLeading)
                        }

                        KairoHairline()

                        // Zona B — Próxima prática (30%)
                        zonaTocavel(KairoDeepLink.practices) {
                            NextPracticeView(title: entry.data.nextPracticeTitle, time: entry.data.nextPracticeTime)
                                .frame(height: geo.size.height * 0.30 - 1, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        KairoHairline()

                        // Zona C — Streak silencioso (30%) + 回路 no canto inferior-direito
                        zonaTocavel(KairoDeepLink.progress) {
                            HStack(alignment: .bottom) {
                                StreakView(streak: entry.data.streakCount)
                                Spacer()
                                KairoSymbol(size: 14)
                            }
                            .frame(height: geo.size.height * 0.30 - 1, alignment: .bottomLeading)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(KairoBrand.paddingGrande)
        .kairoBackground()
        .widgetURL(KairoDeepLink.today) // fallback único (iOS 16)
    }

    // Link por zona (iOS 17+); em iOS 16 cai no widgetURL global.
    @ViewBuilder
    private func zonaTocavel<Content: View>(_ url: URL, @ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 17.0, *) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }
}

struct KairoLargeWidget: Widget {
    let kind = "KairoLargeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KairoTimelineProvider()) { entry in
            KairoLargeView(entry: entry)
        }
        .configurationDisplayName("Kairo — Painel")
        .description("Frase, próxima prática e consistência.")
        .supportedFamilies([.systemLarge])
    }
}
