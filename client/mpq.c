/* StormLib beside the client's own MPQ code (Storm, statically linked into Wow.exe 12340).
 *
 * The game's file layer (SFile2-Core.cpp) reaches Storm through a handful of cdecl calls: open an
 * archive, find which archive holds a file, open a file in it, size, read, close. We take over
 * those call sites (call rel32 -> ours), so Storm's internals and the SoundCache.MPQ paths stay
 * untouched.
 *
 * WOTLKHD_MPQ=shadow: Storm still does the work; every call is repeated through StormLib and the
 * results compared (which archive, size, every byte read). Mismatches go to wotlk-hd.log.
 *
 * WOTLKHD_MPQ=stormlib: StormLib serves every file the game layer reads (find, open, size, read,
 * seek, close); our handles take Storm's place in the game's SFile objects. Storm still opens the
 * archives: the interface file checks (FrameXML signatures, 0x460fb0/0x4610d0) and a few loaders
 * (0x45b5a0, 0x461180, 0x4616a0) look files up in Storm's own archive list. The two game wrappers
 * that pass a file's Storm handle to those checks go by the file's name instead.
 */
#include <windows.h>
#include <stdlib.h>
#include <string.h>

#include "StormLib.h"

void wlog(const char *fmt, ...);

typedef char(__cdecl *open_archive_t)(const char *, unsigned, unsigned, void **);
typedef int(__cdecl *find_t)(void *, const char *, unsigned, void **);
typedef int(__cdecl *open_file_t)(void *, const char *, unsigned, void **);
typedef unsigned(__cdecl *size_t_)(void *, unsigned *);
typedef char(__cdecl *read_t)(void *, void *, unsigned, unsigned *);
typedef int(__cdecl *close_t)(void *);
typedef int(__cdecl *seek_t)(void *, int, int *, unsigned);

#define STORM_OPEN_ARCHIVE ((open_archive_t)0x0045C480)
#define STORM_FIND ((find_t)0x00460EA0)
#define STORM_OPEN_FILE ((open_file_t)0x00426E60)
#define STORM_SIZE ((size_t_)0x00426F70)
#define STORM_READ ((read_t)0x0045A4B0)
#define STORM_CLOSE ((close_t)0x004321A0)
#define STORM_SEEK ((seek_t)0x00426EB0)
typedef int(__cdecl *auth_t)(void *, unsigned);
typedef unsigned(__cdecl *auth_name_t)(const char *, unsigned);
typedef unsigned(__cdecl *check_name_t)(const char *, unsigned, char);
typedef unsigned(__stdcall *check_t)(void *, unsigned, char);
#define STORM_AUTH ((auth_t)0x0045A610)            /* by Storm file handle (vtable) */
#define STORM_AUTH_NAME ((auth_name_t)0x00460FB0)  /* the same by name */
#define STORM_CHECK_NAME ((check_name_t)0x004610D0)
#define GAME_CHECK ((check_t)0x00421820)           /* SFile wrapper: its handle's name to 0x4610d0 */
#define STORM_LAST_ERROR (*(DWORD *)0x00B32508)

/* archive and file handles, Storm's -> ours */
static struct archive { void *storm; HANDLE ours; unsigned prio; } archives[64];
static unsigned n_archives;
static struct file { void *storm; HANDLE ours; char *name; } *files; /* replace: storm == ours */
static unsigned n_files, cap_files;
static CRITICAL_SECTION lock; /* ponytail: one lock for all StormLib calls (the client loads on two
                                 threads); per-archive locks if it ever shows in load times */
static unsigned long long compared_bytes;
static unsigned compared_files, mismatches;
static int replace; /* WOTLKHD_MPQ=stormlib */

static void mismatch(const char *fmt, const char *name, unsigned a, unsigned b) {
    if (++mismatches <= 200) {
        char line[512];
        wsprintfA(line, fmt, a, b);
        wlog("mpq shadow: %s: %s", name, line);
    }
}

static struct archive *archive_of(void *storm) {
    unsigned i;
    for (i = 0; i < n_archives; i++)
        if (archives[i].storm == storm)
            return &archives[i];
    return NULL;
}

