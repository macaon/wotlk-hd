"""HD player character models: retail's customizable models for 3.3.5, with Wow-hdchar.exe.

usage: chars.py    writes out/patch-6.MPQ and out/patch-enUS-6.MPQ (install.py; needs Wow-hdchar.exe)

Wow-hdchar.exe composites characters as 1024x512 in retail's HD layout (patch_exe.py), so the HD
models' UVs and retail's HD skin, face and underwear textures fit unchanged. The models come in
through convert.py (their skeletons are .skel files); then:

- geosets: 3.3.5 shows hair (0xx), facial hair (1xx), ears (7xx) and armour (4xx-18xx) itself.
  Retail's new groups are set by its client: feet (20xx) and hands (23xx) show without boots and
  gloves, so they join 501 and 401; torso (2201), face, eyes and brows (3202, 3301, 3401) always
  show, so they join the base 0. Other groups (eyesight, blindfolds, tattoos...) are left out.
  Hair styles and facial hair keep classic numbering in retail, so CharHairGeosets and
  CharacterFacialHairStyles stay as they are.
- textures: types 3.3.5 lacks become ones it has: guild emblem layers (15-18, cloak 1507) the
  cape, the eye texture (19) a fixed file, the extra skin layer (9) the body.
- CharSections.dbc: skin, face, hair and underwear textures point at retail's HD files, those the
  compositor reads re-encoded as paletted BLP2 (blp.py; it draws retail's DXT green). The HD
  face is one image covering both face regions, so it fills both face slots; facial hair and scalp
  textures (classic layout) are left out.
"""
import collections
import os
import struct

import blp
import build
import convert
import fetch
from mpq import Client

# race id, retail folder/prefix, 3.3.5 path prefix, HD model per sex
RACES = [
    (10, "bloodelf", "BloodElf", {0: "character/bloodelf/male/bloodelfmale_hd.m2",
                                  1: "character/bloodelf/female/bloodelffemale_hd.m2"}),
    (6, "tauren", "Tauren", {0: "character/tauren/male/taurenmale_hd.m2",
                             1: "character/tauren/female/taurenfemale_hd.m2"}),
]
SEXES = {0: ("male", "Male"), 1: ("female", "Female")}
JOIN = {2001: 501, 2301: 401, 2201: 0, 3202: 0, 3301: 0, 3401: 0,  # 3202 is the face (3201 a small cap)
        1801: 0}  # bare waist under belts; 3.3.5's own model has none, its waist is in the body
# Eye glow: 3.3.5 shows 1702 on blood elves; retail's 1702-1705 are large flame flares (228 vertices,
# alternative eye styles), its plain in-eye glow is 1701 (60). So retail 1701 stands in for 1702.
RENAME = {10: {1701: 1702, 1702: None, 1703: None, 1704: None, 1705: None}}
KEEP_GROUPS = {0, 1, 4, 5, 7, 8, 9, 10, 11, 12, 13, 15, 17, 18}
TEXTURE_TYPES = {15: 2, 16: 2, 17: 2, 18: 2, 9: 1}
EYE_TYPE, JEWELRY_TYPE = 19, 20
# CharSections columns: ID, race, sex, section, texture 1..3, flags, variation, color
CS_RACE, CS_SEX, CS_SECTION, CS_TEX, CS_VARIATION, CS_COLOR = 1, 2, 3, 4, 8, 9
SKIN, FACE, FACIAL_HAIR, HAIR, UNDERWEAR = range(5)
CHR_DISPLAY = 4  # ChrRaces: male display, then female
CMD_SCALE = 4    # CreatureModelData: ModelScale


def tauren_geosets(sid, allowed):
    """Retail splits 3.3.5's tauren hair style (horns and hair in one geoset, style v = geoset v + 2)
    into Horn Style (choice v = 2401 + v), Foremane (1-4) and Hair (2xx), and its facial style v
    (1xx, 2xx and 3xx of v + 1) into Facial Hair (10v) and Hair (20v); ChrCustomizationChoice order
    follows 3.3.5's. Every horn style gets retail's default foremane (1, "Short"); 3xx has no
    retail counterpart."""
    if sid == 1:
        return tuple(sorted(k for k in allowed if 2 <= k < 100))
    if 1 < sid < 100:
        return None
    if 2400 < sid < 2500:
        return sid - 2399 if sid - 2399 in allowed else None
    if 100 < sid < 300:
        return sid + 1 if sid + 1 in allowed else None
    return NotImplemented


