/* Post-processing under the UI: SMAA, then CAS sharpening (post.hlsl, compiled into shaders.h).
 * The world frame (WorldFrame.cpp) ends with the client's own full-frame effects (glow, death,
 * nether: 0x8c1010, called at 0x4f9281); the UI draws after it. We hook that call, let it run,
 * then run our passes on the back buffer, so they never touch the UI. D3D9 only: the client's
 * device is the gx device's (0xc5df88) IDirect3DDevice9 at +0x397c, used only once its vtable is
 * found in d3d9.dll (not under -opengl). Our render targets live in D3DPOOL_DEFAULT, which D3D9
 * wants released before IDirect3DDevice9::Reset: we hook Reset in the device's vtable for that.
 * Settings: cvars (saved in Config.wtf; the WotlkHD addon's Video Options page sets them), registered
 * after the client's world graphics cvars (0x78e400, called at 0x4041c2) and read every frame:
 * hdSMAA, hdSharpen, hdSharpness (0-100), hdSunshafts, hdSunshaftsStrength (0-100), hdAO, hdHaze.
 * For debugging WOTLKHD_EFFECTS overrides them: "smaa,cas,shafts", any of those, or "off"; "ao" adds
 * ambient occlusion (before SMAA and CAS), "aoview" and "depth" debug views of it and the depth;
 * WOTLKHD_AO=radius,intensity tunes the AO (default 1.5 yards, 2). "haze" adds distance haze in the
 * fog colour (WOTLKHD_HAZE=strength,density, default 0.5, 1.5); "shafts" sunshafts (WOTLKHD_SHAFTS=
 * intensity,threshold, default 0.6, 0.4), "shaftsview" their debug view.
 *
 * Depth: D3D9 cannot sample the device's own depth buffer (D24S8), so for depth effects the world is
 * drawn into an INTZ depth texture instead: we create one the size of the back buffer and, through
 * SetDepthStencilSurface and GetDepthStencilSurface in the vtable, it stands in for the device's
 * depth buffer wherever the client binds that one (render to texture with depth targets of its own,
 * the portraits, is left alone), while the client keeps seeing its own surface. */
#include <windows.h>
#include <d3d9.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cvar.h"
#include "shaders.h"
#include "../cache/smaa/Textures/AreaTex.h"
#include "../cache/smaa/Textures/SearchTex.h"

extern "C" void wlog(const char *fmt, ...);
extern "C" void controls_cvars(void); /* controls.c */

#define FFX_APPLY ((void(__cdecl *)(void))0x008C1010)
#define GX_DEVICE (*(BYTE **)0x00C5DF88)
#define GX_D3D_DEVICE 0x397C
#define CAS_SHARPNESS 1.0f /* 0..1; AMD's full strength, still mild at 1440p */
#define NEAR_CLIP (*(float *)0x00ADEED4) /* CWorld near and far clip (AdjustFarClip's result), yards */
#define FAR_CLIP (*(float *)0x00CD7748)
#define FOV (*(float *)0x009E8D88)     /* the world camera's (patch_exe.py widens it) */
static float ao_radius = 1.5f, ao_intensity = 2.0f; /* yards; WOTLKHD_AO=radius,intensity */
static float haze_strength = 0.5f, haze_density = 1.5f; /* per fog end distance; WOTLKHD_HAZE */
/* CShaderEffect's fog, as SetFogParams (0x873210) last set it for the shaders: the colour (0..1, gamma)
 * and s_fogParams.xy = -fogMul / (end - start), end / (end - start) */
#define FOG_COLOR ((const float *)0x00D43058)
#define FOG_PARAMS ((const float *)0x00D43068)
#define FOG_MUL (*(const float *)0x00D4300C)
/* the sky's sun (0x7eecc0: the camera position at 0xd38b18 plus the sun's direction at a fixed radius)
 * and the world camera (the world frame's 0xb7436c +0x7e20: position +0x08, orientation +0x14,
 * forward, left, up rows) */
#define SUN_POS ((const float *)0x00D38E28)
#define SKY_CAMERA ((const float *)0x00D38B18)
#define WORLD_FRAME (*(BYTE **)0x00B7436C)
#define WORLD_CAMERA 0x7E20
static float shaft_intensity = 0.6f, shaft_threshold = 0.4f; /* WOTLKHD_SHAFTS */
#define WORLD_MAX_Z 0.94f /* the client's viewport MaxZ for the world (sky and horizon: 0.998..1) */
#define D3DFMT_INTZ ((D3DFORMAT)MAKEFOURCC('I', 'N', 'T', 'Z'))

static bool use_smaa = true, use_cas = true, use_ao, use_ao_view, use_depth_view, use_haze, use_shafts = true,
    use_shafts_view, broken, from_env;
static float cas_sharpness = CAS_SHARPNESS;

static BYTE *cv_smaa, *cv_sharpen, *cv_sharpness, *cv_shafts, *cv_shafts_strength, *cv_ao, *cv_haze, *cv_colorblind,
    *cv_colorblind_strength;

