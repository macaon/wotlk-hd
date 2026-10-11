"""A/B test models in game: variants of one converted model under new display IDs.

usage: experiment.py    writes out/patch-enUS-5.MPQ (copy to <WoW>/Data/enUS/, needs patch-enUS-4)

Each variant gets its own model file, CreatureModelData row and CreatureDisplayInfo row (90001+),
so `.morph target <id>` shows them one after another. The server accepts any display id.

Current experiment: gargoyle2 (Stonewing Slayer, display 7533) garbles triangles while animating
and crashed the client (bone matrix copy, 0x8203b0). Variants switch one part off at a time.
(Earlier: voidwalker2 particles, shade emitters; both fine in the end.)
"""
import os
import struct

import build
import convert
import fetch
from mpq import CHAIN, Client, write_archive

PATCH4 = os.path.join(build.OUT, "patch-enUS-4.MPQ")
FIRST_ID = 90001
OLD = "Creature\\Gargoyle\\Gargoyle.m2"
NEW = "creature/gargoyle2/gargoyle2.m2"
DISPLAY = 7533  # Stonewing Slayer


def static_bones(m2):
    """No bone animation: every bone track empty, so the model holds its bind pose."""
    d = bytearray(m2)
    n, off = struct.unpack_from("<II", d, 0x2C)
    for i in range(n):
        for t in convert.BONE_TRACKS:
            struct.pack_into("<IIII", d, off + i * 88 + t + 4, 0, 0, 0, 0)
    return bytes(d)


def no_extras(m2):
    """No attachments, events or cameras."""
    d = bytearray(m2)
    for header in (0xF0, 0xF8, 0x100, 0x110, 0x118):
        struct.pack_into("<II", d, header, 0, 0)
    return bytes(d)


def only_base_geoset(skin):
    """Only the batches of geoset 0 submeshes (body)."""
    s = bytearray(skin)
    ns, os_, nt, ot = struct.unpack_from("<IIII", s, 28)
    keep = [bytes(s[ot + i * 24:ot + i * 24 + 24]) for i in range(nt)
            if struct.unpack_from("<H", s, os_ + struct.unpack_from("<H", s, ot + i * 24 + 4)[0] * 48)[0] == 0]
    s[ot:ot + len(keep) * 24] = b"".join(keep)
    struct.pack_into("<I", s, 36, len(keep))
    return bytes(s)


def main():
    client = Client(chain=[PATCH4] + CHAIN)
    data = fetch.get(fetch.fdid(NEW))
    name = lambda f: build.mpq_path(fetch.name(f))
    conv, skins, anims, _ = convert.convert_model(data, "Gargoyle", name, fetch.get)
    convert.MAX_BONES_PER_SUBMESH = 32
    conv32, skins32, _, _ = convert.convert_model(data, "Gargoyle", name, fetch.get)
    convert.MAX_BONES_PER_SUBMESH = 64
    files = {}
    variants = [  # (label, m2, skin)
        ("control: gargoyle2 as built", conv, skins[0]),
        ("no bone animation (bind pose)", static_bones(conv), skins[0]),
        ("no attachments, events, cameras", no_extras(conv), skins[0]),
        ("submeshes split at 32 bones instead of 64", conv32, skins32[0]),
        ("body geoset only", conv, only_base_geoset(skins[0])),
    ]
    cdi = build.Dbc(client.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    cmd = build.Dbc(client.read("DBFilesClient\\CreatureModelData.dbc"))
    base_display = next(r for r in cdi.rows if r[0] == DISPLAY)
    base_model = next(r for r in cmd.rows if r[0] == base_display[build.CDI_MODEL])
    model_dir = OLD.rsplit("\\", 1)[0]
    report = []
    for i, (label, m2, skin) in enumerate(variants):
        did = FIRST_ID + i
        path = f"{model_dir}\\Test{i + 1}.m2"
        convert.check(m2, [skin])
        files[path] = m2
        files[path[:-3] + "00.skin"] = skin
        for (aid, sub), data in anims.items():
            files[f"{path[:-3]}{aid:04d}-{sub:02d}.anim"] = data
        model_row = list(base_model)
        model_row[0] = did
        model_row[2] = cmd.add_string(path[:-3] + ".mdx")
        cmd.rows.append(model_row)
        display_row = list(base_display)
        display_row[0] = did
        display_row[build.CDI_MODEL] = did
        cdi.rows.append(display_row)
        report.append(f".morph target {did}   {label}")
    files["DBFilesClient\\CreatureDisplayInfo.dbc"] = cdi.bytes()
    files["DBFilesClient\\CreatureModelData.dbc"] = cmd.bytes()
    out = os.path.join(build.OUT, "patch-enUS-5.MPQ")
    write_archive(out, files)
    print("\n".join(report))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
