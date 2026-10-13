"""HD player character models: retail's customizable models for 3.3.5, with Wow-hdchar.exe.

usage: chars.py [race dir ...]    converts the races named (retail folder names: dwarf, scourge, ...;
                                  default all) into out/patch-<race dir>.MPQ, one archive per race
                                  (dinput8.dll loads them by name), and writes the shared
                                  out/patch-6.MPQ and out/patch-enUS-6.MPQ (DBCs, every race); then
                                  install.py

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
import csv
import io
import os
import struct
import sys

import blp
import build
import convert
import fetch
from mpq import Client, write_archive
from PIL import Image

# race id, retail folder/prefix, 3.3.5 path prefix, HD model per sex
RACES = [
    (10, "bloodelf", "BloodElf", {0: "character/bloodelf/male/bloodelfmale_hd.m2",
                                  1: "character/bloodelf/female/bloodelffemale_hd.m2"}),
    (2, "orc", "Orc", {0: "character/orc/male/orcmale_hd.m2", 1: "character/orc/female/orcfemale_hd.m2"}),
    (6, "tauren", "Tauren", {0: "character/tauren/male/taurenmale_hd.m2",
                             1: "character/tauren/female/taurenfemale_hd.m2"}),
    (5, "scourge", "Scourge", {0: "character/scourge/male/scourgemale_hd.m2",
                               1: "character/scourge/female/scourgefemale_hd.m2"}),
    (8, "troll", "Troll", {0: "character/troll/male/trollmale_hd.m2", 1: "character/troll/female/trollfemale_hd.m2"}),
    (1, "human", "Human", {0: "character/human/male/humanmale_hd.m2", 1: "character/human/female/humanfemale_hd.m2"}),
    (3, "dwarf", "Dwarf", {0: "character/dwarf/male/dwarfmale_hd.m2", 1: "character/dwarf/female/dwarffemale_hd.m2"}),
    (4, "nightelf", "NightElf", {0: "character/nightelf/male/nightelfmale_hd.m2",
                                 1: "character/nightelf/female/nightelffemale_hd.m2"}),
    (7, "gnome", "Gnome", {0: "character/gnome/male/gnomemale_hd.m2", 1: "character/gnome/female/gnomefemale_hd.m2"}),
]
SEXES = {0: ("male", "Male"), 1: ("female", "Female")}
SEXES_BY_PATH = {upper: sex for sex, (_, upper) in SEXES.items()}
JOIN = {2001: 501, 2301: 401, 2201: 0, 3202: 0, 3301: 0, 3401: 0,  # 3202 is the face (3201 a small cap)
        1801: 0}  # bare waist under belts; 3.3.5's own model has none, its waist is in the body
# Eye glow: 3.3.5 shows 1702 on undead (and 1703 for death knights); retail's 1702-1705 are large
# flame flares (228 vertices, the Primalist eye styles), its plain in-eye glow is 1701 (60). So
# retail 1701 stands in for 1702 on undead.
RENAME = {r: {1701: 1702, 1702: None, 1703: None, 1704: None, 1705: None} for r in (5,)}
# only the DK glow, 1703: blood elf and night elf eyes in retail are the Eye Color texture alone (no
# glow mesh; ours is retail's choice 0), so 3.3.5's own glow slot 1702 stays empty for them
RENAME[8] = RENAME[1] = RENAME[3] = RENAME[10] = RENAME[4] = RENAME[7] = {1701: 1703, 1702: None, 1703: None, 1704: None,
                                                              1705: None}
KEEP_GROUPS = {0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 15, 17, 18}
ARMOUR_GROUPS = {4, 5, 8, 9, 10, 11, 12, 13, 15}
TEXTURE_TYPES = {15: 2, 16: 2, 17: 2, 18: 2, 9: 1}
EYE_TYPE, JEWELRY_TYPE = 19, 20
# CharSections columns: ID, race, sex, section, texture 1..3, flags, variation, color
CS_RACE, CS_SEX, CS_SECTION, CS_TEX, CS_VARIATION, CS_COLOR = 1, 2, 3, 4, 8, 9
SKIN, FACE, FACIAL_HAIR, HAIR, UNDERWEAR = range(5)
CHR_DISPLAY = 4  # ChrRaces: male display, then female
COMPOSITE, THROAT_BOX = (1024, 512), (0, 320, 256, 512)  # patch_exe.py's composite, face lower region
THROAT_RACES = {6, 5}  # races whose HD mesh samples the face lower block (tauren throat, undead bones)
CMD_SCALE = 4    # CreatureModelData: ModelScale


def tauren_geosets(sid, allowed):
    """Retail splits 3.3.5's tauren hair style (horns and hair in one geoset, style v = geoset v + 2)
    into Horn Style (choice v = 2401 + v), Foremane (1-4) and Hair (2xx), and its facial style v
    (1xx, 2xx and 3xx of v + 1) into Facial Hair (10v) and Hair (20v); ChrCustomizationChoice order
    follows 3.3.5's. Every horn style gets retail's default foremane (1, "Short"). 3.3.5's 3xx are
    nose rings, retail's Nose Ring option (16xx), matched by shape (most vertices within 3 cm)."""
    if sid == 1:
        return tuple(sorted(k for k in allowed if 2 <= k < 100))
    if 1 < sid < 100:
        return None
    if 2400 < sid < 2500:
        return sid - 2399 if sid - 2399 in allowed else None
    if 100 < sid < 300:
        return sid + 1 if sid + 1 in allowed else None
    if sid in TAUREN_NOSE_RINGS:
        return tuple(k for k in TAUREN_NOSE_RINGS[sid] if k in allowed) or None
    return NotImplemented