static void __cdecl register_cvars(void) {
    ((void(__cdecl *)(void))0x0078E400)(); /* the client's own world graphics cvars */
    controls_cvars();
    cv_smaa = CVAR_REGISTER("hdSMAA", "wotlk-hd: SMAA anti-aliasing", 1, "1", nullptr, 1, 0, nullptr, 0);
    cv_sharpen = CVAR_REGISTER("hdSharpen", "wotlk-hd: CAS sharpening", 1, "1", nullptr, 1, 0, nullptr, 0);
    cv_sharpness = CVAR_REGISTER("hdSharpness", "wotlk-hd: sharpening strength (0-100)", 1, "100", nullptr, 1, 0,
                                 nullptr, 0);
    cv_shafts = CVAR_REGISTER("hdSunshafts", "wotlk-hd: sunshafts", 1, "1", nullptr, 1, 0, nullptr, 0);
    cv_shafts_strength = CVAR_REGISTER("hdSunshaftsStrength", "wotlk-hd: sunshaft strength (0-100)", 1, "60",
                                       nullptr, 1, 0, nullptr, 0);
    cv_ao = CVAR_REGISTER("hdAO", "wotlk-hd: ambient occlusion", 1, "0", nullptr, 1, 0, nullptr, 0);
    cv_haze = CVAR_REGISTER("hdHaze", "wotlk-hd: distance haze", 1, "0", nullptr, 1, 0, nullptr, 0);
    cv_colorblind = CVAR_SAVED("hdColorblind", "wotlk-hd: colorblind filter (0 off, 1 protanopia, 2 deuteranopia, 3 tritanopia)", "0");
    cv_colorblind_strength = CVAR_SAVED("hdColorblindStrength", "wotlk-hd: colorblind filter strength (0-100)", "100");
    wlog("effects: settings registered (hdSMAA %d, hdSharpen %d, hdSharpness %d, hdSunshafts %d, hdAO %d, hdHaze %d)",
         cv_smaa ? CVAR_INT(cv_smaa) : -1, cv_sharpen ? CVAR_INT(cv_sharpen) : -1,
         cv_sharpness ? CVAR_INT(cv_sharpness) : -1, cv_shafts ? CVAR_INT(cv_shafts) : -1, cv_ao ? CVAR_INT(cv_ao) : -1,
         cv_haze ? CVAR_INT(cv_haze) : -1);
}

static void read_settings(void) {
    if (from_env || !cv_smaa || !cv_sharpen || !cv_sharpness || !cv_shafts || !cv_shafts_strength || !cv_ao || !cv_haze)
        return;
    use_smaa = CVAR_INT(cv_smaa) != 0;
    use_cas = CVAR_INT(cv_sharpen) != 0;
    cas_sharpness = fminf(fmaxf(CVAR_INT(cv_sharpness) / 100.0f, 0.0f), 1.0f);
    use_shafts = CVAR_INT(cv_shafts) != 0;
    shaft_intensity = fmaxf(CVAR_INT(cv_shafts_strength) / 100.0f, 0.0f);
    use_ao = CVAR_INT(cv_ao) != 0;
    use_haze = CVAR_INT(cv_haze) != 0;
}
static unsigned frames;
static float haze_color[3] = {-1.0f, 0.0f, 0.0f}; /* linear, eased; < 0: none seen yet */
#define USE_DEPTH (use_ao || use_ao_view || use_depth_view || use_haze || use_shafts || use_shafts_view)
static IDirect3DDevice9 *dev;
static IDirect3DVertexShader9 *vs_quad, *vs_edges, *vs_weights, *vs_blend;
static IDirect3DPixelShader9 *ps_edges, *ps_weights, *ps_blend, *ps_cas, *ps_depth, *ps_ao, *ps_ao_blur, *ps_ao_apply, *ps_ao_view, *ps_haze, *ps_shafts_mask, *ps_shafts_blur,
    *ps_shafts_apply, *ps_shafts_view, *ps_colorblind;
static IDirect3DTexture9 *area, *search;               /* D3DPOOL_MANAGED: survive Reset */
static IDirect3DTexture9 *color, *edges, *weights, *temp; /* D3DPOOL_DEFAULT, back buffer size */
static IDirect3DTexture9 *ao, *ao_temp;   /* D3DPOOL_DEFAULT, half the back buffer */
static IDirect3DTexture9 *shafts, *shafts_temp; /* D3DPOOL_DEFAULT, half the back buffer, 16-bit float */
static IDirect3DStateBlock9 *state;
static IDirect3DTexture9 *depth;                  /* INTZ, D3DPOOL_DEFAULT */
static IDirect3DSurface9 *depth_surface, *device_depth; /* ours, and the device's that it replaces */
static UINT width, height;

template <class T> static void release(T *&p) {
    if (p)
        p->Release();
    p = nullptr;
}

typedef HRESULT(STDMETHODCALLTYPE *set_depth_t)(IDirect3DDevice9 *, IDirect3DSurface9 *);
typedef HRESULT(STDMETHODCALLTYPE *get_depth_t)(IDirect3DDevice9 *, IDirect3DSurface9 **);
static set_depth_t real_set_depth;
static get_depth_t real_get_depth;

static HRESULT STDMETHODCALLTYPE set_depth_hook(IDirect3DDevice9 *self, IDirect3DSurface9 *s) {
    if (self == dev && s && s == device_depth && depth_surface)
        s = depth_surface;
    return real_set_depth(self, s);
}

