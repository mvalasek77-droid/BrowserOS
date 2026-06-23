import SwiftUI
import StoreKit

// MARK: - PaywallView
//
// Presents the Pro upgrade options to the user. Loads live product info from
// StoreKit 2 so prices are always correct across storefronts. On watchOS the
// view is simplified (Apple Watch can't complete IAP directly — the user is
// prompted to open the iPhone app).

struct PaywallView: View {
    @StateObject private var entitlement = EntitlementManager.shared
    @Environment(\.dismiss) private var dismiss

    // StoreKit products
    @State private var products: [Product] = []
    @State private var monthlyProduct: Product?
    @State private var annualProduct: Product?
    @State private var lifetimeProduct: Product?
    @State private var isLoading: Bool = true
    @State private var purchaseError: String?
    @State private var isPurchasing: Bool = false

    init() {}

    var body: some View {
        #if os(iOS)
        iosBody
        #else
        watchBody
        #endif
    }

    // MARK: - iOS

    #if os(iOS)
    private var iosBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SteroidBrand.Spacing.lg) {
                    headerSection
                    featureList
                    pricingSection
                    restoreButton
                    legalText
                }
                .padding(.horizontal, SteroidBrand.Spacing.lg)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("SteroidOS Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Purchase Error", isPresented: .constant(purchaseError != nil), actions: {
                Button("OK") { purchaseError = nil }
            }, message: {
                Text(purchaseError ?? "")
            })
        }
        .task { await loadProducts() }
    }

    private var headerSection: some View {
        VStack(spacing: SteroidBrand.Spacing.sm) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow.gradient)
                .padding(.top, SteroidBrand.Spacing.md)

            Text("Unlock SteroidOS Pro")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("Full watch mirroring, site-specific extractors, reader mode, media detection, and every future feature.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SteroidBrand.Spacing.lg)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: SteroidBrand.Spacing.sm) {
            PaywallFeatureRow(icon: "applewatch", title: "Watch Mirroring", subtitle: "Full page content on your wrist")
            PaywallFeatureRow(icon: "doc.text.magnifyingglass", title: "Reader Mode", subtitle: "Distraction-free articles")
            PaywallFeatureRow(icon: "play.rectangle.fill", title: "Media Detection", subtitle: "YouTube & video player")
            PaywallFeatureRow(icon: "bookmark.fill", title: "Sync Everything", subtitle: "Bookmarks, history & settings")
            PaywallFeatureRow(icon: "sparkles", title: "All Future Features", subtitle: "Included at no extra cost")
        }
        .padding(SteroidBrand.Spacing.lg)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: SteroidBrand.Radius.lg, style: .continuous))
    }

    private var pricingSection: some View {
        VStack(spacing: SteroidBrand.Spacing.sm) {
            if isLoading {
                ProgressView("Loading pricing…")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                if let monthly = monthlyProduct {
                    PaywallPlanCard(
                        title: "Monthly",
                        price: monthly.displayPrice,
                        period: "/month",
                        trialText: "1 week free",
                        isFeatured: false
                    ) {
                        Task { await purchase(monthly) }
                    }
                }
                if let annual = annualProduct {
                    PaywallPlanCard(
                        title: "Annual",
                        price: annual.displayPrice,
                        period: "/year",
                        trialText: "1 month free",
                        isFeatured: true,
                        badgeText: "BEST VALUE"
                    ) {
                        Task { await purchase(annual) }
                    }
                }
                if let lifetime = lifetimeProduct {
                    PaywallPlanCard(
                        title: "Lifetime",
                        price: lifetime.displayPrice,
                        period: "one-time",
                        trialText: nil,
                        isFeatured: false
                    ) {
                        Task { await purchase(lifetime) }
                    }
                }
            }
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await entitlement.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
        }
        .padding(.top, SteroidBrand.Spacing.sm)
    }

    private var legalText: some View {
        Text("Subscriptions auto-renew unless cancelled at least 24 hours before the period ends. Manage in Settings → Apple ID → Subscriptions.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, SteroidBrand.Spacing.xl)
    }
    #endif

    // MARK: - watchOS

    #if os(watchOS)
    private var watchBody: some View {
        ScrollView {
            VStack(spacing: SteroidBrand.Spacing.md) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.yellow)

                Text("SteroidOS Pro")
                    .font(.headline)

                Text("Open the iPhone app to subscribe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 4) {
                    PaywallFeatureRow(icon: "applewatch", title: "Mirroring", subtitle: nil)
                    PaywallFeatureRow(icon: "doc.text", title: "Reader Mode", subtitle: nil)
                    PaywallFeatureRow(icon: "play.fill", title: "Media", subtitle: nil)
                }

                Button("Close") { dismiss() }
                    .tint(.blue)
            }
            .padding(.horizontal, 4)
        }
    }
    #endif

    // MARK: - Actions

    private func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: EntitlementManager.ProductID.all)
            await MainActor.run {
                self.products = storeProducts
                self.monthlyProduct  = storeProducts.first { $0.id == EntitlementManager.ProductID.monthly }
                self.annualProduct   = storeProducts.first { $0.id == EntitlementManager.ProductID.annual }
                self.lifetimeProduct = storeProducts.first { $0.id == EntitlementManager.ProductID.lifetime }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.purchaseError = "Couldn't load pricing: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func purchase(_ product: Product) async {
        await MainActor.run { isPurchasing = true }
        defer { Task { @MainActor in isPurchasing = false } }

        do {
            try await entitlement.purchase(product)
            await MainActor.run {
                if entitlement.isPro {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                self.purchaseError = error.localizedDescription
            }
        }
    }
}

// MARK: - Feature Row

struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: SteroidBrand.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18))
        }
        #if os(watchOS)
        .padding(.vertical, 2)
        #endif
    }
}

// MARK: - Plan Card (iOS)

#if os(iOS)
struct PaywallPlanCard: View {
    let title: String
    let price: String
    let period: String
    let trialText: String?
    let isFeatured: Bool
    var badgeText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                        if let badgeText {
                            Text(badgeText)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                        }
                    }
                    if let trialText {
                        Text("\(trialText) trial")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(.title3.bold())
                    Text(period)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(SteroidBrand.Spacing.md)
            .background(isFeatured ? Color.blue.opacity(0.08) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: SteroidBrand.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SteroidBrand.Radius.md, style: .continuous)
                    .stroke(isFeatured ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
#endif