"""Sketch-derived layout data for the world blockout. PLACEHOLDER: read off Austin's sketch by eye; names are the
spellings as read (ticket #606, unconfirmed). Coordinates are SKETCH PIXELS (the 2000x1500 display of the photo);
P() maps them to world metres: 1 unit = 1 m, +X east, +Y north, centre of the map at the origin."""
import numpy as np

# PLACEHOLDER: world size is not decided (ticket #603, scale test). Change here and re-run build_landscape.py,
# or just scale the world_root empty in the .blend.
WORLD_W = 2000.0   # metres east-west
WORLD_H = 1500.0   # metres north-south
SK = dict(x0=128.0, x1=1990.0, y0=50.0, y1=1450.0)   # the drawn frame in sketch pixels


def P(x, y):
    return ((x - SK["x0"]) / (SK["x1"] - SK["x0"]) * WORLD_W - WORLD_W / 2,
            WORLD_H / 2 - (y - SK["y0"]) / (SK["y1"] - SK["y0"]) * WORLD_H)


def PL(pts):
    return np.array([P(x, y) for x, y in pts], float)


# name: (sketch xy, kind, flatten radius m, blend m, min distance from a river m (pushes it off the bank), coastal)
POIS = {
    "avequalla":       ((540, 168), "castle",             42, 40, 55, False),
    "nofishun":        ((1480, 175), "fort",              32, 30, 0, False),
    "northwood":       ((1000, 400), "forest_clearing",    0, 0, 70, False),
    "old_gate":        ((1140, 345), "gate_ruin",         28, 25, 40, False),
    "teshfield":       ((772, 538), "hamlet",             40, 30, 70, False),
    "veilton":         ((205, 645), "road_end",           25, 25, 0, False),
    "valley_cross":    ((545, 632), "walled_town_round",  50, 40, 0, False),
    "hopes_gates":     ((1120, 703), "walled_town_square", 60, 40, 80, False),
    "alebend":         ((1075, 857), "farm",              45, 35, 0, False),
    "entwar":          ((1430, 800), "river_tower",       30, 30, 60, True),
    "elder_woods":     ((1470, 1030), "great_tree",        0, 0, 0, False),
    "lastford":        ((1120, 1160), "ford",             20, 25, 0, False),
    "hells_mouth":     ((320, 1160), "volcano",            0, 0, 0, False),
    "unnamed_harbour": ((1860, 1095), "harbour",          35, 35, 0, True),
}

# rivers: name -> dict(pts, w (water width m), depth m below the surrounding ground, join (river it ends in))
RIVERS = {
    "river_main": dict(pts=[(530, 330), (560, 380), (640, 450), (700, 510), (750, 555), (820, 600), (900, 625),
                            (1000, 668), (1100, 715), (1200, 750), (1300, 780), (1380, 795), (1470, 822)], w=22, depth=2.8),
    "river_lake_out": dict(pts=[(585, 215), (582, 300), (560, 380)], w=14, depth=2.4, join="river_main"),
    "river_nw": dict(pts=[(320, 55), (400, 85), (470, 120), (505, 150), (548, 178)], w=12, depth=2.4, join="lake_avequalla"),
    "river_northwood": dict(pts=[(1100, 350), (1090, 400), (1050, 450), (1078, 505), (1052, 590), (1075, 650),
                                 (1100, 715)], w=16, depth=2.6, join="river_main"),
    "stream_nw1": dict(pts=[(990, 250), (1000, 290), (1060, 330), (1100, 350)], w=9, depth=2.0, join="river_northwood"),
    "stream_nw2": dict(pts=[(920, 262), (960, 300), (1030, 330), (1100, 350)], w=9, depth=2.0, join="river_northwood"),
    "stream_ne": dict(pts=[(1285, 195), (1200, 235), (1140, 290), (1100, 350)], w=10, depth=2.0, join="river_northwood"),
    "stream_east": dict(pts=[(1480, 325), (1390, 350), (1300, 342), (1200, 340), (1112, 388)], w=10, depth=2.0, join="river_northwood"),
    "river_south": dict(pts=[(350, 1020), (450, 1030), (560, 1040), (630, 1062), (700, 1090), (800, 1105),
                             (880, 1140), (905, 1168), (960, 1178), (1050, 1160), (1118, 1166), (1190, 1195),
                             (1250, 1240), (1330, 1268), (1450, 1270), (1600, 1268), (1750, 1255), (1830, 1200),
                             (1895, 1135), (1930, 1105)], w=20, depth=2.8),
    "river_south_b": dict(pts=[(710, 1240), (800, 1262), (850, 1285), (950, 1255), (1050, 1205), (1118, 1168)],
                          w=14, depth=2.4, join="river_south"),
}
# lakes: fixed water level, wide and flat
LAKES = {
    "lake_avequalla": dict(pts=[(600, 172), (650, 138), (705, 150), (760, 128), (795, 120)], w=48),
}

