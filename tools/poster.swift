import AVFoundation
import Foundation

// USAGE: swift poster.swift <input> <output.jpg> <maxDim> [timeSeconds]
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: poster <input> <output.jpg> <maxDim> [time]"); exit(1) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let maxDim = Int(args[3]) ?? 1920
let at = args.count > 4 ? Double(args[4])! : min(asset.duration.seconds * 0.25, 2.0)

let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: maxDim, height: maxDim)
gen.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
gen.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
let t = CMTime(seconds: at, preferredTimescale: 600)
guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else {
    print("frame fail"); exit(1)
}
let url = URL(fileURLWithPath: args[2]) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, "public.jpeg" as CFString, 1, nil) else { exit(1) }
let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.78]
CGImageDestinationAddImage(dest, cg, props as CFDictionary)
CGImageDestinationFinalize(dest)
print("poster OK \(args[1])")