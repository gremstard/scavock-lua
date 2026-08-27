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

def main():
    n = 0
    for rel, fn in OUT.items():
        write_png(os.path.join(ROOT, rel), fn())
        n += 1
    print(f"wrote {n} textures")

if __name__ == "__main__":
    main()
