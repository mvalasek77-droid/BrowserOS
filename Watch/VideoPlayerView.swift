import AVFoundation
import AVKit
import SwiftUI
import WatchKit

/// Plays a video the iPhone handed over, natively on the watch: full frame
/// rate, sound on the watch speaker or headphones. If the stream won't play
/// (protected or unsupported), offers to stream it from the iPhone instead.
struct VideoPlayerView: View {
    let offer: VideoOffer
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if failed {
                failure
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(offer.title)
        .task { await start() }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var failure: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "play.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("This video can't play on the watch")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                Button {
                    session.setVideoMirror(true)
                    dismiss()
                } label: {
                    Label("Stream from iPhone", systemImage: "iphone.and.arrow.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Close", role: .cancel) { dismiss() }
            }
            .padding(.horizontal, 6)
        }
    }

    @MainActor
    private func start() async {
        guard let url = offer.url else {
            failed = true
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        if offer.startTime > 1 {
            _ = await newPlayer.seek(to: CMTime(seconds: offer.startTime, preferredTimescale: 600))
        }
        player = newPlayer
        newPlayer.play()

        // Watch for the stream failing to load (KVO-free polling keeps this simple).
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, player != nil else { return }
            switch item.status {
            case .failed:
                WKInterfaceDevice.current().play(.failure)
                player?.pause()
                failed = true
                return
            case .readyToPlay:
                return
            default:
                continue
            }
        }
        // Still not ready after 15 s: treat as unplayable.
        if item.status != .readyToPlay {
            player?.pause()
            failed = true
        }
    }
}
