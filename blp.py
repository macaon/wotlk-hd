"""BLP2 writing in the paletted form 3.3.5's character compositor reads, and DXT5 or raw BGRA for UI art.

usage: blp.py <in.blp|png> <out.blp>    re-encodes one texture (self-test without arguments)

3.3.5's own character textures are BLP2, compression 1 (256-colour palette), alpha depth 0 or 8,
alpha type 8, with every mip level: the compositor copies regions from the source mip whose size
matches, and draws a texture it cannot read (retail's DXT) as plain green.
"""
import io
import struct
import sys

from PIL import Image


def mips(im):
    out = [im]
    while im.width > 1 or im.height > 1:
        im = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)
        out.append(im)
    return out[:16]


def encode(im):
    """BLP2 bytes for a PIL image: paletted, 8-bit alpha when it has any, all mips."""
    im = im.convert("RGBA")
    alpha = im.getextrema()[3][0] < 255
    levels = mips(im)
    paletted = levels[0].convert("RGB").quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = paletted.getpalette()[:768]
    palette += [0] * (768 - len(palette))
    data = []
    for level in levels:
        p = paletted if level is levels[0] else level.convert("RGB").quantize(palette=paletted, dither=Image.Dither.NONE)
        data.append(p.tobytes() + (level.getchannel("A").tobytes() if alpha else b""))
    header = struct.pack("<4sIBBBBII", b"BLP2", 1, 1, 8 if alpha else 0, 8, 1, im.width, im.height)
    offsets, sizes, pos = [], [], len(header) + 16 * 4 * 2 + 256 * 4
    for d in data:
        offsets.append(pos)
        sizes.append(len(d))
        pos += len(d)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    pal = b"".join(struct.pack("<BBBB", palette[i * 3 + 2], palette[i * 3 + 1], palette[i * 3], 0) for i in range(256))
    return header + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + pal + b"".join(data)


def encode_dxt5(im):
    """BLP2 bytes for a PIL image: DXT5 (alpha type 7, as 3.3.5's own UI art), all mips."""
    data = []
    for level in mips(im.convert("RGBA")):
        if level.width < 4 or level.height < 4:  # DXT blocks are 4x4; the small mips are padded
            padded = Image.new("RGBA", (max(4, level.width), max(4, level.height)))
            padded.paste(level)
            level = padded
        buf = io.BytesIO()
        level.save(buf, "DDS", pixel_format="DXT5")
        data.append(buf.getvalue()[128:])
    header = struct.pack("<4sIBBBBII", b"BLP2", 1, 2, 8, 7, 1, im.width, im.height)
    offsets, sizes, pos = [], [], len(header) + 16 * 4 * 2 + 256 * 4
    for d in data:
        offsets.append(pos)
        sizes.append(len(d))
        pos += len(d)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    return header + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + bytes(1024) + b"".join(data)


def encode_raw(im):
    """BLP2 bytes for a PIL image: uncompressed BGRA (compression 3, as retail's HUD art and 3.3.5's
    UI-PAIDCHARACTERCUSTOMIZATION-BUTTON), all mips; for art DXT5's 4x4 blocks garble."""
    data = [level.tobytes("raw", "BGRA") for level in mips(im.convert("RGBA"))]
    header = struct.pack("<4sIBBBBII", b"BLP2", 1, 3, 8, 2, 1, im.width, im.height)
    offsets, sizes, pos = [], [], len(header) + 16 * 4 * 2 + 256 * 4
    for d in data:
        offsets.append(pos)
        sizes.append(len(d))
        pos += len(d)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    return header + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + bytes(1024) + b"".join(data)


def decode(blp_bytes):
    """Mip 0 of a BLP2 as an RGBA image, including retail's uncompressed BGRA (compression 3)."""
    if blp_bytes[8] == 3:
        w, h = struct.unpack_from("<2I", blp_bytes, 12)
        off = struct.unpack_from("<I", blp_bytes, 20)[0]
        return Image.frombytes("RGBA", (w, h), blp_bytes[off:off + w * h * 4], "raw", "BGRA")
    im = Image.open(io.BytesIO(blp_bytes))
    im.load()
    return im.convert("RGBA")


def reencode(blp_bytes):
    im = Image.open(io.BytesIO(blp_bytes))
    im.load()
    return encode(im)


if __name__ == "__main__":
    if len(sys.argv) == 3:
        open(sys.argv[2], "wb").write(reencode(open(sys.argv[1], "rb").read()))
    else:
        src = Image.new("RGBA", (64, 32), (200, 100, 50, 255))
        src.putpixel((3, 3), (10, 20, 30, 128))
        out = encode(src)
        back = Image.open(io.BytesIO(out))
        back.load()
        assert back.size == (64, 32) and struct.unpack_from("<4sIBBBB", out)[2:5] == (1, 8, 8)
        # Pillow ignores 8-bit alpha in paletted BLP2 (3.3.5's own files read back alpha 0 too),
        # so check the layout: mip 0 is the indices and then one alpha byte per pixel.
        offset, size = struct.unpack_from("<I", out, 20)[0], struct.unpack_from("<I", out, 84)[0]
        assert size == 64 * 32 * 2 and out[offset + 64 * 32 + 3 * 64 + 3] == 128
        dxt = encode_dxt5(src)
        assert all(abs(a - b) < 8 for a, b in zip(decode(dxt).getpixel((0, 0)), (200, 100, 50, 255)))
        raw = struct.pack("<4sIBBBBII", b"BLP2", 1, 3, 8, 8, 0, 2, 1) + struct.pack("<16I", 1172, *[0] * 15) + \
            bytes(64 + 1024) + bytes([1, 2, 3, 4, 5, 6, 7, 8])
        assert decode(raw).getpixel((1, 0)) == (7, 6, 5, 8)
        assert decode(encode_raw(src)).getpixel((3, 3)) == (10, 20, 30, 128)
        print("ok", len(out), len(dxt), "bytes")
