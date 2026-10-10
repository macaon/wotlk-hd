"""Patch a copy of the 3.3.5a (12340) Wow.exe: large-address-aware and a wider field of view.

usage: patch_exe.py [fov]    writes Wow-hd.exe next to Wow.exe

Large-address-aware lets the 32-bit client use 4 GB instead of 2 GB, which the HD models need.

FoV: the camera reads its default from a pi/2 constant at file offset 0x5E7588, the same spot
WowFovChanger patches (https://github.com/fosley/WowFovChanger). Without an argument the value
keeps the vertical view of 2.0 on 3440x1440 (picked by eye in game) and adjusts it for the
monitor's aspect ratio (gxResolution in WTF/Config.wtf).
"""
import math
import os
import re
import struct
import sys

WOW = os.environ.get("WOW_DIR", os.path.expanduser("~/Games/wotlk"))
SIZE_12340 = 7704216
FOV_OFFSET = 0x5E7588
PI_2 = struct.pack("<f", math.pi / 2)
FOV_REF, ASPECT_REF = 2.0, 3440 / 1440  # calibration: looks right in game on 3440x1440
LAA = 0x20


def aspect():
    try:
        cfg = open(os.path.join(WOW, "WTF", "Config.wtf")).read()
        w, h = re.search(r'SET gxResolution "(\d+)x(\d+)"', cfg).groups()
        return int(w) / int(h)
    except (OSError, AttributeError):
        return 16 / 9


def fov_for(a):
    """Same vertical view as FOV_REF at ASPECT_REF, wider or narrower horizontally."""
    return 2 * math.atan(math.tan(FOV_REF / 2) * a / ASPECT_REF)


def patch(exe, fov):
    d = bytearray(exe)
    if len(d) != SIZE_12340:
        sys.exit(f"Wow.exe is {len(d)} bytes, expected {SIZE_12340} (3.3.5a 12340)")
    if d[FOV_OFFSET:FOV_OFFSET + 4] != PI_2:
        sys.exit(f"unexpected bytes at FoV offset: {d[FOV_OFFSET:FOV_OFFSET + 4].hex()}")
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    flags = struct.unpack_from("<H", d, pe + 22)[0]
    struct.pack_into("<H", d, pe + 22, flags | LAA)
    struct.pack_into("<f", d, FOV_OFFSET, fov)
    return bytes(d)


def main():
    fov = float(sys.argv[1]) if len(sys.argv) > 1 else fov_for(aspect())
    src = os.path.join(WOW, "Wow.exe")
    out = os.path.join(WOW, "Wow-hd.exe")
    data = patch(open(src, "rb").read(), fov)
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out}: large-address-aware, FoV {fov:.4f} ({math.degrees(fov):.1f} deg)")


if __name__ == "__main__":
    assert abs(fov_for(ASPECT_REF) - FOV_REF) < 1e-6
    main()
