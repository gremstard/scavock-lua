#!/usr/bin/env python3
"""Generate placeholder 16x16 textures for the Scavock Luanti game.

Pure stdlib (zlib/struct) PNG writer - no PIL dependency.
Deterministic: same output every run (seeded RNG per texture name).
"""
import os, struct, zlib, random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 16

def write_png(path, pixels):
    """pixels: list of SIZE rows, each a list of SIZE (r,g,b,a) tuples."""
    raw = b""
    for row in pixels:
        raw += b"\x00" + b"".join(struct.pack("4B", *px) for px in row)
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)

def blank(color=(0, 0, 0, 0)):
    return [[color for _ in range(SIZE)] for _ in range(SIZE)]

def clamp(v):
    return max(0, min(255, int(v)))

def noise_fill(base, var, rng, alpha=255):
    px = blank()
    for y in range(SIZE):
        for x in range(SIZE):
            d = rng.randint(-var, var)
            px[y][x] = (clamp(base[0] + d), clamp(base[1] + d), clamp(base[2] + d), alpha)
    return px

def speckle(px, color, count, rng, size=1):
    for _ in range(count):
        x, y = rng.randint(0, SIZE - size), rng.randint(0, SIZE - size)
        for dy in range(size):
            for dx in range(size):
                px[y + dy][x + dx] = (*color, 255)
    return px

def vlines(px, color, every, rng, jitter=6):
    for x in range(0, SIZE, every):
        for y in range(SIZE):
            c = [clamp(v + rng.randint(-jitter, jitter)) for v in color]
            px[y][x] = (c[0], c[1], c[2], 255)
    return px

def border(px, color):
    for i in range(SIZE):
        px[0][i] = (*color, 255); px[SIZE-1][i] = (*color, 255)
        px[i][0] = (*color, 255); px[i][SIZE-1] = (*color, 255)
    return px

def diag_handle(px, color=(110, 78, 44)):
    # bottom-left to upper-right stick, 2px thick
    for i in range(2, 13):
        x, y = i, SIZE - 1 - i
        for (dx, dy) in ((0, 0), (1, 0), (0, 1)):
            if 0 <= x+dx < SIZE and 0 <= y+dy < SIZE:
                px[y+dy][x+dx] = (*color, 255)
    return px

def blob(px, cx, cy, r, color):
    for y in range(SIZE):
        for x in range(SIZE):
            if (x-cx)**2 + (y-cy)**2 <= r*r:
                px[y][x] = (*color, 255)
    return px

MATERIALS = {  # tier ladder colors (tools/weapons/ingots)
    "scrap":    (138, 127, 106),
    "iron":     (198, 198, 200),
    "steel":    (127, 143, 166),
    "titanium": (170, 186, 205),
    "graphene": (45, 45, 50),
}

OUT = {}  # relpath -> builder fn

def tex(mod, name):
    def deco(fn):
        OUT[f"mods/{mod}/textures/{name}.png"] = fn
        return fn
    return deco

def R(name):
    return random.Random(name)

# ---------- core nodes ----------
def add(mod, name, fn):
    OUT[f"mods/{mod}/textures/{name}.png"] = fn

add("scavock_core", "scavock_stone",  lambda: noise_fill((120, 120, 122), 10, R("stone")))
add("scavock_core", "scavock_dirt",   lambda: noise_fill((110, 80, 52), 12, R("dirt")))
add("scavock_core", "scavock_grass_top", lambda: noise_fill((70, 128, 58), 14, R("grass")))
def grass_side():
    px = noise_fill((110, 80, 52), 12, R("gside"))
    for y in range(0, 4):
        for x in range(SIZE):
            g = R(f"gs{x}{y}").randint(-14, 14)
            px[y][x] = (clamp(70+g), clamp(128+g), clamp(58+g), 255)
    return px
add("scavock_core", "scavock_grass_side", grass_side)
add("scavock_core", "scavock_dry_grass_top", lambda: noise_fill((160, 140, 70), 14, R("drygrass")))
def dry_grass_side():
    px = noise_fill((110, 80, 52), 12, R("dgside"))
    for y in range(0, 4):
        for x in range(SIZE):
            g = R(f"dgs{x}{y}").randint(-14, 14)
            px[y][x] = (clamp(160+g), clamp(140+g), clamp(70+g), 255)
    return px
add("scavock_core", "scavock_dry_grass_side", dry_grass_side)
add("scavock_core", "scavock_sand",   lambda: noise_fill((214, 198, 148), 10, R("sand")))
add("scavock_core", "scavock_snow",   lambda: noise_fill((236, 240, 246), 6, R("snow")))
add("scavock_core", "scavock_ice",    lambda: noise_fill((160, 200, 235), 8, R("ice"), alpha=230))
add("scavock_core", "scavock_water",  lambda: noise_fill((30, 80, 170), 10, R("water"), alpha=160))
add("scavock_core", "scavock_gravel", lambda: speckle(noise_fill((105, 100, 96), 14, R("gravel")), (70, 66, 62), 14, R("gravsp"), 2))

def trunk(base, ring):
    def fn():
        return vlines(noise_fill(base, 8, R(str(base))), ring, 3, R(str(ring)))
    return fn
add("scavock_core", "scavock_tree",        trunk((100, 72, 40), (78, 54, 28)))
add("scavock_core", "scavock_tree_top",    lambda: blob(noise_fill((100, 72, 40), 8, R("tt")), 8, 8, 5, (145, 110, 66)))
add("scavock_core", "scavock_pine_tree",   trunk((84, 58, 34), (60, 40, 22)))
add("scavock_core", "scavock_pine_top",    lambda: blob(noise_fill((84, 58, 34), 8, R("pt")), 8, 8, 5, (120, 88, 52)))
def birch_side():
    px = noise_fill((225, 222, 210), 6, R("birch"))
    return speckle(px, (40, 40, 40), 7, R("bsp"), 2)
