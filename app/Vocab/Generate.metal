#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The forming card (FormingCard.swift). Technique after Bencho's "Generate" block (MIT):
// a drifting noise displacement, then a blur, then contrast that turns about the paper.

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

// Two octaves, like feTurbulence numOctaves="2".
static float fbm(float2 p) {
    return 0.62 * valueNoise(p) + 0.38 * valueNoise(p * 2.03 + 17.0);
}

/// Liquid surface: each point samples from a noise-shifted neighbour.
/// `scale` matches feDisplacementMap's scale (offset = scale × (noise − 0.5)).
[[ stitchable ]] float2 generateRipple(float2 position, float scale, float frequency) {
    float2 p = position * frequency;
    float2 d = float2(fbm(p), fbm(p * float2(1.0, 1.3) + float2(31.4, 47.2))) - 0.5;
    return position + d * scale;
}

/// Contrast about the paper's luminance rather than mid-grey: the ground holds and the ink deepens.
[[ stitchable ]] half4 paperContrast(float2 position, half4 color, float k, float paper) {
    if (color.a <= 0.0h) { return color; }
    half3 c = color.rgb / color.a;
    c = clamp((c - half(paper)) * half(k) + half(paper), 0.0h, 1.0h);
    return half4(c * color.a, color.a);
}