TAUREN_NOSE_RINGS = {1603: (302,), 1602: (303, 306, 307, 309)}  # retail "Bead", "Open"


def orc_geosets(sid, allowed):
    """Orc hair styles and beards keep their ids (retail's choices follow 3.3.5's). Retail moved the
    male tusks into their own option (40xx): natural tusks always drawn. 3.3.5's female piercing
    styles (3xx) are retail earrings plus nose rings, matched by shape (earrings that keep the
    default ears, 702)."""
    new = ORC_GEOSETS.get(sid, NotImplemented)
    if isinstance(new, tuple):
        return tuple(k for k in new if k in allowed) or None
    return new


ORC_GEOSETS = {4001: 0, 4002: None, 4003: None, 4004: None,
               3501: (302, 305), 3502: (303, 306), 3504: (307,), 1601: (304,), 1603: (305, 306)}


def undead_geosets(sid, allowed):
    """Retail's Skin Type adds exposed bone pieces (19xx, 29xx, 30xx); its first, Bony (x01), is
    3.3.5's look, always drawn. Male jaws keep their ids (1xx; retail's 2xx skeletal jaws have no
    3.3.5 style). The female jaw is in 3.3.5's body; retail moved it to Jaw Features (202 Intact,
    203 Bonejawed, 204 Toothy), kept as such and chosen per facial style (UNDEAD_FEMALE_JAWS)."""
    if sid in (1901, 2901, 3001):
        return 0
    if sid in (202, 203, 204) and 102 not in allowed:
        return sid
    if 300 < sid < 400:  # retail's Face Features: no 3.3.5 style
        return None
    return NotImplemented


# 3.3.5 undead female facial style -> 2xx jaw: retail pairs the jaw textures 03 (style 4) and 04
# (style 5) with Bonejawed and Toothy; the other styles' textures go on the intact jaw
UNDEAD_FEMALE_JAWS = {4: 3, 5: 4}
FHS_3XX, FHS_2XX = 4, 5  # CharacterFacialHairStyles: race, sex, style, then geosets 1xx, 3xx, 2xx, 16xx, 17xx


