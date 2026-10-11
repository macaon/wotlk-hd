"""Convert a retail (MD21, v272-274) creature model to a 3.3.5 (MD20, v264) one.

The MD20 header and most structs are unchanged since 3.3.5 (see m2.py), so this lifts the MD20
out of its chunk and fixes what 3.3.5 reads differently. Everything was checked against 3.3.5's
own files and Wow.exe (12340); see README.md "Converter notes".

Submeshes over 64 bones are split; vertices the chosen skin does not use are dropped. Refused
(ConvertError) rather than half-converted: .skel-based models and skins over 65535 vertices.
"""
import math
import collections
import struct

from m2 import ARRAYS, FLAG_COMBINER_COMBOS, HEADER_SIZE, M2

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
# Retail effect 3 (Combiners_Opaque_Mod2xNA_Alpha_Add, Diffuse_T1_Env_T1) is effect 0 plus a third
# texture added on top (moltengiant's lava cracks). 3.3.5 draws such glows as a second batch: the
# same submesh on the next material layer, unlit and additive.
EFFECT_GLOW = 3
GLOW_MATERIAL = (0x11, BLEND_ADD)  # unlit, no z-write

CAMERA_RETAIL, CAMERA_WOTLK = 116, 100
PARTICLE_RETAIL, PARTICLE_WOTLK = 492, 476
PARTICLE_FLAGS = 0x007FFFFF       # 3.3.5 files use bits below 0x80000; 0x800000+ are newer
PARTICLE_MULTITEXTURE = 0x10000000
PARTICLE_COMPRESSED_GRAVITY = 0x00800000  # gravity keys are packed vectors, not floats
PARTICLE_BLEND_MAX = 4
FAR_CLIP_WOTLK = 27.777779  # retail portrait cameras store 100x this
# 3.3.5 knows key bones 0..26 (its own models never use more); retail numbers them past 290, and a
# Stonewing Slayer (gargoyle2, key bones up to 286) garbled and crashed the client while animating.
MAX_KEY_BONE = 26


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


