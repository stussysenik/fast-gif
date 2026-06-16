#ifndef FASTGIF_CORE_H
#define FASTGIF_CORE_H

#include <stdint.h>
#include <stddef.h>

/**
 * Input frame: raw RGBA pixel data plus frame timing.
 * rgba must point to width * height * 4 bytes of RGBA data.
 */
typedef struct {
    const uint8_t *rgba;
    uint32_t width;
    uint32_t height;
    /** Frame delay in centiseconds (1/100 s). E.g. 4 = 40 ms ≈ 25 fps. */
    uint16_t delay_cs;
} RawFrame;

/**
 * Output buffer holding the encoded GIF bytes.
 * Must be freed with fastgif_free() after use.
 */
typedef struct {
    uint8_t *data;
    size_t len;
} GIFOutput;

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Encode RGBA frames to an optimized GIF using NeuQuant color quantization.
 *
 * @param frames     Pointer to an array of RawFrame structs.
 * @param count      Number of frames.
 * @param colors     Palette size (2–256). Values outside range are clamped.
 * @param loop_count 0 = loop infinitely; N = loop N times.
 * @param quality    NeuQuant sample factor: 1 = best quality (slow), 30 = fastest.
 * @return           Heap-allocated GIFOutput, or NULL on failure.
 *                   Caller must free with fastgif_free().
 */
GIFOutput *fastgif_encode(
    const RawFrame *frames,
    size_t count,
    uint32_t colors,
    uint16_t loop_count,
    int32_t quality
);

/**
 * Encode RGBA frames to a GIF using ONE global palette trained over evenly-spaced
 * frames, plus optional deterministic spatial Sierra2_4a diffusion. This is the
 * zero-flicker path: a pixel constant across frames maps to a constant index.
 *
 * @param frames     Pointer to an array of RawFrame structs.
 * @param count      Number of frames.
 * @param colors     Palette size (2–256). Clamped.
 * @param loop_count 0 = loop infinitely; N = loop N times.
 * @param quality    NeuQuant sample factor for palette training (1=best, 30=fast).
 * @param dither     0 = nearest-color; non-zero = spatial Sierra2_4a diffusion.
 * @return           Heap-allocated GIFOutput, or NULL. Free with fastgif_free().
 */
GIFOutput *fastgif_encode_global(
    const RawFrame *frames,
    size_t count,
    uint32_t colors,
    uint16_t loop_count,
    int32_t quality,
    uint8_t dither
);

/**
 * Quantize frame `target` against the global palette trained over the whole clip,
 * returning a palette-reconstructed RawFrame. Exact preview of what
 * fastgif_encode_global (nearest / draft) ships for that frame.
 *
 * @param frames  Pointer to an array of RawFrame structs.
 * @param count   Number of frames.
 * @param target  Index of the frame to preview (< count).
 * @param colors  Palette size (2–256). Clamped.
 * @param quality NeuQuant sample factor (1=best, 30=fast).
 * @return        Heap-allocated RawFrame, or NULL. Free with fastgif_raw_frame_free().
 */
RawFrame *fastgif_preview_global(
    const RawFrame *frames,
    size_t count,
    size_t target,
    uint32_t colors,
    int32_t quality
);

/**
 * Quantize a single RGBA frame through the same NeuQuant path the GIF encoder
 * uses, returning a palette-reconstructed RawFrame (alpha preserved).
 *
 * Witness for preview↔export parity: given matching `colors` and `quality`,
 * the returned color set is identical to fastgif_encode's for that frame.
 *
 * @param rgba    Pointer to w * h * 4 bytes of RGBA pixel data.
 * @param w       Frame width in pixels.
 * @param h       Frame height in pixels.
 * @param colors  Palette size (2–256). Values outside range are clamped.
 * @param quality NeuQuant sample factor: 1 = best (slow), 30 = fastest.
 * @return        Heap-allocated RawFrame, or NULL on failure.
 *                Caller must free with fastgif_raw_frame_free().
 */
RawFrame *fastgif_preview_frame(
    const uint8_t *rgba,
    uint32_t w,
    uint32_t h,
    uint32_t colors,
    int32_t quality
);

/**
 * Free a RawFrame returned by fastgif_preview_frame.
 * Safe to call with NULL. Must not be called more than once per pointer.
 */
void fastgif_raw_frame_free(RawFrame *rf);

/**
 * Free a GIFOutput returned by fastgif_encode.
 * Safe to call with NULL. Must not be called more than once per pointer.
 */
void fastgif_free(GIFOutput *output);

#ifdef __cplusplus
}
#endif

#endif /* FASTGIF_CORE_H */