RACE_GEOSETS = {6: tauren_geosets}
# Horn Color choices (ChrCustomizationElement -> Material -> TextureFileData), by 3.3.5 hair colour
HORN_TEXTURES = {0: ["01", "02", "03", "01", "07", "07", "07"], 1: ["01", "02", "03", "04", "10", "10", "10", "10"]}


def geoset_map(old_skin, race):
    """geoset_map for convert: retail ids joined (JOIN) or kept when the 3.3.5 model has them too
    (its skin lists exactly what 3.3.5 can switch on: its hair styles, facial hair, armour
    variants), the rest left out. Retail's extra hair styles and armour variants would not fit
    3.3.5's 65535 indices anyway."""
    allowed = set(convert.geoset_ids(old_skin))

    rename = RENAME.get(race, {})
    special = RACE_GEOSETS.get(race)

    def remap(sid):
        if special:
            new = special(sid, allowed)
            if new is not NotImplemented:
                return new
        if sid in rename:
            return rename[sid] if rename[sid] in allowed else None
        sid = JOIN.get(sid, sid)
        return sid if sid in allowed and sid // 100 in KEEP_GROUPS else None
    return remap


def textures(m2, eye_path, jewelry_path=None):
    """Texture slots of types 3.3.5 lacks retyped; the eye slot becomes the fixed file eye_path and
    the jewelry slot (type 20, tauren hair accessories) the model's one jewelry colour file."""
    b = convert.Blob(m2)
    n, off = struct.unpack_from("<II", b.d, 0x50)
    for i in range(n):
        t = off + i * 16
        ttype, = struct.unpack_from("<I", b.d, t)
        fixed = eye_path if ttype == EYE_TYPE else jewelry_path if ttype == JEWELRY_TYPE else None
        if fixed:
            name = fixed.encode() + b"\0"
            struct.pack_into("<III", b.d, t, 0, 0, len(name))
            struct.pack_into("<I", b.d, t + 12, b.add(name))
        elif ttype in TEXTURE_TYPES:
            struct.pack_into("<I", b.d, t, TEXTURE_TYPES[ttype])
    return bytes(b.d)


def single_layer_eyes(m2, skin, eye_path):
    """Eye batches draw the eye texture alone: retail adds a reflection layer, and two layers through
    3.3.5's default shader multiply the eye into near-black orbs."""
    n, off = struct.unpack_from("<II", m2, 0x50)
    names = []
    for i in range(n):
        _, _, length, name_off = struct.unpack_from("<4I", m2, off + i * 16)
        names.append(m2[name_off:name_off + length - 1].decode("latin-1") if length else "")
    nl, ol = struct.unpack_from("<II", m2, 0x80)
    lookup = struct.unpack_from(f"<{nl}H", m2, ol)
    s = bytearray(skin)
    nt, ot = struct.unpack_from("<II", s, 36)
    for i in range(nt):
        count, combo = struct.unpack_from("<HH", s, ot + i * 24 + 14)
        if count > 1 and names[lookup[combo]] == eye_path:
            struct.pack_into("<H", s, ot + i * 24 + 14, 1)
    return bytes(s)


def model(race, hd_path, old_path, files, report, dropped):
    fid = fetch.fdid(hd_path)
    fetch.prefetch_models([fid])

    def texture_name(f):
        path = build.mpq_path(fetch.name(f))
        files[path] = fetch.get(f)
        return path
    old_skin = Client().read(old_path[:-3] + "00.skin")
    # Full detail: Wow-hdchar.exe draws index starts past 65535 (the submesh's level as the high
    # word, patch_exe.py), so the skin keeps every 3.3.5 hair style. (convert_model_fitting with
    # split= and fallback_body= fits under 65535 for an unpatched client, at the cost of styles.)
    m2, skins, anims, warnings = convert.convert_model(
        fetch.get(fid), old_path.rsplit("\\", 1)[1][:-3], texture_name, fetch.get,
        geoset_map=geoset_map(old_skin, race), index_limit=None)
    race_dir = hd_path.split("/")[1]
    eyes = f"character/{race_dir}/eyes00_00"
    eye_fid = next((f for n, f in fetch._listfile()[1].items() if n.startswith(eyes) and n.endswith(".blp")), None)
    if not eye_fid:
        raise convert.ConvertError(f"no eye texture {eyes}*")
    eye_path = texture_name(eye_fid)
    jewelry = hd_path[:-3] + "_jewelry_color"
    jewelry_fid = next((f for n, f in fetch._listfile()[1].items() if n.startswith(jewelry) and n.endswith(".blp")), None)
    m2 = textures(m2, eye_path, jewelry_fid and texture_name(jewelry_fid))
    skins = [single_layer_eyes(m2, s, eye_path) for s in skins]
    convert.check(m2, skins, allow_level=True)
    files[old_path] = m2
    for i, s in enumerate(skins):
        files[f"{old_path[:-3]}{i:02d}.skin"] = s
    for (aid, sub), data in anims.items():
        files[f"{old_path[:-3]}{aid:04d}-{sub:02d}.anim"] = data
    report.append(f"{old_path} <- {hd_path}" + "".join(f"\n  {w}" for w in warnings))


