import Foundation

enum DiscogsError: LocalizedError {
    case rateLimited
    case notFound
    case network(Error)
    case parse

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "超過 API 請求限制，請稍後再試"
        case .notFound:    return "找不到相關資料"
        case .network(let e): return e.localizedDescription
        case .parse:       return "資料解析失敗"
        }
    }
}

class DiscogsService: ObservableObject {
    static let shared = DiscogsService()

    // 免費申請 Personal Access Token：https://www.discogs.com/settings/developers
    var personalAccessToken: String? = nil

    private let baseURL = "https://api.discogs.com"
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = [
            "User-Agent": "IdentifyVinyl/1.0 +github.com/IdentifyVinyl",
            "Accept": "application/vnd.discogs.v2.discogs+json"
        ]
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func search(query: String, perPage: Int = 20) async throws -> [DiscogsRelease] {
        var comps = URLComponents(string: "\(baseURL)/database/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "format", value: "vinyl"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        if let token = personalAccessToken {
            comps.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
        guard let url = comps.url else { throw DiscogsError.parse }
        let (data, response) = try await session.data(from: url)
        try checkHTTP(response)
        do { return try JSONDecoder().decode(DiscogsSearchResponse.self, from: data).results }
        catch { throw DiscogsError.parse }
    }

    func smartSearch(label: ScannedLabel) async throws -> [DiscogsRelease] {
        if let catno = label.catalogNumber {
            let results = try await search(query: catno)
            if !results.isEmpty { return results }
        }
        return try await search(query: label.searchQuery)
    }

    func fetchRelease(id: Int) async throws -> ReleaseDetail {
        var comps = URLComponents(string: "\(baseURL)/releases/\(id)")!
        if let token = personalAccessToken {
            comps.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        guard let url = comps.url else { throw DiscogsError.parse }
        let (data, response) = try await session.data(from: url)
        try checkHTTP(response)
        do { return try JSONDecoder().decode(ReleaseDetail.self, from: data) }
        catch { throw DiscogsError.parse }
    }

    private func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: break
        case 404: throw DiscogsError.notFound
        case 429: throw DiscogsError.rateLimited
        default: break
        }
    }
}