static HRESULT STDMETHODCALLTYPE get_depth_hook(IDirect3DDevice9 *self, IDirect3DSurface9 **out) {
    HRESULT hr = real_get_depth(self, out);
    if (SUCCEEDED(hr) && self == dev && *out && *out == depth_surface && device_depth) {
        (*out)->Release();
        device_depth->AddRef();
        *out = device_depth;
    }
    return hr;
}

static void release_depth(void) {
    if (depth_surface && device_depth)
        real_set_depth(dev, device_depth); /* never leave ours bound */
    release(depth_surface);
    release(depth);
    release(device_depth);
}

static void release_targets(void) {
    release_depth();
    release(color);
    release(edges);
    release(weights);
    release(temp);
    release(ao);
    release(ao_temp);
    release(shafts);
    release(shafts_temp);
    release(state);
    width = height = 0;
}

typedef HRESULT(STDMETHODCALLTYPE *reset_t)(IDirect3DDevice9 *, D3DPRESENT_PARAMETERS *);
static reset_t real_reset;

typedef HRESULT(STDMETHODCALLTYPE *present_t)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
static present_t real_present;
static void colorblind(void);

static HRESULT STDMETHODCALLTYPE present_hook(IDirect3DDevice9 *self, const RECT *src, const RECT *dst, HWND w,
                                              const RGNDATA *dirty) {
    if (self == dev && !broken)
        colorblind();
    return real_present(self, src, dst, w, dirty);
}

static HRESULT STDMETHODCALLTYPE reset_hook(IDirect3DDevice9 *self, D3DPRESENT_PARAMETERS *pp) {
    if (self == dev)
        release_targets();
    return real_reset(self, pp);
}

/* A lookup texture from SMAA's tables, row by row (the D3D9 pitch may be larger). */
static IDirect3DTexture9 *lookup_texture(UINT w, UINT h, D3DFORMAT f, const unsigned char *bytes, UINT pitch) {
    IDirect3DTexture9 *t = nullptr;
    D3DLOCKED_RECT r;
    if (FAILED(dev->CreateTexture(w, h, 1, 0, f, D3DPOOL_MANAGED, &t, nullptr)))
        return nullptr;
    if (FAILED(t->LockRect(0, &r, nullptr, 0))) {
        t->Release();
        return nullptr;
    }
    for (UINT y = 0; y < h; y++)
        memcpy((BYTE *)r.pBits + y * r.Pitch, bytes + y * pitch, pitch);
    t->UnlockRect(0);
    return t;
}

/* Once, on the first world frame: the device, the Reset hook, shaders and lookup textures. */
static bool setup(void) {
    BYTE *gx = GX_DEVICE;
    IDirect3DDevice9 *d = gx ? *(IDirect3DDevice9 **)(gx + GX_D3D_DEVICE) : nullptr;
    HMODULE owner = nullptr;
    char name[MAX_PATH] = "";
    if (d)
        GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           *(LPCSTR *)d, &owner);
    if (owner)
        GetModuleFileNameA(owner, name, MAX_PATH);
    const char *base = strrchr(name, '\\');
    if (!base || _stricmp(base + 1, "d3d9.dll") != 0) {
        wlog("effects: no D3D9 device (OpenGL?), effects off");
        return false;
    }
    dev = d;

    void **vtbl = *(void ***)dev;
    DWORD old;
    if (!VirtualProtect(&vtbl[16], sizeof(void *), PAGE_READWRITE, &old)) {
        wlog("effects: cannot hook IDirect3DDevice9::Reset (%lu), effects off", GetLastError());
        return false;
    }
    real_reset = (reset_t)vtbl[16];
    vtbl[16] = (void *)reset_hook;
    VirtualProtect(&vtbl[16], sizeof(void *), old, &old);
    if (VirtualProtect(&vtbl[17], sizeof(void *), PAGE_READWRITE, &old)) {
        real_present = (present_t)vtbl[17];
        vtbl[17] = (void *)present_hook;
        VirtualProtect(&vtbl[17], sizeof(void *), old, &old);
        wlog("effects: Present hooked (color filter)");
    } else
        wlog("effects: cannot hook IDirect3DDevice9::Present (%lu), no color filter", GetLastError());
    if (VirtualProtect(&vtbl[39], 2 * sizeof(void *), PAGE_READWRITE, &old)) {
        real_set_depth = (set_depth_t)vtbl[39];
        real_get_depth = (get_depth_t)vtbl[40];
        vtbl[39] = (void *)set_depth_hook;
        vtbl[40] = (void *)get_depth_hook;
        VirtualProtect(&vtbl[39], 2 * sizeof(void *), old, &old);
    }

    bool ok = SUCCEEDED(dev->CreateVertexShader(quad_vs, &vs_quad)) &&
              SUCCEEDED(dev->CreateVertexShader(smaa_edges_vs, &vs_edges)) &&
              SUCCEEDED(dev->CreateVertexShader(smaa_weights_vs, &vs_weights)) &&
              SUCCEEDED(dev->CreateVertexShader(smaa_blend_vs, &vs_blend)) &&
              SUCCEEDED(dev->CreatePixelShader(smaa_edges_ps, &ps_edges)) &&
              SUCCEEDED(dev->CreatePixelShader(smaa_weights_ps, &ps_weights)) &&
              SUCCEEDED(dev->CreatePixelShader(smaa_blend_ps, &ps_blend)) &&
              SUCCEEDED(dev->CreatePixelShader(cas_ps, &ps_cas)) &&
              SUCCEEDED(dev->CreatePixelShader(depth_ps, &ps_depth)) &&
              SUCCEEDED(dev->CreatePixelShader(ao_ps, &ps_ao)) &&
              SUCCEEDED(dev->CreatePixelShader(ao_blur_ps, &ps_ao_blur)) &&
              SUCCEEDED(dev->CreatePixelShader(ao_apply_ps, &ps_ao_apply)) &&
              SUCCEEDED(dev->CreatePixelShader(ao_view_ps, &ps_ao_view)) &&
              SUCCEEDED(dev->CreatePixelShader(haze_ps, &ps_haze)) &&
              SUCCEEDED(dev->CreatePixelShader(shafts_mask_ps, &ps_shafts_mask)) &&
              SUCCEEDED(dev->CreatePixelShader(shafts_blur_ps, &ps_shafts_blur)) &&
              SUCCEEDED(dev->CreatePixelShader(shafts_apply_ps, &ps_shafts_apply)) &&
              SUCCEEDED(dev->CreatePixelShader(shafts_view_ps, &ps_shafts_view)) &&
              SUCCEEDED(dev->CreatePixelShader(colorblind_ps, &ps_colorblind));
    area = lookup_texture(AREATEX_WIDTH, AREATEX_HEIGHT, D3DFMT_A8L8, areaTexBytes, AREATEX_PITCH);
    search = lookup_texture(SEARCHTEX_WIDTH, SEARCHTEX_HEIGHT, D3DFMT_L8, searchTexBytes, SEARCHTEX_PITCH);
    if (!ok || !area || !search) {
        wlog("effects: shaders or SMAA textures failed, effects off");
        return false;
    }
    wlog("effects: D3D9 device %p, %s%s%s%s%s%s%s%s before the UI", (void *)dev, use_ao ? "AO, " : "",
         use_haze ? "haze, " : "", use_shafts ? "shafts, " : "",
         use_smaa ? "SMAA" : "", use_smaa && use_cas ? " and " : "", use_cas ? "CAS" : "",
         use_ao_view ? ", AO view" : "", use_depth_view ? ", depth view" : "");
    return true;
}

