// KairoSharedViews.swift
// Peças reutilizadas pelos widgets. Sem ícones, sem botões, sem animação.

import SwiftUI
import WidgetKit

/// 回路 — âncora visual de todo widget.
struct KairoSymbol: View {
    var size: CGFloat = 12
    var body: some View {
        Text(KairoBrand.kairo)
            .font(.system(size: size, weight: .regular))
            .foregroundColor(KairoColors.kin)
    }
}

/// Ponto discreto de "dados não frescos" (> 24h). Só aparece quando defasado.
struct StalenessDot: View {
    let stale: Bool
    var body: some View {
        if stale {
            Text(KairoBrand.stoneBullet)
                .font(KairoTypography.micro)
                .foregroundColor(KairoColors.smoke)
        }
    }
}

/// Frase do dia (serif). `lines` limita as linhas; trunca com em-dash.
struct PhraseView: View {
    let phrase: String
    var font: Font = KairoTypography.bodyM
    var lines: Int = 4
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(phrase)
            .font(font)
            .foregroundColor(KairoColors.corpo(scheme))
            .lineLimit(lines)
            .truncationMode(.tail)
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Zona B — "Próxima prática".
struct NextPracticeView: View {
    let title: String
    let time: Date?
    @Environment(\.colorScheme) private var scheme

    private var horario: String? {
        guard let time else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: time)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRÓXIMA PRÁTICA")
                .font(KairoTypography.micro)
                .tracking(KairoBrand.espacamentoMicro)
                .foregroundColor(KairoColors.kin)
            if title.isEmpty {
                Text("—")
                    .font(KairoTypography.bodyM)
                    .foregroundColor(KairoColors.smoke)
            } else {
                Text(title)
                    .font(KairoTypography.bodyL)
                    .foregroundColor(KairoColors.corpo(scheme))
                    .lineLimit(1)
                if let horario {
                    Text(horario)
                        .font(KairoTypography.caption)
                        .foregroundColor(KairoColors.ash)
                }
            }
        }
    }
}

/// Zona C — streak silencioso: stones de pedra, sem alarde.
struct StreakView: View {
    let streak: Int

    var body: some View {
        let s = KairoFormat.stones(streak: streak)
        VStack(alignment: .leading, spacing: 8) {
            if streak <= 0 {
                Text("comece o ritmo")
                    .font(KairoTypography.micro)
                    .foregroundColor(KairoColors.smoke)
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<s.cheios, id: \.self) { _ in
                        Circle()
                            .fill(KairoColors.kin)
                            .frame(width: KairoBrand.stoneDiametro, height: KairoBrand.stoneDiametro)
                    }
                    if s.overflow {
                        Text(KairoBrand.stoneBullet)
                            .font(KairoTypography.micro)
                            .foregroundColor(KairoColors.kin)
                    }
                }
                Text("consistência")
                    .font(KairoTypography.stone9)
                    .foregroundColor(KairoColors.smoke)
            }
        }
    }
}

/// Estado vazio (fresh install): 回路 centralizado + "Kairo".
struct KairoEmptyState: View {
    var simbolo: CGFloat = 22
    var body: some View {
        VStack(spacing: 8) {
            KairoSymbol(size: simbolo)
            Text("Kairo")
                .font(KairoTypography.caption)
                .foregroundColor(KairoColors.ash)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hairline de 1pt (#DCD8CF) — único divisor permitido.
struct KairoHairline: View {
    var body: some View {
        Rectangle()
            .fill(KairoColors.line)
            .frame(height: 1)
    }
}

/// Aplica o fundo do widget respeitando o esquema (default escuro).
struct KairoBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { KairoColors.fundo(scheme) }
    }
}

extension View {
    func kairoBackground() -> some View { modifier(KairoBackground()) }
}
