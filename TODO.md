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
(`UnitFrames.lua`), combined bags (`Bags.lua`), action bars (`ActionBars.lua`), minimap (`Minimap.lua`), character window (`Character.lua`), Map & Quest Log (`WorldMap.lua`). Retail settings mapped to 3.3.5:
[docs/retail-options.md](docs/retail-options.md).

- Mouseover cast covers action bar spells only, not macros or items.
- The color filter starts with the first world frame (not on the login and character screens).

- Options window: our own retail pages (single-column layout, steppers) in place of the client's
  panels, then search box, dropdown menu lists, scrollbar art, a Key Bindings page; see
  docs/retail-options.md.
- Nameplates: which auras retail shows beside the bar, `NAME_PLATE_UNIT_ADDED`/`REMOVED` and unit
  events for `nameplateN`.
- Character window: retail's model controls and inner border, the Pet, Reputation,
  Skills and Currency tabs in retail's frame.
- Action bars: the shaman's totem bar in our own bar (it can shift in combat), rounded icon corners (pre-masked
  icons in the build). Check the main bar's border corners and gryphon height against retail. Bags: retail's bank window, Edit Mode box; sorting, assignments and
  item markers not yet checked in game.
- Options window: Defaults on the client's Interface pages resets from addon code (taints until
  /reload); the red X and Esc don't save Interface options (only Close does, see Settings.lua).
- Edit Mode: chat, more boxes (pet,
  boss, arena, durability, vehicle seats). Raid frames: pets, power bars, health text, heal
  prediction (no 3.3.5 API), retail's raid manager panel.
- Retail textures under 3.3.5's own UI paths in an MPQ (buttons, panels), restyling the whole UI.
- Map & Quest Log (`WorldMap.lua`): fine-tune against retail in game; check that retail shows no
  numbers on quest markers (several quests in one zone); the maximized map's size and title; the
  filter button's count; menus close when clicking elsewhere.
- Waypoints: map pins and `/way`, with retail's super-tracking arrow.
- Adventure Guide (Encounter Journal): dungeons and raids, bosses, abilities and loot, from retail's
  journal tables mapped onto 3.3.5's instances.
- Cooldown numbers on action buttons; item level in item tooltips.
- Retail's loot window and loot toasts.
- Mount and pet journal over 3.3.5's companion functions.
- Retail's spellbook, talents and auction house.

## Gameplay

Client-only unless noted; the core client stays plain 3.3.5 and works against any server.

- Spell queue window: the next spell can be pressed shortly before the current cast or global
  cooldown ends and goes off as soon as it can (DLL; test against Warden like every hook).
- Soft targeting and an interact key: interact with the nearest thing, a highlight on what would be
  targeted next (DLL).
- `[@cursor]` in macros: ground-targeted spells cast where the mouse is (DLL).
- Maybe: retail's action camera (over-the-shoulder offset, dynamic pitch).

Needing the server, in an optional addon that turns on only when the server says it has the module
(addon message handshake), so the core client never depends on AzerothCore:

- Later: account-wide mounts and collections.
- Maybe: transmog (AzerothCore's mod-transmog).
- Probably not: retail-style flying. Cataclysm reworked the old world for flying; needs examining.

## Client

See [docs/client-roadmap.md](docs/client-roadmap.md): crash logger, interface signature check, cap
patches (farclip, camera distance, nameplate range), Wow-hd.exe possibly unneeded under Proton.
