import SwiftUI

struct ScanResultsView: View {
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ocrSection
                searchBarSection
                if viewModel.isSearching {
                    HStack { Spacer(); ProgressView("搜尋 Discogs..."); Spacer() }.padding()
                } else if let err = viewModel.errorMessage {
                    ContentUnavailableView(err, systemImage: "magnifyingglass").padding()
                } else if viewModel.searchResults.isEmpty {
                    ContentUnavailableView("找不到結果", systemImage: "record.circle",
                        description: Text("請嘗試修改搜尋關鍵字")).padding()
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.searchResults) { release in
                            NavigationLink { ReleaseDetailView(release: release) } label: {
                                ReleaseCard(release: release)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var ocrSection: some View {
        if let label = viewModel.scannedLabel, !label.lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("掃描辨識", systemImage: "text.viewfinder").font(.headline)
                HStack(spacing: 8) {
                    if let cat = label.catalogNumber { Chip(icon: "barcode", text: cat, color: .purple) }
                    if let year = label.year { Chip(icon: "calendar", text: year, color: .orange) }
                }
                DisclosureGroup("原始辨識文字") {
                    Text(label.rawText.isEmpty ? "（無）" : label.rawText)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }.font(.caption)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var searchBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Discogs 搜尋", systemImage: "magnifyingglass").font(.headline)
            HStack(spacing: 8) {
                TextField("輸入關鍵字、目錄號…", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder).submitLabel(.search)
                    .onSubmit { Task { await viewModel.performSearch(query: viewModel.searchQuery) } }
                Button { Task { await viewModel.performSearch(query: viewModel.searchQuery) } } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(.blue)
                }.disabled(viewModel.isSearching)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ReleaseCard: View {
    let release: DiscogsRelease
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: release.thumb ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "record.circle").font(.system(size: 30)).foregroundStyle(.secondary)
            }
            .frame(width: 68, height: 68)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                if let artist = release.artistName {
                    Text(artist).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(release.albumTitle ?? release.title).font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(release.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let year = release.year { Text(year).font(.caption2).foregroundStyle(.secondary) }
                    if let lbl = release.label?.first {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(lbl).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let catno = release.catno, catno != "none", !catno.isEmpty {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(catno).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                if let fmts = release.format, !fmts.isEmpty {
                    Text(fmts.prefix(2).joined(separator: ", ")).font(.caption2).foregroundStyle(.blue)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Chip: View {
    let icon: String; let text: String; let color: Color
    var body: some View {
        Label(text, systemImage: icon).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule()).foregroundStyle(color)
    }
}
