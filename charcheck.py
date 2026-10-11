"""Checks for adding a race to chars.py (see README, "Adding a race").

usage: charcheck.py options <race dir> <sex>     retail customization choices and their geosets
       charcheck.py geosets <race dir> <sex> [race id]
                                                 3.3.5 vs retail geoset ids, 3.3.5 style tables
       charcheck.py match <race dir> <sex> <3.3.5 ids> [retail groups]
                                                 retail geosets closest in shape to 3.3.5's
       charcheck.py built <race dir> <sex>       the built out/patch-6 model: skin vertices outside
                                                 3.3.5's regions, broken keyframes, aliases left

race dir is retail's folder name (orc, tauren, scourge, ...), sex male or female. match needs numpy
and scipy (the scratch venv); the rest runs with the repo's python.
"""
import collections
import csv
import os
import struct
import sys

import build
import chars
import convert
import fetch
import mpq
from m2 import ARRAYS

OUT_WOW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "wow")  # for mpq.Client
REGIONS = [  # patch_exe.REGIONS as drawn: what the compositor fills, everything else stays black
    (0, 0, 256, 128), (0, 128, 256, 128), (0, 256, 256, 64), (256, 0, 256, 128), (256, 128, 256, 64),
    (256, 192, 256, 128), (256, 320, 256, 128), (256, 448, 256, 64), (512, 0, 512, 512), (0, 320, 256, 192)]


def table(name):
    return list(csv.DictReader(open(fetch.table(name))))


def hd_path(race_dir, sex):
    return f"character/{race_dir}/{sex}/{race_dir}{sex}_hd"


def old_path(race_dir, sex):
    """3.3.5's model path for the race (from chars.RACES, else a capitalised guess)."""
    old = next((o for _, r, o, _ in chars.RACES if r == race_dir), race_dir.capitalize())
    s = sex.capitalize()
    return f"Character\\{old}\\{s}\\{old}{s}"


def options(race_dir, sex):
    fid = str(fetch.fdid(hd_path(race_dir, sex) + ".m2"))
    disp = {r["ID"]: r for r in table("CreatureDisplayInfo")}
    model = {r["ID"]: r for r in table("CreatureModelData")}
    chr_model = next(r["ID"] for r in table("ChrModel") if disp.get(r["DisplayID"])
                     and model.get(disp[r["DisplayID"]]["ModelID"], {}).get("FileDataID") == fid)
    geo = {r["ID"]: r for r in table("ChrCustomizationGeoset")}
    elements = collections.defaultdict(list)
    for e in table("ChrCustomizationElement"):
        elements[e["ChrCustomizationChoiceID"]].append(e)
    choices = collections.defaultdict(list)
    for c in table("ChrCustomizationChoice"):
        choices[c["ChrCustomizationOptionID"]].append(c)
    print("ChrModel", chr_model)
    for o in sorted((o for o in table("ChrCustomizationOption") if o["ChrModelID"] == chr_model),
                    key=lambda o: int(o["OrderIndex"])):
        out = []
        for c in sorted(choices[o["ID"]], key=lambda c: int(c["OrderIndex"])):
            ids = sorted({int(geo[e["ChrCustomizationGeosetID"]]["GeosetType"]) * 100 +
                          int(geo[e["ChrCustomizationGeosetID"]]["GeosetID"])
                          for e in elements[c["ID"]] if e["ChrCustomizationGeosetID"] != "0"})
            out.append(f"{c['Name_lang'][:12] or '-'}{ids or ''}")
        print(f"  {o['Name_lang']}: " + ", ".join(out))


def geosets(race_dir, sex, race=None):
    client = mpq.Client()
    old = client.read(old_path(race_dir, sex) + "00.skin")
    print("3.3.5 :", sorted(set(convert.geoset_ids(old))))
    print("retail:", sorted(set(convert.geoset_ids(fetch.get(fetch.fdid(hd_path(race_dir, sex) + "00.skin"))))))
    race = race or next((r for r, d, _, _ in chars.RACES if d == race_dir), None)
    sx = 0 if sex == "male" else 1
    hair = build.Dbc(client.read("DBFilesClient\\CharHairGeosets.dbc"))
    facial = build.Dbc(client.read("DBFilesClient\\CharacterFacialHairStyles.dbc"))
    if race is None:
        races = build.Dbc(client.read("DBFilesClient\\ChrRaces.dbc"))
        print("race id not in chars.RACES (pass it); ChrRaces:", [(r[0], races.string(r[14])) for r in races.rows][:12])
        return
    print("hair style -> geoset:", sorted((r[3], r[4]) for r in hair.rows if r[1] == race and r[2] == sx))
    print("facial style -> (1xx, 3xx, 2xx):", sorted((r[2], tuple(r[3:6])) for r in facial.rows
                                                  if r[0] == race and r[1] == sx))
    print("3.3.5 scale (display x model):", chars.native_scale(race, sx))


