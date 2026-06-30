import SwiftUI

// MARK: - Reader Mode View
// Clean, distraction-free reading optimized for watch screen with polished typography

struct ReaderModeView: View {
    let content: ReaderContent
    
    var body: some View {
        // No ScrollView here — the parent BrowserPageView already wraps us in one.
        // Nested ScrollViews fight over Digital Crown/touch gestures on watchOS.
        VStack(alignment: .leading, spacing: 12) {
                // Article Title — hero card with glass effect
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let byline = content.byline {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9))
                            Text(byline)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .steroidGlassCard(cornerRadius: 12)

                // Article Content
                ForEach(content.content) { block in
                    renderBlock(block)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func renderBlock(_ block: ReaderContent.ReaderBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(3)
                .padding(.horizontal, 4)
        
        case .heading(let text, let level):
            Text(text)
                .font(level <= 2 ? .headline : .subheadline.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.horizontal, 4)
        
        case .quote(let text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                
                Text(text)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.04))
            )
        
        case .code(let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.green)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.12), lineWidth: 0.5)
                )
        }
    }
}