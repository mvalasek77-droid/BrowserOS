import SwiftUI

/// The timeline index: everything in the cut as a searchable list.
///
/// Final Cut's index is how you navigate a feature — scrolling a two-hour
/// timeline to find one shot is not a workflow. This adds smart collections and
/// role mixing on top, so "every rejected shot over four seconds" or "mute all
/// music" is one tap rather than a hunt.
struct TimelineIndexView: View {
    @ObservedObject var doc: CutDocument
    @State private var tab: IndexTab = .clips
    @State private var query: String = ""
    @State private var activeCollection: SmartCollection?

    enum IndexTab: String, CaseIterable, Identifiable {
        case clips, markers, captions, roles
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .clips: return "film"
            case .markers: return "bookmark"
            case .captions: return "captions.bubble"
            case .roles: return "person.2.badge.gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Index", selection: $tab) {
                ForEach(IndexTab.allCases) { item in
                    Label(item.label, systemImage: item.symbol).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if tab != .roles {
                searchField
            }

            switch tab {
            case .clips: clipList
            case .markers: markerList
            case .captions: captionList
            case .roles: roleList
            }
        }
        .navigationTitle("Timeline index")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchField: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search name, note or prompt", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            if tab == .clips {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SmartCollection.starters) { collection in
                            let isOn = activeCollection?.id == collection.id
                            Button {
                                activeCollection = isOn ? nil : collection
                                Haptics.tap()
                            } label: {
                                Text(collection.name)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isOn ? Palette.accent.opacity(0.22) : Color(.tertiarySystemFill),
                                                in: Capsule())
                                    .foregroundStyle(isOn ? Palette.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Clips

    private var filteredClips: [PlacedItem] {
        doc.placed.filter { placed in
            guard !placed.item.content.isGap else { return false }
            if let activeCollection, !activeCollection.matches(placed) { return false }
            guard !query.isEmpty else { return true }
            let haystack = placed.item.name + " " + placed.item.notes
                + " " + (placed.item.provenance.prompt ?? "")
            return haystack.localizedCaseInsensitiveContains(query)
        }
        .sorted { $0.start < $1.start }
    }

    private var clipList: some View {
        List {
            Section {
                ForEach(filteredClips) { placed in
                    Button {
                        doc.select(placed.item.id)
                        Haptics.tap()
                    } label: {
                        clipRow(placed)
                    }
                    .listRowBackground(doc.selection.contains(placed.item.id)
                                       ? Palette.accent.opacity(0.12) : nil)
                }
            } footer: {
                Text("\(filteredClips.count) of \(doc.placed.count) items")
            }
        }
    }

    private func clipRow(_ placed: PlacedItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: placed.item.content.symbol)
                .foregroundStyle(placed.lane == 0 ? Palette.cool : Palette.good)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(placed.item.name).font(.subheadline).lineLimit(1)
                    if placed.item.isLocked {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !placed.item.isEnabled {
                        Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                    }
                    if placed.item.isAdjustmentLayer {
                        Image(systemName: "square.3.layers.3d").font(.caption2).foregroundStyle(Palette.accent)
                    }
                }
                HStack(spacing: 6) {
                    Text(placed.start.timecode(at: doc.rate))
                    Text(placed.item.role.label)
                    if let speed = placed.item.speedLabel { Text(speed) }
                    if placed.item.hasEffects { Image(systemName: "wand.and.rays") }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                if let rating = placed.item.rating {
                    Image(systemName: rating.symbol)
                        .font(.caption2)
                        .foregroundStyle(rating == .favorite ? Palette.good : Palette.bad)
                }
                if placed.item.cost > 0 {
                    Text(Money.compact(placed.item.cost))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Markers

    private var markerList: some View {
        let entries = doc.timeline.allMarkers.filter {
            query.isEmpty || $0.marker.name.localizedCaseInsensitiveContains(query)
        }
        return List {
            if entries.isEmpty {
                Text("No markers yet. Add one from the inspector while the playhead is parked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                Button {
                    doc.playhead = entry.at
                    Haptics.tap()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: entry.marker.kind.symbol)
                            .foregroundStyle(entry.marker.kind == .completed ? Palette.good : Palette.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.marker.name).font(.subheadline)
                            Text("\(entry.at.timecode(at: doc.rate)) · \(entry.itemName)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.marker.kind.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Captions

    private var captionEntries: [PlacedItem] {
        doc.placed
            .filter { $0.item.content.isCaption }
            .filter { placed in
                guard !query.isEmpty else { return true }
                return (placed.item.content.caption?.text ?? "")
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.start < $1.start }
    }

    private var captionList: some View {
        let warnings = doc.timeline.captionWarnings()
        return List {
            if captionEntries.isEmpty {
                Section {
                    Text("No captions yet.").font(.caption).foregroundStyle(.secondary)
                } footer: {
                    Text("Captions are timeline items, so they ripple with the picture instead of drifting in a sidecar.")
                }
            }
            ForEach(captionEntries) { placed in
                Button {
                    doc.select(placed.item.id)
                    Haptics.tap()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(placed.item.content.caption?.text ?? "")
                            .font(.subheadline)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(placed.start.timecode(at: doc.rate))
                            Text("→")
                            Text(placed.end.timecode(at: doc.rate))
                            if let language = placed.item.content.caption?.language {
                                Text(language.uppercased())
                            }
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                        if let warning = warnings.first(where: { $0.item.item.id == placed.item.id })?.warning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Roles

    private var roleList: some View {
        let groups = doc.timeline.itemsByRole()
        let mix = doc.timeline.checkMix()
        return List {
            Section {
                ForEach(groups, id: \.role.fcpxmlValue) { group in
                    let isOn = group.items.contains { $0.item.isEnabled }
                    HStack {
                        Image(systemName: group.role.kind == .audio ? "waveform" : "film")
                            .foregroundStyle(Palette.cool)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.role.label).font(.subheadline)
                            Text("\(group.items.count) clips")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            doc.setRoleEnabled(!isOn, roleName: group.role.name)
                            Haptics.tap()
                        } label: {
                            Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .foregroundStyle(isOn ? Palette.good : Palette.bad)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Roles")
            } footer: {
                Text("Roles are how a magnetic timeline organises itself — muting Music here is the equivalent of muting a track, without any tracks.")
            }

            Section {
                KeyValueRow(key: "Busiest moment",
                            value: mix.busiestMoment.timecode(at: doc.rate))
                KeyValueRow(key: "Overlapping sources", value: "\(mix.overlappingCount)")
                KeyValueRow(key: "Headroom", value: String(format: "%+.1f dB", mix.headroomDB))
                if mix.clippingRisk {
                    Label("Summed level exceeds unity at the busiest moment — pull something down or duck it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.bad)
                }
                Button {
                    var ducking = Ducking()
                    ducking.isEnabled = true
                    doc.applyDucking(ducking)
                    Haptics.success()
                } label: {
                    Label("Duck everything under dialogue", systemImage: "waveform.badge.minus")
                }
            } header: {
                Text("Mix check")
            } footer: {
                Text("A gain-staging estimate from the levels and fades on the cut — not a LUFS measurement, which needs rendered audio.")
            }
        }
    }
}
