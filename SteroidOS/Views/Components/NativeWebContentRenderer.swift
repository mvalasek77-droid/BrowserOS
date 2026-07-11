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
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
    
    /// Flattens elements into renderable items, tracking list position for
    /// ordered lists so that `<li>` items get proper 1, 2, 3… numbering.
    private var renderableElements: [RenderableItem] {
        var items: [RenderableItem] = []
        var orderedListIndex = 0
        
        for element in elements {
            switch element {
            case .listItem(_, let ordered):
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

// MARK: - Heading (card-style, color-coded)

struct HeadingView: View {
    let text: String
    let level: Int
    
    /// Color-coded accent per heading level for visual hierarchy on the watch.
    private var accentColor: Color {
        switch level {
        case 1: return .blue
        case 2: return .purple
        case 3: return .orange
        case 4: return .teal
        default: return .indigo
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Color-coded accent bar — gives each section a visual anchor.
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)
            Text(text)
                .font(level == 1 ? .system(size: 17, weight: .bold, design: .rounded) :
                      level == 2 ? .system(size: 15, weight: .bold, design: .rounded) :
                      level == 3 ? .system(size: 14, weight: .semibold, design: .rounded) :
                      .system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, level <= 2 ? 10 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Paragraph (card-based, large readable text)

struct ParagraphView: View {
    let text: String

    var body: some View {
        // Plain flowing text — boxing every paragraph in a card made pages
        // read as disconnected fragments.
        Text(text)
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - List Item (card pill, large text)

struct ListItemView: View {
    let text: String
    let ordered: Bool
    let index: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(ordered ? "\(index)." : "\u{2022}")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
                .frame(width: 18, alignment: .trailing)

            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Link (glass pill button, 44pt tap target)

struct LinkView: View {
    let text: String
    let url: String
    let onTap: (String) -> Void
    
    var body: some View {
        // Compact text-style link — the old full-width gradient pills
        // dominated the page and made mixed content unreadable.
        Button {
            onTap(url)
        } label: {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue)
                    .padding(.top, 3)

                Text(text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.blue)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(LinkButtonStyle())
        .accessibilityLabel("Open link: \(text)")
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Web Image (async loaded, compressed for watch)

struct WebImageView: View {
    let url: String
    let alt: String
    @State private var imageData: Data? = nil
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?

    /// Downscaled images keyed by URL. LazyVStack discards row state on
    /// scroll, so without this every image is refetched and re-downscaled
    /// each time it scrolls back into view.
    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

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
                    .accessibilityLabel(alt.isEmpty ? "Web image" : alt)
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12))
                    .frame(height: 100)
                    .overlay {
                        VStack(spacing: 6) {
                            ProgressView()
                                .tint(.blue)
                            Text("Loading image…")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .shimmering()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
                    .frame(height: 80)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.secondary)
                            if !alt.isEmpty {
                                Text(alt.prefix(30))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            loadImage()
        }
        .onDisappear {
            // Cancel in-flight image fetch when view scrolls off-screen
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private func loadImage() {
        guard imageData == nil, !isLoading else { return }
        if let cached = Self.cache.object(forKey: url as NSString) {
            imageData = cached as Data
            return
        }
        isLoading = true
        let url = self.url
        // Detached so the downscale/JPEG re-encode runs off the main actor.
        loadTask = Task.detached(priority: .utility) {
            do {
                let fetcher = await WebFetcher()
                let data = try await fetcher.fetchImageData(url: url)
                // Downscale for watchOS memory constraints
                let compressed = Self.downscaleForWatch(data: data, maxDimension: 200)
                Self.cache.setObject(compressed as NSData, forKey: url as NSString, cost: compressed.count)
                await MainActor.run {
                    imageData = compressed
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
    
    /// Downscale images on watchOS to prevent OOM crashes with full-res images
    static func downscaleForWatch(data: Data, maxDimension: CGFloat) -> Data {
        #if os(watchOS)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return data }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        if scale >= 1.0 { return data }  // Already small enough
        let newWidth = Int(image.size.width * scale)
        let newHeight = Int(image.size.height * scale)
        let bitsPerComponent = 8
        let bytesPerRow = newWidth * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: newWidth, height: newHeight,
                                       bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return data
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let resizedCG = context.makeImage() else { return data }
        let resized = UIImage(cgImage: resizedCG)
        return resized.jpegData(compressionQuality: 0.7) ?? data
        #else
        return data
        #endif
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
                .font(.system(size: 13, weight: .regular, design: .rounded).italic())
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.06))
        )
    }
}

// MARK: - Code Block (dark glass card)

struct CodeBlockView: View {
    let code: String
    
    var body: some View {
        Text(code)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(.green)
            .padding(12)
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
        VStack(alignment: .leading, spacing: 3) {
            if !headers.isEmpty {
                HStack(spacing: 4) {
                    ForEach(headers, id: \.self) { header in
                        Text(header.prefix(12))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                )
            }
            
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { cell in
                        Text(cell.prefix(16))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.05))
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
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
        SteroidHaptics.tap()
        isSubmitting = true
        let payload = values.filter { !$0.value.isEmpty }
        WatchSessionManager.shared.submitForm(formIndex: formIndex, values: payload)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isSubmitting = false
            SteroidHaptics.success()
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
