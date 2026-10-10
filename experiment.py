"""A/B test models in game: variants of one converted model under new display IDs.

usage: experiment.py    writes out/patch-enUS-5.MPQ (copy to <WoW>/Data/enUS/, needs patch-enUS-4)

Each variant gets its own model file, CreatureModelData row and CreatureDisplayInfo row (90001+),
so `.morph target <id>` shows them one after another. The server accepts any display id.

Current experiment: voidwalker2's particles draw as flat squares. The 3.3.5 voidwalker has the
same four emitters (two glow balls, two smoke), so variants swap in its flags and textures.
(Previous one, shade: showed the emitter struct conversion itself is right.)
"""
import os
import struct

import build
import convert
import fetch
from mpq import CHAIN, Client, write_archive

PATCH4 = os.path.join(build.OUT, "patch-enUS-4.MPQ")
FIRST_ID = 90001
OLD = "Creature\\VoidWalker\\VoidWalker.m2"
NEW = "creature/voidwalker2/voidwalker2.m2"
DISPLAY = 1132  # warlock voidwalker
GLOW = "CREATURE\\FIREELEMENTAL\\GLOWBALL.BLP"   # what the 3.3.5 voidwalker's glow balls use
SMOKE = "CREATURE\\VOIDWALKER\\SMOKE01.BLP"


def edit_emitters(m2, fn):
    """m2 with fn(emitter bytearray, index, model) applied to each emitter; may append strings."""
    b = convert.Blob(m2)
    m = convert.M2(m2)
    n, off = m.arrays["particles"]
    for i in range(n):
        e = bytearray(b.d[off + i * convert.PARTICLE_WOTLK:off + (i + 1) * convert.PARTICLE_WOTLK])
        fn(e, i, b)
        b.d[off + i * convert.PARTICLE_WOTLK:off + (i + 1) * convert.PARTICLE_WOTLK] = e
    return bytes(b.d)


def add_texture(b, path):
    """Append a hardcoded texture slot naming path; returns its index."""
    n, off = struct.unpack_from("<II", b.d, 0x50)
    slots = bytes(b.d[off:off + n * 16])
    name = path.encode() + b"\0"
    name_off = b.add(name)
    b.set_array(0x50, n + 1, slots + struct.pack("<4I", 0, 0, len(name), name_off))
    return n


def wotlk_flags(e, i, b):
    e[4:8] = struct.pack("<I", 0x20001 if e[0x28] == 4 else 0x20019)


def wotlk_textures(e, i, b):
    path = GLOW if e[0x28] == 4 else SMOKE
    cache = b.__dict__.setdefault("added", {})
    if path not in cache:
        cache[path] = add_texture(b, path)
    struct.pack_into("<H", e, 0x16, cache[path])


def no_particles(m2):
    d = bytearray(m2)
    struct.pack_into("<II", d, 0x128, 0, 0)
    return bytes(d)


def main():
    client = Client(chain=[PATCH4] + CHAIN)
    conv, skins, anims, _ = convert.convert_model(
        fetch.get(fetch.fdid(NEW)), "VoidWalker", lambda f: build.mpq_path(fetch.name(f)), fetch.get)
    files = {build.mpq_path(fetch.name(f)): fetch.get(f) for f in convert.M2(fetch.get(fetch.fdid(NEW))).u32s("TXID") if f}
    both = edit_emitters(edit_emitters(conv, wotlk_flags), wotlk_textures)
    original = Client()  # without the patch: the 3.3.5 file at OLD is replaced there
    variants = [
        ("CONTROL: the 3.3.5 voidwalker, unconverted (squares here too = OpenGL/client)",
         original.read(OLD)),
        ("converted voidwalker2, as built", conv),
        ("converted, no particle emitters (are the squares particles?)", no_particles(conv)),
        ("converted, emitter flags from the 3.3.5 voidwalker", edit_emitters(conv, wotlk_flags)),
        ("converted, 3.3.5 particle textures (glowball/smoke01)", edit_emitters(conv, wotlk_textures)),
        ("converted, 3.3.5 flags and textures", both),
    ]

    cdi = build.Dbc(client.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    cmd = build.Dbc(client.read("DBFilesClient\\CreatureModelData.dbc"))
    base_display = next(r for r in cdi.rows if r[0] == DISPLAY)
    base_model = next(r for r in cmd.rows if r[0] == base_display[build.CDI_MODEL])
    model_dir = OLD.rsplit("\\", 1)[0]
    report = []
    for i, (label, m2) in enumerate(variants):
        did = FIRST_ID + i
        path = f"{model_dir}\\Test{i + 1}.m2"
        skin = original.read(OLD[:-3] + "00.skin") if i == 0 else skins[0]
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
