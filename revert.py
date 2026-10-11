"""Put original 3.3.5 models back over patch-enUS-4, to find which upgrade misbehaves in game.

usage: revert.py <old model path> ...    writes out/patch-enUS-5.MPQ (copy to <WoW>/Data/enUS/)

e.g. revert.py creature/felbat/felbat.m2. The DBCs are patch-enUS-4's with those models' display
and model rows restored; the model, its skins and .anim files come from the client's own archives.
"""
import os
import struct
import sys

import build
from mpq import CHAIN, Client, write_archive

PATCH4 = os.path.join(build.OUT, "patch-enUS-4.MPQ")


def main(paths):
    original, patched = Client(), Client(chain=[PATCH4] + CHAIN)
    files = {}
    tables = {}
    for name in ("CreatureDisplayInfo", "CreatureModelData"):
        tables[name] = (build.Dbc(original.read(f"DBFilesClient\\{name}.dbc")),
                        build.Dbc(patched.read(f"DBFilesClient\\{name}.dbc")))
    (cdi_old, cdi), (cmd_old, cmd) = tables["CreatureDisplayInfo"], tables["CreatureModelData"]
    old_model = {r[0]: build.norm(cmd_old.string(r[2])) for r in cmd_old.rows}
    old_cdi = {r[0]: r for r in cdi_old.rows}
    for path in paths:
        path = build.norm(path)
        models = {mid for mid, p in old_model.items() if p == path}
        for i, r in enumerate(cdi.rows):
            o = old_cdi.get(r[0])
            if o and o[build.CDI_MODEL] in models:
                row = list(o)
                for col in range(build.CDI_TEX, build.CDI_TEX + 3):  # strings live in the new table
                    row[col] = cdi.add_string(cdi_old.string(o[col])) if o[col] else 0
                cdi.rows[i] = row
        base = build.mpq_path(path)[:-3]
        m2 = original.read(f"{base}.m2")
        n_seq, seq_off = struct.unpack_from("<II", m2, 0x1C)
        names = [f"{base}.m2", f"{base}00.skin"]
        for k in range(n_seq):  # external .anim files (patch-enUS-4 has the upgrade's under the same names)
            aid, sub = struct.unpack_from("<HH", m2, seq_off + k * 64)
            if not struct.unpack_from("<I", m2, seq_off + k * 64 + 12)[0] & 0x60:
                names.append(f"{base}{aid:04d}-{sub:02d}.anim")
        for n in names:
            data = original.read(n)
            if data:
                files[n] = data
        print(f"{path}: {len(models)} model rows, {len(names)} files")
    files["DBFilesClient\\CreatureDisplayInfo.dbc"] = cdi.bytes()
    files["DBFilesClient\\CreatureModelData.dbc"] = cmd.bytes()
    out = os.path.join(build.OUT, "patch-enUS-5.MPQ")
    write_archive(out, files)
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
