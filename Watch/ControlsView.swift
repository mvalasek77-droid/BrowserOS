import SwiftUI
import WatchKit

/// Page options (long-press the address bar or the page, or ••• on the start
/// page): navigation, video, zoom, Favorites, New Tab and saved-login fill.
struct ControlsView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let frame = session.frame {
                    Text(frame.title.isEmpty ? frame.url : frame.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 6) {
                    navButton("chevron.left", enabled: session.frame?.canGoBack ?? false) {
                        session.goBack()
                    }
                    navButton("chevron.right", enabled: session.frame?.canGoForward ?? false) {
                        session.goForward()
                    }
                    navButton("arrow.clockwise", enabled: session.frame != nil) {
                        session.reload()
                    }
                    navButton("arrow.up.to.line", enabled: session.viewScroll > 0) {
                        session.scrollTo(0)
                    }
                }

                if session.pageHasVideo && !session.isVideoMirrorOn {
                    row("Play video on watch", "play.rectangle.fill", prominent: true) {
                        session.playVideo()
                    }
                }

                row(session.isBookmarked ? "Remove from Favorites" : "Add to Favorites",
                    session.isBookmarked ? "star.slash" : "star") {
                    session.toggleBookmark()
                }

                row(session.zoomed ? "Zoom out" : "Zoom in 2×",
                    session.zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass") {
                    session.zoomed.toggle()
                }

                row("New Tab", "plus.square.on.square") {
                    session.newTab()
                }

                row("Fill saved login", "key.horizontal.fill") {
                    session.fillSavedLogin()
                }
                .disabled(session.image == nil)

                Text(session.isPhoneReachable ? "iPhone connected" : "iPhone not reachable")
                    .font(.caption2)
                    .foregroundStyle(session.isPhoneReachable ? Color.green : Color.orange)
            }
            .padding(.horizontal, 4)
        }
    }

    private func navButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
            dismiss()
        } label: {
            Image(systemName: systemName)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func row(_ title: String, _ systemImage: String, prominent: Bool = false,
                     action: @escaping () -> Void) -> some View {
        let button = Button {
            WKInterfaceDevice.current().play(.click)
            action()
            dismiss()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if prominent {
            button.buttonStyle(.borderedProminent).tint(.green)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
