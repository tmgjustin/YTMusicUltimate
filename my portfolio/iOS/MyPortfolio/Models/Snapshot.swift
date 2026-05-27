import Foundation

struct PortfolioSnapshot: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var totalValue: Double
    var totalCost: Double
    var totalPnL: Double
    var totalPnLPercent: Double
    var assetBreakdown: [AssetBreakdown]

    struct AssetBreakdown: Codable {
        var type: AssetType
        var value: Double
        var percent: Double
    }
}

extension PortfolioSnapshot {
    static func from(_ portfolio: Portfolio) -> PortfolioSnapshot {
        let total = portfolio.totalValue
        let breakdown: [AssetBreakdown] = AssetType.allCases.compactMap { type in
            let value = portfolio.assets(ofType: type).reduce(0) { $0 + $1.totalValue }
            guard value > 0 else { return nil }
            return AssetBreakdown(
                type: type,
                value: value,
                percent: total > 0 ? value / total * 100 : 0
            )
        }
        return PortfolioSnapshot(
            date: Date(),
            totalValue: portfolio.totalValue,
            totalCost: portfolio.totalCost,
            totalPnL: portfolio.totalPnL,
            totalPnLPercent: portfolio.totalPnLPercent,
            assetBreakdown: breakdown
        )
    }
}
