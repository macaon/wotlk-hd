/* wotlk-hd client extension, loaded by Wow.exe as dinput8.dll (it imports DINPUT8.dll).
 *
 * Forwards DirectInput8Create to the system dinput8.dll and runs our own code inside the client:
 * hooks for what byte patches cannot do cleanly. For now it only proves it loads, writing
 * wotlk-hd.log next to the exe. Under Wine/Proton: WINEDLLOVERRIDES=dinput8=n,b.
 */
#include <windows.h>
#include <stdio.h>

typedef HRESULT(WINAPI *DirectInput8Create_t)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN);
static DirectInput8Create_t real_create;
static FILE *log_file;

void wlog(const char *fmt, ...) {
    if (!log_file)
        return;
    va_list args;
    va_start(args, fmt);
    vfprintf(log_file, fmt, args);
    va_end(args);
    fputc('\n', log_file);
    fflush(log_file);
}

static void open_log(void) {
    char path[MAX_PATH];
    DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
    while (n && path[n - 1] != '\\' && path[n - 1] != '/')
        n--;
    lstrcpyA(path + n, "wotlk-hd.log");
    log_file = fopen(path, "w");
}

static int load_real(void) {
    if (real_create)
        return 1;
    char path[MAX_PATH];
    UINT n = GetSystemDirectoryA(path, MAX_PATH);
    lstrcpyA(path + n, "\\dinput8.dll");
    HMODULE real = LoadLibraryA(path);
    if (real)
        real_create = (DirectInput8Create_t)GetProcAddress(real, "DirectInput8Create");
    wlog("system dinput8: %s (%s)", path, real_create ? "ok" : "missing");
    return real_create != NULL;
}

__declspec(dllexport) HRESULT WINAPI DirectInput8Create(HINSTANCE inst, DWORD version, REFIID iid, LPVOID *out,
                                                        LPUNKNOWN outer) {
    if (!load_real())
        return E_FAIL;
    return real_create(inst, version, iid, out, outer);
}

BOOL WINAPI DllMain(HINSTANCE dll, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(dll);
        open_log();
        char exe[MAX_PATH];
        GetModuleFileNameA(NULL, exe, MAX_PATH);
        HMODULE base = GetModuleHandleA(NULL);
        wlog("wotlk-hd client extension loaded into %s (base %p)", exe, (void *)base);
        /* 3.3.5a 12340 checks: the FoV constant patch_exe.py writes, read back */
        wlog("Wow.exe build check: PE timestamp %08lx",
             ((IMAGE_NT_HEADERS *)((BYTE *)base + ((IMAGE_DOS_HEADER *)base)->e_lfanew))->FileHeader.TimeDateStamp);
    }
    return TRUE;
}
