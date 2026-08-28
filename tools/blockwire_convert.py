#!/usr/bin/env python3
"""Blockwire -> Luanti texture converter (BLOCKWIRE-FILE-FORMATS.md, blocks
only per D13 scope direction).

Decodes `kind:"block"` recipes — int colors (0x1000000 = transparent,
inverted-alpha top byte), row-major faces, optional facesRLE — into PNGs a
Luanti texture pack (or our mods) can use directly.

Usage:
  # one recipe -> six face PNGs + a main PNG (previewFace)
  python3 tools/blockwire_convert.py my_block.json --name scavock_stone --out pack/

  # a whole texture pack from a mapping file (lines: file.json = texture_name)
  python3 tools/blockwire_convert.py --pack blockwire_dir/ --map map.txt --out pack/

The pack gets a texture_pack.conf; drop the folder into Luanti's
textures/ dir (client side) to reskin Scavock without touching the game.
"""
import os, sys, json, struct, zlib, argparse

TRANSPARENT = 0x1000000
FACES = ["front", "back", "left", "right", "top", "bottom"]

def decode_pixel(px):
    if px == TRANSPARENT:
        return (0, 0, 0, 0)
    r = (px >> 16) & 255
    g = (px >> 8) & 255
    b = px & 255
    a = 255 - ((px >> 24) & 255)
    return (r, g, b, a)

def rle_expand(enc):
    out = []
    for i in range(0, len(enc), 2):
        out.extend([enc[i]] * enc[i + 1])
    return out

def write_png(path, w, h, pixels):
    raw = b""
    for y in range(h):
        raw += b"\x00" + b"".join(
            struct.pack("4B", *pixels[y * w + x]) for x in range(w))
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I",
            zlib.crc32(c) & 0xffffffff)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

def convert(json_path, name, out_dir):
    with open(json_path) as f:
        d = json.load(f)
    if not (d.get("faces") or d.get("facesRLE")):
        raise SystemExit(json_path + ": not a Blockwire block recipe (no faces)")
    if d.get("kind", "block") not in ("block", "voxel"):
        print("  note: kind=%s — converting its faces only" % d.get("kind"))
    w_px = d.get("w", 1) * 16
    h_px = d.get("h", 1) * 16
    faces = d.get("faces") or {}
    rle = d.get("facesRLE") or {}
    written = []
    for face in FACES:
        arr = faces.get(face) or (rle_expand(rle[face]) if face in rle else None)
        if not arr:
            continue
        pixels = [decode_pixel(p) for p in arr]
        if len(pixels) < w_px * h_px:
            pixels += [(0, 0, 0, 0)] * (w_px * h_px - len(pixels))
        write_png(os.path.join(out_dir, "%s_%s.png" % (name, face)),
            w_px, h_px, pixels)
        written.append(face)
    # main texture = previewFace (what most single-texture nodes use)
    main = d.get("previewFace", "front")
    if main in written:
        src = os.path.join(out_dir, "%s_%s.png" % (name, main))
        with open(src, "rb") as f:
            data = f.read()
        with open(os.path.join(out_dir, name + ".png"), "wb") as f:
            f.write(data)
    print("%s -> %s (%s + main)" % (os.path.basename(json_path), name,
        ",".join(written)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json", nargs="?")
    ap.add_argument("--name")
    ap.add_argument("--out", default="blockwire_pack")
    ap.add_argument("--pack", help="directory of blockwire .json files")
    ap.add_argument("--map", help="mapping file: <file.json> = <texture_name>")
    ap.add_argument("--title", default="Scavock Blockwire Pack")
    args = ap.parse_args()

    if args.pack and args.map:
        with open(args.map) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                src, name = [p.strip() for p in line.split("=", 1)]
                convert(os.path.join(args.pack, src), name, args.out)
        with open(os.path.join(args.out, "texture_pack.conf"), "w") as f:
            f.write("title = %s\ndescription = Converted from Blockwire recipes\n"
                % args.title)
        print("pack ready: %s (drop into Luanti's textures/ dir)" % args.out)
    elif args.json and args.name:
        convert(args.json, args.name, args.out)
    else:
        ap.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