static IDirect3DTexture9 *target_texture(UINT w = width, UINT h = height, D3DFORMAT f = D3DFMT_A8R8G8B8) {
    IDirect3DTexture9 *t = nullptr;
    dev->CreateTexture(w, h, 1, D3DUSAGE_RENDERTARGET, f, D3DPOOL_DEFAULT, &t, nullptr);
    return t;
}

static bool make_targets(UINT w, UINT h) {
    release_targets();
    width = w, height = h;
    color = target_texture();
    edges = target_texture();
    weights = target_texture();
    temp = target_texture();
    /* always: the depth effects can be turned on at any time */
    ao = target_texture(w / 2, h / 2);
    ao_temp = target_texture(w / 2, h / 2);
    shafts = target_texture(w / 2, h / 2, D3DFMT_A16B16G16R16F);
    shafts_temp = target_texture(w / 2, h / 2, D3DFMT_A16B16G16R16F);
    if (FAILED(dev->CreateStateBlock(D3DSBT_ALL, &state)))
        state = nullptr;
    if (!color || !state || !edges || !weights || !temp || !ao || !ao_temp || !shafts || !shafts_temp) {
        wlog("effects: no %ux%u render targets, effects off", w, h);
        release_targets();
        return false;
    }
    return true;
}

/* The INTZ texture in place of the device's depth buffer, which is bound now (the world frame has
 * just used it). It takes over from the next frame; false when the device's cannot be replaced. */
static bool make_depth(void) {
    D3DSURFACE_DESC d;
    if (FAILED(real_get_depth(dev, &device_depth)) || !device_depth)
        return false;
    device_depth->GetDesc(&d);
    if (d.MultiSampleType != D3DMULTISAMPLE_NONE || d.Width != width || d.Height != height) {
        wlog("effects: depth buffer %ux%u, multisample %u: no depth effects (turn multisampling off)",
             d.Width, d.Height, (unsigned)d.MultiSampleType);
        release(device_depth);
        return false;
    }
    if (FAILED(dev->CreateTexture(width, height, 1, D3DUSAGE_DEPTHSTENCIL, D3DFMT_INTZ, D3DPOOL_DEFAULT, &depth,
                                  nullptr)) ||
        FAILED(depth->GetSurfaceLevel(0, &depth_surface))) {
        wlog("effects: no INTZ depth texture, no depth effects");
        release_depth();
        return false;
    }
    wlog("effects: %ux%u INTZ depth texture in place of the device's depth buffer", width, height);
    return true;
}

