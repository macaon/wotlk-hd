"""BLP2 writing in the paletted form 3.3.5's character compositor reads.

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
        print("ok", len(out), "bytes")
