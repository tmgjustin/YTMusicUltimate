import Foundation
import Combine

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published var portfolio: Portfolio = Portfolio(assets: [])
    @Published var snapshots: [PortfolioSnapshot] = []
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil

    private let storage = StorageService.shared
    private let priceService = PriceService.shared

    init() {
        portfolio = Portfolio(assets: storage.loadAssets())
        snapshots = storage.loadSnapshots()
    }

    // MARK: - Asset CRUD

    func addAsset(_ asset: Asset) {
        portfolio.assets.append(asset)
        save()
    }

    func updateAsset(_ asset: Asset) {
        guard let idx = portfolio.assets.firstIndex(where: { $0.id == asset.id }) else { return }
        portfolio.assets[idx] = asset
        save()
    }

    func deleteAssets(at offsets: IndexSet, type: AssetType? = nil) {
        if let type {
            var filtered = portfolio.assets.filter { $0.type == type }
            filtered.remove(atOffsets: offsets)
            portfolio.assets = portfolio.assets.filter { $0.type != type } + filtered
        } else {
            portfolio.assets.remove(atOffsets: offsets)
        }
        save()
    }

    // MARK: - Price Refresh

    func refreshPrices() async {
        isRefreshing = true
        errorMessage = nil
        let updates = await priceService.refreshPrices(for: portfolio.assets)
        for i in portfolio.assets.indices {
            if let newPrice = updates[portfolio.assets[i].id] {
                portfolio.assets[i].currentPrice = newPrice
                portfolio.assets[i].lastUpdated = Date()
            }
        }
        takeSnapshot()
        save()
        isRefreshing = false
    }

    // MARK: - Snapshot

    func takeSnapshot() {
        let snap = PortfolioSnapshot.from(portfolio)
        snapshots.append(snap)
        storage.saveSnapshot(snap)
    }

    // MARK: - Helpers

    private func save() {
        storage.saveAssets(portfolio.assets)
    }

    func assetsForType(_ type: AssetType) -> [Asset] {
        portfolio.assets(ofType: type)
    }

    func valueForType(_ type: AssetType) -> Double {
        assetsForType(type).reduce(0) { $0 + $1.totalValue }
    }
}
