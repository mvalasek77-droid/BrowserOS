import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @EnvironmentObject var browserState: BrowserState
    @FocusState private var isFocused: Bool
    #if canImport(Speech)
    @StateObject private var voice = VoiceInputController()
    #endif

    var body: some View {
        HStack(spacing: 6) {
            #if canImport(Speech)
            Image(systemName: voice.isRecording ? "waveform" : "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(voice.isRecording ? .red : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: voice.isRecording)
            #else
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            #endif

            TextField("Search or enter URL", text: $viewModel.addressBarText)
                .font(.system(size: 13, weight: .medium))
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    viewModel.submitAddress(state: browserState)
                }

            if !viewModel.addressBarText.isEmpty {
                #if canImport(Speech)
                if !voice.isRecording {
                    Button {
                        viewModel.addressBarText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                #else
                Button {
                    viewModel.addressBarText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                    .font(.system(size: 13))
                    .foregroundStyle(voice.isRecording ? .red : .blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Speak URL or search")
            #endif
        }
        .padding(.horizontal, isFocused ? 12 : 10)
        .padding(.vertical, isFocused ? 10 : 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    isFocused
                        ? Color.blue.opacity(0.5)
                        : Color.white.opacity(0.25),
                    lineWidth: isFocused ? 1 : 0.5
                )
        )
        .shadow(
            color: isFocused ? .blue.opacity(0.15) : .black.opacity(0.15),
            radius: isFocused ? 10 : 8,
            x: 0,
            y: 4
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .onChange(of: isFocused) { _, newValue in
            viewModel.isAddressBarFocused = newValue
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
}
