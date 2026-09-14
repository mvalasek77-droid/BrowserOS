import SwiftUI
import StoreKit

/// The legal links App Review requires on any screen that sells an
/// auto-renewable subscription (Guideline 3.1.2). Both must be reachable from
/// the paywall itself — having them only on the App Store listing is the most
/// common reason a subscription app is rejected.
enum LegalLinks {

    /// Apple's standard End User Licence Agreement. Correct to use unless you
    /// upload a custom licence agreement in App Store Connect, in which case
    /// point this at yours instead.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// ⚠️ REPLACE BEFORE SUBMITTING.
    ///
    /// This must be a live, publicly reachable page — App Review opens it. The
    /// same URL also goes in App Store Connect under App Privacy. A 404 here
    /// fails review just as surely as a missing link.
    static let privacyPolicy = URL(string: "https://mvalasek77-droid.github.io/cinema-composer-privacy.html")!

    /// True once the placeholder above has actually been replaced.
    static var isPrivacyPolicyConfigured: Bool {
        !(privacyPolicy.host ?? "").localizedCaseInsensitiveContains("REPLACE-ME")
    }

    /// The disclosure Apple requires beside the purchase control: what is
    /// charged, when it renews, and how to stop it.
    static let subscriptionTerms = """
        Payment is charged to your Apple Account at confirmation of purchase. \
        A subscription renews automatically unless auto-renew is turned off at \
        least 24 hours before the end of the current period, and your account \
        is charged for renewal within 24 hours of the period ending. Manage or \
        cancel in Settings › Apple Account › Subscriptions. Lifetime is a \
        one-time purchase and does not renew.
        """
}

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

                    legalFooter
                        .padding(.top, 4)
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

    // MARK: - Legal

    /// Restore, the renewal disclosure, and the two links Guideline 3.1.2
    /// requires. Kept together so none of it can be dropped by accident.
    private var legalFooter: some View {
        VStack(spacing: 12) {
            Button("Restore purchases") {
                Task { await restore() }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.cool)

            Text(LegalLinks.subscriptionTerms)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Link("Terms of Use", destination: LegalLinks.termsOfUse)
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
            }
            .font(.caption.weight(.medium))
            .tint(Palette.cool)

            #if DEBUG
            // Impossible to miss in development, and compiled out of the build
            // that ships — so the placeholder cannot reach App Review silently.
            if !LegalLinks.isPrivacyPolicyConfigured {
                Label("Set LegalLinks.privacyPolicy to a live URL before submitting.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.bad)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(Palette.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            #endif
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
                VStack(alignment: .trailing, spacing: 1) {
                    // Price alone is not enough disclosure — the period has to
                    // be visible before purchase, not implied by the plan name.
                    Text(priceWithPeriod(for: product))
                        .font(.subheadline.bold().monospacedDigit())
                    if let equivalent = monthlyEquivalent(for: product) {
                        Text(equivalent)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
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
        .accessibilityLabel("\(product.displayName), \(priceWithPeriod(for: product))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// "$9.99 / month", or the bare price for the one-time lifetime unlock.
    private func priceWithPeriod(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "\(period.value) days"
        case .week: unit = period.value == 1 ? "week" : "\(period.value) weeks"
        case .month: unit = period.value == 1 ? "month" : "\(period.value) months"
        case .year: unit = period.value == 1 ? "year" : "\(period.value) years"
        @unknown default: return product.displayPrice
        }
        return "\(product.displayPrice) / \(unit)"
    }

    /// What an annual plan works out at per month, so the saving is legible
    /// without the buyer doing the arithmetic.
    private func monthlyEquivalent(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod,
              period.unit == .year, period.value == 1 else { return nil }
        // StoreKit's own format style already carries the product's currency
        // and the storefront's locale, so this stays correct in every region.
        let monthly = product.price / 12
        return "\(monthly.formatted(product.priceFormatStyle)) / month"
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