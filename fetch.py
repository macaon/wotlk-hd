"""Retail files by FileDataID and DB2 tables as CSV from wago.tools, cached per build in cache/<build>/.

usage: fetch.py <fdid | path> [...]    prints where each file landed

Everything comes from one build (BUILD, live retail). wago.tools' default without a build mixes
products: its tables were the 12.1.5 PTR, and boar2.m2 came from a different export than its skins
(10696 vertices against skins for 10821), which scrambled its triangles.

ponytail: relies on wago.tools; a Blizzard CDN reader (TACT encoding/root/archive indexes) is
the fallback if it goes away.
"""
import os
import sys
import time
import urllib.error
import urllib.request

BUILD = os.environ.get("WOW_BUILD", "12.1.0.69933")  # live retail, 2026-10-11
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")
BUILD_CACHE = os.path.join(CACHE, BUILD)
_names = None
_ids = None


def _listfile():
    global _names, _ids
    if _names is None:
        _names, _ids = {}, {}
        with open(os.path.join(CACHE, "listfile.csv"), encoding="utf-8") as f:
            for line in f:
                fid, _, name = line.rstrip("\n").partition(";")
                _names[int(fid)] = name
                _ids[name] = int(fid)
    return _names, _ids


def name(fdid):
    return _listfile()[0].get(fdid)


def fdid(path):
    return _listfile()[1].get(path.lower().replace("\\", "/"))


def get(fid):
    """The file's bytes, downloaded once."""
    return _download(f"https://wago.tools/api/casc/{fid}?download&version={BUILD}",
                     os.path.join(BUILD_CACHE, "files", str(fid)))


def prefetch(fids, workers=8):
    """Download files in parallel (wago.tools takes seconds per file)."""
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(workers) as pool:
        for _ in pool.map(lambda f: (get(f), None)[1] if f else None, set(fids)):
            pass


def prefetch_models(fids):
    """Models, then everything they reference by FileDataID (skins, skeleton, anims, textures)."""
    from m2 import M2
    prefetch(fids)
    deps = []
    for f in fids:
        try:
            m = M2(get(f))
        except (OSError, ValueError):
            continue
        for chunk in ("SFID", "TXID", "SKID"):
            deps += m.u32s(chunk)
        deps += m.u32s("AFID")[1::2]  # (anim id, sub id) u16 pairs then the fdid
    prefetch(deps)


def table(name):
    """Path of DB2 table `name` as CSV, downloaded once."""
    path = os.path.join(BUILD_CACHE, f"{name}.csv")
    _download(f"https://wago.tools/db2/{name}/csv?build={BUILD}", path)
    return path


def _download(url, path):
    if os.path.exists(path):
        return open(path, "rb").read()
    req = urllib.request.Request(url, headers={"User-Agent": "wotlk-hd (private)"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            break
        except urllib.error.HTTPError as e:
            if e.code < 500 or attempt == 5:
                raise OSError(f"fetching {url}: HTTP {e.code}") from e
        except OSError:
            if attempt == 5:
                raise
        time.sleep(2 ** attempt)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "wb") as f:
        f.write(data)
    os.replace(path + ".tmp", path)
    return data


if __name__ == "__main__":
    for a in sys.argv[1:]:
        fid = int(a) if a.isdigit() else fdid(a)
        if fid is None:
            sys.exit(f"{a}: not in the listfile")
        get(fid)
        print(fid, name(fid), os.path.join(BUILD_CACHE, "files", str(fid)))
