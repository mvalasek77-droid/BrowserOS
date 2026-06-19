import SwiftUI

// MARK: - Native Web Content Renderer
// Card-based native SwiftUI rendering of HTML elements for Apple Watch.
// Every element is a first-class watchOS citizen with polished micro-animations.

struct NativeWebContentRenderer: View {
    let elements: [NativeWebElement]
    let onLinkTap: (String) -> Void
    
    var body: some View {
        LazyVStack(spacing: 8, pinnedViews: []) {
            ForEach(Array(renderableElements.enumerated()), id: \.offset) { _, item in
                renderElement(item.element, listIndex: item.listIndex)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }
    
    /// Flattens elements into renderable items, tracking list position for
    /// ordered lists so that `<li>` items get proper 1, 2, 3… numbering.
    private var renderableElements: [RenderableItem] {
        var items: [RenderableItem] = []
        var orderedListIndex = 0
        
        for element in elements {
            switch element {
            case .listItem(let text, let ordered):
                if ordered {
                    orderedListIndex += 1
                    items.append(RenderableItem(element: element, listIndex: orderedListIndex))
                } else {
                    items.append(RenderableItem(element: element, listIndex: nil))
                }
            default:
                // Any non-list element resets the ordered counter
                if !items.isEmpty || orderedListIndex > 0 {
                    orderedListIndex = 0
                }
                items.append(RenderableItem(element: element, listIndex: nil))
            }
        }
        return items
    }
    
    @ViewBuilder
    private func renderElement(_ element: NativeWebElement, listIndex: Int?) -> some View {
        switch element {
        case .heading(let text, let level):
            HeadingView(text: text, level: level)
        case .paragraph(let text):
            ParagraphView(text: text)
        case .listItem(let text, let ordered):
            ListItemView(text: text, ordered: ordered, index: listIndex ?? 0)
        case .link(let text, let url):
            LinkView(text: text, url: url, onTap: onLinkTap)
        case .image(let url, let alt):
            WebImageView(url: url, alt: alt)
        case .divider:
            Divider()
                .padding(.vertical, 4)
        case .blockquote(let text):
            BlockquoteView(text: text)
        case .codeBlock(let code):
            CodeBlockView(code: code)
        case .table(let headers, let rows):
            TableView(headers: headers, rows: rows)
        case .form(let formIndex, let action, _, let inputs):
            FormView(formIndex: formIndex, action: action, inputs: inputs)
        }
    }
}

/// Helper to carry list position info through the renderer.
private struct RenderableItem {
    let element: NativeWebElement
    let listIndex: Int?
}

// MARK: - Heading (card-style)

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
            .padding(.horizontal, 10)
            .padding(.vertical, level <= 2 ? 8 : 4)
            .if(level <= 2) { view in
                view.background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
            }
    }
}

// MARK: - Paragraph (clean typography)

struct ParagraphView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
    }
}

// MARK: - List Item (card pill)

struct ListItemView: View {
    let text: String
    let ordered: Bool
    let index: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(ordered ? "\(index)." : "\u{2022}")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
                .frame(width: 18, alignment: .trailing)
            
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - Link (glass pill button)

struct LinkView: View {
    let text: String
    let url: String
    let onTap: (String) -> Void
    
    var body: some View {
        Button {
            onTap(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.85), Color.blue.opacity(0.65)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(LinkButtonStyle())
        .accessibilityLabel("Open link: \(text)")
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12))
                    .frame(height: 90)
                    .overlay {
                        ProgressView()
                            .tint(.blue)
                    }
                    .shimmering()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
                    .frame(height: 70)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            if !alt.isEmpty {
                                Text(alt.prefix(30))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
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

// MARK: - Blockquote (accent bar card)

struct BlockquoteView: View {
    let text: String
    
    var body: some View {
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
                .fill(Color.blue.opacity(0.05))
        )
    }
}

// MARK: - Code Block (dark glass card)

struct CodeBlockView: View {
    let code: String
    
    var body: some View {
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
                    .stroke(Color.green.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Table (compact card for watch)

struct TableView: View {
    let headers: [String]
    let rows: [[String]]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !headers.isEmpty {
                HStack(spacing: 4) {
                    ForEach(headers, id: \.self) { header in
                        Text(header.prefix(10))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                )
            }
            
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { cell in
                        Text(cell.prefix(14))
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.04))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Form (polished card form)

struct FormView: View {
    let formIndex: Int
    let action: String
    let inputs: [FormField]

    @State private var values: [String: String] = [:]
    @State private var isSubmitting = false

    private var submitButtonLabel: String {
        if let submit = inputs.first(where: { $0.type == "submit" }) {
            return submit.placeholder ?? "Submit"
        }
        return "Submit"
    }

    private var editableFields: [FormField] {
        inputs.filter { $0.type != "submit" && !$0.name.isEmpty }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(editableFields) { field in
                fieldView(for: field)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 4) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                    }
                    Text(submitButtonLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(LinkButtonStyle())
            .disabled(isSubmitting)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            for field in editableFields where field.value != nil {
                values[field.name] = field.value
            }
        }
    }

    @ViewBuilder
    private func fieldView(for field: FormField) -> some View {
        let prompt = field.label ?? field.placeholder ?? field.name
        let binding = Binding<String>(
            get: { values[field.name] ?? "" },
            set: { values[field.name] = $0 }
        )

        VStack(alignment: .leading, spacing: 3) {
            if let label = field.label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Group {
                switch field.type {
                case "password":
                    SecureField(prompt, text: binding)
                        .font(.system(size: 13))
                        .textContentType(.password)
                case "email":
                    TextField(prompt, text: binding)
                        .font(.system(size: 13))
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                case "url":
                    TextField(prompt, text: binding)
                        .font(.system(size: 13))
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                case "tel":
                    TextField(prompt, text: binding)
                        .font(.system(size: 13))
                        .textContentType(.telephoneNumber)
                case "search":
                    TextField(prompt, text: binding)
                        .font(.system(size: 13))
                        .textInputAutocapitalization(.never)
                case "number":
                    TextField(prompt, text: binding)
                        .font(.system(size: 13))
                default:
                    TextField(prompt, text: binding)
                        .font(.system(size: 13))
                        .textInputAutocapitalization(.never)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func submit() {
        isSubmitting = true
        let payload = values.filter { !$0.value.isEmpty }
        WatchSessionManager.shared.submitForm(formIndex: formIndex, values: payload)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isSubmitting = false
        }
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}