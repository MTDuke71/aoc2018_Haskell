"""Day 17: Reservoir Research -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day17.hs; this file is here so the *algorithm* reads without
Haskell's ST/array plumbing in the way.

Run from the repo root:

    python python/day17.py

Reads inputs/day17.txt and prints both parts.

The simulation is a recursive flood fill (paint-bucket / scanline
fill, from graphics) on a grid:

  * water falls straight down through sand;
  * when it lands on clay or settled water it spreads sideways;
  * a row walled on BOTH sides settles (~, water at rest);
  * otherwise it streams off the open edge(s) (|, sand water passed
    through) and keeps falling.

`drop` returns True iff the cell it was asked about ended up *solid*
(clay or settled water), so the caller can decide whether its own
row can pool.

The non-obvious part: ONE recursive sweep does not converge when the
terrain has internal clay islands -- a row that should settle only
after a neighbouring pool fills is missed on the first pass.  So we
iterate to a fixed point: wipe the transient streams, re-run the
drop with the (larger) settled set from last time, and stop when no
more water comes to rest.  Settled water only grows, so this is a
monotone fixed point -- it converges (here in ~35 passes).
"""
import re
import sys
import threading
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day17.txt"


def parse(text):
    """Clay cell set, plus the (min y, max y) counting window."""
    clay = set()
    for line in text.splitlines():
        if not line.strip():
            continue
        a, b, c = map(int, re.findall(r"\d+", line))
        if line[0] == "x":
            for y in range(b, c + 1):
                clay.add((a, y))
        else:                          # line[0] == 'y'
            for x in range(b, c + 1):
                clay.add((x, a))
    ys = [y for _, y in clay]
    return clay, min(ys), max(ys)


def simulate(clay, miny, maxy):
    # grid maps (x, y) -> '#' clay | '|' flowing | '~' settled.
    grid = {p: "#" for p in clay}

    def drop(x, y):
        if y > maxy:
            return False                     # fell off the bottom
        c = grid.get((x, y), ".")
        if c == "#" or c == "~":
            return True                      # solid: supports water above
        if c == "|":
            return False                     # already a stream here
        if not drop(x, y + 1):               # resolve below first
            grid[(x, y)] = "|"
            return False
        # floor below -> spread along this row
        def scan(dx):
            cx = x
            while True:
                nx = cx + dx
                if grid.get((nx, y), ".") == "#":
                    return cx, True          # wall: bounded at cx
                cx = nx
                below = grid.get((cx, y + 1), ".")
                if below not in ("#", "~"):
                    return cx, False         # no floor: falls at cx
        lx, lw = scan(-1)
        rx, rw = scan(1)
        if lw and rw:                        # walled both sides: pool
            for xx in range(lx, rx + 1):
                grid[(xx, y)] = "~"
            return True
        for xx in range(lx, rx + 1):         # overflow: stream the row
            grid[(xx, y)] = "|"
        if not lw:
            drop(lx, y + 1)
        if not rw:
            drop(rx, y + 1)
        return False

    prev = -1
    while True:
        # wipe the transient streams; clay and settled water persist
        for k in [k for k, v in grid.items() if v == "|"]:
            del grid[k]
        drop(500, 0)
        cur = sum(1 for v in grid.values() if v == "~")
        if cur == prev:
            break
        prev = cur

    reach = sum(1 for (x, y), v in grid.items()
                if v in "|~" and miny <= y <= maxy)
    rest = sum(1 for (x, y), v in grid.items()
               if v == "~" and miny <= y <= maxy)
    return reach, rest


def main():
    clay, miny, maxy = parse(INPUT.read_text())
    # deep recursion: a tall map needs a roomy stack
    sys.setrecursionlimit(1_000_000)
    threading.stack_size(64 * 1024 * 1024)
    out = {}
    t = threading.Thread(
        target=lambda: out.update(zip(("p1", "p2"),
                                      simulate(clay, miny, maxy))))
    t.start()
    t.join()
    print(f"  part 1: {out['p1']}")
    print(f"  part 2: {out['p2']}")


if __name__ == "__main__":
    main()
