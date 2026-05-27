import Foundation

enum PriceServiceError: Error {
    case invalidSymbol
    case networkError(Error)
    case parsingError
}

final class PriceService {
    static let shared = PriceService()
    private init() {}

    private let session = URLSession.shared

    // MARK: - 台股（Yahoo Finance）

    func fetchTWSEPrice(symbol: String) async throws -> Double {
        // symbol 例如 "2330.TW"
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d"
        guard let url = URL(string: urlString) else { throw PriceServiceError.invalidSymbol }

        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double
        else { throw PriceServiceError.parsingError }

        return price
    }

    // MARK: - 加密貨幣（CoinGecko）

    func fetchCryptoPrice(coinId: String, vsCurrency: String = "twd") async throws -> Double {
        let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=\(coinId)&vs_currencies=\(vsCurrency)"
        guard let url = URL(string: urlString) else { throw PriceServiceError.invalidSymbol }

        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let coinData = json[coinId] as? [String: Any],
              let price = coinData[vsCurrency] as? Double
        else { throw PriceServiceError.parsingError }

        return price
    }

    // MARK: - 批次更新

    func refreshPrices(for assets: [Asset]) async -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        await withTaskGroup(of: (UUID, Double?).self) { group in
            for asset in assets {
                group.addTask {
                    do {
                        switch asset.type {
                        case .stock:
                            let price = try await self.fetchTWSEPrice(symbol: "\(asset.symbol).TW")
                            return (asset.id, price)
                        case .crypto:
                            let price = try await self.fetchCryptoPrice(coinId: asset.symbol.lowercased())
                            return (asset.id, price)
                        default:
                            return (asset.id, nil)
                        }
                    } catch {
                        return (asset.id, nil)
                    }
                }
            }
            for await (id, price) in group {
                if let price { result[id] = price }
            }
        }
        return result
    }
}
