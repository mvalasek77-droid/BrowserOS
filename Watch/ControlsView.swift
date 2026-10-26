import SwiftUI

/// Long-press sheet: navigation buttons and an address field.
struct ControlsView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        session.goBack()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!(session.frame?.canGoBack ?? false))

                    Button {
                        session.goForward()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!(session.frame?.canGoForward ?? false))

                    Button {
                        session.reload()
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                TextField("Search or URL", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(go)

                Button {
                    session.fillSavedLogin()
                    dismiss()
                } label: {
                    Label("Fill saved login", systemImage: "key.horizontal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                // Only meaningful when there's a page to fill on.
                .disabled(session.image == nil)

                Button("Go", action: go)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let frame = session.frame {
                    Text(frame.title.isEmpty ? frame.url : frame.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                Text(session.isPhoneReachable ? "iPhone connected" : "iPhone not reachable")
                    .font(.caption2)
                    .foregroundStyle(session.isPhoneReachable ? Color.green : Color.orange)
            }
            .padding(.horizontal, 4)
        }
    }

    private func go() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.navigate(to: trimmed)
        dismiss()
    }
}
