"""Pick the upgrades: every 3.3.5 creature model whose retail replacement has clearly more detail.

usage: plan.py              writes upgrades.json (read by build.py) and prints a summary
       plan.py --unlinked   lists newer retail versions no old display points at (dragonhawk ->
                            dragonhawk2); they need texture maps by hand, so they go in build.MANUAL

Candidates come from survey.py (a model's retail target is where most of its displays went). Kept
when the retail model's best skin has at least MIN_GAIN times the triangles of the 3.3.5 skin;
"updated in place" alone is not enough (retail felbat and snake are the same meshes).
"""
import collections
import json
import os
import struct

import fetch
import survey
from mpq import Client

MIN_GAIN = 1.5
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "upgrades.json")


def triangles(skin):
    return struct.unpack_from("<I", skin, 12)[0] // 3 if skin and skin[:4] == b"SKIN" else None


def main():
    _, seen = survey.classify()
    targets = collections.defaultdict(collections.Counter)
    for _, kind, old, new in seen:
        if kind in ("new-model", "updated") and old.startswith("creature/"):
            targets[old][new] += 1
    client = Client()
    upgrades, skipped = {}, collections.Counter()
    for old, counter in sorted(targets.items()):
        new = counter.most_common(1)[0][0]
        if new.startswith("character/"):
            skipped["retail uses a character model (humanoid track)"] += 1
            continue  # customizable models take materials and textures from elsewhere (naga)
        old_tris = triangles(client.read(old[:-3].replace("/", "\\") + "00.skin"))
        fid = fetch.fdid(new[:-3] + "00.skin")
        if not old_tris or not fid:
            skipped["no skin to compare"] += 1
            continue
        try:
            new_tris = triangles(fetch.get(fid))
        except OSError:
            skipped["download failed"] += 1
            continue
        if not new_tris or new_tris < old_tris * MIN_GAIN:
            skipped[f"under {MIN_GAIN}x triangles"] += 1
            continue
        name = old.rsplit("/", 1)[1][:-3]
        if name in upgrades:
            name = old[len("creature/"):-3].replace("/", "_")
        upgrades[name] = {"old": old, "new": new, "triangles": [old_tris, new_tris],
                          "displays": sum(counter.values())}
    with open(OUT, "w") as f:
        json.dump(upgrades, f, indent=1, sort_keys=True)
    print(f"{len(targets)} candidates, {len(upgrades)} upgrades -> {OUT}")
    for reason, n in skipped.most_common():
        print(f"  skipped {n}: {reason}")


def unlinked():
    """Old creature models without an upgrade whose name has a newer numbered version in retail
    that retail displays use, ranked by how many old displays would change.
    [(old displays, old path, new path, old triangles, new triangles, retail displays)]"""
    import csv
    _, seen = survey.classify()
    planned = {u["old"] for u in json.load(open(OUT)).values()} if os.path.exists(OUT) else set()
    old_displays = collections.Counter(old for _, kind, old, _ in seen
                                       if kind not in ("humanoid",) and old.startswith("creature/"))
    rm = {r["ID"]: int(r["FileDataID"]) for r in csv.DictReader(open(os.path.join(fetch.CACHE, "CreatureModelData.csv")))}
    used = collections.Counter(rm.get(r["ModelID"]) for r in csv.DictReader(open(os.path.join(fetch.CACHE, "CreatureDisplayInfo.csv"))))
    by_family = collections.defaultdict(list)
    names, _ = fetch._listfile()
    for fid, name in names.items():
        if name.startswith("creature/") and name.endswith(".m2") and used[fid]:
            base = name.rsplit("/", 1)[1][:-3]
            if base[-1:].isdigit():
                by_family[survey.family(name)].append((used[fid], name))
    client = Client()
    rows = []
    for old, n in old_displays.most_common():
        if old in planned or not by_family.get(survey.family(old)):
            continue
        uses, new = max(by_family[survey.family(old)])
        old_tris = triangles(client.read(old[:-3].replace("/", "\\") + "00.skin"))
        fid = fetch.fdid(new[:-3] + "00.skin")
        new_tris = triangles(fetch.get(fid)) if fid else None
        if old_tris and new_tris and new_tris >= old_tris * MIN_GAIN:
            rows.append((n, old, new, old_tris, new_tris, uses))
    return rows


if __name__ == "__main__":
    import sys
    if "--unlinked" in sys.argv:
        for n, old, new, a, b, uses in unlinked():
            print(f"{n:4} displays  {old:50} -> {new:50} {a:>6} -> {b:<6} (retail displays {uses})")
    else:
        main()
