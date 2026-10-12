# Client extension review and roadmap (2026-10-12)

What the dinput8.dll hook (`client/`) does well, what to fix, and what else is feasible in the
3.3.5a (12340) client. Feasibility notes are estimates; items marked "check" need disassembly.

## Review of the dinput8 hook

Proxying dinput8 is the right way in: Wow.exe imports it, so it loads early without touching the
exe. The PE timestamp gate plus the per-site byte comparison (all or nothing) is the right level of
care, and generating the patches for two cave addresses to find the relocations is neat.

1. **Timing.** `DllMain` runs before Wow's static initializers, which is why patching
   `REGION_INIT` there works. Anything that needs a live client (D3D/GL device, Lua, the world)
   cannot be set up in `DllMain` (loader lock). Set those up on the first `DirectInput8Create`
   call (the window exists by then), or later with a jmp detour on a known init function using the
   cave machinery already in `patch_exe.py`.
2. **Warden is on** (`Warden.Enabled = 1` in AzerothCore). The current sites pass because
   `warden_checks` does not cover them. New hooks, especially ones resembling known hacks (Lua
   unlock, farclip, camera), may get kicked: turn Warden off or check new sites against
   `warden_checks`.
3. **`client/dinput8.c`:** the `VirtualProtect` return value is not checked; a failure would
   crash in `DllMain` without a log line.
4. **`patch_exe.py`:** `SHIFT_SITE, SHIFT_BYTES` is defined twice; the second is dead.
5. **Maybe drop Wow-hd.exe.** Proton generally enables Wine's large-address-aware override for
   32-bit games (`WINE_LARGE_ADDRESS_AWARE`); check GE-Proton11-7. If it holds, the DLL can write the
   FoV at runtime from `gxResolution` and we ship only the stock Wow.exe, dinput8.dll and the MPQs.

**Disassembly target:** retail is 64-bit with a different, multi-threaded engine, so it only helps
with file formats. **Cata 4.3.4 (15595)** is the better reference: still 32-bit, close to 3.3.5's
engine, already has Worgen and Goblin, larger race tables and newer terrain. awesome_wotlk (an
existing 3.3.5 DLL extending Lua, camera and nameplates) is a good source of known offsets.

## Feasibility

| Idea | Verdict | How |
|---|---|---|
| Model upgrades | In progress | — |
| Higher-res model textures | Easy | Larger power-of-two BLPs work (DXT1/3/5; no BC7 in D3D9-era formats). Composite skins are 1024x512 already; armour to 2048x1024 is in the README's "To fix later". The limit is memory in a 4 GB 32-bit process: budget textures. |
| Higher-res world textures (WMO, doodads, terrain tiles) | Easy to medium | Data only: replace files by path in an MPQ. Terrain tilesets can go above 256² (keep the `_s` specular variants). Retail-only height blending (`_h` textures) needs shader changes: skip. Visual-only changes do not affect the server. |
| Higher-poly trees | Medium | Trees are M2 doodads: the existing converter pipeline. The 3.3.5 renderer is bound by draw calls more than triangles. Any change to collision geometry (doodads, WMOs) means re-extracting AzerothCore's vmaps/mmaps from the patched client, or line of sight and pathing will not match. |
| Structures (retail WMOs) | Hard | Needs a retail-to-3.3.5 WMO converter, plus the vmaps caveat. Azeroth's terrain changed in Cataclysm, so only single buildings carry over, not zones; Northrend and Outland changed least. |
| Fog, sky, time-of-day lighting | Easy | Data in the `Light*.dbc` files (fog distances, colours, sky); client only. Pair with a farclip cap patch (in-game maximum 777; more costs memory). |
| Sunshafts, SSAO, DOF | ReShade, medium | Rewriting the renderer is out of scope. ReShade works with `-opengl` (already used) and the depth buffer is readable, but effects also land on the UI. Fix: make the DLL a ReShade addon and call `render_effects()` where the world finishes drawing and the UI starts. Real dynamic shadows are not realistic. |
| New races (Worgen) | Possible, big project | Client: rows in `ChrRaces`, `CharBaseInfo`, `CharSections`, hair/facial tables, `HelmetGeosetVisData`, sounds, name generation; GlueXML for character creation; helmet variants per race (retail has them). Check for hard-coded race-count arrays in 12340 against 4.3.4 (Worgen's id 22 is the risk). Server: `playercreateinfo`, race masks, starting zone, racials, language, factions. Two Forms needs an aura-based model swap. Do Goblin first: race id 9 already exists in 3.3.5's `ChrRaces`. |
| More character slots | Medium | 10 per realm is the client's cap (`CharactersPerRealm = 10`). Check whether 12340's character list array has a fixed size, add paging or scrolling to `CharacterSelect.lua`, and patch the interface signature check so modified GlueXML loads. |

## Memory: working within 4 GB

The client usually fails on address-space fragmentation, not total use: no contiguous block for a
large texture or buffer even with plenty free overall.

1. **Measure first.** A memory census in dinput8.dll (a `VirtualQuery` walk on a timer, ~20 lines)
   logging committed/reserved memory per module, the client heap and the largest free block to
   `wotlk-hd.log`. It shows whether the memory is the client's own (models, textures, the MPQ file
   cache) or the graphics driver's, and decides which fix below applies.
2. **Move the driver's memory out of the process.** Under classic Wine the OpenGL/Vulkan driver
   lives in the same 32-bit address space and competes with the game for it. Wine's newer WoW64
   mode runs 32-bit games in a 64-bit process with a 64-bit driver, so the driver's own allocations
   sit above 4 GB. Check whether GE-Proton11-7 enables it by default.
3. **DXVK's `d3d9.textureMemory`.** It keeps the system-memory copies of textures out of the 32-bit
   address space except while in use. We use `-opengl` because DXVK slowed down over long sessions;
   if that slowdown is fixable, this setting plus Vulkan might beat the OpenGL path.
4. **Trim what the client keeps resident** (check, needs disassembly): whether it keeps decoded BLPs
   after uploading them, how large its MPQ/file cache is, when it unloads models. Byte patches or
   hooks like the existing ones.
5. **Budget textures by role.** Full resolution on characters and close-up props, smaller on
   distant world textures. The mipmaps are already in the files: a build setting, not new art.

A 64-bit client recompiled from the decompile is not realistic: M2 and other loaders read files as
one blob and rewrite 32-bit offsets into pointers in place, pointer-size assumptions are everywhere,
and matching the default client's behaviour is person-years of work. For a long-term 64-bit client,
Whoa (github.com/whoahq/whoa, a clean-room 12340 reimplementation; check its status) is the
realistic path.

## Other improvements

- **Disable the interface signature check:** one patch, unlocks GlueXML/FrameXML modding
  (character select, login screen, extra slots, the race UI).
- **Crash logger in the DLL:** a vectored exception handler writing the exception address, a short
  stack and the last M2/BLP path opened to `wotlk-hd.log` (would have pinned down gargoyle2 and
  Lady Vashj).
- **Raise client caps:** farclip, maximum camera distance, nameplate range (~41 yards), sound
  channel count.
- **New Lua functions** registered from the DLL for addons (the awesome_wotlk approach).
- **Anti-aliasing for alpha-tested foliage:** in OpenGL mode a driver setting or a ReShade
  SMAA/FXAA pass; real alpha-to-coverage needs a render hook.

## Suggested order

1. Signature-check patch, crash logger, cap patches: small, and they unlock or de-risk later work.
2. ReShade addon running effects before the UI.
3. Doodad and texture packs through the existing pipeline.
4. Goblin as a trial run, then Worgen.
