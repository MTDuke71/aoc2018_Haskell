"""Day 18: Settlers of the North Pole -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day18.hs; this file is here so the *algorithm* reads without
Haskell's array/newtype plumbing in the way.

Run from the repo root:

    python python/day18.py

Reads inputs/day18.txt and prints both parts.

The simulation is a two-dimensional cellular automaton (Conway's
Game of Life family, and a direct cousin of Day 12's 1-D pot rule).
Every minute all acres update simultaneously from their eight
neighbours:

  * open       -> trees       if >= 3 neighbours are trees
  * trees      -> lumberyard  if >= 3 neighbours are lumberyards
  * lumberyard -> stays       if adjacent to >= 1 lumberyard AND
                               >= 1 trees, otherwise -> open

Part 1 just steps ten times.

Part 2 wants the resource value after 1,000,000,000 minutes.  A
finite automaton on a finite grid must eventually repeat a state,
and from then on it cycles with a fixed period.  So record the
minute each state was first seen; the first repeat (state last seen
at t0, now at t) gives period = t - t0.  The target minute lands
(target - t) % period steps further on.  Same idea as Day 12, but
Day 12 collapsed to a period-1 fixed point (the shape stopped
changing); here the period is genuinely > 1, so we need the full
seen-state -> minute map, not a single previous value.
"""
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day18.txt"

DELTAS = [(dr, dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1)
          if (dr, dc) != (0, 0)]


def parse(text):
    """Grid as a list of equal-length strings, one per row."""
    return [line for line in text.splitlines() if line]


def step(grid):
    h, w = len(grid), len(grid[0])
    out = []
    for r in range(h):
        row = []
        for c in range(w):
            trees = yards = 0
            for dr, dc in DELTAS:
                nr, nc = r + dr, c + dc
                if 0 <= nr < h and 0 <= nc < w:
                    n = grid[nr][nc]
                    if n == "|":
                        trees += 1
                    elif n == "#":
                        yards += 1
            cur = grid[r][c]
            if cur == ".":
                row.append("|" if trees >= 3 else ".")
            elif cur == "|":
                row.append("#" if yards >= 3 else "|")
            else:                                  # cur == '#'
                row.append("#" if yards >= 1 and trees >= 1 else ".")
        out.append("".join(row))
    return out


def resource_value(grid):
    flat = "".join(grid)
    return flat.count("|") * flat.count("#")


def part1(grid):
    for _ in range(10):
        grid = step(grid)
    return resource_value(grid)


def part2(grid, target=1_000_000_000):
    seen = {}
    t = 0
    while t < target:
        key = "\n".join(grid)
        if key in seen:                            # cycle found
            period = t - seen[key]
            remaining = (target - t) % period
            for _ in range(remaining):
                grid = step(grid)
            return resource_value(grid)
        seen[key] = t
        grid = step(grid)
        t += 1
    return resource_value(grid)


def main():
    grid = parse(INPUT.read_text())
    print(f"  part 1: {part1(grid)}")
    print(f"  part 2: {part2(grid)}")


if __name__ == "__main__":
    main()
