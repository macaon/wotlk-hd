"""Convert a retail (MD21, v272-274) creature model to a 3.3.5 (MD20, v264) one.

The MD20 header and most structs are unchanged since 3.3.5 (see m2.py), so this lifts the MD20
out of its chunk and fixes what 3.3.5 reads differently. Everything was checked against 3.3.5's
own files and Wow.exe (12340); see README.md "Converter notes".

Submeshes over 64 bones are split. Refused (ConvertError) rather than half-converted: .skel-based
models and more than 65535 vertices.
"""
import struct

from m2 import M2

VERSION_WOTLK = 264
MAX_BONES_PER_SUBMESH = 64  # the most any 3.3.5 creature skin uses (boneCountMax)
MAX_ANIM_ID = 505           # highest id in 3.3.5's AnimationData.dbc

# Header flags 3.3.5 knows: tilt x/y, 0x4 (unknown, set by many 3.3.5 models), combiner combos.
MODEL_FLAGS = 0x0F
SEQ_FLAGS = 0x7F            # later bits (0x80, 0x800: chunked/lowpriority anims) are newer
MATERIAL_FLAGS = 0x1F       # unlit, unfogged, two-sided, billboard, no z-write
BATCH_FLAGS = 0x7F
BLEND_ADD = 4               # retail 7 (BM_BLEND_ADD) has no 3.3.5 equivalent; additive is closest

# texture_unit_lookup we write: index 0 -> UV0 + env (the 3.3.5 creature default (0, -1)),
# index 2 -> UV0 + UV1. A batch's coord combo points at the first of its texture's entries.
TEXTURE_UNITS = (0, -1, 0, 1)
COORD_T1_ENV, COORD_T1_T2 = 0, 2

# Shader effects selected with 0x8000: Wow.exe 12340 (0x836c90) accepts only 1..3, where 1..3
# are retail's 0..2 (Combiners_Opaque_Mod2xNA_Alpha, _AddAlpha, _AddAlpha_Alpha + Diffuse_T1_Env).
TABLE_SHADERS_WOTLK = 3

CAMERA_RETAIL, CAMERA_WOTLK = 116, 100
FAR_CLIP_WOTLK = 27.777779  # retail portrait cameras store 100x this


class ConvertError(Exception):
    pass


class Blob:
    """An MD20 being rebuilt: original bytes patched in place, new data appended at the end."""

    def __init__(self, data):
        self.d = bytearray(data)

    def add(self, data):
        while len(self.d) % 16:
            self.d.append(0)
        off = len(self.d)
        self.d += data
        return off

    def set_array(self, header_off, count, data):
        off = self.add(data) if count else 0
        struct.pack_into("<II", self.d, header_off, count, off)


def convert_shader(shader, tex_count):
    """(shader_id, texture_count, coord_combo) for 3.3.5 from a retail batch's values."""
    if shader & 0x8000:
        effect = shader & 0x7FFF
        if effect < TABLE_SHADERS_WOTLK:
            return 0x8000 | (effect + 1), tex_count, COORD_T1_ENV
        # ponytail: unknown retail effect -> first layer only; add mappings when one looks wrong
        return 0, 1, COORD_T1_ENV
    if tex_count == 1:
        # retail sets 0x10/0x70 for "Combiners_Mod" where 3.3.5 uses shader 0 and the blend mode
        return 0, 1, COORD_T1_ENV
    return 0, min(tex_count, 2), COORD_T1_T2


