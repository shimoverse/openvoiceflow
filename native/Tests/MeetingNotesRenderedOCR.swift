// OCR the actual captured window; SwiftUI omits disabled buttons and static text
// from this accessibility tree, so AX alone cannot verify pending-state copy.
import AppKit
import Vision

let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
var rect = CGRect(origin: .zero, size: image.size)
let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
try VNImageRequestHandler(cgImage: cgImage).perform([request])
for observation in request.results ?? [] {
    if let text = observation.topCandidates(1).first?.string { print(text) }
}