add("scavock_core", "scavock_birch_tree",  birch_side)
add("scavock_core", "scavock_birch_top",   lambda: blob(noise_fill((225, 222, 210), 6, R("bt")), 8, 8, 5, (200, 190, 160)))
def leaves(base, name):
    def fn():
        px = noise_fill(base, 18, R(name))
        rng = R(name + "holes")
        for _ in range(30):
            px[rng.randint(0, 15)][rng.randint(0, 15)] = (0, 0, 0, 0)
        return px
    return fn
add("scavock_core", "scavock_leaves",       leaves((52, 110, 44), "lv"))
add("scavock_core", "scavock_pine_needles", leaves((36, 84, 48), "pn"))
add("scavock_core", "scavock_birch_leaves", leaves((88, 140, 60), "bl"))
add("scavock_core", "scavock_planks", lambda: vlines(noise_fill((150, 112, 66), 8, R("planks")), (118, 86, 48), 4, R("plv")))

def concrete():
    px = noise_fill((150, 148, 144), 8, R("conc"))
    return speckle(px, (120, 118, 114), 10, R("concsp"), 2)
add("scavock_core", "scavock_concrete", concrete)
def concrete_cracked():
    px = concrete()
    rng = R("crack")
    x = rng.randint(3, 12)
    for y in range(SIZE):
        px[y][clamp(x)] = (90, 88, 84, 255)
        x += rng.randint(-1, 1); x = max(1, min(14, x))
    return px
add("scavock_core", "scavock_concrete_cracked", concrete_cracked)
def debris():
    px = noise_fill((100, 95, 88), 16, R("debris"))
    speckle(px, (150, 110, 60), 8, R("rust"), 2)
    return speckle(px, (170, 170, 175), 6, R("metal"), 2)
add("scavock_core", "scavock_debris", debris)

def ore(spot, name, count=9):
    def fn():
        return speckle(noise_fill((120, 120, 122), 10, R("stone")), spot, count, R(name), 2)
    return fn
add("scavock_core", "scavock_coal_ore",     ore((30, 30, 32), "coalore"))
add("scavock_core", "scavock_iron_ore",     ore((190, 150, 120), "ironore"))
add("scavock_core", "scavock_titanium_ore", ore((190, 205, 225), "titore", 6))
add("scavock_core", "scavock_coal_block",   lambda: border(noise_fill((36, 36, 38), 8, R("coalb")), (20, 20, 22)))

def item_lump(color, name):
    def fn():
        px = blank()
        return blob(px, 8, 9, 5, color)
    return fn
add("scavock_core", "scavock_coal_lump",     item_lump((40, 40, 44), "coallump"))
add("scavock_core", "scavock_iron_lump",     item_lump((165, 130, 105), "ironlump"))
add("scavock_core", "scavock_titanium_lump", item_lump((175, 190, 210), "titlump"))
def ingot(color):
    def fn():
        px = blank()
        for y in range(6, 11):
            for x in range(3, 13):
                px[y][x] = (*color, 255)
        for x in range(3, 13):
            px[6][x] = tuple(clamp(c + 30) for c in color) + (255,)
        return px
    return fn
for mat, col in MATERIALS.items():
    add("scavock_core", f"scavock_{mat}_ingot", ingot(col))
def stick():
    px = blank()
    return diag_handle(px)
add("scavock_core", "scavock_stick", stick)

def workbench_top():
    px = vlines(noise_fill((150, 112, 66), 8, R("wbt")), (118, 86, 48), 4, R("wbtv"))
    return border(px, (90, 64, 36))
add("scavock_core", "scavock_workbench_top", workbench_top)
add("scavock_core", "scavock_workbench_side", lambda: border(vlines(noise_fill((130, 96, 56), 8, R("wbs")), (100, 72, 40), 5, R("wbsv")), (90, 64, 36)))
def furnace_front():
    px = noise_fill((120, 120, 122), 10, R("stone"))
    for y in range(8, 13):
        for x in range(5, 11):
            px[y][x] = (30, 30, 30, 255)
    return px
add("scavock_core", "scavock_furnace_front", furnace_front)
def furnace_front_active():
    px = furnace_front()
    for y in range(9, 12):
        for x in range(6, 10):
            px[y][x] = (240, 140, 30, 255)
    return px
add("scavock_core", "scavock_furnace_front_active", furnace_front_active)
add("scavock_core", "scavock_furnace_side", lambda: noise_fill((110, 110, 112), 10, R("fside")))

