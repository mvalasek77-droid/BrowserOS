import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
    }
}