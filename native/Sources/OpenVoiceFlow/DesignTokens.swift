import SwiftUI

/// Design tokens from the Claude Design system (native/design/*.dc.html).
/// One source of truth for every surface: HUD, menu bar, dashboard, onboarding.
enum DT {
    // MARK: accents (identical in both themes unless noted)
    static let emberDark = Color(hex: 0xE8974E)   // accent on dark surfaces
    static let emberLight = Color(hex: 0xB4661F)  // accent on light surfaces (4.6:1)
    static let emberWave = Color(hex: 0xC97B35)   // brand/active mid-tone
    static let moss = Color(hex: 0x7FAF8A)        // success / PRIVATE badges (dark)
    static let mossLight = Color(hex: 0x4E7A58)
    static let errorAccent = Color(hex: 0xE0523A) // HUD error accent
    static let warnAmber = Color(hex: 0xD99A3D)   // max-duration countdown
    static let destructive = Color(hex: 0xC7402C)

    // MARK: HUD-local inks
    static let hudMsgDark = Color(hex: 0xEAE6DD)
    static let hudMsgLight = Color(hex: 0x26221B)
    static let hudSideDark = Color(hex: 0x96907F)
    static let hudSideLight = Color(hex: 0x847D6E)
    static let dimWaveDark = Color(red: 214/255, green: 208/255, blue: 194/255).opacity(0.5)
    static let dimWaveLight = Color(red: 58/255, green: 52/255, blue: 40/255).opacity(0.45)
    static let chipInkDark = Color(hex: 0xCFC9BB)
    static let chipInkLight = Color(hex: 0x4A4437)

    // MARK: dashboard/window surfaces
    static let winDark = Color(hex: 0x1D1B18)
    static let winLight = Color(hex: 0xFCFBF8)
    static let sideDark = Color(hex: 0x191714)
    static let sideLight = Color(hex: 0xF4F2EC)
    static let cardDark = Color(hex: 0x211F1B)
    static let cardLight = Color.white
    static let inkDark = Color(hex: 0xEAE6DD)
    static let inkLight = Color(hex: 0x26221B)
    static let ink2Dark = Color(hex: 0x96907F)
    static let ink2Light = Color(hex: 0x847D6E)

    // MARK: radii (design "Radii: 6 control · 10 card · 16 window · capsule h/2")
    static let rControl: CGFloat = 6
    static let rCard: CGFloat = 12
    static let rWindow: CGFloat = 14

    // MARK: springs — snap(.25,.90) · arrive(.30,.85) · settle(.45,1.0)
    static let snap = Animation.spring(response: 0.25, dampingFraction: 0.90)
    static let arrive = Animation.spring(response: 0.30, dampingFraction: 0.85)
    static let settle = Animation.spring(response: 0.45, dampingFraction: 1.0)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The shared waveform math, verbatim from the design files. Every animated
/// line in the product goes through these three functions.
enum Voiceline {
    /// Synthetic speech envelope S(t): composite sines with a silence gate.
    static func envelope(_ t: Double) -> Double {
        let gate: Double = (sin(t * 0.9) + sin(t * 0.53 + 1.2)) > 0.9 ? 0.06 : 1
        var v = (sin(t * 2.3) + sin(t * 3.85 + 1.4) + sin(t * 5.9 + 0.4)) / 3
        v = max(0, v * 0.75 + 0.5)
        return min(1, v * gate)
    }

    /// Edge-taper window win(u) = sin(πu)^0.85.
    static func window(_ u: Double) -> Double {
        pow(max(0, sin(.pi * u)), 0.85)
    }

    /// Per-x wobble term: a·h·0.30·(three summed sines).
    static func wobble(x: Double, t: Double, amp: Double, height: Double) -> Double {
        amp * height * 0.30 * (
            sin(x * 0.052 + t * 6.6) * 0.55 +
            sin(x * 0.117 - t * 9.4) * 0.26 +
            sin(x * 0.026 + t * 3.2) * 0.42
        )
    }
}
