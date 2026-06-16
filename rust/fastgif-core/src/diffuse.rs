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

/// True if more than 20% of pixels changed significantly between two RGBA frames
/// (sum of per-channel absolute deltas > 48 ≈ 16/channel). A scene cut resets the
/// temporal error carry so a hard cut doesn't smear the previous frame's error.
/// Integer-only for determinism.
pub fn scene_changed(prev: &[u8], cur: &[u8]) -> bool {
    let n = prev.len().min(cur.len()) / 4;
    if n == 0 {
        return true;
    }
    let mut changed = 0usize;
    for i in 0..n {
        let b = i * 4;
        let d = (prev[b] as i32 - cur[b] as i32).abs()
            + (prev[b + 1] as i32 - cur[b + 1] as i32).abs()
            + (prev[b + 2] as i32 - cur[b + 2] as i32).abs();
        if d > 48 {
            changed += 1;
        }
    }
    changed * 100 > n * 20
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

/// One frame of temporally-coherent Sierra diffusion.
///
/// `carry` is the temporal error buffer (`i32`, `w*h*3`): it is read as this
/// frame's per-pixel seed and overwritten with the residual to feed the next
/// frame. Each pixel's quantization error is split — 3/4 diffuses to spatial
/// neighbours (Sierra2_4a), 1/4 carries to the *same pixel next frame*. Error is
/// conserved, so the feedback loop is bounded: static content converges to a
/// fixed dither pattern (zero temporal flicker) while moving content stays
/// dithered. Integer-only → deterministic.
pub fn diffuse_temporal(
    rgba: &[u8],
    w: usize,
    h: usize,
    palette: &[u8],
    carry: &mut [i32],
) -> Vec<u8> {
    let mut err = carry.to_vec(); // spatial working buffer, seeded by temporal carry
    let mut tnext = vec![0i32; w * h * 3];
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
            let er = dr - palette[idx * 3] as i32;
            let eg = dg - palette[idx * 3 + 1] as i32;
            let eb = db - palette[idx * 3 + 2] as i32;

            // 1/4 of the error feeds the same pixel next frame…
            tnext[e] = er / 4;
            tnext[e + 1] = eg / 4;
            tnext[e + 2] = eb / 4;
            // …the remaining 3/4 diffuses spatially this frame.
            distribute(&mut err, w, h, x, y, er - er / 4, eg - eg / 4, eb - eb / 4);
        }
    }
    carry.copy_from_slice(&tnext);
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
    // SAFETY: in-bounds indices; the slice fully owns the buffer here.
    unsafe { distribute_ptr(err.as_mut_ptr(), w, h, x, y, er, eg, eb) }
}

/// Pointer form of `distribute`, used by the tiled wavefront where a tile may
/// legitimately write into a neighbouring tile's columns (the down-left and
/// right taps). Cross-tile writes are ordered by the wavefront's release/acquire
/// progress fences, so although the buffer is shared, no two writes to the same
/// cell are ever concurrent.
///
/// # Safety
/// `base` must point to a `w*h*3` i32 buffer; `(x,y)` in bounds.
#[inline]
unsafe fn distribute_ptr(base: *mut i32, w: usize, h: usize, x: usize, y: usize, er: i32, eg: i32, eb: i32) {
    #[inline]
    unsafe fn add(base: *mut i32, i: usize, er: i32, eg: i32, eb: i32, num: i32) {
        let e = i * 3;
        *base.add(e) += er * num / 4;
        *base.add(e + 1) += eg * num / 4;
        *base.add(e + 2) += eb * num / 4;
    }
    if x + 1 < w {
        add(base, y * w + (x + 1), er, eg, eb, 2);
    }
    if y + 1 < h {
        if x >= 1 {
            add(base, (y + 1) * w + (x - 1), er, eg, eb, 1);
        }
        add(base, (y + 1) * w + x, er, eg, eb, 1);
    }
}

/// Raw pointer wrapper to share the error/index buffers across scoped threads.
#[derive(Clone, Copy)]
struct SyncPtr<T>(*mut T);
// SAFETY: cross-thread access to the pointed-to buffers is serialised per cell by
// the wavefront's progress fences (see `diffuse_tiled`).
unsafe impl<T> Send for SyncPtr<T> {}
unsafe impl<T> Sync for SyncPtr<T> {}

