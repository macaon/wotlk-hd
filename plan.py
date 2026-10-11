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
SPLIT_GAIN = 1.01  # any denser: wolf_ghost and minifelreaver are the same meshes
# survey.py "reused" displays that really were given to another creature, not split off
REASSIGNED = {4, 64}  # crystal spider and sound test -> murloc2
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "upgrades.json")


def triangles(skin):
    return struct.unpack_from("<I", skin, 12)[0] // 3 if skin and skin[:4] == b"SKIN" else None


def gain(client, old, new, minimum=MIN_GAIN):
    """(old, new) skin0 triangles if the retail model is an upgrade, else the reason it is not."""
    old_tris = triangles(client.read(old[:-3].replace("/", "\\") + "00.skin"))
    fid = fetch.fdid(new[:-3] + "00.skin")
    if not old_tris or not fid:
        return "no skin to compare"
    try:
        new_tris = triangles(fetch.get(fid))
    except OSError:
        return "download failed"
    if not new_tris or new_tris < old_tris * minimum:
        return f"under {minimum}x triangles"
    return old_tris, new_tris


def main():
    _, seen = survey.classify()
    targets = collections.defaultdict(collections.Counter)
    for _, kind, old, new in seen:
        if kind in ("new-model", "updated") and old.startswith("creature/"):
            targets[old][new] += 1
    # Displays retail moved to a variant model of their own (molten giants: moltengiant, not the
    # mountaingiant2 the rest went to). survey.py calls them reused; they become upgrades of just
    # those displays, next to the old model.
    splits = collections.defaultdict(list)
    for did, kind, old, new in seen:
        if (kind == "reused" and old.startswith("creature/") and new.startswith("creature/")
                and did not in REASSIGNED):
            splits[(old, new)].append(did)
    client = Client()
    upgrades, skipped = {}, collections.Counter()

    def add(name, entry):
        if name in upgrades:
            name = entry["old"][len("creature/"):-3].replace("/", "_") + "_" + name
        upgrades[name] = entry

    for old, counter in sorted(targets.items()):
        new = counter.most_common(1)[0][0]
        if new.startswith("character/"):
            skipped["retail uses a character model (humanoid track)"] += 1
            continue  # customizable models take materials and textures from elsewhere (naga)
        g = gain(client, old, new)
        if isinstance(g, str):
            skipped[g] += 1
            continue
        add(old.rsplit("/", 1)[1][:-3], {"old": old, "new": new, "triangles": list(g),
                                          "displays": sum(counter.values())})
    for (old, new), dids in sorted(splits.items()):
        # the creature's own model in retail, even if not much denser (moltengiant: 1.27x)
        g = gain(client, old, new, SPLIT_GAIN)
        if isinstance(g, str):
            skipped[f"split: {g}"] += 1
            continue
        add(new.rsplit("/", 1)[1][:-3], {"old": old, "new": new, "triangles": list(g),
                                          "displays": len(dids), "only": sorted(dids)})
    with open(OUT, "w") as f:
        json.dump(upgrades, f, indent=1, sort_keys=True)
    n_splits = sum("only" in u for u in upgrades.values())
    print(f"{len(targets)} candidates, {len(upgrades)} upgrades ({n_splits} split off) -> {OUT}")
    for reason, n in skipped.most_common():
        print(f"  skipped {n}: {reason}")


def unlinked():
    """Old creature models without an upgrade whose name has a newer numbered version in retail
    that retail displays use, ranked by how many old displays would change.
    [(old displays, old path, new path, old triangles, new triangles, retail displays)]"""
    import csv
    _, seen = survey.classify()
    planned = {u["old"] for u in json.load(open(OUT)).values() if "only" not in u} if os.path.exists(OUT) else set()
    old_displays = collections.Counter(old for _, kind, old, _ in seen
                                       if kind not in ("humanoid",) and old.startswith("creature/"))
    rm = {r["ID"]: int(r["FileDataID"]) for r in csv.DictReader(open(fetch.table("CreatureModelData")))}
    used = collections.Counter(rm.get(r["ModelID"]) for r in csv.DictReader(open(fetch.table("CreatureDisplayInfo"))))
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
