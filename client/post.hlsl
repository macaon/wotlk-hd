// Post-processing for effects.cpp (D3D9, shader model 3), compiled by shaders.sh into shaders.h.
// SMAA: Jimenez et al., MIT (cache/smaa, iryoku/smaa), driven as in its own D3D9 demo.
// CAS: AMD FidelityFX Contrast Adaptive Sharpening, MIT, the sharpen-only filter.
//
// Samplers (effects.cpp sets their states): s0 colour, gamma space; s1 colour, sRGB read (linear);
// s2 SMAA edges; s3 SMAA blend weights; s4 SMAA area texture; s5 SMAA search texture.
// c0: render target metrics (1/w, 1/h, w, h); c1.x: CAS peak, -1 / lerp(8, 5, sharpness).

float4 rt_metrics : register(c0);
float4 cas_params : register(c1);

#define SMAA_HLSL_3
#define SMAA_PRESET_HIGH
#define SMAA_RT_METRICS rt_metrics
#include "SMAA.hlsl"

sampler2D color_gamma : register(s0);
sampler2D color_linear : register(s1);
sampler2D edges_tex : register(s2);
sampler2D blend_tex : register(s3);
sampler2D area_tex : register(s4);
sampler2D search_tex : register(s5);

void quad_vs(inout float4 position : POSITION, inout float2 texcoord : TEXCOORD0) {}

void smaa_edges_vs(inout float4 position : POSITION, inout float2 texcoord : TEXCOORD0,
                   out float4 offset[3] : TEXCOORD1) {
    SMAAEdgeDetectionVS(texcoord, offset);
}

void smaa_weights_vs(inout float4 position : POSITION, inout float2 texcoord : TEXCOORD0,
                     out float2 pixcoord : TEXCOORD1, out float4 offset[3] : TEXCOORD2) {
    SMAABlendingWeightCalculationVS(texcoord, pixcoord, offset);
}

void smaa_blend_vs(inout float4 position : POSITION, inout float2 texcoord : TEXCOORD0,
                   out float4 offset : TEXCOORD1) {
    SMAANeighborhoodBlendingVS(texcoord, offset);
}

float4 smaa_edges_ps(float2 texcoord : TEXCOORD0, float4 offset[3] : TEXCOORD1) : COLOR {
    return float4(SMAAColorEdgeDetectionPS(texcoord, offset, color_gamma), 0.0, 0.0);
}

float4 smaa_weights_ps(float2 texcoord : TEXCOORD0, float2 pixcoord : TEXCOORD1,
                       float4 offset[3] : TEXCOORD2) : COLOR {
    return SMAABlendingWeightCalculationPS(texcoord, pixcoord, offset, edges_tex, area_tex, search_tex, 0.0);
}

float4 smaa_blend_ps(float2 texcoord : TEXCOORD0, float4 offset : TEXCOORD1) : COLOR {
    return SMAANeighborhoodBlendingPS(texcoord, offset, color_linear, blend_tex);
}

// a b c
// d e f
// g h i
float4 cas_ps(float2 texcoord : TEXCOORD0) : COLOR {
    float2 px = rt_metrics.xy;
    float3 a = tex2D(color_linear, texcoord + float2(-px.x, -px.y)).rgb;
    float3 b = tex2D(color_linear, texcoord + float2(0.0, -px.y)).rgb;
    float3 c = tex2D(color_linear, texcoord + float2(px.x, -px.y)).rgb;
    float3 d = tex2D(color_linear, texcoord + float2(-px.x, 0.0)).rgb;
    float3 e = tex2D(color_linear, texcoord).rgb;
    float3 f = tex2D(color_linear, texcoord + float2(px.x, 0.0)).rgb;
    float3 g = tex2D(color_linear, texcoord + float2(-px.x, px.y)).rgb;
    float3 h = tex2D(color_linear, texcoord + float2(0.0, px.y)).rgb;
    float3 i = tex2D(color_linear, texcoord + float2(px.x, px.y)).rgb;

    // Soft min and max: the cross plus the whole 3x3, so values range over 0..2.
    float3 mn = min(min(min(d, e), min(f, b)), h);
    mn += min(mn, min(min(a, c), min(g, i)));
    float3 mx = max(max(max(d, e), max(f, b)), h);
    mx += max(mx, max(max(a, c), max(g, i)));

    // Sharpen less where the neighbourhood is already near black or white.
    float3 amp = sqrt(saturate(min(mn, 2.0 - mx) / max(mx, 1.0e-5)));
    float3 w = amp * cas_params.x;
    return float4(saturate((b * w + d * w + f * w + h * w + e) / (1.0 + 4.0 * w)), 1.0);
}
