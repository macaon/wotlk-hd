"""Old and converted models side by side: writes out/compare.html (open it in a browser).

usage: compare.py [name ...]    upgrades from build.py (default: all), needs out/patch-enUS-4.MPQ

Writes one data file per model to out/compare/, loaded when picked, so the page stays small.

Old model, textures and display row come from the client; the converted ones from the patch. Bind
pose, no animation. Both views share one camera and keep their in-game size.
"""
import base64
import io
import json
import os
import struct
import sys

from PIL import Image

import build
from m2 import M2
from mpq import CHAIN, Client

# Display to show per upgrade (Ghostlands ones); others use the model's first display.
DISPLAYS = {"murloc": 3619, "minespider": 1087, "rat": 1141, "frog": 901,
            "zombie": 1200, "skeleton": 158, "larva": 9904, "dragonhawk": 17545,
            "zombiearm": 1197, "banshee": 10728, "manawurm": 15934, "crab": 999, "ghoul": 137,
            "gnoll": 848, "gnollmelee": 10851, "gnollcaster": 10854, "ent": 15588, "rabbit": 328,
            "fleshgolem": 15962, "spirithealer": 5233, "horse": 229}
PATCH = os.path.join(build.OUT, "patch-enUS-4.MPQ")


def b64(arr, fmt):
    return base64.b64encode(struct.pack(f"<{len(arr)}{fmt}", *arr)).decode()


def png(data):
    im = Image.open(io.BytesIO(data))
    im.load()
    buf = io.BytesIO()
    im.convert("RGBA").save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def visible(geoset, field):
    """3.3.5 rule as build.py writes it: group n shows the variant in nibble n (none if unset)."""
    if not geoset:
        return True
    group, variant = divmod(geoset, 100)
    chosen = (field >> (4 * (group - 1))) & 0xF if 1 <= group <= 8 else 0
    return variant == chosen


def mesh(client, path, cdi, row, textures):
    """Geometry, draw groups and stats for one model as drawn for one display row."""
    m = M2(client.read(path))
    d = m.md20
    skin = client.read(path[:-3] + "00.skin")
    nv, ov, ni, oi, _, _, ns, os_, nt, ot = struct.unpack_from("<10I", skin, 4)
    lookup = struct.unpack_from(f"<{nv}H", skin, ov)
    indices = struct.unpack_from(f"<{ni}H", skin, oi)
    subs = [struct.unpack_from("<6H", skin, os_ + i * 48) for i in range(ns)]
    n, off = m.arrays["vertices"]
    pos, nrm, uv = [], [], []
    for v in lookup:
        x, y, z = struct.unpack_from("<3f", d, off + v * 48)
        a, b, c = struct.unpack_from("<3f", d, off + v * 48 + 20)
        u, w = struct.unpack_from("<2f", d, off + v * 48 + 32)
        pos += [x, z, -y]  # WoW is z-up, three.js y-up
        nrm += [a, c, -b]
        uv += [u, w]
    slots = m.textures()
    n, off = m.arrays["texture_lookup"]
    tex_lookup = struct.unpack_from(f"<{n}H", d, off)
    mats = m.materials()
    model_dir = path.rsplit("\\", 1)[0]
    groups, tris = [], []
    for i in range(nt):
        _, _, _, sub, _, _, mat, layer, _, tcombo = struct.unpack_from("<BbHHHhHHHH", skin, ot + i * 24)
        sid, level, _, _, istart, icount = subs[sub]
        if layer or not visible(sid, row[build.CDI_GEOSETS]):
            continue
        ttype, _, name = slots[tex_lookup[tcombo]]
        if ttype == 0:
            tpath = name
        elif 11 <= ttype <= 13 and row[build.CDI_TEX + ttype - 11]:
            tpath = f"{model_dir}\\{cdi.string(row[build.CDI_TEX + ttype - 11])}.blp"
        else:
            tpath = None
        key = tpath.lower() if tpath else ""
        if key and key not in textures:
            data = client.read(tpath)
            textures[key] = png(data) if data else ""
        start = istart + (level << 16)
        groups.append({"start": len(tris), "count": icount, "tex": key, "blend": mats[mat][1],
                       "twoSided": bool(mats[mat][0] & 4)})
        tris += indices[start:start + icount]
    return {"pos": b64(pos, "f"), "nrm": b64(nrm, "f"), "uv": b64(uv, "f"), "idx": b64(tris, "I"),
            "groups": groups, "scale": build.f32(row[build.CDI_SCALE]),
            "stats": f"{m.count('vertices')} vertices, {len(tris) // 3} triangles, {m.count('bones')} bones"}