def char_sections(cs, race, race_dir, sex, files, report):
    """Point a race and sex's CharSections rows at retail's HD textures (by color and variation)."""
    lower, _ = SEXES[sex]
    prefix = f"character/{race_dir}/{lower}/{race_dir}{lower}"

    def hd(name, composited=True):
        """Path of retail texture `name` in the patch; textures the compositor reads re-encoded."""
        fid = fetch.fdid(name)
        if not fid:
            return None
        path = build.mpq_path(name)
        if path not in files:
            files[path] = blp.reencode(fetch.get(fid)) if composited else fetch.get(fid)
        return path
    original = build.Dbc(Client().read("DBFilesClient\\CharSections.dbc"))
    old_rows = {r[0]: r for r in original.rows}

    def hd_of(name, composited=True):
        """retail's HD file for a 3.3.5 texture name (CharSections colour numbers do not always
        match the file numbers: female face colour 16 is file _10, so names are mapped)."""
        base = name.lower().replace("\\", "/").replace("facelower", "faceupper")
        return hd(base[:-4] + "_hd.blp", composited) if base.endswith(".blp") else None
    changed = collections.Counter()
    for r in cs.rows:
        if r[CS_RACE] != race or r[CS_SEX] != sex:
            continue
        names = [original.string(t) if t else "" for t in old_rows[r[0]][CS_TEX:CS_TEX + 3]]
        if r[CS_SECTION] == SKIN:  # the extra (tauren fur) is drawn directly, not composited
            want = [hd_of(names[0]), hd_of(names[1], composited=False) if names[1] else None, None]
        elif r[CS_SECTION] == FACE:
            face = hd_of(names[1] or names[0])
            want = [face, face, None]
        elif r[CS_SECTION] == FACIAL_HAIR:  # HD facial hair is one full-face texture (tauren), or geometry
            want = [hd_of(names[0]) or "", "", ""]
        elif r[CS_SECTION] == HAIR and race_dir == "tauren":  # the "hair" texture is the horns
            colors = HORN_TEXTURES[sex]
            want = [hd(f"character/tauren/taurenhorns_{colors[r[CS_COLOR]] if r[CS_COLOR] < len(colors) else colors[0]}.blp",
                       composited=False), "", ""]
        elif r[CS_SECTION] == HAIR:
            want = [hd_of(names[0], composited=False), "", ""]
        elif r[CS_SECTION] == UNDERWEAR:
            want = [hd_of(names[0]), hd_of(names[1]) if names[1] else None, None]
        else:
            continue
        if want[0] is None and r[CS_SECTION] != FACIAL_HAIR:
            changed[f"section {r[CS_SECTION]}: no HD texture, kept"] += 1
            continue
        for i, t in enumerate(want):
            if t is not None:
                r[CS_TEX + i] = cs.add_string(t) if t else 0
        changed[f"section {r[CS_SECTION]}"] += 1
    report.append(f"CharSections race {race} sex {sex}: {dict(changed)}")


def hair_fallbacks(race, sex, dropped, report):
    """CharHairGeosets with styles whose geoset was left out pointed at the nearest kept one, so a
    character with such a style gets a similar one rather than none."""
    table = build.Dbc(Client().read("DBFilesClient\\CharHairGeosets.dbc"))
    kept = sorted({r[4] for r in table.rows if r[1] == race and r[2] == sex} - dropped)
    moved = 0
    for r in table.rows:
        if r[1] == race and r[2] == sex and r[4] in dropped and kept:
            r[4] = min(kept, key=lambda g: abs(g - r[4]))
            moved += 1
    report.append(f"CharHairGeosets race {race} sex {sex}: {moved} styles moved to a kept one")
    return table


