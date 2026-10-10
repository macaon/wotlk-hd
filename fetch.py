"""Retail files by FileDataID from wago.tools, cached in cache/files/.

usage: fetch.py <fdid | path> [...]    prints where each file landed

ponytail: relies on wago.tools; a Blizzard CDN reader (TACT encoding/root/archive indexes) is
the fallback if it goes away.
"""
import os
import sys
import time
import urllib.error
import urllib.request

CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")
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
    path = os.path.join(CACHE, "files", str(fid))
    if os.path.exists(path):
        return open(path, "rb").read()
    req = urllib.request.Request(f"https://wago.tools/api/casc/{fid}?download",
                                 headers={"User-Agent": "wotlk-hd (private)"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            break
        except urllib.error.HTTPError as e:
            if e.code < 500 or attempt == 5:
                raise OSError(f"fetching {fid}: HTTP {e.code}") from e
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
        print(fid, name(fid), os.path.join(CACHE, "files", str(fid)))
