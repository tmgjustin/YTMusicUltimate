import SwiftUI

struct StocksView: View {
    @EnvironmentObject var vm: PortfolioViewModel
    @State private var showAdd = false

    private var stocks: [Asset] { vm.assetsForType(.stock) }

    var body: some View {
        NavigationStack {
            List {
                if stocks.isEmpty {
                    ContentUnavailableView(
                        "尚無股票",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("點右上角 + 新增股票")
                    )
                } else {
                    Section {
                        summaryRow
                    }
                    Section("持股明細") {
                        ForEach(stocks) { asset in
                            NavigationLink {
                                AssetDetailView(asset: asset)
                            } label: {
                                AssetRow(asset: asset)
                            }
                        }
                        .onDelete { offsets in
                            vm.deleteAssets(at: offsets, type: .stock)
                        }
                    }
                }
            }
            .navigationTitle("股票")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
                if !stocks.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddAssetView()
            }
        }
    }

    private var summaryRow: some View {
        let total = stocks.reduce(0) { $0 + $1.totalValue }
        let pnl = stocks.reduce(0) { $0 + $1.unrealizedPnL }
        let cost = stocks.reduce(0) { $0 + $1.totalCost }
        let pct = cost > 0 ? pnl / cost * 100 : 0
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("股票總值")
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

struct AssetRow: View {
    let asset: Asset

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name)
                    .font(.headline)
                Text(asset.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(asset.totalValue.currencyString)
                    .font(.subheadline.bold())
                HStack(spacing: 2) {
                    Image(systemName: asset.unrealizedPnL >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(asset.unrealizedPnLPercent.pnlString)%")
                }
                .font(.caption)
                .foregroundStyle(asset.unrealizedPnL >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AssetDetailView: View {
    @EnvironmentObject var vm: PortfolioViewModel
    let asset: Asset

    var body: some View {
        List {
            Section("持倉資訊") {
                LabeledContent("名稱", value: asset.name)
                LabeledContent("代號", value: asset.symbol)
                LabeledContent("數量", value: asset.quantity.formatted())
                LabeledContent("成本價", value: asset.costBasis.currencyString)
                LabeledContent("現價", value: asset.currentPrice.currencyString)
                LabeledContent("幣別", value: asset.currency)
            }
            Section("損益") {
                LabeledContent("總成本", value: asset.totalCost.currencyString)
                LabeledContent("市值", value: asset.totalValue.currencyString)
                LabeledContent("未實現損益") {
                    Text("\(asset.unrealizedPnL.currencyString)  (\(asset.unrealizedPnLPercent.pnlString)%)")
                        .foregroundStyle(asset.unrealizedPnL >= 0 ? .green : .red)
                }
            }
            Section {
                LabeledContent("最後更新", value: asset.lastUpdated.formatted())
            }
        }
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    StocksView().environmentObject(PortfolioViewModel())
}
