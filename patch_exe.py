"""Patch a copy of the 3.3.5a (12340) Wow.exe: large-address-aware and a wider field of view.

usage: patch_exe.py [fov]                 writes Wow-hd.exe next to Wow.exe
       patch_exe.py --characters [fov]    writes Wow-hdchar.exe: the above plus HD character textures
       patch_exe.py --emit-header         writes client/patches.h: those character patches for
                                          dinput8.dll, which applies them to a Wow-hd.exe in memory

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
# The M2 batch draw (three paths after 0x8203b0) passes a 32-bit index start but fills it from the
# submesh's u16 start alone; retail adds level (the u16 at +2) as the high word, and HD character
# skins need it (the blood elves have 113k-155k indices). 3.3.5's own skins have level 0 everywhere
# (6706 submeshes checked), so they draw as before. (site, original bytes, target register code)
INDEX_SITES = [(0x8205D9, "0fb7560a0fb77608", "esi"), (0x820662, "0fb7560a0fb77608", "esi"),
               (0x8206DA, "0fb74e0a0fb75608", "edx")]
# The hardware-skinning batch draw (0x820b9c, submesh in eax) stores the u16 start alone too; its
# detour stores start | level << 16. (site, original bytes, cave body)
# Every cave keeps the flags (pushfd/popfd): 0x820b9c sits between a cmp and the je that uses it,
# and an earlier version without them switched skinning paths and broke world objects.
# The real limit: when a skin's GPU index buffer is built (FUN_008360a0) the client copies each
# submesh's triangles from its u16 start in the file (level ignored) and writes the submesh's new
# start in its own buffer back as u16 (truncated past 65535). These two detours read start | level
# << 16 and keep the new start's high word in the copy's level field, which the draw detours add.
REBUILD_SITES = [
    # movzx ebx,[ebx+ecx+8]; add edx,ecx  ->  ebx = start | level << 16
    (0x83619F, "0fb75c0b0803d1", "50" "0fb7440b02" "c1e010" "0fb75c0b08" "0bd8" "58" "03d1"),
    # mov [edx+8],bx; movzx edx,[edx+0xa]  ->  also level = start >> 16
    (0x836240, "66895a080fb7520a", "66895a08" "53" "c1eb10" "66895a02" "5b" "0fb7520a"),
]
STORE_SITES = [
    (0x820B9C, "0fb750088955d4", "0fb75008" "50" "0fb74002" "c1e010" "0bd0" "58" "8955d4"),
]
INDEX_CAVES = {  # count load, then start | level << 16, keeping the scratch register
    "esi": "0fb7560a" "51" "0fb74e02" "c1e110" "0fb77608" "0bf1" "59",
    "edx": "0fb74e0a" "50" "0fb74602" "c1e010" "0fb75608" "0bd0" "58",
}
SHIFT_SITE, SHIFT_BYTES = 0x4F1B7A, "b909000000"
# CM2Model::SetGeometryVisible (0x82c7c0) compares the submesh id as a u32, level included: with
# level set (starts past 65535) a geoset never matched a hide/show range and stayed visible (robes,
# cuffs and bulky belts on naked characters). mov eax,[ebp-4]; mov eax,[eax+edx] -> add edx,[ebp-4];
# movzx eax,word [edx] (edx is reloaded at the loop head and rewritten before its next use).
ID_SITE, ID_BYTES, ID_PATCH = 0x82C7EA, "8b45fc8b0410", "0355fc0fb702"


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
    return b"\xe9" + struct.pack("<I", (dst - (src + 5)) & 0xFFFFFFFF)


CAVE = 0xDFD000  # first page past the stock image: Wow-hdchar.exe's .hdchar section


def character_patches(put, cave=CAVE):
    """The composite as 1024x512 in retail's HD layout (see REGIONS) and 32-bit index starts:
    put(va, new bytes, expected original bytes) for each site; returns the code cave for `cave`."""
    table = b"".join(struct.pack("<4i", *r) for r in REGIONS)
    code = bytearray(table)
    # region initializer: copy the table (push esi/edi; mov esi; mov edi; mov ecx,40; rep movsd)
    put(REGION_INIT, b"\x56\x57\xbe" + struct.pack("<I", cave) + b"\xbf" + struct.pack("<I", REGION_TABLE)
        + b"\xb9\x28\x00\x00\x00\xf3\xa5\x5f\x5e\xc3", bytes.fromhex("b800010000"))
    put(LEVEL_SITE, b"\xb8" + struct.pack("<I", LEVEL) + b"\x90" * 7, bytes.fromhex(LEVEL_BYTES))
    put(SHIFT_SITE, b"\xb9" + struct.pack("<I", LEVEL), bytes.fromhex(SHIFT_BYTES))
    put(ID_SITE, bytes.fromhex(ID_PATCH), bytes.fromhex(ID_BYTES))
    for site, original in SIZE_SITES.items():
        original = bytes.fromhex(original)
        at = cave + len(code)
        body = original[:-2] + b"\x68" + struct.pack("<I", COMPOSITE_H) + b"\x68" + struct.pack("<I", COMPOSITE_W)
        code += body + jmp(at + len(body), site + len(original))
        put(site, jmp(site, at) + b"\x90" * (len(original) - 5), original)
    for site, skip, cont in DXT_SITES:
        at = cave + len(code)
        body = bytearray(b"\x89\x45\xe4\x85\xc0\x0f\x8e")  # mov [ebp-0x1c],eax; test; jle skip
        body += struct.pack("<I", (skip - (at + len(body) + 4)) & 0xFFFFFFFF)
        body += b"\x50\xd1\xf8\x75\x01\x40\x89\x45\xec\x58"  # push; sar 1; jnz; inc; mov [ebp-0x14]; pop
        code += body + jmp(at + len(body), cont)
        put(site, jmp(site, at) + b"\x90" * 3, bytes.fromhex(DXT_BYTES))
    for site, original, reg in INDEX_SITES:
        at = cave + len(code)
        body = b"\x9c" + bytes.fromhex(INDEX_CAVES[reg]) + b"\x9d"  # pushfd ... popfd
        code += body + jmp(at + len(body), site + 8)
        put(site, jmp(site, at) + b"\x90" * 3, bytes.fromhex(original))
    for site, original, cave_body in REBUILD_SITES + STORE_SITES:
        original = bytes.fromhex(original)
        at = cave + len(code)
        body = b"\x9c" + bytes.fromhex(cave_body) + b"\x9d"
        code += body + jmp(at + len(body), site + len(original))
        put(site, jmp(site, at) + b"\x90" * (len(original) - 5), original)
    assert len(code) <= 0x1000
    return bytes(code)


def patch_characters(exe):
    """Wow-hdchar.exe: character_patches written into the exe, the cave as a new section."""
    pe = Pe(exe)
    cave = pe.add_section(b".hdchar", 0x1000)
    code = character_patches(lambda va, data, expect: pe.write(va, data, expect=expect), cave)
    pe.d[pe.offset(cave):pe.offset(cave) + len(code)] = code
    return bytes(pe.d)


def emit_header(path):
    """client/patches.h: character_patches as data for dinput8.dll, which applies them in memory.
    The DLL's cave lands wherever VirtualAlloc puts it, so the patches are generated for two cave
    addresses and every dword that moves with the cave becomes a fixup (+1 or -1 times the shift)."""
    def gen(cave):
        sites = []
        return character_patches(lambda va, data, expect: sites.append((va, expect, data)), cave), sites
    shift = 0x01010101  # every byte of a moved dword changes, so its first changed byte is its start
    code, sites = gen(CAVE)
    code_b, sites_b = gen(CAVE + shift)

    def fixups(a, b, where):
        out, i = [], 0
        while i < len(a):
            if a[i] != b[i]:
                d = (struct.unpack_from("<I", b, i)[0] - struct.unpack_from("<I", a, i)[0]) & 0xFFFFFFFF
                assert d in (shift, -shift & 0xFFFFFFFF), (where, i)
                out.append((where, i, 1 if d == shift else -1))
                i += 4
            else:
                i += 1
        return out
    fix = fixups(code, code_b, 0xFFFFFFFF)
    for n, ((_, _, new), (_, _, new_b)) in enumerate(zip(sites, sites_b)):
        fix += fixups(new, new_b, n)
    c_bytes = lambda b: ", ".join(f"0x{x:02x}" for x in b)
    lines = ["/* Generated by patch_exe.py --emit-header; do not edit. */",
             f"#define HD_CAVE 0x{CAVE:08X}u  /* the address the bytes below were generated for */",
             f"static const unsigned char hd_cave[] = {{{c_bytes(code)}}};",
             "struct hd_site { unsigned va, orig_len, patch_len; const unsigned char *orig, *patch; };",
             "struct hd_fix { unsigned site, offset; int sign; };  /* site ~0u: in the cave */"]
    for i, (va, orig, new) in enumerate(sites):  # orig may be shorter: REGION_INIT checks 5 bytes
        lines.append(f"static const unsigned char hd_o{i}[] = {{{c_bytes(orig)}}};")
        lines.append(f"static const unsigned char hd_p{i}[] = {{{c_bytes(new)}}};")
    lines.append("static const struct hd_site hd_sites[] = {")
    for i, (va, orig, new) in enumerate(sites):
        lines.append(f"    {{0x{va:08X}u, {len(orig)}u, {len(new)}u, hd_o{i}, hd_p{i}}},")
    lines.append("};")
    lines.append("static const struct hd_fix hd_fixes[] = {")
    lines += [f"    {{0x{w:X}u, {o}u, {sg}}}," for w, o, sg in fix]
    lines.append("};")
    open(path, "w").write("\n".join(lines) + "\n")
    print(f"wrote {path}: {len(sites)} sites, {len(code)} cave bytes, {len(fix)} fixups")


def main():
    args = sys.argv[1:]
    if "--emit-header" in args:
        emit_header(os.path.join(os.path.dirname(os.path.abspath(__file__)), "client", "patches.h"))
        return
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
