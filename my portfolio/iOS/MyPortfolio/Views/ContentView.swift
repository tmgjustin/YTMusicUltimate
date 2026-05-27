import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: PortfolioViewModel

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("總覽", systemImage: "chart.pie.fill")
                }

            StocksView()
                .tabItem {
                    Label("股票", systemImage: "chart.line.uptrend.xyaxis")
                }

            OtherAssetsView()
                .tabItem {
                    Label("其他資產", systemImage: "banknote.fill")
                }

            HistoryView()
                .tabItem {
                    Label("歷史", systemImage: "clock.fill")
                }
        }
        .task {
            await vm.refreshPrices()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PortfolioViewModel())
}