/// Row-tile *parallel* Sierra2_4a diffusion, byte-identical to
/// `diffuse_sequential` (proposition P1). The frame is split into `tiles` vertical
/// column strips, each driven by its own scoped thread. A strip processing row `y`
/// waits until its left neighbour has finished row `y` and its right neighbour has
/// finished row `y-1` — exactly the Sierra footprint — so the global processing
/// order is a valid topological order of the same dependency graph the sequential
/// raster scan obeys. Result: identical bytes, parallel execution.
///
/// Critical path ≈ O(H + tiles·W/tiles) = O(H + W); with `tiles` strips advancing
/// on a skewed wavefront the throughput approaches `tiles`×.
pub fn diffuse_tiled(
    rgba: &[u8],
    w: usize,
    h: usize,
    palette: &[u8],
    err: &mut [i32],
    tiles: usize,
) -> Vec<u8> {
    let t = tiles.clamp(1, w.max(1));
    if t == 1 || h == 0 {
        return diffuse_sequential(rgba, w, h, palette, err);
    }

    let mut indices = vec![0u8; w * h];
    let bounds: Vec<(usize, usize)> = (0..t).map(|i| (i * w / t, (i + 1) * w / t)).collect();
    let progress: Vec<crossbeam_utils::CachePadded<std::sync::atomic::AtomicIsize>> =
        (0..t).map(|_| crossbeam_utils::CachePadded::new(std::sync::atomic::AtomicIsize::new(-1))).collect();

    let err_ptr = SyncPtr(err.as_mut_ptr());
    let idx_ptr = SyncPtr(indices.as_mut_ptr());

    crossbeam_utils::thread::scope(|scope| {
        for ti in 0..t {
            let (x0, x1) = bounds[ti];
            // Skip empty strips (can happen when tiles > w after clamp edge cases).
            if x0 >= x1 {
                progress[ti].store((h - 1) as isize, std::sync::atomic::Ordering::Release);
                continue;
            }
            let progress = &progress;
            scope.spawn(move |_| {
                use std::sync::atomic::Ordering;
                // Rebind the whole wrappers so the closure captures `SyncPtr`
                // (Send), not the raw `*mut` field (Rust 2021 disjoint capture).
                let err_ptr = err_ptr;
                let idx_ptr = idx_ptr;
                let errp = err_ptr.0;
                let idxp = idx_ptr.0;
                for y in 0..h {
                    if ti > 0 {
                        while progress[ti - 1].load(Ordering::Acquire) < y as isize {
                            std::hint::spin_loop();
                        }
                    }
                    if ti < t - 1 {
                        while progress[ti + 1].load(Ordering::Acquire) < y as isize - 1 {
                            std::hint::spin_loop();
                        }
                    }
                    for x in x0..x1 {
                        let i = y * w + x;
                        let e = i * 3;
                        let base = i * 4;
                        // SAFETY: this strip's cells for row y, plus cross-tile taps
                        // whose target cells are not yet (or no longer) being touched
                        // by the owning strip, per the wavefront ordering above.
                        unsafe {
                            let dr = (rgba[base] as i32 + *errp.add(e)).clamp(0, 255);
                            let dg = (rgba[base + 1] as i32 + *errp.add(e + 1)).clamp(0, 255);
                            let db = (rgba[base + 2] as i32 + *errp.add(e + 2)).clamp(0, 255);
                            let idx = nearest_index(palette, dr, dg, db);
                            *idxp.add(i) = idx as u8;
                            let er = dr - palette[idx * 3] as i32;
                            let eg = dg - palette[idx * 3 + 1] as i32;
                            let eb = db - palette[idx * 3 + 2] as i32;
                            distribute_ptr(errp, w, h, x, y, er, eg, eb);
                        }
                    }
                    progress[ti].store(y as isize, Ordering::Release);
                }
            });
        }
    })
    .expect("diffuse_tiled worker panicked");

    indices
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

    #[test]
    fn temporal_static_content_reaches_stable_cycle() {
        // A flat mid-gray frame between two palette entries. The temporal feedback
        // is error-conserving, so on static content it must settle into a bounded
        // repeating cycle (no divergence). A small period — ideally 1 (fixed
        // point) — means perceptually zero flicker.
        let w = 16;
        let h = 16;
        let palette = [120, 120, 120, 136, 136, 136];
        let frame: Vec<u8> = (0..w * h).flat_map(|_| [128, 128, 128, 255]).collect();
        let mut carry = vec![0i32; w * h * 3];

        let mut history: Vec<Vec<u8>> = Vec::new();
        for _ in 0..40 {
            history.push(diffuse_temporal(&frame, w, h, &palette, &mut carry));
        }
        // The last frame must equal an earlier one within a short period.
        let last = history.last().unwrap();
        let period = (1..=4).find(|&p| history[history.len() - 1 - p] == *last);
        assert!(
            period.is_some(),
            "temporal diffusion did not reach a stable short cycle on static content"
        );
    }

    #[test]
    fn scene_change_detects_cut_and_ignores_noise() {
        let n = 100;
        let a = vec![100u8; n * 4];
        let mut b = a.clone();
        // Tiny noise on a few pixels — not a cut.
        for i in 0..3 {
            b[i * 4] = 105;
        }
        assert!(!scene_changed(&a, &b));
        // Half the pixels jump hard — a cut.
        let mut c = a.clone();
        for i in 0..(n / 2) {
            c[i * 4] = 255;
            c[i * 4 + 1] = 255;
            c[i * 4 + 2] = 255;
        }
        assert!(scene_changed(&a, &c));
    }
}
