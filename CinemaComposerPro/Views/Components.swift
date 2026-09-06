import SwiftUI

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum Palette {
    static let accent = Color(red: 0.94, green: 0.63, blue: 0.13)
    static let cool = Color(red: 0.31, green: 0.64, blue: 1.0)
    static let good = Color(red: 0.26, green: 0.75, blue: 0.48)
    static let bad = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let panel = Color(.secondarySystemBackground)
}

enum Haptics {
    private static let successGenerator = UINotificationFeedbackGenerator()
    private static let warningGenerator = UINotificationFeedbackGenerator()
    private static let tapGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func success() {
        successGenerator.notificationOccurred(.success)
    }

    static func tap() {
        tapGenerator.impactOccurred()
    }

    static func warning() {
        warningGenerator.notificationOccurred(.warning)
    }

    static func heavy() {
        heavyGenerator.impactOccurred()
    }

    static func prepare() {
        successGenerator.prepare()
        tapGenerator.prepare()
    }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
                    Capsule().fill(.quaternary)
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

struct FinalScriptAICard: View {
    var style: CardStyle = .compact
    @Environment(\.openURL) private var openURL

    enum CardStyle { case compact, full }

    private static let appStoreURL = URL(string: "https://apps.apple.com/app/final-script-ai/id6783624274")!

    var body: some View {
        Button { openURL(Self.appStoreURL) } label: {
            switch style {
            case .compact: compactLayout
            case .full: fullLayout
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Final Script AI")
        .accessibilityHint("Opens in the App Store")
    }

    private var compactLayout: some View {
        HStack(spacing: 12) {
            scriptIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("Final Script AI").font(.subheadline.bold())
                Text("Write production-ready screenplays with AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("GET")
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Palette.cool, in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(colors: [Palette.cool.opacity(0.3), Palette.accent.opacity(0.15)],
                                   startPoint: .leading, endPoint: .trailing),
                    lineWidth: 0.5
                )
        )
    }

    private var fullLayout: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                scriptIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text("Final Script AI")
                        .font(.headline)
                    Text("The screenplay companion to Cinema Composer Pro")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                promoFeature(icon: "doc.text", text: "AI-powered screenplay writing and formatting")
                promoFeature(icon: "arrow.triangle.branch", text: "Scene breakdowns that feed straight into production")
                promoFeature(icon: "person.3", text: "Character development and dialogue refinement")
                promoFeature(icon: "sparkles", text: "Rewrite, expand, and polish with AI assistance")
            }

            HStack {
                Text("Write the script, then produce it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Open in App Store")
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Palette.cool, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cool.opacity(0.2), lineWidth: 0.5))
    }

    private var scriptIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Palette.cool, Palette.cool.opacity(0.7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
            Image(systemName: "text.page.fill")
                .font(.title3)
                .foregroundStyle(.white)
        }
    }

    private func promoFeature(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Palette.cool)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
