import SwiftUI

enum SteroidBrand {
    static let name = "SteroidOS"
    static let tagline = "Native Browser for Apple Watch"
    static let supportEmail = "support@steroidos.app"
    static let termsAcceptedVersionKey = "steroidos_terms_accepted_version"
    static let currentTermsVersion = 1

    static let privacyPolicyURL = URL(string: "https://mvalasek77-droid.github.io/BrowserOS/apple-connect/privacy-policy.html")!
    static let termsOfUseURL = URL(string: "https://mvalasek77-droid.github.io/BrowserOS/apple-connect/terms-of-use.html")!
    static let bugReportURL = URL(string: "https://github.com/mvalasek77-droid/BrowserOS/issues/new")!

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

    /// Animation timing
    enum AnimationTiming {
        static let fastSpring = Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let mediumSpring = Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let slowSpring = Animation.spring(response: 0.5, dampingFraction: 0.8)
    }

    /// Reusable transitions
    enum Transitions {
        static let gentle = AnyTransition.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity)
    }
}

// MARK: - Liquid Glass View Modifiers

extension View {
    /// iOS 26 native glass effect with fallback to ultraThinMaterial on older OS
    @ViewBuilder
    func steroidGlassCapsule() -> some View {
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func steroidGlassRounded(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }

    /// Deep glass card — elevated surface with glass effect
    @ViewBuilder
    func steroidGlassCard(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
    }

    /// Floating glass panel — highest elevation with strong shadow fallback
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

    /// Subtle inner glow border
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

    /// Shimmer loading effect
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

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}

// MARK: - Haptic Feedback Helpers

extension View {
    /// Watch haptic feedback on tap
    func hapticOnTap() -> some View {
        self.onAppear {
            #if os(watchOS)
            // Haptics are played directly in button actions
            #endif
        }
    }
}