"""Build the client patch: retail creature models converted over the 3.3.5 ones they replace.

usage: build.py [name ...]    only the named upgrades (default: all in UPGRADES)

Writes out/patch-enUS-4.MPQ. Install by copying it to <WoW>/Data/enUS/. A locale patch numbered
past the client's own wins whichever way 3.3.5 orders base and locale patches, which matters for
the DBC in it.
"""
import collections
import csv
import os
import struct
import sys

import convert
import fetch
from mpq import Client, write_archive
from survey import wdbc

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# old 3.3.5 model -> retail model. Display IDs carry over for most (survey.py); `textures` maps an
# old skin texture name to the retail texture for displays retail didn't move to the new model.
UPGRADES = {
    "murloc": ("creature/murloc/murloc.m2", "creature/murloc2/murloc2.m2", {}),
    "felbat": ("creature/felbat/felbat.m2", "creature/felbat/felbat.m2", {}),
    "minespider": ("creature/minespider/minespider.m2", "creature/minespider2/minespider2.m2", {}),
    "rat": ("creature/rat/rat.m2", "creature/rat2/rat2.m2", {}),
    "frog": ("creature/frog/frog.m2", "creature/frog2/frog2.m2", {}),
    "snake": ("creature/snake/snake.m2", "creature/snake/snake.m2", {}),
    "zombie": ("creature/zombie/zombie.m2", "creature/zombie2/zombie2.m2", {}),
    "skeleton": ("creature/skeleton/skeleton.m2", "creature/scourgewarrior/scourgewarrior.m2", {}),
    "larva": ("creature/larva/larva.m2", "creature/larva2/larva2.m2", {}),
}

# 3.3.5 CreatureDisplayInfo.dbc columns
CDI_MODEL, CDI_EXTRA, CDI_SCALE, CDI_TEX, CDI_GEOSETS = 1, 3, 4, 6, 14


def mpq_path(path):
    return path.replace("/", "\\")


def norm(path):
    p = path.lower().replace("\\", "/")
    return p[:-4] + ".m2" if p.endswith((".mdx", ".mdl")) else p


def f32(u):
    return struct.unpack("<f", struct.pack("<I", u))[0]


def u32(f):
    return struct.unpack("<I", struct.pack("<f", f))[0]


class Dbc:
    """A WDBC file whose rows (lists of u32) can be edited and strings appended."""

    def __init__(self, data):
        magic, n, self.fields, size, ssize = struct.unpack_from("<4s4I", data)
        assert magic == b"WDBC" and size == self.fields * 4
        self.rows = [list(struct.unpack_from(f"<{self.fields}I", data, 20 + i * size)) for i in range(n)]
        self.strings = bytearray(data[20 + n * size:])
        self.added = {}

    def string(self, off):
        return self.strings[off:self.strings.index(b"\0", off)].decode("utf-8", "replace")

    def add_string(self, s):
        if s not in self.added:
            self.added[s] = len(self.strings)
            self.strings += s.encode() + b"\0"
        return self.added[s]

    def bytes(self):
        body = b"".join(struct.pack(f"<{self.fields}I", *r) for r in self.rows)
        return struct.pack("<4s4I", b"WDBC", len(self.rows), self.fields, self.fields * 4,
                           len(self.strings)) + body + bytes(self.strings)


def retail_tables():
    disp = {int(r["ID"]): r for r in csv.DictReader(open(os.path.join(fetch.CACHE, "CreatureDisplayInfo.csv")))}
    model = {int(r["ID"]): int(r["FileDataID"]) for r in csv.DictReader(open(os.path.join(fetch.CACHE, "CreatureModelData.csv")))}
    # 3.3.5 packs a display's geoset choice as one nibble per group (group 1 lowest): 0x1111 shows
    # geosets 101, 201, 301 and 401. Retail lists them as rows (GeosetIndex = group - 1).
    geosets = collections.Counter()
    for r in csv.DictReader(open(os.path.join(fetch.CACHE, "CreatureDisplayInfoGeosetData.csv"))):
        geosets[int(r["CreatureDisplayInfoID"])] |= int(r["GeosetValue"]) << (4 * int(r["GeosetIndex"]))
    return disp, model, geosets


def retail_textures(r):
    return tuple(int(r[f"TextureVariationFileDataID_{i}"]) for i in range(3))


