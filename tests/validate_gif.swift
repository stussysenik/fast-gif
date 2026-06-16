#!/usr/bin/env swift
// Usage:
//   swift tests/validate_gif.swift <path-to-gif> [--expected-frames N]
//                                                [--expected-duration S]
//                                                [--mode best|good|draft]
//                                                [--baseline tests/fixtures/flicker-baseline.txt]
//                                                [--alpha 0.3]
//
// Exits non-zero with a diagnostic on any failed check.
//
// Flicker metric: reads palette indices in a 32x32 region centered at the
// midpoint, computes per-pixel variance across frames, averages them.
// This is `flicker(gif)` in §9.P2.

import Foundation
import ImageIO
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

struct Args {
    var path: String
    var expectedFrames: Int = 24
    var expectedDuration: Double = 3.0
    var mode: String = "best"
    var baseline: String = "tests/fixtures/flicker-baseline.txt"
    var alpha: Double = 0.3
    var emitBaseline: Bool = false
}

var args = Args(path: "")
var i = 1
let argv = CommandLine.arguments
while i < argv.count {
    let a = argv[i]
    switch a {
    case "--expected-frames": i += 1; args.expectedFrames = Int(argv[i]) ?? 24
    case "--expected-duration": i += 1; args.expectedDuration = Double(argv[i]) ?? 3.0
    case "--mode": i += 1; args.mode = argv[i]
    case "--baseline": i += 1; args.baseline = argv[i]
    case "--alpha": i += 1; args.alpha = Double(argv[i]) ?? 0.3
    case "--emit-baseline": args.emitBaseline = true
    default: if args.path.isEmpty { args.path = a } else { die("unexpected arg: \(a)") }
    }
    i += 1
}
if args.path.isEmpty { die("usage: validate_gif.swift <path> [...]") }

let url = URL(fileURLWithPath: args.path)
guard let data = try? Data(contentsOf: url) else { die("read failed: \(args.path)") }

// -- Check 1: GIF89a header
let header = data.prefix(6)
guard header == Data("GIF89a".utf8) else { die("header mismatch: \(header.map { String(format: "%02x", $0) }.joined())") }
print("ok: header GIF89a")

// -- Check 2: Frame count
guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { die("CGImageSourceCreateWithData failed") }
let n = CGImageSourceGetCount(src)
if n < args.expectedFrames { die("frames: got \(n), expected >= \(args.expectedFrames)") }
print("ok: \(n) frames")

// -- Check 3: Duration within ±5%
var total: Double = 0
for f in 0..<n {
    let props = CGImageSourceCopyPropertiesAtIndex(src, f, nil) as? [CFString: Any]
    let gifDict = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    let delay = (gifDict?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
    total += delay
}
let lower = args.expectedDuration * 0.95
let upper = args.expectedDuration * 1.05
if total < lower || total > upper {
    die("duration: got \(total), expected \(args.expectedDuration) ±5%")
}
print("ok: duration \(String(format: "%.3f", total))s")

// -- Check 4: Global color table bit (Best mode only)
// LSD packed field is at offset 10; bit 7 is the GCT flag.
if args.mode == "best" {
    let packed = data[10]
    if (packed & 0x80) == 0 { die("global color table bit not set (Best mode requires GCT)") }
    print("ok: global color table present")
}

// -- Check 5: Flicker metric
// Sample a 32x32 region at the center across all frames.
// Variance of palette-quantized RGB across frames, averaged per pixel.
let REGION = 32
var samples: [[SIMD3<Double>]] = [] // per frame: REGION*REGION values
for f in 0..<n {
    guard let cg = CGImageSourceCreateImageAtIndex(src, f, nil) else { die("decode frame \(f)") }
    let W = cg.width, H = cg.height
    let x0 = (W - REGION) / 2, y0 = (H - REGION) / 2
    let bpr = REGION * 4
    var buf = [UInt8](repeating: 0, count: bpr * REGION)
    let ctx = CGContext(
        data: &buf, width: REGION, height: REGION,
        bitsPerComponent: 8, bytesPerRow: bpr,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.translateBy(x: -CGFloat(x0), y: -CGFloat(y0))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    var pixels = [SIMD3<Double>](); pixels.reserveCapacity(REGION * REGION)
    for p in stride(from: 0, to: buf.count, by: 4) {
        pixels.append(SIMD3<Double>(Double(buf[p]), Double(buf[p+1]), Double(buf[p+2])))
    }
    samples.append(pixels)
}
let K = REGION * REGION
var flicker: Double = 0
for p in 0..<K {
    var mean = SIMD3<Double>(0, 0, 0)
    for s in samples { mean += s[p] }
    mean /= Double(n)
    var variance: Double = 0
    for s in samples {
        let d = s[p] - mean
        variance += (d.x*d.x + d.y*d.y + d.z*d.z)
    }
    flicker += variance / Double(n)
}
flicker /= Double(K)
print("flicker: \(String(format: "%.4f", flicker))")

// Two modes:
// 1. --emit-baseline writes the flicker value to the baseline file + hash.
// 2. default reads the baseline and asserts flicker <= max(alpha * B0, 0.5).
if args.emitBaseline {
    let b = "B0=\(flicker)\n"
    try b.write(toFile: args.baseline, atomically: true, encoding: .utf8)
    // Sign with git hash-object for tamper check.
    let p = Process()
    p.launchPath = "/usr/bin/env"
    p.arguments = ["git", "hash-object", args.baseline]
    let pipe = Pipe()
    p.standardOutput = pipe
    try p.run(); p.waitUntilExit()
    let hash = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    try (b + "HASH=\(hash)\n").write(toFile: args.baseline, atomically: true, encoding: .utf8)
    print("ok: emitted baseline B0=\(flicker) hash=\(hash)")
    exit(0)
}

guard let baselineText = try? String(contentsOfFile: args.baseline) else {
    die("missing baseline: \(args.baseline) — run with --emit-baseline first")
}
let b0Line = baselineText.split(separator: "\n").first { $0.hasPrefix("B0=") }
guard let b0Str = b0Line?.split(separator: "=").last, let B0 = Double(b0Str) else {
    die("baseline unreadable")
}
let bound = max(args.alpha * B0, 0.5)
if flicker > bound {
    die("flicker \(flicker) > bound \(bound) (alpha=\(args.alpha), B0=\(B0))")
}
print("ok: flicker \(String(format: "%.4f", flicker)) <= bound \(String(format: "%.4f", bound)) (alpha=\(args.alpha), B0=\(B0))")
