import SwiftUI

/// First-launch tutorial for SteroidOS. Shows once (or from the Watch status
/// sheet's "View tutorial" button). Explains the watch-mirror concept, how to
/// browse from the wrist, and how saved logins work.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    /// Set true by the "View tutorial" button so it always shows content, even
    /// mid-session (not just first launch).
    var forced = false
    @State private var page = 0

    private struct Step: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let body: String
    }

    private let steps: [Step] = [
        Step(id: 0, icon: "applewatch",
             title: "Welcome to SteroidOS",
             body: "Your iPhone browser, mirrored live on your Apple Watch. Whatever you open here appears on your wrist in real time — no sync delay."),
        Step(id: 1, icon: "hand.tap",
             title: "Browse from your wrist",
             body: "On the watch: tap the mirror to click links and buttons, turn the Digital Crown to scroll the page, double-tap to zoom, long-press for the address bar, back and reload."),
        Step(id: 2, icon: "character.cursor.ibeam",
             title: "Type without the phone",
             body: "Tap any search box or text field on the watch and a dictation sheet opens — speak your text, submit, and it's typed into the page on your iPhone, ready to go."),
        Step(id: 3, icon: "key.horizontal.fill",
             title: "Logins, saved on your terms",
             body: "The first time you dictate a password, the watch offers to save it for that site in the iPhone's Keychain. Next time, long-press the watch → Fill saved login — both fields fill instantly."),
        Step(id: 4, icon: "iphone.radiowaves.left.and.right",
             title: "Keep the phone awake",
             body: "If the mirror goes dark, tap Wake iPhone on the watch. Frames keep streaming only while SteroidOS is open on both devices."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(steps) { step in
                    VStack(spacing: 18) {
                        Spacer()
                        Image(systemName: step.icon)
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(.blue)
                            .symbolRenderingMode(.hierarchical)
                        Text(step.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(step.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Spacer()
                        Spacer()
                    }
                    .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                Button("Skip") { dismiss() }
                    .foregroundStyle(.secondary)
                Spacer()
                if page < steps.count - 1 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.trailingAndLeading)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        TutorialGate.markSeen()
                        dismiss()
                    } label: {
                        Label("Start browsing", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(.background)
    }
}

/// Reusable trailing+leading label style so "Next >" reads naturally.
extension LabelStyle where Self == TrailingAndLeadingLabelStyle {
    static var trailingAndLeading: TrailingAndLeadingLabelStyle { TrailingAndLeadingLabelStyle() }
}

struct TrailingAndLeadingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// Decides when the tutorial should appear: once per install (not per launch).
enum TutorialGate {
    static let seenKey = "SteroidOS.tutorialSeen"

    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: seenKey) }

    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }
}