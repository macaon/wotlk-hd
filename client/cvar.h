/* The client's console variables (12340): CVar::Register (0x767fc0, cdecl: name, help, flags, default,
 * callback, category, ...) returns the cvar; its integer value is at +0x30. Flag 1 saves it in
 * Config.wtf. Register from controls_cvars()/effects' register_cvars, which run right after the
 * client's world graphics cvars. */
#ifndef WOTLKHD_CVAR_H
#define WOTLKHD_CVAR_H
#include <windows.h>

typedef BYTE *(__cdecl *cvar_register_t)(const char *, const char *, unsigned, const char *, void *, unsigned,
                                         int, void *, int);
#define CVAR_REGISTER ((cvar_register_t)0x00767FC0)
#define CVAR_INT(cv) (*(int *)((cv) + 0x30))
#define CVAR_SAVED(name, help, def) CVAR_REGISTER(name, help, 1, def, 0, 1, 0, 0, 0)

#endif
