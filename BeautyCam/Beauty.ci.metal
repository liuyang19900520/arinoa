#include <CoreImage/CoreImage.h>
using namespace metal;

// MARK: - helpers (not exported as kernels)

static inline float3 toGamma(float3 c) { return pow(max(c, 0.0), float3(1.0 / 2.2)); }
static inline float3 toLinear(float3 c) { return pow(max(c, 0.0), float3(2.2)); }

// YCbCr skin probability (classic Cb 77..127, Cr 133..173 range, softened).
static inline float skinProb(float3 g) {
    float y  = 0.299 * g.r + 0.587 * g.g + 0.114 * g.b;
    float cb = 0.5 - 0.168736 * g.r - 0.331264 * g.g + 0.5 * g.b;
    float cr = 0.5 + 0.5 * g.r - 0.418688 * g.g - 0.081312 * g.b;
    float pcb = smoothstep(0.26, 0.31, cb) * (1.0 - smoothstep(0.50, 0.55, cb));
    float pcr = smoothstep(0.49, 0.53, cr) * (1.0 - smoothstep(0.68, 0.72, cr));
    float py  = smoothstep(0.06, 0.18, y);
    return pcb * pcr * py;
}

// Smooth falloff: 1 at the center, 0 at the rim, with zero slope at the rim so the warped
// region blends into the untouched image without a visible edge.
static inline float falloff(float x) {
    float a = 1.0 - x * x;
    return a * a;
}

// Local translation: content near c is pulled toward m. Displacement gradient stays below
// ~1.54 * |m - c| / R, so with |m - c| well under R the mapping never folds over.
static inline float2 slimWarp(float2 p, float2 c, float2 m, float R) {
    float d = length(p - c);
    if (d >= R) return p;
    return p - falloff(d / R) * (m - c);
}

// Local scaling: magnifies content around c by up to 1 / (1 - k) at the center.
static inline float2 eyeWarp(float2 p, float2 c, float R, float k) {
    float2 pc = p - c;
    float d = length(pc);
    if (d >= R) return p;
    return c + pc * (1.0 - k * falloff(d / R));
}

extern "C" { namespace coreimage {

// Skin retouching: edge-preserving smoothing + log-curve brightening, applied only inside a
// soft face ellipse and only where the color looks like skin. Background pixels return untouched.
//   fc / axes / rot: face ellipse center, semi-axes, (cos, sin) of the head roll.
float4 beautySkin(sampler src, float radius, float smooth, float sigmaR, float beta,
                  float2 fc, float2 axes, float2 rot, destination dest) {
    float2 d = dest.coord();
    float4 c = src.sample(src.transform(d));

    float2 q = d - fc;
    float2 r = float2(q.x * rot.x + q.y * rot.y, -q.x * rot.y + q.y * rot.x);
    float face = 1.0 - smoothstep(0.75, 1.0, length(r / axes));
    if (face <= 0.0) return c;
    float3 cg = toGamma(c.rgb);
    float skin = skinProb(cg) * face;
    if (skin <= 0.001) return c;

    float3 outc = c.rgb;
    if (smooth > 0.001) {
        float3 sum = c.rgb;
        float wsum = 1.0;
        for (int ring = 1; ring <= 3; ring++) {
            float rr = float(ring) / 3.0;
            float spatial = exp(-2.0 * rr * rr);
            for (int i = 0; i < 8; i++) {
                float a = float(i) * 0.785398 + float(ring) * 0.392699;
                float2 off = float2(cos(a), sin(a)) * radius * rr;
                float4 s = src.sample(src.transform(d + off));
                float diff = length(toGamma(s.rgb) - cg);
                float w = spatial * exp(-(diff * diff) / (2.0 * sigmaR * sigmaR));
                sum += s.rgb * w;
                wsum += w;
            }
        }
        // Never fully replace the pixel: the remainder keeps visible skin texture.
        outc = mix(c.rgb, sum / wsum, smooth * skin);
    }
    if (beta > 1.001) {
        float3 g = toGamma(outc);
        float3 w = log(g * (beta - 1.0) + 1.0) / log(beta);
        outc = toLinear(mix(g, w, skin));
    }
    return float4(outc, c.a);
}

// Face reshaping: slim both cheeks, then enlarge both eyes.
// A sampler kernel (not a CIWarpKernel) so the input region is explicit and tiling can't
// hand it too little source data.
float4 beautyWarp(sampler src, float2 le, float2 re, float eyeR, float eyeK,
                  float2 lc, float2 lt, float2 rc, float2 rt, float slimR,
                  destination dest) {
    float2 p = dest.coord();
    p = slimWarp(p, lc, lt, slimR);
    p = slimWarp(p, rc, rt, slimR);
    p = eyeWarp(p, le, eyeR, eyeK);
    p = eyeWarp(p, re, eyeR, eyeK);
    return src.sample(src.transform(p));
}

}}
