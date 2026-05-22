import SwiftUI

// MARK: - BrandCard

struct BrandCard<Content: View>: View {
    var padding: CGFloat = 14
    var radius: CGFloat = 16
    let content: () -> Content

    init(padding: CGFloat = 14, radius: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(Theme.textMuted)
    }
}

// MARK: - StatCell + StatStrip

struct StatCell: View {
    let value: String
    let label: String
    var valueColor: Color = Theme.navyText

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(valueColor)
            Text(label.lowercased())
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}

struct StatStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        let value: String
        let label: String
        var color: Color = Theme.navyText
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                StatCell(value: item.value, label: item.label, valueColor: item.color)
            }
        }
    }
}

// MARK: - InlineActionPill

struct InlineActionPill: View {
    let title: String
    var systemImage: String? = nil
    var fg: Color = Theme.navyText
    var bg: Color = Color.black.opacity(0.05)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let s = systemImage { Image(systemName: s).font(.caption2.bold()) }
                Text(title).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BigCTAButton

struct BigCTAButton: View {
    let title: String
    var systemImage: String? = nil
    var bg: Color = Theme.success
    var fg: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let s = systemImage { Image(systemName: s).font(.headline) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TotalSummaryCard

struct TotalSummaryCard: View {
    struct Row {
        let label: String
        let value: String
        var color: Color = .white.opacity(0.6)
    }

    let rows: [Row]
    let total: String
    var totalColor: Color = Theme.amber

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rows.count, id: \.self) { i in
                HStack {
                    Text(rows[i].label)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(rows[i].value)
                        .font(.subheadline)
                        .foregroundStyle(rows[i].color)
                }
            }
            Divider().background(Color.white.opacity(0.15)).padding(.vertical, 4)
            HStack(alignment: .lastTextBaseline) {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(total)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(totalColor)
            }
        }
        .padding(16)
        .background(Theme.navy)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
