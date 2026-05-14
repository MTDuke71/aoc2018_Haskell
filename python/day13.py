"""Day 13: Mine Cart Madness -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day13.hs; this file is here so the simulation reads at full speed
without Haskell syntax getting in the way.

Run from the repo root:

    python python/day13.py

Reads inputs/day13.txt and prints both parts.

Unlike Day 12, Day 13 is mechanically interesting (asynchronous,
reading-order tick with mid-tick collisions) rather than algorithmically
interesting.  This Python version is short because the algorithm is
short -- the Haskell version is longer mostly because of the types.
"""
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day13.txt"

# Cart facing -> (dy, dx).  Reading-order natural: y grows downward.
DV = {"^": (-1, 0), "v": (1, 0), "<": (0, -1), ">": (0, 1)}

# Underlying track tile that a cart sits on at parse time.
UNDER = {"^": "|", "v": "|", "<": "-", ">": "-"}

# Reflections at curves.  '/' reflects (^<->) and (v<->), '\' reflects (^<->)
# and (v<->).  Spelled out as dicts so the rule is impossible to misread.
SLASH = {"^": ">", "v": "<", "<": "v", ">": "^"}      # '/'
BACK  = {"^": "<", "v": ">", "<": "^", ">": "v"}      # '\\'

# Intersection turn cycle: L -> S -> R -> L -> ...
NEXT_TURN = {"L": "S", "S": "R", "R": "L"}

# Apply an intersection turn to a direction.
def turn(d, t):
    if t == "S":
        return d
    if t == "L":
        return {"^": "<", "<": "v", "v": ">", ">": "^"}[d]
    # t == "R"
    return {"^": ">", ">": "v", "v": "<", "<": "^"}[d]


def parse(text):
    """Return (grid, carts).

    `grid` is a dict (y, x) -> tile char.  Carts are replaced with
    their underlying track piece (`|` or `-`).

    `carts` is a list of `[y, x, dir, turn]` records, in arbitrary
    order -- tick() re-sorts them every tick.  `dir` is one of
    `^v<>`; `turn` is one of `LSR` (next turn to take at a `+`).
    """
    grid = {}
    carts = []
    for y, row in enumerate(text.splitlines()):
        for x, c in enumerate(row):
            if c in DV:
                carts.append([y, x, c, "L"])
                grid[(y, x)] = UNDER[c]
            elif c != " ":
                grid[(y, x)] = c
    return grid, carts


def tick(grid, carts):
    """Run one tick.  Mutates `carts` in place and returns the list of
    crash positions (x, y) that occurred during this tick, in
    reading-order of the crashing mover.

    Each cart moves exactly once, in reading order based on its
    position *at the start of the tick*.  After moving, the cart
    reads its new tile and applies the turn / intersection rule.
    Collisions are detected against every other live cart -- both
    those that have already moved this tick and those that have not.
    Both colliding carts are removed (Part 2 semantics); Part 1 just
    returns on the first crash.
    """
    carts.sort(key=lambda c: (c[0], c[1]))
    occupied = {(c[0], c[1]): i for i, c in enumerate(carts)}
    alive = set(range(len(carts)))
    crashes = []
    for i in range(len(carts)):
        if i not in alive:
            continue
        c = carts[i]
        del occupied[(c[0], c[1])]
        dy, dx = DV[c[2]]
        c[0] += dy
        c[1] += dx
        tile = grid.get((c[0], c[1]), " ")
        if tile == "/":
            c[2] = SLASH[c[2]]
        elif tile == "\\":
            c[2] = BACK[c[2]]
        elif tile == "+":
            c[2] = turn(c[2], c[3])
            c[3] = NEXT_TURN[c[3]]
        if (c[0], c[1]) in occupied:
            j = occupied.pop((c[0], c[1]))
            alive.discard(i)
            alive.discard(j)
            crashes.append((c[1], c[0]))  # puzzle format: x first
        else:
            occupied[(c[0], c[1])] = i
    carts[:] = [c for i, c in enumerate(carts) if i in alive]
    return crashes


def part1(grid, carts):
    """Return 'x,y' of the first collision."""
    while True:
        cs = tick(grid, carts)
        if cs:
            x, y = cs[0]
            return f"{x},{y}"


def part2(grid, carts):
    """Return 'x,y' of the last surviving cart."""
    while len(carts) > 1:
        tick(grid, carts)
    c = carts[0]
    return f"{c[1]},{c[0]}"


def main():
    text = INPUT.read_text()
    g1, c1 = parse(text)
    g2, c2 = parse(text)
    print(f"  part 1: {part1(g1, c1)}")
    print(f"  part 2: {part2(g2, c2)}")


if __name__ == "__main__":
    main()
