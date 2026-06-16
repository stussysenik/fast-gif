//! FastGIF Rust Core — NeuQuant quantization + GIF encoding.
//! C FFI for Swift bridging.
//!
//! color_quant::NeuQuant stores the color map in RGBA order internally.
//! `lookup(idx)` returns `[r, g, b, a]` (confirmed from source: p.r, p.g, p.b, p.a).
//! We use `color_map_rgb()` directly to build the GIF palette — it emits R, G, B per entry.

use std::borrow::Cow;
use std::ptr;
use std::slice;

/// Input frame: raw RGBA pixels + timing.
#[repr(C)]
pub struct RawFrame {
    pub rgba: *const u8,
    pub width: u32,
    pub height: u32,
    /// Frame delay in centiseconds (1/100 s). E.g. 4 = 40ms ≈ 25fps.
    pub delay_cs: u16,
}

/// Output: GIF data buffer. Free with `fastgif_free`.
#[repr(C)]
pub struct GIFOutput {
    pub data: *mut u8,
    pub len: usize,
}

/// Encode RGBA frames into an optimized GIF using NeuQuant quantization.
///
/// # Parameters
/// - `frames_ptr`: pointer to `count` RawFrame structs
/// - `count`: number of frames
/// - `colors`: palette size (2–256; clamped)
/// - `loop_count`: 0 = infinite loop; N > 0 = loop N times
/// - `quality`: NeuQuant sample factor (1 = best quality/slowest, 30 = fastest/lower quality)
///
/// # Safety
/// - `frames_ptr` must point to `count` valid `RawFrame` structs for the duration of the call
/// - Each `RawFrame.rgba` must point to `width * height * 4` bytes of RGBA pixel data
/// - Returns null on any failure; caller must free with `fastgif_free`
#[no_mangle]
pub unsafe extern "C" fn fastgif_encode(
    frames_ptr: *const RawFrame,
    count: usize,
    colors: u32,
    loop_count: u16,
    quality: i32,
) -> *mut GIFOutput {
    if frames_ptr.is_null() || count == 0 {
        return ptr::null_mut();
    }

    let raw_frames = slice::from_raw_parts(frames_ptr, count);
    let w = raw_frames[0].width as u16;
    let h = raw_frames[0].height as u16;
    let num_colors = (colors as usize).clamp(2, 256);
    // NeuQuant sample factor: 1 = highest quality, 30 = fastest
    let sample_fac = quality.clamp(1, 30);

    let mut buf: Vec<u8> = Vec::with_capacity(count * 4096);

    let result = (|| -> Result<(), gif::EncodingError> {
        // No global palette — each frame carries its own local palette
        let mut enc = gif::Encoder::new(&mut buf, w, h, &[])?;

        let repeat = if loop_count == 0 {
            gif::Repeat::Infinite
        } else {
            gif::Repeat::Finite(loop_count)
        };
        enc.set_repeat(repeat)?;

        for rf in raw_frames {
            let pixel_count = (rf.width * rf.height) as usize;
            let rgba = slice::from_raw_parts(rf.rgba, pixel_count * 4);

            // NeuQuant color quantization.
            // new(samplefac, colors, pixels) trains the network immediately.
            // Input is RGBA; lookup() and color_map_rgb() return colors in R, G, B order.
            let nq = color_quant::NeuQuant::new(sample_fac, num_colors, rgba);

            // Build the GIF local palette as packed RGB triples (R, G, B per entry).
            // color_map_rgb() emits entries as [r, g, b, r, g, b, ...] — correct for GIF.
            let palette = nq.color_map_rgb();

            // Map each RGBA pixel to its nearest palette index.
            let mut indices = Vec::with_capacity(pixel_count);
            for px in rgba.chunks_exact(4) {
                indices.push(nq.index_of(px) as u8);
            }

            let mut frame = gif::Frame::default();
            frame.width = rf.width as u16;
            frame.height = rf.height as u16;
            frame.delay = rf.delay_cs;
            frame.palette = Some(palette);
            frame.buffer = Cow::Owned(indices);

            enc.write_frame(&frame)?;
        }
        Ok(())
    })();

    if result.is_err() {
        return ptr::null_mut();
    }

    let len = buf.len();
    let data = {
        let mut boxed = buf.into_boxed_slice();
        let ptr_inner = boxed.as_mut_ptr();
        std::mem::forget(boxed);
        ptr_inner
    };

    Box::into_raw(Box::new(GIFOutput { data, len }))
}

