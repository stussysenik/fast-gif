//! Deterministic, fixed-point error diffusion (Sierra2_4a, a.k.a. "Sierra Lite").
//!
//! Every operation is integer arithmetic, so the output is byte-identical across
//! architectures — this is what backs the determinism guarantee (proposition P5).
//! The error is carried in an `i32` buffer (R,G,B interleaved, one triple per
//! pixel) so callers can either zero-seed it for spatial-only diffusion (C3) or
//! thread it across frames for temporal diffusion (C4).

/// Nearest palette entry by integer squared-euclidean distance, via a linear
/// scan over the (≤256-entry) palette. Deterministic and arch-independent — this
/// single lookup is shared by the encoder, the preview, and the diffuser so that
/// "what you preview" is provably "what you export".
#[inline]
pub fn nearest_index(palette: &[u8], r: i32, g: i32, b: i32) -> usize {
    let n = palette.len() / 3;
    let mut best = 0usize;
    let mut best_d = i32::MAX;
    for i in 0..n {
        let pr = palette[i * 3] as i32;
        let pg = palette[i * 3 + 1] as i32;
        let pb = palette[i * 3 + 2] as i32;
        let dr = r - pr;
        let dg = g - pg;
        let db = b - pb;
        let d = dr * dr + dg * dg + db * db;
        if d < best_d {
            best_d = d;
            best = i;
            if d == 0 {
                break;
            }
        }
    }
    best
}

/// Map every pixel to its nearest palette index, no diffusion. Used by the
/// `draft` tier and as the parity reference for the preview path.
pub fn map_nearest(rgba: &[u8], palette: &[u8]) -> Vec<u8> {
    rgba.chunks_exact(4)
        .map(|px| nearest_index(palette, px[0] as i32, px[1] as i32, px[2] as i32) as u8)
        .collect()
}

/// Sierra2_4a spatial diffusion over one frame in raster order.
///
/// `err` is an `i32` error buffer of length `w*h*3` (R,G,B interleaved). It is
/// read as the per-pixel seed (zero for spatial-only) and accumulated into as
/// error is pushed forward. Returns the palette-index buffer (`w*h` bytes).
pub fn diffuse_sequential(
    rgba: &[u8],
    w: usize,
    h: usize,
    palette: &[u8],
    err: &mut [i32],
) -> Vec<u8> {
    let mut indices = vec![0u8; w * h];
    for y in 0..h {
        for x in 0..w {
            let i = y * w + x;
            let e = i * 3;
            let base = i * 4;
            let dr = (rgba[base] as i32 + err[e]).clamp(0, 255);
            let dg = (rgba[base + 1] as i32 + err[e + 1]).clamp(0, 255);
            let db = (rgba[base + 2] as i32 + err[e + 2]).clamp(0, 255);

            let idx = nearest_index(palette, dr, dg, db);
            indices[i] = idx as u8;

            let qr = palette[idx * 3] as i32;
            let qg = palette[idx * 3 + 1] as i32;
            let qb = palette[idx * 3 + 2] as i32;
            distribute(err, w, h, x, y, dr - qr, dg - qg, db - qb);
        }
    }
    indices
}

/// Sierra2_4a kernel (divisor 4):
/// ```text
///        *  2
///    1   1
/// ```
/// i.e. (x+1,y)+=2/4, (x-1,y+1)+=1/4, (x,y+1)+=1/4. Integer division truncates
/// deterministically.
#[inline]
fn distribute(err: &mut [i32], w: usize, h: usize, x: usize, y: usize, er: i32, eg: i32, eb: i32) {
    #[inline]
    fn add(err: &mut [i32], i: usize, er: i32, eg: i32, eb: i32, num: i32) {
        let e = i * 3;
        err[e] += er * num / 4;
        err[e + 1] += eg * num / 4;
        err[e + 2] += eb * num / 4;
    }
    if x + 1 < w {
        add(err, y * w + (x + 1), er, eg, eb, 2);
    }
    if y + 1 < h {
        if x >= 1 {
            add(err, (y + 1) * w + (x - 1), er, eg, eb, 1);
        }
        add(err, (y + 1) * w + x, er, eg, eb, 1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nearest_picks_exact_match() {
        let palette = [0, 0, 0, 255, 255, 255, 255, 0, 0];
        assert_eq!(nearest_index(&palette, 250, 5, 5), 2);
        assert_eq!(nearest_index(&palette, 10, 10, 10), 0);
        assert_eq!(nearest_index(&palette, 240, 240, 240), 1);
    }

    #[test]
    fn diffuse_is_deterministic() {
        // Same input twice → identical indices (the core of determinism).
        let w = 8;
        let h = 8;
        let palette = [0, 0, 0, 255, 255, 255];
        let rgba: Vec<u8> = (0..w * h)
            .flat_map(|i| [(i * 3) as u8, (i * 5) as u8, (i * 7) as u8, 255])
            .collect();
        let a = diffuse_sequential(&rgba, w, h, &palette, &mut vec![0i32; w * h * 3]);
        let b = diffuse_sequential(&rgba, w, h, &palette, &mut vec![0i32; w * h * 3]);
        assert_eq!(a, b);
    }
}