def convert_skin(data, vertex_bones, bone_lookup, glow_material=None, n_colors=None):
    """A retail .skin as a 3.3.5 one (48-byte header). Returns bytes.

    vertex_bones(v) -> set of bones model vertex v is weighted to (absolute bone indices);
    vertex_bones(v, slots=True) -> its 4 influence slots, None where the weight is 0.
    bone_lookup: the model's bone lookup table; palettes of split submeshes are appended to it.
    glow_material: material index for the extra additive batch of EFFECT_GLOW batches.
    n_colors: the model's color count; batches pointing past it get none (retail boar2 does).

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
        # Retail skin vertex palette indices can be stale (boar2: most point at the wrong bone), so
        # they are always recomputed from the model vertices' bones: the submesh's own palette when
        # it holds them all and fits, otherwise new palettes, splitting in triangle order.
        window = list(bone_lookup[combo:combo + bones])
        need = {b for t in tris for v in t for b in vertex_bones(lookup[v])}
        if bones <= MAX_BONES_PER_SUBMESH and need <= set(window):
            groups = [(tris, window, combo)]
        else:
            groups = []
            palette, cur = [], []
            for t in tris:
                tneed = {b for v in t for b in vertex_bones(lookup[v])}
                if len(set(palette) | tneed) > MAX_BONES_PER_SUBMESH and cur:
                    groups.append((cur, palette, None))
                    palette, cur = [], []
                palette += sorted(tneed - set(palette))
                cur.append(t)
            groups.append((cur, palette, None))
        pieces.append([])
        for group_tris, palette, g_combo in groups:
            if g_combo is None:
                g_combo = len(bone_lookup)
                bone_lookup += palette
            g_bones = len(palette)
            slot = {}
            for i, b in enumerate(palette):
                slot.setdefault(b, i)
            local = {}
            vstart = len(out_lookup)
            for t in group_tris:
                for v in t:
                    if v not in local:
                        local[v] = len(out_lookup)
                        out_lookup.append(lookup[v])
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
        flags, prio, shader, sub, geo, color, mat, layer, tcount, tcombo = struct.unpack_from("<BbHHHhHHHH", b)
        glow = None
        if shader == 0x8000 | EFFECT_GLOW and tcount == 3 and glow_material is not None:
            glow = bytearray(b)
            struct.pack_into("<BbH", glow, 0, flags & BATCH_FLAGS, prio, 0)
            struct.pack_into("<HHHHH", glow, 10, glow_material, layer + 1, 1, tcombo + 2, COORD_T1_ENV)
            shader, tcount = 0x8000, 2  # effect 0 for the first two textures
        if n_colors is not None and color >= n_colors:
            struct.pack_into("<h", b, 8, -1)
            if glow:
                struct.pack_into("<h", glow, 8, -1)
        shader, tcount, coord = convert_shader(shader, tcount)
        struct.pack_into("<BbH", b, 0, flags & BATCH_FLAGS, prio, shader)
        struct.pack_into("<H", b, 14, tcount)
        struct.pack_into("<H", b, 18, coord)
        for piece in pieces[sub]:
            for out in [b] + ([glow] if glow else []):
                struct.pack_into("<H", out, 4, piece)
                batches.append(bytes(out))

    return pack_skin(out_lookup, out_idx, bytes(out_props), out_subs, batches)


def pack_skin(lookup, indices, props, subs, batches):
    """A 3.3.5 skin from its arrays (submeshes and batches as 48- and 24-byte records)."""
    parts = [struct.pack(f"<{len(lookup)}H", *lookup), struct.pack(f"<{len(indices)}H", *indices),
             props, b"".join(subs), b"".join(batches)]
    counts = [len(lookup), len(indices), len(lookup), len(subs), len(batches)]
    out = bytearray(48)
    header = [b"SKIN"]
    pos = 48
    for n, part in zip(counts, parts):
        header.append(struct.pack("<II", n, pos if n else 0))
        out += part
        pos += len(part)
    header.append(struct.pack("<I", MAX_BONES_PER_SUBMESH))
    out[:48] = b"".join(header)
    return bytes(out)


def select_geosets(skin, geoset_map, index_limit=0xFFFF, optional=None, dropped=None):
    """The skin with submesh geosets renamed by geoset_map(id) -> new id, or None to drop the
    submesh, and only drawn submeshes left, their triangles packed from index 0. 3.3.5 ignores a
    submesh's level (the high word of its index start), so every start must stay under 65536:
    the HD blood elves (113k drawn indices) and gargoyle2 (70k) drew garbage past it.
    index_limit=None writes starts past it with level, for Wow-hdchar.exe (patch_exe.py).
    optional(id): submeshes that go last and are left out (their ids added to `dropped`) when
    they would start past index_limit, rather than failing (alternative hair styles).
    geoset_map may return a tuple of ids: the submesh is drawn once per id (a retail horn shared by
    several 3.3.5 hair styles)."""
    nv, ov, ni, oi, nb, ob, ns, os_, nt, ot = struct.unpack_from("<10I", skin, 4)
    lookup = struct.unpack_from(f"<{nv}H", skin, ov)
    indices = struct.unpack_from(f"<{ni}H", skin, oi)
    subs = [bytearray(skin[os_ + j * 48:os_ + j * 48 + 48]) for j in range(ns)]
    batches = [bytearray(skin[ot + i * 24:ot + i * 24 + 24]) for i in range(nt)]
    keep = {}
    for j, s in enumerate(subs):
        new_id = geoset_map(struct.unpack_from("<H", s, 0)[0]) if geoset_map else struct.unpack_from("<H", s, 0)[0]
        if new_id is not None:
            keep[j] = new_id if isinstance(new_id, tuple) else (new_id,)
    used = {struct.unpack_from("<H", b, 4)[0] for b in batches}
    drawn = [(j, sid) for j in sorted(used & set(keep)) for sid in keep[j]]
    if optional:
        drawn.sort(key=lambda js: (bool(optional(js[1])), js[0]))
    new_sub = collections.defaultdict(list)
    out_idx, out_subs = [], []
    for j, sid in drawn:
        s = bytearray(subs[j])
        struct.pack_into("<H", s, 0, sid)
        level, = struct.unpack_from("<H", s, 2)
        start, count = struct.unpack_from("<HH", s, 8)
        start += level << 16
        if index_limit is not None and len(out_idx) > index_limit:
            sid, = struct.unpack_from("<H", s, 0)
            if optional and optional(sid):
                if dropped is not None:
                    dropped.add(sid)
                continue
            raise ConvertError(f"more than 65535 triangle indices in drawn submeshes")
        struct.pack_into("<H", s, 2, len(out_idx) >> 16)
        struct.pack_into("<H", s, 8, len(out_idx) & 0xFFFF)
        out_idx += indices[start:start + count]
        new_sub[j].append(len(out_subs))
        out_subs.append(bytes(s))
    out_batches = []
    for b in batches:
        sub, = struct.unpack_from("<H", b, 4)
        for n in new_sub.get(sub, ()):
            struct.pack_into("<H", b, 4, n)
            out_batches.append(bytes(b))
    return pack_skin(lookup, out_idx, bytes(skin[ob:ob + nv * 4]), out_subs, out_batches)


def geoset_ids(skin):
    """Geoset id of each submesh in a (3.3.5 or retail) skin."""
    ns, os_ = struct.unpack_from("<II", skin, 28)
    return [struct.unpack_from("<H", skin, os_ + i * 48)[0] for i in range(ns)]


def anim_payload(data, chunked):
    """The raw track data of a retail .anim file (what 3.3.5 .anim files hold whole)."""
    if not chunked and data[:4] not in (b"AFM2", b"AFSA", b"AFSB"):  # .skel models: chunked anyway
        return data
    pos = 0
    while pos + 8 <= len(data):
        cid, size = struct.unpack_from("<4sI", data, pos)
        if cid == b"AFM2":
            return data[pos + 8:pos + 8 + size]
        pos += 8 + size
    raise ConvertError("chunked .anim without AFM2")


# .skel chunks: where each array (count, offset relative to the chunk) sits, and its MD20 header slot
SKEL_ARRAYS = {b"SKS1": [(0, 0x14), (8, 0x1C), (16, 0x24)],   # global loops, sequences, lookup
               b"SKB1": [(0, 0x2C), (8, 0x34)],                # bones, key bone lookup
               b"SKA1": [(0, 0xF0), (8, 0xF8)]}                # attachments, attachment lookup
BONE_SIZE, ATTACHMENT_SIZE, SEQUENCE_SIZE = 88, 40, 64
BONE_TRACKS, ATTACHMENT_TRACKS = (16, 36, 56), (20,)


# Repacking: element size, and (offset, key size) of the animation tracks inside each element
SIMPLE_ARRAYS = {"name": 1, "global_loops": 4, "sequences": SEQUENCE_SIZE, "sequence_lookup": 2,
                 "key_bone_lookup": 2, "vertices": 48, "replaceable_texture_lookup": 2,
                 "materials": 4, "bone_lookup": 2, "texture_lookup": 2, "texture_unit_lookup": 2,
                 "transparency_lookup": 2, "texture_transform_lookup": 2, "collision_indices": 2,
                 "collision_positions": 12, "collision_normals": 12, "attachment_lookup": 2,
                 "camera_lookup": 2}
TRACK_ARRAYS = {"bones": (BONE_SIZE, [(16, 12), (36, 8), (56, 12)]),
                "colors": (40, [(0, 12), (20, 2)]),
                "texture_weights": (20, [(0, 2)]),
                "texture_transforms": (60, [(0, 12), (20, 16), (40, 12)]),
                "attachments": (ATTACHMENT_SIZE, [(20, 1)]),
                "lights": (156, [(16, 12), (36, 4), (56, 12), (76, 4), (96, 4), (116, 4), (136, 1)]),
                "cameras": (CAMERA_WOTLK, [(16, 36), (48, 36), (80, 12)])}
EVENT_SIZE, EVENT_TRACK = 36, 24  # an event's track has timestamps only


def repack(m2):
    """The model rebuilt from only the data its structures reference, without key frames of
    sequences 3.3.5 never plays (ids past MAX_ANIM_ID). Converting appends and leaves the replaced
    data behind (the full retail vertex array, whole .skel chunks): the blood elf HD model was 35 MB
    and the client used the old model instead. Returns (m2, kept (anim id, sub id) pairs).

    ponytail: models with particles or ribbons come back as they are (their structs hold many
    arrays not walked here); walk them too if those models get big.
    """
    src = bytes(m2)
    arrays = {name: struct.unpack_from("<II", src, off) for off, name in ARRAYS}
    header_of = {name: off for off, name in ARRAYS}
    n_seq, seq_off = arrays["sequences"]
    seqs = [struct.unpack_from("<HHI", src, seq_off + k * SEQUENCE_SIZE) for k in range(n_seq)]
    flags = [struct.unpack_from("<I", src, seq_off + k * SEQUENCE_SIZE + 12)[0] for k in range(n_seq)]
    played = [aid <= MAX_ANIM_ID for aid, _, _ in seqs]
    kept = {(aid, sub) for (aid, sub, _), p in zip(seqs, played) if p}
    if arrays["particles"][0] or arrays["ribbons"][0]:
        return src, kept
    flags_m2, = struct.unpack_from("<I", src, 0x10)
    out = Blob(src[:HEADER_SIZE + (8 if flags_m2 & FLAG_COMBINER_COMBOS else 0)])

    def copy(header, size, n=None, off=None):
        if n is None:
            n, off = struct.unpack_from("<II", src, header)
        out.set_array(header, n, src[off:off + n * size])
        return n, struct.unpack_from("<I", out.d, header + 4)[0]

    def track(pos, key_size, values=True):
        _, global_loop = struct.unpack_from("<Hh", out.d, pos)
        for arr, size in ((pos + 4, 4),) + (((pos + 12, key_size),) if values else ()):
            n, off = struct.unpack_from("<II", out.d, arr)
            if not n:
                continue
            outer = bytearray(src[off:off + n * 8])
            for k in range(n):
                cnt, inner = struct.unpack_from("<II", outer, k * 8)
                if not cnt:
                    continue
                if global_loop < 0 and k < n_seq and not played[k]:
                    struct.pack_into("<II", outer, k * 8, 0, 0)
                elif global_loop >= 0 or (k < n_seq and flags[k] & 0x20):
                    struct.pack_into("<I", outer, k * 8 + 4, out.add(src[inner:inner + cnt * size]))
                # else: the keys are in that sequence's .anim file; offsets stay as they are
            struct.pack_into("<I", out.d, arr + 4, out.add(bytes(outer)))

    for name, size in SIMPLE_ARRAYS.items():
        copy(header_of[name], size)
    if flags_m2 & FLAG_COMBINER_COMBOS:
        copy(HEADER_SIZE, 2)
    n, off = copy(header_of["textures"], 16)
    for i in range(n):
        t = off + i * 16
        length, name_off = struct.unpack_from("<II", src, struct.unpack_from("<I", src, header_of["textures"] + 4)[0] + i * 16 + 8)
        if length:
            struct.pack_into("<I", out.d, t + 12, out.add(src[name_off:name_off + length]))
    for name, (size, tracks) in TRACK_ARRAYS.items():
        n, off = copy(header_of[name], size)
        for i in range(n):
            for t, key_size in tracks:
                track(off + i * size + t, key_size)
    n, off = copy(header_of["events"], EVENT_SIZE)
    for i in range(n):
        track(off + i * EVENT_SIZE + EVENT_TRACK, 4, values=False)
    return bytes(out.d), kept


def chunks(data):
    out, pos = {}, 0
    while pos + 8 <= len(data):
        cid, size = struct.unpack_from("<4sI", data, pos)
        out[cid] = data[pos + 8:pos + 8 + size]
        pos += 8 + size
    return out


def merge_skel(b, skel, get_file):
    """Put a retail .skel's skeleton into the MD20 being built (retail moved bones, sequences and
    attachments of character models there). Returns {(anim id, sub id): 3.3.5 .anim bytes}.

    Each chunk is appended whole and its arrays pointed at; offsets inside are relative to the
    chunk, so the animation tracks of bones and attachments are relocated. Per-sequence key arrays
    that live in .anim files (sequence without flag 0x20, track without global loop) are relative
    to a chunk of that file instead: AFM2 (model tracks), AFSA (attachments), AFSB (bones). 3.3.5
    reads one payload, so the three are concatenated and those offsets moved by their chunk's base.
    """
    c = chunks(skel)
    if b"SKPD" in c:
        raise ConvertError("skeleton has a parent skeleton (not handled yet)")
    d = b.d
    bases = {}
    for cid, arrays in SKEL_ARRAYS.items():
        if cid not in c:
            continue
        base = bases[cid] = b.add(c[cid])
        for rel, header in arrays:
            n, off = struct.unpack_from("<II", c[cid], rel)
            struct.pack_into("<II", d, header, n, base + off if n else 0)
    n_seq, seq_off = struct.unpack_from("<II", d, 0x1C)
    seq_flags = [struct.unpack_from("<I", d, seq_off + i * SEQUENCE_SIZE + 12)[0] for i in range(n_seq)]
    raw = c.get(b"AFID", b"")
    afid = {struct.unpack_from("<HH", raw, i * 8): struct.unpack_from("<I", raw, i * 8 + 4)[0]
            for i in range(len(raw) // 8)}
    anims, anim_base = {}, {}  # anim_base[sequence index][chunk id] = offset in the joined payload
    for k in range(n_seq):
        key = struct.unpack_from("<HH", d, seq_off + k * SEQUENCE_SIZE)
        if seq_flags[k] & 0x60 or not afid.get(key):
            continue
        parts, joined = chunks(get_file(afid[key])), b""
        anim_base[k] = {}
        for cid in (b"AFM2", b"AFSA", b"AFSB"):
            joined += bytes(-len(joined) % 16)
            anim_base[k][cid] = len(joined)
            joined += parts.get(cid, b"")
        anims[key] = joined

    def relocate(track, base, anim_chunk):
        _, global_loop = struct.unpack_from("<Hh", d, track)
        for arr in (track + 4, track + 12):  # timestamps, values: arrays of per-sequence arrays
            n, off = struct.unpack_from("<II", d, arr)
            if not n:
                continue
            off += base
            struct.pack_into("<I", d, arr + 4, off)
            for k in range(n):
                cnt, inner = struct.unpack_from("<II", d, off + k * 8)
                if not cnt:
                    continue
                if global_loop >= 0 or (k < n_seq and seq_flags[k] & 0x20):
                    struct.pack_into("<I", d, off + k * 8 + 4, inner + base)
                elif k in anim_base:
                    struct.pack_into("<I", d, off + k * 8 + 4, inner + anim_base[k][anim_chunk])

    for cid, header, size, tracks, anim_chunk in (
            (b"SKB1", 0x2C, BONE_SIZE, BONE_TRACKS, b"AFSB"),
            (b"SKA1", 0xF0, ATTACHMENT_SIZE, ATTACHMENT_TRACKS, b"AFSA")):
        if cid in bases:
            n, off = struct.unpack_from("<II", d, header)
            for i in range(n):
                for t in tracks:
                    relocate(off + i * size + t, bases[cid], anim_chunk)
    return anims


def convert_model(data, model_name, texture_name, get_file, lod=0, geoset_map=None, index_limit=0xFFFF,
                  optional=None, dropped=None):
    """Convert one retail model.

    model_name: name stored in the header (the 3.3.5 file name without extension).
    texture_name(fdid) -> path the converted model should reference for a hardcoded texture.
    get_file(fdid) -> bytes of a retail file (skins, anims).
    lod: which retail skin to convert (convert_model_fitting tries lighter ones).
    geoset_map(id) -> 3.3.5 geoset id, or None to leave the submesh out (see select_geosets).

    Returns (m2 bytes, [skin bytes], {(anim id, sub id): anim bytes}, [warnings]).
    """
    m = M2(data)
    warnings = []
    b = Blob(m.md20)
    d = b.d
    skel_anims = {}
    if "SKID" in m.chunks:
        skel_anims = merge_skel(b, get_file(m.u32s("SKID")[0]), get_file)
        m.arrays = {name: struct.unpack_from("<II", d, off) for off, name in ARRAYS}
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
    anims = dict(skel_anims)
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
        if not flags & 0x60 and (aid, sub) not in anims:  # external .anim (not in-file 0x20 or alias 0x40)
            fid = afid.get((aid, sub))
            if not fid and aid > MAX_ANIM_ID:
                continue  # never played by 3.3.5; repack drops its keys
            if not fid:
                raise ConvertError(f"sequence {aid}-{sub} has no .anim file")
            anims[(aid, sub)] = anim_payload(get_file(fid), chunked)
    if high_ids:
        warnings.append(f"animation ids above 3.3.5's {MAX_ANIM_ID} (never played): {sorted(high_ids)}")

    # 3.3.5 reads sequence_lookup directly by animation id; retail's is a hash table (blood elf
    # HD: 701 slots for ids up to 1818, so 158 ids gave another sequence; gargoyle2: 223 slots, so
    # ids past 222 read beyond it, garbling and crashing the client). Rebuilt as 3.3.5's: the first
    # sequence of each id, -1 where there is none.
    lookup = {}
    for i in range(n):
        aid, = struct.unpack_from("<H", d, off + i * SEQUENCE_SIZE)
        if aid <= MAX_ANIM_ID:
            lookup.setdefault(aid, i)
    table = [lookup.get(a, -1) for a in range(max(lookup, default=-1) + 1)]
    b.set_array(0x24, len(table), struct.pack(f"<{len(table)}h", *table))

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

    # Particle emitters: the 3.3.5 struct (476 bytes) with 16 bytes appended later (multi-texture
    # parameters); every field before them is unchanged (compared on shade.m2 in both versions).
    # 3.3.5 files give every emitter an empty string (count 1, "\0") for its geometry and recursion
    # model names; retail leaves them at count 0, offset 0, which 3.3.5 reads as the name "MD20...",
    # so the emitter tries to spawn a model and draws nothing.
    n, off = m.arrays["particles"]
    empty = b.add(b"\0") if n else 0
    emitters = b""
    decoded = set()
    for i in range(n):
        flags, = struct.unpack_from("<I", d, off + i * PARTICLE_RETAIL + 4)
        if flags & PARTICLE_COMPRESSED_GRAVITY:
            if not decompress_gravity(d, off + i * PARTICLE_RETAIL + 0x84, decoded):
                warnings.append(f"emitter {i}: gravity keys in .anim files left as they are")
    for i in range(n):
        wrap_cells(d, off + i * PARTICLE_RETAIL, decoded)
    for i in range(n):
        e = bytearray(d[off + i * PARTICLE_RETAIL:off + i * PARTICLE_RETAIL + PARTICLE_WOTLK])
        flags, = struct.unpack_from("<I", e, 4)
        tex, = struct.unpack_from("<H", e, 0x16)
        if flags & PARTICLE_MULTITEXTURE:
            tex &= 0x1F  # three 5-bit texture indices; 3.3.5 takes one
        struct.pack_into("<I", e, 4, flags & PARTICLE_FLAGS)
        struct.pack_into("<H", e, 0x16, tex)
        e[0x28] = min(e[0x28], PARTICLE_BLEND_MAX)
        for name_off in (0x18, 0x20):
            if not struct.unpack_from("<I", e, name_off)[0]:
                struct.pack_into("<II", e, name_off, 1, empty)
        emitters += e
    b.set_array(0x128, n, emitters)

    if m.count("ribbons"):
        # ponytail: ribbon emitters dropped until a model needs one (struct not compared yet)
        warnings.append(f"dropped {m.count('ribbons')} ribbon emitters")
        struct.pack_into("<II", d, 0x120, 0, 0)

    sfid = m.u32s("SFID")
    if not sfid:
        raise ConvertError("no skins")
    lods = lod if isinstance(lod, tuple) else (lod,)
    if max(lods[:2]) >= len(sfid):
        raise ConvertError("no skin light enough for 3.3.5")
    for k in lods[:2]:
        if skin_agreement(d, get_file(sfid[k])) < 0.9:
            # retail palettes are recomputed below, which would hide a skin from another export
            raise ConvertError("skin does not match the model's vertices (files from different builds?)")
    if isinstance(lod, tuple):  # (body lod, other lod, which geosets come from the other)
        body, other, from_other = lod
        skin = merge_skins(b, [(get_file(sfid[body]), lambda s: not from_other(s)),
                               (get_file(sfid[other]), from_other)])
    else:
        skin = compact_vertices(b, get_file(sfid[lod]))
    n, off = m.arrays["bone_lookup"]
    bone_lookup = list(struct.unpack_from(f"<{n}H", d, off))
    _, voff = struct.unpack_from("<II", d, 0x3C)

    def vertex_bones(v, slots=False):
        w = d[voff + v * 48 + 12:voff + v * 48 + 16]
        b = d[voff + v * 48 + 16:voff + v * 48 + 20]
        if slots:
            return [b[k] if w[k] else None for k in range(4)]
        return {b[k] for k in range(4) if w[k]}

    # Key bones 3.3.5 does not know: off on the bones, and the lookup only as long as 3.3.5's.
    n, off = struct.unpack_from("<II", d, 0x2C)
    for i in range(n):
        if struct.unpack_from("<i", d, off + i * 88)[0] > MAX_KEY_BONE:
            struct.pack_into("<i", d, off + i * 88, -1)
    n, off = struct.unpack_from("<II", d, 0x34)
    if n > MAX_KEY_BONE + 1:
        struct.pack_into("<I", d, 0x34, MAX_KEY_BONE + 1)
    # Lookups to texture transforms the model does not have (retail leaves 0 with none): none.
    n_tt = struct.unpack_from("<I", d, 0x60)[0]
    n, off = struct.unpack_from("<II", d, 0x98)
    for i in range(n):
        if struct.unpack_from("<h", d, off + i * 2)[0] >= n_tt:
            struct.pack_into("<h", d, off + i * 2, -1)

    n_mat, mat_off = m.arrays["materials"]  # plus GLOW_MATERIAL, unused unless a batch needs it
    b.set_array(0x70, n_mat + 1, bytes(d[mat_off:mat_off + n_mat * 4]) + struct.pack("<HH", *GLOW_MATERIAL))
    skins = [select_geosets(convert_skin(skin, vertex_bones, bone_lookup, n_mat, struct.unpack_from("<I", d, 0x48)[0]),
                            geoset_map, index_limit, optional, dropped)]
    if len(bone_lookup) > n:
        if len(bone_lookup) > 0xFFFF:
            raise ConvertError("bone lookup too large after splitting")
        b.set_array(0x78, len(bone_lookup), struct.pack(f"<{len(bone_lookup)}H", *bone_lookup))
        warnings.append(f"split submeshes over {MAX_BONES_PER_SUBMESH} bones")
    struct.pack_into("<I", d, 0x44, len(skins))
    m2, kept = repack(d)
    return m2, skins, {k: v for k, v in anims.items() if k in kept}, warnings


def convert_model_fitting(data, model_name, texture_name, get_file, geoset_map=None, optional=None,
                          split=None, fallback_body=None, dropped=None):
    """convert_model with the most detailed retail skin that fits 3.3.5's 65535 index starts.

    split(geoset id): geosets that may come from a lighter LOD than the rest (hair), so the body
    keeps its detail; the pair is chosen by counting indices first. If no pair fits, the body comes
    from fallback_body and split geosets from the lightest LOD, those that do not fit left out
    (their ids added to `dropped`). Otherwise the first LOD with nothing left out, else (with
    optional submeshes) the one leaving out the fewest."""
    sfid = M2(data).u32s("SFID")
    if split and sfid:
        kept = (lambda s: geoset_map(s) is not None) if geoset_map else (lambda s: True)
        skins = [get_file(f) for f in sfid]
        for body in range(len(skins)):
            for other in range(body, len(skins)):
                total = (skin_indices(skins[body], lambda s: kept(s) and not split(s)) +
                         skin_indices(skins[other], lambda s: kept(s) and split(s)))
                if total <= 0xFFFF:
                    result = convert_model(data, model_name, texture_name, get_file, (body, other, split),
                                           geoset_map)
                    if body or other:
                        result[3].append(f"skins {body} (body) and {other} (split geosets) to fit 65535 indices")
                    return result
        if fallback_body is None:
            raise ConvertError("no skin light enough for 3.3.5")
        lost = set() if dropped is None else dropped
        result = convert_model(data, model_name, texture_name, get_file,
                               (fallback_body, len(skins) - 1, split), geoset_map, optional=split, dropped=lost)
        result[3].append(f"skins {fallback_body} (body) and {len(skins) - 1} (split geosets); "
                         f"left out to fit 65535 indices: geosets {sorted(lost)}")
        return result
    best = None
    for lod in range(len(sfid) or 1):
        dropped = set()
        try:
            result = convert_model(data, model_name, texture_name, get_file, lod, geoset_map,
                                   optional=optional, dropped=dropped)
        except ConvertError as e:
            if "65535 triangle indices" not in str(e):
                raise
            continue
        if lod:
            result[3].append(f"skin {lod} (lighter LOD): heavier ones exceed 65535 indices")
        if not dropped:
            return result
        if best is None or len(dropped) < len(best[1]):
            best = (result, dropped)
    if best is None:
        raise ConvertError("no skin light enough for 3.3.5")
    result, dropped = best
    result[3].append(f"left out to fit 65535 indices: geosets {sorted(dropped)}")
    return result


def wrap_cells(d, emitter, done):
    """Bring head/tail cell tracks that only name cells past the texture's rows x cols back into
    range, in place. voidwalker2 keys cell 1 on a 1x1 texture, which retail wraps to cell 0 and
    3.3.5 draws from outside the texture (flat squares). Tracks with some valid keys (shade: 0..16
    on 4x4, 16 being the end of life) are left alone."""
    rows, cols = struct.unpack_from("<HH", d, emitter + 0x30)
    cells = max(rows, 1) * max(cols, 1)
    for track in (0x13C, 0x14C):
        _, _, nv, ov = struct.unpack_from("<4I", d, emitter + track)
        if not nv or ov in done:
            continue
        values = struct.unpack_from(f"<{nv}H", d, ov)
        if min(values) >= cells:
            done.add(ov)
            struct.pack_into(f"<{nv}H", d, ov, *(v % cells for v in values))


def decompress_gravity(d, track_off, done):
    """Rewrite a gravity track's compressed vectors as 3.3.5's floats, in place. False if some
    keys live outside the model (external .anim data).

    With PARTICLE_COMPRESSED_GRAVITY each key is (int8 x, int8 y, int16 z): a unit direction from
    x/128, y/128 and the implied z, scaled by z * 0.04238648 (a negative scale flips the direction).
    3.3.5 has only a downward float: the vector's z, negated. Checked against arcanegolem and
    manafiend, whose 3.3.5 files hold the same emitters with float gravity (0.694 vs -0.678).
    """
    _, _, _, _, nv, ov = struct.unpack_from("<HhIIII", d, track_off)
    inside = True
    for s in range(nv):
        n, p = struct.unpack_from("<II", d, ov + s * 8)
        if not n:
            continue
        if p + n * 4 > len(d) or p == 0:
            inside = False
            continue
        if p in done:
            continue
        done.add(p)
        for k in range(n):
            x, y, z = struct.unpack_from("<bbh", d, p + k * 4)
            fx, fy = x / 128, y / 128
            fz = math.sqrt(max(0.0, 1 - fx * fx - fy * fy))
            scale = z * 0.04238648
            if scale < 0:
                fz, scale = -fz, -scale
            struct.pack_into("<f", d, p + k * 4, -fz * scale)
    return inside


def skin_agreement(d, skin):
    """Share of skin vertices whose first palette bone (skin) is their model vertex's bone (m2)."""
    nv, ov, ni, oi, nb, ob, ns, os_ = struct.unpack_from("<8I", skin, 4)
    look = struct.unpack_from(f"<{nv}H", skin, ov)
    base, = struct.unpack_from("<I", skin, 0x2C)
    nl, ol = struct.unpack_from("<II", d, 0x78)
    _, voff = struct.unpack_from("<II", d, 0x3C)
    bone_lookup = struct.unpack_from(f"<{nl}H", d, ol)
    ok = total = 0
    for j in range(ns):
        _, _, vs, vc, _, _, _, combo = struct.unpack_from("<8H", skin, os_ + j * 48)
        for i in range(vs, vs + vc):
            p = combo + skin[ob + i * 4]
            total += 1
            ok += p < nl and bone_lookup[p] == d[voff + (look[i] + base) * 48 + 16]
    return ok / total if total else 1.0


