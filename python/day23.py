"""Day 23: Experimental Emergency Teleportation -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day23.hs; this file is here so the *algorithm* reads without
Haskell's Set-as-priority-queue plumbing in the way.

The input is a swarm of nanobots, each an (x, y, z) position and a
signal radius r.  A bot is "in range" of any integer point within
Manhattan distance r of it -- so each bot's coverage is an octahedron
(a taxicab ball).

  * Part 1: the bot with the largest radius; how many bots (itself
    included) lie within its range.  One linear scan.

  * Part 2: the integer point in range of the *most* bots; among ties,
    the one closest to the origin; report that Manhattan distance.

Part 2 is the calendar's hardest search -- the answer can be anywhere
in a ~10^8-wide cube, far too large to scan.  The trick is branch and
bound over an *octree*:

  * Bound every bot inside one big power-of-two cube.
  * For a cube, count how many bots' ranges *touch* it.  No point
    inside can be seen by more bots than that, so the count is an
    admissible upper bound.
  * Keep cubes in a priority queue ordered (most bots, then closest to
    origin, then smallest).  Pop the best, split it into 8 octants,
    push them back.  Because the bound only shrinks and the origin
    distance only grows as cubes get smaller, the first 1x1x1 cube
    pulled from the queue is provably the optimal point.

Run from the repo root:

    python python/day23.py

Reads inputs/day23.txt and prints both parts.
"""
import heapq
import re
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day23.txt"

NUM = re.compile(r"-?\d+")


def parse(text):
    """Each line -> ((x, y, z), r).  Pull the four integers out."""
    bots = []
    for line in text.strip().splitlines():
        x, y, z, r = map(int, NUM.findall(line))
        bots.append(((x, y, z), r))
    return bots


def manhattan(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


# ---------------------------------------------------------------------------
# Part 1
# ---------------------------------------------------------------------------

def part1(bots):
    pos, r = max(bots, key=lambda b: b[1])          # strongest = largest radius
    return sum(1 for p, _ in bots if manhattan(pos, p) <= r)


# ---------------------------------------------------------------------------
# Part 2: branch and bound over an octree
# ---------------------------------------------------------------------------

def dist_point_box(p, lo, size):
    """Manhattan distance from point p to the nearest cell of the cube
    [lo .. lo+size-1]^3.  Per axis: how far p lies outside the range."""
    total = 0
    for v, l in zip(p, lo):
        h = l + size - 1
        if v < l:
            total += l - v
        elif v > h:
            total += v - h
    return total


def dist_box_origin(lo, size):
    """Manhattan distance from the origin to the nearest cell of the cube."""
    total = 0
    for l in lo:
        h = l + size - 1
        if l > 0:
            total += l
        elif h < 0:
            total += -h
    return total


def part2(bots):
    xs = [p[0] for p, _ in bots]
    ys = [p[1] for p, _ in bots]
    zs = [p[2] for p, _ in bots]
    lo = (min(xs), min(ys), min(zs))
    extent = max(max(xs) - lo[0], max(ys) - lo[1], max(zs) - lo[2])
    size = 1
    while size <= extent:
        size *= 2                                    # smallest power of two > extent

    def count(lo, size):
        return sum(1 for p, r in bots if dist_point_box(p, lo, size) <= r)

    # Heap key: (-count, dist_to_origin, size, lo).  Python's tuple order
    # makes this "most bots, then closest, then smallest cube" first.
    heap = [(-count(lo, size), dist_box_origin(lo, size), size, lo)]
    while heap:
        neg_c, d, size, lo = heapq.heappop(heap)
        if size == 1:
            return d                                 # first 1x1x1 popped is optimal
        h = size // 2
        for dx in (0, h):
            for dy in (0, h):
                for dz in (0, h):
                    nlo = (lo[0] + dx, lo[1] + dy, lo[2] + dz)
                    heapq.heappush(
                        heap,
                        (-count(nlo, h), dist_box_origin(nlo, h), h, nlo),
                    )
    raise RuntimeError("queue emptied without reaching a 1x1x1 cube")


def main():
    bots = parse(INPUT.read_text())
    print("part 1:", part1(bots))
    print("part 2:", part2(bots))


if __name__ == "__main__":
    main()