static struct file *file_of(void *storm) {
    unsigned i;
    for (i = 0; i < n_files; i++)
        if (files[i].storm == storm)
            return &files[i];
    return NULL;
}

/* Storm hashes '/' as '\\', StormLib does not */
static const char *backslashes(const char *name, char *buf) {
    unsigned i;
    for (i = 0; name[i] && i < MAX_PATH - 1; i++)
        buf[i] = name[i] == '/' ? '\\' : name[i];
    buf[i] = 0;
    return buf;
}

/* Storm's search: the highest priority archive that has the file, unless that entry is a deletion
 * marker (patch-enUS.MPQ deletes Blizzard_VehicleUI.toc that way) */
static struct archive *find_ours(const char *name) {
    struct archive *best = NULL;
    HANDLE f;
    DWORD flags = 0;
    unsigned i;
    for (i = 0; i < n_archives; i++)
        if ((!best || archives[i].prio > best->prio) && SFileHasFile(archives[i].ours, name))
            best = &archives[i];
    if (best && SFileOpenFileEx(best->ours, name, 0, &f)) {
        SFileGetFileInfo(f, SFileInfoFlags, &flags, sizeof(flags), NULL);
        SFileCloseFile(f);
    }
    return flags & MPQ_FILE_DELETE_MARKER ? NULL : best;
}

static char __cdecl hook_open_archive(const char *name, unsigned prio, unsigned flags, void **out) {
    char ok = STORM_OPEN_ARCHIVE(name, prio, flags, out);
    HANDLE ours;
    if (!ok)
        return ok;
    EnterCriticalSection(&lock);
    if (n_archives == sizeof(archives) / sizeof(archives[0]))
        wlog("mpq: %s: more than %u archives, not opened by StormLib", name, n_archives);
    else if (!SFileOpenArchive(name, 0, STREAM_FLAG_READ_ONLY | MPQ_OPEN_NO_LISTFILE | MPQ_OPEN_NO_ATTRIBUTES, &ours))
        wlog("mpq: StormLib cannot open %s (%lu)", name, GetLastError());
    else {
        archives[n_archives].storm = *out;
        archives[n_archives].ours = ours;
        archives[n_archives++].prio = prio;
        wlog("mpq: %s priority %u flags %x", name, prio, flags);
    }
    LeaveCriticalSection(&lock);
    return ok;
}

static int __cdecl hook_find(void *archive, const char *name, unsigned flags, void **out) {
    struct archive *storm_in, *ours;
    char buf[MAX_PATH];
    int found;
    if (replace && !archive) {
        EnterCriticalSection(&lock);
        ours = find_ours(backslashes(name, buf));
        LeaveCriticalSection(&lock);
        if (out)
            *out = ours ? ours->storm : NULL; /* Storm's handle: what hook_open_file gets back */
        return ours != NULL;
    }
    found = STORM_FIND(archive, name, flags, out);
    EnterCriticalSection(&lock);
    name = backslashes(name, buf);
    storm_in = found && out ? archive_of(*out) : NULL; /* without out, only whether it exists */
    ours = archive ? NULL : find_ours(name);
    if (archive)
        ; /* a search in one archive: not used by the game, nothing to compare */
    else if (!found != !ours)
        mismatch("found by Storm %u, by StormLib %u", name, !!found, !!ours);
    else if (found && out && storm_in != ours)
        mismatch("Storm found it at priority %u, StormLib at %u", name, storm_in ? storm_in->prio : ~0u,
                 ours->prio);
    LeaveCriticalSection(&lock);
    return found;
}

static void add_file(void *storm, HANDLE ours, const char *name) {
    if (n_files == cap_files) {
        cap_files = cap_files ? cap_files * 2 : 256;
        files = realloc(files, cap_files * sizeof(*files));
    }
    files[n_files].storm = storm;
    files[n_files].ours = ours;
    files[n_files++].name = _strdup(name);
}