def merge_skins(b, parts):
    """One skin from submeshes of several retail skins (LODs) of this model, vertices compacted like
    compact_vertices: parts = [(skin, keep(geoset id))]. Lets a character take body and face from a
    detailed LOD and hair from a light one (retail's far LODs paint the eyes shut)."""
    lookup, indices, props, subs, batches = [], [], bytearray(), [], []
    for skin, keep in parts:
        nv, ov, ni, oi, nb, ob, ns, os_, nt, ot = struct.unpack_from("<10I", skin, 4)
        base, = struct.unpack_from("<I", skin, 0x2C)
        look = struct.unpack_from(f"<{nv}H", skin, ov)
        idx = struct.unpack_from(f"<{ni}H", skin, oi)
        drawn = {struct.unpack_from("<H", skin, ot + i * 24 + 4)[0] for i in range(nt)}
        new_sub = {}
        for j in range(ns):
            s = bytearray(skin[os_ + j * 48:os_ + j * 48 + 48])
            sid, level, vs, vc, start, count = struct.unpack_from("<6H", s)
            if j not in drawn or not keep(sid):
                continue
            new_vs = len(lookup)
            if new_vs + vc > 0xFFFF:
                raise ConvertError("more than 65535 triangle indices: merged skin over the vertex limit")
            lookup += [base + v for v in look[vs:vs + vc]]
            props += skin[ob + vs * 4:ob + (vs + vc) * 4]
            start += level << 16
            new_start = len(indices)
            indices += [i - vs + new_vs for i in idx[start:start + count]]
            struct.pack_into("<HHHH", s, 2, new_start >> 16, new_vs, vc, new_start & 0xFFFF)
            new_sub[j] = len(subs)
            subs.append(bytes(s))
        for i in range(nt):
            bt = bytearray(skin[ot + i * 24:ot + i * 24 + 24])
            j, = struct.unpack_from("<H", bt, 4)
            if j in new_sub:
                struct.pack_into("<H", bt, 4, new_sub[j])
                batches.append(bytes(bt))
    order = sorted(set(lookup))
    if len(order) > 0xFFFF:
        raise ConvertError(f"merged skin uses {len(order)} vertices (3.3.5 indexes at most 65535)")
    n, off = struct.unpack_from("<II", b.d, 0x3C)
    new_index = {v: i for i, v in enumerate(order)}
    b.set_array(0x3C, len(order), b"".join(bytes(b.d[off + v * 48:off + v * 48 + 48]) for v in order))
    skin = bytearray(pack_skin([new_index[v] for v in lookup], indices, bytes(props), subs, batches))
    struct.pack_into("<I", skin, 0x2C, 0)
    return bytes(skin)