# ---------- tools / weapons ----------
def tool_pick(color):
    def fn():
        px = blank(); diag_handle(px)
        for i, w in ((2, 9), (3, 7), (4, 3)):
            for x in range(8 - w // 2, 8 + w // 2 + 1):
                px[i][x] = (*color, 255)
        return px
    return fn
def tool_axe(color):
    def fn():
        px = blank(); diag_handle(px)
        for y in range(2, 8):
            for x in range(4, 10):
                if x + y < 14:
                    px[y][x] = (*color, 255)
        return px
    return fn
def tool_doubleaxe(color):
    def fn():
        px = blank(); diag_handle(px)
        for y in range(2, 8):
            for x in range(2, 14):
                if abs(x - 8) > 1:
                    px[y][x] = (*color, 255)
        return px
    return fn
def tool_sword(color):
    def fn():
        px = blank()
        for i in range(3, 14):
            px[SIZE - 1 - i][i] = (*color, 255)
            if i < 13:
                px[SIZE - 2 - i][i] = (*color, 255)
        px[12][4] = (90, 60, 30, 255); px[11][3] = (90, 60, 30, 255)
        px[13][2] = (110, 78, 44, 255); px[14][1] = (110, 78, 44, 255)
        return px
    return fn
def tool_dagger(color):
    def fn():
        px = blank()
        for i in range(6, 12):
            px[SIZE - 1 - i][i] = (*color, 255)
        px[10][4] = (110, 78, 44, 255); px[11][3] = (110, 78, 44, 255)
        return px
    return fn
def tool_spear(color):
    def fn():
        px = blank()
        for i in range(1, 14):
            px[SIZE - 1 - i][i] = (110, 78, 44, 255)
        px[1][14] = (*color, 255); px[2][13] = (*color, 255)
        px[1][13] = (*color, 255); px[2][14] = (*color, 255)
        return px
    return fn

for mat, col in MATERIALS.items():
    add("scavock_tools", f"scavock_pick_{mat}", tool_pick(col))
    add("scavock_tools", f"scavock_axe_{mat}", tool_axe(col))
    for form, fn in (("dagger", tool_dagger), ("sword", tool_sword),
                     ("waraxe", tool_axe), ("doubleaxe", tool_doubleaxe),
                     ("spear", tool_spear)):
        add("scavock_weapons", f"scavock_{form}_{mat}", fn(col))

def bow():
    px = blank()
    for i in range(2, 14):
        px[SIZE - 1 - i][i] = (110, 78, 44, 255)
    for i in range(3, 13):
        px[SIZE - 1 - i][SIZE - 1 - (SIZE - 1 - i) if False else 3] = px[SIZE - 1 - i][3]
    # string: vertical-ish line from (13,2) to (2,13)
    for i in range(2, 14):
        px[SIZE - 1 - i][2 if i < 8 else 13] = px[SIZE - 1 - i][2 if i < 8 else 13]
    for y in range(2, 14):
        px[y][13 - (y - 2)] = px[y][13 - (y - 2)]
    # simpler: draw string as straight line between tips
    for t in range(12):
        x = 2 + t; y = 2 + t
        px[y][x] = px[y][x]
    for t in range(12):
        px[13 - t][13] = (200, 200, 190, 255) if t < 0 else px[13 - t][13]
    # fallback visible string
    for y in range(2, 14):
        px[y][12] = (210, 210, 200, 255)
    return px
add("scavock_weapons", "scavock_bow", bow)
def arrow_item():
    px = blank()
    for i in range(2, 13):
        px[SIZE - 1 - i][i] = (150, 112, 66, 255)
    px[2][13] = (170, 170, 175, 255); px[3][12] = (170, 170, 175, 255)
    px[12][3] = (220, 220, 220, 255); px[13][2] = (220, 220, 220, 255)
    return px
add("scavock_weapons", "scavock_arrow", arrow_item)
add("scavock_weapons", "scavock_arrow_tex", lambda: noise_fill((150, 112, 66), 8, R("arrowtex")))

# ---------- loot / evac ----------
def crate_side():
    px = vlines(noise_fill((140, 104, 60), 8, R("crate")), (110, 80, 44), 5, R("cratev"))
    border(px, (90, 64, 36))
    for i in range(SIZE):
        px[i][i] = (100, 72, 40, 255)
    return px
add("scavock_loot", "scavock_crate", crate_side)
def beacon_side():
    px = noise_fill((60, 64, 70), 8, R("beacon"))
    for y in range(3, 13):
        for x in range(6, 10):
            px[y][x] = (80, 220, 120, 255)
    return border(px, (40, 42, 46))
add("scavock_evac", "scavock_beacon_side", beacon_side)
def beacon_top():
    px = noise_fill((60, 64, 70), 8, R("beacontop"))
    return blob(px, 8, 8, 4, (120, 240, 150))
add("scavock_evac", "scavock_beacon_top", beacon_top)
def vault_icon():
    px = noise_fill((70, 74, 82), 8, R("vault"))
    border(px, (40, 42, 46))
    return blob(px, 8, 8, 3, (180, 185, 195))
add("scavock_evac", "scavock_vault", vault_icon)

# ---------- identity palette (SCAVOCK_Visual_Identity.md §3) ----------
VOID = (16, 17, 20)
CHARCOAL = (28, 30, 35)
SLATE = (42, 45, 52)
CHARTREUSE = (182, 214, 46)
BONE = (228, 224, 212)

# ---------- grid inventory (flat fills, subtle borders — §7 Inventory) ----------
def grid_cell():
    px = blank((*CHARCOAL, 240))
    return border(px, SLATE)
add("scavock_grid", "scavock_cell", grid_cell)
def grid_cell_occupied():
    px = blank((*SLATE, 240))
    return border(px, (58, 62, 70))
add("scavock_grid", "scavock_cell_occupied", grid_cell_occupied)
def grid_cell_held():
    px = blank((*SLATE, 240))
    return border(px, CHARTREUSE)
add("scavock_grid", "scavock_cell_held", grid_cell_held)

# ---------- HUD (§7: crosshair is a small dot, not a reticle) ----------
def crosshair():
    px = blank()
    for y in range(7, 9):
        for x in range(7, 9):
            px[y][x] = (*BONE, 230)
    px[6][7] = (*VOID, 120); px[6][8] = (*VOID, 120)
    px[9][7] = (*VOID, 120); px[9][8] = (*VOID, 120)
    px[7][6] = (*VOID, 120); px[8][6] = (*VOID, 120)
    px[7][9] = (*VOID, 120); px[8][9] = (*VOID, 120)
    return px
add("scavock_player", "crosshair", crosshair)
add("scavock_player", "object_crosshair", crosshair)
def hotbar_slot():
    px = blank((*CHARCOAL, 190))
    return border(px, (*SLATE, 255)[:3])
add("scavock_player", "scavock_hotbar_slot", hotbar_slot)
def hotbar_selected():
    px = blank((0, 0, 0, 0))
    for i in range(SIZE):
        for t in range(2):
            px[t][i] = (*CHARTREUSE, 255); px[SIZE-1-t][i] = (*CHARTREUSE, 255)
            px[i][t] = (*CHARTREUSE, 255); px[i][SIZE-1-t] = (*CHARTREUSE, 255)
    return px
add("scavock_player", "scavock_hotbar_selected", hotbar_selected)

# ---------- medical (§12 revives) ----------
def medkit():
    px = blank()
    for y in range(4, 12):
        for x in range(2, 14):
            px[y][x] = (*BONE, 255)
    for y in range(6, 10):
        for x in range(7, 9):
            px[y][x] = (179, 58, 36, 255)
    for x in range(6, 10):
        for y in range(7, 9):
            px[y][x] = (179, 58, 36, 255)
    return px
add("scavock_death", "scavock_medkit", medkit)
def stabiliser():
    px = blank()
    for i in range(3, 12):
        px[SIZE - 1 - i][i] = (*BONE, 255)
        px[SIZE - 2 - i][i] = (*BONE, 255)
    px[3][12] = (170, 170, 175, 255); px[2][13] = (170, 170, 175, 255)
    px[12][2] = (179, 58, 36, 255); px[11][3] = (179, 58, 36, 255)
    return px
add("scavock_death", "scavock_stabiliser", stabiliser)

# ---------- creatures (§24: ordinary animals, box visuals) ----------
def fur(base, name, streak):
    def fn():
        px = noise_fill(base, 10, R(name))
        return speckle(px, streak, 10, R(name + "s"), 1)
    return fn
def face(base, name, eye=(20, 20, 22)):
    def fn():
        px = noise_fill(base, 10, R(name))
        px[6][4] = (*eye, 255); px[6][5] = (*eye, 255)
        px[6][10] = (*eye, 255); px[6][11] = (*eye, 255)
        for y in range(11, 14):
            for x in range(6, 10):
                px[y][x] = tuple(clamp(c - 30) for c in base) + (255,)
        return px
    return fn
add("scavock_creatures", "scavock_wolf", fur((120, 118, 115), "wolf", (90, 88, 86)))
add("scavock_creatures", "scavock_wolf_face", face((120, 118, 115), "wolfface"))
add("scavock_creatures", "scavock_boar", fur((104, 76, 52), "boar", (80, 56, 38)))
def boar_face():
    px = face((104, 76, 52), "boarface")()
    px[12][5] = (228, 224, 212, 255); px[11][5] = (228, 224, 212, 255)
    px[12][10] = (228, 224, 212, 255); px[11][10] = (228, 224, 212, 255)
    return px
add("scavock_creatures", "scavock_boar_face", boar_face)
add("scavock_creatures", "scavock_rat", fur((70, 68, 66), "rat", (52, 50, 48)))
add("scavock_creatures", "scavock_rat_face", face((70, 68, 66), "ratface", eye=(180, 60, 40)))
def leather():
    px = blank()
    for y in range(4, 12):
        for x in range(3, 13):
            if (x + y) % 9 != 0:
                px[y][x] = (139, 98, 62, 255)
    return px
add("scavock_core", "scavock_leather", leather)

# ---------- survival (§13) ----------
def item_dot(color, name, r=4):
    def fn():
        return blob(blank(), 8, 8, r, color)
    return fn
add("scavock_survival", "scavock_meat_raw", item_dot((178, 74, 66), "meatraw", 5))
add("scavock_survival", "scavock_meat_cooked", item_dot((136, 90, 52), "meatcooked", 5))
def berry(color, name):
    def fn():
        px = blank()
        blob(px, 5, 9, 2, color); blob(px, 10, 7, 2, color); blob(px, 8, 11, 2, color)
        px[4][8] = (60, 100, 45, 255); px[3][8] = (60, 100, 45, 255)
        return px
    return fn
add("scavock_survival", "scavock_berry_surface", berry((150, 40, 60), "b1"))
add("scavock_survival", "scavock_berry_cave", berry((90, 110, 180), "b2"))
add("scavock_survival", "scavock_berry_mut", berry((182, 214, 46), "b3"))
def bush(berrycol, name):
    def fn():
        px = noise_fill((52, 110, 44), 18, R(name))
        rng = R(name + "b")
        for _ in range(6):
            x, y = rng.randint(2, 13), rng.randint(2, 13)
            px[y][x] = (*berrycol, 255); px[y][x+1] = (*berrycol, 255)
        return px
    return fn
add("scavock_survival", "scavock_bush_surface", bush((150, 40, 60), "bushs"))
add("scavock_survival", "scavock_bush_cave", bush((90, 110, 180), "bushc"))
add("scavock_survival", "scavock_bush_mut", bush((182, 214, 46), "bushm"))
def mushroom(cap, name):
    def fn():
        px = blank()
        for y in range(4, 8):
            for x in range(4, 12):
                px[y][x] = (*cap, 255)
        for y in range(8, 13):
            for x in range(7, 9):
                px[y][x] = (210, 200, 180, 255)
        return px
    return fn
add("scavock_survival", "scavock_mushroom_cave", mushroom((150, 110, 80), "mc"))
add("scavock_survival", "scavock_mushroom_mut", mushroom((182, 214, 46), "mm"))
def canteen(fillcol):
    def fn():
        px = blank()
        for y in range(4, 13):
            for x in range(4, 12):
                px[y][x] = (86, 90, 98, 255)
        for y in range(2, 4):
            for x in range(6, 10):
                px[y][x] = (60, 63, 70, 255)
        if fillcol:
            for y in range(9, 12):
                for x in range(5, 11):
                    px[y][x] = (*fillcol, 255)
        return px
    return fn
add("scavock_survival", "scavock_canteen_empty", canteen(None))
add("scavock_survival", "scavock_canteen_full", canteen((60, 120, 200)))
def bandage():
    px = blank()
    for y in range(6, 10):
        for x in range(2, 14):
            px[y][x] = (*BONE, 255)
    for x in range(2, 14, 3):
        px[7][x] = (200, 196, 184, 255)
    return px
add("scavock_survival", "scavock_bandage", bandage)
def splint():
    px = blank()
    diag_handle(px, (150, 112, 66))
    for i in range(4, 11, 3):
        px[SIZE - 1 - i][i - 1] = (*BONE, 255)
        px[SIZE - 2 - i][i + 1] = (*BONE, 255)
    return px
add("scavock_survival", "scavock_splint", splint)
def river_water():
    return noise_fill((40, 110, 190), 10, R("rwater"), alpha=160)
add("scavock_core", "scavock_river_water", river_water)

# ---------- gear (§10 clothing, §11 reinforcement) ----------
LEATHER_C = (139, 98, 62)
CLOTH_C = (96, 104, 92)
def garment(color, name, shape):
    def fn():
        px = blank()
        for (y0, y1, x0, x1) in shape:
            for y in range(y0, y1):
                for x in range(x0, x1):
                    d = R(name + str(x * 16 + y)).randint(-8, 8)
                    px[y][x] = (clamp(color[0]+d), clamp(color[1]+d), clamp(color[2]+d), 255)
        return px
    return fn
add("scavock_gear", "scavock_cap", garment(LEATHER_C, "cap", [(3, 7, 3, 13), (7, 9, 2, 14)]))
def glasses():
    px = blank()
    for x in range(2, 14):
        px[7][x] = (40, 42, 46, 255)
    for cx in (4, 11):
        for y in range(6, 10):
            for x in range(cx - 1, cx + 2):
                px[y][x] = (60, 63, 70, 255)
    return px
add("scavock_gear", "scavock_glasses", glasses)
add("scavock_gear", "scavock_scarf", garment((122, 60, 48), "scarf", [(6, 9, 2, 14), (9, 14, 6, 9)]))
add("scavock_gear", "scavock_shirt", garment(CLOTH_C, "shirt", [(3, 12, 4, 12), (4, 8, 1, 4), (4, 8, 12, 15)]))
add("scavock_gear", "scavock_vest", garment((70, 76, 68), "vest", [(3, 13, 4, 12)]))
add("scavock_gear", "scavock_shorts", garment((80, 88, 100), "shorts", [(4, 8, 3, 13), (8, 13, 3, 7), (8, 13, 9, 13)]))
add("scavock_gear", "scavock_pants", garment((66, 72, 82), "pants", [(3, 6, 3, 13), (6, 14, 3, 7), (6, 14, 9, 13)]))
add("scavock_gear", "scavock_backpack_s", garment(LEATHER_C, "bps", [(4, 12, 4, 12)]))
add("scavock_gear", "scavock_backpack_l", garment((110, 76, 46), "bpl", [(2, 14, 3, 13)]))
add("scavock_gear", "scavock_shoes", garment((60, 46, 32), "shoes", [(8, 12, 2, 8), (8, 12, 9, 15)]))
def reinforcement(color):
    def fn():
        px = blank()
        for y in range(3, 13):
            for x in range(3, 13):
                if abs(x - 8) + abs(y - 8) <= 6:
                    px[y][x] = (*color, 255)
        for y in range(6, 10):
            for x in range(6, 10):
                px[y][x] = tuple(clamp(c - 40) for c in color) + (255,)
        return px
    return fn
REINF_COLORS = {
    "leather": LEATHER_C, "chain": (150, 152, 158), "scrap": (138, 127, 106),
    "iron": (198, 198, 200), "steel": (127, 143, 166),
    "titanium": (170, 186, 205), "graphene": (45, 45, 50),
}
for tier, col in REINF_COLORS.items():
    add("scavock_gear", f"scavock_reinf_{tier}", reinforcement(col))
def chain_link():
    px = blank()
    for a in range(0, 360, 12):
        import math as _m
        x = int(8 + 4 * _m.cos(_m.radians(a))); y = int(8 + 4 * _m.sin(_m.radians(a)))
        px[y][x] = (150, 152, 158, 255)
    return px
add("scavock_core", "scavock_chain_link", chain_link)
def feather():
    px = blank()
    for i in range(3, 13):
        px[SIZE - 1 - i][i] = (*BONE, 255)
        if i % 2 == 0 and i < 12:
            px[SIZE - 2 - i][i] = (200, 196, 184, 255)
            px[SIZE - i][i] = (200, 196, 184, 255)
    return px
add("scavock_gear", "scavock_feather", feather)
def spring():
    px = blank()
    for y in range(3, 13):
        x = 6 + (y % 3)
        px[y][x] = (170, 170, 175, 255); px[y][x + 1] = (170, 170, 175, 255)
    return px
add("scavock_gear", "scavock_spring", spring)
def strap():
    px = blank()
    for y in range(2, 14):
        for x in range(6, 10):
            px[y][x] = (*LEATHER_C, 255)
    px[7][7] = (90, 60, 36, 255); px[7][8] = (90, 60, 36, 255)
    return px
add("scavock_gear", "scavock_strap", strap)
def lockplate():
    px = blank()
    for y in range(4, 12):
        for x in range(4, 12):
            px[y][x] = (198, 198, 200, 255)
    px[8][7] = (40, 42, 46, 255); px[8][8] = (40, 42, 46, 255); px[9][8] = (40, 42, 46, 255)
    return px
add("scavock_gear", "scavock_lockplate", lockplate)

# ---------- world (§12 beds, corpses, safe zones) ----------
def bed_top():
    px = noise_fill((122, 60, 48), 8, R("bed"))
    for y in range(0, 5):
        for x in range(SIZE):
            px[y][x] = (228, 224, 212, 255)
    return px
add("scavock_world", "scavock_bed_top", bed_top)
add("scavock_world", "scavock_bed_side", lambda: noise_fill((100, 72, 40), 8, R("bedside")))
def corpse_tex():
    px = noise_fill((70, 74, 82), 8, R("corpse"))
    return speckle(px, (110, 100, 90), 8, R("corpsesp"), 2)
add("scavock_world", "scavock_corpse", corpse_tex)
def safezone_core():
    px = noise_fill((60, 64, 70), 6, R("sz"))
    return blob(px, 8, 8, 4, (228, 224, 212))
add("scavock_world", "scavock_safezone", safezone_core)
def stab_adv():
    px = blank()
    for i in range(3, 12):
        px[SIZE - 1 - i][i] = (*BONE, 255)
        px[SIZE - 2 - i][i] = (*BONE, 255)
    px[3][12] = (170, 186, 205, 255); px[2][13] = (170, 186, 205, 255)
    px[12][2] = (182, 214, 46, 255); px[11][3] = (182, 214, 46, 255)
    return px
add("scavock_death", "scavock_stabiliser_adv", stab_adv)

# ---------- full roster (§24) ----------
ROSTER = {
    "cow": ((225, 222, 215), (60, 50, 45)),
    "chicken": ((235, 232, 225), (200, 60, 40)),
    "deer": ((176, 140, 96), (140, 106, 70)),
    "bear": ((70, 52, 38), (50, 36, 26)),
    "dog": ((150, 116, 78), (110, 82, 54)),
    "cat": ((130, 128, 132), (100, 98, 102)),
    "bat": ((48, 44, 50), (30, 28, 32)),
    "cavebear": ((88, 76, 66), (60, 50, 42)),
    "hyena": ((160, 140, 104), (90, 76, 56)),
    "megalania": ((104, 116, 84), (70, 80, 56)),
    "giganto": ((60, 50, 44), (40, 32, 28)),
    "terrorbird": ((140, 92, 60), (190, 70, 50)),
    "argentavis": ((70, 62, 58), (48, 42, 40)),
    "glyptodon": ((120, 112, 96), (86, 80, 68)),
    "titanoboa": ((84, 110, 70), (56, 76, 46)),
    "megisto": ((196, 190, 180), (160, 152, 140)),
    "yeti": ((232, 234, 238), (200, 204, 210)),
}
for cname, (base, streak) in ROSTER.items():
    add("scavock_creatures", "scavock_" + cname, fur(base, cname, streak))
    add("scavock_creatures", "scavock_" + cname + "_face", face(base, cname + "f"))
def rock():
    px = blank()
    return blob(px, 8, 8, 5, (110, 108, 104))
add("scavock_creatures", "scavock_rock", rock)
def egg():
    px = blank()
    return blob(px, 8, 9, 4, (235, 230, 215))
add("scavock_creatures", "scavock_egg", egg)
def fence_tex():
    px = blank()
    for y in range(SIZE):
        for x in (3, 4, 11, 12):
            px[y][x] = (110, 80, 44, 255)
    for y in (4, 5, 10, 11):
        for x in range(SIZE):
            px[y][x] = (130, 96, 56, 255)
    return px
add("scavock_creatures", "scavock_fence", fence_tex)

# ---------- power (§15) ----------
add("scavock_core", "scavock_copper_ore", ore((196, 120, 70), "copore"))
add("scavock_core", "scavock_copper_lump", item_dot((196, 120, 70), "coplump", 5))
add("scavock_core", "scavock_copper_ingot", ingot((196, 120, 70)))
def plastic():
    px = blank()
    for y in range(4, 12):
        for x in range(3, 13):
            px[y][x] = (210, 210, 214, 220)
    return px
add("scavock_power", "scavock_plastic", plastic)
def wire_tex():
    px = blank((0, 0, 0, 0))
    for x in range(SIZE):
        px[7][x] = (196, 120, 70, 255); px[8][x] = (150, 90, 52, 255)
    return px
add("scavock_power", "scavock_wire", wire_tex)
def lamp(on):
    def fn():
        base = (240, 232, 190) if on else (90, 92, 96)
        px = noise_fill(base, 6, R("lamp" + str(on)))
        return border(px, (60, 63, 70))
    return fn
add("scavock_power", "scavock_lamp_off", lamp(False))
add("scavock_power", "scavock_lamp_on", lamp(True))
def engine_tex():
    px = noise_fill((86, 90, 98), 8, R("engine"))
    speckle(px, (196, 120, 70), 6, R("engc"), 2)
    return border(px, (50, 53, 60))
add("scavock_power", "scavock_engine", engine_tex)
def battery_tex():
    px = noise_fill((60, 63, 70), 6, R("batt"))
    for y in range(5, 11):
        for x in range(4, 7):
            px[y][x] = (182, 214, 46, 255)
    return border(px, (40, 42, 46))
add("scavock_power", "scavock_battery", battery_tex)
def solar_tex():
    px = noise_fill((30, 40, 70), 8, R("solar"))
    for i in range(0, SIZE, 4):
        for j in range(SIZE):
            px[j][min(i, 15)] = (60, 75, 110, 255)
    return border(px, (86, 90, 98))
add("scavock_power", "scavock_solar", solar_tex)
def switch_tex(on):
    def fn():
        px = noise_fill((90, 92, 96), 6, R("sw" + str(on)))
        col = (182, 214, 46) if on else (179, 58, 36)
        for y in range(5, 11):
            for x in range(6, 10):
                px[y][x] = (*col, 255)
        return px
    return fn
add("scavock_power", "scavock_switch_off", switch_tex(False))
add("scavock_power", "scavock_switch_on", switch_tex(True))
add("scavock_power", "scavock_plate", lambda: border(noise_fill((120, 120, 122), 8, R("plate")), (86, 90, 98)))
def door_tex():
    px = vlines(noise_fill((130, 96, 56), 8, R("pdoor")), (100, 72, 40), 4, R("pdv"))
    return border(px, (196, 120, 70))
add("scavock_power", "scavock_door", door_tex)
def alarm_tex():
    px = noise_fill((60, 63, 70), 6, R("alarm"))
    return blob(px, 8, 8, 4, (179, 58, 36))
add("scavock_power", "scavock_alarm", alarm_tex)
def torch_tex():
    px = blank()
    for y in range(7, 14):
        for x in range(7, 9):
            px[y][x] = (110, 78, 44, 255)
    blob(px, 8, 5, 2, (232, 160, 60))
    return px
add("scavock_power", "scavock_torch", torch_tex)
def oil_tex():
    px = blank()
    for y in range(3, 13):
        for x in range(4, 12):
            px[y][x] = (179, 58, 36, 255)
    for y in range(5, 12):
        for x in range(5, 11):
            px[y][x] = (40, 38, 36, 255)
    return px
add("scavock_power", "scavock_oil", oil_tex)

# ---------- locks (§14) ----------
def lock_tex(color):
    def fn():
        px = blank()
        for y in range(6, 13):
            for x in range(4, 12):
                px[y][x] = (*color, 255)
        for a in range(0, 180, 20):
            import math as _m
            x = int(8 + 3 * _m.cos(_m.radians(a))); y = int(6 - 3 * _m.sin(_m.radians(a)))
            if 0 <= y < 16: px[y][x] = (140, 140, 145, 255)
        px[9][7] = (20, 20, 22, 255); px[9][8] = (20, 20, 22, 255)
        return px
    return fn
add("scavock_locks", "scavock_lock_pickable", lock_tex((150, 152, 158)))
add("scavock_locks", "scavock_lock_passcode", lock_tex((196, 120, 70)))
def lockpick():
    px = blank()
    for i in range(3, 13):
        px[SIZE - 1 - i][i] = (198, 198, 200, 255)
    px[3][12] = (198, 198, 200, 255); px[4][12] = (198, 198, 200, 255)
    return px
add("scavock_locks", "scavock_lockpick", lockpick)
def locker():
    px = noise_fill((100, 106, 116), 6, R("locker"))
    border(px, (70, 74, 82))
    for y in range(3, 13):
        px[y][8] = (70, 74, 82, 255)
    return px
add("scavock_locks", "scavock_locker", locker)
def crate_cracked():
    px = vlines(noise_fill((140, 104, 60), 8, R("cratecr")), (110, 80, 44), 5, R("cratecrv"))
    for i in range(3, 13):
        px[i][i] = (30, 26, 20, 255)
        px[i][i - 1] = (30, 26, 20, 255)
    return px
add("scavock_locks", "scavock_crate_cracked", crate_cracked)

# ---------- explosives (§16) ----------
def tnt_tex():
    px = noise_fill((179, 58, 36), 8, R("tnt"))
    for y in range(6, 10):
        for x in range(SIZE):
            px[y][x] = (228, 224, 212, 255)
    return px
add("scavock_boom", "scavock_tnt", tnt_tex)
def tnt_lit():
    px = tnt_tex()
    px[1][8] = (232, 160, 60, 255); px[0][8] = (240, 200, 80, 255)
    return px
add("scavock_boom", "scavock_tnt_lit", tnt_lit)
def grenade_tex():
    px = blank()
    blob(px, 8, 9, 4, (70, 76, 68))
    px[4][8] = (150, 152, 158, 255); px[3][8] = (150, 152, 158, 255)
    return px
add("scavock_boom", "scavock_grenade", grenade_tex)
def sensor_tex():
    px = blank()
    for y in range(5, 11):
        for x in range(4, 12):
            px[y][x] = (60, 63, 70, 255)
    px[7][7] = (182, 214, 46, 255); px[7][8] = (182, 214, 46, 255)
    return px
add("scavock_boom", "scavock_sensor", sensor_tex)
def button_tex():
    px = blank()
    for y in range(5, 12):
        for x in range(4, 12):
            px[y][x] = (86, 90, 98, 255)
    blob(px, 8, 8, 2, (179, 58, 36))
    return px
add("scavock_boom", "scavock_button", button_tex)
def trigger_bomb():
    px = grenade_tex()
    px[7][3] = (182, 214, 46, 255); px[8][3] = (182, 214, 46, 255)
    return px
add("scavock_boom", "scavock_trigger_bomb", trigger_bomb)
def trigger_button():
    px = button_tex()
    px[4][4] = (182, 214, 46, 255)
    return px
add("scavock_boom", "scavock_trigger_button", trigger_button)

# ---------- bow upgrades (§17) ----------
def bow_piercing():
    px = OUT["mods/scavock_weapons/textures/scavock_bow.png"]()
    for y in range(2, 14):
        if px[y][12][3] > 0:
            px[y][12] = (170, 186, 205, 255)
    px[2][13] = (170, 186, 205, 255); px[13][2] = (170, 186, 205, 255)
    return px
add("scavock_weapons", "scavock_bow_piercing", bow_piercing)
def arrow_fx(tip):
    def fn():
        px = OUT["mods/scavock_weapons/textures/scavock_arrow.png"]()
        px[2][13] = (*tip, 255); px[3][12] = (*tip, 255); px[3][13] = (*tip, 255)
        return px
    return fn
add("scavock_weapons", "scavock_arrow_poison", arrow_fx((182, 214, 46)))
add("scavock_weapons", "scavock_arrow_fire", arrow_fx((217, 118, 30)))
add("scavock_weapons", "scavock_arrow_explosive", arrow_fx((179, 58, 36)))

# ---------- evac structure (§21) ----------
def console_tex():
    px = noise_fill((60, 64, 70), 6, R("console"))
    border(px, (40, 42, 46))
    for y in range(4, 7):
        for x in range(3, 13):
            px[y][x] = (28, 30, 35, 255)
    px[5][5] = (182, 214, 46, 255); px[5][8] = (179, 58, 36, 255)
    for y in range(9, 13):
        px[y][7] = (150, 152, 158, 255); px[y][8] = (150, 152, 158, 255)
    return px
add("scavock_evac", "scavock_console", console_tex)
def trapdoor_tex():
    px = vlines(noise_fill((100, 106, 116), 6, R("trap")), (70, 74, 82), 4, R("trapv"))
    return border(px, (50, 53, 60))
add("scavock_evac", "scavock_trapdoor", trapdoor_tex)

# ---------- discovery chain (§4b/4c) ----------
def tinted_stone(tint, name):
    def fn():
        px = noise_fill((120, 120, 122), 10, R("stone"))
        for y in range(SIZE):
            for x in range(SIZE):
                r, g, b, a = px[y][x]
                px[y][x] = (clamp((r + tint[0]) // 2), clamp((g + tint[1]) // 2),
                            clamp((b + tint[2]) // 2), a)
        return px
    return fn
add("scavock_under", "scavock_stone_mut", tinted_stone((182, 214, 46), "smut"))
add("scavock_under", "scavock_stone_cavock", tinted_stone((217, 118, 30), "scav"))
def mut_grass():
    px = noise_fill((140, 180, 40), 14, R("mutgrass"))
    return px
add("scavock_under", "scavock_mut_grass_top", mut_grass)
def tech_block():
    px = noise_fill((70, 74, 82), 5, R("tech"))
    border(px, (50, 53, 60))
    for x in range(2, 14, 4):
        px[7][x] = (182, 214, 46, 255); px[8][x] = (86, 90, 98, 255)
    return px
add("scavock_under", "scavock_tech", tech_block)
def ice_city():
    px = noise_fill((190, 210, 230), 8, R("icecity"))
    return border(px, (150, 170, 195))
add("scavock_under", "scavock_ice_city", ice_city)
def source_core():
    px = noise_fill((40, 44, 52), 6, R("source"))
    blob(px, 8, 8, 5, (182, 214, 46))
    blob(px, 8, 8, 2, (228, 224, 212))
    return px
add("scavock_under", "scavock_source", source_core)
def adv_tech():
    px = blank()
    for y in range(4, 12):
        for x in range(4, 12):
            px[y][x] = (70, 74, 82, 255)
    px[7][7] = (182, 214, 46, 255); px[8][8] = (182, 214, 46, 255)
    px[7][8] = (228, 224, 212, 255); px[8][7] = (228, 224, 212, 255)
    return px
add("scavock_under", "scavock_advtech", adv_tech)
def compass_tex(preset=False):
    def fn():
        px = blank()
        import math as _m
        for a in range(0, 360, 8):
            x = int(8 + 6 * _m.cos(_m.radians(a)))
            y = int(8 + 6 * _m.sin(_m.radians(a)))
            px[y][x] = (86, 90, 98, 255)
        for i in range(1, 6):
            px[8 - i][8] = (179, 58, 36, 255) if not preset else (217, 118, 30, 255)
            if i < 4:
                px[8 + i][8] = (228, 224, 212, 255)
        return px
    return fn
add("scavock_compass", "scavock_compass", compass_tex(False))
add("scavock_compass", "scavock_compass_cavock", compass_tex(True))

# ---------- vehicles (§27) + water (§24.10) ----------
def car_tex():
    px = noise_fill((150, 60, 44), 8, R("car"))
    for y in range(3, 8):
        for x in range(3, 13):
            px[y][x] = (140, 170, 190, 230)
    for x in (2, 13):
        for y in range(12, 15):
            px[y][x] = (30, 30, 32, 255)
    return px
add("scavock_vehicles", "scavock_car", car_tex)
def boat_tex():
    px = vlines(noise_fill((130, 96, 56), 8, R("boat")), (100, 72, 40), 4, R("boatv"))
    return border(px, (90, 64, 36))
add("scavock_vehicles", "scavock_boat", boat_tex)
def plane_tex():
    px = noise_fill((170, 175, 182), 8, R("plane"))
    for y in range(6, 10):
        for x in range(SIZE):
            px[y][x] = (120, 126, 134, 255)
    return px
add("scavock_vehicles", "scavock_plane", plane_tex)
def pump_tex():
    px = noise_fill((179, 58, 36), 8, R("pump"))
    border(px, (90, 30, 20))
    for y in range(4, 8):
        for x in range(5, 11):
            px[y][x] = (228, 224, 212, 255)
    return px
add("scavock_vehicles", "scavock_pump", pump_tex)
def fish_tex():
    px = blank()
    blob(px, 7, 8, 4, (140, 160, 180))
    px[8][12] = (140, 160, 180, 255); px[7][13] = (140, 160, 180, 255)
    px[9][13] = (140, 160, 180, 255)
    px[7][5] = (20, 20, 22, 255)
    return px
add("scavock_vehicles", "scavock_fish", fish_tex)
def rod_tex():
    px = blank()
    diag_handle(px, (110, 78, 44))
    for y in range(2, 8):
        px[y][13] = (210, 210, 200, 255)
    px[8][13] = (179, 58, 36, 255)
    return px
add("scavock_vehicles", "scavock_rod", rod_tex)

def main():
    n = 0
    for rel, fn in OUT.items():
        write_png(os.path.join(ROOT, rel), fn())
        n += 1
    print(f"wrote {n} textures")

if __name__ == "__main__":
    main()
