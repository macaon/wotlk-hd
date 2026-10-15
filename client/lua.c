/* Lua functions from the DLL for our addons (the awesome_wotlk approach). The game UI's Lua state is
 * made fresh on every UI load and /reload (0x52aa..: FrameScript_Initialize 0x819bb0, then the game's
 * script functions 0x5120e0, called once, at 0x52ab16); ours are registered right after the
 * game's, through FrameScript_RegisterFunction (0x817f90: a global C closure). The glue screens'
 * state gets none.
 *
 * The client only calls C functions inside Wow.exe's code: 0x86b5a0 checks each against bounds at
 * 0xd415b8/0xd415bc (.data), which 0x86b510 fills from the .text section while they are 0. Set
 * first, they cover the whole address space. Warden (server side) can read them; AzerothCore's default checks
 * do not. */
#include <windows.h>

#include "lua.h"

void wlog(const char *fmt, ...);

#define FRAMESCRIPT_REGISTER ((void(__cdecl *)(const char *, lua_CFunction))0x00817F90)
#define GAME_SCRIPT_FUNCTIONS ((void(__cdecl *)(void))0x005120E0)
#define CFUNC_LOW ((DWORD *)0x00D415B8)
#define CFUNC_HIGH ((DWORD *)0x00D415BC)
#define WOTLKHD_LUA_VERSION 3 /* WotlkHD_Version(): bump when the functions change */

static struct { const char *name; lua_CFunction fn; } functions[64];
static unsigned function_count;

void lua_function(const char *name, lua_CFunction fn) {
    if (function_count == sizeof(functions) / sizeof(functions[0])) {
        wlog("lua: no room for %s", name);
        return;
    }
    functions[function_count].name = name;
    functions[function_count++].fn = fn;
}

static void __cdecl script_functions(void) {
    unsigned i;
    GAME_SCRIPT_FUNCTIONS();
    for (i = 0; i < function_count; i++)
        FRAMESCRIPT_REGISTER(functions[i].name, functions[i].fn);
}

static int __cdecl version(lua_State *L) {
    lua_pushnumber(L, WOTLKHD_LUA_VERSION);
    return 1;
}

void lua_hooks(void) {
    BYTE *at = (BYTE *)0x0052AB16;
    DWORD old;
    if (at[0] != 0xE8 || 0x0052AB16 + 5 + *(int *)(at + 1) != 0x005120E0 || *CFUNC_LOW || *CFUNC_HIGH) {
        wlog("lua: call at 0052ab16 or C function bounds not as expected, no Lua functions");
        return;
    }
    *CFUNC_LOW = 1;
    *CFUNC_HIGH = 0xFFFFFFFF;
    VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
    *(int *)(at + 1) = (int)((BYTE *)script_functions - (at + 5));
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), NULL, 0);
    lua_function("WotlkHD_Version", version);
    wlog("lua: %u functions for the game UI", function_count);
}
