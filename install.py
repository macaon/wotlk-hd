"""Copy built patches into the game: out/patch-<name>.MPQ to <WoW>/Data/, out/patch-enUS-<name>.MPQ
to Data/enUS/ (numbered patches, and chars.py's one per race, loaded by name through dinput8.dll).

usage: install.py [name ...]    patch names: 6, dwarf, ... (default: every one built in out/)
"""
import glob
import os
import re
import shutil
import sys

import build

WOW = os.environ.get("WOW_DIR", os.path.expanduser("~/Games/wotlk"))

if __name__ == "__main__":
    built = sorted(glob.glob(os.path.join(build.OUT, "patch-*.MPQ")))
    names = set(sys.argv[1:])
    for src in built:
        name = re.search(r"patch-(?:enUS-)?(.+)\.MPQ$", os.path.basename(src)).group(1)
        if names and name not in names or not re.fullmatch(r"[0-9a-z]+", name):
            continue  # names with dots (patch-enUS-5.experiment.MPQ) are side builds: never installed
        dst = os.path.join(WOW, "Data", "enUS" if "-enUS-" in os.path.basename(src) else "")
        shutil.copy(src, dst)
        print(f"{src} -> {dst}")
