import SwiftUI

// MARK: - Tab Manager View
// List of open browser tabs with subtle spring interactions and adaptive haptics.

struct TabManagerView: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        List {
            Section {
                Button {
                    haptic(.success)
                    browserState.addTab()
                } label: {
                    Label("New Tab", systemImage: "plus.circle.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("New tab")
                .accessibilityHint("Create a new browsing tab")
            }

            Section("Open Tabs") {
                ForEach(browserState.tabs) { tab in
                    tabRow(tab)
                        .listRowInsets(EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 6))
                }
            }
        }
        .navigationTitle("Tabs")
    }

    private func tabRow(_ tab: BrowserTab) -> some View {
        HStack(spacing: 8) {
            Button {
                haptic(.click)
                browserState.switchToTab(tab.id)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(tab.id == browserState.activeTabId ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            .frame(width: 34, height: 34)
                        Image(systemName: tab.id == browserState.activeTabId ? "globe" : "doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab.id == browserState.activeTabId ? .blue : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tab.title.isEmpty ? "New Tab" : tab.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(tab.url.isEmpty ? "Ready to browse" : tab.url)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if tab.id == browserState.activeTabId {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open tab \(tab.title.isEmpty ? "New Tab" : tab.title)")
            .accessibilityHint("Switch to this tab")

            if browserState.tabs.count > 1 {
                Button(role: .destructive) {
                    haptic(.notification)
                    browserState.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab")
                .accessibilityHint("Remove this browsing tab")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tab.id == browserState.activeTabId ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
        )
    }

    private enum HapticType {
        case click
        case success
        case notification
    }

    private func haptic(_ type: HapticType) {
        switch type {
        case .click:
            SteroidHaptics.selection()
        case .success:
            SteroidHaptics.success()
        case .notification:
            SteroidHaptics.warning()
        }
    }
}
