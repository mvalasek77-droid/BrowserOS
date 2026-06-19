import SwiftUI

struct ErrorLogView: View {
    @ObservedObject private var log = ErrorLog.shared
    @State private var showClearConfirm = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        Group {
            if log.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("No errors")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                                .font(.footnote)
                        }
                        .accessibilityLabel("Clear error log")
                    }

                    Section("\(log.entries.count) entries") {
                        ForEach(log.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(entry.source)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(Self.timeFormatter.string(from: entry.date))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(entry.message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                    .lineLimit(4)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Error Log")
        .confirmationDialog("Clear all log entries?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) { log.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