static void sampler(DWORD s, IDirect3DTexture9 *t, bool linear_filter, bool srgb) {
    D3DTEXTUREFILTERTYPE f = linear_filter ? D3DTEXF_LINEAR : D3DTEXF_POINT;
    dev->SetTexture(s, t);
    dev->SetSamplerState(s, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
    dev->SetSamplerState(s, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
    dev->SetSamplerState(s, D3DSAMP_MINFILTER, f);
    dev->SetSamplerState(s, D3DSAMP_MAGFILTER, f);
    dev->SetSamplerState(s, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
    dev->SetSamplerState(s, D3DSAMP_SRGBTEXTURE, srgb);
}

static void target(IDirect3DTexture9 *t, IDirect3DSurface9 *back) {
    IDirect3DSurface9 *s = back;
    if (t)
        t->GetSurfaceLevel(0, &s);
    dev->SetRenderTarget(0, s);
    if (t)
        s->Release();
}

/* Full-screen quad, shifted half a pixel (of a w x h target) for D3D9's pixel centres (as in SMAA's
 * D3D9 demo). */
static HRESULT draw(IDirect3DVertexShader9 *vs, IDirect3DPixelShader9 *ps, UINT w = width, UINT h = height) {
    float px = 1.0f / w, py = 1.0f / h;
    float quad[4][5] = {{-1.0f - px, 1.0f + py, 0.5f, 0.0f, 0.0f},
                        {1.0f - px, 1.0f + py, 0.5f, 1.0f, 0.0f},
                        {-1.0f - px, -1.0f + py, 0.5f, 0.0f, 1.0f},
                        {1.0f - px, -1.0f + py, 0.5f, 1.0f, 1.0f}};
    dev->SetVertexShader(vs);
    dev->SetPixelShader(ps);
    return dev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, quad, sizeof(quad[0]));
}

/* The sun on screen: texcoords, and how visible (0 behind the camera, below the horizon or far off
 * screen). False without a world camera. */
static bool sun_on_screen(float *u, float *v, float *visibility) {
    BYTE *frame = WORLD_FRAME, *cam = frame ? *(BYTE **)(frame + WORLD_CAMERA) : nullptr;
    if (!cam)
        return false;
    const float *pos = (const float *)(cam + 0x08), *m = (const float *)(cam + 0x14);
    const float *fwd = m, *up = m + 6;
    float right[3] = {fwd[1] * up[2] - fwd[2] * up[1], fwd[2] * up[0] - fwd[0] * up[2], fwd[0] * up[1] - fwd[1] * up[0]};
    float rel[3] = {SUN_POS[0] - pos[0], SUN_POS[1] - pos[1], SUN_POS[2] - pos[2]};
    float dist = sqrtf(rel[0] * rel[0] + rel[1] * rel[1] + rel[2] * rel[2]);
    float z = rel[0] * fwd[0] + rel[1] * fwd[1] + rel[2] * fwd[2];
    if (frames % 600 == 2)
        wlog("effects: camera %.1f %.1f %.1f (sky's %.1f %.1f %.1f), sun %.1f %.1f %.1f, forward %.2f %.2f %.2f",
             pos[0], pos[1], pos[2], SKY_CAMERA[0], SKY_CAMERA[1], SKY_CAMERA[2], SUN_POS[0], SUN_POS[1],
             SUN_POS[2], fwd[0], fwd[1], fwd[2]);
    if (dist <= 0.0f || z <= 0.0f) {
        *visibility = 0.0f;
        return true;
    }
    float aspect = (float)width / height, tan_y = tanf(0.5f * FOV / sqrtf(aspect * aspect + 1.0f));
    float x = (rel[0] * right[0] + rel[1] * right[1] + rel[2] * right[2]) / (z * tan_y * aspect);
    float y = (rel[0] * up[0] + rel[1] * up[1] + rel[2] * up[2]) / (z * tan_y);
    *u = 0.5f + 0.5f * x;
    *v = 0.5f - 0.5f * y;
    float off = fmaxf(fabsf(x), fabsf(y)); /* 1 at the screen's edge */
    float elevation = rel[2] / dist;
    *visibility = fminf(fmaxf(2.0f - off, 0.0f), 1.0f) * fminf(fmaxf(elevation * 5.0f, 0.0f), 1.0f);
    if (frames % 600 == 2)
        wlog("effects: sun at %.3f %.3f, visibility %.2f", *u, *v, *visibility);
    return true;
}

static void render(void) {
    IDirect3DSurface9 *back = nullptr, *saved_target = nullptr, *saved_depth = nullptr, *color_surface = nullptr;
    D3DSURFACE_DESC desc;
    if (FAILED(dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &back)))
        return;
    back->GetDesc(&desc);
    if ((desc.Width != width || desc.Height != height) && !make_targets(desc.Width, desc.Height)) {
        back->Release();
        broken = true;
        return;
    }

    bool depth_ready = depth != nullptr; /* drawn into this frame */
    if (USE_DEPTH && !depth && !make_depth()) {
        use_ao = use_ao_view = use_depth_view = use_haze = use_shafts = use_shafts_view = false;
        from_env = true; /* no depth: the settings cannot turn the depth effects on */
    }

    /* A D3DSBT_ALL state block keeps everything but the render target and depth surface. */
    state->Capture();
    dev->GetRenderTarget(0, &saved_target);
    dev->GetDepthStencilSurface(&saved_depth);

    dev->SetDepthStencilSurface(nullptr);
    dev->SetRenderState(D3DRS_ZENABLE, FALSE);
    dev->SetRenderState(D3DRS_STENCILENABLE, FALSE);
    dev->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
    dev->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
    dev->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
    dev->SetRenderState(D3DRS_FILLMODE, D3DFILL_SOLID);
    dev->SetRenderState(D3DRS_COLORWRITEENABLE, 0xF);
    dev->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);
    dev->SetRenderState(D3DRS_FOGENABLE, FALSE);
    dev->SetRenderState(D3DRS_CLIPPLANEENABLE, 0);
    dev->SetFVF(D3DFVF_XYZ | D3DFVF_TEX1);
    float metrics[4] = {1.0f / width, 1.0f / height, (float)width, (float)height};
    float cas[4] = {-1.0f / (8.0f + (5.0f - 8.0f) * cas_sharpness), 0.0f, 0.0f, 0.0f};
    dev->SetVertexShaderConstantF(0, metrics, 1);
    dev->SetPixelShaderConstantF(0, metrics, 1);
    dev->SetPixelShaderConstantF(1, cas, 1);

    color->GetSurfaceLevel(0, &color_surface);
    dev->StretchRect(back, nullptr, color_surface, nullptr, D3DTEXF_NONE);

    if ((use_ao || use_ao_view) && depth_ready) {
        /* the world camera's projection (GxuXformCreateProjection_SG): vertical fov = fov / sqrt(a^2 + 1) */
        float aspect = (float)width / height, tan_y = tanf(0.5f * FOV / sqrtf(aspect * aspect + 1.0f));
        float planes[4] = {NEAR_CLIP, FAR_CLIP, WORLD_MAX_Z, 0.0f};
        float params[4] = {tan_y * aspect, tan_y, ao_radius, ao_intensity};
        UINT w2 = width / 2, h2 = height / 2;
        float half_metrics[4] = {1.0f / w2, 1.0f / h2, (float)w2, (float)h2};
        float across[4] = {1.0f / w2, 0.0f, 0.0f, 0.0f}, down[4] = {0.0f, 1.0f / h2, 0.0f, 0.0f};
        dev->SetPixelShaderConstantF(2, planes, 1);
        dev->SetPixelShaderConstantF(3, params, 1);
        dev->SetPixelShaderConstantF(4, half_metrics, 1);
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
        sampler(6, depth, false, false);
        target(ao, back);
        draw(vs_quad, ps_ao, w2, h2);
        target(ao_temp, back);
        sampler(7, ao, false, false);
        dev->SetPixelShaderConstantF(5, across, 1);
        draw(vs_quad, ps_ao_blur, w2, h2);
        target(ao, back);
        sampler(7, ao_temp, false, false);
        dev->SetPixelShaderConstantF(5, down, 1);
        draw(vs_quad, ps_ao_blur, w2, h2);
        if (use_ao) {  /* the darkened scene becomes the colour SMAA and CAS start from */
            dev->SetRenderState(D3DRS_SRGBWRITEENABLE, TRUE);
            target(nullptr, back);
            sampler(1, color, false, true);
            sampler(7, ao, true, false);
            draw(vs_quad, ps_ao_apply);
            dev->StretchRect(back, nullptr, color_surface, nullptr, D3DTEXF_NONE);
        }
    }
    if (use_haze && depth_ready) {
        float span = FOG_PARAMS[0] < 0.0f ? -FOG_MUL / FOG_PARAMS[0] : 0.0f, fog_end = FOG_PARAMS[1] * span;
        if (!(fog_end > 1.0f && fog_end < 100000.0f))
            fog_end = FAR_CLIP;
        float planes[4] = {NEAR_CLIP, FAR_CLIP, WORLD_MAX_Z, 0.0f};
        /* additive draws (glows, particles) set black fog: keep the last real colour, and ease changes
         * (zones, time of day) over about a second rather than jump */
        if (FOG_COLOR[0] + FOG_COLOR[1] + FOG_COLOR[2] > 0.02f)
            for (int i = 0; i < 3; i++) {
                float c = powf(FOG_COLOR[i], 2.2f);
                haze_color[i] = haze_color[0] < 0.0f ? c : haze_color[i] + (c - haze_color[i]) * 0.05f;
            }
        if (haze_color[0] < 0.0f)
            goto no_haze;
        float fog[4] = {haze_color[0], haze_color[1], haze_color[2], haze_strength};
        float params[4] = {haze_density / fog_end, 0.0f, 0.0f, 0.0f};
        if (++frames % 600 == 1)
            wlog("effects: fog start %.1f, end %.1f, colour %.2f %.2f %.2f (far clip %.1f)", fog_end - span, fog_end,
                 FOG_COLOR[0], FOG_COLOR[1], FOG_COLOR[2], FAR_CLIP);
        dev->SetPixelShaderConstantF(2, planes, 1);
        dev->SetPixelShaderConstantF(6, fog, 1);
        dev->SetPixelShaderConstantF(7, params, 1);
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, TRUE);
        target(nullptr, back);
        sampler(1, color, false, true);
        sampler(6, depth, false, false);
        draw(vs_quad, ps_haze);
        dev->StretchRect(back, nullptr, color_surface, nullptr, D3DTEXF_NONE);
    }