def first_display(cdi, model_rows, old_path, new_rows, new_model_path):
    """A display of the old model to show, preferring one the patch changed (some may keep the old
    model): DISPLAYS' choice, else the first non-humanoid display."""
    models = {r[0] for r in model_rows if build.norm(r[1]) == old_path}
    dids = [r[0] for r in cdi.rows if r[build.CDI_MODEL] in models and not r[build.CDI_EXTRA]]
    moved = [d for d in dids if new_model_path.get(new_rows[d][build.CDI_MODEL]) != build.mpq_path(old_path)]
    return (moved or dids or [None])[0]


def main(names):
    old = Client()
    new = Client(chain=[PATCH] + CHAIN)  # an absolute path wins over the Data/ join
    old_cdi = build.Dbc(old.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    new_cdi = build.Dbc(new.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    cmd = build.Dbc(old.read("DBFilesClient\\CreatureModelData.dbc"))
    model_rows = [(r[0], cmd.string(r[2])) for r in cmd.rows]
    new_cmd = build.Dbc(new.read("DBFilesClient\\CreatureModelData.dbc"))
    new_model_path = {r[0]: build.mpq_path(build.norm(new_cmd.string(r[2]))) for r in new_cmd.rows}
    old_rows = {r[0]: r for r in old_cdi.rows}
    new_rows = {r[0]: r for r in new_cdi.rows}
    data_dir = os.path.join(build.OUT, "compare")
    os.makedirs(data_dir, exist_ok=True)
    index = []
    for name in names:
        old_path, new_path, _ = build.UPGRADES[name]
        path = build.mpq_path(old_path)
        did = DISPLAYS.get(name) or first_display(old_cdi, model_rows, old_path, new_rows, new_model_path)
        if did is None:
            continue
        # a display moved to <name>_hd.m2 when other skins keep the old model (build.py KEEP)
        npath = new_model_path[new_rows[did][build.CDI_MODEL]]
        if not new.read(npath) or new.read(npath) == old.read(path):
            continue  # not in the patch (refused by the converter)
        textures = {}
        try:
            creature = {"from": old_path, "to": new_path,
                        "old": mesh(old, path, old_cdi, old_rows[did], textures),
                        "new": mesh(new, npath, new_cdi, new_rows[did], textures)}
        except (struct.error, KeyError, IndexError) as e:
            print(f"{name}: cannot show ({e})")
            continue
        with open(os.path.join(data_dir, f"{name}.js"), "w") as f:
            f.write(f"LOADED({json.dumps(name)}, {json.dumps({'creature': creature, 'textures': textures})});")
        index.append({"name": name, "label": f"{name} (display {did})"})
    html = PAGE.replace("/*DATA*/", json.dumps(index))
    out = os.path.join(build.OUT, "compare.html")
    with open(out, "w") as f:
        f.write(html)
    print(f"wrote {out}: {len(index)} models, data in {data_dir}/")


PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>Model Compare</title>
<style>
:root { --bg: #15171a; --fg: #e6e6e6; --muted: #9aa0a6; --panel: #202328; }
html, body { margin: 0; height: 100%; overflow: hidden; background: var(--bg); color: var(--fg); font: 14px system-ui, sans-serif; }
header { display: flex; gap: 16px; align-items: center; padding: 10px 16px; background: var(--panel); flex-wrap: wrap; }
select { font: inherit; padding: 4px 8px; }
#labels { display: flex; position: absolute; top: 52px; left: 0; right: 0; pointer-events: none; }
#labels div { flex: 1; padding: 8px 16px; }
#labels b { display: block; font-size: 16px; }
#labels span { color: var(--muted); }
canvas { display: block; width: 100%; height: calc(100% - 44px); }
.hint { color: var(--muted); }
</style></head><body>
<header><select id="pick"></select><span class="hint">drag to orbit, scroll to zoom, right-drag to pan</span></header>
<div id="labels"><div><b>3.3.5</b><span id="a"></span></div><div><b>retail, converted</b><span id="b"></span></div></div>
<canvas id="c"></canvas>
<script type="importmap">{"imports": {"three": "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js",
 "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/"}}</script>
<script type="module">
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
const INDEX = /*DATA*/;
const cache = {};
let textures = {};
const canvas = document.getElementById("c");
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(devicePixelRatio);
renderer.setScissorTest(true);
const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 1000);
const controls = new OrbitControls(camera, canvas);
const loader = new THREE.TextureLoader();
const texCache = {};
function tex(key) {
  if (!key || !textures[key]) return null;
  if (!texCache[key]) {
    const t = loader.load(textures[key]);
    t.flipY = false; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace;
    texCache[key] = t;
  }
  return texCache[key];
}
const f32 = s => new Float32Array(Uint8Array.from(atob(s), c => c.charCodeAt(0)).buffer);
const u32 = s => new Uint32Array(Uint8Array.from(atob(s), c => c.charCodeAt(0)).buffer);
function scene(m) {
  const s = new THREE.Scene();
  s.background = new THREE.Color(0x2a2e34);
  s.add(new THREE.HemisphereLight(0xffffff, 0x444444, 1.6));
  const sun = new THREE.DirectionalLight(0xffffff, 1.4); sun.position.set(3, 5, 4); s.add(sun);
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(f32(m.pos), 3));
  g.setAttribute("normal", new THREE.BufferAttribute(f32(m.nrm), 3));
  g.setAttribute("uv", new THREE.BufferAttribute(f32(m.uv), 2));
  g.setIndex(new THREE.BufferAttribute(u32(m.idx), 1));
  const mats = m.groups.map((gr, i) => {
    g.addGroup(gr.start, gr.count, i);
    const t = tex(gr.tex);
    return new THREE.MeshLambertMaterial({
      map: t, color: t ? 0xffffff : 0xff00ff, side: gr.twoSided ? THREE.DoubleSide : THREE.FrontSide,
      alphaTest: gr.blend === 1 ? 0.5 : 0, transparent: gr.blend >= 2, depthWrite: gr.blend < 2,
      blending: gr.blend === 4 || gr.blend === 3 ? THREE.AdditiveBlending : THREE.NormalBlending });
  });
  const mesh = new THREE.Mesh(g, mats);
  mesh.scale.setScalar(m.scale);
  s.add(mesh);
  return s;
}
let scenes = [];
window.LOADED = (name, data) => { cache[name] = data; show(name); };
function select(name) {
  location.hash = name;
  if (cache[name]) return show(name);
  const s = document.createElement("script");
  s.src = `compare/${name}.js`;
  document.head.appendChild(s);
}
function show(name) {
  if (name !== location.hash.slice(1)) return;  // a slower load for an earlier pick
  textures = cache[name].textures;
  for (const k in texCache) delete texCache[k];
  const c = cache[name].creature;
  scenes = [scene(c.old), scene(c.new)];
  document.getElementById("a").textContent = `${c.from}: ${c.old.stats}`;
  document.getElementById("b").textContent = `${c.to}: ${c.new.stats}`;
  const box = new THREE.Box3();
  scenes.forEach(s => box.expandByObject(s));
  const size = box.getSize(new THREE.Vector3()).length(), mid = box.getCenter(new THREE.Vector3());
  controls.target.copy(mid);
  camera.position.copy(mid).add(new THREE.Vector3(size * 0.9, size * 0.35, size * 0.9));
  camera.near = size / 100; camera.far = size * 20; camera.updateProjectionMatrix();
  controls.update();
}
const pick = document.getElementById("pick");
INDEX.forEach(c => pick.add(new Option(c.label, c.name)));
pick.onchange = () => select(pick.value);
const start = INDEX.find(c => c.name === location.hash.slice(1)) || INDEX[0];
pick.value = start.name;
select(start.name);
function frame() {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (canvas.width !== Math.floor(w * devicePixelRatio)) renderer.setSize(w, h, false);
  camera.aspect = (w / 2) / h; camera.updateProjectionMatrix();
  scenes.forEach((s, i) => {
    renderer.setViewport(i * w / 2, 0, w / 2, h);
    renderer.setScissor(i * w / 2, 0, w / 2, h);
    renderer.render(s, camera);
  });
  requestAnimationFrame(frame);
}
frame();
</script></body></html>
"""

if __name__ == "__main__":
    names = sys.argv[1:] or list(build.UPGRADES)
    main(names)
