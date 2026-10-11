"""HD player character models: retail's customizable models for 3.3.5, with Wow-hdchar.exe.

usage: chars.py    writes out/patch-6.MPQ and out/patch-enUS-6.MPQ (install.py; needs Wow-hdchar.exe)

Wow-hdchar.exe composites characters as 1024x512 in retail's HD layout (patch_exe.py), so the HD
models' UVs and retail's HD skin, face and underwear textures fit unchanged. The models come in
through convert.py (their skeletons are .skel files); then:

- geosets: 3.3.5 shows hair (0xx), facial hair (1xx), ears (7xx) and armour (4xx-18xx) itself.
  Retail's new groups are set by its client: feet (20xx) and hands (23xx) show without boots and
  gloves, so they join 501 and 401; torso (2201), face, eyes and brows (3201, 3301, 3401) always
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
]
SEXES = {0: ("male", "Male"), 1: ("female", "Female")}
JOIN = {2001: 501, 2301: 401, 2201: 0, 3201: 0, 3301: 0, 3401: 0}
KEEP_GROUPS = {0, 1, 4, 5, 7, 8, 9, 10, 11, 12, 13, 15, 17, 18}
TEXTURE_TYPES = {15: 2, 16: 2, 17: 2, 18: 2, 9: 1}
EYE_TYPE = 19
# CharSections columns: ID, race, sex, section, texture 1..3, flags, variation, color
CS_RACE, CS_SEX, CS_SECTION, CS_TEX, CS_VARIATION, CS_COLOR = 1, 2, 3, 4, 8, 9
SKIN, FACE, FACIAL_HAIR, HAIR, UNDERWEAR = range(5)


def geoset_map(old_skin):
    """geoset_map for convert: retail ids joined (JOIN) or kept when the 3.3.5 model has them too
    (its skin lists exactly what 3.3.5 can switch on: its hair styles, facial hair, armour
    variants), the rest left out. Retail's extra hair styles and armour variants would not fit
    3.3.5's 65535 indices anyway."""
    allowed = set(convert.geoset_ids(old_skin))

    def remap(sid):
        sid = JOIN.get(sid, sid)
        return sid if sid in allowed and sid // 100 in KEEP_GROUPS else None
    return remap


def textures(m2, eye_path):
    """Texture slots of types 3.3.5 lacks retyped; the eye slot becomes the fixed file eye_path."""
    b = convert.Blob(m2)
    n, off = struct.unpack_from("<II", b.d, 0x50)
    for i in range(n):
        t = off + i * 16
        ttype, = struct.unpack_from("<I", b.d, t)
        if ttype == EYE_TYPE:
            name = eye_path.encode() + b"\0"
            struct.pack_into("<III", b.d, t, 0, 0, len(name))
            struct.pack_into("<I", b.d, t + 12, b.add(name))
        elif ttype in TEXTURE_TYPES:
            struct.pack_into("<I", b.d, t, TEXTURE_TYPES[ttype])
    return bytes(b.d)


def model(hd_path, old_path, files, report):
    fid = fetch.fdid(hd_path)
    fetch.prefetch_models([fid])

    def texture_name(f):
        path = build.mpq_path(fetch.name(f))
        files[path] = fetch.get(f)
        return path
    old_skin = Client().read(old_path[:-3] + "00.skin")
    # Index starts past 65535 drew garbage even with Wow-hdchar.exe's level patches, so the skins
    # fit under it: the most detailed LOD that does, alternative hair styles last and left out if
    # nothing else fits (the HD male's 16 styles are 46k-60k indices on their own).
    m2, skins, anims, warnings = convert.convert_model_fitting(
        fetch.get(fid), old_path.rsplit("\\", 1)[1][:-3], texture_name, fetch.get,
        geoset_map=geoset_map(old_skin), optional=lambda sid: 0 < sid < 100)
    race_dir = hd_path.split("/")[1]
    eyes = f"character/{race_dir}/eyes00_00"
    eye_fid = next((f for n, f in fetch._listfile()[1].items() if n.startswith(eyes) and n.endswith(".blp")), None)
    if not eye_fid:
        raise convert.ConvertError(f"no eye texture {eyes}*")
    m2 = textures(m2, texture_name(eye_fid))
    convert.check(m2, skins)
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
    changed = collections.Counter()
    for r in cs.rows:
        if r[CS_RACE] != race or r[CS_SEX] != sex:
            continue
        v, c = r[CS_VARIATION], r[CS_COLOR]
        if r[CS_SECTION] == SKIN:
            want = [hd(f"{prefix}skin00_{c:02d}_hd.blp"), None, None]
        elif r[CS_SECTION] == FACE:
            face = hd(f"{prefix}faceupper{v:02d}_{c:02d}_hd.blp")
            want = [face, face, None]
        elif r[CS_SECTION] == FACIAL_HAIR:
            want = ["", "", ""]
        elif r[CS_SECTION] == HAIR:
            want = [hd(f"character/{race_dir}/hair00_{c:02d}_hd.blp", composited=False), "", ""]
        elif r[CS_SECTION] == UNDERWEAR:
            want = [hd(f"{prefix}nakedpelvisskin00_{c:02d}_hd.blp"), hd(f"{prefix}nakedtorsoskin00_{c:02d}_hd.blp"), None]
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


def main():
    client = Client()
    cs = build.Dbc(client.read("DBFilesClient\\CharSections.dbc"))
    files, report = {}, []
    for race, race_dir, old_dir, hd_models in RACES:
        for sex, hd_path in hd_models.items():
            _, upper = SEXES[sex]
            old_path = f"Character\\{old_dir}\\{upper}\\{old_dir}{upper}.m2"
            try:
                model(hd_path, old_path, files, report)
            except (convert.ConvertError, AssertionError, struct.error, OSError, IndexError, KeyError) as e:
                report.append(f"{old_path}: {type(e).__name__}: {e}")
                continue
            char_sections(cs, race, race_dir, sex, files, report)
    files["DBFilesClient\\CharSections.dbc"] = cs.bytes()
    print("\n".join(report))
    print(build.write_patch(6, files))


if __name__ == "__main__":
    main()
