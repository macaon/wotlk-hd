/* Retail's control options, as saved cvars for the WotlkHD addon's Options window.
 *
 * Mouseover cast (hdMouseoverCast, hdMouseoverCastKey: 0 none, 1 Alt, 2 Ctrl, 3 Shift): an action bar
 * spell without a unit goes to the unit under the mouse when the spell can take it (helpful on a unit
 * we can assist, harmful on one we can attack). Script_UseAction (0x5ac000) resolves its unit argument
 * at 0x5ac043 (0x60abf0; no unit means the target) and its worker casts at 0x5abe54
 * (0x80da80: spell, item, target GUID); we note whether a unit was given at the first and swap the
 * target at the second. Spells only: items and macros keep their own targeting.
 *
 * Lock cursor to window (hdLockCursor): while the game window has focus, the cursor stays inside it
 * (ClipCursor, checked by a thread every 100 ms, since focus changes and window moves reset it). */
#include <windows.h>

#include "cvar.h"

void wlog(const char *fmt, ...);

#define MOUSEOVER_GUID ((unsigned *)0x00BD07A0)
#define UNIT_TOKEN ((int(__cdecl *)(const char *, unsigned *, int))0x0060ABF0)
#define CAST_SPELL ((int(__cdecl *)(int, int, unsigned, unsigned))0x0080DA80)
#define UNIT_BY_TOKEN ((void *(__cdecl *)(const char *))0x0060C1F0)
#define UNIT_CAN_ATTACK ((char(__thiscall *)(void *, void *))0x00729740)
#define UNIT_CAN_ASSIST ((char(__thiscall *)(void *, void *, int))0x007293D0)
#define SPELL_REC_INIT ((void(__thiscall *)(void *))0x008B7DA0)
#define SPELL_REC_FREE ((void(__thiscall *)(void *))0x005EEB70)
#define SPELL_DB_GET ((int(__thiscall *)(void *, int, void *))0x004CFD20)
#define SPELL_DB ((void *)0x00AD49D0)
#define SPELL_KIND ((int(__cdecl *)(void *))0x007FE1B0) /* 1 helpful, 2 harmful (Is*Spell) */

static BYTE *cv_mouseover, *cv_mouseover_key, *cv_lock_cursor;
static int no_unit;

void controls_cvars(void) {
    cv_mouseover = CVAR_SAVED("hdMouseoverCast", "wotlk-hd: action bar spells go to the unit under the mouse", "0");
    cv_mouseover_key = CVAR_SAVED("hdMouseoverCastKey", "wotlk-hd: mouseover cast modifier (0 none, 1 alt, 2 ctrl, 3 shift)", "0");
    cv_lock_cursor = CVAR_SAVED("hdLockCursor", "wotlk-hd: keep the cursor inside the game window", "0");
}

static int modifier_held(void) {
    static const int keys[] = {0, VK_MENU, VK_CONTROL, VK_SHIFT};
    int k = CVAR_INT(cv_mouseover_key);
    return k <= 0 || k > 3 || (GetAsyncKeyState(keys[k]) & 0x8000);
}

static int spell_kind(int spell) {
    __declspec(align(16)) BYTE rec[0x400];
    int kind = 0;
    SPELL_REC_INIT(rec);
    if (SPELL_DB_GET(SPELL_DB, spell, rec))
        kind = SPELL_KIND(rec);
    SPELL_REC_FREE(rec);
    return kind;
}

static int __cdecl use_action_unit(const char *token, unsigned *guid, int flag) {
    no_unit = !token || !*token;
    return UNIT_TOKEN(token, guid, flag);
}

static int __cdecl use_action_cast(int spell, int item, unsigned lo, unsigned hi) {
    if (no_unit && cv_mouseover && CVAR_INT(cv_mouseover) && (MOUSEOVER_GUID[0] || MOUSEOVER_GUID[1]) &&
        modifier_held()) {
        void *player = UNIT_BY_TOKEN("player"), *unit = UNIT_BY_TOKEN("mouseover");
        int kind = player && unit ? spell_kind(spell) : 0;
        if ((kind == 1 && UNIT_CAN_ASSIST(player, unit, 0)) || (kind == 2 && UNIT_CAN_ATTACK(player, unit)))
            lo = MOUSEOVER_GUID[0], hi = MOUSEOVER_GUID[1];
    }
    no_unit = 0;
    return CAST_SPELL(spell, item, lo, hi);
}

static DWORD WINAPI lock_cursor(LPVOID unused) {
    RECT last = {0};
    (void)unused;
    for (;; Sleep(100)) {
        HWND w = GetForegroundWindow();
        DWORD pid = 0;
        RECT r;
        POINT p = {0, 0};
        if (w)
            GetWindowThreadProcessId(w, &pid);
        if (!cv_lock_cursor || !CVAR_INT(cv_lock_cursor) || pid != GetCurrentProcessId() || IsIconic(w)) {
            if (last.right) {
                ClipCursor(NULL);
                last.right = 0;
            }
            continue;
        }
        GetClientRect(w, &r);
        ClientToScreen(w, &p);
        OffsetRect(&r, p.x, p.y);
        RECT now;
        GetClipCursor(&now); /* leave a smaller clip alone (the client's own, mouselook) */
        if (now.left < r.left || now.top < r.top || now.right > r.right || now.bottom > r.bottom) {
            ClipCursor(&r);
            last = r;
        }
    }
    return 0;
}

void controls_hooks(void) {
    static const struct { unsigned site, target; void *hook; } sites[] = {
        {0x005AC043u, 0x0060ABF0u, use_action_unit}, {0x005ABE54u, 0x0080DA80u, use_action_cast}};
    unsigned i;
    for (i = 0; i < 2; i++) {
        BYTE *at = (BYTE *)(UINT_PTR)sites[i].site;
        if (at[0] != 0xE8 || sites[i].site + 5 + *(int *)(at + 1) != sites[i].target) {
            wlog("controls: call at %08x not as expected, no mouseover cast", sites[i].site);
            break;
        }
    }
    if (i == 2) {
        for (i = 0; i < 2; i++) {
            BYTE *at = (BYTE *)(UINT_PTR)sites[i].site;
            DWORD old;
            VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
            *(int *)(at + 1) = (int)((BYTE *)sites[i].hook - (at + 5));
            VirtualProtect(at, 5, old, &old);
        }
        FlushInstructionCache(GetCurrentProcess(), NULL, 0);
        wlog("controls: mouseover cast hooked");
    }
    CloseHandle(CreateThread(NULL, 0, lock_cursor, NULL, 0, NULL));
}
