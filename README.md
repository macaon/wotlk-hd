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
  buttons at the bottom right, retail's experience and reputation bars (rested fill and pip, colours
  by standing), and retail's pixel-sized UI with Use UI Scale off.
- Retail's combined bags: one window with search, retail item slots and quality borders, Clean Up
  Bags (stacking and sorting), bag assignments and ignore, junk, quest and new item markers; the bank
  opens your bags, as on retail.
- Retail's character window: the larger frame with retail's slot columns, model on the race's
  backdrop, the stats pane (item level, attributes, enhancements by role) and sidebar tabs; retail's
  tabs under it.
- Retail's minimap: the larger map in retail's frame, the zone bar with clock and calendar, tracking
  and mail beside it, zoom buttons on hover and mouse wheel zoom, player coordinates under it.
- Retail raid frames for raids (and parties, with Use Raid-Style Party Frames): green or class
  coloured health, roles, target and aggro highlights, buffs, debuffs, dispellable types and range
  fade.
- Retail's Edit Mode (game menu): move and resize the unit frames, party and raid frames, cast bar,
  minimap, buffs, quest tracker and action bars, with a grid and snapping, retail's Modern and
  Classic preset layouts and your own; positions are kept account-wide.
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
| `Wow-hd.exe` | Your own Wow.exe, patched locally with the large-address-aware flag and a wider FoV (`patch_exe.py`); never distributed |
| `addon/WotlkHD` | The Options window, retail art (`ui.py`) and the HD Effects page |

## Requirements

Built and tested on Linux only (Fedora), with the client running under Proton (GE-Proton). The build
scripts are Linux shell scripts and shared libraries. What they produce (MPQs, `dinput8.dll`, the
addon, `Wow-hd.exe`) are Windows files and should work on Windows too, but nobody has tried.

Nothing of Blizzard's is in this repository or shipped with it: you need your own client, and every
script reads or patches that copy.

- **A stock 3.3.5a (12340) client.** The scripts look for it in `~/Games/wotlk`; set `WOW_DIR` to use
  another folder. `patch_exe.py` checks that `Wow.exe` is the 12340 build.
- **A 3.3.5a server.** Developed against AzerothCore, with Warden on.
- **Python 3 with Pillow.** `charcheck.py match` also needs numpy and scipy.
- **git, curl, cmake and a C/C++ compiler**, to build StormLib and CascLib below.
- **StormLib** as a shared library, for reading and writing MPQs. The scripts look for
  `~/Git/ref/StormLib/build/libstorm.so`; set `STORMLIB` to use another path.
- **Zig 0.13.0**, for the DLL: `client/build.sh` fetches and compiles its own StormLib and SMAA.
- **Retail data.** Tables come from wago.tools for the build pinned in `fetch.py` (`BUILD`, or
  `WOW_BUILD`). Files come from a local retail install of that same build when there is one
  (`WOW_RETAIL`, read with CascLib), otherwise from wago.tools, which is much slower. A retail install
  of any other build is ignored.

Setup, once:

    git clone https://github.com/ladislav-zezula/StormLib.git ~/Git/ref/StormLib
    cmake -S ~/Git/ref/StormLib -B ~/Git/ref/StormLib/build -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build ~/Git/ref/StormLib/build -j

    mkdir -p cache && cd cache
    curl -sfLo listfile.csv https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv
    curl -sfL https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar xJ
    # only with a local retail install of the pinned build:
    git clone -b 3.0 https://github.com/ladislav-zezula/CascLib.git
    cmake -S CascLib -B CascLib/build -DCASC_BUILD_SHARED_LIB=ON -DCASC_BUILD_STATIC_LIB=OFF -DCMAKE_BUILD_TYPE=Release
    cmake --build CascLib/build -j

## Build and install

    python3 build.py     # creature models -> out/patch-4.MPQ, out/patch-enUS-4.MPQ
    python3 chars.py     # HD characters (run again after every build.py)
    python3 ui.py        # retail UI art into addon/WotlkHD
    client/build.sh      # client/dinput8.dll
    python3 patch_exe.py # Wow-hd.exe, patched from your own Wow.exe, next to it
    python3 install.py   # patches into Data/ and Data/enUS/, the addon into Interface/AddOns/

The first `build.py` and `chars.py` runs fetch a lot of retail files; they are cached in `cache/`.

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
  encoding, MPQ access and retail file fetching (cached in `cache/<build>/`), which the tools above
  use.

## More

- [docs/notes.md](docs/notes.md): technical notes on the converter, character models, the client
  hooks (with Wow.exe addresses) and adding a race.
- [docs/client-roadmap.md](docs/client-roadmap.md): review of the DLL and what else the client
  could do.
- [TODO.md](TODO.md): open bugs and planned work.

Warden is on in AzerothCore. New client hooks may need checking against `warden_checks`.
