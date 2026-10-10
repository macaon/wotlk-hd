"""Choose the unlinked upgrades (plan.py --unlinked) and their skins: writes out/pick.html.

usage: pick.py    then open out/pick.html, review, and save picks.json into this folder

Each old model gets a row: include or not, and for every old skin the retail display whose look it
takes (textures and geosets), pre-filled with the closest colour match. build.py reads picks.json.
An existing picks.json is loaded into the page, so choices can be revised later.
"""
import base64
import collections
import csv
import io
import json
import os

from PIL import Image

import build
import fetch
import plan
from mpq import Client

PICKS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "picks.json")
MAX_OPTIONS = 12   # retail looks offered per model, most used first
THUMB = 72
# Named characters and bosses: off unless ticked (their new models can look like someone else).
NAMED = {"jaina", "rexxar", "illidandark", "ragnaros", "archimonde", "kingymiron", "nightbane",
         "dragonkalecgos", "lich"}


def image(data):
    im = Image.open(io.BytesIO(data))
    im.load()
    return im.convert("RGBA")


def thumb(im):
    buf = io.BytesIO()
    im.resize((THUMB, THUMB)).save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def histogram(im):
    """Normalized 4x4x4 colour histogram of the opaque pixels."""
    px = list(im.resize((48, 48)).get_flattened_data())
    opaque = [p for p in px if p[3] >= 128] or px
    h = [0] * 64
    for r, g, b, _ in opaque:
        h[(r >> 6) * 16 + (g >> 6) * 4 + (b >> 6)] += 1
    return [x / len(opaque) for x in h]


