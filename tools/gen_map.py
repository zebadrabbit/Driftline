#!/usr/bin/env python3
"""Procedural map generator for driftline (map format v1).

Generates a SubSpace-style arena: organic rock formations (cellular automata),
a central safe zone, east/west team bases with flags + goals + spawns.
All open space is guaranteed connected (isolated pockets are filled solid).

Usage:
    python tools/gen_map.py [--size 1024] [--seed 1] [--density 0.42]
                            [--out maps/procgen.json]
"""
import argparse
import json
import random
from collections import deque

SOLID_ATLAS = (1, 0)     # wall tile used by maps/default.json
SAFE_ATLAS = (18, 8)     # safe-zone bg tile per tiles_def.json
TILE_SIZE = 16


def generate(size: int, seed: int, density: float) -> dict:
    rng = random.Random(seed)
    w = h = size
    # grid[y][x]: True = solid rock. Border ring is engine-generated; keep it open here.
    grid = [[rng.random() < density for _ in range(w)] for _ in range(h)]

    # Cellular automata smoothing -> organic rock blobs.
    for _ in range(5):
        nxt = [row[:] for row in grid]
        for y in range(1, h - 1):
            row_a, row_b, row_c = grid[y - 1], grid[y], grid[y + 1]
            for x in range(1, w - 1):
                n = (row_a[x - 1] + row_a[x] + row_a[x + 1]
                     + row_b[x - 1] + row_b[x + 1]
                     + row_c[x - 1] + row_c[x] + row_c[x + 1])
                nxt[y][x] = n >= 4 if row_b[x] else n >= 5
        grid = nxt

    def clear_rect(x0, y0, x1, y1):
        for y in range(max(0, y0), min(h, y1)):
            for x in range(max(0, x0), min(w, x1)):
                grid[y][x] = False

    def wall_rect(x0, y0, x1, y1, gaps):
        """Hollow rectangle outline with entrance gaps (list of (x, y) tiles skipped)."""
        gapset = set(gaps)
        for x in range(x0, x1):
            for y in (y0, y1 - 1):
                if (x, y) not in gapset:
                    grid[y][x] = True
        for y in range(y0, y1):
            for x in (x0, x1 - 1):
                if (x, y) not in gapset:
                    grid[y][x] = True

    cx, cy = w // 2, h // 2
    safe_half = 25  # 50x50 center safe zone, same as default map

    # Central safe zone: open bowl a bit larger than the safe tiles.
    clear_rect(cx - safe_half - 8, cy - safe_half - 8, cx + safe_half + 8, cy + safe_half + 8)

    # Team bases east and west: open room, wall outline with entrance gaps.
    base_half = 24
    entities = []
    for team, bx in ((1, w // 8), (2, w - w // 8)):
        x0, y0 = bx - base_half, cy - base_half
        x1, y1 = bx + base_half, cy + base_half
        clear_rect(x0 - 6, y0 - 6, x1 + 6, y1 + 6)
        gaps = []
        gap_w = 6
        for gy in range(cy - gap_w // 2, cy + gap_w // 2):   # east + west entrances
            gaps.append((x0, gy))
            gaps.append((x1 - 1, gy))
        for gx in range(bx - gap_w // 2, bx + gap_w // 2):   # north + south entrances
            gaps.append((gx, y0))
            gaps.append((gx, y1 - 1))
        wall_rect(x0, y0, x1, y1, gaps)
        entities.append({"type": "flag", "x": bx, "y": cy, "team": team})
        entities.append({"type": "goal", "x": bx, "y": cy, "team": 3 - team, "radius": 64})
        for i in range(5):
            entities.append({"type": "spawn", "x": bx + (i - 2) * 4, "y": cy + base_half + 12, "team": team})

    # Keep the outer ring open so the generated boundary wall doesn't create pockets.
    clear_rect(1, 1, w - 1, 3)
    clear_rect(1, h - 3, w - 1, h - 1)
    clear_rect(1, 1, 3, h - 1)
    clear_rect(w - 3, 1, w - 1, h - 1)

    # Connectivity: flood-fill open space from center; fill unreachable pockets solid.
    reachable = [[False] * w for _ in range(h)]
    q = deque([(cx, cy)])
    reachable[cy][cx] = True
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 < nx < w - 1 and 0 < ny < h - 1 and not reachable[ny][nx] and not grid[ny][nx]:
                reachable[ny][nx] = True
                q.append((nx, ny))
    filled = 0
    for y in range(h):
        for x in range(w):
            if not grid[y][x] and not reachable[y][x]:
                grid[y][x] = True
                filled += 1

    solid = [[x, y, *SOLID_ATLAS] for y in range(h) for x in range(w) if grid[y][x]]
    fg = [[x, y, *SAFE_ATLAS]
          for y in range(cy - safe_half, cy + safe_half)
          for x in range(cx - safe_half, cx + safe_half)]

    print(f"size={w}x{h} seed={seed} solids={len(solid)} "
          f"({100.0 * len(solid) / (w * h):.1f}%) pockets_filled={filled}")

    return {
        "format": "driftline.map",
        "schema_version": 1,
        "meta": {"w": w, "h": h, "tile_size": TILE_SIZE, "tileset": "subspace_base"},
        "entities": entities,
        "layers": {"bg": [], "solid": solid, "fg": fg},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--density", type=float, default=0.42,
                    help="initial rock density before smoothing (0.35=open, 0.45=dense)")
    ap.add_argument("--out", default="maps/procgen.json")
    args = ap.parse_args()
    data = generate(args.size, args.seed, args.density)
    with open(args.out, "w", newline="\n") as f:
        json.dump(data, f, separators=(",", ":"))
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
