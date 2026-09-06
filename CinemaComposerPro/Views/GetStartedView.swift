import SwiftUI

struct GetStartedView: View {
    @EnvironmentObject private var model: ProductionViewModel
    @Binding var isPresented: Bool
    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep: Int, CaseIterable {
        case welcome, describe, tools, keys, strategy, ready

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .describe: return "Your Picture"
            case .tools: return "Video Tools"
            case .keys: return "API Keys"
            case .strategy: return "Strategy"
            case .ready: return "Ready"
            }
        }

        var icon: String {
            switch self {
            case .welcome: return "film.stack"
            case .describe: return "pencil.and.list.clipboard"
            case .tools: return "square.stack.3d.up"
            case .keys: return "key"
            case .strategy: return "bolt.badge.clock"
            case .ready: return "checkmark.seal"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                    .padding(.horizontal)
                    .padding(.top, 8)

                TabView(selection: $step) {
                    welcomeCard.tag(OnboardingStep.welcome)
                    describeCard.tag(OnboardingStep.describe)
                    toolsCard.tag(OnboardingStep.tools)
                    keysCard.tag(OnboardingStep.keys)
                    strategyCard.tag(OnboardingStep.strategy)
                    readyCard.tag(OnboardingStep.ready)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: step)

                navigationBar
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        finishOnboarding()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Palette.accent : Color(.tertiarySystemFill))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if step.rawValue > 0 {
                Button {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .tint(.secondary)
            }

            Spacer()

            if step == .ready {
                Button {
                    finishOnboarding()
                } label: {
                    Label("Start producing", systemImage: "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            } else {
                Button {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .ready }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeCard: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "film.stack")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 40)

                Text("Cinema Composer Pro")
                    .font(.title.bold())

                Text("The conductor for your AI film orchestra")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "dollarsign.circle", title: "Producer",
                              detail: "Price the entire picture before spending a cent")
                    featureRow(icon: "waveform.path", title: "Conductor",
                              detail: "Run AI tools in the right order under a hard spend cap")
                    featureRow(icon: "bolt.badge.clock", title: "Optimizer",
                              detail: "Six efficiency passes that prove what each one saves")
                    featureRow(icon: "film.stack", title: "Cutting Room",
                              detail: "NLE timeline where every clip remembers what made it")
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                FinalScriptAICard(style: .full)
            }
            .padding()
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Describe the picture

    private var describeCard: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionHeader(icon: "pencil.and.list.clipboard",
                              title: "Describe your picture",
                              subtitle: "Every slider moves real money. Start rough — you can tune it later.")

                VStack(spacing: 12) {
                    TextField("Title", text: $model.spec.title)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    LabelledSlider(label: "Runtime",
                                   value: $model.spec.runtimeMinutes,
                                   range: 1...210,
                                   step: 1,
                                   display: "\(Int(model.spec.runtimeMinutes)) min")

                    Picker("Genre", selection: $model.spec.genre) {
                        ForEach(Genre.allCases) { genre in Text(genre.label).tag(genre) }
                    }
                    .pickerStyle(.menu)

                    Picker("Tier", selection: $model.spec.tier) {
                        ForEach(ProductionTier.allCases) { tier in Text(tier.label).tag(tier) }
                    }
                    .pickerStyle(.menu)

                    templatePicker
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                livePreview
            }
            .padding()
        }
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or start from a template:")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ProductionTemplate.allCases) { template in
                        Button {
                            model.spec = template.spec
                            Haptics.success()
                        } label: {
                            VStack(spacing: 4) {
                                Text(template.name)
                                    .font(.caption.bold())
                                Text(template.blurb)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 120)
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Video tools

    private var toolsCard: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionHeader(icon: "square.stack.3d.up",
                              title: "Your video tools",
                              subtitle: "These are the AI engines that generate your shots. Add more from the marketplace or import a tool pack.")

                let videoTools = model.registry.tools.filter { $0.capabilities.contains(Capability.videoTextToVideo) }

                VStack(spacing: 0) {
                    ForEach(videoTools) { tool in
                        videoToolRow(tool)
                        if tool.id != videoTools.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                NavigationLink {
                    VideoToolMarketplaceView()
                } label: {
                    Label("Browse video tool marketplace", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Palette.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }

    private func videoToolRow(_ tool: AITool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tool.keyRef.flatMap { model.keys.has($0) ? Palette.good : nil } ?? Color(.tertiaryLabel))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.subheadline)
                HStack(spacing: 6) {
                    Text(tool.vendor)
                    Text("q\(Int(tool.quality * 100))")
                    Text(Money.rate(tool.pricing.rate) + "/s")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let ref = tool.keyRef {
                if model.keys.has( ref) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.good)
                } else {
                    Text("needs key")
                        .font(.caption2)
                        .foregroundStyle(Palette.accent)
                }
            } else {
                Text("local")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Step 4: Keys

    private var keysCard: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionHeader(icon: "key",
                              title: "Connect your API keys",
                              subtitle: "Keys go into the iOS Keychain — never synced, never exported. Without a key, a tool works in dry-run only.")

                let refs = model.registry.keyRefs

                VStack(spacing: 0) {
                    ForEach(refs, id: \.self) { ref in
                        keyRefRow(ref)
                        if ref != refs.last {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                NavigationLink {
                    KeysView()
                } label: {
                    Label("Manage all keys", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                Text("You can add keys later from Setup > API Keys. Dry runs work without any.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func keyRefRow(_ ref: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: model.keys.has( ref) ? "key.fill" : "key")
                .foregroundStyle(model.keys.has( ref) ? Palette.good : Color(.tertiaryLabel))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(ref).font(.subheadline)
                let tools = model.registry.tools.filter { $0.keyRef == ref }
                Text("Used by: " + tools.map(\.name).prefix(3).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if model.keys.has( ref) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.good)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Step 5: Strategy

    private var strategyCard: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionHeader(icon: "bolt.badge.clock",
                              title: "Pick your strategy",
                              subtitle: "This shapes every decision the conductor makes — which tool to pick, how many takes to burn, where to spend the money.")

                ForEach(PlanningStrategy.allCases) { strategy in
                    Button {
                        model.strategy = strategy
                        Haptics.tap()
                    } label: {
                        strategyRow(strategy, selected: model.strategy == strategy)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    KeyValueRow(key: "Estimated total", value: Money.compact(model.budget.total))
                    KeyValueRow(key: "Shots", value: "\(model.budget.shotCount)")
                    KeyValueRow(key: "Wall clock", value: Clock.duration(model.budget.schedule.wallClockSeconds))
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }

    private func strategyRow(_ strategy: PlanningStrategy, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "circle.inset.filled" : "circle")
                .foregroundStyle(selected ? Palette.accent : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(strategy.label).font(.subheadline.bold())
                let w = strategy.weights
                Text("Cost \(Int(w.cost * 100))% · Speed \(Int(w.time * 100))% · Quality \(Int(w.quality * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(selected ? Palette.accent.opacity(0.12) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Step 6: Ready

    private var readyCard: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.good)
                    .padding(.top, 40)

                Text("You're ready to produce")
                    .font(.title2.bold())

                VStack(spacing: 8) {
                    readinessRow(label: "Picture", value: model.spec.title, ok: !model.spec.title.isEmpty)
                    readinessRow(label: "Runtime", value: "\(Int(model.spec.runtimeMinutes)) min", ok: true)
                    readinessRow(label: "Genre", value: model.spec.genre.label, ok: true)
                    readinessRow(label: "Tier", value: model.spec.tier.label, ok: true)
                    readinessRow(label: "Strategy", value: model.strategy.label, ok: true)

                    let keyCount = model.registry.keyRefs.filter { model.keys.has( $0) }.count
                    let keyTotal = model.registry.keyRefs.count
                    readinessRow(label: "API keys", value: "\(keyCount)/\(keyTotal)", ok: keyCount > 0)

                    readinessRow(label: "Budget", value: Money.compact(model.budget.total), ok: model.budget.isComplete)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if !model.budget.isComplete {
                    Text("Some departments are unstaffed — the budget is a floor, not a quote. You can still produce; add keys or tools later to fill the gaps.")
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }

    private func readinessRow(label: String, value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Palette.good : .secondary)
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    // MARK: - Live preview (bottom of describe step)

    private var livePreview: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Live estimate").font(.caption.bold())
                Spacer()
            }
            StatGrid(stats: [
                ("Total", Money.compact(model.budget.total)),
                ("Shots", "\(model.budget.shotCount)"),
                ("Per minute", Money.string(model.budget.unitEconomics.perRuntimeMinute)),
                ("Wall clock", Clock.duration(model.budget.schedule.wallClockSeconds)),
            ])
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(Palette.accent)
            Text(title).font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "ccp_onboarding_complete")
        model.save()
        Haptics.success()
        isPresented = false
    }
}
