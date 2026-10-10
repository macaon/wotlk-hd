"""M2 model reading: the MD20 header (3.3.5 and later) and the chunks around it in MD21 files.

usage: m2.py <file.m2>...    prints a summary
"""
import struct
import sys

# MD20 header arrays (count, offset) in order, from 0x08. The 3.3.5 (v264) layout, unchanged
# since: later versions only add chunks around it. (Field names follow wowdev / wow.export.)
ARRAYS = [
    (0x08, "name"), (0x14, "global_loops"), (0x1C, "sequences"), (0x24, "sequence_lookup"),
    (0x2C, "bones"), (0x34, "key_bone_lookup"), (0x3C, "vertices"),
    (0x48, "colors"), (0x50, "textures"), (0x58, "texture_weights"), (0x60, "texture_transforms"),
    (0x68, "replaceable_texture_lookup"), (0x70, "materials"), (0x78, "bone_lookup"),
    (0x80, "texture_lookup"), (0x88, "texture_unit_lookup"), (0x90, "transparency_lookup"),
    (0x98, "texture_transform_lookup"), (0xD8, "collision_indices"), (0xE0, "collision_positions"),
    (0xE8, "collision_normals"), (0xF0, "attachments"), (0xF8, "attachment_lookup"),
    (0x100, "events"), (0x108, "lights"), (0x110, "cameras"), (0x118, "camera_lookup"),
    (0x120, "ribbons"), (0x128, "particles"),
]
FLAG_COMBINER_COMBOS = 0x08  # a texture_combiner_combos array follows the header at 0x130
HEADER_SIZE = 0x130


class M2:
    def __init__(self, data):
        self.chunks = {}
        if data[:4] == b"MD21":
            pos = 0
            while pos + 8 <= len(data):
                cid, size = struct.unpack_from("<4sI", data, pos)
                self.chunks[cid.decode("latin-1")] = data[pos + 8:pos + 8 + size]
                pos += 8 + size
            self.md20 = self.chunks.pop("MD21")
        elif data[:4] == b"MD20":
            self.md20 = data
        else:
            raise ValueError(f"not an M2: {data[:4]!r}")
        d = self.md20
        self.version, = struct.unpack_from("<I", d, 4)
        self.flags, = struct.unpack_from("<I", d, 0x10)
        self.views, = struct.unpack_from("<I", d, 0x44)
        self.arrays = {name: struct.unpack_from("<II", d, off) for off, name in ARRAYS}
        if self.flags & FLAG_COMBINER_COMBOS:
            self.arrays["texture_combiner_combos"] = struct.unpack_from("<II", d, HEADER_SIZE)

    def count(self, name):
        return self.arrays[name][0]

    def name(self):
        n, off = self.arrays["name"]
        return self.md20[off:off + n].rstrip(b"\0").decode("latin-1")

    def u32s(self, chunk):
        c = self.chunks.get(chunk, b"")
        return list(struct.unpack(f"<{len(c) // 4}I", c))

    def textures(self):
        """(type, flags, name or None) per texture slot."""
        n, off = self.arrays["textures"]
        out = []
        for i in range(n):
            ttype, flags, ln, lo = struct.unpack_from("<4I", self.md20, off + i * 16)
            name = self.md20[lo:lo + ln].rstrip(b"\0").decode("latin-1") if ln else None
            out.append((ttype, flags, name))
        return out

    def sequences(self):
        """(id, variation, flags) per sequence. Flag 0x20: data inside the M2; 0x40: alias."""
        n, off = self.arrays["sequences"]
        return [struct.unpack_from("<HHxxxxxxxxI", self.md20, off + i * 64) for i in range(n)]

    def materials(self):
        n, off = self.arrays["materials"]
        return [struct.unpack_from("<HH", self.md20, off + i * 4) for i in range(n)]


def summary(path, data):
    m = M2(data)
    out = [f"{path}: {m.name()} v{m.version} flags {m.flags:#x} views {m.views}",
           f"  chunks {sorted(m.chunks)}",
           "  " + " ".join(f"{k}={m.count(k)}" for k in
                           ("vertices", "bones", "sequences", "textures", "materials", "attachments",
                            "events", "lights", "cameras", "ribbons", "particles"))]
    if "SKID" in m.chunks:
        out.append(f"  skeleton file {m.u32s('SKID')[0]}")
    txid = m.u32s("TXID")
    for i, (t, f, n) in enumerate(m.textures()):
        out.append(f"  tex {i}: type {t} flags {f:#x} {n or ''}{' fdid ' + str(txid[i]) if i < len(txid) and txid[i] else ''}")
    blend = sorted({b for _, b in m.materials()})
    out.append(f"  blend modes {blend}")
    return "\n".join(out)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(summary(p, open(p, "rb").read()))
