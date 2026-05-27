import Foundation

final class StorageService {
    static let shared = StorageService()
    private init() {}

    private let assetsKey   = "mp_assets"
    private let snapshotsKey = "mp_snapshots"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Assets

    func saveAssets(_ assets: [Asset]) {
        if let data = try? encoder.encode(assets) {
            UserDefaults.standard.set(data, forKey: assetsKey)
        }
    }

    func loadAssets() -> [Asset] {
        guard let data = UserDefaults.standard.data(forKey: assetsKey),
              let assets = try? decoder.decode([Asset].self, from: data)
        else { return [] }
        return assets
    }

    // MARK: - Snapshots

    func saveSnapshot(_ snapshot: PortfolioSnapshot) {
        var snapshots = loadSnapshots()
        snapshots.append(snapshot)
        // 最多保留 365 筆
        if snapshots.count > 365 { snapshots.removeFirst(snapshots.count - 365) }
        if let data = try? encoder.encode(snapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsKey)
        }
    }

    func loadSnapshots() -> [PortfolioSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotsKey),
              let snapshots = try? decoder.decode([PortfolioSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: assetsKey)
        UserDefaults.standard.removeObject(forKey: snapshotsKey)
    }
}
