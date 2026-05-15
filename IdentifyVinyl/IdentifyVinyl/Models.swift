import Foundation

// MARK: - Scanned Label

struct ScannedLabel {
    var rawText: String
    var lines: [String]
    var catalogNumber: String?
    var year: String?
    var inferredTitle: String?
    var inferredArtist: String?

    var searchQuery: String {
        if let cat = catalogNumber { return cat }
        let parts = [inferredArtist, inferredTitle].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return lines.prefix(3).joined(separator: " ")
    }
}

// MARK: - Discogs Search

struct DiscogsSearchResponse: Codable {
    let results: [DiscogsRelease]
    let pagination: DiscogsPagination
}

struct DiscogsPagination: Codable {
    let pages: Int
    let items: Int
    let perPage: Int
    let page: Int

    enum CodingKeys: String, CodingKey {
        case pages, items, page
        case perPage = "per_page"
    }
}

struct DiscogsRelease: Codable, Identifiable {
    let id: Int
    let title: String
    let year: String?
    let label: [String]?
    let format: [String]?
    let country: String?
    let thumb: String?
    let coverImage: String?
    let genre: [String]?
    let style: [String]?
    let uri: String?
    let catno: String?
    let resourceUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, label, format, country, thumb, genre, style, uri, catno
        case coverImage = "cover_image"
        case resourceUrl = "resource_url"
    }

    var artistName: String? {
        let parts = title.components(separatedBy: " - ")
        return parts.count >= 2 ? parts[0] : nil
    }

    var albumTitle: String? {
        let parts = title.components(separatedBy: " - ")
        return parts.count >= 2 ? parts.dropFirst().joined(separator: " - ") : parts[0]
    }
}

// MARK: - Release Detail

struct ReleaseDetail: Codable, Identifiable {
    let id: Int
    let title: String
    let artists: [DiscogsArtist]?
    let year: Int?
    let labels: [DiscogsLabel]?
    let formats: [DiscogsFormat]?
    let genres: [String]?
    let styles: [String]?
    let tracklist: [DiscogsTrack]?
    let lowestPrice: Double?
    let numForSale: Int?
    let thumb: String?
    let images: [DiscogsImage]?
    let notes: String?
    let country: String?
    let uri: String?
    let released: String?
    let community: DiscogsCommunity?

    enum CodingKeys: String, CodingKey {
        case id, title, artists, year, labels, formats, genres, styles
        case tracklist, thumb, images, notes, country, uri, released, community
        case lowestPrice = "lowest_price"
        case numForSale = "num_for_sale"
    }

    var primaryImageURL: URL? {
        let urlStr = images?.first(where: { $0.type == "primary" })?.uri
            ?? images?.first?.uri
        return urlStr.flatMap { URL(string: $0) }
    }

    var artistDisplay: String {
        if let artists, !artists.isEmpty {
            return artists.map(\.name)
                .map { $0.hasSuffix(" (2)") || $0.hasSuffix(" (3)") ? String($0.dropLast(4)) : $0 }
                .joined(separator: ", ")
        }
        return title.components(separatedBy: " - ").first ?? title
    }
}

struct DiscogsArtist: Codable {
    let id: Int?
    let name: String
    let anv: String?
}

struct DiscogsLabel: Codable {
    let id: Int?
    let name: String
    let catno: String?
}

struct DiscogsFormat: Codable {
    let name: String
    let qty: String?
    let descriptions: [String]?
}

struct DiscogsTrack: Codable, Identifiable {
    var id: String { "\(position)-\(title)" }
    let position: String
    let title: String
    let duration: String?
    let extraArtists: [DiscogsArtist]?

    enum CodingKeys: String, CodingKey {
        case position, title, duration
        case extraArtists = "extraartists"
    }
}

struct DiscogsImage: Codable {
    let uri: String
    let type: String?
    let width: Int?
    let height: Int?
}

struct DiscogsCommunity: Codable {
    let rating: DiscogsCommunityRating?
    let have: Int?
    let want: Int?
}

struct DiscogsCommunityRating: Codable {
    let average: Double?
    let count: Int?
}
