#!/usr/bin/env python3
"""Scavock box-rig player (D15: Minecraft 64x64 skin format).

Generates:
  mods/scavock_player/models/scavock_character.obj  — 6-box rig, MC UV layout
  mods/scavock_player/textures/scavock_skin_base.png    — WHITE body (recolored
      by skin tone via ^[multiply)
  .../scavock_skin_clothes.png  — fixed shorts overlay (spawn state, §10)
  .../scavock_face_N.png        — face features, transparent elsewhere
  .../scavock_hair_N.png        — WHITE hair shapes (recolored via multiply)
  .../scavock_beard_N.png       — WHITE facial hair

REPLACE THESE PNGs with real art under the same filenames: one 64x64 base
skin, face overlays (transparent except the face), hair and facial-hair
overlays. The customizer composites base^tone ^ clothes ^ face ^ hair ^ beard
in that order.
"""
import os, struct, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXDIR = os.path.join(ROOT, "mods", "scavock_player", "textures")
MODELDIR = os.path.join(ROOT, "mods", "scavock_player", "models")
W = H = 64

def write_png(path, px):
    raw = b""
    for row in px:
        raw += b"\x00" + b"".join(struct.pack("4B", *p) for p in row)
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

def canvas():
    return [[(0, 0, 0, 0)] * W for _ in range(H)]

