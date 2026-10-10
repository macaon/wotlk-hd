"""A/B test models in game: variants of one converted model under new display IDs.

usage: experiment.py    writes out/patch-enUS-5.MPQ (copy to <WoW>/Data/enUS/, needs patch-enUS-4)

Each variant gets its own model file, CreatureModelData row and CreatureDisplayInfo row (90001+),
so `.morph target <id>` shows them one after another. The server accepts any display id.

Current experiment: why converted particle emitters draw nothing. Shade exists in 3.3.5 and retail
with the same emitters, so variants step from the converted retail shade towards 3.3.5's emitters.
"""
import os
import struct

import build
import convert
import fetch
from mpq import CHAIN, Client, write_archive
from survey import wdbc

PATCH4 = os.path.join(build.OUT, "patch-enUS-4.MPQ")
FIRST_ID = 90001
SHADE = "Creature\\Shade\\Shade.m2"
SHADE_DISPLAY = 4629  # Darkwraith, unchanged by patch-enUS-4: the control


def emitters(m2):
    m = convert.M2(m2)
    n, off = m.arrays["particles"]
    return n, off


def copy_fields(conv, wotlk, fields):
    """conv with each emitter's (offset, size) fields taken from the 3.3.5 shade's emitters."""
    d = bytearray(conv)
    n, off = emitters(conv)
    wn, woff = emitters(wotlk)
    assert n == wn
    for i in range(n):
        for f, size in fields:
            a = off + i * convert.PARTICLE_WOTLK + f
            b = woff + i * convert.PARTICLE_WOTLK + f
            d[a:a + size] = wotlk[b:b + size]
    return bytes(d)


def main():
    client = Client(chain=[PATCH4] + CHAIN)
    wotlk = client.read(SHADE)
    conv, skins, anims, _ = convert.convert_model(
        fetch.get(fetch.fdid("creature/shade/shade.m2")), "Shade",
        lambda f: build.mpq_path(fetch.name(f)), fetch.get)
    files = {}
    for fid in convert.M2(fetch.get(fetch.fdid("creature/shade/shade.m2"))).u32s("TXID"):
        if fid:
            files[build.mpq_path(fetch.name(fid))] = fetch.get(fid)

    flags = [(0x04, 4)]
    scalars = flags + [(0x13C, 16), (0x180, 4), (0x1A0, 4)]  # head cell curve, spin, wind x
    variants = [
        ("converted retail shade, as built", conv),
        ("converted, emitter flags from 3.3.5", copy_fields(conv, wotlk, flags)),
        ("converted, every emitter value from 3.3.5", copy_fields(conv, wotlk, scalars)),
        ("3.3.5 shade, unchanged file under a new name (harness check)", wotlk),
    ]

    cdi = build.Dbc(client.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    cmd = build.Dbc(client.read("DBFilesClient\\CreatureModelData.dbc"))
    base_display = next(r for r in cdi.rows if r[0] == SHADE_DISPLAY)
    base_model = next(r for r in cmd.rows if r[0] == base_display[build.CDI_MODEL])
    report = []
    for i, (label, m2) in enumerate(variants):
        did = FIRST_ID + i
        name = f"ShadeTest{i + 1}"
        path = f"Creature\\Shade\\{name}.m2"
        convert.check(m2, skins if m2 is not wotlk else [client.read(SHADE[:-3] + "00.skin")])
        files[path] = m2
        files[path[:-3] + "00.skin"] = skins[0] if m2 is not wotlk else client.read(SHADE[:-3] + "00.skin")
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
    print(f".morph target {SHADE_DISPLAY}   control: 3.3.5 shade as the client ships it")
    print("\n".join(report))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
