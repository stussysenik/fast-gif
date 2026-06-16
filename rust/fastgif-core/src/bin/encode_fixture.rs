//! Host-side fixture encoder for the verification harness.
//!
//! Reads the raw RGBA dump produced by `scripts/make-fixture.sh`, runs it
//! through the *current* `fastgif_encode` FFI exactly as the app's export path
//! would, and writes a `.gif`. This is what lets the flicker gate measure the
//! real encoder on the host (no simulator) so the baseline is honest.
//!
//! Usage: encode_fixture <frames.bin> <out.gif> [--colors N] [--quality Q] [--global]
//!
//! `--global` routes through `fastgif_encode_global` (added in C3); without it
//! the per-frame `fastgif_encode` is used. Until C3 lands, only the default
//! (per-frame) path exists.

use std::fs;
use std::process::exit;

use fastgif_core::{fastgif_encode, fastgif_encode_global, fastgif_free, RawFrame};

fn die(msg: &str) -> ! {
    eprintln!("encode_fixture: {msg}");
    exit(1);
}

fn read_u32(buf: &[u8], off: usize) -> u32 {
    u32::from_le_bytes([buf[off], buf[off + 1], buf[off + 2], buf[off + 3]])
}

fn main() {
    let argv: Vec<String> = std::env::args().collect();
    if argv.len() < 3 {
        die("usage: encode_fixture <frames.bin> <out.gif> [--colors N] [--quality Q] [--global]");
    }
    let in_path = &argv[1];
    let out_path = &argv[2];

    let mut colors: u32 = 256;
    let mut quality: i32 = 10;
    let mut global = false;
    let mut dither: u8 = 1;
    let mut i = 3;
    while i < argv.len() {
        match argv[i].as_str() {
            "--colors" => { i += 1; colors = argv[i].parse().unwrap_or(256); }
            "--quality" => { i += 1; quality = argv[i].parse().unwrap_or(10); }
            "--global" => { global = true; }
            "--no-dither" => { dither = 0; }
            other => die(&format!("unexpected arg: {other}")),
        }
        i += 1;
    }

    let data = fs::read(in_path).unwrap_or_else(|e| die(&format!("read {in_path}: {e}")));
    if data.len() < 20 || &data[0..4] != b"FGFX" {
        die("bad fixture: missing FGFX header");
    }
    let w = read_u32(&data, 4);
    let h = read_u32(&data, 8);
    let count = read_u32(&data, 12) as usize;
    let fps = read_u32(&data, 16);
    let frame_bytes = (w as usize) * (h as usize) * 4;
    let delay_cs = ((100.0 / fps as f64).round() as u16).max(1);

    let expected = 20 + count * frame_bytes;
    if data.len() != expected {
        die(&format!("bad fixture size: got {}, expected {}", data.len(), expected));
    }

    // Build RawFrame structs pointing into `data` (kept alive for the call).
    let frames: Vec<RawFrame> = (0..count)
        .map(|n| {
            let start = 20 + n * frame_bytes;
            RawFrame {
                rgba: data[start..].as_ptr(),
                width: w,
                height: h,
                delay_cs,
            }
        })
        .collect();

    // SAFETY: `frames` outlives the call; each `rgba` points to w*h*4 bytes in `data`.
    // The global path applies spatial Sierra diffusion (dither=1), representing the
    // `best` export tier the flicker gate measures.
    let out = if global {
        unsafe { fastgif_encode_global(frames.as_ptr(), frames.len(), colors, 0, quality, dither, std::ptr::null()) }
    } else {
        unsafe { fastgif_encode(frames.as_ptr(), frames.len(), colors, 0, quality) }
    };
    if out.is_null() {
        die("encode returned null");
    }

    // SAFETY: `out` is a valid GIFOutput from fastgif_encode.
    let gif: Vec<u8> = unsafe {
        let o = &*out;
        std::slice::from_raw_parts(o.data, o.len).to_vec()
    };
    unsafe { fastgif_free(out) };

    fs::write(out_path, &gif).unwrap_or_else(|e| die(&format!("write {out_path}: {e}")));
    eprintln!(
        "encode_fixture: wrote {} ({} bytes, {} frames, colors={}, quality={})",
        out_path, gif.len(), count, colors, quality
    );
}
