import WidgetKit
import SwiftUI

// MARK: - BrowserOS Complication
// Watch face complication + Smart Stack widget that surfaces the most
// recently visited page (with a one-tap launch action) and a quick
// voice-search affordance. Falls back to the BrowserOS logo if there's
// no recent history.

struct BrowserOSComplicationEntry: TimelineEntry {
    let date: Date
    let recentTitle: String?
    let recentURL: String?
}

struct BrowserOSComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrowserOSComplicationEntry {
        BrowserOSComplicationEntry(date: Date(), recentTitle: "Browse the web", recentURL: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BrowserOSComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BrowserOSComplicationEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 15 minutes so the recent page stays current without
        // burning watch battery.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> BrowserOSComplicationEntry {
        let store = HistoryStore()
        let recent = store.load().first
        return BrowserOSComplicationEntry(
            date: Date(),
            recentTitle: recent?.title,
            recentURL: recent?.url
        )
    }
}

// MARK: - Complication Views

struct BrowserOSComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: BrowserOSComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .semibold))
        }
        .widgetURL(launchURL(for: .openHome))
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                Text("BrowserOS")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            if let title = entry.recentTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            } else {
                Text("Tap to browse")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(launchURL(for: entry.recentURL != nil ? .openRecent : .openHome))
    }

    private var inlineView: some View {
        Label {
            Text(entry.recentTitle ?? "BrowserOS")
                .lineLimit(1)
        } icon: {
            Image(systemName: "globe")
        }
        .widgetURL(launchURL(for: .openHome))
    }

    private var cornerView: some View {
        Image(systemName: "globe")
            .font(.system(size: 16, weight: .semibold))
            .widgetURL(launchURL(for: .openHome))
    }

    private enum LaunchAction { case openHome, openRecent, voiceSearch }

    private func launchURL(for action: LaunchAction) -> URL? {
        switch action {
        case .openHome:
            return URL(string: "browseros://home")
        case .openRecent:
            if let url = entry.recentURL {
                return URL(string: "browseros://open?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)")
            }
            return URL(string: "browseros://home")
        case .voiceSearch:
            return URL(string: "browseros://voice")
        }
    }
}

// MARK: - Widget

struct BrowserOSWidget: Widget {
    let kind: String = "BrowserOSComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BrowserOSComplicationProvider()) { entry in
            BrowserOSComplicationView(entry: entry)
        }
        .configurationDisplayName("BrowserOS")
        .description("Launch BrowserOS or jump back into your last page.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

