// KairoTokens.swift
// Paleta, tipografia e constantes de marca dos widgets do Kairo.
// Regra de ouro: NADA fora destes tokens. Sem cores vivas, sem ênfase, sem ruído.

import SwiftUI

enum KairoColors {
    static let sumi  = Color(red: 0.04, green: 0.04, blue: 0.04) // #0A0A0A
    static let washi = Color(red: 0.96, green: 0.95, blue: 0.93) // #F5F2EC
    static let kin   = Color(red: 0.61, green: 0.48, blue: 0.25) // #9C7A3F
    static let graph = Color(red: 0.16, green: 0.16, blue: 0.16) // #2A2A2A
    static let smoke = Color(red: 0.33, green: 0.33, blue: 0.33) // #555555
    static let ash   = Color(red: 0.54, green: 0.54, blue: 0.54) // #8A8A8A
    static let line  = Color(red: 0.86, green: 0.85, blue: 0.81) // #DCD8CF

    /// Fundo que respeita dark/light (default escuro — ver `Always`).
    static func fundo(_ scheme: ColorScheme) -> Color { scheme == .light ? washi : sumi }
    /// Cor de corpo (frase do Mentor) por esquema.
    static func corpo(_ scheme: ColorScheme) -> Color { scheme == .light ? sumi : washi }
}

enum KairoTypography {
    // Corpo (serif): New York no iOS como fallback de Söhne Breit.
    static let bodyL = Font.custom("NewYork-Regular", size: 16)
    static let bodyM = Font.custom("NewYork-Regular", size: 14)
    static let bodyS = Font.custom("NewYork-Regular", size: 12)
    // Display (sans-serif): SF Pro.
    static let micro   = Font.system(size: 10, weight: .medium, design: .default)
    static let caption = Font.system(size: 12, weight: .medium)
    static let stone9  = Font.system(size: 9, weight: .regular, design: .default)
}

enum KairoBrand {
    /// Âncora visual de TODO widget. Único caractere especial permitido (+ stones).
    static let kairo = "回路"
    /// Bullet de pedra para a inline / fallbacks textuais.
    static let stoneBullet = "·"

    static let espacamentoMicro: CGFloat = 1.5   // letter-spacing dos micro-labels
    static let padding: CGFloat = 16             // mínimo
    static let paddingGrande: CGFloat = 24       // preferido no large
    static let stoneDiametro: CGFloat = 4
    static let maxStones = 7
}

enum KairoDeepLink {
    static let today     = URL(string: "kairo://today")!
    static let mentor    = URL(string: "kairo://mentor")!
    static let practices = URL(string: "kairo://practices")!
    static let progress  = URL(string: "kairo://progress")!
}
