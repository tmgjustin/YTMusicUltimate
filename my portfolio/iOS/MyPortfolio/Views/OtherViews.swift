import SwiftUI

// MARK: - OtherAssetsView（加密貨幣 / 現金 / 不動產 / 其他）

struct OtherAssetsView: View {
    @EnvironmentObject var vm: PortfolioViewModel

    private let tabs: [AssetType] = [.crypto, .cash, .realEstate, .other]
    @State private var selectedType: AssetType = .crypto

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("類型", selection: $selectedType) {
                    ForEach(tabs, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                AssetTypeListView(type: selectedType)
            }
            .navigationTitle("其他資產")
        }
    }
}

// MARK: - AssetTypeListView

struct AssetTypeListView: View {
    @EnvironmentObject var vm: PortfolioViewModel
    @State private var showAdd = false
    let type: AssetType

    private var assets: [Asset] { vm.assetsForType(type) }

    var body: some View {
        List {
            if assets.isEmpty {
                ContentUnavailableView(
                    "尚無\(type.rawValue)",
                    systemImage: type.systemImage,
                    description: Text("點右上角 + 新增")
                )
            } else {
                Section {
                    typeSummaryRow
                }
                Section("明細") {
                    ForEach(assets) { asset in
                        NavigationLink {
                            AssetDetailView(asset: asset)
                        } label: {
                            AssetRow(asset: asset)
                        }
                    }
                    .onDelete { offsets in
                        vm.deleteAssets(at: offsets, type: type)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            if !assets.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAssetView()
        }
    }

    private var typeSummaryRow: some View {
        let total = assets.reduce(0) { $0 + $1.totalValue }
        let pnl   = assets.reduce(0) { $0 + $1.unrealizedPnL }
        let cost  = assets.reduce(0) { $0 + $1.totalCost }
        let pct   = cost > 0 ? pnl / cost * 100 : 0
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(type.rawValue)總值")
                    .font(.caption).foregroundStyle(.secondary)
                Text(total.currencyString)
                    .font(.title3.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("未實現損益")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(pnl.currencyString) (\(pct.pnlString)%)")
                    .font(.subheadline.bold())
                    .foregroundStyle(pnl >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @EnvironmentObject var vm: PortfolioViewModel

    var body: some View {
        NavigationStack {
            List {
                if vm.snapshots.isEmpty {
                    ContentUnavailableView(
                        "尚無歷史記錄",
                        systemImage: "clock",
                        description: Text("每次刷新價格時自動記錄")
                    )
                } else {
                    ForEach(vm.snapshots.reversed()) { snap in
                        SnapshotRow(snapshot: snap)
                    }
                }
            }
            .navigationTitle("歷史記錄")
        }
    }
}

struct SnapshotRow: View {
    let snapshot: PortfolioSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.date.formatted(date: .complete, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(snapshot.totalValue.currencyString)
                    .font(.headline)
                Spacer()
                Text("\(snapshot.totalPnL.currencyString) (\(snapshot.totalPnLPercent.pnlString)%)")
                    .font(.subheadline)
                    .foregroundStyle(snapshot.totalPnL >= 0 ? .green : .red)
            }
            if !snapshot.assetBreakdown.isEmpty {
                HStack(spacing: 8) {
                    ForEach(snapshot.assetBreakdown, id: \.type) { item in
                        Label(
                            String(format: "%@ %.0f%%", item.type.rawValue, item.percent),
                            systemImage: item.type.systemImage
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Extensions

extension Double {
    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "NT$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "NT$\(Int(self))"
    }

    var pnlString: String {
        String(format: "%+.2f", self)
    }
}

extension AssetType {
    var color: Color {
        switch self {
        case .stock:      return .blue
        case .crypto:     return .orange
        case .cash:       return .green
        case .realEstate: return .purple
        case .other:      return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .stock:      return "chart.line.uptrend.xyaxis"
        case .crypto:     return "bitcoinsign.circle.fill"
        case .cash:       return "banknote.fill"
        case .realEstate: return "house.fill"
        case .other:      return "ellipsis.circle.fill"
        }
    }
}
