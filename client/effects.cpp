/* Post-processing under the UI: SMAA, then CAS sharpening (post.hlsl, compiled into shaders.h).
 * The world frame (WorldFrame.cpp) ends with the client's own full-frame effects (glow, death,
 * nether: 0x8c1010, called at 0x4f9281); the UI draws after it. We hook that call, let it run,
 * then run our passes on the back buffer, so they never touch the UI. D3D9 only: the client's
 * device is the gx device's (0xc5df88) IDirect3DDevice9 at +0x397c, used only once its vtable is
 * found in d3d9.dll (not under -opengl). Our render targets live in D3DPOOL_DEFAULT, which D3D9
 * wants released before IDirect3DDevice9::Reset: we hook Reset in the device's vtable for that.
 * WOTLKHD_EFFECTS picks the effects: "smaa,cas" (the default), "smaa", "cas" or "off". */
#include <windows.h>
#include <d3d9.h>
#include <stdlib.h>
#include <string.h>

#include "shaders.h"
#include "../cache/smaa/Textures/AreaTex.h"
#include "../cache/smaa/Textures/SearchTex.h"

extern "C" void wlog(const char *fmt, ...);

#define FFX_APPLY ((void(__cdecl *)(void))0x008C1010)
#define GX_DEVICE (*(BYTE **)0x00C5DF88)
#define GX_D3D_DEVICE 0x397C
#define CAS_SHARPNESS 1.0f /* 0..1; AMD's full strength, still mild at 1440p */

static bool use_smaa = true, use_cas = true, broken;
static IDirect3DDevice9 *dev;
static IDirect3DVertexShader9 *vs_quad, *vs_edges, *vs_weights, *vs_blend;
static IDirect3DPixelShader9 *ps_edges, *ps_weights, *ps_blend, *ps_cas;
static IDirect3DTexture9 *area, *search;               /* D3DPOOL_MANAGED: survive Reset */
static IDirect3DTexture9 *color, *edges, *weights, *temp; /* D3DPOOL_DEFAULT, back buffer size */
static IDirect3DStateBlock9 *state;
static UINT width, height;

template <class T> static void release(T *&p) {
    if (p)
        p->Release();
    p = nullptr;
}

static void release_targets(void) {
    release(color);
    release(edges);
    release(weights);
    release(temp);
    release(state);
    width = height = 0;
}

typedef HRESULT(STDMETHODCALLTYPE *reset_t)(IDirect3DDevice9 *, D3DPRESENT_PARAMETERS *);
static reset_t real_reset;

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

    bool ok = SUCCEEDED(dev->CreateVertexShader(quad_vs, &vs_quad)) &&
              SUCCEEDED(dev->CreateVertexShader(smaa_edges_vs, &vs_edges)) &&
              SUCCEEDED(dev->CreateVertexShader(smaa_weights_vs, &vs_weights)) &&
              SUCCEEDED(dev->CreateVertexShader(smaa_blend_vs, &vs_blend)) &&
              SUCCEEDED(dev->CreatePixelShader(smaa_edges_ps, &ps_edges)) &&
              SUCCEEDED(dev->CreatePixelShader(smaa_weights_ps, &ps_weights)) &&
              SUCCEEDED(dev->CreatePixelShader(smaa_blend_ps, &ps_blend)) &&
              SUCCEEDED(dev->CreatePixelShader(cas_ps, &ps_cas));
    area = lookup_texture(AREATEX_WIDTH, AREATEX_HEIGHT, D3DFMT_A8L8, areaTexBytes, AREATEX_PITCH);
    search = lookup_texture(SEARCHTEX_WIDTH, SEARCHTEX_HEIGHT, D3DFMT_L8, searchTexBytes, SEARCHTEX_PITCH);
    if (!ok || !area || !search) {
        wlog("effects: shaders or SMAA textures failed, effects off");
        return false;
    }
    wlog("effects: D3D9 device %p, %s%s%s before the UI", (void *)dev, use_smaa ? "SMAA" : "",
         use_smaa && use_cas ? " and " : "", use_cas ? "CAS" : "");
    return true;
}

static IDirect3DTexture9 *target_texture(void) {
    IDirect3DTexture9 *t = nullptr;
    dev->CreateTexture(width, height, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &t, nullptr);
    return t;
}

static bool make_targets(UINT w, UINT h) {
    release_targets();
    width = w, height = h;
    color = target_texture();
    edges = use_smaa ? target_texture() : nullptr;
    weights = use_smaa ? target_texture() : nullptr;
    temp = use_smaa && use_cas ? target_texture() : nullptr;
    if (FAILED(dev->CreateStateBlock(D3DSBT_ALL, &state)))
        state = nullptr;
    if (!color || !state || (use_smaa && (!edges || !weights)) || (use_smaa && use_cas && !temp)) {
        wlog("effects: no %ux%u render targets, effects off", w, h);
        release_targets();
        return false;
    }
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

/* Full-screen quad, shifted half a pixel for D3D9's pixel centres (as in SMAA's D3D9 demo). */
static void draw(IDirect3DVertexShader9 *vs, IDirect3DPixelShader9 *ps) {
    float px = 1.0f / width, py = 1.0f / height;
    float quad[4][5] = {{-1.0f - px, 1.0f + py, 0.5f, 0.0f, 0.0f},
                        {1.0f - px, 1.0f + py, 0.5f, 1.0f, 0.0f},
                        {-1.0f - px, -1.0f + py, 0.5f, 0.0f, 1.0f},
                        {1.0f - px, -1.0f + py, 0.5f, 1.0f, 1.0f}};
    dev->SetVertexShader(vs);
    dev->SetPixelShader(ps);
    dev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, quad, sizeof(quad[0]));
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
    float cas[4] = {-1.0f / (8.0f + (5.0f - 8.0f) * CAS_SHARPNESS), 0.0f, 0.0f, 0.0f};
    dev->SetVertexShaderConstantF(0, metrics, 1);
    dev->SetPixelShaderConstantF(0, metrics, 1);
    dev->SetPixelShaderConstantF(1, cas, 1);

    color->GetSurfaceLevel(0, &color_surface);
    dev->StretchRect(back, nullptr, color_surface, nullptr, D3DTEXF_NONE);
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

    state->Apply();
    dev->SetRenderTarget(0, saved_target);
    dev->SetDepthStencilSurface(saved_depth);
    if (saved_target)
        saved_target->Release();
    if (saved_depth)
        saved_depth->Release();
    back->Release();
}

static void __cdecl world_end(void) {
    FFX_APPLY();
    if (broken)
        return;
    if (!dev && !setup()) {
        broken = true;
        return;
    }
    render();
}

extern "C" void effects_hooks(void) {
    const char *mode = getenv("WOTLKHD_EFFECTS");
    if (mode) {
        use_smaa = strstr(mode, "smaa") != nullptr;
        use_cas = strstr(mode, "cas") != nullptr;
    }
    if (!use_smaa && !use_cas) {
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
