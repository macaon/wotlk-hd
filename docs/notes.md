# Technical notes

How the pieces work and what was found along the way: addresses in Wow.exe 12340, file format
differences between 3.3.5 and retail, and the per-race character work. The README has the overview;
open work is in [TODO.md](../TODO.md).

## Survey (retail 12.1.0, 2026-10-10)

24262 WotLK displays: 15451 humanoid (character models, separate track), 3584 same, 2888
updated in place (same file, new bounding box), 1692 replaced by a newer file, 523 gone,
65 player bodies, 59 whose display ID was reassigned in retail (keep the old model).
About 500 of 1096 creature model files have a newer version. "Updated in place" overcounts: a
changed bounding box does not mean a new mesh (retail felbat and snake have the same triangles as
3.3.5's); compare skin triangle counts before adding an upgrade.

Display IDs are mostly stable across versions, so the retail row for a WotLK display ID is the
upgrade. A few were reused for something else (WotLK display 4 is a crystal spider, retail's is a
murloc), so each model's most common retail target counts and outliers keep the old model.

## Converter notes

Checked against 3.3.5's own files and Wow.exe 12340:

- The MD20 header and the bone, vertex, sequence, texture, attachment and event structs are unchanged
  since 3.3.5; retail wraps the MD20 in an `MD21` chunk with `SFID` (skins), `TXID` (textures),
  `AFID` (.anim files) beside it. External .anim data is the `AFM2` chunk's payload.
- Sequence blend time: one u32 in 3.3.5, two u16 (in, out) later. Newer sequence/material flags masked.
- Shaders: 3.3.5 resolves `0x8000|n` only for n = 1..3 (`0x836c90`), which are retail's 0..2.
  Its creature skins otherwise use shader 0 with a `texture_unit_lookup` like `(0, -1)` (UV0 + env).
- Cameras: 3.3.5 has `fov` after the type (100 bytes); later versions moved it into a track at the end
  (116 bytes). Values carry over 1:1; retail portrait far clip is 100x.
- Geosets: 3.3.5's `CreatureGeosetData` is one nibble per group (`0x1111` -> 101, 201, 301, 401);
  retail lists the same per display in `CreatureDisplayInfoGeosetData`, and shows only the groups
  a display lists (boar2's 101 needs a texture display 193 lacks). Unlisted groups get variant 15,
  which no model has, so 3.3.5 hides them.
- Retail skin vertex palette indices can be stale (boar2); they are always rebuilt from the model
  vertices' bones.
- Targets under `character/` (naga) are customizable models; they belong to the humanoid track.
- Retail skins index model vertices from a base offset in the header (0x2C, 3.3.5's boneCountMax);
  each LOD has its own range. Only the chosen skin's vertices are kept (gnoll2: 67697 -> 14823).
- Particle emitters: 3.3.5's 476-byte struct plus 16 appended bytes (multi-texture parameters);
  converted by truncating, newer flag bits masked. Their geometry/recursion model names must be
  an empty string (count 1, "\0") as in 3.3.5 files: count 0 / offset 0 reads as "MD20...".
  With emitter flag 0x800000 the gravity keys are packed vectors (int8 x, int8 y, int16 z, scale
  z*0.04238648); 3.3.5 takes a float, the negated z (checked on arcanegolem/manafiend). Ribbons
  are still dropped. Mana wyrm particles only play in its death animation. Head/tail cell tracks
  whose keys are all past rows x cols are wrapped (voidwalker2: cell 1 on a 1x1 texture drew flat
  squares in 3.3.5, or so it seemed: the squares later turned out to come and go with the scene,
  unconverted 3.3.5 effects too, which points at the -opengl renderer; the wrap is kept as harmless).
- Limits: 64 bones per submesh (the 3.3.5 max), 65535 vertices. Bigger submeshes are split in
  triangle order with their own palettes (vertex bones are absolute; skin vertex bones index
  `bone_lookup[combo + i]`; checked on 3.3.5 and retail files).
- Some upgrades are not reachable through display IDs: retail's new `dragonhawk2` is only used by
  new displays, so old ones need a manual old -> new model entry.

## Character models

Retail HD player models (`character/<race>/<sex>/<race><sex>_hd.m2`) keep bones and animations
in a `.skel` file (chunks SKL1, SKS1, SKB1, SKA1, AFID, BFID; no parent skeleton for blood elves)
and hold every customization option in one mesh (bloodelfmale_hd: 253k vertices, 3.3.5 allows
65535), so a conversion keeps only the geosets 3.3.5 can choose.

The character texture is composited by Wow.exe 12340, `CCharacterComponent::Initialize` at
0x4f1a20: a square texture of `1 << level` pixels, level clamped to 6..9 (512 at most). The region
table is built at startup by 0x9c8f30 into 0xb6b928 (x, y, w, h in units of 512) and shifted down
for lower levels into 0xb6b888; the size is at 0xb6b5fc (19 references).

| region | 3.3.5 (512) | retail layout 2 at half scale (1024x512) |
|---|---|---|
| ArmUpper | 0,0,256,128 | 0,0,256,128 |
| ArmLower | 0,128,256,128 | 0,128,256,128 |
| Hand | 0,256,256,64 | 0,256,256,64 |
| FaceUpper | 0,320,256,64 | 512,0,512,512 |
| FaceLower | 0,384,256,128 | 512,0,512,512 |
| TorsoUpper | 256,0,256,128 | 256,0,256,128 |
| TorsoLower | 256,128,256,64 | 256,128,256,64 |
| LegUpper | 256,192,256,128 | 256,192,256,128 |
| LegLower | 256,320,256,128 | 256,320,256,128 |
| Foot | 256,448,256,64 | 256,448,256,64 |

Retail (CharComponentTextureLayouts/Sections) layout 1 is exactly the 3.3.5 one at 1024x1024;
layout 2 (2048x1024) is the HD one; HD skin and face files are 1024x512, i.e. layout 2 at half
scale. So HD models at native texture resolution need a 1024x512 composite with that table. The
table is global: every character model, old or HD, is composited with it.

`patch_exe.py --characters` writes Wow-hdchar.exe with that composite: level fixed at 10, the
region table replaced, and a new section `.hdchar` holding the table and detours for the 13 places
that create, free or mark dirty the composite as (size, size) and for the two DXT compression loops
(which assumed as many block rows as columns). The blitter copies regions 1:1 from a source mip
chosen by width and never resamples, so source textures must match their region size.

Fixed: gargoyle2 (Stonewing Slayer) garbled into screen-wide triangles and crashed the client
(0x8204ae, bone matrix copy) when in view, and boar2's triangles joined the wrong vertices. Both
were files from mixed builds: wago.tools without a build mixes products (tables from the 12.1.5
PTR, boar2.m2 from another export than its skins). fetch.py pins one build; the check that
catches it: each skin vertex's palette bone (skin) must be its model vertex's bone (m2).

Install: `install.py` copies out/patch-N.MPQ to <WoW>/Data/ and out/patch-enUS-N.MPQ to
Data/enUS/; by default only those already installed and the per-race archives (out/ also holds old
experiments, and every patch in Data loads), a new numbered patch by name (`install.py 9`). Models and textures must be in the base patch: Blizzard's Data/patch-3.MPQ outranks
every locale patch for the 3.x model updates it holds (463 of our files, the blood elves among them,
showed the old model until this split); DBCs override from the locale patch.

3.3.5 draws a submesh from its u16 index start alone (it ignores level, the high word retail
adds), so a skin's triangles must start below index 65536. Models past it (gargoyle2,
dragonspawn, crypt fiend, nerubian priest, vrykul female at 69k-113k indices) drew garbage and
crashed; the converter now leaves out undrawn submeshes and takes the most detailed retail LOD that
fits (arakkoa has none). For HD characters the client patches (dinput8.dll, or Wow-hdchar.exe) use
level everywhere it matters: the skin's index buffer rebuild (0x8360a0, the real limit), the draw
paths after 0x8203b0, and SetGeometryVisible (0x82c7c0), which read id and level as one u32 and
left every late geoset visible. So the HD characters keep full detail.

Tauren: retail splits 3.3.5's hair style (horns and hair in one geoset) into Horn Style, Foremane
and Hair, and its facial style into Facial Hair and Hair; chars.py maps them from retail's
ChrCustomizationChoice order (which follows 3.3.5's), a retail horn shared by several styles is
drawn once per style. Retail builds the race's size into the HD mesh; 3.3.5 scales its own mesh
with display 59 (x1.35) and model 60 (x1.25) instead, and character select ignores those, so
chars.py shrinks the HD mesh by them (convert.scale_model) and leaves the DBCs alone.

## Client extension (client/)

`client/dinput8.dll` is our code inside the client: Wow.exe imports DINPUT8.dll, so a dinput8.dll
next to it is loaded first and forwards DirectInput8Create to the system one. At load it applies
the character patches (1024x512 character textures, 32-bit index starts) to Wow-hd.exe in memory,
from `client/patches.h`, which `patch_exe.py --emit-header` generates from the same tables as
Wow-hdchar.exe; each site only if its original bytes are there, all or nothing. Large-address-aware
and FoV stay in Wow-hd.exe (LAA must be in the exe header). Build with `client/build.sh` (Zig's toolchain, unpacked into cache/:
ziglang.org zig-linux-x86_64-0.13.0); copy the DLL next to Wow.exe; under Wine/Proton set
`WINEDLLOVERRIDES=dinput8=n,b`. It writes wotlk-hd.log next to the exe.

It also lets the client load archives by name: the client finds `Data\patch-?.MPQ` and
`Data\<locale>\patch-<locale>-?.MPQ` by wildcard and loads them in descending name order
(case-insensitive: later names win), so the DLL turns both `?` into `*`. `chars.py` writes one
archive per race (`patch-dwarf.MPQ`, ...), which sort above the numbered patches. Never leave other
`patch-*.MPQ` files in Data (backups, side builds): they load too.

MPQ reader (`client/mpq.c`, first step of docs/client-roadmap.md): StormLib (fetched into cache/ by
`build.sh` at a pinned commit) takes over the calls the game's file layer makes into the client's
own Storm. Off by default; `WOTLKHD_MPQ=shadow` repeats every read through StormLib and logs any
difference (which archive, size, bytes, seeks), `WOTLKHD_MPQ=stormlib` serves the game's files from
StormLib. Storm still opens the archives: the interface file checks look files up in its archive
list. Pass the variable through the launcher: `WOTLKHD_MPQ=stormlib ~/Games/wotlk/launch.sh`.

Face shapes (`client/faces.c`): retail gives each face a .bone file, offset matrices for about 30
head bones (ChrCustomizationElement -> ChrCustomizationBoneSet), which reshape the skull to match
the face texture. `chars.py` writes them per race and sex as `Character\wotlk-hd\faces-<race>-<sex>.bin`
(by face variation; tauren offsets follow the shrunk mesh). The DLL notes each character model's
face when its geosets are set up (0x4ed951: component race +0x18, sex +0x1c, face +0x2c, model
+0x38) and, where the animate function multiplies a bone's local matrix by its parent's (0x82fe4f),
applies T(-pivot) x offset x T(pivot) to face bones, so children follow.

Post-processing (`client/effects.cpp`, D3D9 only): SMAA, then AMD's CAS sharpening, on the world but
not the UI. The world frame ends with the client's own full-frame effects (0x8c1010, called at
0x4f9281) before the UI draws; the DLL hooks that call and runs its passes on the back buffer there,
on the client's device (gx device 0xc5df88, IDirect3DDevice9 at +0x397c), restoring the device state
afterwards. The effects are cvars, saved in Config.wtf: `hdSMAA`, `hdSharpen`, `hdSharpness` (0-100),
`hdSunshafts`, `hdSunshaftsStrength` (0-100), `hdAO`, `hdHaze`, registered right after the client's
world graphics cvars (0x78e400, called at 0x4041c2) and read every frame, so changes apply at once.
The WotlkHD addon (`addon/WotlkHD`, installed by `install.py`) puts them on an HD Effects page in
Video Options and raises the View Distance slider to the engine's 1583 (setting `farClipOverride`, as
the old continents otherwise cap at 791). For debugging `WOTLKHD_EFFECTS` overrides the cvars
(`smaa,cas,shafts`, any of those, or `off`). The shaders are
`client/post.hlsl` (SMAA from iryoku/smaa, MIT, fetched into cache/ by `build.sh`), compiled into the
committed `client/shaders.h` by `client/shaders.sh`, which runs Microsoft's d3dcompiler_47.dll
(fetched from the Windows SDK, build time only) under Proton's Wine.

Depth and ambient occlusion (opt-in: `WOTLKHD_EFFECTS=smaa,cas,ao`; `aoview` and `depth` are debug
views; `WOTLKHD_AO=radius,intensity`, default 1.5 yards, 2). D3D9 cannot sample the device's D24S8
depth buffer, so for depth effects the world draws into an INTZ depth texture instead: the DLL hooks
SetDepthStencilSurface and GetDepthStencilSurface in the device's vtable so it stands in for the
device's depth buffer only (render to texture with depth targets of its own keeps those). The client
draws the world into the viewport depth range 0..0.94 and sky and horizon layers into 0.998..1; near
and far clip are 0xadeed4 and 0xcd7748, the field of view the camera constant 0x9e8d88 (vertical =
fov / sqrt(aspect^2 + 1), GxuXformCreateProjection_SG). AO runs at half resolution, so depth reads
snap to depth pixel centres (a half-resolution pixel lies exactly between two; rounding picked
either, in stripes). It is off by default: on small detailed models, characters at a distance, its
blurred darkening costs some sharpness.

Distance haze (opt-in: `WOTLKHD_EFFECTS=smaa,cas,haze`; `WOTLKHD_HAZE=strength,density`, default 0.5,
1.5 per fog end): the world fades towards the fog colour with distance, from close by rather than in
the client's wall at the fog end; the sky is left alone. Colour and distances are CShaderEffect's, as
SetFogParams (0x873210) last set them: colour 0xd43058, s_fogParams 0xd43068 (-fogMul / (end - start),
end / (end - start)), fogMul 0xd4300c. Additive draws set black fog, so black is ignored and changes
ease in over about a second. Off by default: zone fog is often blue-grey, which cools warm zones.

Sunshafts (on by default; `WOTLKHD_SHAFTS=intensity,threshold`, default 0.6, 0.4; `shaftsview` shows
them with a ring where the sun is): a broad glow of the sky's own colour around the sun plus its
brightest sky, sky only (by depth), blurred radially towards the sun at half resolution in two passes,
so whatever stands in front of the sky cuts it into rays; added in linear light. The sun is the sky's
(0xd38e28, set in 0x7eecc0 as the camera position 0xd38b18 plus the sun's direction at a fixed radius),
projected through the world camera ([0xb7436c] +0x7e20: position +0x08, forward row at +0x14, up row
at +0x2c); it fades out behind the camera, below the horizon and off screen.

Portraits (`client/portraits.c`): unit frame portraits render at 256x256 instead of 64x64.
SetPortraitTexture (0x619580) draws the model into a "Portrait1" texture when the device can render
to textures and masks it with a quad, so only the texture (0x619b72) and the portrait depth target
(0x6180e8) carry the size; the read-back fallback without render to texture keeps 64.

Lua functions (`client/lua.c`, API in `client/lua.h`): C functions in the DLL become globals in the
game UI's Lua state, registered right after the game's own script functions (0x5120e0, called at
0x52ab16 on every UI load and /reload). The client rejects C functions outside Wow.exe's code
(0x86b5a0, bounds at 0xd415b8/0xd415bc, filled from .text while 0); the DLL sets them first to the
whole address space. `WotlkHD_Version()` returns the API version for addons to check.

Retail UI (`ui.py`, `addon/WotlkHD`): `ui.py` exports the retail atlases its `ATLASES` lists as DXT5
BLPs into `addon/WotlkHD/Art/` (3.3.5's UI art is paletted or DXT; retail's is often raw BGRA) and
their coordinates into `Atlas.lua`; `Retail.lua` adds `Texture:SetAtlas`, retail's metal frame and
skins for the option controls. `Settings.lua` is retail's Options window (Game and AddOns tabs,
category list, Defaults, Apply, Close) hosting the client's own Interface, Video and Sound panels and
addon panels; the old frames, the game menu and `InterfaceOptionsFrame_OpenToCategory` open it.

NPC weapons (`client/npcitems.c`): NPCs moved onto HD character models (`NPC_LOOKS`) lose the weapons
their old creature models had in the mesh, and the server sends none. `chars.py` `NPC_WEAPONS` picks
retail item displays per 3.3.5 display (retail has no table: its servers send NPC weapons), imports
them as Item.dbc rows from 60000 and writes `Character\wotlk-hd\npc-items.bin`. After the display
setup of an NPC with a look (0x71d010, called at 0x730199), the DLL fills its empty
UNIT_VIRTUAL_ITEM_SLOT_ID fields and calls the unit's virtual item handler (0x725010), which the
client otherwise runs only when the server changes those fields. Client-only on purpose: a stock
client keeps the old model with its own weapons.

The DLL also logs a memory census once a minute: committed memory by kind and the largest free
block, the limit for any big allocation (high-res textures).

## Adding a race (HD character models)

Blood elves, orcs, tauren, undead, trolls, humans, dwarves, night elves, gnomes, draenei and goblins are done; each race is an entry in `chars.py` `RACES` plus, where retail
reorganised it, a geoset function in `RACE_GEOSETS`. Order of work:

1. `charcheck.py options <dir> <sex>`: retail's customization options, each choice's geosets, in
   retail's order (its first choices follow 3.3.5's style order: that order is the mapping).
   `charcheck.py geosets <dir> <sex> <race id>`: 3.3.5 and retail geoset ids, 3.3.5's hair and
   facial style tables (facial columns are 1xx, 3xx, 2xx) and the 3.3.5 display x model scale.
