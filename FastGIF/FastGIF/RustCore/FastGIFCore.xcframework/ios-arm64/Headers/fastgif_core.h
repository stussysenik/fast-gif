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
 * Free a GIFOutput returned by fastgif_encode.
 * Safe to call with NULL. Must not be called more than once per pointer.
 */
void fastgif_free(GIFOutput *output);

/**
 * Quantize one RGBA frame with NeuQuant and return a palette-reconstructed
 * RawFrame whose alpha is preserved. Used by the WYSIWYG preview path.
 *
 * Caller must free with fastgif_raw_frame_free.
 */
RawFrame *fastgif_preview_frame(
    const uint8_t *rgba,
    uint32_t w,
    uint32_t h,
    uint32_t colors
);

/** Free a RawFrame returned by fastgif_preview_frame. Safe to call with NULL. */
void fastgif_raw_frame_free(RawFrame *rf);

#ifdef __cplusplus
}
#endif

#endif /* FASTGIF_CORE_H */
