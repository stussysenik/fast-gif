//! Witness for proposition P4 (quality-verification capability):
//!
//!     palette_error(8 samples) ≤ palette_error(4 samples)
//!
//! Training the global palette over more evenly-spaced frames must not make the
//! whole-clip quantization error worse. If it did, the "sample 8 frames" choice
//! in `train_global_palette` would be unjustified. Measured on the cat-loaf
//! fixture (panning gradient + static probe).

use std::path::PathBuf;
use std::process::Command;

use fastgif_core::{diffuse::nearest_index, train_palette};

fn fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/cat-loaf-3s-frames.bin")
}

/// Read the fixture, regenerating it via make-fixture.sh if absent.
fn read_fixture() -> Option<(usize, usize, usize, Vec<u8>)> {
    let path = fixture_path();
    if !path.exists() {
        let script = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../scripts/make-fixture.sh");
        let _ = Command::new("bash").arg(script).status();
    }
    let data = std::fs::read(&path).ok()?;
    if data.len() < 20 || &data[0..4] != b"FGFX" {
        return None;
    }
    let rd = |o: usize| u32::from_le_bytes([data[o], data[o + 1], data[o + 2], data[o + 3]]) as usize;
    let w = rd(4);
    let h = rd(8);
    let count = rd(12);
    Some((w, h, count, data))
}

fn frames_of(data: &[u8], w: usize, h: usize, count: usize) -> Vec<&[u8]> {
    let fb = w * h * 4;
    (0..count).map(|n| &data[20 + n * fb..20 + (n + 1) * fb]).collect()
}

/// Sum of squared distance from every pixel to its nearest palette entry.
fn palette_error(frames: &[&[u8]], palette: &[u8]) -> u64 {
    let mut total = 0u64;
    for f in frames {
        for px in f.chunks_exact(4) {
            let idx = nearest_index(palette, px[0] as i32, px[1] as i32, px[2] as i32);
            let dr = px[0] as i64 - palette[idx * 3] as i64;
            let dg = px[1] as i64 - palette[idx * 3 + 1] as i64;
            let db = px[2] as i64 - palette[idx * 3 + 2] as i64;
            total += (dr * dr + dg * dg + db * db) as u64;
        }
    }
    total
}

#[test]
fn more_samples_do_not_worsen_palette_error() {
    let Some((w, h, count, data)) = read_fixture() else {
        eprintln!("P4: fixture unavailable — run scripts/make-fixture.sh; skipping");
        return;
    };
    let frames = frames_of(&data, w, h, count);
    let colors = 16;
    let quality = 10;

    let p4 = train_palette(&frames, colors, quality, 4);
    let p8 = train_palette(&frames, colors, quality, 8);

    let e4 = palette_error(&frames, &p4);
    let e8 = palette_error(&frames, &p8);

    eprintln!("P4: palette_error(4)={e4}  palette_error(8)={e8}");
    assert!(
        e8 <= e4,
        "8-sample palette ({e8}) worse than 4-sample ({e4}) — sampling is not sufficient"
    );
}