def facial_styles(report):
    """CharacterFacialHairStyles with the undead female styles switching retail's jaws and the gnome
    male ones adding retail's moustaches."""
    table = build.Dbc(Client().read("DBFilesClient\\CharacterFacialHairStyles.dbc"))
    for r in table.rows:
        if r[0] == 5 and r[1] == 1:
            r[FHS_2XX] = UNDEAD_FEMALE_JAWS.get(r[2], 2)
        if r[0] == 7 and r[1] == 0 and r[2] in GNOME_MUSTACHES:
            r[FHS_3XX] = GNOME_MUSTACHES[r[2]] - 300
    report.append("CharacterFacialHairStyles: undead female jaws, gnome male moustaches")
    return table


def troll_geosets(sid, allowed):
    """3.3.5's troll facial styles are tusks (3xx); retail moved them to Tusks (40xx), its first
    choices in 3.3.5's order (male tusks match by shape too: 4001-4005 = 302-306)."""
    if 4000 < sid < 4100:
        return sid - 3699 if sid - 3699 in allowed else None
    return NotImplemented


def human_geosets(sid, allowed):
    """3.3.5's human female facial styles are piercings (3xx); retail moved them to Piercings
    (35xx), its first choices in 3.3.5's order (matched by shape: 3501-3506 = 302-307). Human
    eyebrows are texture by default; retail's brow geometry (34xx) is extra choices, left out."""
    if 3500 < sid < 3600:
        return sid - 3199 if sid - 3199 in allowed else None
    if 3400 < sid < 3500:
        return None
    return NotImplemented


def dwarf_geosets(sid, allowed):
    """3.3.5's dwarves have their ears in the body: retail's ears (702) always drawn, its helmet
    stubs (701) left out. 3.3.5's female facial styles (3xx) are retail earrings (35xx) and a nose
    ring (16xx), matched by shape."""
    if sid // 100 == 7:
        return 0 if sid == 702 else None
    new = DWARF_GEOSETS.get(sid, NotImplemented)
    return new if new is NotImplemented or new in allowed else None


DWARF_GEOSETS = {3501: 302, 3502: 303, 3503: 304, 1601: 305, 3504: 306}


def nightelf_geosets(sid, allowed):
    """3.3.5's night elf ears (702) are closest in shape to retail's Thin ears (701, its default);
    the other ear choices are left out. Retail has four moustaches (301-304) for 3.3.5's 302-307,
    none close in shape: 304 also stands in for 305 and 302 for 306, so styles 4 and 5 keep one."""
    if sid // 100 == 7:
        return 702 if sid == 701 and 702 in allowed else None
    if sid in NIGHTELF_MUSTACHES:
        ids = tuple(i for i in NIGHTELF_MUSTACHES[sid] if i in allowed)
        return ids if len(ids) > 1 else ids[0] if ids else None
    return NotImplemented


NIGHTELF_MUSTACHES = {302: (302, 306), 304: (304, 305)}


def gnome_geosets(sid, allowed):
    """3.3.5's gnome female facial styles are earrings (2xx); retail moved them to Earrings (35xx),
    its first choices in 3.3.5's order (3501-3506 = 202-207; by shape 206 and 207 are the right and
    left ones, as in retail). Male eyebrows: retail's default is none (3400), 3.3.5 has no brow mesh.
    3.3.5's male beards (102-108) have the moustache built in; retail split them into Beard, its
    first choices in 3.3.5's order (101-107 = 102-108, by shape too), and Moustache: the moustache
    closest in shape to the rest of each classic beard (GNOME_MUSTACHES) is kept under its own id."""
    if 100 < sid < 108:
        return sid + 1 if sid + 1 in allowed else None
    if sid == 108:
        return None
    if 300 < sid < 400:
        return sid if sid in GNOME_MUSTACHES.values() else None
    if 3500 < sid < 3600:
        return sid - 3299 if sid - 3299 in allowed else None
    if 3400 < sid < 3500:
        return None
    return NotImplemented


# gnome male facial style -> retail moustache (best fit to the classic beard minus retail's beard;
# styles 3 and 4 close calls against 305 and 303). Never 301: the client shows x01 where a helmet
# hides facial hair (0x4ef1ec), so style 2 takes its runner-up 305 (0.087 against 301's 0.084).
GNOME_MUSTACHES = {2: 305, 3: 303, 4: 310, 5: 305, 6: 305, 7: 305}
RACE_GEOSETS = {6: tauren_geosets, 2: orc_geosets, 5: undead_geosets, 8: troll_geosets, 1: human_geosets,
                3: dwarf_geosets, 4: nightelf_geosets, 7: gnome_geosets}
