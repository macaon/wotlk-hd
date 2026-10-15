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
frames (`RaidFrames.lua`), Edit Mode (`EditMode.lua`).

- Mouseover cast covers action bar spells only, not macros or items.
- The color filter starts with the first world frame (not on the login and character screens).

- Options window: search box, retail dropdown menu lists, retail's single-column page layout,
  scrollbar art, a retail Key Bindings page.
- Nameplates: `NAME_PLATE_UNIT_ADDED`/`REMOVED` and unit events for `nameplateN`, a look checked
  against retail.
- Unit and player frames, bags, action bars in retail's look.
- Edit Mode: action bars, named layouts (retail's presets, reset all), chat; raid frames: pets, heal prediction (no 3.3.5
  API), retail's raid manager panel.
- Retail textures under 3.3.5's own UI paths in an MPQ (buttons, panels), restyling the whole UI.

## Client

See [docs/client-roadmap.md](docs/client-roadmap.md): crash logger, interface signature check, cap
patches (farclip, camera distance, nameplate range), Wow-hd.exe possibly unneeded under Proton.
