"""Copy built patches into the game: out/patch-<name>.MPQ to <WoW>/Data/, out/patch-enUS-<name>.MPQ
to Data/enUS/ (numbered patches, and chars.py's one per race, loaded by name through dinput8.dll),
and the addon (addon/WotlkHD, the Video Options page for the client's effects) to Interface/AddOns/.

usage: install.py [name ...]    patch names: 6, dwarf, ...; default: the archives already installed
                                and chars.py's per-race ones (a new numbered patch needs its name:
                                out/ also holds old experiments, and everything in Data loads)
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
        if not names and not name.isalpha() and not os.path.exists(os.path.join(dst, os.path.basename(src))):
            continue
        shutil.copy(src, dst)
        print(f"{src} -> {dst}")
    addon = os.path.join(os.path.dirname(os.path.abspath(__file__)), "addon", "WotlkHD")
    dst = os.path.join(WOW, "Interface", "AddOns", "WotlkHD")
    shutil.copytree(addon, dst, dirs_exist_ok=True)
    print(f"{addon} -> {dst}")