no_haze:
    float sun_u = 0.5f, sun_v = 0.5f, sun_visibility = 0.0f;
    frames += !use_haze; /* the haze counts frames otherwise */
    if ((use_shafts || use_shafts_view) && depth_ready && sun_on_screen(&sun_u, &sun_v, &sun_visibility) &&
        (sun_visibility > 0.0f || use_shafts_view)) {
        UINT w2 = width / 2, h2 = height / 2;
        float planes[4] = {NEAR_CLIP, FAR_CLIP, WORLD_MAX_Z, 0.0f};
        float sun[4] = {sun_u, sun_v, sun_visibility, shaft_intensity};
        float pass1[4] = {0.5f, shaft_threshold, 0.0f, 0.0f}, pass2[4] = {1.0f, shaft_threshold, 0.0f, 0.0f};
        dev->SetPixelShaderConstantF(2, planes, 1);
        dev->SetPixelShaderConstantF(8, sun, 1);
        dev->SetPixelShaderConstantF(9, pass1, 1);
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
        target(shafts, back);
        sampler(1, color, true, true);
        sampler(6, depth, false, false);
        draw(vs_quad, ps_shafts_mask, w2, h2);
        target(shafts_temp, back);
        sampler(8, shafts, true, false);
        draw(vs_quad, ps_shafts_blur, w2, h2);
        target(shafts, back);
        sampler(8, shafts_temp, true, false);
        dev->SetPixelShaderConstantF(9, pass2, 1);
        draw(vs_quad, ps_shafts_blur, w2, h2);
        if (use_shafts) {
            dev->SetRenderState(D3DRS_SRGBWRITEENABLE, TRUE);
            target(nullptr, back);
            sampler(1, color, false, true);
            sampler(8, shafts, true, false);
            draw(vs_quad, ps_shafts_apply);
            dev->StretchRect(back, nullptr, color_surface, nullptr, D3DTEXF_NONE);
        }
    }
    color_surface->Release();

    IDirect3DTexture9 *source = color;
    if (use_smaa) {
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
        target(edges, back);
        dev->Clear(0, nullptr, D3DCLEAR_TARGET, 0, 1.0f, 0);
        sampler(0, color, true, false);
        draw(vs_edges, ps_edges);

        target(weights, back);
        dev->Clear(0, nullptr, D3DCLEAR_TARGET, 0, 1.0f, 0);
        sampler(2, edges, true, false);
        sampler(4, area, true, false);
        sampler(5, search, false, false);
        draw(vs_weights, ps_weights);

        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, TRUE);
        target(use_cas ? temp : nullptr, back);
        sampler(1, color, true, true);
        sampler(3, weights, true, false);
        draw(vs_blend, ps_blend);
        source = temp;
    }
    if (use_cas) {
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, TRUE);
        target(nullptr, back);
        sampler(1, source, false, true);
        draw(vs_quad, ps_cas);
    }
    if (use_shafts_view && depth_ready) {
        float sun[4] = {sun_u, sun_v, sun_visibility, shaft_intensity};
        dev->SetPixelShaderConstantF(8, sun, 1);
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
        target(nullptr, back);
        sampler(8, shafts, true, false);
        draw(vs_quad, ps_shafts_view);
    }
    if (use_ao_view && depth_ready) {
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
        target(nullptr, back);
        sampler(7, ao, true, false);
        draw(vs_quad, ps_ao_view);
    }
    if (use_depth_view && depth_ready) {
        float planes[4] = {NEAR_CLIP, FAR_CLIP, WORLD_MAX_Z, 0.0f};
        dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
        dev->SetPixelShaderConstantF(2, planes, 1);
        target(nullptr, back);
        sampler(6, depth, false, false);
        draw(vs_quad, ps_depth);
    }

    state->Apply();
    dev->SetRenderTarget(0, saved_target);
    dev->SetDepthStencilSurface(saved_depth);
    if (saved_target)
        saved_target->Release();
    if (saved_depth)
        saved_depth->Release();
    back->Release();
}

