import Foundation
import Vision
import AppKit

// USAGE: swift vision.swift <image>...
// Classifies each image with Vision scene labels.

func classify(_ path: String) {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("\(path): LOAD_FAIL")
        return
    }
    let req = VNClassifyImageRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do {
        try handler.perform([req])
        let obs = (req.results ?? []).sorted { $0.confidence > $1.confidence }
        let top = obs.prefix(4).map { "\($0.identifier):\(String(format: "%.2f", $0.confidence))" }
        print("\(URL(fileURLWithPath: path).lastPathComponent): \(top.joined(separator: " | "))")
    } catch {
        print("\(path): ERR \(error)")
    }
}

for p in CommandLine.arguments.dropFirst() {
    classify(p)
}