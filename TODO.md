# TODO

## Fix

- Lady Vashj doesn't convert: sequence 62 has no `.anim` file.
- NPC looks (`chars.py` `NPC_LOOKS`): belt buckles (retail waist models) have no slot in 3.3.5.
- Helmets are sized for 3.3.5's heads; check fit and hair/ear hiding per race.

## Models and textures

- Retail animations with ids past 3.3.5's 505 (never played now).
- Particle ribbons (dropped by the converter).
- Higher-res armour textures: retail's fit the 1024x512 regions; 2048x1024 for more.
- World doodads and textures through the same pipeline.
- Worgen as a playable race.
- Retail-only customization options (more beards, sideburns, earrings, headdresses) would need new
  style rows in the server's DBCs too.

## Retail UI

Done: Lua functions from the DLL (`client/lua.c`), retail Options window (`addon/WotlkHD`), mouseover
cast, cursor lock and color filter (`client/controls.c`, `client/effects.cpp`, `Options.lua`),
nameplates as units and retail nameplates (`client/nameplates.c`, `Nameplates.lua`), retail raid
frames (`RaidFrames.lua`), Edit Mode (`EditMode.lua`), retail unit frames and cast bars
(`UnitFrames.lua`), combined bags (`Bags.lua`), action bars (`ActionBars.lua`). Retail settings mapped to 3.3.5:
[docs/retail-options.md](docs/retail-options.md).

- Mouseover cast covers action bar spells only, not macros or items.
- The color filter starts with the first world frame (not on the login and character screens).

- Options window: our own retail pages (single-column layout, steppers) in place of the client's
  panels, then search box, dropdown menu lists, scrollbar art, a Key Bindings page; see
  docs/retail-options.md.
- Nameplates: which auras retail shows beside the bar, `NAME_PLATE_UNIT_ADDED`/`REMOVED` and unit
  events for `nameplateN`.
- Action bars: the shaman's totem bar in our own bar (it can shift in combat), retail's
  XP/reputation bar art, rounded icon corners (pre-masked icons in the build). Check the main bar's
  border corners and gryphon height against retail. Bags: retail's bank window, quest and new item highlights, Edit Mode
  box, sorting (no 3.3.5 API: would move items itself).
- Options window: Defaults on the client's Interface pages resets from addon code (taints until
  /reload); the red X and Esc don't save Interface options (only Close does, see Settings.lua).
- Edit Mode: chat, more boxes (pet,
  boss, arena, durability, vehicle seats). Raid frames: pets, power bars, health text, heal
  prediction (no 3.3.5 API), retail's raid manager panel.
- Retail textures under 3.3.5's own UI paths in an MPQ (buttons, panels), restyling the whole UI.

## Client

See [docs/client-roadmap.md](docs/client-roadmap.md): crash logger, interface signature check, cap
patches (farclip, camera distance, nameplate range), Wow-hd.exe possibly unneeded under Proton.
