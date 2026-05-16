import SwiftUI

// MARK: - Native Web Content Renderer
// The revolutionary part: HTML elements rendered as native SwiftUI components
// No WKWebView — every element is a first-class watchOS citizen

struct NativeWebContentRenderer: View {
    let elements: [NativeWebElement]
    let onLinkTap: (String) -> Void
    
    var body: some View {
        LazyVStack(spacing: 6, pinnedViews: []) {
            ForEach(elements) { element in
                renderElement(element)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func renderElement(_ element: NativeWebElement) -> some View {
        switch element {
        case .heading(let text, let level):
            HeadingView(text: text, level: level)
        case .paragraph(let text):
            ParagraphView(text: text)
        case .listItem(let text, let ordered):
            ListItemView(text: text, ordered: ordered)
        case .link(let text, let url):
            LinkView(text: text, url: url, onTap: onLinkTap)
        case .image(let url, let alt):
            WebImageView(url: url, alt: alt)
        case .divider:
            Divider().padding(.vertical, 4)
        case .blockquote(let text):
            BlockquoteView(text: text)
        case .codeBlock(let code):
            CodeBlockView(code: code)
        case .table(let headers, let rows):
            TableView(headers: headers, rows: rows)
        case .form(let inputs):
            FormView(inputs: inputs, onSubmit: { _ in })
        }
    }
}

// MARK: - Heading

struct HeadingView: View {
    let text: String
    let level: Int
    
    var body: some View {
        Text(text)
            .font(level == 1 ? .title2.bold() :
                  level == 2 ? .title3.bold() :
                  level == 3 ? .headline :
                  .subheadline.bold())
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Paragraph

struct ParagraphView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
    }
}

// MARK: - List Item

struct ListItemView: View {
    let text: String
    let ordered: Bool
    @State private var index: Int = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(ordered ? "\(index)." : "\u{2022}")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Link

struct LinkView: View {
    let text: String
    let url: String
    let onTap: (String) -> Void
    
    var body: some View {
        Button {
            onTap(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 9))
                Text(text)
                    .font(.body)
                    .underline(true, color: .blue)
            }
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Web Image (async loaded, compressed for watch)

struct WebImageView: View {
    let url: String
    let alt: String
    @State private var imageData: Data? = nil
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
            } else if isLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 80)
                    .overlay {
                        ProgressView()
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 60)
                    .overlay {
                        VStack(spacing: 2) {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !alt.isEmpty {
                                Text(alt.prefix(30))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard imageData == nil, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let fetcher = WebFetcher()
                let data = try await fetcher.fetchImageData(url: url)
                await MainActor.run {
                    imageData = data
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}

// MARK: - Blockquote

struct BlockquoteView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue.opacity(0.6))
                .frame(width: 3)
            
            Text(text)
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Code Block

struct CodeBlockView: View {
    let code: String
    
    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.green)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Table (compact for watch)

struct TableView: View {
    let headers: [String]
    let rows: [[String]]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !headers.isEmpty {
                HStack(spacing: 4) {
                    ForEach(headers, id: \.self) { header in
                        Text(header.prefix(8))
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.2))
            }
            
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { cell in
                        Text(cell.prefix(12))
                            .font(.system(size: 10))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.05))
            }
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Form

struct FormView: View {
    let inputs: [FormField]
    let onSubmit: ([String: String]) -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(inputs) { field in
                Group {
                    if field.type == "submit" {
                        Button("Submit") {}
                            .buttonStyle(.borderedProminent)
                    } else if field.type == "password" {
                        SecureField(field.placeholder ?? field.name, text: .constant(""))
                            .font(.system(size: 13))
                    } else {
                        TextField(field.placeholder ?? field.name, text: .constant(""))
                            .font(.system(size: 13))
                            .textInputAutocapitalization(.never)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

// ErrorBannerView is defined in Components/ErrorBannerView.swift