//! Witness for proposition P1 (quality-verification capability):
//!
//!     diffuse_tiled(T) ≡ diffuse_sequential   byte-for-byte, for T ∈ {1,2,4,6,8}
//!
//! The row-tile parallel diffuser must produce exactly the same palette indices
//! as the sequential raster scan — otherwise the speedup would silently change
//! the output (and break the determinism guarantee). Measured on a 240×240
//! gradient that exercises real cross-tile error flow.

use fastgif_core::diffuse::{diffuse_sequential, diffuse_tiled};

fn gradient(w: usize, h: usize) -> Vec<u8> {
    let mut px = vec![0u8; w * h * 4];
    for y in 0..h {
        for x in 0..w {
            let o = (y * w + x) * 4;
            px[o] = ((x * 255) / (w - 1)) as u8;
            px[o + 1] = ((y * 255) / (h - 1)) as u8;
            px[o + 2] = (((x + y) * 255) / (w + h - 2)) as u8;
            px[o + 3] = 255;
        }
    }
    px
}

#[test]
fn tiled_matches_sequential_across_tile_counts() {
    let w = 240;
    let h = 240;
    let rgba = gradient(w, h);
    // A non-trivial 16-entry palette (grays + primaries) so quantization error
    // is real and propagates across tile boundaries.
    let palette: Vec<u8> = (0..16)
        .flat_map(|i| {
            let v = (i * 17) as u8;
            [v, v.wrapping_add(40), v.wrapping_add(80)]
        })
        .collect();

    let reference = diffuse_sequential(&rgba, w, h, &palette, &mut vec![0i32; w * h * 3]);

    for &t in &[1usize, 2, 4, 6, 8] {
        let tiled = diffuse_tiled(&rgba, w, h, &palette, &mut vec![0i32; w * h * 3], t);
        assert_eq!(
            tiled, reference,
            "diffuse_tiled({t}) diverged from diffuse_sequential"
        );
    }
}
