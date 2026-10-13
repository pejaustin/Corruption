"""One-time use (2026-10-13): writes tools/deprecated/gen_water_blockers.gd's output into a landscape scene as text.
Austin, 2026-10-13: no bank walls; height-limited blockers; bridges and fords work by placement.
  - removes every water body's Wall / Wall/Shape override and its ConcavePolygonShape3D, and the old Blocker nodes
  - adds the sea's blocker and the river's per-chunk blockers as plain NavigationObstacle3D nodes under <body>/Blockers
    (400 m: Waters/Pale River gets a Blockers node; the sea gets Waters/Glittering Ocean/Blockers, its look is `Ocean`)
  - sets each RiverCrossing's Ford slab top (editable children) to the generated height
Nothing else in the scene is touched.
Usage: python3 tools/deprecated/apply_water_blockers.py <repo_root> <size> <generated.json>"""
import json
import re
import sys

root, size, data_path = sys.argv[1:4]
path = f"{root}/art/world/export/world_landscape_{size}.tscn"
data = json.load(open(data_path))
text = open(path).read()
SEA, RIVER = "Glittering Ocean", "Pale River"

# split into sections (each starts with "[")
sections = re.split(r"\n(?=\[)", text.rstrip("\n"))
head = sections[0]


def parent_of(h):
    m = re.search(r' parent="((?:[^"\\]|\\.)*)"', h)
    return m.group(1).replace("\\'", "'") if m else None


def name_of(h):
    return re.search(r' name="((?:[^"\\]|\\.)*)"', h).group(1).replace("\\'", "'")


drop_subs = set()
kept = []
for sec in sections:
    h = sec.split("\n", 1)[0]
    if h.startswith("[node"):
        par, name = parent_of(h), name_of(h)
        if par and par.startswith("Waters/") and (name == "Wall" or par.endswith("/Wall")):
            drop_subs.update(re.findall(r'SubResource\("([^"]+)"\)', sec))
            continue
        if par and par.startswith("Waters/") and par.endswith("/Blockers") and h.find("NavigationObstacle3D") > 0:
            continue
    kept.append(sec)
sections = [s for s in kept if not (s.startswith("[sub_resource") and re.search(r' id="([^"]+)"', s.split("\n", 1)[0]).group(1) in drop_subs)]


def num(x):
    return ("%.2f" % x).rstrip("0").rstrip(".") if abs(x) >= 0.005 else "0"


def blocker(parent, i, b):
    verts = ", ".join(f"{num(p[0])}, 0, {num(p[1])}" for p in b["outline"])
    return "\n".join([
        f'[node name="Blocker{i}" type="NavigationObstacle3D" parent="{parent}"]',
        f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {num(b['bottom'])}, 0)",
        f"height = {num(b['top'] - b['bottom'])}",
        f"vertices = PackedVector3Array({verts})",
        "affect_navigation_mesh = true",
        "carve_navigation_mesh = true",
        "avoidance_enabled = false",
        ""])


new = []
if size == "2km":
    sea_parent, river_parent = f"Waters/{SEA}/Blockers", f"Waters/{RIVER}/Blockers"
else:
    new.append(f'[node name="{SEA}" type="Node3D" parent="Waters"]\n')
    new.append(f'[node name="Blockers" type="Node3D" parent="Waters/{SEA}"]\n')
    new.append(f'[node name="Blockers" type="Node3D" parent="Waters/{RIVER}"]\n')
    sea_parent, river_parent = f"Waters/{SEA}/Blockers", f"Waters/{RIVER}/Blockers"
new.append(blocker(sea_parent, 0, data["sea"]))
for i, b in enumerate(data["river"]):
    new.append(blocker(river_parent, i, b))
editables = []
for f in data["fords"]:
    p = f["path"].replace("'", "\\'")
    local_y = f["top"] - f["y"] - 0.1   # the slab is 0.2 m thick, its top 0.1 over the Ford node
    new.append(f'[node name="Ford" parent="{p}" index="0"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {num(local_y)}, 0)\n')
    editables.append(f'[editable path="{p}"]\n')
# nodes go after the last [node] section, editable lines at the very end
last_node = max(i for i, s in enumerate(sections) if s.startswith("[node"))
out = sections[:last_node + 1] + [s.rstrip("\n") for s in new] + sections[last_node + 1:] + [e.rstrip("\n") for e in editables]
text = ""
for i, sec in enumerate(out):
    if i:
        text += "\n" if sec.startswith("[ext_resource") and out[i - 1].startswith("[ext_resource") else "\n\n"
    text += sec.rstrip("\n")
open(path, "w").write(text + "\n")
print(size, "dropped sub_resources", len(drop_subs), "blockers", 1 + len(data["river"]), "fords", len(data["fords"]))
