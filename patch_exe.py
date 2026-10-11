"""Patch a copy of the 3.3.5a (12340) Wow.exe: large-address-aware and a wider field of view.

usage: patch_exe.py [fov]                 writes Wow-hd.exe next to Wow.exe
       patch_exe.py --characters [fov]    writes Wow-hdchar.exe: the above plus HD character textures

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


# HD character textures. 3.3.5 composites a character's skin, face, hair and armour into one
# square texture of 1 << level pixels (level 6..9) with a fixed table of ten regions (README,
# "Character models"). Retail HD models expect layout 2 of CharComponentTextureLayouts: 2048x1024,
# body regions as in 3.3.5 on the left half, the face on the whole right half. At half scale that
# is 1024x512 with body regions exactly where 3.3.5's 512 composite has them, so old armour
# textures still copy 1:1 (the blitter never resamples, it picks a source mip). The patch makes
# the composite 1024x512 with that table.
COMPOSITE_W, COMPOSITE_H, LEVEL = 1024, 512, 10
REGIONS = [  # x, y, w, h in 3.3.5's region order
    (0, 0, 256, 128), (0, 128, 256, 128), (0, 256, 256, 64),            # arm upper, lower, hand
    (256, 0, 256, 128), (256, 128, 256, 64), (256, 192, 256, 128),      # torso upper, lower, leg upper
    (256, 320, 256, 128), (256, 448, 256, 64),                          # leg lower, foot
    (512, 0, 512, 512), (512, 0, 512, 512),                             # face upper, face lower
]
REGION_INIT, REGION_TABLE = 0x9C8F30, 0xB6B928  # static initializer filling the table; the table
# Each site loads the size and pushes it twice as (height, width) for a texture create, free or
# dirty rect; the detour pushes 512 and 1024 instead. Bytes: from the load through both pushes.
SIZE_SITES = {
    0x4E9519: "a1fcb5b6006a015050", 0x4EE173: "a1fcb5b6006a015050", 0x4EFF6F: "a1fcb5b60057515050",
    0x4F101A: "a1fcb5b6005050", 0x4F10B8: "a1fcb5b6005050", 0x4F1864: "a1fcb5b6008b0e5050",
    0x4F18A0: "a1fcb5b6008b56045050", 0x4F1E33: "a1fcb5b6005050", 0x4F1E6D: "a1fcb5b6005050",
    0x4F1E92: "a1fcb5b6005050", 0x4F236E: "a1fcb5b6005050", 0x4F2390: "a1fcb5b6005050",
    0x4F23B1: "a1fcb5b6005050",
}
# DXT compression of the composite (two copies of the loop): size/4 blocks per row and as many
# rows; rows become max(1, width/8). (site, skip-the-loop target, continue)
DXT_SITES = [(0x4E9C1C, 0x4E9C56, 0x4E9C24), (0x4E9CDC, 0x4E9D16, 0x4E9CE4)]
DXT_BYTES = "8945e47e358945ec"  # mov [ebp-0x1c],eax; jle; mov [ebp-0x14],eax
# CCharacterComponent::Initialize: drop the level caps (jne; cmp eax,8; jbe; mov eax,8 -> mov
# eax,10), and shift the region table by 10 - level instead of 9 - level.
LEVEL_SITE, LEVEL_BYTES = 0x4F1B60, "750a83f8087605b808000000"
SHIFT_SITE, SHIFT_BYTES = 0x4F1B7A, "b909000000"
# Not patched: the batch draws take a submesh's index start as u16 and ignore level (the high word
# retail adds). Adding it in the draw paths (0x8205d9, 0x820662, 0x8206da, 0x820b9c) broke world
# objects (3.3.5 seems to use that field at run time) and the HD heads still drew garbage, so skins
# stay under index 65536 instead (convert.select_geosets).


class Pe:
    def __init__(self, data):
        self.d = bytearray(data)
        self.pe = struct.unpack_from("<I", self.d, 0x3C)[0]
        self.opt = self.pe + 24
        self.base = struct.unpack_from("<I", self.d, self.opt + 28)[0]
        self.sections = self.opt + struct.unpack_from("<H", self.d, self.pe + 20)[0]

    def section_rows(self):
        n = struct.unpack_from("<H", self.d, self.pe + 6)[0]
        return [struct.unpack_from("<8s4I", self.d, self.sections + i * 40) for i in range(n)]

    def offset(self, va):
        for _, vsize, rva, rsize, raw in self.section_rows():
            if rva <= va - self.base < rva + max(vsize, rsize):
                return raw + va - self.base - rva
        raise ValueError(f"{va:#x} is in no section")

    def write(self, va, data, expect=None):
        o = self.offset(va)
        if expect is not None and self.d[o:o + len(expect)] != expect:
            sys.exit(f"unexpected bytes at {va:#x}: {self.d[o:o + len(expect)].hex()}")
        self.d[o:o + len(data)] = data

    def add_section(self, name, size):
        """A new readable, executable section at the end; returns its virtual address."""
        rows = self.section_rows()
        n = len(rows)
        if self.sections + (n + 1) * 40 > rows[0][4]:
            sys.exit("no room for another section header")
        sect_align, file_align = struct.unpack_from("<II", self.d, self.opt + 32)
        rva = max(r[2] + r[1] for r in rows)
        rva = -(-rva // sect_align) * sect_align
        raw = -(-len(self.d) // file_align) * file_align
        rsize = -(-size // file_align) * file_align
        self.d += bytes(raw + rsize - len(self.d))
        struct.pack_into("<8s4I12xI", self.d, self.sections + n * 40, name, size, rva, rsize, raw,
                         0x60000020)  # code, execute, read
        struct.pack_into("<H", self.d, self.pe + 6, n + 1)
        struct.pack_into("<I", self.d, self.opt + 56, -(-(rva + size) // sect_align) * sect_align)
        return self.base + rva


def jmp(src, dst):
    return b"\xe9" + struct.pack("<i", dst - (src + 5))


def patch_characters(exe):
    """The composite as 1024x512 in retail's HD layout (see REGIONS)."""
    pe = Pe(exe)
    cave = pe.add_section(b".hdchar", 0x1000)
    table = b"".join(struct.pack("<4i", *r) for r in REGIONS)
    code = bytearray(table)
    # region initializer: copy the table (push esi/edi; mov esi; mov edi; mov ecx,40; rep movsd)
    pe.write(REGION_INIT, b"\x56\x57\xbe" + struct.pack("<I", cave) + b"\xbf" + struct.pack("<I", REGION_TABLE)
             + b"\xb9\x28\x00\x00\x00\xf3\xa5\x5f\x5e\xc3", expect=bytes.fromhex("b800010000"))
    pe.write(LEVEL_SITE, b"\xb8" + struct.pack("<I", LEVEL) + b"\x90" * 7, expect=bytes.fromhex(LEVEL_BYTES))
    pe.write(SHIFT_SITE, b"\xb9" + struct.pack("<I", LEVEL), expect=bytes.fromhex(SHIFT_BYTES))
    for site, original in SIZE_SITES.items():
        original = bytes.fromhex(original)
        at = cave + len(code)
        body = original[:-2] + b"\x68" + struct.pack("<I", COMPOSITE_H) + b"\x68" + struct.pack("<I", COMPOSITE_W)
        code += body + jmp(at + len(body), site + len(original))
        pe.write(site, jmp(site, at) + b"\x90" * (len(original) - 5), expect=original)
    for site, skip, cont in DXT_SITES:
        at = cave + len(code)
        body = bytearray(b"\x89\x45\xe4\x85\xc0\x0f\x8e")  # mov [ebp-0x1c],eax; test; jle skip
        body += struct.pack("<i", skip - (at + len(body) + 4))
        body += b"\x50\xd1\xf8\x75\x01\x40\x89\x45\xec\x58"  # push; sar 1; jnz; inc; mov [ebp-0x14]; pop
        code += body + jmp(at + len(body), cont)
        pe.write(site, jmp(site, at) + b"\x90" * 3, expect=bytes.fromhex(DXT_BYTES))
    assert len(code) <= 0x1000
    pe.d[pe.offset(cave):pe.offset(cave) + len(code)] = code
    return bytes(pe.d)


def main():
    args = sys.argv[1:]
    characters = "--characters" in args
    args = [a for a in args if a != "--characters"]
    fov = float(args[0]) if args else fov_for(aspect())
    src = os.path.join(WOW, "Wow.exe")
    out = os.path.join(WOW, "Wow-hdchar.exe" if characters else "Wow-hd.exe")
    data = patch(open(src, "rb").read(), fov)
    if characters:
        data = patch_characters(data)
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out}: large-address-aware, FoV {fov:.4f} ({math.degrees(fov):.1f} deg)"
          + (f", {COMPOSITE_W}x{COMPOSITE_H} character textures" if characters else ""))


if __name__ == "__main__":
    assert abs(fov_for(ASPECT_REF) - FOV_REF) < 1e-6
    main()
