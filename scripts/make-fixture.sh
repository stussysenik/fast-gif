#!/usr/bin/env bash
# Generates the canonical reference clip used by the flicker baseline + perf bench.
#
# Content is generated procedurally (deterministic — no RNG, no wall-clock, no
# CoreImage color management) so the signed flicker baseline is reproducible:
#   - Background: a full-spectrum HSV rainbow sweep that PANS horizontally.
#     Many distinct colors → genuine per-frame palette contention at realistic
#     palette sizes (32/64/128), which is what surfaces per-frame palette flicker.
#   - Probe: a 64x64 mid-gray (128,128,128) square at the exact center, byte-
#     identical in every frame. It fully contains the flicker metric's 32x32
#     center sample region, so any inter-frame variance read there is *pure
#     palette flicker* — the defect from the proposal. A correct global-palette
#     encoder drives it toward zero.
#
# Outputs:
#   tests/fixtures/cat-loaf-3s.mov         3s, 240x240, 24fps, H.264 (human-inspectable)
#   tests/fixtures/cat-loaf-3s-frames.bin  raw RGBA dump consumed by the host encoder
#
# .bin layout (little-endian):
#   magic "FGFX" (4) | width u32 | height u32 | count u32 | fps u32 | count*W*H*4 RGBA
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOV="$REPO/tests/fixtures/cat-loaf-3s.mov"
BIN="$REPO/tests/fixtures/cat-loaf-3s-frames.bin"
mkdir -p "$(dirname "$MOV")"

MOV="$MOV" BIN="$BIN" /usr/bin/swift - <<'SWIFT'
import AVFoundation

let movURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOV"]!)
let binURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BIN"]!)
try? FileManager.default.removeItem(at: movURL)
try? FileManager.default.removeItem(at: binURL)

let W = 240, H = 240, FPS: Int32 = 24, DURATION = 3
let frames = DURATION * Int(FPS)
// Probe sized to safely contain the metric's 32x32 center sample while staying a
// MINORITY color (~3% of pixels) — so the per-frame palette is not forced to
// dedicate a stable entry to it, which is exactly when the nearest-entry flips
// frame-to-frame (the flicker defect).
let PROBE = 40
let probeLo = (W - PROBE) / 2, probeHi = probeLo + PROBE   // center 40x40 → [100,140)

func b(_ v: Double) -> UInt8 { UInt8(max(0.0, min(1.0, v)) * 255.0 + 0.5) }

// Render frame `i` into a freshly-allocated RGBA buffer.
// Background: a 2-stop horizontal gradient whose endpoints animate with pan —
// few distinct colors per frame, so at modest palette sizes the budget is
// genuinely contested and the desaturated gray probe sits near a shifting
// quantization boundary.
func renderRGBA(_ i: Int) -> [UInt8] {
    var buf = [UInt8](repeating: 255, count: W * H * 4)
    let pan = Double(i) / Double(frames)
    let c0 = (pan, 0.2, 1.0 - pan)
    let c1 = (1.0 - pan, 0.8, pan)
    for y in 0..<H {
        for x in 0..<W {
            let o = (y * W + x) * 4
            if x >= probeLo && x < probeHi && y >= probeLo && y < probeHi {
                buf[o] = 128; buf[o+1] = 128; buf[o+2] = 128   // static probe
            } else {
                let f = Double(x) / Double(W - 1)
                buf[o]   = b(c0.0 + (c1.0 - c0.0) * f)
                buf[o+1] = b(c0.1 + (c1.1 - c0.1) * f)
                buf[o+2] = b(c0.2 + (c1.2 - c0.2) * f)
            }
        }
    }
    return buf
}

// --- BIN ---
var raw = Data()
raw.append(contentsOf: Array("FGFX".utf8))
func u32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) } }
u32(UInt32(W)); u32(UInt32(H)); u32(UInt32(frames)); u32(UInt32(FPS))

// --- MOV ---
let writer = try AVAssetWriter(outputURL: movURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for i in 0..<frames {
    let rgba = renderRGBA(i)
    raw.append(contentsOf: rgba)

    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self)
    let rowBytes = CVPixelBufferGetBytesPerRow(pb!)
    for y in 0..<H {
        for x in 0..<W {
            let s = (y * W + x) * 4, d = y * rowBytes + x * 4
            base[d]   = rgba[s + 2]   // B
            base[d+1] = rgba[s + 1]   // G
            base[d+2] = rgba[s]       // R
            base[d+3] = rgba[s + 3]   // A
        }
    }
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: FPS))
}

input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
if writer.status == .failed {
    FileHandle.standardError.write("writer failed: \(writer.error!)\n".data(using: .utf8)!)
    exit(1)
}

try raw.write(to: binURL)
print("wrote \(movURL.path)")
print("wrote \(binURL.path) (\(raw.count) bytes, \(frames) frames \(W)x\(H))")
SWIFT