def convert_skin(data, vertex_bones, bone_lookup):
    """A retail .skin as a 3.3.5 one (48-byte header). Returns bytes.

    vertex_bones(v) -> set of bones model vertex v is weighted to (absolute bone indices);
    vertex_bones(v, slots=True) -> its 4 influence slots, None where the weight is 0.
    bone_lookup: the model's bone lookup table; palettes of split submeshes are appended to it.

    A submesh over MAX_BONES_PER_SUBMESH is split, in triangle order, into submeshes that each fit.
    Skin vertices store bone indices relative to their submesh's palette (bone_lookup[combo + i]),
    so split submeshes get their own vertex copies, and each batch is repeated per piece.
    """
    if data[:4] != b"SKIN":
        raise ConvertError("not a skin")
    nv, ov, ni, oi, nb, ob, ns, os_, nt, ot = struct.unpack_from("<10I", data, 4)
    lookup = struct.unpack_from(f"<{nv}H", data, ov)
    indices = struct.unpack_from(f"<{ni}H", data, oi)
    out_lookup, out_props, out_idx, out_subs = [], bytearray(), [], []
    pieces = []  # per old submesh: indices of its new submeshes
    for j in range(ns):
        sub = data[os_ + j * 48:os_ + j * 48 + 48]
        level, = struct.unpack_from("<H", sub, 2)
        istart, icount, bones, combo = struct.unpack_from("<HHHH", sub, 8)
        istart += level << 16
        if combo + bones > len(bone_lookup):
            raise ConvertError("submesh bone range outside the bone lookup")
        tris = [indices[i:i + 3] for i in range(istart, istart + icount, 3)]
        if bones <= MAX_BONES_PER_SUBMESH:
            groups = [(tris, None)]
        else:
            groups = []
            palette, cur = [], []
            for t in tris:
                need = {b for v in t for b in vertex_bones(lookup[v])}
                if len(set(palette) | need) > MAX_BONES_PER_SUBMESH and cur:
                    groups.append((cur, palette))
                    palette, cur = [], []
                palette += sorted(need - set(palette))
                cur.append(t)
            groups.append((cur, palette))
        pieces.append([])
        for group_tris, palette in groups:
            if palette is None:
                g_combo, g_bones = combo, bones
            else:
                g_combo, g_bones = len(bone_lookup), len(palette)
                bone_lookup += palette
                slot = {b: i for i, b in enumerate(palette)}
            local = {}
            vstart = len(out_lookup)
            for t in group_tris:
                for v in t:
                    if v not in local:
                        local[v] = len(out_lookup)
                        out_lookup.append(lookup[v])
                        if palette is None:
                            out_props += data[ob + v * 4:ob + v * 4 + 4]
                        else:
                            w = vertex_bones(lookup[v], slots=True)
                            out_props += bytes(slot[b] if b is not None else 0 for b in w)
                    out_idx.append(local[v])
            g_istart = len(out_idx) - len(group_tris) * 3
            if len(out_lookup) > 0xFFFF:
                raise ConvertError("more than 65535 skin vertices after splitting")
            s2 = bytearray(sub)
            struct.pack_into("<HHHHHHH", s2, 2, g_istart >> 16, vstart, len(out_lookup) - vstart,
                             g_istart & 0xFFFF, len(group_tris) * 3, g_bones, g_combo)
            pieces[-1].append(len(out_subs))
            out_subs.append(bytes(s2))

    batches = []
    for i in range(nt):
        b = bytearray(data[ot + i * 24:ot + i * 24 + 24])
        flags, prio, shader, sub, geo, color, mat, layer, tcount = struct.unpack_from("<BbHHHhHHH", b)
        shader, tcount, coord = convert_shader(shader, tcount)
        struct.pack_into("<BbH", b, 0, flags & BATCH_FLAGS, prio, shader)
        struct.pack_into("<H", b, 14, tcount)
        struct.pack_into("<H", b, 18, coord)
        for piece in pieces[sub]:
            struct.pack_into("<H", b, 4, piece)
            batches.append(bytes(b))

    parts = [struct.pack(f"<{len(out_lookup)}H", *out_lookup), struct.pack(f"<{len(out_idx)}H", *out_idx),
             bytes(out_props), b"".join(out_subs), b"".join(batches)]
    counts = [len(out_lookup), len(out_idx), len(out_lookup), len(out_subs), len(batches)]
    out = bytearray(48)
    header = [b"SKIN"]
    pos = 48
    for n, p in zip(counts, parts):
        header.append(struct.pack("<II", n, pos if n else 0))
        out += p
        pos += len(p)
    header.append(struct.pack("<I", MAX_BONES_PER_SUBMESH))
    out[:48] = b"".join(header)
    return bytes(out)


def geoset_ids(skin):
    """Geoset id of each submesh in a (3.3.5 or retail) skin."""
    ns, os_ = struct.unpack_from("<II", skin, 28)
    return [struct.unpack_from("<H", skin, os_ + i * 48)[0] for i in range(ns)]


def anim_payload(data, chunked):
    """The raw track data of a retail .anim file (what 3.3.5 .anim files hold whole)."""
    if not chunked:
        return data
    pos = 0
    while pos + 8 <= len(data):
        cid, size = struct.unpack_from("<4sI", data, pos)
        if cid == b"AFM2":
            return data[pos + 8:pos + 8 + size]
        pos += 8 + size
    raise ConvertError("chunked .anim without AFM2")


