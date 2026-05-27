import SwiftUI

@main
struct MyPortfolioApp: App {
    @StateObject private var vm = PortfolioViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
    }
}
