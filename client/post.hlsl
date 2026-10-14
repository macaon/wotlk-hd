// Post-processing for effects.cpp (D3D9, shader model 3), compiled by shaders.sh into shaders.h.
// SMAA: Jimenez et al., MIT (cache/smaa, iryoku/smaa), driven as in its own D3D9 demo.
// CAS: AMD FidelityFX Contrast Adaptive Sharpening, MIT, the sharpen-only filter.
//
// Samplers (effects.cpp sets their states): s0 colour, gamma space; s1 colour, sRGB read (linear);
// s2 SMAA edges; s3 SMAA blend weights; s4 SMAA area texture; s5 SMAA search texture;
// s6 scene depth (INTZ: the device's depth buffer as a texture, 0 near .. 1 far); s7 ambient occlusion.
// c0: render target metrics (1/w, 1/h, w, h); c1.x: CAS peak, -1 / lerp(8, 5, sharpness);
// c2: near and far clip (yards), and the depth the world is drawn up to.
// c3: tan of half the field of view (x, y), AO radius (yards), AO intensity; c4: AO target metrics
// (half the screen); c5.xy: AO blur step (texcoords).

float4 rt_metrics : register(c0);
float4 cas_params : register(c1);
float4 clip_planes : register(c2);
float4 ao_params : register(c3);
float4 ao_metrics : register(c4);
float4 blur_step : register(c5);

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
sampler2D depth_tex : register(s6);
sampler2D ao_tex : register(s7);

// Distance from the camera plane in yards: D3D's depth d = f/(f-n) - f*n/((f-n)*z), inverted. The
// client draws the world into the viewport depth range 0..0.94 (c2.z) and sky and horizon layers into
// 0.998..1, so depth over c2.z is sky: the far clip.
// Depth pixel centre for a texcoord: half-resolution passes land exactly between two depth pixels,
// where point sampling (or rounding) picks either by the coordinates' rounding noise: stripes on
// ground seen at an angle. A quarter pixel off the border makes it the left or upper one, always.
float2 depth_texel(float2 texcoord) {
    return (floor(texcoord * rt_metrics.zw - 0.25) + 0.5) * rt_metrics.xy;
}

float linear_depth(float2 texcoord) {
    float d = min(tex2Dlod(depth_tex, float4(depth_texel(texcoord), 0.0, 0.0)).r / clip_planes.z, 1.0);
    float n = clip_planes.x, f = clip_planes.y;
    return n * f / (f - d * (f - n));
}

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

// Debug view (WOTLKHD_EFFECTS=depth): log distance, near black, the far clip (and the sky) white.
float4 depth_ps(float2 texcoord : TEXCOORD0) : COLOR {
    float v = saturate(log2(linear_depth(texcoord) / clip_planes.x) / log2(clip_planes.y / clip_planes.x));
    return float4(v, v, v, 1.0);
}


// Ambient occlusion: how much nearby geometry hides each point from the sky, from depth alone.
// View-space position of a screen point (x right, y up, z into the screen, yards).
float3 view_pos(float2 texcoord) {
    texcoord = depth_texel(texcoord);  // the position of the depth pixel actually read
    float z = linear_depth(texcoord);
    return float3((texcoord.x * 2.0 - 1.0) * ao_params.x * z, (1.0 - texcoord.y * 2.0) * ao_params.y * z, z);
}

// 12 samples on a spiral within ao_params.z yards, turned per pixel; each counts by how far it
// rises above the surface (over its distance: the cosine to the normal, less a minimum height) and
// fades out linearly towards the radius.
float4 ao_ps(float2 texcoord : TEXCOORD0, float2 vpos : VPOS) : COLOR {
    float3 p = view_pos(texcoord);
    if (p.z >= clip_planes.y * 0.999)
        return 1.0;  // sky
    // Normal from the nearer neighbour on each side, so silhouettes get no halo.
    float3 l = view_pos(texcoord - float2(rt_metrics.x, 0.0)), r = view_pos(texcoord + float2(rt_metrics.x, 0.0));
    float3 u = view_pos(texcoord - float2(0.0, rt_metrics.y)), d = view_pos(texcoord + float2(0.0, rt_metrics.y));
    float3 dx = abs(r.z - p.z) < abs(p.z - l.z) ? r - p : p - l;
    float3 dy = abs(d.z - p.z) < abs(p.z - u.z) ? d - p : p - u;
    float3 n = normalize(cross(dx, dy));
    n = n.z > 0.0 ? -n : n;  // towards the camera
    float radius = ao_params.z;
    float2 scale = min(0.5 * radius / (p.z * ao_params.xy), 0.1);  // radius in texcoords, capped up close
    float angle = 6.2831853 * frac(52.9829189 * frac(dot(vpos, float2(0.06711056, 0.00583715))));
    float sum = 0.0;
    [unroll] for (int i = 0; i < 12; i++) {
        float a = angle + i * 2.3999632;  // golden angle
        float2 q = texcoord + float2(cos(a), sin(a)) * ((i + 0.5) / 12.0) * scale;
        float3 v = view_pos(q) - p;
        float vv = dot(v, v);
        float fall = saturate(1.0 - vv / (radius * radius));
        // height above the surface's plane, less a minimum: steps of a few centimetres (floor slabs,
        // wall panels) occlude nothing
        sum += fall * max(dot(v, n) - 0.05 - 0.002 * p.z, 0.0) * rsqrt(vv + 1.0e-4);
    }
    float ao = saturate(1.0 - ao_params.w * sum / 12.0);
    return lerp(ao, 1.0, saturate((p.z - 150.0) / 150.0)).xxxx;  // none in the distance
}

// Depth-aware blur, run across then down: neighbours off the surface (an edge) count less. Off the
// surface means away from the depth the surface's slope along the blur predicts, so floors and walls
// seen at an angle still blur along the direction their depth changes in (no streaks).
float4 ao_blur_ps(float2 texcoord : TEXCOORD0) : COLOR {
    float z0 = linear_depth(texcoord), sum = 0.0, weights = 0.0;
    float zl = linear_depth(texcoord - blur_step.xy), zr = linear_depth(texcoord + blur_step.xy);
    float slope = abs(zr - z0) < abs(z0 - zl) ? zr - z0 : z0 - zl;  // the nearer side: not across an edge
    [unroll] for (int i = -4; i <= 4; i++) {
        float2 q = texcoord + blur_step.xy * i;
        float w = exp(-i * i / 8.0) * saturate(1.0 - abs(linear_depth(q) - (z0 + slope * i)) / (0.02 * z0 + 0.05));
        sum += tex2Dlod(ao_tex, float4(q, 0.0, 0.0)).r * w;
        weights += w;
    }
    return (sum / max(weights, 1.0e-4)).xxxx;
}

// The scene darkened by the AO, in linear light (s1 and the target are sRGB).
float4 ao_apply_ps(float2 texcoord : TEXCOORD0) : COLOR {
    return float4(tex2D(color_linear, texcoord).rgb * tex2D(ao_tex, texcoord).r, 1.0);
}

// Debug view (WOTLKHD_EFFECTS=aoview): the AO term alone.
float4 ao_view_ps(float2 texcoord : TEXCOORD0) : COLOR {
    return float4(tex2D(ao_tex, texcoord).rrr, 1.0);
}
