// KairoSmallWidget.swift — Home Screen 2x2 (systemSmall).
// 回路 no topo-esquerda + frase do dia (serif, até 4 linhas). Toque → /today.

import WidgetKit
import SwiftUI

struct KairoSmallView: View {
    let entry: KairoEntry

    var body: some View {
        Group {
            if entry.data.isEmpty {
                KairoEmptyState(simbolo: 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        KairoSymbol(size: 12)
                        Spacer()
                        StalenessDot(stale: entry.data.isStale)
                    }
                    PhraseView(phrase: entry.data.phrase, font: KairoTypography.bodyM, lines: 4)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(KairoBrand.padding)
        .kairoBackground()
        .widgetURL(KairoDeepLink.today)
    }
}

struct KairoSmallWidget: Widget {
    let kind = "KairoSmallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KairoTimelineProvider()) { entry in
            KairoSmallView(entry: entry)
        }
        .configurationDisplayName("Kairo — Frase do dia")
        .description("Uma frase do Mentor, em silêncio.")
        .supportedFamilies([.systemSmall])
    }
}
