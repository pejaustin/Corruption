"""Rough stand-in shapes for each kind of POI (all PLACEHOLDER). Origin = the POI's ground centre, +Y is north,
the gate / approach faces south (-Y) unless noted. Used by build_pois.py (full, with collision) and
build_landscape.py (visual only, small, at each poi_ marker)."""
import math

from common import *

T = lambda k: (k, k, k, 1.0)


class Site:
    def __init__(self):
        self.vis = Builder()
        self.col = Builder()
        self.props = []  # (prop collection name, loc, rot_z, scale)

    # -- primitives (vis, plus a box in the collision builder when col=True) --
    def box(self, loc, size, mat="stone", k=1.0, rot=0.0, col=True):
        self.vis.box(loc, size, mat, T(k), rot)
        if col:
            self.col.box(loc, size, "stone", T(1), rot)

    def cyl(self, loc, r, h, mat="stone", k=1.0, segs=8, col=True):
        self.vis.cone(loc, (r, r, h), mat, T(k), top=1.0, segs=segs)
        if col:
            self.col.box(loc, (2 * r, 2 * r, h), "stone", T(1))

    def roof(self, loc, r, h, mat="roof", k=1.0, segs=8):
        self.vis.cone(loc, (r, r, h), mat, T(k), top=0.0, segs=segs)

    def ball(self, loc, r, mat="leaf_round", k=1.0):
        self.vis.ico(loc, (r, r, r), mat, T(k))

    def prop(self, name, loc, rot=0.0, scale=1.0):
        self.props.append((name, loc, rot, scale))

    def gable(self, loc, w, d, h, mat="roof", k=1.0, rot=0.0):
        b = self.vis
        c, s = math.cos(rot), math.sin(rot)
        def p(x, y, z):
            return (loc[0] + x * c - y * s, loc[1] + x * s + y * c, loc[2] + z)
        base = [p(-w / 2, -d / 2, 0), p(w / 2, -d / 2, 0), p(w / 2, d / 2, 0), p(-w / 2, d / 2, 0)]
        r0, r1 = p(-w / 2, 0, h), p(w / 2, 0, h)
        b.quad([base[0], base[3], base[2], base[1]], mat, T(k * 0.7))
        b.quad([base[0], base[1], r1, r0], mat, T(k))
        b.quad([base[2], base[3], r0, r1], mat, T(k * 0.9))
        b.quad([base[3], base[0], r0], mat, T(k * 0.8))
        b.quad([base[1], base[2], r1], mat, T(k * 0.8))

    def house(self, loc, w=7.0, d=6.0, h=4.0, rot=0.0):
        self.box(loc, (w, d, h), "plaster", 0.95, rot)
        self.gable((loc[0], loc[1], loc[2] + h), w + 0.8, d + 0.8, 2.5, rot=rot)

    def wall_line(self, a, b, h=7.0, t=2.0, mat="stone", gap=0.0):
        """Wall from point a to b (x, y); gap = length of an opening at the middle."""
        ax, ay = a
        bx, by = b
        L = math.hypot(bx - ax, by - ay)
        ang = math.atan2(by - ay, bx - ax)
        segs = [(0.0, L)] if gap <= 0 else [(0.0, (L - gap) / 2), ((L + gap) / 2, L)]
        for s0, s1 in segs:
            m = (s0 + s1) / 2
            self.box((ax + math.cos(ang) * m, ay + math.sin(ang) * m, 0), (s1 - s0, t, h), mat, 0.95, ang)

    def tower(self, loc, r=3.5, h=12.0, roof=True):
        self.cyl(loc, r, h, "stone", 0.9, segs=8)
        if roof:
            self.roof((loc[0], loc[1], loc[2] + h), r * 1.25, r * 1.6, "roof", 1.0, 8)

    def ring_wall(self, R, n, h=7.0, t=2.0, gate_idx=0, gap=8.0, tower_r=3.5, tower_h=11.0):
        # gate faces south: vertex 0 of the ring sits at angle -90 deg + half step so segment gate_idx is south
        step = 2 * math.pi / n
        pts = [(R * math.cos(-math.pi / 2 - step / 2 + i * step), R * math.sin(-math.pi / 2 - step / 2 + i * step))
               for i in range(n)]
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            self.wall_line(a, b, h, t, gap=gap if i == gate_idx else 0.0)
        for p in pts:
            self.tower((p[0], p[1], 0), tower_r, tower_h)

    def rect_wall(self, w, d, h=7.0, t=2.0, gap=8.0, tower_r=3.5, tower_h=11.0):
        c = [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]
        self.wall_line(c[0], c[1], h, t, gap=gap)  # south side has the gate
        self.wall_line(c[1], c[2], h, t)
        self.wall_line(c[2], c[3], h, t)
        self.wall_line(c[3], c[0], h, t)
        for p in c:
            self.tower((p[0], p[1], 0), tower_r, tower_h)

    def dais(self, loc, w, d, h, mat="stone", k=0.85):
        self.box(loc, (w, d, h), mat, k)