def distance(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def main():
    client = Client()
    cdi = build.Dbc(client.read("DBFilesClient\\CreatureDisplayInfo.dbc"))
    cmd = build.Dbc(client.read("DBFilesClient\\CreatureModelData.dbc"))
    model_path = {r[0]: build.norm(cmd.string(r[2])) for r in cmd.rows}
    rdisp, rmodel, rgeosets = build.retail_tables()
    saved = json.load(open(PICKS)) if os.path.exists(PICKS) else {}
    taken = {old for old, _, _ in build.UPGRADES.values()}
    models = []
    for n_displays, old, new, old_tris, new_tris, _ in plan.unlinked():
        if old in taken:
            continue
        name = old.rsplit("/", 1)[1][:-3]
        model_dir = build.mpq_path(old).rsplit("\\", 1)[0]
        new_fid = fetch.fdid(new)
        # old skins: slot-0 texture name of the old model's displays
        old_skins = collections.Counter(
            cdi.string(r[build.CDI_TEX]).lower() for r in cdi.rows
            if model_path.get(r[build.CDI_MODEL]) == old and not r[build.CDI_EXTRA] and r[build.CDI_TEX])
        # retail looks: one per skin texture (its most used geosets, i.e. outfit), most used first
        outfits = collections.defaultdict(collections.Counter)
        for did, r in rdisp.items():
            if rmodel.get(int(r["ModelID"])) == new_fid:
                tex = build.retail_textures(r)
                if tex[0]:
                    outfits[tex][rgeosets[did]] += 1
        looks = {}
        for tex, by_geo in outfits.items():
            geo = by_geo.most_common(1)[0][0]
            looks[(tex, geo)] = [did for did, r in rdisp.items()
                                 if rmodel.get(int(r["ModelID"])) == new_fid
                                 and build.retail_textures(r) == tex and rgeosets[did] == geo]
        options = sorted(looks.items(), key=lambda kv: -sum(outfits[kv[0][0]].values()))[:MAX_OPTIONS]
        if not old_skins or not options:
            continue
        opts = []
        for (tex, geo), dids in options:
            im = image(fetch.get(tex[0]))
            opts.append({"display": min(dids), "label": fetch.name(tex[0]).rsplit("/", 1)[1][:-4],
                         "uses": sum(outfits[tex].values()), "geosets": geo, "thumb": thumb(im), "hist": histogram(im)})
        skins = []
        for tex_name, count in old_skins.most_common():
            data = client.read(f"{model_dir}\\{tex_name}.blp")
            if not data:
                continue
            im = image(data)
            h = histogram(im)
            best = min(opts, key=lambda o: distance(o["hist"], h))
            skins.append({"tex": tex_name, "count": count, "thumb": thumb(im), "auto": best["display"]})
        prior = saved.get(name, {})
        models.append({
            "name": name, "old": old, "new": new, "triangles": [old_tris, new_tris],
            "displays": n_displays,
            "include": prior.get("include", name not in NAMED and n_displays > 3),
            "options": [{k: v for k, v in o.items() if k != "hist"} for o in opts],
            "skins": [dict(s, pick=prior.get("skins", {}).get(s["tex"], s["auto"])) for s in skins],
        })
        print(f"{name}: {len(skins)} skins, {len(opts)} retail looks", flush=True)
    out = os.path.join(build.OUT, "pick.html")
    with open(out, "w") as f:
        f.write(PAGE.replace("/*DATA*/", json.dumps(models)))
    print(f"wrote {out}: {len(models)} models")


PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>Upgrade Picker</title>
<style>
:root { --bg: #f6f6f4; --fg: #1d1f22; --muted: #6b7076; --panel: #ffffff; --line: #dcdcd8; --accent: #2f6fdb; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #15171a; --fg: #e6e6e6; --muted: #9aa0a6; --panel: #202328; --line: #33373d; --accent: #6ea0ff; } }
body { margin: 0; background: var(--bg); color: var(--fg); font: 14px system-ui, sans-serif; }
header { position: sticky; top: 0; z-index: 1; display: flex; gap: 12px; align-items: center; flex-wrap: wrap;
  padding: 10px 16px; background: var(--panel); border-bottom: 1px solid var(--line); }
header .grow { flex: 1; }
button, label.btn { font: inherit; padding: 6px 12px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--bg); color: var(--fg); cursor: pointer; }
main { padding: 16px; display: grid; gap: 16px; max-width: 1400px; margin: 0 auto; }
section { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 12px 16px; }
section.off { opacity: 0.45; }
h2 { font-size: 16px; margin: 0; display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
h2 small { color: var(--muted); font-weight: normal; }
.skin { display: flex; gap: 12px; align-items: flex-start; margin-top: 12px; }
.old { width: 96px; flex: none; text-align: center; font-size: 12px; color: var(--muted); overflow-wrap: anywhere; }
.opts { display: flex; gap: 6px; flex-wrap: wrap; }
.opt { width: 80px; font-size: 11px; color: var(--muted); text-align: center; cursor: pointer;
  border: 2px solid transparent; border-radius: 6px; padding: 2px; overflow-wrap: anywhere; }
.opt.sel { border-color: var(--accent); color: var(--fg); }
.opt.auto::after { content: " (auto)"; }
img { width: 72px; height: 72px; display: block; margin: 0 auto 2px; border-radius: 4px; image-rendering: auto; }
.arrow { align-self: center; color: var(--muted); font-size: 20px; }
</style></head><body>
<header><b>Upgrade picker</b><span id="count"></span><span class="grow"></span>
<button id="all">Include all</button><button id="none">Include none</button>
<label class="btn">Load picks.json<input id="load" type="file" accept=".json" hidden></label>
<button id="save">Save picks.json</button></header>
<main id="list"></main>
<script>
const MODELS = /*DATA*/;
const KEY = "wotlk-hd-picks";
let picks = {};
for (const m of MODELS) picks[m.name] = { include: m.include, skins: Object.fromEntries(m.skins.map(s => [s.tex, s.pick])) };
try { Object.assign(picks, JSON.parse(localStorage.getItem(KEY) || "{}")); } catch (e) {}
function remember() { try { localStorage.setItem(KEY, JSON.stringify(picks)); } catch (e) {} count(); }
function count() {
  const n = MODELS.filter(m => picks[m.name].include).length;
  document.getElementById("count").textContent = `${n} of ${MODELS.length} models included`;
}
function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) k === "class" ? e.className = v : e.setAttribute(k, v);
  kids.forEach(k => e.append(k));
  return e;
}
function render() {
  const list = document.getElementById("list");
  list.replaceChildren();
  for (const m of MODELS) {
    const p = picks[m.name];
    const box = el("input", { type: "checkbox" });
    box.checked = p.include;
    const sec = el("section", { class: p.include ? "" : "off" });
    box.onchange = () => { p.include = box.checked; sec.className = p.include ? "" : "off"; remember(); };
    sec.append(el("h2", {}, box, `${m.name}`,
      el("small", {}, `${m.old} \\u2192 ${m.new} \\u00b7 ${m.triangles[0]} \\u2192 ${m.triangles[1]} triangles \\u00b7 ${m.displays} displays`)));
    for (const s of m.skins) {
      const opts = el("div", { class: "opts" });
      for (const o of m.options) {
        const d = el("div", { class: "opt" + (p.skins[s.tex] === o.display ? " sel" : "") + (s.auto === o.display ? " auto" : ""),
                              title: `retail display ${o.display}, ${o.uses} displays use this look` },
                     el("img", { src: o.thumb, alt: o.label }), o.label);
        d.onclick = () => { p.skins[s.tex] = o.display; [...opts.children].forEach(c => c.classList.remove("sel")); d.classList.add("sel"); remember(); };
        opts.append(d);
      }
      sec.append(el("div", { class: "skin" },
        el("div", { class: "old" }, el("img", { src: s.thumb, alt: s.tex }), `${s.tex} (${s.count})`),
        el("div", { class: "arrow" }, "\\u2192"), opts));
    }
    list.append(sec);
  }
  count();
}
document.getElementById("all").onclick = () => { MODELS.forEach(m => picks[m.name].include = true); remember(); render(); };
document.getElementById("none").onclick = () => { MODELS.forEach(m => picks[m.name].include = false); remember(); render(); };
document.getElementById("save").onclick = () => {
  const out = {};
  for (const m of MODELS) out[m.name] = { include: picks[m.name].include, old: m.old, new: m.new, skins: picks[m.name].skins };
  const a = el("a", { href: URL.createObjectURL(new Blob([JSON.stringify(out, null, 1)], { type: "application/json" })), download: "picks.json" });
  a.click();
};
document.getElementById("load").onchange = async e => {
  const data = JSON.parse(await e.target.files[0].text());
  for (const [k, v] of Object.entries(data)) if (picks[k]) picks[k] = { include: v.include, skins: v.skins };
  remember(); render();
};
render();
</script></body></html>
"""

if __name__ == "__main__":
    main()