static int __cdecl hook_open_file(void *archive, const char *name, unsigned flags, void **out) {
    int ok = 0;
    struct archive *in;
    HANDLE ours = NULL;
    char buf[MAX_PATH];
    if (replace) {
        EnterCriticalSection(&lock);
        in = archive ? archive_of(archive) : find_ours(backslashes(name, buf));
        if (in || !archive) {
            if (in && SFileOpenFileEx(in->ours, backslashes(name, buf), 0, &ours))
                add_file(ours, ours, name); /* the name as the game gave it, for the interface checks */
            else
                ours = NULL;
            *out = ours;
            LeaveCriticalSection(&lock);
            return ours != NULL;
        }
        LeaveCriticalSection(&lock); /* an archive we do not have: Storm's */
    }
    ok = STORM_OPEN_FILE(archive, name, flags, out);
    EnterCriticalSection(&lock);
    in = archive ? archive_of(archive) : find_ours(backslashes(name, buf));
    if (in && !SFileOpenFileEx(in->ours, backslashes(name, buf), 0, &ours))
        ours = NULL;
    if (!ok != !ours && (in || !archive))
        mismatch("opened by Storm %u, by StormLib %u", name, !!ok, !!ours);
    if (ok && ours)
        add_file(*out, ours, name);
    else if (ours)
        SFileCloseFile(ours);
    LeaveCriticalSection(&lock);
    return ok;
}

static unsigned __cdecl hook_size(void *file, unsigned *high) {
    unsigned size;
    struct file *f;
    if (replace) {
        EnterCriticalSection(&lock);
        f = file_of(file);
        size = f ? SFileGetFileSize(f->ours, (DWORD *)high) : 0;
        LeaveCriticalSection(&lock);
        if (f)
            return size;
    }
    size = STORM_SIZE(file, high);
    EnterCriticalSection(&lock);
    f = file_of(file);
    if (f && SFileGetFileSize(f->ours, NULL) != size)
        mismatch("size %u from Storm, %u from StormLib", f->name, size, SFileGetFileSize(f->ours, NULL));
    LeaveCriticalSection(&lock);
    return size;
}

/* Storm reads past the end as a success with fewer bytes and error 0x26; StormLib fails */
static char __cdecl hook_read(void *file, void *buf, unsigned n, unsigned *read) {
    char ok;
    struct file *f;
    if (replace) {
        DWORD got = 0;
        EnterCriticalSection(&lock);
        f = file_of(file);
        if (f) {
            ok = SFileReadFile(f->ours, buf, n, &got, NULL) || GetLastError() == ERROR_HANDLE_EOF;
            LeaveCriticalSection(&lock);
            if (read)
                *read = got;
            if (got != n)
                STORM_LAST_ERROR = ERROR_HANDLE_EOF;
            return ok;
        }
        LeaveCriticalSection(&lock);
    }
    ok = STORM_READ(file, buf, n, read);
    EnterCriticalSection(&lock);
    f = file_of(file);
    if (f) {
        void *mine = malloc(n ? n : 1);
        DWORD got = 0;
        SFileReadFile(f->ours, mine, n, &got, NULL);
        if (ok && got != (read ? *read : n))
            mismatch("read %u bytes through Storm, %u through StormLib", f->name, read ? *read : n, got);
        else if (ok && memcmp(buf, mine, got))
            mismatch("%u bytes differ (of %u)", f->name, got, n);
        compared_bytes += got;
        free(mine);
    }
    LeaveCriticalSection(&lock);
    return ok;
}

/* Storm takes no high part: positions stay 32-bit */
static int __cdecl hook_seek(void *file, int distance, int *high, unsigned method) {
    int pos;
    struct file *f;
    if (replace) {
        EnterCriticalSection(&lock);
        f = file_of(file);
        pos = f ? (int)SFileSetFilePointer(f->ours, distance, NULL, method) : 0;
        LeaveCriticalSection(&lock);
        if (f)
            return pos;
    }
    pos = STORM_SEEK(file, distance, high, method);
    EnterCriticalSection(&lock);
    f = file_of(file);
    if (f) {
        DWORD ours = SFileSetFilePointer(f->ours, distance, NULL, method);
        if (ours != (DWORD)pos)
            mismatch("seek to %u through Storm, %u through StormLib", f->name, pos, ours);
    }
    LeaveCriticalSection(&lock);
    return pos;
}

