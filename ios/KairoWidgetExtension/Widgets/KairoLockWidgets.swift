// KairoLockWidgets.swift — Lock Screen (iOS 16+).
// Rectangular / Inline / Circular. O sistema renderiza em modo monocromático
// (vibrant) — não lutamos contra isso: confiamos no glifo 回路 e na tipografia.
// O bundle só inclui estes widgets quando iOS >= 16 (ver KairoWidgetBundle).

import WidgetKit
import SwiftUI

// MARK: - Rectangular
@available(iOSApplicationExtension 16.0, *)
struct KairoLockRectangularView: View {
    let entry: KairoEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(KairoBrand.kairo).font(.system(size: 11, weight: .regular))
                Text("Kairo").font(.system(size: 11, weight: .semibold))
            }
            if !entry.data.isEmpty {
                Text(KairoFormat.truncar(entry.data.phrase, max: 60))
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
        .widgetURL(KairoDeepLink.today)
    }
}

@available(iOSApplicationExtension 16.0, *)
struct KairoLockRectangularWidget: Widget {
    let kind = "KairoLockRectangularWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KairoTimelineProvider()) { entry in
            KairoLockRectangularView(entry: entry)
        }
        .configurationDisplayName("Kairo — Frase")
        .description("Frase do dia na tela bloqueada.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Inline
@available(iOSApplicationExtension 16.0, *)
struct KairoLockInlineView: View {
    let entry: KairoEntry
    var body: some View {
        // 1 linha, máx. 32 chars; trunca com em-dash (regra global, nunca "...").
        Text(entry.data.isEmpty ? "回路 Kairo" : KairoFormat.truncar(entry.data.phrase, max: 32))
            .widgetURL(KairoDeepLink.today)
    }
}

@available(iOSApplicationExtension 16.0, *)
struct KairoLockInlineWidget: Widget {
    let kind = "KairoLockInlineWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KairoTimelineProvider()) { entry in
            KairoLockInlineView(entry: entry)
        }
        .configurationDisplayName("Kairo — Linha")
        .description("Frase do dia em uma linha.")
        .supportedFamilies([.accessoryInline])
    }
}

// MARK: - Circular
@available(iOSApplicationExtension 16.0, *)
struct KairoLockCircularView: View {
    let entry: KairoEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text(KairoBrand.kairo).font(.system(size: 16, weight: .regular))
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(KairoDeepLink.today)
    }
}

@available(iOSApplicationExtension 16.0, *)
struct KairoLockCircularWidget: Widget {
    let kind = "KairoLockCircularWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KairoTimelineProvider()) { entry in
            KairoLockCircularView(entry: entry)
        }
        .configurationDisplayName("Kairo — Selo")
        .description("O selo 回路 na tela bloqueada.")
        .supportedFamilies([.accessoryCircular])
    }
}
