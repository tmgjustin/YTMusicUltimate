import Vision
import UIKit

class OCRService {

    func recognize(image: UIImage) async -> ScannedLabel {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: ScannedLabel(rawText: "", lines: []))
                return
            }
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: ScannedLabel(rawText: "", lines: []))
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let rawText = lines.joined(separator: "\n")
                continuation.resume(returning: Self.parseLabel(lines: lines, rawText: rawText))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "ja-JP", "ko-KR", "zh-Hant"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try? handler.perform([request])
        }
    }

    func detectTextRegions(in pixelBuffer: CVPixelBuffer, completion: @escaping ([CGRect]) -> Void) {
        let request = VNDetectTextRectanglesRequest { request, _ in
            let rects = (request.results as? [VNTextObservation])?.map(\.boundingBox) ?? []
            DispatchQueue.main.async { completion(rects) }
        }
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }

    private static func parseLabel(lines: [String], rawText: String) -> ScannedLabel {
        var label = ScannedLabel(rawText: rawText, lines: lines)
        let catnoRegex = try? NSRegularExpression(pattern: #"\b([A-Z]{1,6}[\s\-]?\d{3,8}[A-Z]?)\b"#)
        if let m = catnoRegex?.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)),
           let range = Range(m.range(at: 1), in: rawText) {
            label.catalogNumber = String(rawText[range])
        }
        let yearRegex = try? NSRegularExpression(pattern: #"\b(19[5-9]\d|20[012]\d)\b"#)
        if let m = yearRegex?.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)),
           let range = Range(m.range(at: 1), in: rawText) {
            label.year = String(rawText[range])
        }
        let content = lines.filter {
            $0.count > 2 && $0.count < 80
            && !$0.contains("℗") && !$0.contains("©")
            && !$0.lowercased().hasPrefix("side")
            && !$0.lowercased().hasPrefix("rpm")
            && !$0.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == " " })
        }
        label.inferredTitle = content.first
        label.inferredArtist = content.dropFirst().first
        return label
    }
}
