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

Done: Lua functions from the DLL (`client/lua.c`), retail Options window (`addon/WotlkHD`).

- Options window: search box, retail dropdown menu lists, retail's single-column page layout,
  scrollbar art, a retail Key Bindings page.
- Small DLL wins: colorblind filter, cursor locked to the window, FoV and camera sliders, mouseover
  casting.
- Nameplates as units, retail nameplates.
- Unit and player frames, bags, action bars in retail's look.
- Edit Mode, raid frames.
- Retail textures under 3.3.5's own UI paths in an MPQ (buttons, panels), restyling the whole UI.

## Client

See [docs/client-roadmap.md](docs/client-roadmap.md): crash logger, interface signature check, cap
patches (farclip, camera distance, nameplate range), Wow-hd.exe possibly unneeded under Proton.