2. Map what moved: same ids need nothing (orc hair, beards); pieces split into new options get a
   geoset function (tauren: horns 24xx and foremane under one 3.3.5 style id, nose rings 16xx for
   3xx; troll: tusks 3xx moved to 40xx; human: female piercings 3xx moved to 35xx; dwarf: female 3xx to earrings 35xx and a nose ring 16xx, ears 702 always drawn; night elf: ears 701 (Thin) as 702, male moustaches 305/306 borrow 304/302; gnome: female earrings 2xx moved to 35xx, male beards 102-108 split into retail beards 101-107 plus a moustache per style (`CharacterFacialHairStyles` 3xx, never x01: helmets force it), male brows none, mesh shrunk by 1.15; draenei: male hair and facial hair ids one higher in retail (3-15 = 2-14, 101-107 = 102-108), female horns 2401-2408 = 101-108, tail 3801 and female tendrils 201 always drawn (body in 3.3.5); orc: tusks 40xx always drawn, piercings as earring 35xx + nose ring 16xx). A geoset map may
   return a tuple (one retail piece drawn for several styles) or 0 (always drawn).
   When ids or order do not settle it, `charcheck.py match <dir> <sex> <3.3.5 ids> [groups]`
   (needs numpy and scipy) ranks retail pieces by shape; beards redesigned in HD match nothing well.
