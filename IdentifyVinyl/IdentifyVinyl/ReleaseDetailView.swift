import SwiftUI

struct ReleaseDetailView: View {
    let release: DiscogsRelease
    @State private var detail: ReleaseDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            if isLoading { ProgressView("載入中…").frame(maxWidth: .infinity, minHeight: 300) }
            else if let msg = errorMessage { ContentUnavailableView(msg, systemImage: "exclamationmark.triangle").frame(minHeight: 300) }
            else if let detail { DetailContent(detail: detail, isFavorite: $isFavorite) }
        }
        .navigationTitle(release.albumTitle ?? release.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isFavorite.toggle() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart").foregroundStyle(isFavorite ? .red : .primary)
                }
            }
        }
        .task {
            do { detail = try await DiscogsService.shared.fetchRelease(id: release.id) }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }
}

private struct DetailContent: View {
    let detail: ReleaseDetail; @Binding var isFavorite: Bool
    var body: some View {
        VStack(spacing: 0) {
            AsyncImage(url: detail.primaryImageURL) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "record.circle.fill").font(.system(size: 90)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 280).background(Color(.secondarySystemBackground))
            }.frame(maxWidth: .infinity).clipped()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.artistDisplay).font(.title2.weight(.bold))
                    Text(detail.title.components(separatedBy: " - ").last ?? detail.title).font(.title3).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    if let y = detail.year { MetaCell(icon: "calendar", label: "年份", value: "\(y)") }
                    if let c = detail.country { MetaCell(icon: "globe", label: "國家", value: c) }
                    if let lbl = detail.labels?.first {
                        MetaCell(icon: "tag", label: "廠牌", value: lbl.name)
                        if let catno = lbl.catno, catno != "none" { MetaCell(icon: "barcode", label: "目錄號", value: catno) }
                    }
                    if let fmt = detail.formats?.first {
                        MetaCell(icon: "record.circle", label: "格式",
                                 value: ([fmt.name] + (fmt.descriptions ?? [])).joined(separator: ", "))
                    }
                    if let r = detail.released { MetaCell(icon: "calendar.badge.clock", label: "發行", value: r) }
                }
                if let price = detail.lowestPrice, let num = detail.numForSale {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("市場最低價").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "US$ %.2f", price)).font(.title2.weight(.bold)).foregroundStyle(.green)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("在售數量").font(.caption).foregroundStyle(.secondary)
                            Text("\(num) 件").font(.title3.weight(.semibold))
                        }
                    }
                    .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                if let genres = detail.genres, !genres.isEmpty { TagRow(title: "流派", tags: genres, color: .purple) }
                if let styles = detail.styles, !styles.isEmpty { TagRow(title: "風格", tags: styles, color: .blue) }
                if let tracks = detail.tracklist, !tracks.isEmpty { TracklistBlock(tracks: tracks) }
                if let notes = detail.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("備註").font(.headline)
                        Text(notes).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                BuyRecommendation(detail: detail)
                if let uri = detail.uri, let url = URL(string: "https://www.discogs.com\(uri)") {
                    Link(destination: url) {
                        Label("在 Discogs 查看完整資料", systemImage: "safari").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.buttonStyle(.borderedProminent)
                }
            }.padding()
        }
    }
}

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
        .padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TagRow: View {
    let title: String; let tags: [String]; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag).font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(color.opacity(0.12), in: Capsule()).foregroundStyle(color)
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
                        Text(track.position).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                        Text(track.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        if let dur = track.duration, !dur.isEmpty { Text(dur).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(idx % 2 == 0 ? Color.clear : Color(.tertiarySystemBackground))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
        }
    }
}

private struct BuyRecommendation: View {
    let detail: ReleaseDetail
    private var score: Int {
        var s = 0
        if let n = detail.numForSale, n > 3  { s += 1 }
        if let p = detail.lowestPrice, p < 40 { s += 1 }
        if !(detail.tracklist?.isEmpty ?? true) { s += 1 }
        if detail.genres?.isEmpty == false { s += 1 }
        return s
    }
    private var verdict: (String, String, Color) {
        switch score {
        case 4: return ("強烈推薦購買", "checkmark.seal.fill", .green)
        case 3: return ("值得考慮", "hand.thumbsup.fill", .blue)
        case 2: return ("謹慎評估", "exclamationmark.circle.fill", .orange)
        default: return ("資訊不足，需進一步研究", "questionmark.circle.fill", .gray)
        }
    }
    var body: some View {
        let (label, icon, color) = verdict
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("購買建議").font(.caption).foregroundStyle(.secondary)
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
            Spacer()
        }
        .padding().background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layoutRows(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? 0,
                      height: rows.map(\.maxHeight).reduce(0,+) + spacing * CGFloat(max(0, rows.count-1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layoutRows(proposal: ProposedViewSize(bounds.size), subviews: subviews) {
            var x = bounds.minX
            for (sv, sz) in row.items { sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz)); x += sz.width + spacing }
            y += row.maxHeight + spacing
        }
    }
    private struct Row { var items: [(LayoutSubview, CGSize)] = []; var maxHeight: CGFloat { items.map(\.1.height).max() ?? 0 } }
    private func layoutRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxW = proposal.width ?? .infinity
        var rows: [Row] = []; var cur = Row(); var w: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if w + sz.width > maxW, !cur.items.isEmpty { rows.append(cur); cur = Row(); w = 0 }
            cur.items.append((sv, sz)); w += sz.width + spacing
        }
        if !cur.items.isEmpty { rows.append(cur) }
        return rows
    }
}