# ---------------------------------------------------------------- kinds
def castle(s):  # Avequal'la: castle by a lake, spires
    s.rect_wall(46, 38, 8, 2.5, gap=9, tower_r=4, tower_h=14)
    s.box((0, 4, 0), (16, 14, 16), "stone", 0.9)
    for dx in (-5, 0, 5):
        s.tower((dx, 4, 16), 2.2, 6, roof=True)
        s.roof((dx, 4, 22), 3.2, 8, "roof", 1.0, 6)
    s.house((-14, -4, 0), 8, 6, 5)
    s.house((14, -4, 0), 8, 6, 5)


def fort(s):  # Nof'ishun: plain square fort in the mountains
    s.rect_wall(30, 24, 7, 2.2, gap=7, tower_r=3, tower_h=10)
    s.box((0, 4, 0), (10, 8, 9), "stone", 0.85)
    s.gable((0, 4, 9), 11, 9, 3, "roof")


def walled_town_round(s):  # Valley Cross: walled town in fields, round walls with towers
    s.ring_wall(34, 8, 7, 2, 0, 9, 3.5, 11)
    s.box((0, 4, 0), (12, 10, 12), "stone", 0.9)
    s.roof((0, 4, 12), 8, 6, "roof", 1.0, 4)
    for i, (x, y) in enumerate([(-18, -4), (-14, 14), (14, 12), (19, -2), (-6, -16), (8, -17), (-2, 20), (18, 18)]):
        s.house((x * 0.8, y * 0.8, 0), 6, 6, 3.5, rot=0.4 * i)


def walled_town_square(s):  # Hope's Gates: walled town where rivers meet, tall gate towers
    s.rect_wall(64, 52, 8, 2.5, gap=10, tower_r=4.5, tower_h=13)
    s.box((0, 14, 0), (16, 12, 15), "stone", 0.9)
    s.roof((0, 14, 15), 11, 8, "roof", 1.0, 4)
    for i, (x, y) in enumerate([(-22, -10), (-10, -14), (10, -14), (22, -10), (-22, 6), (-24, 18), (22, 6), (24, 18),
                                (-8, 0), (8, 0)]):
        s.house((x, y, 0), 7, 6, 4, rot=0.15 * i)


def hamlet(s):  # Teshfield: small settlement on the river (no wall)
    for i, (x, y) in enumerate([(-12, 4), (-4, 12), (8, 10), (14, 0), (-14, -10), (6, -12), (-2, -2)]):
        s.house((x, y, 0), 6.5, 5.5, 3.5, rot=0.3 * i)
    s.box((22, 6, 0), (6, 3, 0.4), "wood", 0.9, col=False)  # landing stage
    s.prop("fence", (-20, -2, 0), math.pi / 2)
    s.prop("fence", (-20, 2.0, 0), math.pi / 2)


def farm(s):  # Alebend: farm and windmill
    s.box((-8, 6, 0), (14, 8, 4), "wood", 0.9)
    s.gable((-8, 6, 4), 15, 9, 4, "roof")
    s.house((8, -4, 0), 7, 6, 3.5)
    s.cyl((22, 10, 0), 4.0, 12, "plaster", 0.95, 8)
    s.roof((22, 10, 12), 4.6, 4.5, "roof", 1.0, 8)
    s.box((22, 5.2, 8.2), (0.4, 0.3, 7.6), "wood", 0.9, col=False)  # sails (a cross)
    s.box((22, 5.2, 11.8), (7.6, 0.3, 0.4), "wood", 0.9, col=False)
    s.box((10, -22, 0.05), (36, 18, 0.1), "dirt", 0.8, col=False)  # field patch
    for i in range(5):
        s.prop("fence", (-26 + i * 3, -30, 0))


