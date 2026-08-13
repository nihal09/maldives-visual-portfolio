import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import VideoToolbox

// USAGE: swift transcode.swift <input> <output> <maxDim> <bitrate> <codec: h264|hevc> [maxDurSeconds]
// Best-effort audio pass-through as AAC. Optional maxDurSeconds trims to a short loop.

let args = CommandLine.arguments
guard args.count >= 6 else {
    print("usage: \(args[0]) <input> <output> <maxDim> <bitrate> <h264|hevc> [maxDurSeconds]")
    exit(1)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
guard let maxDim = Int(args[3]), let bitrate = Int(args[4]) else { exit(1) }
let codec: AVVideoCodecType = args[5] == "hevc" ? .hevc : .h264
var maxDur: Double? = nil
if args.count >= 7, let d = Double(args[6]) { maxDur = d }

let asset = AVURLAsset(url: inputURL)
guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    print("no video track"); exit(1)
}
let naturalSize = videoTrack.naturalSize
let preferred = videoTrack.preferredTransform
let p1 = CGPoint(x: naturalSize.width, y: 0).applying(preferred)
let p2 = CGPoint(x: 0, y: naturalSize.height).applying(preferred)
let dispW = max(abs(p1.x), abs(p2.x))
let dispH = max(abs(p1.y), abs(p2.y))
let scale = CGFloat(maxDim) / max(dispW, dispH)
let targetW = Int((dispW * scale).rounded())
let targetH = Int((dispH * scale).rounded())
let origin = CGPoint.zero.applying(preferred)
let transform = preferred
    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
    .concatenating(CGAffineTransform(translationX: -origin.x * scale, y: -origin.y * scale))

print("\(inputURL.lastPathComponent): \(Int(naturalSize.width))x\(Int(naturalSize.height)) -> \(targetW)x\(targetH)")

try? FileManager.default.removeItem(at: outputURL)
guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
    print("writer fail"); exit(1)
}

var compression: [String: Any] = [
    AVVideoAverageBitRateKey: bitrate,
    AVVideoExpectedSourceFrameRateKey: 30,
    AVVideoMaxKeyFrameIntervalKey: 48,
]
if codec == .h264 {
    compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
}
let writerSettings: [String: Any] = [
    AVVideoCodecKey: codec,
    AVVideoWidthKey: targetW,
    AVVideoHeightKey: targetH,
    AVVideoCompressionPropertiesKey: compression,
]
let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
videoInput.expectsMediaDataInRealTime = false
guard writer.canAdd(videoInput) else { print("cannot add video input"); exit(1) }
writer.add(videoInput)

var audioInput: AVAssetWriterInput?
if let audioTrack = asset.tracks(withMediaType: .audio).first,
   let desc = audioTrack.formatDescriptions.first {
    let fmt = desc as! CMFormatDescription
    if CMFormatDescriptionGetMediaType(fmt) == kCMMediaType_Audio {
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        audioInput!.expectsMediaDataInRealTime = false
        if writer.canAdd(audioInput!) { writer.add(audioInput!) } else { audioInput = nil }
    }
}

guard let reader = try? AVAssetReader(asset: asset) else { print("reader fail"); exit(1) }
let readerVideo = AVAssetReaderTrackOutput(
    track: videoTrack,
    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
)
readerVideo.alwaysCopiesSampleData = false
guard reader.canAdd(readerVideo) else { print("cannot add reader"); exit(1) }
reader.add(readerVideo)
let audioTrack = asset.tracks(withMediaType: .audio).first
var readerAudio: AVAssetReaderTrackOutput?
if audioInput != nil, let at = audioTrack {
    readerAudio = AVAssetReaderTrackOutput(track: at, outputSettings: nil)
    readerAudio!.alwaysCopiesSampleData = false
    reader.add(readerAudio!)
}

let fullDur = asset.duration
let clampedDur = maxDur.map { CMTime(seconds: min($0, fullDur.seconds), preferredTimescale: fullDur.timescale) } ?? fullDur
let timeRange = CMTimeRange(start: .zero, duration: clampedDur)
reader.timeRange = timeRange
guard reader.startReading() else { print("read start fail: \(String(describing: reader.error))"); exit(1) }
guard writer.startWriting() else { print("write start fail"); exit(1) }
writer.startSession(atSourceTime: timeRange.start)

