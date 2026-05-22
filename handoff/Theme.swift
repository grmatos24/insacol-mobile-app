import SwiftUI

// MARK: - Brand colors

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

enum Theme {
    // Brand
    static let amber     = Color(hex: "#FFC107")
    static let amberDark = Color(hex: "#F59E0B")
    static let navy      = Color(hex: "#0F172A")
    static let navyLight = Color(hex: "#1E293B")

    // Surfaces (Field First — light)
    static let surface     = Color(hex: "#FAFAF7")  // fondo de pantalla
    static let cardSurface = Color.white            // fondo de card
    static let cardBorder  = Color.black.opacity(0.10)
    static let divider     = Color.black.opacity(0.08)

    // Text
    static let navyText  = Color(hex: "#0F172A")
    static let textMuted = Color(hex: "#3C3C43").opacity(0.6)

    // Status
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

// MARK: - Glass card modifier (mantener para login/otras vistas)

extension View {
    func glassCard() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Status badge helper

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
