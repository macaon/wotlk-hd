/* Nameplates as units, as on retail: "nameplateN" works as a unit token in every Unit* function
 * (UnitName("nameplate3"), UnitCastingInfo, UnitAura, "nameplate3target", ...), and
 * WotlkHD_NamePlateUnit(frame) gives a nameplate frame's token, and WotlkHD_UnitDistance(unit) a unit's
 * distance (for retail's scaling of nameplates by distance). Nameplates show out to retail's 60 yards
 * instead of 41 (the range at 0xadaa7c, squared, read once at 0x72b331). A unit's nameplate frame is at
 * CGUnit+0xc38 (null without one). The client reuses its nameplate frames, so a frame gets its number
 * the first time it's asked for and keeps it.
 *
 * Token parsing (0x60abf0) tries its prefixes in turn; we go in before its last ("none", 0x60afaa) and
 * on a match continue where it reads suffixes such as "target" (0x60ad57). Offsets as awesome_wotlk
 * found them. */
#include <windows.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

#include "lua.h"

void wlog(const char *fmt, ...);

#define ENUM_OBJECTS ((int(__cdecl *)(int(__cdecl *)(unsigned, unsigned, void *), void *))0x004D4B30)
#define GET_OBJECT ((BYTE *(__cdecl *)(unsigned, unsigned, int, const char *, int))0x004D4DB0)
#define TYPE_UNIT 8
#define UNIT_NAMEPLATE 0xC38
#define MAX_PLATES 256
#define PLATE_RANGE_SQ ((float *)0x00ADAA7C) /* nameplates show within this distance squared (41^2) */
#define UNIT_BY_TOKEN ((BYTE *(__cdecl *)(const char *))0x0060C1F0)
typedef void(__thiscall *get_position_t)(BYTE *, float *); /* CGUnit vtable slot 11: x, y, z */

static void *plates[MAX_PLATES];
static unsigned plate_count;

struct find { void *plate; unsigned guid[2]; };

static int __cdecl find_unit(unsigned lo, unsigned hi, void *data) {
    struct find *f = data;
    BYTE *unit = GET_OBJECT(lo, hi, TYPE_UNIT, "", 0);
    if (unit && *(void **)(unit + UNIT_NAMEPLATE) == f->plate) {
        f->guid[0] = lo, f->guid[1] = hi;
        return 0;
    }
    return 1;
}

/* ponytail: walks the object list per lookup (a few hundred objects); keep a per-frame map if it ever
 * shows up in a profile */
static void plate_guid(void *plate, unsigned guid[2]) {
    struct find f = {plate, {0, 0}};
    ENUM_OBJECTS(find_unit, &f);
    guid[0] = f.guid[0], guid[1] = f.guid[1];
}

__attribute__((used)) int __cdecl nameplate_token(const char **token, unsigned *guid) {
    const char *s = *token;
    unsigned n = 0;
    if (_strnicmp(s, "nameplate", 9))
        return 0;
    for (s += 9; *s >= '0' && *s <= '9'; s++)
        n = n * 10 + (*s - '0');
    *token = s;
    guid[0] = guid[1] = 0;
    if (n >= 1 && n <= plate_count)
        plate_guid(plates[n - 1], guid);
    return 1;
}

__attribute__((naked)) static void token_thunk(void) {
    __asm__ volatile("pushal\n\t"
                     "pushl %esi\n\t"     /* the GUID out */
                     "leal 8(%ebp), %eax\n\t" /* the token, advanced past what we read */
                     "pushl %eax\n\t"
                     "call _nameplate_token\n\t"
                     "addl $8, %esp\n\t"
                     "testl %eax, %eax\n\t"
                     "popal\n\t"
                     "jnz 1f\n\t"
                     "movl 8(%ebp), %eax\n\t" /* the instructions we replaced */
                     "pushl $0x7FFFFFFF\n\t"
                     "pushl $0x0060AFB2\n\t"
                     "ret\n"
                     "1:\n\t"
                     "pushl $0x0060AD57\n\t"
                     "ret\n\t");
}

static int __cdecl nameplate_unit(lua_State *L) {
    void *plate;
    unsigned guid[2], i;
    char token[16];
    if (lua_type(L, 1) != LUA_TTABLE) {
        lua_pushnil(L);
        return 1;
    }
    lua_rawgeti(L, 1, 0);
    plate = lua_touserdata(L, -1);
    lua_settop(L, -2);
    if (!plate || (plate_guid(plate, guid), !(guid[0] | guid[1]))) {
        lua_pushnil(L);
        return 1;
    }
    for (i = 0; i < plate_count && plates[i] != plate; i++)
        ;
    if (i == plate_count) {
        if (plate_count == MAX_PLATES) {
            lua_pushnil(L);
            return 1;
        }
        plates[plate_count++] = plate;
    }
    snprintf(token, sizeof(token), "nameplate%u", i + 1);
    lua_pushstring(L, token);
    return 1;
}

/* WotlkHD_UnitDistance(unit): yards from the player, or nil; for scaling nameplates by distance, as
 * retail does (addons get no positions in 3.3.5). */
static int __cdecl unit_distance(lua_State *L) {
    const char *token = lua_type(L, 1) == LUA_TSTRING ? lua_tostring(L, 1) : 0;
    BYTE *unit = token ? UNIT_BY_TOKEN(token) : 0, *player = UNIT_BY_TOKEN("player");
    float a[3], b[3];
    if (!unit || !player) {
        lua_pushnil(L);
        return 1;
    }
    (*(get_position_t **)unit)[11](unit, a);
    (*(get_position_t **)player)[11](player, b);
    lua_pushnumber(L, sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2])));
    return 1;
}

void nameplate_hooks(void) {
    static const BYTE orig[] = {0x8B, 0x45, 0x08, 0x68, 0xFF, 0xFF, 0xFF, 0x7F};
    BYTE *at = (BYTE *)0x0060AFAA;
    DWORD old;
    if (memcmp(at, orig, sizeof(orig))) {
        wlog("nameplates: token parser at 0060afaa not as expected, no nameplate units");
        return;
    }
    VirtualProtect(at, sizeof(orig), PAGE_EXECUTE_READWRITE, &old);
    at[0] = 0xE9;
    *(int *)(at + 1) = (int)((BYTE *)token_thunk - (at + 5));
    memset(at + 5, 0x90, sizeof(orig) - 5);
    VirtualProtect(at, sizeof(orig), old, &old);
    FlushInstructionCache(GetCurrentProcess(), NULL, 0);
    *PLATE_RANGE_SQ = 60.0f * 60.0f; /* retail's nameplateMaxDistance */
    lua_function("WotlkHD_NamePlateUnit", nameplate_unit);
    lua_function("WotlkHD_UnitDistance", unit_distance);
    wlog("nameplates: nameplateN unit tokens, 60 yard range");
}
