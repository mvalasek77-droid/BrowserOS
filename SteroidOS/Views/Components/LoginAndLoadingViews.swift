import SwiftUI

// MARK: - Login Required View
// Shows when a page requires interactive login (Claude, Facebook, etc.)
// The watch can't render login forms — directs user to sign in on iPhone.

struct LoginRequiredView: View {
    let info: LoginRequiredInfo
    let onOpenOnIPhone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: info.isOAuthProvider ? "person.crop.circle.badge.questionmark" : "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Sign In Required")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            Text(info.title.isEmpty ? info.url : info.title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(info.reason)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                SteroidHaptics.tap()
                onOpenOnIPhone()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Open on iPhone")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("Open on iPhone to sign in")
            .accessibilityHint("Launches the SteroidOS app on your iPhone where you can log in to this site")
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Skeleton Loading View
// Shimmer placeholder shown while page content is being fetched/loaded.

struct SkeletonLoadingView: View {
    @State private var animateShimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title skeleton
            skeletonLine(width: 180, height: 16)
                .padding(.bottom, 4)

            // Body lines
            skeletonLine(width: 220, height: 10)
            skeletonLine(width: 200, height: 10)
            skeletonLine(width: 180, height: 10)
            skeletonLine(width: 210, height: 10)
            skeletonLine(width: 160, height: 10)

            // Image skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.05), lineWidth: 0.5)
                )

            // More body
            skeletonLine(width: 200, height: 10)
            skeletonLine(width: 180, height: 10)
            skeletonLine(width: 140, height: 10)
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animateShimmer = true
            }
        }
        .onDisappear {
            animateShimmer = false
        }
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(animateShimmer ? Color.gray.opacity(0.15) : Color.gray.opacity(0.08))
            .frame(width: width, height: height)
    }
}