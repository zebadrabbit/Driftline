#!/usr/bin/env python3
"""Import original SubSpace .lvl maps into driftline map format v1.

LVL format: optional BMP tileset at the start (magic 'BM'; tile data begins at
the offset stored in the BMP file-size field). Then 4-byte little-endian tile
records: bits 0-11 = x, bits 12-23 = y, bits 24-31 = tile id. Arena 1024x1024.

Tile id mapping (VIE special tiles):
  1-161   solid walls          -> solid layer, atlas ((id-1)%19, (id-1)//19)
  162-169 doors                -> solid layer (engine animates/toggles them)
  170     turf flag            -> skipped for now (needs FlagMode 2 support)
  171     safe zone            -> fg layer (non-solid, safe_zone per tiles_def)
  172     goal tile            -> bg layer + clustered into goal entities
  173-175 fly-over decor       -> fg layer (non-solid)
  176-190 fly-under decor      -> bg layer (non-solid)
  216-218 asteroids            -> solid rock tile
  219     station (6x6)        -> 6x6 solid rock footprint
  220     wormhole (5x5)       -> wormhole entity at center
  else    ignored

Usage: python tools/lvl_import.py input.lvl [-o maps/imported/name.json]
"""
import argparse
import json
import os
import struct
from collections import deque

ARENA = 1024
ROCK_ATLAS = (1, 0)  # generic solid tile for asteroids/station footprints


def atlas(tile_id: int):
    return ((tile_id - 1) % 19, (tile_id - 1) // 19)


def read_tiles(path: str):
    data = open(path, "rb").read()
    off = 0
    if data[:2] == b"BM":
        off = struct.unpack_from("<I", data, 2)[0]
    tiles = []
    for i in range(off, len(data) - 3, 4):
        v = struct.unpack_from("<I", data, i)[0]
        x = v & 0xFFF
        y = (v >> 12) & 0xFFF
        t = v >> 24
        if 0 <= x < ARENA and 0 <= y < ARENA and t > 0:
            tiles.append((x, y, t))
    return tiles


def in_interior(x, y):
    return 0 < x < ARENA - 1 and 0 < y < ARENA - 1


def cluster(cells):
    """Connected 4-neighbour clusters of (x,y) cells."""
    todo = set(cells)
    out = []
    while todo:
        seed = todo.pop()
        group = [seed]
        q = deque([seed])
        while q:
            x, y = q.popleft()
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if n in todo:
                    todo.discard(n)
                    group.append(n)
                    q.append(n)
        out.append(group)
    return out


def convert(path: str):
    tiles = read_tiles(path)
    solid, fg, bg = [], [], []
    goal_cells, wormholes = [], []
    turf_flags = 0
    entities_turf = []
    solid_set = set()

    def add_solid(x, y, ax, ay):
        if in_interior(x, y) and (x, y) not in solid_set:
            solid_set.add((x, y))
            solid.append([x, y, ax, ay])

    for x, y, t in tiles:
        if not in_interior(x, y):
            continue
        if 1 <= t <= 169:
            add_solid(x, y, *atlas(t))
        elif t == 170:
            turf_flags += 1
            entities_turf.append({"type": "flag", "x": x, "y": y, "team": 0})
        elif t == 171:
            fg.append([x, y, *atlas(t)])
        elif t == 172:
            bg.append([x, y, *atlas(t)])
            goal_cells.append((x, y))
        elif 173 <= t <= 175:
            fg.append([x, y, *atlas(t)])
        elif 176 <= t <= 190:
            bg.append([x, y, *atlas(t)])
        elif 216 <= t <= 218:
            size = 2 if t == 217 else 1
            for dy in range(size):
                for dx in range(size):
                    add_solid(x + dx, y + dy, *ROCK_ATLAS)
        elif t == 219:
            for dy in range(6):
                for dx in range(6):
                    add_solid(x + dx, y + dy, *ROCK_ATLAS)
        elif t == 220:
            wormholes.append((x + 2, y + 2))  # 5x5 footprint, entity at center

    entities = list(entities_turf)
    for wx, wy in wormholes:
        entities.append({"type": "wormhole", "x": wx, "y": wy, "team": 0})
    for group in cluster(goal_cells):
        cx = sum(c[0] for c in group) // len(group)
        cy = sum(c[1] for c in group) // len(group)
        # radius in px covering the cluster
        r = max(max(abs(c[0] - cx), abs(c[1] - cy)) for c in group) * 16 + 16
        team = 1 if cx < ARENA // 2 else 2
        entities.append({"type": "goal", "x": cx, "y": cy, "team": team, "radius": r})

    # Spawns: nearest open tiles to arena center (original used center-radius spawning).
    def open_at(x, y):
        return in_interior(x, y) and (x, y) not in solid_set
    placed = 0
    used = set()
    for ring in range(0, ARENA // 2, 4):
        if placed >= 8:
            break
        for x, y in ((512 - ring, 512), (512 + ring, 512), (512, 512 - ring), (512, 512 + ring)):
            if placed < 8 and (x, y) not in used and open_at(x, y):
                used.add((x, y))
                entities.append({"type": "spawn", "x": x, "y": y, "team": 1 + placed % 2})
                placed += 1

    name = os.path.splitext(os.path.basename(path))[0].lstrip("_")
    print(f"{name}: {len(tiles)} records -> {len(solid)} solid, {len(fg)} fg, "
          f"{len(bg)} bg, {len(entities)} entities "
          f"(wormholes={len(wormholes)}, goals={len(cluster(goal_cells)) if goal_cells else 0}, "
          f"turf_flags={turf_flags})")

    return {
        "format": "driftline.map",
        "schema_version": 1,
        "meta": {"w": ARENA, "h": ARENA, "tile_size": 16, "tileset": "subspace_base"},
        "entities": entities,
        "layers": {"bg": bg, "solid": solid, "fg": fg},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("-o", "--out", default=None)
    args = ap.parse_args()
    data = convert(args.input)
    out = args.out
    if out is None:
        name = os.path.splitext(os.path.basename(args.input))[0].lstrip("_").lower()
        out = os.path.join("maps", "imported", name + ".json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", newline="\n") as f:
        json.dump(data, f, separators=(",", ":"))
        f.write("\n")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