/* The colorblind filter, on the finished frame (UI included) just before Present. Uses the world
 * pass's targets, so it starts with the first world frame (not on the glue screens). */
static void colorblind(void) {
    IDirect3DSurface9 *back = nullptr, *saved_target = nullptr, *color_surface = nullptr;
    D3DSURFACE_DESC desc;
    if (!cv_colorblind || CVAR_INT(cv_colorblind) < 1 || CVAR_INT(cv_colorblind) > 3 || !state || !color ||
        FAILED(dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &back)))
        return;
    back->GetDesc(&desc);
    if (desc.Width != width || desc.Height != height) {
        back->Release();
        return;
    }
    state->Capture();
    dev->GetRenderTarget(0, &saved_target);
    dev->SetRenderState(D3DRS_ZENABLE, FALSE);
    dev->SetRenderState(D3DRS_STENCILENABLE, FALSE);
    dev->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
    dev->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
    dev->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
    dev->SetRenderState(D3DRS_FILLMODE, D3DFILL_SOLID);
    dev->SetRenderState(D3DRS_COLORWRITEENABLE, 0xF);
    dev->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);
    dev->SetRenderState(D3DRS_FOGENABLE, FALSE);
    dev->SetRenderState(D3DRS_CLIPPLANEENABLE, 0);
    dev->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
    dev->SetFVF(D3DFVF_XYZ | D3DFVF_TEX1);
    float metrics[4] = {1.0f / width, 1.0f / height, (float)width, (float)height};
    float params[4] = {(float)CVAR_INT(cv_colorblind),
                       fminf(fmaxf(CVAR_INT(cv_colorblind_strength) / 100.0f, 0.0f), 1.0f), 0.0f, 0.0f};
    dev->SetVertexShaderConstantF(0, metrics, 1);
    dev->SetPixelShaderConstantF(10, params, 1);
    color->GetSurfaceLevel(0, &color_surface);
    HRESULT copied = dev->StretchRect(back, nullptr, color_surface, nullptr, D3DTEXF_NONE);
    color_surface->Release();
    target(nullptr, back);
    sampler(0, color, false, false);
    HRESULT began = dev->BeginScene();
    HRESULT drawn = draw(vs_quad, ps_colorblind);
    dev->EndScene();
    static bool reported;
    if (!reported && (FAILED(copied) || FAILED(began) || FAILED(drawn))) {
        wlog("effects: color filter pass failed: copy %08lx, begin %08lx, draw %08lx", (unsigned long)copied,
             (unsigned long)began, (unsigned long)drawn);
        reported = true;
    }
    state->Apply();
    dev->SetRenderTarget(0, saved_target);
    if (saved_target)
        saved_target->Release();
    back->Release();
}

