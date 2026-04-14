#!/usr/bin/env bash
# Generates the canonical reference clip used by flicker baseline + perf bench.
# Output: tests/fixtures/cat-loaf-3s.mov  (3s, 240x240, 24fps, H.264)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/tests/fixtures/cat-loaf-3s.mov"
mkdir -p "$(dirname "$OUT")"

OUT="$OUT" /usr/bin/swift - <<'SWIFT'
import AVFoundation
import CoreImage

let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUT"]!)
try? FileManager.default.removeItem(at: url)

let W: Int = 240, H: Int = 240, FPS: Int32 = 24, DURATION: Int = 3
let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W,
    AVVideoHeightKey: H
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: W,
        kCVPixelBufferHeightKey as String: H
    ]
)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let ctx = CIContext()
let frames = DURATION * Int(FPS)
for i in 0..<frames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    let t = Double(i) / Double(frames)
    // A slow horizontal color ramp that pans — guarantees gradient content,
    // which is where per-frame palette flicker is visible.
    let hue = t
    let ci = CIFilter(name: "CILinearGradient", parameters: [
        "inputPoint0": CIVector(x: 0, y: 0),
        "inputPoint1": CIVector(x: CGFloat(W), y: 0),
        "inputColor0": CIColor(red: hue, green: 0.2, blue: 1.0 - hue),
        "inputColor1": CIColor(red: 1.0 - hue, green: 0.8, blue: hue),
    ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    ctx.render(ci, to: pb!)
    let time = CMTime(value: CMTimeValue(i), timescale: FPS)
    adaptor.append(pb!, withPresentationTime: time)
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
if writer.status == .failed { FileHandle.standardError.write("writer failed: \(writer.error!)\n".data(using: .utf8)!); exit(1) }
print("wrote \(url.path)")
SWIFT