def skin_indices(skin, keep):
    """Triangle indices a retail skin's drawn submeshes with keep(geoset id) would take."""
    ns, os_, nt, ot = struct.unpack_from("<4I", skin, 28)
    drawn = {struct.unpack_from("<H", skin, ot + i * 24 + 4)[0] for i in range(nt)}
    return sum(struct.unpack_from("<H", skin, os_ + j * 48 + 10)[0] for j in drawn
               if keep(struct.unpack_from("<H", skin, os_ + j * 48)[0]))


def compact_vertices(b, skin):
    """Keep only the model vertices this skin uses; returns the skin with its lookup remapped.

    Retail skins index model vertices from a base offset in the header (0x2C, where 3.3.5 has
    boneCountMax): each LOD uses its own range, so one skin's vertices fit 3.3.5's u16 limit
    even when the whole model (gnoll2: 67697) does not.
    """
    nv, ov = struct.unpack_from("<II", skin, 4)
    base, = struct.unpack_from("<I", skin, 0x2C)
    used = [base + v for v in struct.unpack_from(f"<{nv}H", skin, ov)]
    order = sorted(set(used))
    if len(order) > 0xFFFF:
        raise ConvertError(f"skin uses {len(order)} vertices (3.3.5 indexes at most 65535)")
    n, off = struct.unpack_from("<II", b.d, 0x3C)
    if order[-1] >= n:
        raise ConvertError("skin references vertices outside the model")
    new_index = {v: i for i, v in enumerate(order)}
    b.set_array(0x3C, len(order), b"".join(bytes(b.d[off + v * 48:off + v * 48 + 48]) for v in order))
    out = bytearray(skin)
    struct.pack_into(f"<{nv}H", out, ov, *(new_index[v] for v in used))
    struct.pack_into("<I", out, 0x2C, 0)
    return bytes(out)


