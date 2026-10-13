/* Unit frame portraits at 256x256 instead of 64x64 (shown at about 120 px at 1440p, so 64 was
 * stretched twice). SetPortraitTexture (0x619580) renders the unit's model straight into a
 * "Portrait1" texture when the device can render to textures (0xc5cdfc), then masks it round with a
 * quad: only the texture's size (0x619b72) and, on the APIs that need one, the portrait depth target
 * (0x6180e8, created once at startup) say 64. Without render to texture it draws into a 64x64 screen
 * corner and reads it back instead; that path keeps 64, told apart by the render target flag. */
#include <windows.h>

void wlog(const char *fmt, ...);

#define PORTRAIT_SIZE 256u
#define GX_TEX_RENDER_TARGET 0x80u

typedef void *(__cdecl *tex_create_t)(UINT w, UINT h, UINT format, UINT format2, UINT flags, void *pixels,
                                      void *callback, const char *name, UINT unused);
typedef void *(__cdecl *tex_create_ex_t)(UINT, UINT w, UINT h, UINT, UINT, UINT, UINT flags, UINT, void *,
                                         const char *, UINT);

static void *__cdecl portrait_texture(UINT w, UINT h, UINT format, UINT format2, UINT flags, void *pixels,
                                      void *callback, const char *name, UINT unused) {
    if (flags & GX_TEX_RENDER_TARGET)
        w = h = PORTRAIT_SIZE;
    return ((tex_create_t)0x004B9200)(w, h, format, format2, flags, pixels, callback, name, unused);
}

static void *__cdecl portrait_depth(UINT a, UINT w, UINT h, UINT b, UINT c, UINT d, UINT flags, UINT e,
                                    void *callback, const char *name, UINT f) {
    (void)w, (void)h;
    return ((tex_create_ex_t)0x004B8C80)(a, PORTRAIT_SIZE, PORTRAIT_SIZE, b, c, d, flags, e, callback, name, f);
}

void portrait_hooks(void) {
    static const struct { unsigned site, target; void *hook; } sites[] = {
        {0x00619B72u, 0x004B9200u, portrait_texture}, {0x006180E8u, 0x004B8C80u, portrait_depth}};
    unsigned i;
    for (i = 0; i < 2; i++) {
        BYTE *at = (BYTE *)(UINT_PTR)sites[i].site;
        if (at[0] != 0xE8 || sites[i].site + 5 + *(int *)(at + 1) != sites[i].target) {
            wlog("portraits: call at %08x not as expected, none hooked", sites[i].site);
            return;
        }
    }
    for (i = 0; i < 2; i++) {
        BYTE *at = (BYTE *)(UINT_PTR)sites[i].site;
        DWORD old;
        VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
        *(int *)(at + 1) = (int)((BYTE *)sites[i].hook - (at + 5));
        VirtualProtect(at, 5, old, &old);
    }
    FlushInstructionCache(GetCurrentProcess(), NULL, 0);
    wlog("portraits: rendered at %ux%u", PORTRAIT_SIZE, PORTRAIT_SIZE);
}
