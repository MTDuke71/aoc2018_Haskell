"""Day 22: Mode Maze -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day22.hs; this file is here so the *algorithm* reads without
Haskell's lazy-array knot-tying in the way.

The input is just two numbers: the cave depth and the target
coordinates.  The map is *computed*, not given -- each region's
"erosion level" depends on the erosion levels of the regions to its
left and above (a two-neighbour DP recurrence), and erosion mod 3
gives the region type: 0 rocky, 1 wet, 2 narrow.

  * Part 1: sum of region types over the (0,0)..target rectangle.
  * Part 2: fewest minutes from (0,0) holding the torch to the
    target holding the torch.  Moving costs 1 minute, switching
    tools costs 7, and each region type forbids one of the three
    tools.

Part 2 is Dijkstra's algorithm over a *layered* graph: the nodes are
not grid cells but (cell, tool) pairs.  Tools are encoded 0 neither,
1 torch, 2 climbing gear -- chosen so that tool t is forbidden
exactly in region type t, making "tool valid here" a single
comparison (tool != region_type).

Where the Haskell version uses a lazy self-referential array (demand
a cell and its dependencies compute themselves), Python has no lazy
arrays, so the erosion table is filled in explicitly, row by row, in
dependency order.  Same DP, scheduled by hand instead of by the
runtime.

Run from the repo root:

    python python/day22.py

Reads inputs/day22.txt and prints both parts.
"""
import heapq
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day22.txt"

ROCKY, WET, NARROW = 0, 1, 2
NEITHER, TORCH, GEAR = 0, 1, 2

MODULUS = 20183


def parse(text):
    depth_line, target_line = text.strip().splitlines()
    depth = int(depth_line.split(":")[1])
    tx, ty = map(int, target_line.split(":")[1].split(","))
    return depth, (tx, ty)


# ---------------------------------------------------------------------------
# The erosion table (explicit DP fill)
# ---------------------------------------------------------------------------

def erosion_table(depth, target, mx, my):
    """Erosion level for every cell in (0,0)..(mx,my).

    Filled in row-major order so the (x-1, y) and (x, y-1) cells a
    geologic index needs are always already computed.
    """
    tx, ty = target
    erosion = {}
    for y in range(my + 1):
        for x in range(mx + 1):
            if (x, y) in ((0, 0), (tx, ty)):
                geo = 0
            elif y == 0:
                geo = x * 16807
            elif x == 0:
                geo = y * 48271
            else:
                geo = erosion[x - 1, y] * erosion[x, y - 1]
            erosion[x, y] = (geo + depth) % MODULUS
    return erosion


def part1(depth, target):
    tx, ty = target
    erosion = erosion_table(depth, target, tx, ty)
    return sum(level % 3 for level in erosion.values())


# ---------------------------------------------------------------------------
# Part 2: Dijkstra over (position, tool)
# ---------------------------------------------------------------------------

def part2(depth, target, pad=100):
    """Fewest minutes from ((0,0), TORCH) to (target, TORCH).

    Classic Dijkstra with a binary heap and lazy deletion: states
    may enter the heap several times with different distances; only
    the first (smallest) pop counts.  The first time the goal is
    popped, its distance is final.

    The cave is unbounded right and down, so the erosion table is
    computed on a rectangle padded past the target and the pad edge
    acts as a wall.  Every column or row of excursion past the
    target costs 2 minutes there-and-back, so optimal paths stray
    only a bounded distance; pad=100 is far beyond it.
    """
    tx, ty = target
    mx, my = tx + pad, ty + pad
    erosion = erosion_table(depth, target, mx, my)
    region = {pos: level % 3 for pos, level in erosion.items()}

    start = ((0, 0), TORCH)
    goal = ((tx, ty), TORCH)

    heap = [(0, start)]
    settled = set()
    while heap:
        dist, state = heapq.heappop(heap)
        if state == goal:
            return dist
        if state in settled:
            continue
        settled.add(state)
        (x, y), tool = state

        # Switch to the other tool valid in this region: 7 minutes.
        for other in (NEITHER, TORCH, GEAR):
            if other != tool and other != region[x, y]:
                heapq.heappush(heap, (dist + 7, ((x, y), other)))

        # Step to a neighbour the current tool allows: 1 minute.
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx <= mx and 0 <= ny <= my and tool != region[nx, ny]:
                heapq.heappush(heap, (dist + 1, ((nx, ny), tool)))

    raise RuntimeError("goal unreachable (pad too small?)")


def main():
    depth, target = parse(INPUT.read_text())
    print("part 1:", part1(depth, target))
    print("part 2:", part2(depth, target))


if __name__ == "__main__":
    main()
