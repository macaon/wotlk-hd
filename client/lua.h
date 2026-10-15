/* The client's Lua 5.1 API (12340), for functions our addons call (lua.c registers them). Stack
 * values are 16 bytes here: the usual TValue plus a taint word. */
#ifndef WOTLKHD_LUA_H
#define WOTLKHD_LUA_H
#ifdef __cplusplus
extern "C" {
#endif

typedef struct lua_State lua_State;
typedef int(__cdecl *lua_CFunction)(lua_State *);

#define lua_gettop ((int(__cdecl *)(lua_State *))0x0084DBD0)
#define lua_settop ((void(__cdecl *)(lua_State *, int))0x0084DBF0)
#define lua_type ((int(__cdecl *)(lua_State *, int))0x0084DEB0)
#define lua_tonumber ((double(__cdecl *)(lua_State *, int))0x0084E030)
#define lua_toboolean ((int(__cdecl *)(lua_State *, int))0x0084E0B0)
#define lua_tolstring ((const char *(__cdecl *)(lua_State *, int, unsigned *))0x0084E0E0)
#define lua_pushnil ((void(__cdecl *)(lua_State *))0x0084E280)
#define lua_pushnumber ((void(__cdecl *)(lua_State *, double))0x0084E2A0)
#define lua_pushstring ((void(__cdecl *)(lua_State *, const char *))0x0084E350)
#define lua_pushboolean ((void(__cdecl *)(lua_State *, int))0x0084E4D0)
#define lua_rawgeti ((void(__cdecl *)(lua_State *, int, int))0x0084E670)
#define lua_touserdata ((void *(__cdecl *)(lua_State *, int))0x0084E1C0)
#define lua_tostring(L, i) lua_tolstring(L, i, 0)
#define LUA_TSTRING 4
#define LUA_TTABLE 5

/* A global Lua function, (re)registered on every UI load; call from a *_hooks() at startup. */
void lua_function(const char *name, lua_CFunction fn);

#ifdef __cplusplus
}
#endif
#endif
