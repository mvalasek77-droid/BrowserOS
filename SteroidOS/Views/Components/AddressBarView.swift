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
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        withAnimation(.spring(response: 0.3)) {
                            showSuggestions = false
                        }
                        viewModel.submitAddress(state: browserState)
                    }
                    .onChange(of: viewModel.addressBarText) { _, newValue in
                        withAnimation(.spring(response: 0.2)) {
                            showSuggestions = isFocused && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                    }

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
                #endif
            }
            .padding(.horizontal, isFocused ? 12 : 10)
            .padding(.vertical, isFocused ? 10 : 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
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
            .padding(.vertical, 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)

            // Suggestions dropdown with glass effect
            if showSuggestions && !currentSuggestions.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(currentSuggestions, id: \.self) { suggestion in
                            Button {
                                withAnimation(.spring(response: 0.25)) {
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
                        }
                    }
                }
                .frame(maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
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

    private var clearButton: some View {
        Button {
            withAnimation(.spring(response: 0.2)) {
                viewModel.addressBarText = ""
                showSuggestions = false
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}