def safe_for_other_races(cs, converted, files, report):
    """CharSections rows of races without HD models, made safe for Wow-hdchar.exe: its compositor
    copies a region's full size from a source smaller than the region without scaling, so 3.3.5's
    256x64 faces in the 512x512 face region read past their image (a crash logging in a tauren),
    and a 512 skin read past for the right half. Skins are padded to 1024x512 (the old atlas on the
    left), face, facial hair and scalp textures left out. Those races look wrong on that exe anyway
    until they are converted."""
    client = Client()
    padded = {}
    count = 0
    for r in cs.rows:
        if (r[CS_RACE], r[CS_SEX]) in converted:
            continue
        if r[CS_SECTION] == SKIN and r[CS_TEX]:
            name = cs.string(r[CS_TEX])
            if name not in padded:
                data = client.read(name)
                if data:
                    im = blp.Image.open(blp.io.BytesIO(data))
                    im.load()
                    canvas = blp.Image.new("RGBA", (1024, 512), (0, 0, 0, 255))
                    canvas.paste(im.convert("RGBA").resize((512, 512)), (0, 0))
                    path = name[:-4] + "_hdpad.blp"
                    files[path] = blp.encode(canvas)
                    padded[name] = path
            if name in padded:
                r[CS_TEX] = cs.add_string(padded[name])
                count += 1
        elif r[CS_SECTION] in (FACE, FACIAL_HAIR):
            r[CS_TEX:CS_TEX + 3] = [0, 0, 0]
            count += 1
        elif r[CS_SECTION] == HAIR:
            r[CS_TEX + 1:CS_TEX + 3] = [0, 0]
            count += 1
    report.append(f"other races made safe: {count} rows, {len(padded)} skins padded")


def native_size(converted, files, report):
    """Retail builds a race's size into its HD mesh (display and model scale 1); 3.3.5 scales its
    own mesh instead (tauren: display 59 x1.35, model 60 x1.25), which on the HD mesh made giants.
    Both scales go to 1 for every converted race and sex. The creature patch (build.py) writes
    these DBCs too, so its output is the starting point: run chars.py after build.py."""
    creature_patch = Client(chain=[build.patch_paths(4)[1]])
    stock = Client()
    read = lambda name: creature_patch.read(name) or stock.read(name)
    races = build.Dbc(stock.read("DBFilesClient\\ChrRaces.dbc"))
    cdi = build.Dbc(read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    cmd = build.Dbc(read("DBFilesClient\\CreatureModelData.dbc"))
    one = struct.unpack("<I", struct.pack("<f", 1.0))[0]
    displays = {r[CHR_DISPLAY + sex] for r in races.rows for race, sex in converted if r[0] == race}
    models = set()
    for r in cdi.rows:
        if r[0] in displays:
            models.add(r[build.CDI_MODEL])
            if r[build.CDI_SCALE] != one:
                report.append(f"display {r[0]} scale {struct.unpack('<f', struct.pack('<I', r[build.CDI_SCALE]))[0]:g} -> 1")
                r[build.CDI_SCALE] = one
    for r in cmd.rows:
        if r[0] in models and r[CMD_SCALE] != one:
            report.append(f"model {r[0]} scale {struct.unpack('<f', struct.pack('<I', r[CMD_SCALE]))[0]:g} -> 1")
            r[CMD_SCALE] = one
    files["DBFilesClient\\CreatureDisplayInfo.dbc"] = cdi.bytes()
    files["DBFilesClient\\CreatureModelData.dbc"] = cmd.bytes()


def main():
    client = Client()
    cs = build.Dbc(client.read("DBFilesClient\\CharSections.dbc"))
    files, report, hair_tables = {}, [], []
    for race, race_dir, old_dir, hd_models in RACES:
        for sex, hd_path in hd_models.items():
            _, upper = SEXES[sex]
            old_path = f"Character\\{old_dir}\\{upper}\\{old_dir}{upper}.m2"
            dropped = set()
            try:
                model(race, hd_path, old_path, files, report, dropped)
            except (convert.ConvertError, AssertionError, struct.error, OSError, IndexError, KeyError) as e:
                report.append(f"{old_path}: {type(e).__name__}: {e}")
                continue
            char_sections(cs, race, race_dir, sex, files, report)
            if dropped:
                hair_tables.append(hair_fallbacks(race, sex, dropped, report))
    converted = {(race, sex) for race, _, _, models in RACES for sex in models}
    safe_for_other_races(cs, converted, files, report)
    native_size(converted, files, report)
    files["DBFilesClient\\CharSections.dbc"] = cs.bytes()
    if hair_tables:  # ponytail: one race with dropped styles so far; merge tables when there are more
        files["DBFilesClient\\CharHairGeosets.dbc"] = hair_tables[-1].bytes()
    print("\n".join(report))
    print(build.write_patch(6, files))


if __name__ == "__main__":
    main()
