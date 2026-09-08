import SwiftUI
import StoreKit

/// The paywall. The Cutting Room — the actual NLE where a producer cuts their
/// film — is the Pro feature. Planning, budgeting, and dry runs stay free so
/// a new user can learn the whole pipeline before paying.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var products: [Product] = []
    @State private var selectedProductID: String?
    @State private var isPurchasing = false
    @State private var message: String?
    @State private var loadFailed = false

    /// Feature rows the buyer sees. Keep in sync with what the gates protect.
    private static let features: [(icon: String, title: String, detail: String)] = [
        ("film.stack", "The Cutting Room", "The full NLE: blade, ripple, slip, take stacks, regenerate — every clip carries its cost."),
        ("waveform.path", "Live runs", "Call real AI vendors for video, voice and score under a hard spend cap."),
        ("square.and.arrow.up", "Every export", "EDL, FCPXML and OTIO carry the cut into Resolve, Premiere or Final Cut — with provenance."),
        ("dollarsign.circle", "Cost-honest takes", "Swap takes, see what the cut costs, and what wasted takes burned."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 52))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 24)

                    Text("Cinema Composer Pro")
                        .font(.title2.bold())

                    Text("The cutting room is where the picture gets made.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Self.features, id: \.icon) { feature in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: feature.icon)
                                    .font(.title3)
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title).font(.subheadline.bold())
                                    Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    if loadFailed {
                        VStack(spacing: 10) {
                            Text("Couldn't reach the App Store.")
                                .font(.subheadline)
                            Text(message ?? "Check your connection and try again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Try again") { Task { await loadProducts() } }
                                .buttonStyle(.bordered)
                        }
                    } else if isPurchasing {
                        ProgressView("Completing purchase…")
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(products, id: \.id) { product in
                                planRow(product)
                            }
                            if products.isEmpty {
                                ProgressView("Loading plans…")
                                    .padding(.vertical, 12)
                            }
                            Button {
                                Task { await purchaseSelected() }
                            } label: {
                                Text("Continue")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                            .disabled(selectedProductID == nil)
                        }
                        .padding(.horizontal, 4)
                    }

                    Button("Restore purchases") {
                        Task { await restore() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Cinema Composer Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadProducts() }
        .alert("Purchase failed", isPresented: Binding(
            get: { message != nil && !loadFailed },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - Rows

    private func planRow(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isBestValue = product.id == EntitlementManager.ProductID.annual
        return Button {
            selectedProductID = product.id
            Haptics.tap()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline.bold())
                        if isBestValue {
                            Text("Best value")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Palette.good, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    if let trial = trialText(for: product) {
                        Text(trial)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.subheadline.bold().monospacedDigit())
            }
            .padding(12)
            .background(
                isSelected ? Palette.accent.opacity(0.12) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Palette.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
    }

    private func trialText(for product: Product) -> String? {
        guard let subscription = product.subscription,
              let intro = subscription.introductoryOffer else { return nil }
        let freeTrial: Bool
        switch intro.paymentMode {
        case .freeTrial: freeTrial = true
        default: freeTrial = false
        }
        guard freeTrial else { return nil }
        let period: String
        switch intro.period.unit {
        case .day: period = intro.period.value == 1 ? "day" : "\(intro.period.value) days"
        case .week: period = intro.period.value == 1 ? "week" : "\(intro.period.value) weeks"
        case .month: period = intro.period.value == 1 ? "month" : "\(intro.period.value) months"
        case .year: period = intro.period.value == 1 ? "year" : "\(intro.period.value) years"
        @unknown default: period = "period"
        }
        return "\(period) free trial"
    }

    // MARK: - Store actions

    private func loadProducts() async {
        loadFailed = false
        do {
            products = try await Product.products(for: EntitlementManager.ProductID.all)
            if selectedProductID == nil {
                selectedProductID = products.first?.id
            }
        } catch {
            loadFailed = true
            message = error.localizedDescription
        }
    }

    private func purchaseSelected() async {
        guard let id = selectedProductID,
              let product = products.first(where: { $0.id == id }) else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await EntitlementManager.shared.purchase(product)
            Haptics.success()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        await EntitlementManager.shared.restorePurchases()
        if EntitlementManager.shared.isPro {
            Haptics.success()
            dismiss()
        } else {
            message = "No previous purchases found for this Apple ID."
        }
    }
}