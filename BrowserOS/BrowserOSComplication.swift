import WidgetKit
import SwiftUI

// MARK: - BrowserOS Complication
// Quick-launch complication for Apple Watch face

struct BrowserOSComplicationEntry: TimelineEntry {
    let date: Date
    let title: String
}

struct BrowserOSComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrowserOSComplicationEntry {
        BrowserOSComplicationEntry(date: Date(), title: "BrowserOS")
    }
    
    func getSnapshot(in context: Context, completion: @escaping (BrowserOSComplicationEntry) -> Void) {
        completion(BrowserOSComplicationEntry(date: Date(), title: "BrowserOS"))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<BrowserOSComplicationEntry>) -> Void) {
        let entry = BrowserOSComplicationEntry(date: Date(), title: "BrowserOS")
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct BrowserOSComplicationView: View {
    let entry: BrowserOSComplicationEntry
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
            Text("Browse")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct BrowserOSWidget: Widget {
    let kind: String = "BrowserOSComplication"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BrowserOSComplicationProvider()) { entry in
            BrowserOSComplicationView(entry: entry)
        }
        .configurationDisplayName("BrowserOS")
        .description("Quick launch your browser")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}