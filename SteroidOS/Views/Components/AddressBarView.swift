import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @EnvironmentObject var browserState: BrowserState
    @FocusState private var isFocused: Bool
    @State private var showSuggestions: Bool = false
    #if canImport(Speech)
    @StateObject private var voice = VoiceInputController()
    #endif

    private var currentSuggestions: [String] {
        browserState.suggestions(for: viewModel.addressBarText)
    }

    var body: some View {
        VStack(spacing: 4) {
            addressBarField

            // Suggestions dropdown with glass effect
            if showSuggestions && !currentSuggestions.isEmpty {
                suggestionList
                    .frame(maxHeight: 120)
                    .steroidGlassRounded(cornerRadius: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 6)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }
        }
        #if canImport(Speech)
        .onChange(of: voice.transcript) { _, newTranscript in
            if !newTranscript.isEmpty {
                viewModel.addressBarText = newTranscript
            }
        }
        .onAppear {
            voice.onFinish = { finalText in
                if !finalText.isEmpty {
                    viewModel.addressBarText = finalText
                    viewModel.submitAddress(state: browserState)
                }
            }
        }
        .onChange(of: browserState.voiceInputRequested) { _, requested in
            if requested {
                browserState.voiceInputRequested = false
                voice.start()
            }
        }
        #endif
    }

    private var addressBarField: some View {
        HStack(spacing: 6) {
            #if canImport(Speech)
            Image(systemName: voice.isRecording ? "waveform" : "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(voice.isRecording ? .red : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: voice.isRecording)
            #else
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            #endif

            TextField("Search or enter URL", text: $viewModel.addressBarText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    SteroidHaptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSuggestions = false
                    }
                    viewModel.submitAddress(state: browserState)
                }
                .onChange(of: viewModel.addressBarText) { _, newValue in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        showSuggestions = isFocused && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                }
                .accessibilityLabel("Search or enter URL")

            if !viewModel.addressBarText.isEmpty {
                #if canImport(Speech)
                if !voice.isRecording {
                    clearButton
                }
                #else
                clearButton
                #endif
            }

            #if canImport(Speech)
            Button {
                SteroidHaptics.tap()
                if voice.isRecording {
                    voice.stop()
                } else {
                    voice.start()
                }
            } label: {
                Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(voice.isRecording ? .red : .blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Speak URL or search")
            .accessibilityHint(voice.isRecording ? "Double tap to stop recording" : "Double tap to start voice input")
            #endif
        }
        .padding(.horizontal, isFocused ? 10 : 8)
        .padding(.vertical, isFocused ? 7 : 5)
        .steroidGlassCapsule()
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: isFocused
                            ? [Color.blue.opacity(0.6), Color.cyan.opacity(0.4)]
                            : [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isFocused ? 1 : 0.5
                )
        )
        .shadow(
            color: isFocused ? .blue.opacity(0.2) : .black.opacity(0.1),
            radius: isFocused ? 12 : 6,
            x: 0,
            y: isFocused ? 4 : 2
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }

    private var suggestionList: some View {
        VStack(spacing: 2) {
            ForEach(currentSuggestions, id: \.self) { suggestion in
                Button {
                    SteroidHaptics.selection()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewModel.addressBarText = suggestion
                        showSuggestions = false
                        viewModel.submitAddress(state: browserState)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(suggestion)
                            .font(.system(size: 12, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suggestion: \(suggestion)")
                .accessibilityHint("Double tap to search for this")
            }
        }
    }
}

extension AddressBarView {
    private var clearButton: some View {
        Button {
            SteroidHaptics.tap()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                viewModel.addressBarText = ""
                showSuggestions = false
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear address bar")
        .accessibilityHint("Double tap to clear the text")
    }
}
