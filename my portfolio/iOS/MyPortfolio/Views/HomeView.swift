import SwiftUI

struct HomeView: View {
    @EnvironmentObject var vm: PortfolioViewModel
    @State private var showAddAsset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    totalValueCard
                    allocationSection
                    recentSnapshotSection
                }
                .padding()
            }
            .navigationTitle("我的資產")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddAsset = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task { await vm.refreshPrices() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddAsset) {
                AddAssetView()
            }
        }
    }

    private var totalValueCard: some View {
        VStack(spacing: 8) {
            Text("總資產")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(vm.portfolio.totalValue.currencyString)
                .font(.system(size: 36, weight: .bold, design: .rounded))
            HStack(spacing: 4) {
                Image(systemName: vm.portfolio.totalPnL >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(vm.portfolio.totalPnL.currencyString)  (\(vm.portfolio.totalPnLPercent.pnlString)%)")
            }
            .font(.subheadline)
            .foregroundStyle(vm.portfolio.totalPnL >= 0 ? .green : .red)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("資產配置")
                .font(.headline)
            ForEach(AssetType.allCases, id: \.self) { type in
                let value = vm.valueForType(type)
                guard value > 0 else { return AnyView(EmptyView()) }
                let total = vm.portfolio.totalValue
                let pct = total > 0 ? value / total : 0
                return AnyView(AllocationRow(type: type, value: value, percent: pct))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var recentSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近期快照")
                .font(.headline)
            if vm.snapshots.isEmpty {
                Text("尚無歷史資料")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(vm.snapshots.suffix(5).reversed()) { snap in
                    HStack {
                        Text(snap.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(snap.totalValue.currencyString)
                            .font(.subheadline.bold())
                        Text("(\(snap.totalPnLPercent.pnlString)%)")
                            .font(.caption)
                            .foregroundStyle(snap.totalPnL >= 0 ? .green : .red)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AllocationRow: View {
    let type: AssetType
    let value: Double
    let percent: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(type.rawValue)
                    .font(.subheadline)
                Spacer()
                Text(value.currencyString)
                    .font(.subheadline.bold())
                Text(String(format: "%.1f%%", percent * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
            ProgressView(value: percent)
                .tint(type.color)
        }
    }
}

// MARK: - Add Asset Sheet

struct AddAssetView: View {
    @EnvironmentObject var vm: PortfolioViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = ""
    @State private var type: AssetType = .stock
    @State private var quantity = ""
    @State private var costBasis = ""
    @State private var currentPrice = ""
    @State private var currency = "TWD"

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資料") {
                    TextField("名稱 (例：台積電)", text: $name)
                    TextField("代號 (例：2330)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                    Picker("類型", selection: $type) {
                        ForEach(AssetType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                }
                Section("持倉") {
                    TextField("數量", text: $quantity)
                        .keyboardType(.decimalPad)
                    TextField("成本價", text: $costBasis)
                        .keyboardType(.decimalPad)
                    TextField("現價", text: $currentPrice)
                        .keyboardType(.decimalPad)
                    Picker("幣別", selection: $currency) {
                        Text("TWD").tag("TWD")
                        Text("USD").tag("USD")
                        Text("USDT").tag("USDT")
                    }
                }
            }
            .navigationTitle("新增資產")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveAndDismiss() }
                        .disabled(name.isEmpty || symbol.isEmpty)
                }
            }
        }
    }

    private func saveAndDismiss() {
        let asset = Asset(
            name: name,
            symbol: symbol,
            type: type,
            quantity: Double(quantity) ?? 0,
            costBasis: Double(costBasis) ?? 0,
            currentPrice: Double(currentPrice) ?? 0,
            currency: currency
        )
        vm.addAsset(asset)
        dismiss()
    }
}

#Preview {
    HomeView().environmentObject(PortfolioViewModel())
}
