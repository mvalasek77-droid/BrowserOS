import SwiftUI

// MARK: - Reader Mode View
// Clean, distraction-free reading optimized for watch screen

struct ReaderModeView: View {
    let content: ReaderContent
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Article Title
                Text(content.title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Byline
                if let byline = content.byline {
                    Text(byline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Divider()
                
                // Article Content
                ForEach(content.content) { block in
                    renderBlock(block)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
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
        
        case .heading(let text, let level):
            Text(text)
                .font(level <= 2 ? .headline : .subheadline.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        
        case .quote(let text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 3)
                
                Text(text)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        
        case .code(let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.green)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}