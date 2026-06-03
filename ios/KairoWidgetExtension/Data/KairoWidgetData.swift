// KairoWidgetData.swift
// Modelo + leitura do App Group + lógica pura de truncamento e streak.
// A verdade é escrita pelo app principal (ver KairoWidgetBridge no Runner).

import Foundation

struct KairoWidgetData {
    var phrase: String
    var nextPracticeTitle: String
    var nextPracticeTime: Date?
    var streakCount: Int
    var lastUpdated: Date?

    /// Sem nenhum dado útil ainda (fresh install) → estado "回路 + Kairo".
    var isEmpty: Bool { phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Dados defasados (> 24h) → mostrar ponto discreto de "não fresco".
    var isStale: Bool {
        guard let last = lastUpdated else { return false }
        return Date().timeIntervalSince(last) > 24 * 60 * 60
    }

    static let vazio = KairoWidgetData(
        phrase: "", nextPracticeTitle: "", nextPracticeTime: nil,
        streakCount: 0, lastUpdated: nil
    )
}

enum KairoStore {
    static let appGroup = "group.com.kairo.shared"

    static func ler() -> KairoWidgetData {
        guard let d = UserDefaults(suiteName: appGroup) else { return .vazio }
        let phrase = d.string(forKey: "phrase_today") ?? ""
        let title  = d.string(forKey: "next_practice_title") ?? ""
        let timeISO = d.string(forKey: "next_practice_time")
        let streak = d.integer(forKey: "streak_count")
        let updatedEpoch = d.double(forKey: "last_updated")

        var time: Date? = nil
        if let iso = timeISO, !iso.isEmpty {
            time = ISO8601DateFormatter().date(from: iso)
        }
        let updated: Date? = updatedEpoch > 0 ? Date(timeIntervalSince1970: updatedEpoch) : nil

        return KairoWidgetData(
            phrase: phrase, nextPracticeTitle: title, nextPracticeTime: time,
            streakCount: streak, lastUpdated: updated
        )
    }
}

// ── Lógica pura (espelhada em Dart/Kotlin e coberta por testes) ──────────────

enum KairoFormat {
    /// Trunca a frase com EM-DASH (nunca com "..."). Corta na borda de palavra
    /// quando possível para não cortar no meio de uma palavra.
    /// (Reconcilia a nota do inline com a regra global "never '...'": usamos —.)
    static func truncar(_ texto: String, max: Int) -> String {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limpo.count > max, max > 1 else { return limpo }
        let corte = limpo.prefix(max - 1)
        // recua até o último espaço para não partir uma palavra
        if let ultimoEspaco = corte.range(of: " ", options: .backwards) {
            let palavra = corte[..<ultimoEspaco.lowerBound]
            let semPontuacao = palavra.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
            if semPontuacao.count >= max / 2 {
                return semPontuacao + "—"
            }
        }
        return corte.trimmingCharacters(in: .whitespaces) + "—"
    }

    /// Quantos stones desenhar e se há overflow (> 7 → 6 stones + bullet).
    static func stones(streak: Int) -> (cheios: Int, overflow: Bool) {
        if streak <= 0 { return (0, false) }
        if streak <= KairoBrand.maxStones { return (streak, false) }
        return (KairoBrand.maxStones - 1, true) // 6 + "·"
    }
}