3. Add the race to `RACES`, run `chars.py <race dir>` (that race only; the others keep their out/patch-<race dir>.MPQ; run it again after every `build.py`: its CreatureDisplayInfo.dbc starts from build.py's and overrides it),
   then `charcheck.py built <dir> <sex>`: skin-textured vertices outside 3.3.5's regions draw black
   (tauren throat, undead fingers and bones, draenei tendrils: `THROAT_RACES`, the face lower region), keyframes in missing .anim files or
   starting after 0 crash the client (the converter fixes both; this confirms it).
4. In game: character select size (meshes are shrunk by the 3.3.5 scale, `native_scale`), every
   hair, facial and colour choice, and NPCs on the race's model (they play animations players
   do not: the Lazy Peon's lie-down found the alias bug).

Textures come from retail's materials, not file names: skins, underwear (targets 13, 14) and hair
from Skin Color and Hair Color, faces from Face x Skin Color (the face sheet's target: 5, 4 on draenei); names only for 3.3.5
choices retail lacks. Eyes are retail's Eye Color choice 0; no glow mesh except the death knight's
(1703), and undead's 1702.

Pitfalls seen so far: retail-only texture types (19 eyes, 20 jewelry: fixed files); the skin extra
(type 8, tauren fur) shared per three skin colours in retail; `mpq.Client()`'s default chain leaves
out our own patches (read out/patch-<race dir>.MPQ explicitly, as charcheck does); retail textures past
3.3.5's layout (the face sheet is region 8, face upper; facial hair sheets go there too).

Goblins (`NPC_RACES`) are NPCs only in 3.3.5, with three skins, two hair geosets and no face or
hair textures. chars.py writes their CharSections and CharHairGeosets from retail's choices and gives
every NPC look its retail look by CreatureDisplayInfoExtra id (all 648 exist in retail). Retail's
per-NPC ears, chin, nose, earrings and nose ring move into the facial groups 1xx, 2xx, 3xx, 16xx and
17xx (`GOBLIN_GROUPS`), with one CharacterFacialHairStyles row for each combination used (17 male,
9 female) as the look's facial hair. Helmets that hide facial hair show x01: ear stubs, first chin
and nose.
