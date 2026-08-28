#!/usr/bin/env python3
"""Generic box-rig creature bodies (§23: box-rig everything).

Four OBJ bodies; every face maps the full texture, so each creature's
existing fur/face texture wraps it. Per-creature proportions come from
visual_size (which stretches the mesh):
  scavock_quad.obj    — body + head + 4 legs (wolves, bears, cows...)
  scavock_biped.obj   — torso + head + arms + legs (Gigantopithecus, Yeti)
  scavock_bird.obj    — body + head/beak + wings (chicken, birds, bats)
  scavock_serpent.obj — segments + head (Titanoboa)
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "mods", "scavock_creatures", "models")

def box(verts, uvs, faces, mn, mx):
    x0, y0, z0 = mn
    x1, y1, z1 = mx
    base = len(verts)
    for X in (x0, x1):
        for Y in (y0, y1):
            for Z in (z0, z1):
                verts.append((X, Y, Z))
    if not uvs:
        uvs.extend([(0, 0), (1, 0), (1, 1), (0, 1)])
    t1, t2, t3, t4 = 1, 2, 3, 4
    c = lambda xi, yi, zi: base + xi * 4 + yi * 2 + zi + 1
    quads = [
        (c(0,0,1), c(1,0,1), c(1,1,1), c(0,1,1)),  # front +z
        (c(1,0,0), c(0,0,0), c(0,1,0), c(1,1,0)),  # back
        (c(0,0,0), c(0,0,1), c(0,1,1), c(0,1,0)),  # -x
        (c(1,0,1), c(1,0,0), c(1,1,0), c(1,1,1)),  # +x
        (c(0,1,1), c(1,1,1), c(1,1,0), c(0,1,0)),  # top
        (c(0,0,0), c(1,0,0), c(1,0,1), c(0,0,1)),  # bottom
    ]
    for q in quads:
        faces.append(((q[0], t1), (q[1], t2), (q[2], t3), (q[3], t4)))

def write_obj(name, boxes):
    verts, uvs, faces = [], [], []
    for mn, mx in boxes:
        box(verts, uvs, faces, mn, mx)
    lines = ["o " + name]
    for v in verts:
        lines.append("v %.4f %.4f %.4f" % v)
    for t in uvs:
        lines.append("vt %.4f %.4f" % t)
    for f in faces:
        lines.append("f " + " ".join("%d/%d" % p for p in f))
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".obj"), "w") as fh:
        fh.write("\n".join(lines) + "\n")

def main():
    write_obj("scavock_quad", [
        ((-0.28, 0.34, -0.5), (0.28, 0.78, 0.38)),   # body
        ((-0.18, 0.55, 0.30), (0.18, 0.95, 0.68)),   # head
        ((-0.26, 0.0, -0.46), (-0.10, 0.4, -0.30)),  # legs
        ((0.10, 0.0, -0.46), (0.26, 0.4, -0.30)),
        ((-0.26, 0.0, 0.20), (-0.10, 0.4, 0.36)),
        ((0.10, 0.0, 0.20), (0.26, 0.4, 0.36)),
        ((-0.06, 0.55, -0.66), (0.06, 0.68, -0.48)), # tail stub
    ])
    write_obj("scavock_biped", [
        ((-0.30, 0.75, -0.18), (0.30, 1.55, 0.18)),  # torso
        ((-0.20, 1.55, -0.20), (0.20, 1.95, 0.20)),  # head
        ((-0.48, 0.55, -0.12), (-0.30, 1.50, 0.12)), # arms (long)
        ((0.30, 0.55, -0.12), (0.48, 1.50, 0.12)),
        ((-0.24, 0.0, -0.12), (-0.04, 0.75, 0.12)),  # legs
        ((0.04, 0.0, -0.12), (0.24, 0.75, 0.12)),
    ])
    write_obj("scavock_bird", [
        ((-0.22, 0.3, -0.4), (0.22, 0.75, 0.3)),     # body
        ((-0.13, 0.7, 0.2), (0.13, 1.0, 0.48)),      # head
        ((-0.04, 0.78, 0.46), (0.04, 0.86, 0.66)),   # beak
        ((-0.62, 0.55, -0.3), (-0.22, 0.63, 0.2)),   # wings
        ((0.22, 0.55, -0.3), (0.62, 0.63, 0.2)),
        ((-0.14, 0.0, -0.08), (-0.05, 0.32, 0.04)),  # legs
        ((0.05, 0.0, -0.08), (0.14, 0.32, 0.04)),
    ])
    write_obj("scavock_serpent", [
        ((-0.30, 0.0, -0.9), (0.30, 0.42, -0.2)),    # rear segment
        ((-0.34, 0.0, -0.25), (0.34, 0.5, 0.35)),    # mid segment
        ((-0.26, 0.15, 0.3), (0.26, 0.62, 0.75)),    # fore
        ((-0.2, 0.35, 0.7), (0.2, 0.75, 1.05)),      # head
    ])
    print("creature models written")

if __name__ == "__main__":
    main()
