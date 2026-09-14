import SwiftUI
import Vision
import VisionKit

/// Photographs a lab report and reads the text off it, on this device.
///
/// Vision runs locally, so a picture of someone's blood results never leaves
/// the phone — the same promise the rest of My health makes. Nothing is saved
/// from here: the recognised values are handed back as a draft for the reader
/// to check in the normal form.
struct LabScannerView: UIViewControllerRepresentable {
    /// Called with whatever could be read. An empty draft is a valid outcome
    /// and means the scan found nothing it was confident about.
    let onScan: (LabReport) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    /// VisionKit delivers its delegate callbacks on the main thread, so the
    /// coordinator is isolated to it. The protocol itself predates concurrency
    /// annotations, hence `@preconcurrency`: it keeps the isolation and adds a
    /// runtime check that the callback really did arrive on the main actor,
    /// rather than asserting it and hoping.
    @MainActor

    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let parent: LabScannerView

        init(_ parent: LabScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Pages are read in order and concatenated: a CBC and a serology
            // result are often two sheets from the same visit.
            var text = ""
            for index in 0..<scan.pageCount {
                text += Self.recognisedText(in: scan.imageOfPage(at: index)) + "\n"
            }
            let draft = LabReportParser.draft(from: text)
            parent.onScan(draft)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            // A failed scan is not an error worth a dialog: the reader can type
            // the values, which is the path this feature is shortening, not
            // replacing.
            parent.onCancel()
        }

        private static func recognisedText(in image: UIImage) -> String {
            guard let cgImage = image.cgImage else { return "" }
            let request = VNRecognizeTextRequest()
            // Accurate over fast: this is read once, and a misread digit costs
            // far more than a second of waiting.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false   // it would "correct" numbers
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
    }
}
