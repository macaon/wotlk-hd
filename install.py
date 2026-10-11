"""Copy built patches into the game: out/patch-N.MPQ to <WoW>/Data/, out/patch-enUS-N.MPQ to Data/enUS/.

usage: install.py [n ...]    patch numbers (default: every one built in out/)
"""
import glob
import os
import re
import shutil
import sys

import build

WOW = os.environ.get("WOW_DIR", os.path.expanduser("~/Games/wotlk"))

if __name__ == "__main__":
    numbers = sys.argv[1:] or sorted({re.search(r"patch-(?:enUS-)?(\d+)\.MPQ$", p).group(1)
                                      for p in glob.glob(os.path.join(build.OUT, "patch-*[0-9].MPQ"))})
    for n in numbers:
        for src, dst in zip(build.patch_paths(n), ("Data", "Data/enUS")):
            if os.path.exists(src):
                shutil.copy(src, os.path.join(WOW, dst))
                print(f"{src} -> {os.path.join(WOW, dst)}")
