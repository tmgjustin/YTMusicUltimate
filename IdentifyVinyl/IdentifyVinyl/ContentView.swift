import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isShowingResults {
                    ScanResultsView(viewModel: viewModel)
                } else {
                    CameraScanView(viewModel: viewModel)
                }
            }
            .navigationTitle("黑膠掃描器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isShowingResults {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("重新掃描") { viewModel.reset() }
                    }
                }
            }
        }
    }
}
