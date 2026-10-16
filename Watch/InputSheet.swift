import SwiftUI
import WatchKit

/// Appears when the user taps a text field in the mirror. `TextFieldLink`
/// opens the system text-entry picker (dictation, Scribble, keyboard) and
/// returns the result; we then ship it to the iPhone and dismiss.
struct InputSheet: View {
    let prompt: InputPrompt
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var didSeedText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !prompt.placeholder.isEmpty {
                    Text(prompt.placeholder)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                TextFieldLink(prompt: Text(linkPromptText)) {
                    HStack {
                        Text(text.isEmpty ? "Tap to enter text" : text)
                            .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.blue)
                    }
                } onSubmit: { entered in
                    text = entered
                    submit()
                }
                .buttonStyle(.bordered)

                Button(action: submit) {
                    Label(submitLabel, systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            // Pre-fill with the field's current value only once so dictation
            // results don't get overwritten on re-render.
            if !didSeedText {
                text = prompt.currentValue
                didSeedText = true
            }
        }
    }

    private var linkPromptText: String {
        if !prompt.placeholder.isEmpty { return prompt.placeholder }
        switch prompt.inputType {
        case "search": return "Search"
        case "url": return "URL"
        case "email": return "Email"
        case "tel": return "Phone number"
        case "number": return "Number"
        case "password": return "Password"
        default: return "Enter text"
        }
    }

    private var submitLabel: String {
        if prompt.submitOnReturn {
            switch prompt.inputType {
            case "search": return "Search"
            default: return "Go"
            }
        }
        return "Done"
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        WKInterfaceDevice.current().play(.click)
        session.fillInput(text: text, submit: prompt.submitOnReturn)
        dismiss()
    }
}
