import SwiftUI

/// Shared furniture. The app reads as a piece of production software, so the
/// numbers are monospaced, the panels are dark, and nothing bounces.
enum Palette {
    static let accent = Color(red: 0.94, green: 0.63, blue: 0.13)
    static let cool = Color(red: 0.31, green: 0.64, blue: 1.0)
    static let good = Color(red: 0.26, green: 0.75, blue: 0.48)
    static let bad = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let panel = Color(.secondarySystemBackground)
}

struct StatTile: View {
    var label: String
    var value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StatGrid: View {
    var stats: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                StatTile(label: stat.0, value: stat.1)
            }
        }
    }
}

/// A labelled bar — used for department share, where the shape of the spend
/// matters more than the exact number.
struct ShareBar: View {
    var label: String
    var amount: String
    var fraction: Double
    var tint: Color = Palette.cool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(amount).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.panel)
                    Capsule().fill(tint.opacity(0.85))
                        .frame(width: max(2, geometry.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

struct KeyValueRow: View {
    var key: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct WarningBanner: View {
    var messages: [String]

    var body: some View {
        if messages.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