ROADS = {
    "road_veilton": [(215, 650), (350, 665), (450, 655), (520, 650)],
    "road_vc_teshfield": [(572, 624), (640, 592), (700, 570), (745, 552)],
    "road_avequalla": [(582, 226), (606, 300), (645, 390), (692, 470), (738, 540)],
    "road_tesh_hopes": [(785, 578), (900, 648), (1010, 702), (1090, 722)],
    "road_vc_alebend": [(560, 665), (600, 730), (700, 790), (850, 832), (960, 850), (1040, 860)],
    "road_hopes_alebend": [(1112, 735), (1100, 790), (1062, 845)],
    "road_south": [(1062, 875), (1075, 980), (1090, 1080), (1115, 1160), (1160, 1280), (1190, 1450)],
    "road_alebend_loop": [(1075, 880), (1130, 897), (1300, 882), (1420, 852), (1432, 822)],
    "road_coast": [(1130, 1162), (1200, 1182), (1235, 1245), (1305, 1292), (1450, 1296), (1650, 1290),
                   (1800, 1243), (1880, 1165), (1892, 1112)],
}

SEA = [(1757, -40), (1745, 150), (1742, 300), (1715, 420), (1752, 520), (1700, 625), (1600, 715), (1500, 780),
       (1452, 812), (1500, 845), (1600, 868), (1730, 885), (1850, 878), (1930, 905), (1975, 960), (1968, 1030),
       (1940, 1090), (1928, 1150), (1962, 1250), (2100, 1300), (2100, -40)]

# mountain regions: (polygon, max peak height m)  PLACEHOLDER heights
MOUNTAINS = [
    ([(730, 70), (1760, 40), (1760, 200), (1500, 300), (1250, 240), (1000, 232), (880, 250), (790, 205), (730, 150)], 135),
    ([(130, 180), (480, 170), (520, 330), (400, 390), (130, 335)], 95),
    ([(640, 260), (880, 240), (900, 320), (760, 350), (725, 520), (640, 485), (565, 370)], 100),
    ([(1490, 270), (1745, 220), (1738, 420), (1640, 560), (1420, 545), (1335, 425), (1305, 360)], 110),
]

FORESTS = {
    "northwood": dict(poly=[(850, 330), (900, 260), (1010, 245), (1250, 205), (1450, 205), (1545, 225), (1520, 265),
                            (1430, 330), (1250, 390), (1130, 445), (1070, 480), (1040, 520), (950, 535), (880, 500),
                            (835, 420)], tree="tree_cone", spacing=28),
    "elder_woods": dict(poly=[(1240, 1000), (1300, 940), (1480, 915), (1700, 920), (1780, 945), (1800, 1010),
                              (1770, 1100), (1700, 1180), (1600, 1230), (1450, 1250), (1320, 1250), (1250, 1200),
                              (1225, 1100)], tree="tree_lollipop", spacing=30),
    "alebend_strip": dict(poly=[(1150, 760), (1250, 782), (1350, 812), (1410, 828), (1370, 836), (1250, 824),
                                (1160, 792)], tree="tree_lollipop", spacing=22),
    "lastford_grove": dict(poly=[(990, 1090), (1040, 1065), (1085, 1090), (1075, 1135), (1020, 1140)],
                           tree="tree_lollipop", spacing=18),
}
# ground tints: ash around Hell's Mouth, farm fields (centre x, y, radius x, radius y in sketch pixels)
ASH = (360, 1215, 330, 240)
FIELDS = [(590, 585, 120, 55), (610, 740, 150, 70), (790, 700, 120, 60), (1130, 600, 110, 90), (1260, 700, 130, 60),
          (470, 770, 70, 50)]
