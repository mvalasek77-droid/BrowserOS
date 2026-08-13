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
        VStack(spacing: 2) {
            addressBarField

            if showSuggestions && !currentSuggestions.isEmpty {
                suggestionList
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
        HStack(spacing: 4) {
            #if canImport(Speech)
            Image(systemName: voice.isRecording ? "waveform" : "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(voice.isRecording ? .red : .secondary)
            #else
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            #endif

            TextField("Search or URL", text: $viewModel.addressBarText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    SteroidHaptics.tap()
                    showSuggestions = false
                    viewModel.submitAddress(state: browserState)
                }
                .onChange(of: viewModel.addressBarText) { _, newValue in
                    showSuggestions = isFocused && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                SteroidHaptics.tap()
                if voice.isRecording {
                    voice.stop()
                } else {
                    voice.start()
                }
            } label: {
                Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(voice.isRecording ? .red : .blue)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(currentSuggestions.prefix(3), id: \.self) { suggestion in
                Button {
                    SteroidHaptics.tap()
                    viewModel.addressBarText = suggestion
                    showSuggestions = false
                    viewModel.submitAddress(state: browserState)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(suggestion)
                            .font(.system(size: 11, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 4)
    }

    private var clearButton: some View {
        Button {
            viewModel.addressBarText = ""
            showSuggestions = false
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