static void __cdecl world_end(void) {
    FFX_APPLY();
    if (broken)
        return;
    read_settings();
    if (!dev && !setup()) {
        broken = true;
        return;
    }
    render();
}

extern "C" void effects_hooks(void) {
    const char *mode = getenv("WOTLKHD_EFFECTS");
    BYTE *reg = reinterpret_cast<BYTE *>(0x004041C2);
    if (reg[0] == 0xE8 && 0x004041C2u + 5 + *reinterpret_cast<int *>(reg + 1) == 0x0078E400u) {
        DWORD o;
        VirtualProtect(reg, 5, PAGE_EXECUTE_READWRITE, &o);
        *reinterpret_cast<int *>(reg + 1) = static_cast<int>(reinterpret_cast<BYTE *>(&register_cvars) - (reg + 5));
        VirtualProtect(reg, 5, o, &o);
    } else
        wlog("effects: call at 004041c2 not as expected, no settings (cvars)");
    from_env = mode != nullptr;
    if (mode) {
        use_smaa = strstr(mode, "smaa") != nullptr;
        use_cas = strstr(mode, "cas") != nullptr;
        use_depth_view = strstr(mode, "depth") != nullptr;
        use_ao_view = strstr(mode, "aoview") != nullptr;
        use_ao = strstr(mode, "ao") != nullptr && !use_ao_view;
        use_haze = strstr(mode, "haze") != nullptr;
        use_shafts_view = strstr(mode, "shaftsview") != nullptr;
        use_shafts = strstr(mode, "shafts") != nullptr && !use_shafts_view;
    }
    if (const char *tune = getenv("WOTLKHD_SHAFTS")) {
        float a, b;
        if (sscanf(tune, "%f,%f", &a, &b) == 2 && a >= 0.0f && b >= 0.0f && b < 1.0f)
            shaft_intensity = a, shaft_threshold = b;
        wlog("effects: shafts intensity %.2f, threshold %.2f", shaft_intensity, shaft_threshold);
    }
    if (const char *tune = getenv("WOTLKHD_HAZE")) {
        float a, b;
        if (sscanf(tune, "%f,%f", &a, &b) == 2 && a >= 0.0f && b > 0.0f)
            haze_strength = a, haze_density = b;
        wlog("effects: haze strength %.2f, density %.2f", haze_strength, haze_density);
    }
    if (const char *tune = getenv("WOTLKHD_AO")) {
        float r, i;
        if (sscanf(tune, "%f,%f", &r, &i) == 2 && r > 0.0f && i >= 0.0f)
            ao_radius = r, ao_intensity = i;
        wlog("effects: AO radius %.2f yd, intensity %.2f", ao_radius, ao_intensity);
    }
    if (from_env && !use_smaa && !use_cas && !USE_DEPTH) {
        wlog("effects: off (WOTLKHD_EFFECTS=%s)", mode);
        return;
    }
    BYTE *at = reinterpret_cast<BYTE *>(0x004F9281);
    if (at[0] != 0xE8 || 0x004F9281u + 5 + *reinterpret_cast<int *>(at + 1) != 0x008C1010u) {
        wlog("effects: call at 004f9281 not as expected, not hooked");
        return;
    }
    DWORD old;
    VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
    *reinterpret_cast<int *>(at + 1) = static_cast<int>(reinterpret_cast<BYTE *>(&world_end) - (at + 5));
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), NULL, 0);
    wlog("effects: world frame end hooked (004f9281)");
}