def ford(s):  # Lastford: shallow east-west river with a north-south crossing, a post each side, a grove
    s.box((0, 0, -0.3), (64, 14, 0.3), "water", 1.0, col=False)  # placeholder water strip
    for i in range(7):
        s.box((-8, -4.5 + i * 1.5, -0.2), (1.6, 1.6, 0.5), "rock", 0.9, col=False)  # stepping stones
    s.box((-4, -11, 0), (1.6, 1.6, 5), "stone", 0.85)
    s.box((4, 11, 0), (1.6, 1.6, 5), "stone", 0.85)
    for i, (x, y) in enumerate([(-26, 10), (-32, 20), (-22, 24), (-34, 6), (-28, 32)]):
        s.prop("tree_lollipop", (x, y, 0), i * 1.1, 1.0 + 0.1 * i)


def gate_ruin(s):  # Old Gate: pillars and a broken lintel, ruined walls
    s.box((-6, 0, 0), (2.4, 2.4, 9), "stone", 0.8)
    s.box((6, 0, 0), (2.4, 2.4, 7), "stone", 0.75)
    s.box((-3.5, 0, 9), (7, 2, 1.6), "stone", 0.85, rot=0.1, col=False)
    s.box((-4, -1, 0), (2, 2, 1.4), "stone", 0.8, rot=0.5, col=False)
    s.prop("ruin_wall", (-16, 0, 0), 0.0)
    s.prop("ruin_wall", (16, 2, 0), math.pi)
    s.prop("rock", (8, -8, 0), 1.0)


def harbour(s):  # unnamed coastal town: pier, boat, warehouse, houses. Sea lies to the east (+X)
    s.box((14, 0, -0.4), (46, 40, 0.1), "water", 1.0, col=False)  # sea patch, east
    s.box((26, -2, 0), (34, 4, 0.7), "wood", 0.9)  # pier
    for x in range(12, 40, 6):
        s.box((x, -4.3, -1.5), (0.5, 0.5, 2.2), "wood", 0.7, col=False)
        s.box((x, 0.3, -1.5), (0.5, 0.5, 2.2), "wood", 0.7, col=False)
    s.box((36, 8, 0), (6, 2.4, 1.2), "wood", 0.85, col=False)  # boat hull
    s.box((36, 8, 1.2), (0.3, 0.3, 7), "wood", 0.9, col=False)
    s.box((36, 8, 5), (0.2, 3.5, 3.5), "plaster", 1.0, col=False)  # sail
    s.box((-8, 4, 0), (14, 9, 5), "wood", 0.9)
    s.gable((-8, 4, 5), 15, 10, 3.5, "roof")
    for i, (x, y) in enumerate([(-22, -8), (-12, -14), (-24, 8), (-4, -14)]):
        s.house((x, y, 0), 6.5, 6, 3.5, rot=0.3 * i)


def river_tower(s):  # Entwar: tower at the river mouth (NOT one of the four player towers)
    s.cyl((0, 0, 0), 5, 20, "stone", 0.9, 8)
    s.roof((0, 0, 20), 6.4, 7, "roof", 1.0, 8)
    s.wall_line((-12, -10), (12, -10), 5, 2, gap=6)
    s.wall_line((12, -10), (12, 8), 5, 2)
    s.wall_line((-12, 8), (-12, -10), 5, 2)
    s.box((20, 2, 0), (14, 4, 0.6), "wood", 0.9, col=False)  # quay


def volcano(s):  # Hell's Mouth: crater with lava in a ring of ash
    s.vis.cone((0, 0, 0), (90, 90, 45), "ash", T(0.8), top=0.3, segs=12)
    s.col.cone((0, 0, 0), (90, 90, 45), "stone", T(1), top=0.3, segs=12)
    s.vis.cone((0, 0, 45.1), (24, 24, 0.3), "lava", T(1.0), top=1.0, segs=12)
    for i in range(6):
        a = i * math.pi / 3
        s.prop("rock", (math.cos(a) * 70, math.sin(a) * 70, 0), a, 2.0)


