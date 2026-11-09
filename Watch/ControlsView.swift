import SwiftUI
import WatchKit

/// Navigation menu (☰ button or long-press): search, back/forward/reload,
/// jump to top, quick links, and saved-login fill.
struct ControlsView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss

    private struct QuickSite: Identifiable {
        let name: String
        let url: String
        let icon: String
        var id: String { url }
    }

    private static let quickSites: [QuickSite] = [
        QuickSite(name: "Google", url: "https://www.google.com", icon: "magnifyingglass.circle"),
        QuickSite(name: "YouTube", url: "https://m.youtube.com", icon: "play.rectangle"),
        QuickSite(name: "Wikipedia", url: "https://en.m.wikipedia.org", icon: "book"),
        QuickSite(name: "Reddit", url: "https://www.reddit.com", icon: "bubble.left.and.bubble.right")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // One tap → dictation / Scribble / keyboard → Google results
                // (or the site, if what you said looks like an address).
                TextFieldLink(prompt: Text("Search Google or enter URL")) {
                    Label("Search or URL", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } onSubmit: { query in
                    go(query)
                }
                .buttonStyle(.borderedProminent)

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

                Text("Go to")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                ForEach(Self.quickSites) { site in
                    Button {
                        go(site.url)
                    } label: {
                        Label(site.name, systemImage: site.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    session.fillSavedLogin()
                    dismiss()
                } label: {
                    Label("Fill saved login", systemImage: "key.horizontal.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                // Only meaningful when there's a page to fill on.
                .disabled(session.image == nil)

                if let frame = session.frame {
                    Text(frame.title.isEmpty ? frame.url : frame.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }

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

    private func go(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        WKInterfaceDevice.current().play(.click)
        session.navigate(to: trimmed)
        dismiss()
    }
}
