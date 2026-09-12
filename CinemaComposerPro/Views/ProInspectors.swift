import SwiftUI

// MARK: - Effects

/// The effect stack. Order is meaning — the list renders top down, and a blur
/// above a grade blurs the graded picture.
struct EffectsInspector: View {
    @ObservedObject var doc: CutDocument
    var placed: PlacedItem
    @State private var showLibrary = false

    private var item: TimelineItem { placed.item }

    var body: some View {
        List {
            Section {
                if item.effects.isEmpty {
                    Text("No effects on this clip.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(item.effects.enumerated()), id: \.element.id) { index, effect in
                    EffectRow(doc: doc, effect: effect, index: index, total: item.effects.count)
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    let effect = item.effects[from]
                    doc.moveEffect(effect.id, to: destination > from ? destination - 1 : destination)
                }
                .onDelete { offsets in
                    for offset in offsets { doc.removeEffect(item.effects[offset].id) }
                }
            } header: {
                HStack {
                    Text("Effect stack")
                    Spacer()
                    Button { showLibrary = true } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } footer: {
                Text("Effects render top down. Drag to reorder — a blur above a grade blurs the graded picture, not the raw one.")
            }

            if doc.selection.count > 1 {
                Section {
                    Button {
                        doc.pasteAttributesFromPrimary()
                        Haptics.success()
                    } label: {
                        Label("Paste look onto \(doc.selection.count - 1) other clips",
                              systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    Text("Copies the effect stack and grade from the first selected clip to the rest.")
                }
            }

            if item.isAdjustmentLayer {
                let affected = doc.timeline.itemsAffected(byAdjustmentLayer: item.id)
                Section {
                    Label("Adjustment layer", systemImage: "square.3.layers.3d")
                        .foregroundStyle(Palette.accent)
                    KeyValueRow(key: "Clips affected", value: "\(affected.count)")
                } footer: {
                    Text("Everything on a lower lane under this span inherits these effects. Final Cut has no native equivalent — it makes you build a Motion template.")
                }
            } else {
                Section {
                    Button {
                        doc.addAdjustmentLayerOverSelection()
                        Haptics.success()
                    } label: {
                        Label("Add adjustment layer over selection", systemImage: "square.3.layers.3d")
                    }
                }
            }
        }
        .sheet(isPresented: $showLibrary) {
            EffectLibrarySheet(doc: doc, isPresented: $showLibrary)
        }
    }
}

private struct EffectRow: View {
    @ObservedObject var doc: CutDocument
    var effect: Effect
    var index: Int
    var total: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    doc.toggleEffect(effect.id, enabled: !effect.isEnabled)
                    Haptics.tap()
                } label: {
                    Image(systemName: effect.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(effect.isEnabled ? Palette.good : .secondary)
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 1) {
                    Text(effect.name).font(.subheadline)
                    Text(effect.category.label).font(.caption2).foregroundStyle(.secondary)
                }

                Spacer()

                if effect.hasAnimation {
                    Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(Palette.accent)
                }
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                ForEach(effect.parameters) { parameter in
                    parameterControl(parameter)
                }
                .padding(.leading, 26)
            }
        }
        .opacity(effect.isEnabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func parameterControl(_ parameter: EffectParameter) -> some View {
        switch parameter.value {
        case .number(let animatable):
            CommitSlider(label: parameter.name,
                         range: parameter.minimum...parameter.maximum,
                         step: parameter.step,
                         format: { String(format: "%.1f\(parameter.unit)", $0) },
                         initial: animatable.constant) { value in
                doc.setEffectParameter(value, parameterID: parameter.id, effectID: effect.id)
            }
        case .choice(let selected, let options):
            HStack {
                Text(parameter.name).font(.caption)
                Spacer()
                Text(options.indices.contains(selected) ? options[selected] : "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .toggle(let on):
            HStack {
                Text(parameter.name).font(.caption)
                Spacer()
                Image(systemName: on ? "checkmark" : "xmark").font(.caption2)
            }
        case .text(let value):
            HStack {
                Text(parameter.name).font(.caption)
                Spacer()
                Text(value.isEmpty ? "none" : value).font(.caption).foregroundStyle(.secondary)
            }
        case .color:
            Text(parameter.name).font(.caption)
        }
    }
}

private struct EffectLibrarySheet: View {
    @ObservedObject var doc: CutDocument
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(EffectLibrary.byCategory(), id: \.0.id) { category, effects in
                    Section(category.label) {
                        ForEach(effects) { effect in
                            Button {
                                doc.addEffect(effect)
                                Haptics.success()
                                isPresented = false
                            } label: {
                                Label(effect.name, systemImage: category.symbol)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Colour

/// Three-way grading plus the global controls, all keyframable.
struct ColorInspector: View {
    @ObservedObject var doc: CutDocument
    var placed: PlacedItem

    private var color: ColorCorrection { placed.item.color }

    var body: some View {
        List {
            Section("Global") {
                CommitSlider(label: "Exposure", range: -2...2, step: 0.05,
                             format: { String(format: "%+.2f", $0) },
                             initial: color.exposure.constant) { value in
                    doc.updateColor { $0.exposure.constant = value }
                }
                CommitSlider(label: "Contrast", range: -100...100, step: 1,
                             format: { String(format: "%+.0f", $0) },
                             initial: color.contrast.constant) { value in
                    doc.updateColor { $0.contrast.constant = value }
                }
                CommitSlider(label: "Saturation", range: 0...200, step: 1,
                             format: { String(format: "%.0f%%", $0) },
                             initial: color.saturation.constant) { value in
                    doc.updateColor { $0.saturation.constant = value }
                }
                CommitSlider(label: "Temperature", range: -100...100, step: 1,
                             format: { String(format: "%+.0f", $0) },
                             initial: color.temperature.constant) { value in
                    doc.updateColor { $0.temperature.constant = value }
                }
                CommitSlider(label: "Tint", range: -100...100, step: 1,
                             format: { String(format: "%+.0f", $0) },
                             initial: color.tint.constant) { value in
                    doc.updateColor { $0.tint.constant = value }
                }
            }

            wheelSection("Shadows", keyPath: \.shadows)
            wheelSection("Midtones", keyPath: \.midtones)
            wheelSection("Highlights", keyPath: \.highlights)

            Section {
                Button(role: .destructive) {
                    doc.resetColor()
                    Haptics.tap()
                } label: {
                    Label("Reset grade", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text(color.isNeutral
                     ? "This clip is ungraded."
                     : "Graded. Use Effects → Paste look to carry this across the scene.")
            }
        }
    }

    private func wheelSection(_ title: String,
                              keyPath: WritableKeyPath<ColorCorrection, ColorWheel>) -> some View {
        let wheel = color[keyPath: keyPath]
        return Section(title) {
            CommitSlider(label: "Hue", range: 0...360, step: 1,
                         format: { String(format: "%.0f°", $0) },
                         initial: wheel.hueAngle.constant) { value in
                doc.updateColor { $0[keyPath: keyPath].hueAngle.constant = value }
            }
            CommitSlider(label: "Strength", range: 0...100, step: 1,
                         format: { String(format: "%.0f%%", $0) },
                         initial: wheel.saturation.constant) { value in
                doc.updateColor { $0[keyPath: keyPath].saturation.constant = value }
            }
            CommitSlider(label: "Brightness", range: -100...100, step: 1,
                         format: { String(format: "%+.0f", $0) },
                         initial: wheel.brightness.constant) { value in
                doc.updateColor { $0[keyPath: keyPath].brightness.constant = value }
            }
        }
    }
}

// MARK: - Mixer

/// EQ, dynamics and ducking — the channel strip a mix needs.
struct MixerInspector: View {
    @ObservedObject var doc: CutDocument
    var placed: PlacedItem

    private var item: TimelineItem { placed.item }
    private var processing: AudioProcessing { item.audioProcessing }

    var body: some View {
        List {
            Section {
                EQCurveView(bands: processing.equalizer)
                    .frame(height: 90)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                ForEach(processing.equalizer) { band in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(band.kind.label).font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(band.frequency)) Hz")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if band.kind.usesGain {
                                Text(String(format: "%+.1f dB", band.gainDB))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(band.gainDB >= 0 ? Palette.good : Palette.bad)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    var bands = processing.equalizer
                    bands.remove(atOffsets: offsets)
                    update { $0.audioProcessing.equalizer = bands }
                }

                HStack {
                    Button("Voice preset") {
                        update { $0.audioProcessing.equalizer = EQBand.presetVoice }
                        Haptics.tap()
                    }
                    Spacer()
                    Button("Music bed") {
                        update { $0.audioProcessing.equalizer = EQBand.presetMusicBed }
                        Haptics.tap()
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            } header: {
                Text("Equaliser")
            } footer: {
                Text("The curve is the summed response of every band — enough to see what you are doing before anything is rendered.")
            }

            Section("Compressor") {
                Toggle("Enabled", isOn: Binding(
                    get: { processing.compressor.isEnabled },
                    set: { on in update { $0.audioProcessing.compressor.isEnabled = on } }
                ))
                if processing.compressor.isEnabled {
                    CommitSlider(label: "Threshold", range: -40...0, step: 0.5,
                                 format: { String(format: "%.1f dB", $0) },
                                 initial: processing.compressor.thresholdDB) { value in
                        update { $0.audioProcessing.compressor.thresholdDB = value }
                    }
                    CommitSlider(label: "Ratio", range: 1...20, step: 0.5,
                                 format: { String(format: "%.1f:1", $0) },
                                 initial: processing.compressor.ratio) { value in
                        update { $0.audioProcessing.compressor.ratio = value }
                    }
                    CommitSlider(label: "Makeup gain", range: 0...24, step: 0.5,
                                 format: { String(format: "%+.1f dB", $0) },
                                 initial: processing.compressor.makeupGainDB) { value in
                        update { $0.audioProcessing.compressor.makeupGainDB = value }
                    }
                    KeyValueRow(key: "−6 dB in",
                                value: String(format: "%.1f dB out",
                                              processing.compressor.outputDB(forInput: -6)))
                }
            }

            Section {
                Toggle("Duck under dialogue", isOn: Binding(
                    get: { processing.ducking.isEnabled },
                    set: { on in
                        update { $0.audioProcessing.ducking.isEnabled = on }
                        if on {
                            var ducking = processing.ducking
                            ducking.isEnabled = true
                            doc.applyDucking(ducking)
                        }
                    }
                ))
                if processing.ducking.isEnabled {
                    CommitSlider(label: "Duck by", range: -30...0, step: 1,
                                 format: { String(format: "%.0f dB", $0) },
                                 initial: processing.ducking.amountDB) { value in
                        update { $0.audioProcessing.ducking.amountDB = value }
                    }
                }
            } header: {
                Text("Ducking")
            } footer: {
                Text("Writes real volume keyframes wherever dialogue plays, so the result is an edit you can see and adjust — not a hidden setting.")
            }

            Section("Delivery") {
                ForEach(LoudnessTarget.all, id: \.name) { target in
                    KeyValueRow(key: target.name,
                                value: String(format: "peak %.0f dBTP", target.truePeakDB))
                }
            }
        }
    }

    private func update(_ change: @escaping (inout TimelineItem) -> Void) {
        let id = item.id
        doc.perform("Mix") { timeline in
            try timeline.update(id: id) { change(&$0) }
        }
    }
}

/// The summed EQ response, drawn across the audible band on a log scale.
private struct EQCurveView: View {
    var bands: [EQBand]

    var body: some View {
        Canvas { context, size in
            let minimumHz = 20.0
            let maximumHz = 20000.0
            let range = 24.0

            func point(_ index: Int, steps: Int) -> CGPoint {
                let t = Double(index) / Double(steps)
                let frequency = minimumHz * pow(maximumHz / minimumHz, t)
                let db = bands.reduce(0) { $0 + $1.responseDB(at: frequency) }
                let clamped = Swift.min(Swift.max(db, -range), range)
                let y = size.height * (0.5 - clamped / (range * 2))
                return CGPoint(x: size.width * t, y: y)
            }

            // Zero line.
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: size.height / 2))
            zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(zero, with: .color(Color(.tertiaryLabel)),
                           style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

            guard !bands.isEmpty else { return }
            let steps = 96
            var curve = Path()
            curve.move(to: point(0, steps: steps))
            for index in 1...steps { curve.addLine(to: point(index, steps: steps)) }
            context.stroke(curve, with: .color(Palette.cool), lineWidth: 2)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Equaliser response curve, \(bands.count) bands")
    }
}