def forest_clearing(s):  # Northwood: a clearing ringed with pines, a stone marker
    s.box((0, 0, 0), (2.5, 2.5, 3), "stone", 0.85)
    for i in range(18):
        a = i * 2 * math.pi / 18 + 0.2 * (i % 3)
        r = 30 + 8 * (i % 3)
        s.prop("tree_cone", (math.cos(a) * r, math.sin(a) * r, 0), a, 1.0 + 0.15 * (i % 4))
    s.prop("rock", (8, -6, 0), 0.7)


def great_tree(s):  # The Elder Woods: one huge tree among ordinary ones
    s.cyl((0, 0, 0), 4, 28, "bark", 0.9, 6)
    for dx, dy, dz, r in [(0, 0, 38, 14), (-12, 4, 32, 9), (11, -3, 30, 9), (3, 10, 27, 7)]:
        s.ball((dx, dy, dz), r, "leaf_round", 1.0)
    for i in range(14):
        a = i * 2 * math.pi / 14
        s.prop("tree_lollipop", (math.cos(a) * 42, math.sin(a) * 42, 0), a, 1.2)


def road_end(s):  # Veilton: end of the road, a wagon and a sign post
    s.box((0, 0, 0.8), (4.2, 2.2, 0.4), "wood", 0.9)
    s.box((0, 0, 1.2), (4, 2, 1.6), "canvas", 0.9)
    for x in (-1.4, 1.4):
        for y in (-1.2, 1.2):
            s.cyl((x, y, 0.1), 0.8, 0.25, "wood", 0.7, 8, col=False)
    s.box((8, -4, 0), (0.25, 0.25, 3), "wood", 0.9)
    s.box((8, -4, 2.3), (1.8, 0.2, 0.6), "wood", 1.0, col=False)
    s.prop("fence", (-10, 6, 0))
    s.prop("rock", (12, 6, 0), 0.4)


def holy_site(s):  # generic holy site starter: ring of pillars around an altar on steps
    s.dais((0, 0, 0), 14, 14, 0.5)
    s.dais((0, 0, 0.5), 10, 10, 0.5, k=0.9)
    s.box((0, 0, 1.0), (3, 1.5, 1.2), "stone", 1.0)
    for i in range(8):
        a = i * math.pi / 4
        s.box((math.cos(a) * 12, math.sin(a) * 12, 0), (1.6, 1.6, 8 if i % 3 else 5.5), "stone", 0.9, a)
    s.prop("ruin_wall", (0, 24, 0), 0.0)


def graveyard(s):  # generic graveyard starter: fenced plot, rows of markers, gate
    for x in range(-3, 4):
        s.prop("fence", (x * 3.0, -14, 0))
        s.prop("fence", (x * 3.0, 14, 0))
    for y in range(-4, 5):
        s.prop("fence", (-10.5, y * 3.0, 0), math.pi / 2)
        s.prop("fence", (10.5, y * 3.0, 0), math.pi / 2)
    s.box((-4, -14, 0), (1.2, 1.2, 4), "stone", 0.8)
    s.box((4, -14, 0), (1.2, 1.2, 4), "stone", 0.8)
    for r in range(3):
        for c in range(5):
            s.prop("grave_marker", (-7 + c * 3.5, -5 + r * 5, 0), 0.0, 1.0)
    s.prop("tree_lollipop", (8, 10, 0), 0.3, 0.9)


def template(s):
    s.box((0, 0, 0), (6, 6, 0.3), "stone", 0.8)  # nothing but a pad: duplicate this file for a new kind


KINDS = dict(castle=castle, fort=fort, walled_town_round=walled_town_round, walled_town_square=walled_town_square,
             hamlet=hamlet, farm=farm, ford=ford, gate_ruin=gate_ruin, harbour=harbour, river_tower=river_tower,
             volcano=volcano, forest_clearing=forest_clearing, great_tree=great_tree, road_end=road_end,
             holy_site=holy_site, graveyard=graveyard, template=template)