# Horn Color choices (ChrCustomizationElement -> Material -> TextureFileData), by 3.3.5 hair colour
HORN_TEXTURES = {0: ["01", "02", "03", "01", "07", "07", "07"], 1: ["01", "02", "03", "04", "10", "10", "10", "10"]}


def geoset_map(old_skin, race):
    """geoset_map for convert: retail ids joined (JOIN) or kept when the 3.3.5 model has them too
    (its skin lists exactly what 3.3.5 can switch on: its hair styles, facial hair, armour
    variants), the rest left out. Retail's extra hair styles and armour variants would not fit
    3.3.5's 65535 indices anyway."""
    allowed = set(convert.geoset_ids(old_skin))
    # the client shows an armour group's x01 when no item covers it; 3.3.5's female troll has
    # no 401 (her bare forearms are elsewhere), retail's are 401
    allowed |= {g * 100 + 1 for g in ARMOUR_GROUPS if any(k // 100 == g for k in allowed)}

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
    scale = native_scale(race, SEXES_BY_PATH[old_path.rsplit("\\", 2)[1]])
    if abs(scale - 1) > 1e-6:
        m2, anims = convert.scale_model(m2, anims, 1 / scale)
        warnings.append(f"mesh scaled by 1/{scale:g} (3.3.5 display x model scale)")
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


def table(name):
    return list(csv.DictReader(open(fetch.table(name))))


def chr_model(hd_path):
    """retail's ChrModel id for an HD model path."""
    fid = str(fetch.fdid(hd_path))
    disp = {r["ID"]: r for r in table("CreatureDisplayInfo")}
    model = {r["ID"]: r for r in table("CreatureModelData")}
    return next(r["ID"] for r in table("ChrModel") if disp.get(r["DisplayID"])
                and model.get(disp[r["DisplayID"]]["ModelID"], {}).get("FileDataID") == fid)


def choice_textures(hd_path, option, target):
    """File ids of the texture each choice of a retail customization option sets on a texture
    target (ChrModelTextureTarget: 1 skin, 10 hair), in retail's choice order (which follows
    3.3.5's colour numbers): Hair Color's are the hair sheets retail draws, Skin Color's the skins."""
    cm = chr_model(hd_path)
    opt = next((o["ID"] for o in table("ChrCustomizationOption") if o["ChrModelID"] == cm and o["Name_lang"] == option), None)
    if opt is None:  # tauren: Horn Color instead
        return []
    mat = {r["ID"]: r["MaterialResourcesID"] for r in table("ChrCustomizationMaterial")
           if r["ChrModelTextureTargetID"] == str(target)}
    files = {}
    for r in table("TextureFileData"):
        files.setdefault(r["MaterialResourcesID"], int(r["FileDataID"]))
    material = {e["ChrCustomizationChoiceID"]: e["ChrCustomizationMaterialID"]
                for e in table("ChrCustomizationElement") if e["ChrCustomizationMaterialID"] in mat}
    choices = sorted((c for c in table("ChrCustomizationChoice") if c["ChrCustomizationOptionID"] == opt),
                     key=lambda c: int(c["OrderIndex"]))
    return [files.get(mat.get(material.get(c["ID"]))) for c in choices]


def face_textures(hd_path):
    """{(face, skin colour): file id} from retail's Face choices, whose materials (texture target 5,
    the face) come per Skin Color choice (RelatedChrCustomizationChoiceID): CharSections' face rows
    by variation and colour. Positions in retail's choice order, as for skins and hair colours."""
    cm = chr_model(hd_path)
    opts = {o["ID"]: o["Name_lang"] for o in table("ChrCustomizationOption") if o["ChrModelID"] == cm}
    order = {}
    for name in ("Face", "Skin Color"):
        cs = sorted((c for c in table("ChrCustomizationChoice")
                     if opts.get(c["ChrCustomizationOptionID"]) == name), key=lambda c: int(c["OrderIndex"]))
        order[name] = {c["ID"]: i for i, c in enumerate(cs)}
    mat = {r["ID"]: r["MaterialResourcesID"] for r in table("ChrCustomizationMaterial")
           if r["ChrModelTextureTargetID"] == "5"}
    files = {}
    for r in table("TextureFileData"):
        files.setdefault(r["MaterialResourcesID"], int(r["FileDataID"]))
    out = {}
    for e in table("ChrCustomizationElement"):
        face, skin = order["Face"].get(e["ChrCustomizationChoiceID"]), order["Skin Color"].get(e["RelatedChrCustomizationChoiceID"])
        if face is not None and skin is not None and files.get(mat.get(e["ChrCustomizationMaterialID"])):
            out[face, skin] = files[mat[e["ChrCustomizationMaterialID"]]]
    return out


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
        if path not in files:  # encoded when written: only for the races being built
            files[path] = (lambda: blp.reencode(fetch.get(fid))) if composited else (lambda: fetch.get(fid))
        return path
    original = build.Dbc(Client().read("DBFilesClient\\CharSections.dbc"))
    old_rows = {r[0]: r for r in original.rows}

    def hd_of(name, composited=True):
        """retail's HD file for a 3.3.5 texture name (CharSections colour numbers do not always
        match the file numbers: female face colour 16 is file _10, so names are mapped)."""
        base = name.lower().replace("\\", "/").replace("facelower", "faceupper")
        return hd(base[:-4] + "_hd.blp", composited) if base.endswith(".blp") else None
    def skin_extra(skin_name):
        """retail's fur sheet for a skin colour: 3.3.5 gives every colour extra 00 (black fur, a
        black collar on light tauren); retail shares one per three colours (00 for 0-2, 03 for
        3-5, ...), so the nearest at or below the colour's number."""
        base = skin_name.lower().replace("\\", "/")[:-4]
        stem, color = base[:-2], int(base[-2:])
        for c in range(color, -1, -1):
            path = hd(f"{stem}{c:02d}_extra_hd.blp", composited=False)
            if path:
                return path
        return None
    skins = {r[CS_COLOR]: original.string(old_rows[r[0]][CS_TEX]) for r in cs.rows
             if r[CS_RACE] == race and r[CS_SEX] == sex and r[CS_SECTION] == SKIN and r[CS_VARIATION] == 0}

    def throat(color):
        """The face lower region's texture (patch_exe.REGIONS): the HD skin's block under the
        hands, which retail's tauren sample for the throat; "" for races that do not."""
        if race not in THROAT_RACES or color not in skins:
            return ""
        path = build.mpq_path(f"{prefix}throat{color:02d}_hd.blp")
        if path not in files:
            fid = fetch.fdid(skins[color].lower().replace("\\", "/")[:-4] + "_hd.blp")
            if not fid:
                return ""

            def encode():
                im = Image.open(io.BytesIO(fetch.get(fid)))
                im.load()
                return blp.encode(im.convert("RGBA").resize(COMPOSITE).crop(THROAT_BOX))
            files[path] = encode
        return path
    hair = choice_textures(f"{prefix}_hd.m2", "Hair Color", 10)
    skin_fids = choice_textures(f"{prefix}_hd.m2", "Skin Color", 1)
    faces = face_textures(f"{prefix}_hd.m2")
    # Skin Color's underwear: target 13 pelvis, 14 torso
    underwear = [choice_textures(f"{prefix}_hd.m2", "Skin Color", t) for t in (13, 14)]
    changed = collections.Counter()
    for r in cs.rows:
        if r[CS_RACE] != race or r[CS_SEX] != sex:
            continue
        names = [original.string(t) if t else "" for t in old_rows[r[0]][CS_TEX:CS_TEX + 3]]
        if r[CS_SECTION] == SKIN:  # retail's Skin Color skin; the extra (tauren fur) drawn directly
            fid = skin_fids[r[CS_COLOR]] if r[CS_COLOR] < len(skin_fids) else None
            want = [hd(fetch.name(fid)) if fid else None, skin_extra(names[0]) if names[1] else None, None]
        elif r[CS_SECTION] == FACE:  # upper: the HD face sheet; lower: the throat block (tauren)
            fid = faces.get((r[CS_VARIATION], r[CS_COLOR]))
            face = hd(fetch.name(fid)) if fid else hd_of(names[1] or names[0])  # names: faces retail lacks
            want = [throat(r[CS_COLOR]) if face else None, face, None]
        elif r[CS_SECTION] == FACIAL_HAIR:  # HD facial hair is one full-face sheet (face upper), or geometry
            # 3.3.5's undead females use the race's sheets; retail's of those names are the male's,
            # the female's are in female/ (orc male's are only in male/, not used yet)
            own = names[0] and hd_of(names[0])
            folder, file = names[0].rsplit("\\", 1) if own else ("", "")
            want = ["", own and hd_of(f"{folder}\\{lower}\\{file}") or own or "", ""]
        elif r[CS_SECTION] == HAIR and race_dir == "tauren":  # the "hair" texture is the horns
            colors = HORN_TEXTURES[sex]
            want = [hd(f"character/tauren/taurenhorns_{colors[r[CS_COLOR]] if r[CS_COLOR] < len(colors) else colors[0]}.blp",
                       composited=False), "", ""]
        elif r[CS_SECTION] == HAIR:  # retail's Hair Color sheet, the same for every style
            fid = hair[r[CS_COLOR]] if names[0] and r[CS_COLOR] < len(hair) else None
            want = [hd(fetch.name(fid), composited=False) if fid else None, "", ""]
        elif r[CS_SECTION] == UNDERWEAR:  # names: colours retail lacks
            fids = [u[r[CS_COLOR]] if r[CS_COLOR] < len(u) else None for u in underwear]
            want = [hd(fetch.name(fids[0])) if fids[0] else hd_of(names[0]),
                    (hd(fetch.name(fids[1])) if fids[1] else hd_of(names[1])) if names[1] else None, None]
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


def native_scale(race, sex):
    """3.3.5's display scale x model scale for a race and sex (tauren male 1.35, female 1.25):
    retail's HD mesh has that size built in, and character select ignores both scales, so the
    HD mesh is shrunk by it and the DBCs stay as they are."""
    client = Client()
    races = build.Dbc(client.read("DBFilesClient\\ChrRaces.dbc"))
    cdi = build.Dbc(client.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    cmd = build.Dbc(client.read("DBFilesClient\\CreatureModelData.dbc"))
    f = lambda x: struct.unpack("<f", struct.pack("<I", x))[0]
    display = next(r[CHR_DISPLAY + sex] for r in races.rows if r[0] == race)
    d = next(r for r in cdi.rows if r[0] == display)
    m = next(r for r in cmd.rows if r[0] == d[build.CDI_MODEL])
    return f(d[build.CDI_SCALE]) * f(m[CMD_SCALE])


def face_bones_path(race, sex):
    """Where client/faces.c looks for a race and sex's face shapes."""
    return f"Character\\wotlk-hd\\faces-{race}-{sex}.bin"


def face_bones(race, sex, hd_path, report):
    """Retail's per-face skeleton shapes (.bone files: offset matrices for some head bones) by
    face, for client/faces.c: b"FACE", version 1, face count, then per face (retail's Face choice
    order, which is 3.3.5's face variation) a bone count and (u32 bone, 16 floats) per bone. Faces
    without a .bone file get no bones, as do those whose file the build lacks (night elf female
    faces 0 and 9: not in retail's CASC either). Translations follow the mesh's 3.3.5 scale (tauren)."""
    cm = chr_model(hd_path)
    face = {o["ID"] for o in table("ChrCustomizationOption") if o["ChrModelID"] == cm and o["Name_lang"] == "Face"}
    choices = sorted((c for c in table("ChrCustomizationChoice") if c["ChrCustomizationOptionID"] in face),
                     key=lambda c: int(c["OrderIndex"]))
    bone_files = {r["ID"]: int(r["BoneFileDataID"]) for r in table("ChrCustomizationBoneSet")}
    sets = {e["ChrCustomizationChoiceID"]: e["ChrCustomizationBoneSetID"] for e in table("ChrCustomizationElement")
            if e["ChrCustomizationBoneSetID"] != "0"}
    scale = 1 / native_scale(race, sex)
    out = [b"FACE", struct.pack("<II", 1, len(choices))]
    for c in choices:
        fid = bone_files.get(sets.get(c["ID"]))
        bones = []
        try:
            data = fid and fetch.get(fid)
        except OSError as e:
            report.append(f"face {c['OrderIndex']} of {hd_path}: default shape, no {fetch.name(fid)} ({e})")
            data = None
        if data:
            off, ids, mats = 4, [], []
            while off < len(data):
                tag, size = data[off:off + 4], struct.unpack_from("<I", data, off + 4)[0]
                if tag == b"BIDA":
                    ids = struct.unpack_from(f"<{size // 2}H", data, off + 8)
                elif tag == b"BOMT":
                    mats = [list(struct.unpack_from("<16f", data, off + 8 + 64 * k)) for k in range(size // 64)]
                off += 8 + size
            for bone, m in zip(ids, mats):
                m[12:15] = [v * scale for v in m[12:15]]
                bones.append(struct.pack("<I16f", bone, *m))
        out += [struct.pack("<I", len(bones))] + bones
    return b"".join(out)


def race_archive(race_dir):
    return os.path.join(build.OUT, f"patch-{race_dir}.MPQ")


def main(selected):
    client = Client()
    cs = build.Dbc(client.read("DBFilesClient\\CharSections.dbc"))
    files, report, hair_tables, race_files = {}, [], [], {}
    for race, race_dir, old_dir, hd_models in RACES:
        rebuild = not selected or race_dir in selected
        if not rebuild and not os.path.exists(race_archive(race_dir)):
            report.append(f"{race_dir}: not rebuilt and no {race_archive(race_dir)}: its DBC rows point at missing files")
        own = race_files.setdefault(race_dir, {}) if rebuild else {}  # DBC rows for every race, files for the rebuilt
        for sex, hd_path in hd_models.items():
            _, upper = SEXES[sex]
            old_path = f"Character\\{old_dir}\\{upper}\\{old_dir}{upper}.m2"
            dropped = set()
            if rebuild:
                try:
                    model(race, hd_path, old_path, own, report, dropped)
                except (convert.ConvertError, AssertionError, struct.error, OSError, IndexError, KeyError) as e:
                    report.append(f"{old_path}: {type(e).__name__}: {e}")
                    continue
                own[face_bones_path(race, sex)] = face_bones(race, sex, hd_path, report)
            char_sections(cs, race, race_dir, sex, own, report)
            if dropped:
                hair_tables.append(hair_fallbacks(race, sex, dropped, report))
    safe_for_other_races(cs, {(race, sex) for race, _, _, models in RACES for sex in models}, files, report)
    files["DBFilesClient\\CharSections.dbc"] = cs.bytes()
    if hair_tables:  # ponytail: one race with dropped styles so far; merge tables when there are more
        files["DBFilesClient\\CharHairGeosets.dbc"] = hair_tables[-1].bytes()
    files["DBFilesClient\\CharacterFacialHairStyles.dbc"] = facial_styles(report).bytes()
    print("\n".join(report))
    print(build.write_patch(6, files))
    for race_dir, own in race_files.items():
        write_archive(race_archive(race_dir), own)
        print(f"wrote {race_archive(race_dir)}: {len(own)} files, {os.path.getsize(race_archive(race_dir)) // 1024} KiB")


if __name__ == "__main__":
    unknown = set(sys.argv[1:]) - {d for _, d, _, _ in RACES}
    if unknown:
        sys.exit(f"unknown race dirs {sorted(unknown)}; known: {[d for _, d, _, _ in RACES]}")
    main(set(sys.argv[1:]))
