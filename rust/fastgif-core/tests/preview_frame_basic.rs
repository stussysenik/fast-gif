use std::slice;
use fastgif_core::{fastgif_preview_frame, fastgif_raw_frame_free};

#[test]
fn preview_returns_quantized_frame_same_dims() {
    let w: u32 = 16;
    let h: u32 = 16;
    let mut pixels = vec![0u8; (w * h * 4) as usize];
    for i in 0..(w * h) as usize {
        pixels[i * 4] = (i as u8).wrapping_mul(7);
        pixels[i * 4 + 1] = (i as u8).wrapping_mul(11);
        pixels[i * 4 + 2] = (i as u8).wrapping_mul(13);
        pixels[i * 4 + 3] = 255;
    }
    unsafe {
        let out = fastgif_preview_frame(pixels.as_ptr(), w, h, 32, 10);
        assert!(!out.is_null(), "fastgif_preview_frame returned null");
        let rf = &*out;
        assert_eq!(rf.width, w);
        assert_eq!(rf.height, h);
        let out_rgba = slice::from_raw_parts(rf.rgba, (w * h * 4) as usize);
        for i in 0..(w * h) as usize {
            assert_eq!(out_rgba[i * 4 + 3], 255, "alpha not preserved at pixel {}", i);
        }
        let mut seen = std::collections::HashSet::new();
        for px in out_rgba.chunks_exact(4) {
            seen.insert((px[0], px[1], px[2]));
        }
        assert!(seen.len() <= 32, "palette budget exceeded: {}", seen.len());
        fastgif_raw_frame_free(out);
    }
}
