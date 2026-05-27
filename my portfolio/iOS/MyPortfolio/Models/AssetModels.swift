import Foundation

enum AssetType: String, Codable, CaseIterable {
    case stock = "股票"
    case crypto = "加密貨幣"
    case cash = "現金"
    case realEstate = "不動產"
    case other = "其他"
}

struct Asset: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var type: AssetType
    var quantity: Double
    var costBasis: Double        // 每單位成本價（TWD）
    var currentPrice: Double     // 每單位現價（TWD）
    var currency: String         // "TWD" / "USD" / "USDT"
    var lastUpdated: Date = Date()

    var totalCost: Double { quantity * costBasis }
    var totalValue: Double { quantity * currentPrice }
    var unrealizedPnL: Double { totalValue - totalCost }
    var unrealizedPnLPercent: Double {
        guard totalCost > 0 else { return 0 }
        return unrealizedPnL / totalCost * 100
    }
}

struct Portfolio: Codable {
    var assets: [Asset]

    var totalValue: Double { assets.reduce(0) { $0 + $1.totalValue } }
    var totalCost: Double  { assets.reduce(0) { $0 + $1.totalCost } }
    var totalPnL: Double   { totalValue - totalCost }
    var totalPnLPercent: Double {
        guard totalCost > 0 else { return 0 }
        return totalPnL / totalCost * 100
    }

    func assets(ofType type: AssetType) -> [Asset] {
        assets.filter { $0.type == type }
    }
}