def rect(px, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            px[y][x] = color

# ---------------------------------------------------------------------------
# OBJ: boxes with the classic MC UV unwrap. Sizes in px (16px = 1 node).
# ---------------------------------------------------------------------------
SCALE = 1.0 / 16.0  # -> ~2.0 units tall

# name: (size(w,h,d), position of box min-corner (x,y,z) px, uv origin (u,v))
BOXES = {
    "head":  ((8, 8, 8),  (-4, 24, -4), (0, 0)),
    "torso": ((8, 12, 4), (-4, 12, -2), (16, 16)),
    "rarm":  ((4, 12, 4), (-8, 12, -2), (40, 16)),
    "larm":  ((4, 12, 4), (4, 12, -2),  (32, 48)),
    "rleg":  ((4, 12, 4), (-4, 0, -2),  (0, 16)),
    "lleg":  ((4, 12, 4), (0, 0, -2),   (16, 48)),
}

def uv(u, v):
    return (u / 64.0, 1.0 - v / 64.0)

def gen_obj():
    verts, uvs, faces = [], [], []
    def V(x, y, z):
        verts.append((x * SCALE, y * SCALE, z * SCALE))
        return len(verts)
    def T(u, v):
        uvs.append(uv(u, v))
        return len(uvs)
    for name, (size, pos, uvo) in BOXES.items():
        w, h, d = size
        x, y, z = pos
        u0, v0 = uvo
        # 8 corners
        c = {}
        for xi, X in ((0, x), (1, x + w)):
            for yi, Y in ((0, y), (1, y + h)):
                for zi, Z in ((0, z), (1, z + d)):
                    c[(xi, yi, zi)] = V(X, Y, Z)
        # face definitions: corner keys (ccw from outside) + uv rect (x0,y0,x1,y1)
        F = [
            # front (+z)
            ([(0,0,1),(1,0,1),(1,1,1),(0,1,1)], (u0+d, v0+d, u0+d+w, v0+d+h), True),
            # back (-z)
            ([(1,0,0),(0,0,0),(0,1,0),(1,1,0)], (u0+2*d+w, v0+d, u0+2*d+2*w, v0+d+h), True),
            # right (-x)
            ([(0,0,0),(0,0,1),(0,1,1),(0,1,0)], (u0, v0+d, u0+d, v0+d+h), True),
            # left (+x)
            ([(1,0,1),(1,0,0),(1,1,0),(1,1,1)], (u0+d+w, v0+d, u0+d+w+d, v0+d+h), True),
            # top (+y)
            ([(0,1,1),(1,1,1),(1,1,0),(0,1,0)], (u0+d, v0, u0+d+w, v0+d), False),
            # bottom (-y)
            ([(0,0,0),(1,0,0),(1,0,1),(0,0,1)], (u0+d+w, v0, u0+d+2*w, v0+d), False),
        ]
        for corners, (ux0, uy0, ux1, uy1), flip in F:
            # uv corners matching vertex order: bl, br, tr, tl in texture
            # space (texture y grows downward; uv() flips)
            t1 = T(ux0, uy1)
            t2 = T(ux1, uy1)
            t3 = T(ux1, uy0)
            t4 = T(ux0, uy0)
            vi = [c[k] for k in corners]
            faces.append(((vi[0], t1), (vi[1], t2), (vi[2], t3), (vi[3], t4)))
    out = ["# Scavock box-rig character (D15)", "o scavock_character"]
    for v in verts:
        out.append("v %.5f %.5f %.5f" % v)
    for t in uvs:
        out.append("vt %.5f %.5f" % t)
    for f in faces:
        out.append("f " + " ".join("%d/%d" % p for p in f))
    os.makedirs(MODELDIR, exist_ok=True)
    with open(os.path.join(MODELDIR, "scavock_character.obj"), "w") as fh:
        fh.write("\n".join(out) + "\n")

# ---------------------------------------------------------------------------
# Texture regions helper: paint every used UV region of every box
# ---------------------------------------------------------------------------
def paint_all_regions(px, color):
    for name, (size, pos, uvo) in BOXES.items():
        w, h, d = size
        u0, v0 = uvo
        rect(px, u0 + d, v0, u0 + d + 2 * w, v0 + d, color)          # top+bottom
        rect(px, u0, v0 + d, u0 + 2 * d + 2 * w, v0 + d + h, color)  # side strip
    return px

def main():
    gen_obj()

    base = paint_all_regions(canvas(), (255, 255, 255, 255))
    write_png(os.path.join(TEXDIR, "scavock_skin_base.png"), base)

    # fixed shorts (§10 spawn state): upper legs + hip rows, slate
    clothes = canvas()
    SLATE = (80, 88, 100, 255)
    for legname in ("rleg", "lleg"):
        size, pos, (u0, v0) = BOXES[legname]
        w, h, d = size
        rect(clothes, u0, v0 + d, u0 + 2 * d + 2 * w, v0 + d + 6, SLATE)
    # torso bottom two rows
    size, pos, (u0, v0) = BOXES["torso"]
    w, h, d = size
    rect(clothes, u0, v0 + d + h - 2, u0 + 2 * d + 2 * w, v0 + d + h, SLATE)
    write_png(os.path.join(TEXDIR, "scavock_skin_clothes.png"), clothes)

    # faces: features inside head-front rect (8,8)-(16,16)
    EYE = (30, 32, 36, 255)
    MOUTH = (140, 80, 70, 255)
    for i, mouth_row in ((1, 14), (2, 13), (3, 14)):
        f = canvas()
        f[11][10] = EYE; f[11][13] = EYE
        if i == 2:
            f[11][9] = EYE; f[11][14] = EYE
        for x in range(10 if i != 3 else 11, 14 if i != 3 else 13):
            f[mouth_row][x] = MOUTH
        write_png(os.path.join(TEXDIR, "scavock_face_%d.png" % i), f)

    # hair: WHITE shapes (multiply-recolored)
    WHT = (255, 255, 255, 255)
    size, pos, (u0, v0) = BOXES["head"]
    w, h, d = size
    for i in range(1, 4):
        hpx = canvas()
        rect(hpx, u0 + d, v0, u0 + d + w, v0 + d, WHT)      # top of head
        fringe = (2, 1, 3)[i - 1]
        rect(hpx, u0, v0 + d, u0 + 2 * d + 2 * w, v0 + d + fringe, WHT)
        if i == 3:  # long: down the back
            rect(hpx, u0 + 2 * d + w, v0 + d, u0 + 2 * d + 2 * w, v0 + d + 7, WHT)
        write_png(os.path.join(TEXDIR, "scavock_hair_%d.png" % i), hpx)

    # beards
    for i, rows in ((1, 2), (2, 4)):
        b = canvas()
        rect(b, u0 + d + 1, v0 + d + h - rows, u0 + d + w - 1, v0 + d + h, WHT)
        write_png(os.path.join(TEXDIR, "scavock_beard_%d.png" % i), b)

    print("player assets written")

if __name__ == "__main__":
    main()
