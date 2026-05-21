import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @EnvironmentObject var browserState: BrowserState
    @FocusState private var isFocused: Bool
    @StateObject private var voice = VoiceInputController()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: voice.isRecording ? "waveform" : "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(voice.isRecording ? .red : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: voice.isRecording)

            TextField("Search or enter URL", text: $viewModel.addressBarText)
                .font(.system(size: 13, weight: .medium))
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    viewModel.submitAddress(state: browserState)
                }

            if !viewModel.addressBarText.isEmpty && !voice.isRecording {
                Button {
                    viewModel.addressBarText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                if voice.isRecording {
                    voice.stop()
                } else {
                    voice.start()
                }
            } label: {
                Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(voice.isRecording ? .red : .blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Speak URL or search")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .onChange(of: isFocused) { _, newValue in
            viewModel.isAddressBarFocused = newValue
        }
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
    }
}