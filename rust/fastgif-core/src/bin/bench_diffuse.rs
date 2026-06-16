//! Wall-clock benchmark for the row-tile diffusion speedup (task 5.4 / P-perf).
//!
//! Times `diffuse_sequential` vs `diffuse_tiled(T)` over a stack of frames the
//! size of a real export, and prints the speedup. Run with --release.
//!
//! Usage: bench_diffuse [w] [h] [frames] [tiles]

use std::time::Instant;

use fastgif_core::diffuse::{diffuse_sequential, diffuse_tiled};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let w: usize = a.get(1).and_then(|s| s.parse().ok()).unwrap_or(480);
    let h: usize = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(480);
    let frames: usize = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(72);
    let tiles: usize = a.get(4).and_then(|s| s.parse().ok()).unwrap_or(8);

    // Deterministic gradient stack.
    let mut stack: Vec<Vec<u8>> = Vec::with_capacity(frames);
    for f in 0..frames {
        let mut px = vec![0u8; w * h * 4];
        for y in 0..h {
            for x in 0..w {
                let o = (y * w + x) * 4;
                px[o] = (((x + f) * 255) / (w + frames)) as u8;
                px[o + 1] = ((y * 255) / h) as u8;
                px[o + 2] = (((x + y) * 255) / (w + h)) as u8;
                px[o + 3] = 255;
            }
        }
        stack.push(px);
    }
    let palette: Vec<u8> = (0..16)
        .flat_map(|i| {
            let v = (i * 17) as u8;
            [v, v.wrapping_add(40), v.wrapping_add(80)]
        })
        .collect();

    // Reuse one error buffer (zeroed per frame) so the measurement reflects the
    // diffusion work, not repeated 12 MB allocations.
    let mut err = vec![0i32; w * h * 3];
    let mut sink = 0u64;

    let t0 = Instant::now();
    for px in &stack {
        err.fill(0);
        let idx = diffuse_sequential(px, w, h, &palette, &mut err);
        sink = sink.wrapping_add(idx[0] as u64);
    }
    let seq = t0.elapsed();

    let t1 = Instant::now();
    for px in &stack {
        err.fill(0);
        let idx = diffuse_tiled(px, w, h, &palette, &mut err, tiles);
        sink = sink.wrapping_add(idx[0] as u64);
    }
    let til = t1.elapsed();

    let speedup = seq.as_secs_f64() / til.as_secs_f64();
    let verdict = if speedup >= 3.0 { "MEETS 3x" } else { "below 3x target" };
    println!(
        "bench_diffuse {w}x{h} x{frames} tiles={tiles}: sequential={:.3}s tiled={:.3}s speedup={:.2}x [{verdict}] (sink={sink})",
        seq.as_secs_f64(),
        til.as_secs_f64(),
        speedup
    );
}