/// Runs one-frame NeuQuant on `rgba` and returns a RawFrame whose pixels are
/// the palette-reconstructed image. Preserves alpha. Caller frees with
/// `fastgif_raw_frame_free`.
///
/// This is the witness for §P3 (preview_parity): it goes through the same
/// `NeuQuant::new(quality, colors, ..)` + `index_of` pipeline as `fastgif_encode`,
/// so when the preview and the draft export are given the *same* `colors` and
/// `quality` the resulting color sets are identical by construction.
///
/// # Safety
/// - `rgba` must point to `w * h * 4` bytes.
/// - Returns null on bad input; caller must free with `fastgif_raw_frame_free`.
#[no_mangle]
pub unsafe extern "C" fn fastgif_preview_frame(
    rgba: *const u8,
    w: u32,
    h: u32,
    colors: u32,
    quality: i32,
) -> *mut RawFrame {
    if rgba.is_null() || w == 0 || h == 0 {
        return ptr::null_mut();
    }
    let n_px = (w as usize) * (h as usize);
    let input = slice::from_raw_parts(rgba, n_px * 4);
    let num_colors = (colors as usize).clamp(2, 256);
    let sample_fac = quality.clamp(1, 30);
    let nq = color_quant::NeuQuant::new(sample_fac, num_colors, input);

    // Build palette-reconstructed RGBA so the caller sees the exact post-quantize
    // pixels the GIF would carry.
    let mut out_pixels = vec![0u8; n_px * 4];
    let palette = nq.color_map_rgb();
    for (dst, src) in out_pixels.chunks_exact_mut(4).zip(input.chunks_exact(4)) {
        let idx = nq.index_of(src);
        let base = idx * 3;
        dst[0] = palette[base];
        dst[1] = palette[base + 1];
        dst[2] = palette[base + 2];
        dst[3] = src[3]; // preserve alpha
    }

    let mut boxed = out_pixels.into_boxed_slice();
    let rgba_ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);

    Box::into_raw(Box::new(RawFrame {
        rgba: rgba_ptr,
        width: w,
        height: h,
        delay_cs: 0,
    }))
}

/// Free a `RawFrame` returned by `fastgif_preview_frame`.
///
/// # Safety
/// - `rf` must be a pointer returned by `fastgif_preview_frame`, or null.
/// - Must not be called more than once for a given pointer.
#[no_mangle]
pub unsafe extern "C" fn fastgif_raw_frame_free(rf: *mut RawFrame) {
    if rf.is_null() {
        return;
    }
    let boxed = Box::from_raw(rf);
    let n = (boxed.width as usize) * (boxed.height as usize) * 4;
    drop(Vec::from_raw_parts(boxed.rgba as *mut u8, n, n));
}

/// Free a `GIFOutput` returned by `fastgif_encode`.
///
/// # Safety
/// - `output` must be a pointer returned by `fastgif_encode`, or null
/// - Must not be called more than once for a given pointer
#[no_mangle]
pub unsafe extern "C" fn fastgif_free(output: *mut GIFOutput) {
    if !output.is_null() {
        let o = Box::from_raw(output);
        if !o.data.is_null() {
            // Reconstruct the Vec to properly deallocate
            drop(Vec::from_raw_parts(o.data, o.len, o.len));
        }
        // o is dropped here, freeing the GIFOutput box
    }
}