let ci = CIContext(options: [.useSoftwareRenderer: false])
let queue = DispatchQueue(label: "transcode.write")
let sema = DispatchSemaphore(value: 0)
var failed = false

var pool: CVPixelBufferPool?
let poolAttrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: targetW,
    kCVPixelBufferHeightKey as String: targetH,
]
let poolStatus = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, poolAttrs as CFDictionary, &pool)
print("pool status: \(poolStatus) pool: \(pool != nil)")

func appendVideo(_ sample: CMSampleBuffer) {
    guard let pool = pool,
          let srcBuf = CMSampleBufferGetImageBuffer(sample) else { failed = true; return }
    var destBuf: CVPixelBuffer?
    let poolCreate = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destBuf)
    guard poolCreate == kCVReturnSuccess, let dest = destBuf else {
        print("pool create fail: \(poolCreate)"); failed = true; return
    }
    let image = CIImage(cvPixelBuffer: srcBuf).transformed(by: transform)
    ci.render(image, to: dest, bounds: image.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
    var timing = CMSampleTimingInfo(
        duration: CMSampleBufferGetDuration(sample),
        presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
        decodeTimeStamp: .invalid
    )
    var desc: CMVideoFormatDescription?
    let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: dest, formatDescriptionOut: &desc
    )
    guard fmtStatus == noErr, let desc = desc else { print("fmt fail \(fmtStatus)"); failed = true; return }
    var out: CMSampleBuffer?
    let sbStatus = CMSampleBufferCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: dest,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil as UnsafeMutableRawPointer?,
        formatDescription: desc,
        sampleTiming: &timing,
        sampleBufferOut: &out
    )
    guard sbStatus == noErr, let out = out else { print("sb fail \(sbStatus)"); failed = true; return }
    let ok = videoInput.append(out)
    if !ok { print("append fail: \(String(describing: writer.error))"); failed = true }
    videoFrames += 1
}

var videoFrames = 0
print("starting requestMediaDataWhenReady")
var inputsDone = 0
let totalInputs = audioInput != nil ? 2 : 1
func maybeFinish() {
    inputsDone += 1
    if inputsDone == totalInputs {
        writer.finishWriting { sema.signal() }
    }
}
videoInput.requestMediaDataWhenReady(on: queue) {
    while videoInput.isReadyForMoreMediaData {
        if let sample = readerVideo.copyNextSampleBuffer() {
            appendVideo(sample)
        } else {
            if reader.status != .completed {
                print("reader stopped early: status=\(reader.status.rawValue) err=\(String(describing: reader.error))")
            }
            videoInput.markAsFinished()
            maybeFinish()
            break
        }
    }
}

if let audioInput = audioInput, let readerAudio = readerAudio {
    audioInput.requestMediaDataWhenReady(on: queue) {
        while audioInput.isReadyForMoreMediaData {
            if let sample = readerAudio.copyNextSampleBuffer() {
                audioInput.append(sample)
            } else {
                if reader.status != .completed {
                    print("audio reader stopped early: status=\(reader.status.rawValue) err=\(String(describing: reader.error))")
                }
                audioInput.markAsFinished()
                maybeFinish()
                break
            }
        }
    }
}

sema.wait()
if writer.status == .completed && !failed {
    print("OK \(outputURL.lastPathComponent) \(targetW)x\(targetH)")
    fastStart(outputURL)
} else {
    print("FAIL status=\(writer.status.rawValue) failed=\(failed) error=\(String(describing: writer.error)) reader=\(String(describing: reader.error))")
    exit(1)
}

// ---- faststart via AVAssetExportSession passthrough-remux ----
// Moves moov to the front (shouldOptimizeForNetworkUse) without re-encoding,
// and keeps any audio track.
func fastStart(_ url: URL) {
    let sema2 = DispatchSemaphore(value: 0)
    var done = false
    let asset = AVURLAsset(url: url)
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
        print("faststart: export session fail"); return
    }
    let tmp = url.deletingPathExtension().appendingPathExtension("opt.mp4")
    try? FileManager.default.removeItem(at: tmp)
    export.outputURL = tmp
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    export.exportAsynchronously {
        done = export.status == .completed
        sema2.signal()
    }
    sema2.wait()
    guard done else {
        print("faststart: export failed \(String(describing: export.error))")
        return
    }
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.moveItem(at: tmp, to: url)
    print("faststart OK")
}
