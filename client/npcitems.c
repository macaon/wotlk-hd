/* Weapons for NPCs moved onto HD character models (chars.py NPC_LOOKS): their old creature models
 * had the weapons in the mesh, and AzerothCore sends no equipment for them. chars.py ships
 * Character\wotlk-hd\npc-items.bin (display -> main hand, off hand, ranged item ids, its own Item.dbc
 * rows) and here a unit with such a display and no virtual items from the server gets those, so the
 * client's own code shows them like any NPC's equipment.
 *
 * Where: the client shows a virtual item only when the server changes UNIT_VIRTUAL_ITEM_SLOT_ID: the
 * field's update callback (0x728e20) calls the unit's handler (0x725010, slot and item), which
 * caches the item's display (unit+0x998) and attaches its model to the unit's model (unit+0xb4).
 * So after the display setup of NPCs with a look (0x71d010, called at 0x730199 for units with a
 * CreatureDisplayInfoExtra record) has built the model, we fill the fields (unit+0xd0:
 * UNIT_VIRTUAL_ITEM_SLOT_ID at +0xc8, UNIT_FIELD_DISPLAYID at +0xf4) and call that handler.
 */
#include <windows.h>
#include <string.h>

void wlog(const char *fmt, ...);

typedef int(__stdcall *load_t)(void *, const char *, void **, unsigned *, unsigned, unsigned, void *);
typedef int(__attribute__((thiscall)) *setup_t)(void *unit, int a, int b);
typedef void(__attribute__((thiscall)) *virtual_item_t)(void *unit, unsigned slot, unsigned item);
#define SFILE_LOAD ((load_t)0x00424E80)
#define DISPLAY_SETUP ((setup_t)0x0071D010)
#define VIRTUAL_ITEM_CHANGED ((virtual_item_t)0x00725010)
#define UNIT_FIELDS 0xD0
#define VIRTUAL_ITEMS 0xC8
#define DISPLAY_ID 0xF4

struct entry { unsigned display, items[3]; };
static const struct entry *table;
static unsigned count, tried;

static const struct entry *find(unsigned display) {
    unsigned i;
    if (!tried) {
        BYTE *data = NULL;
        unsigned size = 0;
        tried = 1;
        if (SFILE_LOAD(NULL, "Character\\wotlk-hd\\npc-items.bin", (void **)&data, &size, 0, 0, NULL) &&
            size >= 8 && !memcmp(data, "NPCI", 4) && 8 + *(unsigned *)(data + 4) * sizeof(struct entry) <= size) {
            count = *(unsigned *)(data + 4);
            table = (const struct entry *)(data + 8); /* the buffer stays */
        }
        wlog("npc items: %u NPC displays with weapons", count);
    }
    for (i = 0; i < count; i++)
        if (table[i].display == display)
            return &table[i];
    return NULL;
}

static int __fastcall npc_display_setup(BYTE *unit, void *edx, int a, int b) {
    int r = DISPLAY_SETUP(unit, a, b);
    BYTE *fields = *(BYTE **)(unit + UNIT_FIELDS);
    unsigned i;
    (void)edx;
    if (r && fields) {
        unsigned *slots = (unsigned *)(fields + VIRTUAL_ITEMS);
        const struct entry *e = find(*(unsigned *)(fields + DISPLAY_ID));
        if (e && !slots[0] && !slots[1] && !slots[2])
            for (i = 0; i < 3; i++)
                if (e->items[i]) {
                    slots[i] = e->items[i];
                    VIRTUAL_ITEM_CHANGED(unit, i, e->items[i]);
                }
    }
    return r;
}

void npc_item_hooks(void) {
    BYTE *at = (BYTE *)0x00730199;
    DWORD old;
    if (at[0] != 0xE8 || 0x00730199u + 5 + *(int *)(at + 1) != 0x0071D010u) {
        wlog("npc items: call at 00730199 not as expected, not hooked");
        return;
    }
    VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
    *(int *)(at + 1) = (int)((BYTE *)npc_display_setup - (at + 5));
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), NULL, 0);
    wlog("npc items: NPC display setup hooked (00730199)");
}
