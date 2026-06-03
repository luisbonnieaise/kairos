// KairoTimelineProvider.swift
// Lê o App Group e devolve uma timeline que se renova a cada 1h. O app
// principal força reload imediato (WidgetCenter.reloadAllTimelines) nos eventos
// relevantes — esta cadência horária é só a rede de segurança.

import WidgetKit
import SwiftUI

struct KairoEntry: TimelineEntry {
    let date: Date
    let data: KairoWidgetData
}

struct KairoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> KairoEntry {
        KairoEntry(date: Date(), data: .vazio)
    }

    func getSnapshot(in context: Context, completion: @escaping (KairoEntry) -> Void) {
        completion(KairoEntry(date: Date(), data: KairoStore.ler()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KairoEntry>) -> Void) {
        let agora = Date()
        let entry = KairoEntry(date: agora, data: KairoStore.ler())
        // Próxima atualização programada em 1h (reload imediato vem do app).
        let proxima = Calendar.current.date(byAdding: .hour, value: 1, to: agora) ?? agora.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(proxima)))
    }
}