def convert_model(data, model_name, texture_name, get_file):
    """Convert one retail model.

    model_name: name stored in the header (the 3.3.5 file name without extension).
    texture_name(fdid) -> path the converted model should reference for a hardcoded texture.
    get_file(fdid) -> bytes of a retail file (skins, anims).

    Returns (m2 bytes, [skin bytes], {(anim id, sub id): anim bytes}, [warnings]).
    """
    m = M2(data)
    warnings = []
    if "SKID" in m.chunks:
        raise ConvertError("uses a .skel skeleton file (not handled yet)")
    if m.count("vertices") > 0xFFFF:
        raise ConvertError(f"{m.count('vertices')} vertices (3.3.5 indexes at most 65535)")
    b = Blob(m.md20)
    d = b.d
    struct.pack_into("<I", d, 4, VERSION_WOTLK)
    struct.pack_into("<I", d, 0x10, m.flags & MODEL_FLAGS)
    b.set_array(0x08, len(model_name) + 1, model_name.encode() + b"\0")

    # Sequences: newer flag bits off; the u32 blend time is two u16 (in, out) since Legion.
    chunked = bool(m.flags & 0x200000)
    afid = {}
    raw = m.chunks.get("AFID", b"")
    for i in range(len(raw) // 8):
        aid, sub, fid = struct.unpack_from("<HHI", raw, i * 8)
        afid[(aid, sub)] = fid
    anims = {}
    n, off = m.arrays["sequences"]
    high_ids = set()
    for i in range(n):
        s = off + i * 64
        aid, sub = struct.unpack_from("<HH", d, s)
        flags, = struct.unpack_from("<I", d, s + 12)
        blend_in, = struct.unpack_from("<H", d, s + 28)
        struct.pack_into("<I", d, s + 12, flags & SEQ_FLAGS)
        struct.pack_into("<I", d, s + 28, blend_in)
        if aid > MAX_ANIM_ID:
            high_ids.add(aid)
        if not flags & 0x60:  # neither inside the M2 (0x20) nor an alias (0x40): external .anim
            fid = afid.get((aid, sub))
            if not fid:
                raise ConvertError(f"sequence {aid}-{sub} has no .anim file")
            anims[(aid, sub)] = anim_payload(get_file(fid), chunked)
    if high_ids:
        warnings.append(f"animation ids above 3.3.5's {MAX_ANIM_ID} (never played): {sorted(high_ids)}")

    # Textures: retail names hardcoded textures by FileDataID (TXID); 3.3.5 needs a path.
    txid = m.u32s("TXID")
    n, off = m.arrays["textures"]
    for i in range(n):
        t = off + i * 16
        ttype, = struct.unpack_from("<I", d, t)
        name_len, = struct.unpack_from("<I", d, t + 8)
        if ttype == 0 and not name_len:
            fid = txid[i] if i < len(txid) else 0
            if not fid:
                raise ConvertError(f"texture {i} is hardcoded but has no file")
            name = texture_name(fid).encode() + b"\0"
            struct.pack_into("<II", d, t + 8, len(name), b.add(name))

    n, off = m.arrays["materials"]
    for i in range(n):
        flags, blend = struct.unpack_from("<HH", d, off + i * 4)
        struct.pack_into("<HH", d, off + i * 4, flags & MATERIAL_FLAGS, BLEND_ADD if blend > 6 else blend)

    b.set_array(0x88, len(TEXTURE_UNITS), struct.pack(f"<{len(TEXTURE_UNITS)}h", *TEXTURE_UNITS))

    # Cameras: 3.3.5 has a fixed fov after the type; later ones moved it to a track at the end.
    n, off = m.arrays["cameras"]
    cams = b""
    for i in range(n):
        c = bytes(d[off + i * CAMERA_RETAIL:off + (i + 1) * CAMERA_RETAIL])
        ctype, far, near = struct.unpack_from("<Iff", c)
        fov = first_track_value(d, off + i * CAMERA_RETAIL + 96) or 0.7853982
        cams += struct.pack("<Ifff", ctype, fov, min(far, FAR_CLIP_WOTLK), near) + c[12:96]
    b.set_array(0x110, n, cams)

    if m.count("particles") or m.count("ribbons"):
        # ponytail: emitters dropped (their structs grew after 3.3.5); convert them when a model needs its effects
        warnings.append(f"dropped {m.count('particles')} particle and {m.count('ribbons')} ribbon emitters")
        struct.pack_into("<II", d, 0x120, 0, 0)
        struct.pack_into("<II", d, 0x128, 0, 0)

    sfid = m.u32s("SFID")
    if not sfid:
        raise ConvertError("no skins")
    n, off = m.arrays["bone_lookup"]
    bone_lookup = list(struct.unpack_from(f"<{n}H", d, off))
    _, voff = m.arrays["vertices"]

    def vertex_bones(v, slots=False):
        w = d[voff + v * 48 + 12:voff + v * 48 + 16]
        b = d[voff + v * 48 + 16:voff + v * 48 + 20]
        if slots:
            return [b[k] if w[k] else None for k in range(4)]
        return {b[k] for k in range(4) if w[k]}

    skins = [convert_skin(get_file(sfid[0]), vertex_bones, bone_lookup)]
    if len(bone_lookup) > n:
        if len(bone_lookup) > 0xFFFF:
            raise ConvertError("bone lookup too large after splitting")
        b.set_array(0x78, len(bone_lookup), struct.pack(f"<{len(bone_lookup)}H", *bone_lookup))
        warnings.append(f"split submeshes over {MAX_BONES_PER_SUBMESH} bones")
    struct.pack_into("<I", d, 0x44, len(skins))
    return bytes(d), skins, anims, warnings


def first_track_value(d, track_off):
    """First key of an M2Track<M2SplineKey<float>> (the value, ignoring tangents), or None."""
    _, _, _, _, nv, ov = struct.unpack_from("<HhIIII", d, track_off)
    if not nv:
        return None
    n, o = struct.unpack_from("<II", d, ov)
    return struct.unpack_from("<f", d, o)[0] if n else None


def check(m2_bytes, skins):
    """Read a converted model back and check every array and index lands inside the file."""
    m = M2(m2_bytes)
    assert m.version == VERSION_WOTLK and not m.chunks
    size = len(m.md20)
    for name, (n, off) in m.arrays.items():
        assert not n or 0 < off < size, f"{name} offset outside the file"
    for t, _, name in m.textures():
        assert t != 0 or name, "hardcoded texture without a name"
    n_tex_lookup = m.count("texture_lookup")
    n_units = m.count("texture_unit_lookup")
    n_mat = m.count("materials")
    n_verts = m.count("vertices")
    d = m.md20
    nl, ol = m.arrays["bone_lookup"]
    bone_lookup = struct.unpack_from(f"<{nl}H", d, ol)
    _, voff = m.arrays["vertices"]
    for s in skins:
        nv, ov, ni, oi, nb, ob, ns, os_, nt, ot = struct.unpack_from("<10I", s, 4)
        lookup = struct.unpack_from(f"<{nv}H", s, ov)
        indices = struct.unpack_from(f"<{ni}H", s, oi)
        assert max(lookup, default=0) < n_verts, "skin vertex outside the model"
        assert max(indices, default=0) < nv, "index outside the skin"
        for j in range(ns):
            level, vs, vc, istart, icount, bones, combo = struct.unpack_from("<7H", s, os_ + j * 48 + 2)
            istart += level << 16
            assert bones <= MAX_BONES_PER_SUBMESH, f"submesh {j} uses {bones} bones"
            assert all(vs <= t < vs + vc for t in indices[istart:istart + icount]), f"submesh {j} indexes outside its vertices"
            for i in range(vs, vs + vc):
                g = voff + lookup[i] * 48
                for k in range(4):
                    if d[g + 12 + k]:
                        p = s[ob + i * 4 + k]
                        assert p < bones and bone_lookup[combo + p] == d[g + 16 + k], \
                            f"submesh {j} vertex {i}: palette does not give the vertex's bone"
        for i in range(nt):
            flags, prio, shader, sub, geo, color, mat, layer, tcount, tcombo, coord = \
                struct.unpack_from("<BbHHHhHHHHH", s, ot + i * 24)
            assert sub < ns and mat < n_mat, "batch submesh/material out of range"
            assert tcombo + tcount <= n_tex_lookup, "batch texture combo out of range"
            assert coord + tcount <= n_units, "batch coord combo out of range"
    return True
