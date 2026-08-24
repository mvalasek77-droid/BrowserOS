import SwiftUI

/// Keys. They go into the Keychain and come back out only as a mask — not into
/// the project file, not into an export, not into the run log.
struct KeysView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @State private var selectedRef: String = ""
    @State private var entry: String = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Vendor", selection: $selectedRef) {
                        ForEach(model.registry.keyRefs, id: \.self) { ref in Text(ref).tag(ref) }
                    }
                    SecureField("API key", text: $entry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save to Keychain") { save() }
                        .disabled(entry.count < 8 || selectedRef.isEmpty)
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Add a key")
                } footer: {
                    Text("Stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly: this device only, never synced, never written into a project file or an export.")
                }

                Section("Stored") {
                    if model.keys.descriptors.isEmpty {
                        Text("No keys yet. Dry runs work without any.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.keys.descriptors) { descriptor in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(descriptor.ref)
                                Spacer()
                                Text(descriptor.masked).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(descriptor.lastUsedAt.map { "last used \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "never used")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                model.keys.delete(ref: descriptor.ref)
                                model.recompute()
                            }
                        }
                    }
                }

                Section {
                    Toggle("Plan only with tools I hold keys for", isOn: $model.restrictToStoredKeys)
                    if !model.missingKeys.isEmpty {
                        Text("A live run still needs: \(model.missingKeys.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Palette.accent)
                    }
                } header: {
                    Text("Planning")
                } footer: {
                    Text("With this on, the conductor scores only the tools you can actually call — the budget stops quoting a vendor you have no account with.")
                }
            }
            .navigationTitle("Keys")
            .onAppear {
                if selectedRef.isEmpty { selectedRef = model.registry.keyRefs.first ?? "" }
            }
        }
    }

    private func save() {
        do {
            try model.keys.save(key: entry, for: selectedRef)
            entry = ""
            message = "Saved \(selectedRef)."
            model.recompute()
        } catch {
            message = error.localizedDescription
        }
    }
}
