# wotlk-hd

Make the 3.3.5a (12340) client look as good as possible without making assets ourselves: newer
creature models and textures from the retail client, converted to 3.3.5 formats and shipped as
one client patch, `Data/patch-4.MPQ`. AzerothCore stays unchanged. Private use only.

## Tools

- `patch_exe.py [fov]`: writes `Wow-hd.exe` next to `Wow.exe` with the large-address-aware flag
  and a wider FoV (computed from `gxResolution` if no value is given). Start it with
  `WOW_EXE=Wow-hd.exe ~/Git/azcore/clientstart.sh`.
- `survey.py [-v]`: compares every WotLK creature display with retail (wago.tools CSV and the
  wowdev community listfile in `cache/`).
- `mpq.py`: reads the client's MPQ chain and writes MPQs via StormLib (`~/Git/ref/StormLib/build`).
- `fetch.py <fdid|path>`: retail files from wago.tools by FileDataID, cached in `cache/files/`.
- `compare.py [name...]`: writes `out/compare.html`, old and converted models side by side.
- `m2.py <file>`: model summary. `convert.py`: retail model -> 3.3.5. `build.py [name...]`:
  converts the `UPGRADES` list into `out/patch-enUS-4.MPQ`; copy that to `<WoW>/Data/enUS/`.

Cache setup:

    mkdir -p cache && cd cache
    for t in CreatureDisplayInfo CreatureModelData CreatureDisplayInfoGeosetData; do curl -sfo $t.csv https://wago.tools/db2/$t/csv; done
    curl -sfLo listfile.csv https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv

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
  retail lists the same per display in `CreatureDisplayInfoGeosetData`.
- Limits: 64 bones per submesh (the 3.3.5 max), 65535 vertices. Bigger submeshes are split in
  triangle order with their own palettes (vertex bones are absolute; skin vertex bones index
  `bone_lookup[combo + i]`; checked on 3.3.5 and retail files). `gnoll2` (67697 vertices) needs a
  lower LOD.
- Some upgrades are not reachable through display IDs: retail's new `dragonhawk2` is only used by
  new displays, so old ones need a manual old -> new model entry.

## Plan

0. **Setup** (done): large-address-aware, FoV, survey.
   **First models** (built, untested in game): Ghostlands' murloc, spiders, rat, frog, zombie,
   skeleton, larva, dragonhawk (-> dragonhawk2, colours matched by eye).
1. **Data** (done): retail tables as CSV and files by FileDataID from wago.tools.
2. **Converter**: unpack chunked `MD21` into an `MD20` v264 layout and resolve FileDataIDs to names;
   remap shaders, blend modes, particles and animation IDs that 3.3.5 lacks; pick a lighter LOD
   skin when the model is too heavy, re-split submeshes over the bone limit, drop geosets retail
   turns off per display. Self-check by reading the result back.
3. **Packaging**: converted models over the old paths, textures under new names with
   `CreatureDisplayInfo.dbc` `TextureVariation` pointing at them, built into `patch-4.MPQ` with
   StormLib. Test in game with `.morph <display>`. Order: 5 iconic mobs, then families, then all
   that convert cleanly; failures keep the old model.
4. **Later**: world doodads and textures through the same pipeline; HD character models for
   humanoid NPCs; ReShade (works with `-opengl`).

Risks: newer models can look flat with 3.3.5 shaders; memory in a 32-bit client.
