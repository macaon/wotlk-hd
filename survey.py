"""How many WotLK creature displays have a newer model in retail?

For each display in the 3.3.5 CreatureDisplayInfo.dbc, look up the same display ID in retail
(wago.tools CSV) and classify it:
  humanoid  - uses a character model (ExtendedDisplayInfoID), separate track
  new-model - retail replaced the model with a different file
  updated   - same model file, but its bounding box changed (the file was redone in place)
  same      - nothing suggests a change
  reused    - retail points this display somewhere other than the rest of its model's displays
              (the display ID was reassigned); keep the old model
  character - a player-race body without ExtendedDisplayInfo, separate track
  gone      - display or model missing in retail
"""
import collections
import re
import csv
import struct
import sys

from mpq import Client


def wdbc(data):
    """Rows of a WDBC file as lists of raw u32 fields, plus a string lookup."""
    magic, n, fields, size, ssize = struct.unpack_from("<4s4I", data)
    assert magic == b"WDBC" and size == fields * 4
    rows = [struct.unpack_from(f"<{fields}I", data, 20 + i * size) for i in range(n)]
    strings = data[20 + n * size:]

    def s(off):
        return strings[off:strings.index(b"\0", off)].decode("utf-8", "replace")
    return rows, s


def f32(u):
    return struct.unpack("<f", struct.pack("<I", u))[0]


def norm(path):
    p = path.lower().replace("\\", "/")
    return p[:-4] + ".m2" if p.endswith(".mdx") or p.endswith(".mdl") else p


def family(path):
    """Model name without folder, extension and version digits: creature/kobold2/kobold2.m2 -> kobold."""
    return re.sub(r"\d+$", "", path.rsplit("/", 1)[-1].rsplit(".", 1)[0])


def classify():
    """(display count, [(display, kind, old model path, retail model path or None)]), kinds as above."""
    c = Client()
    disp, _ = wdbc(c.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    model_rows, ms = wdbc(c.read("DBFilesClient\\CreatureModelData.dbc"))
    old_models = {r[0]: (norm(ms(r[2])), [f32(x) for x in r[17:23]]) for r in model_rows}

    names = {}
    with open("cache/listfile.csv", encoding="utf-8") as f:
        for line in f:
            fid, _, name = line.rstrip("\n").partition(";")
            names[int(fid)] = name
    rd = {int(r["ID"]): r for r in csv.DictReader(open("cache/CreatureDisplayInfo.csv"))}
    rm = {int(r["ID"]): r for r in csv.DictReader(open("cache/CreatureModelData.csv"))}

    seen = []  # (display, kind or None, old path, new path, old box, new box)
    for row in disp:
        did, mid, ext = row[0], row[1], row[3]
        old_path, old_box = old_models.get(mid, ("?", None))
        r = rd.get(did)
        m = r and rm.get(int(r["ModelID"]))
        if ext:
            seen.append((did, "humanoid", old_path, None, None, None))
        elif not m:
            seen.append((did, "gone", old_path, None, None, None))
        else:
            new_path = names.get(int(m["FileDataID"]), f"fdid:{m['FileDataID']}")
            new_box = [float(m[f"GeoBox_{i}"]) for i in range(6)]
            seen.append((did, None, old_path, new_path, old_box, new_box))

    # An old model's most common retail target is its upgrade; displays pointing elsewhere were
    # reassigned (WotLK display 4 is a crystal spider, retail display 4 is a murloc).
    targets = collections.defaultdict(collections.Counter)
    for _, kind, old_path, new_path, _, _ in seen:
        if kind is None:
            targets[old_path][new_path] += 1

    out = []
    for did, kind, old_path, new_path, old_box, new_box in seen:
        if kind is None:
            if old_path.startswith("character/"):
                kind = "character"
            elif new_path != old_path:
                # Trust a renamed target only if it is the model's usual one and either keeps the
                # name or more than one display agrees on it.
                top, votes = targets[old_path].most_common(1)[0]
                ok = new_path == top and (family(new_path) == family(old_path) or votes > 1)
                kind = "new-model" if ok else "reused"
            elif old_box and any(abs(a - b) > 0.01 for a, b in zip(old_box, new_box)):
                kind = "updated"
            else:
                kind = "same"
        out.append((did, kind, old_path, new_path))
    return len(disp), out


def main():
    n_disp, seen = classify()
    kinds = collections.Counter()
    by_model = collections.defaultdict(set)  # old model path -> kinds of its displays
    examples = collections.defaultdict(list)
    for did, kind, old_path, new_path in seen:
        if kind not in ("humanoid", "gone"):
            by_model[old_path].add(kind)
            if len(examples[kind]) < 25:
                examples[kind].append(f"{did}: {old_path} -> {new_path}")
        kinds[kind] += 1

    print(f"{n_disp} WotLK displays")
    for k, n in kinds.most_common():
        print(f"  {k:10} {n}")
    upgraded = sum(1 for ks in by_model.values() if ks & {"new-model", "updated"})
    print(f"{len(by_model)} distinct creature model files, {upgraded} with a newer version in retail")
    if "-v" in sys.argv:
        for k, ex in examples.items():
            print(f"\n{k}:")
            print("\n".join("  " + e for e in ex))


if __name__ == "__main__":
    main()
