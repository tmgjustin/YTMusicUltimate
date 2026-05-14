import SwiftUI

enum ScanState: Equatable {
    case scanning, processing, results, error(String)
    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.scanning, .scanning), (.processing, .processing), (.results, .results): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

@MainActor
class ScannerViewModel: ObservableObject {
    @Published var state: ScanState = .scanning
    @Published var scannedLabel: ScannedLabel?
    @Published var searchResults: [DiscogsRelease] = []
    @Published var searchQuery: String = ""
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var capturedImage: UIImage?

    private let ocrService = OCRService()
    private let discogsService = DiscogsService.shared

    var isShowingResults: Bool {
        state == .results || { if case .error = state { return true }; return false }()
    }

    func processCapture(_ image: UIImage) async {
        state = .processing; capturedImage = image; errorMessage = nil
        let label = await ocrService.recognize(image: image)
        scannedLabel = label; searchQuery = label.searchQuery; state = .results
        await runSearch(with: label)
    }

    private func runSearch(with label: ScannedLabel) async {
        guard !label.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "未偵測到文字，請確保光線充足後重試"; return
        }
        isSearching = true
        do {
            searchResults = try await discogsService.smartSearch(label: label)
            if searchResults.isEmpty { errorMessage = "找不到符合的黑膠唱片，請嘗試修改搜尋關鍵字" }
        } catch { errorMessage = error.localizedDescription }
        isSearching = false
    }

    func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true; errorMessage = nil
        do {
            searchResults = try await discogsService.search(query: query)
            if searchResults.isEmpty { errorMessage = "找不到結果" }
        } catch { errorMessage = error.localizedDescription }
        isSearching = false
    }

    func reset() {
        state = .scanning; scannedLabel = nil; searchResults = []
        searchQuery = ""; capturedImage = nil; errorMessage = nil
    }
}