def first_track_value(d, track_off):
    """First key of an M2Track<M2SplineKey<float>> (the value, ignoring tangents), or None."""
    _, _, _, _, nv, ov = struct.unpack_from("<HhIIII", d, track_off)
    if not nv:
        return None
    n, o = struct.unpack_from("<II", d, ov)
    return struct.unpack_from("<f", d, o)[0] if n else None


def check(m2_bytes, skins, allow_level=False):
    """Read a converted model back and check every array and index lands inside the file."""
    m = M2(m2_bytes)
    assert m.version == VERSION_WOTLK and not m.chunks
    size = len(m.md20)
    for name, (n, off) in m.arrays.items():
        assert not n or 0 < off < size, f"{name} offset outside the file"
    for t, _, name in m.textures():
        assert t != 0 or name, "hardcoded texture without a name"
    n, off = m.arrays["particles"]
    for i in range(n):
        bone, tex = struct.unpack_from("<HH", m.md20, off + i * PARTICLE_WOTLK + 0x14)
        assert bone < m.count("bones") and tex < m.count("textures"), f"emitter {i} bone/texture out of range"
        for name_off in (0x18, 0x20):
            c, o = struct.unpack_from("<II", m.md20, off + i * PARTICLE_WOTLK + name_off)
            assert c and o, f"emitter {i} has no model name string (3.3.5 would read the header)"
    n_tex_lookup = m.count("texture_lookup")
    n_units = m.count("texture_unit_lookup")
    n_mat = m.count("materials")
    n_verts = m.count("vertices")
    d = m.md20
    nl, ol = m.arrays["bone_lookup"]
    bone_lookup = struct.unpack_from(f"<{nl}H", d, ol)
    _, voff = m.arrays["vertices"]
    n_colors = m.count("colors")
    n_seq, seq_off = m.arrays["sequences"]
    n, off = m.arrays["sequence_lookup"]
    for aid, k in enumerate(struct.unpack_from(f"<{n}h", d, off)):
        assert k == -1 or (k < n_seq and struct.unpack_from("<H", d, seq_off + k * SEQUENCE_SIZE)[0] == aid), \
            f"sequence lookup: id {aid} gives sequence {k}"
    nb, bo = m.arrays["bones"]
    assert all(struct.unpack_from("<i", d, bo + i * 88)[0] <= MAX_KEY_BONE for i in range(nb)), "key bone 3.3.5 lacks"
    assert m.count("key_bone_lookup") <= MAX_KEY_BONE + 1, "key bone lookup longer than 3.3.5's"
    n, off = m.arrays["texture_transform_lookup"]
    assert all(t < m.count("texture_transforms") for t in struct.unpack_from(f"<{n}h", d, off)), \
        "texture transform lookup points past the transforms"
    for s in skins:
        nv, ov, ni, oi, nb, ob, ns, os_, nt, ot = struct.unpack_from("<10I", s, 4)
        lookup = struct.unpack_from(f"<{nv}H", s, ov)
        indices = struct.unpack_from(f"<{ni}H", s, oi)
        assert max(lookup, default=0) < n_verts, "skin vertex outside the model"
        assert max(indices, default=0) < nv, "index outside the skin"
        for j in range(ns):
            level, vs, vc, istart, icount, bones, combo = struct.unpack_from("<7H", s, os_ + j * 48 + 2)
            assert allow_level or level == 0, f"submesh {j} has level {level} (3.3.5 ignores it)"
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
            assert color == -1 or color < n_colors, "batch color out of range"
            assert tcombo + tcount <= n_tex_lookup, "batch texture combo out of range"
            assert coord + tcount <= n_units, "batch coord combo out of range"
    return True