static int __cdecl hook_close(void *file) {
    struct file *f;
    EnterCriticalSection(&lock);
    f = file_of(file);
    if (f) {
        SFileCloseFile(f->ours);
        free(f->name);
        *f = files[--n_files];
        if (++compared_files % 1000 == 0 && !replace)
            wlog("mpq shadow: %u files, %llu MB compared, %u mismatches", compared_files, compared_bytes >> 20,
                 mismatches);
        if (replace) {
            LeaveCriticalSection(&lock);
            return 1;
        }
    }
    LeaveCriticalSection(&lock);
    return STORM_CLOSE(file);
}

/* the interface file checks, for files we serve: by name, which Storm resolves to the same archive */
static const char *name_of(void *file) {
    struct file *f;
    const char *name;
    EnterCriticalSection(&lock);
    f = file_of(file);
    name = f ? f->name : NULL; /* stays valid: the game holds the file open around the check */
    LeaveCriticalSection(&lock);
    return name;
}

static int __cdecl hook_auth(void *file, unsigned arg) {
    const char *name = name_of(file);
    return name ? (int)STORM_AUTH_NAME(name, arg) : STORM_AUTH(file, arg);
}

static unsigned __stdcall hook_check(void *sfile, unsigned arg, char flag) {
    const char *name = name_of(*(void **)((BYTE *)sfile + 0x20));
    return name ? STORM_CHECK_NAME(name, arg, flag) : GAME_CHECK(sfile, arg, flag);
}

static const struct { unsigned site, target; void *hook; } sites[] = {
    {0x004219A9u, 0x0045C480u, hook_open_archive}, /* the Data\ patch list (0x405dd0 via 0x421950) */
    {0x00422053u, 0x0045C480u, hook_open_archive},
    {0x0041E26Du, 0x0045C480u, hook_open_archive},
    {0x00424A8Fu, 0x00460EA0u, hook_find}, /* SFile::OpenEx: which archive has it */
    {0x00421F10u, 0x00460EA0u, hook_find},
    {0x00421FCEu, 0x00460EA0u, hook_find},
    {0x00424D88u, 0x00426E60u, hook_open_file},
    {0x0042191Au, 0x00426F70u, hook_size},
    {0x00422617u, 0x0045A4B0u, hook_read},
    {0x00421C2Fu, 0x00426EB0u, hook_seek}, /* SFile::SetFilePointer: sound streams seek */
    {0x00422937u, 0x004321A0u, hook_close},
    {0x004217CEu, 0x0045A610u, hook_auth}, /* stormlib only, from here on */
    {0x004BA7A7u, 0x00421820u, hook_check},
};
#define SHADOW_SITES 11

void mpq_hooks(void) {
    char mode[16] = "";
    unsigned i, n = sizeof(sites) / sizeof(sites[0]);
    GetEnvironmentVariableA("WOTLKHD_MPQ", mode, sizeof(mode));
    replace = lstrcmpiA(mode, "stormlib") == 0;
    if (!replace && lstrcmpiA(mode, "shadow") != 0)
        return;
    if (!replace)
        n = SHADOW_SITES;
    for (i = 0; i < n; i++) {
        BYTE *at = (BYTE *)(UINT_PTR)sites[i].site;
        if (at[0] != 0xE8 || sites[i].site + 5 + *(int *)(at + 1) != sites[i].target) {
            wlog("mpq %s: call at %08x not as expected, none hooked", mode, sites[i].site);
            return;
        }
    }
    InitializeCriticalSection(&lock);
    for (i = 0; i < n; i++) {
        BYTE *at = (BYTE *)(UINT_PTR)sites[i].site;
        DWORD old;
        VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
        *(int *)(at + 1) = (int)((BYTE *)sites[i].hook - (at + 5));
        VirtualProtect(at, 5, old, &old);
    }
    FlushInstructionCache(GetCurrentProcess(), NULL, 0);
    wlog(replace ? "mpq stormlib: %u call sites hooked; StormLib serves the game's files, Storm keeps its archives "
                   "open for the interface checks"
                 : "mpq shadow: %u call sites hooked; StormLib repeats every archive read and compares", n);
}