def match(race_dir, sex, ids, groups=None):
    import numpy as np
    from scipy.spatial import cKDTree

    def verts(m2, skin):
        nv, ov = struct.unpack_from("<II", m2, 0x3C)
        nl, ol = struct.unpack_from("<II", skin, 4)
        lookup = struct.unpack_from(f"<{nl}H", skin, ol)
        ns, os_ = struct.unpack_from("<II", skin, 0x1C)
        out = collections.defaultdict(list)
        for i in range(ns):
            sid, _, vs, vc = struct.unpack_from("<4H", skin, os_ + 48 * i)
            out[sid] += [struct.unpack_from("<3f", m2, ov + 48 * lookup[k]) for k in range(vs, vs + vc)]
        return {k: np.array(v) for k, v in out.items()}
    race = next((r for r, d, _, _ in chars.RACES if d == race_dir), None)
    scale = chars.native_scale(race, 0 if sex == "male" else 1) if race else 1.0
    client = mpq.Client()
    old = {k: v * scale for k, v in verts(client.read(old_path(race_dir, sex) + ".m2"),
                                          client.read(old_path(race_dir, sex) + "00.skin")).items()}
    r = fetch.get(fetch.fdid(hd_path(race_dir, sex) + ".m2"))
    new = verts(r[r.find(b"MD20"):], fetch.get(fetch.fdid(hd_path(race_dir, sex) + "00.skin")))
    both = lambda a, b: float(np.mean(cKDTree(b).query(a)[0]) + np.mean(cKDTree(a).query(b)[0]))
    for k in ids:
        if k not in old:
            print(k, "not in the 3.3.5 skin")
            continue
        cands = sorted((g for g in new if not groups or g // 100 in groups), key=lambda g: both(old[k], new[g]))
        print(k, [(g, round(both(old[k], new[g]), 3)) for g in cands[:4]], "(two-way mean distance)")


def built(race_dir, sex):
    os.makedirs(os.path.join(OUT_WOW, "Data"), exist_ok=True)
    link = os.path.join(OUT_WOW, "Data", "patch-6.MPQ")
    if not os.path.exists(link):
        os.symlink(build.patch_paths(6)[0], link)
    client = mpq.Client(wow_dir=OUT_WOW, chain=["patch-6.MPQ"])
    p = old_path(race_dir, sex)
    m, s = client.read(p + ".m2"), client.read(p + "00.skin")
    if not m:
        print("not in out/patch-6.MPQ: run chars.py")
        return
    arrays = {name: struct.unpack_from("<II", m, off) for off, name in ARRAYS}
    ov = arrays["vertices"][1]
    n_tex, tex_off = arrays["textures"]
    types = [struct.unpack_from("<I", m, tex_off + 16 * i)[0] for i in range(n_tex)]
    n_tl, tl_off = arrays["texture_lookup"]
    tl = [struct.unpack_from("<h", m, tl_off + 2 * i)[0] for i in range(n_tl)]
    nl, ol = struct.unpack_from("<II", s, 4)
    lookup = struct.unpack_from(f"<{nl}H", s, ol)
    ns, os_ = struct.unpack_from("<II", s, 0x1C)
    nb, ob = struct.unpack_from("<II", s, 0x24)
    outside = collections.Counter()
    for i in range(nb):
        sub, = struct.unpack_from("<H", s, ob + 24 * i + 4)
        tex, = struct.unpack_from("<H", s, ob + 24 * i + 16)
        if types[tl[tex]] != 1:
            continue
        sid, _, vs, vc = struct.unpack_from("<4H", s, os_ + 48 * sub)
        for k in range(vs, vs + vc):
            u, v = struct.unpack_from("<2f", m, ov + 48 * lookup[k] + 32)
            x, y = u % 1 * 1024, v % 1 * 512
            if not any(a <= x < a + w and b <= y < b + h for a, b, w, h in REGIONS):
                outside[sid] += 1
    print("skin-textured vertices outside the regions (drawn black):", dict(outside) or "none")
    n_seq, seq_off = arrays["sequences"]
    seqs = [struct.unpack_from("<HH", m, seq_off + 64 * k) for k in range(n_seq)]
    flags = [struct.unpack_from("<I", m, seq_off + 64 * k + 12)[0] for k in range(n_seq)]
    anims, bad = {}, collections.Counter()
    for name, (size, tracks) in convert.TRACK_ARRAYS.items():
        n, off = arrays[name]
        for i in range(n):
            for t, key_size in tracks:
                pos = off + i * size + t
                global_loop, = struct.unpack_from("<h", m, pos + 2)
                for arr, es in ((pos + 4, 4), (pos + 12, key_size)):
                    n_outer, outer = struct.unpack_from("<II", m, arr)
                    for k in range(n_outer):
                        cnt, inner = struct.unpack_from("<II", m, outer + 8 * k)
                        if not cnt:
                            continue
                        if global_loop >= 0 or k >= n_seq or flags[k] & convert.SEQ_INLINE:
                            buf = m
                        else:
                            if seqs[k] not in anims:
                                anims[seqs[k]] = client.read(f"{p}{seqs[k][0]:04d}-{seqs[k][1]:02d}.anim")
                            buf = anims[seqs[k]]
                            if buf is None:
                                bad[f"keys in a missing .anim ({seqs[k][0]}-{seqs[k][1]})"] += 1
                                continue
                        if inner + cnt * es > len(buf):
                            bad["keys out of range"] += 1
                        elif es == 4 and struct.unpack_from("<I", buf, inner)[0] > 0:
                            bad["first key after time 0"] += 1
    print("aliases left:", sum(1 for f in flags if f & convert.SEQ_ALIAS), "keyframe problems:", dict(bad) or "none")


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 3:
        sys.exit(__doc__)
    if a[0] == "match":
        match(a[1], a[2], [int(x) for x in a[3].split(",")], {int(x) for x in a[4].split(",")} if len(a) > 4 else None)
    elif a[0] == "geosets":
        geosets(a[1], a[2], int(a[3]) if len(a) > 3 else None)
    else:
        {"options": options, "built": built}[a[0]](a[1], a[2])
