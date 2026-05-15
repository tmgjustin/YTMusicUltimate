import SwiftUI

struct ReleaseDetailView: View {
    let release: DiscogsRelease

    @State private var detail: ReleaseDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("載入中…")
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let msg = errorMessage {
                ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
                    .frame(minHeight: 300)
            } else if let detail {
                DetailContent(detail: detail, isFavorite: $isFavorite)
            }
        }
        .navigationTitle(release.albumTitle ?? release.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFavorite.toggle()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : .primary)
                }
            }
        }
        .task {
            do {
                detail = try await DiscogsService.shared.fetchRelease(id: release.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Detail Content

private struct DetailContent: View {
    let detail: ReleaseDetail
    @Binding var isFavorite: Bool

    var body: some View {
        VStack(spacing: 0) {
            coverImage
            VStack(alignment: .leading, spacing: 20) {
                titleBlock
                metadataGrid
                if let community = detail.community {
                    CommunityBlock(community: community)
                }
                if let price = detail.lowestPrice, let num = detail.numForSale {
                    PriceBlock(lowestPrice: price, numForSale: num)
                }
                if let genres = detail.genres, !genres.isEmpty {
                    TagRow(title: "流派", tags: genres, color: .purple)
                }
                if let styles = detail.styles, !styles.isEmpty {
                    TagRow(title: "風格", tags: styles, color: .blue)
                }
                if let tracks = detail.tracklist, !tracks.isEmpty {
                    TracklistBlock(tracks: tracks)
                }
                if let notes = detail.notes, !notes.isEmpty {
                    NotesBlock(text: notes)
                }
                BuyRecommendation(detail: detail)
                discogsLink
            }
            .padding()
        }
    }

    // MARK: Sub-views

    @ViewBuilder
    private var coverImage: some View {
        AsyncImage(url: detail.primaryImageURL) { img in
            img.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 90))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(Color(.secondarySystemBackground))
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.artistDisplay)
                .font(.title2.weight(.bold))
            Text(detail.title.components(separatedBy: " - ").last ?? detail.title)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let year = detail.year {
                MetaCell(icon: "calendar", label: "年份", value: "\(year)")
            }
            if let country = detail.country {
                MetaCell(icon: "globe", label: "國家", value: country)
            }
            if let lbl = detail.labels?.first {
                MetaCell(icon: "tag", label: "廠牌", value: lbl.name)
                if let catno = lbl.catno, catno != "none" {
                    MetaCell(icon: "barcode", label: "目錄號", value: catno)
                }
            }
            if let fmt = detail.formats?.first {
                let desc = ([fmt.name] + (fmt.descriptions ?? [])).joined(separator: ", ")
                MetaCell(icon: "record.circle", label: "格式", value: desc)
            }
            if let released = detail.released {
                MetaCell(icon: "calendar.badge.clock", label: "發行", value: released)
            }
        }
    }

    @ViewBuilder
    private var discogsLink: some View {
        if let uri = detail.uri,
           let url = URL(string: "https://www.discogs.com\(uri)") {
            Link(destination: url) {
                Label("在 Discogs 查看完整資料", systemImage: "safari")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Supporting Views

private struct MetaCell: View {
    let icon: String; let label: String; let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.medium)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CommunityBlock: View {
    let community: DiscogsCommunity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discogs 社群").font(.headline)
            HStack(spacing: 0) {
                if let rating = community.rating {
                    VStack(spacing: 4) {
                        starsView(average: rating.average ?? 0)
                        if let avg = rating.average {
                            Text(String(format: "%.2f", avg))
                                .font(.title3.weight(.bold))
                        }
                        if let count = rating.count {
                            Text("\(count) 人評分")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 48)
                }
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.title2)
                    Text("\(community.have ?? 0)")
                        .font(.title3.weight(.bold))
                    Text("擁有")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 48)
                VStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink).font(.title2)
                    Text("\(community.want ?? 0)")
                        .font(.title3.weight(.bold))
                    Text("想要")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func starsView(average: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                let filled = Double(i) <= average
                let half = !filled && Double(i) - 0.5 <= average
                Image(systemName: filled ? "star.fill" : half ? "star.leadinghalf.filled" : "star")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
    }
}

private struct PriceBlock: View {
    let lowestPrice: Double
    let numForSale: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("市場行情").font(.headline)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("市場最低價").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "US$ %.2f", lowestPrice))
                        .font(.title2.weight(.bold)).foregroundStyle(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("在售數量").font(.caption).foregroundStyle(.secondary)
                    Text("\(numForSale) 件").font(.title3.weight(.semibold))
                }
            }
            Text("成交歷史記錄需登入 Discogs 帳號查閱")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TagRow: View {
    let title: String; let tags: [String]; let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(color.opacity(0.12), in: Capsule())
                        .foregroundStyle(color)
                }
            }
        }
    }
}

private struct TracklistBlock: View {
    let tracks: [DiscogsTrack]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("曲目列表").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { idx, track in
                    HStack(spacing: 10) {
                        Text(track.position)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        Text(track.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        if let dur = track.duration, !dur.isEmpty {
                            Text(dur).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(idx % 2 == 0 ? Color.clear : Color(.tertiarySystemBackground))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
        }
    }
}

private struct NotesBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("備註").font(.headline)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Buy Recommendation

private struct BuyRecommendation: View {
    let detail: ReleaseDetail

    private var score: Int {
        var s = 0
        if let n = detail.numForSale, n > 3           { s += 1 }
        if let p = detail.lowestPrice, p < 40          { s += 1 }
        if !(detail.tracklist?.isEmpty ?? true)         { s += 1 }
        if let avg = detail.community?.rating?.average, avg >= 3.8 { s += 1 }
        if let want = detail.community?.want, want > 50 { s += 1 }
        return s
    }

    private var communityNote: String? {
        guard let avg = detail.community?.rating?.average,
              let count = detail.community?.rating?.count, count > 0 else { return nil }
        switch avg {
        case 4.5...: return "社群評價極高（\(String(format: "%.1f", avg))★）"
        case 3.8...: return "社群評價良好（\(String(format: "%.1f", avg))★）"
        case 3.0...: return "社群評價普通（\(String(format: "%.1f", avg))★）"
        default:     return "社群評價偏低（\(String(format: "%.1f", avg))★）"
        }
    }

    private var verdict: (String, String, Color) {
        switch score {
        case 5:    return ("強烈推薦購買", "checkmark.seal.fill", .green)
        case 4:    return ("強烈推薦購買", "checkmark.seal.fill", .green)
        case 3:    return ("值得考慮", "hand.thumbsup.fill", .blue)
        case 2:    return ("謹慎評估", "exclamationmark.circle.fill", .orange)
        default:   return ("資訊不足，需進一步研究", "questionmark.circle.fill", .gray)
        }
    }

    var body: some View {
        let (label, icon, color) = verdict
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("購買建議").font(.caption).foregroundStyle(.secondary)
                    Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                }
                Spacer()
            }
            if let note = communityNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layoutRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.maxHeight).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (sv, sz) in row.items {
                sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += row.maxHeight + spacing
        }
    }

    private struct Row {
        var items: [(LayoutSubview, CGSize)] = []
        var maxHeight: CGFloat { items.map(\.1.height).max() ?? 0 }
    }

    private func layoutRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxW = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var usedW: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if usedW + sz.width > maxW, !current.items.isEmpty {
                rows.append(current)
                current = Row(); usedW = 0
            }
            current.items.append((sv, sz))
            usedW += sz.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
