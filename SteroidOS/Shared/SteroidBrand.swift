import SwiftUI
#if os(watchOS)
import WatchKit
#endif

enum SteroidBrand {
    static let name = "SteroidOS"
    static let tagline = "Native Browser for Apple Watch"
    static let supportEmail = "support@steroidos.app"
    static let termsAcceptedVersionKey = "steroidos_terms_accepted_version"
    static let currentTermsVersion = 1

    static let privacyPolicyURL = URL(string: "https://mvalasek77-droid.github.io/BrowserOS/apple-connect/privacy-policy.html") ?? URL(string: "about:blank")!
    static let termsOfUseURL = URL(string: "https://mvalasek77-droid.github.io/BrowserOS/apple-connect/terms-of-use.html") ?? URL(string: "about:blank")!
    static let bugReportURL = URL(string: "https://github.com/mvalasek77-droid/BrowserOS/issues/new") ?? URL(string: "about:blank")!

    // MARK: - Design Tokens (iOS 26 Liquid Glass ready)

    /// Spacing scale
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Corner radius scale
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    /// Animation timing — smooth, short springs tuned for watch (0.2–0.3s)
    enum AnimationTiming {
        static let fastSpring = Animation.spring(response: 0.25, dampingFraction: 0.75)
        static let mediumSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let slowSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }

    /// Reusable transitions — opacity + subtle scale for depth
    enum Transitions {
        static let gentle = AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity
        )
        static let slideUp = AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        )
    }
}

// MARK: - Liquid Glass View Modifiers

extension View {
    /// iOS 26 native glass effect with fallback to ultraThinMaterial on older OS.
    /// Capsule shape — ideal for pills, address bars, and control strips.
    @ViewBuilder
    func steroidGlassCapsule() -> some View {
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
    }

    /// Rounded-rectangle glass surface with subtle depth shadow.
    @ViewBuilder
    func steroidGlassRounded(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
    }

    /// Deep glass card — elevated surface with glass effect and gentle shadow.
    /// On glass-capable OS the system provides depth; on fallback we add a shadow + hairline.
    @ViewBuilder
    func steroidGlassCard(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    /// Floating glass panel — highest elevation with strong shadow fallback.
    @ViewBuilder
    func steroidGlassElevated(cornerRadius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
                .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    /// Subtle inner glow border — a hairline gradient stroke that reads as
    /// frosted-glass edge lighting. Kept very light so it never looks busy on watch.
    func steroidInnerGlow(cornerRadius: CGFloat = 12) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }

    /// Shimmer loading effect — subtle, battery-friendly (no repeatForever).
    @ViewBuilder
    func steroidShimmer(isActive: Bool) -> some View {
        if isActive {
            self.redacted(reason: .placeholder)
                .shimmering()
        } else {
            self
        }
    }
}

// MARK: - Shimmer Modifier
// Single-pass sweep driven by a one-shot animation. We intentionally avoid
// `.repeatForever` to keep watch battery drain minimal — the sweep plays once
// per appearance and naturally fades as content loads.

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -300
    @State private var hasAnimated = false

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.18),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                // One-shot sweep — no repeatForever to conserve watch battery.
                guard !hasAnimated else { return }
                hasAnimated = true
                withAnimation(.easeOut(duration: 1.4)) {
                    phase = 300
                }
            }
    }
}

// MARK: - Adaptive Haptic Feedback
// Centralized helper so haptics stay subtle and consistent across the app.
// On watchOS we use WKInterfaceDevice; on iOS we fall back to UIKit's
// UIImpactFeedbackGenerator so the shared theme file compiles for both targets.

enum SteroidHaptics {
    /// Light tap for routine button presses.
    static func tap() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #elseif os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// Selection changed — pickers, segments, toggles.
    static func selection() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #elseif os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    /// Successful action — page loaded, form submitted, bookmark saved.
    static func success() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #elseif os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    /// Warning / non-fatal error — standalone mode, load failure.
    static func warning() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #elseif os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
}