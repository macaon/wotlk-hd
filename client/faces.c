/* Per-face head shapes: retail's .bone files (an offset matrix for some head bones per face),
 * shipped by chars.py as Character\wotlk-hd\faces-<race>-<sex>.bin.
 *
 * Which model has which face: CCharacterComponent's geoset update (0x4ed900) runs whenever a
 * character's looks are set up or change; its first SetGeometryVisible call (0x4ed951) has the
 * component in ebx (race +0x18, sex +0x1c, face +0x2c) and the model in ecx. We note model -> face.
 *
 * Applying it: CM2Model's animate (0x82f0f0) computes each bone's matrix as local x parent
 * (0x4c1f00 at 0x82fe4f, model in esi, bone index at [ebp+0x18]) and stores it; parents come
 * before children. For a face bone we make that T(-pivot) x offset x T(pivot) x local x parent:
 * the offset acts in the bone's rest frame at its pivot, moves with the animation and carries
 * over to child bones.
 */
#include <windows.h>
#include <stdlib.h>
#include <string.h>

void wlog(const char *fmt, ...);

typedef float *(__cdecl *matmul_t)(float *, const float *, const float *);
typedef int(__stdcall *load_t)(void *, const char *, void **, unsigned *, unsigned, unsigned, void *);
#define MATMUL ((matmul_t)0x004C1F00)
#define SFILE_LOAD ((load_t)0x00424E80)

struct face { unsigned n; signed char index[1024]; struct { unsigned bone; float m[16]; } *bones; };
struct faceset { int tried; unsigned n; struct face *faces; };
static struct faceset sets[64][2]; /* [race][sex] */

/* model -> face; ponytail: fixed table, a model whose slot run is full evicts the run's first
 * entry (that character keeps the default shape until its looks next change) */
#define SLOTS 4096
static struct slot { BYTE *model; void *shared; struct face *face; } slots[SLOTS];

static struct faceset *load(unsigned race, unsigned sex) {
    struct faceset *s;
    char name[64];
    BYTE *data = NULL, *p;
    unsigned size = 0, i, k;
    if (race >= 64 || sex >= 2)
        return NULL;
    s = &sets[race][sex];
    if (s->tried)
        return s->n ? s : NULL;
    s->tried = 1;
    wsprintfA(name, "Character\\wotlk-hd\\faces-%u-%u.bin", race, sex);
    if (!SFILE_LOAD(NULL, name, (void **)&data, &size, 0, 0, NULL) || size < 12 || memcmp(data, "FACE", 4))
        return NULL; /* not an HD race */
    p = data + 12;
    s->faces = calloc(*(unsigned *)(data + 8), sizeof(struct face));
    for (i = 0; i < *(unsigned *)(data + 8); i++) {
        struct face *f = &s->faces[i];
        memset(f->index, -1, sizeof(f->index));
        f->n = *(unsigned *)p;
        f->bones = (void *)(p + 4);
        for (k = 0; k < f->n; k++)
            if (f->bones[k].bone < sizeof(f->index))
                f->index[f->bones[k].bone] = (signed char)k;
        p += 4 + f->n * sizeof(f->bones[0]);
    }
    s->n = *(unsigned *)(data + 8); /* the buffer stays: the bones point into it */
    wlog("faces: race %u sex %u: %u face shapes", race, sex, s->n);
    return s;
}

static struct slot *slot_of(BYTE *model, int add) {
    unsigned h = ((UINT_PTR)model >> 4) % SLOTS, i;
    for (i = 0; i < 16; i++) {
        struct slot *s = &slots[(h + i) % SLOTS];
        if (s->model == model || (add && !s->model))
            return s;
    }
    return add ? &slots[h] : NULL;
}

__attribute__((used)) void __cdecl record_face(BYTE *model, BYTE *component) {
    struct faceset *set;
    unsigned face;
    struct slot *s;
    if (!model)
        return;
    set = load(*(unsigned *)(component + 0x18), *(unsigned *)(component + 0x1c));
    face = *(unsigned *)(component + 0x2c);
    s = slot_of(model, set != NULL);
    if (!s)
        return;
    s->model = model;
    s->shared = *(void **)(model + 0x2c);
    s->face = set && face < set->n && set->faces[face].n ? &set->faces[face] : NULL;
}

__attribute__((used)) float *__cdecl face_mul(float *out, const float *local, const float *parent, BYTE *model,
                                               unsigned bone) {
    struct slot *s;
    signed char k;
    MATMUL(out, local, parent);
    s = slot_of(model, 0);
    if (!s || !s->face || s->shared != *(void **)(model + 0x2c) || bone >= sizeof(s->face->index) ||
        (k = s->face->index[bone]) < 0)
        return out;
    {
        /* the M2's bones (shared +0x150: the loaded file, bones at +0x30, 0x58 each, pivot +0x4c) */
        const float *pivot = (const float *)(*(BYTE **)(*(BYTE **)((BYTE *)s->shared + 0x150) + 0x30) +
                                             bone * 0x58 + 0x4c);
        const float *m = s->face->bones[k].m;
        float o[16], r[16];
        int i;
        memcpy(o, m, sizeof(o)); /* row vectors: v' = (v - p) M + p */
        for (i = 0; i < 3; i++)
            o[12 + i] = m[12 + i] + pivot[i] - (pivot[0] * m[i] + pivot[1] * m[4 + i] + pivot[2] * m[8 + i]);
        MATMUL(r, o, out);
        memcpy(out, r, sizeof(r));
    }
    return out;
}

__attribute__((naked)) static void record_thunk(void) {
    __asm__ volatile("pushl %ecx\n\t"
                     "pushl %ebx\n\t"
                     "pushl %ecx\n\t"
                     "call _record_face\n\t"
                     "addl $8, %esp\n\t"
                     "popl %ecx\n\t"
                     "movl $0x0082C7C0, %eax\n\t" /* on to SetGeometryVisible */
                     "jmp *%eax\n\t");
}

__attribute__((naked)) static void mul_thunk(void) {
    __asm__ volatile("pushl 0x18(%ebp)\n\t" /* bone index */
                     "pushl %esi\n\t"       /* model */
                     "pushl 20(%esp)\n\t"   /* parent */
                     "pushl 20(%esp)\n\t"   /* local */
                     "pushl 20(%esp)\n\t"   /* out */
                     "call _face_mul\n\t"
                     "addl $20, %esp\n\t"
                     "ret\n\t");
}

void face_hooks(void) {
    static const struct { unsigned site, target; void *hook; } sites[] = {
        {0x004ED951u, 0x0082C7C0u, record_thunk}, {0x0082FE4Fu, 0x004C1F00u, mul_thunk}};
    unsigned i;
    for (i = 0; i < 2; i++) {
        BYTE *at = (BYTE *)(UINT_PTR)sites[i].site;
        if (at[0] != 0xE8 || sites[i].site + 5 + *(int *)(at + 1) != sites[i].target) {
            wlog("faces: call at %08x not as expected, none hooked", sites[i].site);
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
    wlog("faces: 2 call sites hooked (per-face head shapes from Character\\wotlk-hd\\faces-*.bin)");
}