def build(names):
    client = Client()
    cdi = Dbc(client.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    model_rows, ms = wdbc(client.read("DBFilesClient\\CreatureModelData.dbc"))
    old_model = {r[0]: norm(ms(r[2])) for r in model_rows}
    rdisp, rmodel, rgeosets = retail_tables()
    files = {}
    report = []

    for name in names:
        old, new, manual = UPGRADES[name]
        new_fid = fetch.fdid(new)
        old_mpq = mpq_path(old)
        base = old_mpq[:-3]
        model_dir = old_mpq.rsplit("\\", 1)[0]

        def texture_name(fid):
            path = mpq_path(fetch.name(fid))
            files[path] = fetch.get(fid)
            return path

        try:
            m2, skins, anims, warnings = convert.convert_model(
                fetch.get(new_fid), base.rsplit("\\", 1)[1], texture_name, fetch.get)
            convert.check(m2, skins)
        except convert.ConvertError as e:
            report.append(f"{name}: refused: {e}")
            continue
        files[old_mpq] = m2
        # Without a choice 3.3.5 draws every variant at once; variant 1 of each group is the base look.
        groups = {g // 100 for g in convert.geoset_ids(skins[0]) if g}
        default_geosets = sum(1 << (4 * (g - 1)) for g in groups if 1 <= g <= 8)
        for i, s in enumerate(skins):
            files[f"{base}{i:02d}.skin"] = s
        for (aid, sub), data in anims.items():
            files[f"{base}{aid:04d}-{sub:02d}.anim"] = data

        # Displays of the old model: retail's own textures and scale where it moved the same display
        # to the new model; otherwise the texture other displays with that old skin got.
        rows = [r for r in cdi.rows if old_model.get(r[CDI_MODEL]) == old and not r[CDI_EXTRA]]
        paired, learned = {}, collections.defaultdict(collections.Counter)
        for r in rows:
            rr = rdisp.get(r[0])
            if rr and rmodel.get(int(rr["ModelID"])) == new_fid and any(retail_textures(rr)):
                paired[r[0]] = rr
                learned[cdi.string(r[CDI_TEX]).lower()][(retail_textures(rr), rgeosets[r[0]])] += 1
        fallback = collections.Counter(t for c in learned.values() for t in c.elements())
        unmapped = 0
        for r in rows:
            rr = paired.get(r[0])
            old_tex = cdi.string(r[CDI_TEX]).lower()
            if rr:
                tex, geo = retail_textures(rr), rgeosets[r[0]]
                r[CDI_SCALE] = u32(float(rr["CreatureModelScale"]))
            elif old_tex in manual:
                tex, geo = (fetch.fdid(manual[old_tex]), 0, 0), default_geosets
            elif learned.get(old_tex):
                tex, geo = learned[old_tex].most_common(1)[0][0]
            elif fallback:
                (tex, geo), unmapped = fallback.most_common(1)[0][0], unmapped + 1
            else:
                report.append(f"{name}: display {r[0]} has no texture mapping")
                continue
            for i, fid in enumerate(tex):
                if fid:
                    # 3.3.5 looks display textures up next to the model, by name without extension
                    tname = fetch.name(fid).rsplit("/", 1)[1]
                    files[f"{model_dir}\\{tname}"] = fetch.get(fid)
                    r[CDI_TEX + i] = cdi.add_string(tname[:-4])
                else:
                    r[CDI_TEX + i] = 0
            r[CDI_GEOSETS] = geo or default_geosets
        report.append(f"{name}: {old} <- {new}: {len(rows)} displays ({len(paired)} matched in retail"
                      f"{f', {unmapped} on the most common skin' if unmapped else ''})")
        report += [f"  {w}" for w in warnings]

    files["DBFilesClient\\CreatureDisplayInfo.dbc"] = cdi.bytes()
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "patch-enUS-4.MPQ")
    write_archive(out, files)
    print("\n".join(report))
    print(f"wrote {out}: {len(files)} files, {os.path.getsize(out) // 1024} KiB")


if __name__ == "__main__":
    names = sys.argv[1:] or list(UPGRADES)
    unknown = [n for n in names if n not in UPGRADES]
    if unknown:
        sys.exit(f"unknown upgrades: {unknown}; known: {list(UPGRADES)}")
    build(names)
