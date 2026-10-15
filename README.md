# wotlk-hd

A modernised World of Warcraft 3.3.5a (build 12340) client for private use against an unchanged
AzerothCore server. Assets come from the current retail client and are converted to 3.3.5's
formats: creature models, HD player characters and UI art. Nothing is made by hand. A proxy
`dinput8.dll` adds what the engine itself lacks.

It's a personal build: it aims to look and play well, not to stay faithful to 3.3.5.

## Compared to the stock 3.3.5a client

**Models**
- Over a hundred creature models replaced by their retail versions (murlocs, gnolls, spiders,
  dragonhawks, ...), with their retail textures and particles.
- HD player characters for all ten playable races, plus goblins, with retail's skin, face and hair
  textures at 1024x512. Faces get retail's head shapes.
- NPCs that use player races get the HD models too, along with weapons that their old models
  carried in the mesh.

**Graphics** (in-game: Options → System → HD Effects)
- SMAA anti-aliasing and AMD CAS sharpening on the world, not the UI.
- Sunshafts.
- Optional ambient occlusion and distance haze.
- View distance up to the engine's 1583 yards.
- Unit frame portraits at 256x256 instead of 64x64.
- Large-address-aware (4 GB) and a wider field of view.

**Interface**
- Retail's Options window, with Game and AddOns tabs, replaces Interface, Video and Sound Options.
  The client's own option pages are hosted in it with retail art for checkboxes, sliders and
  dropdowns. Addon option pages appear there too.
- Retail nameplates: the name inside the bar, retail's cast bar art, cast bars with spell name and
  icon on every casting enemy (stock 3.3.5 shows the target's only), your debuffs with timers, elite
  and rare icons, retail's scaling by distance, a 60 yard range (41 in 3.3.5), and enemy nameplates
  on by default.
- Retail unit frames (Dragonflight art and layout): player, target and focus with elite and rare
  dragons, target of target, pet, party and party pets, and retail's cast bars.
- Retail action bars: retail's button art, the main bar centered with gryphons (wyverns for the
  Horde) in our own secure bars (no jumping in combat), bars 6 to 8, the micro menu and round bag
  buttons at the bottom right, and retail's pixel-sized UI with Use UI Scale off.
- Retail's combined bags: one window with search, retail item slots and quality borders; the bank
  opens your bags, as on retail.
- Retail raid frames for raids (and parties, with Use Raid-Style Party Frames): green or class
  coloured health, roles, target and aggro highlights, buffs, debuffs, dispellable types and range
  fade.
- Retail's Edit Mode (game menu): move and resize the unit frames, party and raid frames, cast bar,
  minimap, buffs and quest tracker, with a grid and snapping; positions are kept account-wide.
- Nameplates as units: `nameplateN` tokens work in every `Unit*` function, as on retail.
- A Lua API from the DLL for addons (`WotlkHD_Version()`, `WotlkHD_NamePlateUnit(frame)`,
  `WotlkHD_UnitDistance(unit)`).
- Retail's Mouseover Cast (with an optional modifier key), Lock Cursor to Window, and the
  Accessibility color filter (protanopia, deuteranopia, tritanopia) over the whole screen.

**Client**
- Extra patch archives are loaded by name (`patch-dwarf.MPQ`, ...), not just `patch-N.MPQ`.
- Optional StormLib-based MPQ reader (`WOTLKHD_MPQ=stormlib`).

Everything is client-side. A stock client connects to the same server and sees the old models.

## How it fits together

| Piece | What it is |
|---|---|
| `out/patch-4.MPQ`, `out/patch-enUS-4.MPQ` | Creature models and textures, plus their DBCs (`build.py`) |
| `out/patch-<race>.MPQ`, `out/patch-6.MPQ`, `out/patch-enUS-6.MPQ` | HD characters, one archive per race plus the shared DBCs (`chars.py`) |
| `client/dinput8.dll` | Code inside the client: patches and hooks, effects, Lua functions (`client/build.sh`) |
| `Wow-hd.exe` | Wow.exe with the large-address-aware flag and a wider FoV (`patch_exe.py`) |
| `addon/WotlkHD` | The Options window, retail art (`ui.py`) and the HD Effects page |

## Requirements

- Python 3 with Pillow. `charcheck.py match` also needs numpy and scipy.
- StormLib, built at `~/Git/ref/StormLib/build`, for writing MPQs.
- Zig 0.13.0 for the DLL, unpacked into `cache/` (ziglang.org `zig-linux-x86_64-0.13.0`).
- A 3.3.5a (12340) client. On Linux, run it with Proton or Wine.
- Retail data from wago.tools. Alternatively, use a local retail install of the pinned build
  (`WOW_RETAIL`), read with CascLib built in `cache/CascLib` (tag 3.0, built as a shared library).

Cache setup:

    mkdir -p cache && cd cache
    for t in CreatureDisplayInfo CreatureModelData CreatureDisplayInfoGeosetData; do curl -sfo $t.csv https://wago.tools/db2/$t/csv; done
    curl -sfLo listfile.csv https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv

## Build and install

    python3 build.py     # creature models -> out/patch-4.MPQ, out/patch-enUS-4.MPQ
    python3 chars.py     # HD characters (run again after every build.py)
    python3 ui.py        # retail UI art into addon/WotlkHD
    client/build.sh      # client/dinput8.dll
    python3 patch_exe.py # Wow-hd.exe next to Wow.exe
    python3 install.py   # patches into Data/ and Data/enUS/, the addon into Interface/AddOns/

Copy `client/dinput8.dll` next to `Wow.exe` and start `Wow-hd.exe`. Under Wine or Proton, set
`WINEDLLOVERRIDES=dinput8=n,b`. The DLL logs to `wotlk-hd.log` next to the exe.

Leave no other `patch-*.MPQ` files in `Data/` (backups, side builds): every one of them loads.

## Tools

- `survey.py`: compares every WotLK creature display with retail.
- `plan.py`: picks model upgrades into `upgrades.json`.
- `pick.py`: writes `out/pick.html`, for choosing skins and extra upgrades. The choices are saved to
  `picks.json`.
- `compare.py`: writes `out/compare.html`, with old and converted models side by side.
- `experiment.py`: A/B variants of a model under display ids 90001 and up.
- `revert.py`: puts original models back (`patch-5`) to find a misbehaving upgrade.
- `charcheck.py`: per-race checks of options, geosets and built models (see
  [docs/notes.md](docs/notes.md#adding-a-race-hd-character-models)).
- `convert.py`, `m2.py`, `blp.py`, `mpq.py`, `fetch.py`: the converter, the model summary, BLP
  encoding, MPQ access and retail file fetching (cached in `cache/files/`), which the tools above
  use.

## More

- [docs/notes.md](docs/notes.md): technical notes on the converter, character models, the client
  hooks (with Wow.exe addresses) and adding a race.
- [docs/client-roadmap.md](docs/client-roadmap.md): review of the DLL and what else the client
  could do.
- [TODO.md](TODO.md): open bugs and planned work.

Warden is on in AzerothCore. New client hooks may need checking against `warden_checks`.
