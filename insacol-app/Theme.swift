import SwiftUI

// MARK: - Hex color init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - UIColor adaptive helper

private extension UIColor {
    static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8)  & 0xFF) / 255
        let b = CGFloat( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Theme

enum Theme {
    // Brand — fixed in both modes
    static let amber     = Color(hex: "#FFC107")
    static let amberDark = Color(hex: "#F59E0B")
    static let navy      = Color(hex: "#0F172A")
    static let navyLight = Color(hex: "#1E293B")

    // Surfaces — adaptive
    static let surface = Color(UIColor.adaptive(
        light: UIColor(hex: "#FAFAF7"),
        dark:  UIColor(hex: "#0A0F1C")          // más oscuro que navy para que las cards resalten
    ))

    static let cardSurface = Color(UIColor.adaptive(
        light: .white,
        dark:  UIColor(hex: "#1E293B")           // navyLight
    ))

    static let cardBorder = Color(UIColor.adaptive(
        light: .black.withAlphaComponent(0.10),
        dark:  .white.withAlphaComponent(0.12)
    ))

    static let divider = Color(UIColor.adaptive(
        light: .black.withAlphaComponent(0.08),
        dark:  .white.withAlphaComponent(0.10)
    ))

    // Text — adaptive
    static let navyText = Color(UIColor.adaptive(
        light: UIColor(hex: "#0F172A"),
        dark:  UIColor(hex: "#F1F5F9")
    ))

    static let textMuted = Color(UIColor.adaptive(
        light: UIColor(hex: "#3C3C43").withAlphaComponent(0.60),
        dark:  .white.withAlphaComponent(0.50)
    ))

    // Status — mismos en ambos modos
    static let success = Color(hex: "#34C759")
    static let warning = Color(hex: "#F59E0B")
    static let danger  = Color(hex: "#FF3B30")
    static let info    = Color(hex: "#007AFF")

    // Gradients
    static let amberGradient = LinearGradient(
        colors: [amber, amberDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Glass card modifier (LoginView)

extension View {
    func glassCard() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
