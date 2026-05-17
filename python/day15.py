"""Day 15: Beverage Bandits -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day15.hs; this file is here so the *algorithm* -- which is the
whole point of this puzzle -- reads without Haskell's types in the
way.

Run from the repo root:

    python python/day15.py

Reads inputs/day15.txt and prints both parts.

Day 15 is the canonical "implement the spec exactly, the spec is
fiddly" puzzle.  Nothing here is algorithmically deep -- it is a
plain breadth-first shortest path on a small grid.  All the
difficulty is in the *tie-breaking*, and every tie is broken the same
way: "first in reading order", i.e. smallest (y, x).  We lean on that
relentlessly -- positions are (y, x) tuples, and "first in reading
order" is just min() of tuples.

The one non-obvious trick is the *two BFS per move*:

  1. BFS from the unit -> distance to every reachable empty cell.
     The destination is the in-range square with the smallest
     (distance, y, x).
  2. BFS from that destination -> the unit steps onto its own
     neighbour with the smallest (distance-to-destination, y, x).

One BFS finds the goal; the second resolves *which first step* lies
on a shortest path to it, with reading order breaking ties.
"""
from collections import deque
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day15.txt"


def parse(text):
    """Return (walls, units).

    `walls` is a set of (y, x) that block movement.  `units` is a
    list of [y, x, kind, hp] records; kind is 'E' or 'G'.  Units are
    appended in row-major order, which is reading order.
    """
    walls = set()
    units = []
    for y, row in enumerate(text.splitlines()):
        for x, c in enumerate(row):
            if c == "#":
                walls.add((y, x))
            elif c in "EG":
                units.append([y, x, c, 200])
    return walls, units


# Orthogonal neighbours, pre-sorted into reading order: up, left,
# right, down.  Returning them sorted means "first reachable" and
# "min over neighbours" never need an extra sort.
def adj(y, x):
    return [(y - 1, x), (y, x - 1), (y, x + 1), (y + 1, x)]


def bfs(walls, occupied, start):
    """Distance from `start` to every reachable empty cell.

    A cell is traversable if it is not a wall and not currently
    occupied by a unit.  `start` is seeded at 0 and is exempt from
    the occupied test (the moving unit stands there).
    """
    dist = {start: 0}
    q = deque([start])
    while q:
        cy, cx = q.popleft()
        for ny, nx in adj(cy, cx):
            if (ny, nx) in dist:
                continue
            if (ny, nx) in walls or (ny, nx) in occupied:
                continue
            dist[(ny, nx)] = dist[(cy, cx)] + 1
            q.append((ny, nx))
    return dist


def turn(walls, units, idx, elf_ap):
    """Resolve unit `units[idx]`'s whole turn.

    Returns False if the unit found no targets (combat is over),
    otherwise True.  Mutates `units` in place: a move rewrites the
    unit's position; a kill sets the victim's hp <= 0 (the caller
    prunes the dead between rounds and skips them within a round).
    """
    me = units[idx]
    my = me[2]
    enemies = [u for u in units if u[3] > 0 and u[2] != my]
    if not enemies:
        return False  # no targets remain -> combat ends

    occupied = {(u[0], u[1]) for u in units if u[3] > 0}

    def adjacent_enemy():
        # The living enemy adjacent to `me` with the fewest hp;
        # reading order (its position) breaks ties.
        best = None
        for ny, nx in adj(me[0], me[1]):
            for u in units:
                if u[3] > 0 and u[2] != my and (u[0], u[1]) == (ny, nx):
                    key = (u[3], u[0], u[1])
                    if best is None or key < best[0]:
                        best = (key, u)
        return None if best is None else best[1]

    # --- move phase -------------------------------------------------
    if adjacent_enemy() is None:
        # Open squares in range of (adjacent to) some enemy.
        in_range = set()
        for e in enemies:
            for ny, nx in adj(e[0], e[1]):
                if (ny, nx) not in walls and (ny, nx) not in occupied:
                    in_range.add((ny, nx))

        dist_from_me = bfs(walls, occupied, (me[0], me[1]))
        reachable = [
            (d, p) for p in in_range
            for d in [dist_from_me.get(p)] if d is not None
        ]
        if reachable:
            # Nearest, ties by reading order of the square itself.
            _, chosen = min(reachable)
            dist_from_goal = bfs(walls, occupied, chosen)
            # Step onto the neighbour on a shortest path to `chosen`;
            # ties by reading order of the step square.
            step = min(
                (dist_from_goal[p], p)
                for p in adj(me[0], me[1])
                if p not in walls
                and p not in occupied
                and p in dist_from_goal
            )[1]
            me[0], me[1] = step

    # --- attack phase ----------------------------------------------
    victim = adjacent_enemy()
    if victim is not None:
        power = elf_ap if my == "E" else 3
        victim[3] -= power
    return True


def run(walls, units, elf_ap):
    """Simulate to completion.  Returns (full_rounds, sum_hp, elf_deaths)."""
    units = [u[:] for u in units]  # don't mutate the caller's copy
    elves0 = sum(1 for u in units if u[2] == "E")
    rounds = 0
    while True:
        # Turn order: reading order of positions at round start.
        order = sorted(range(len(units)), key=lambda i: (units[i][0], units[i][1]))
        for i in order:
            if units[i][3] <= 0:
                continue  # died earlier this round
            if not turn(walls, units, i, elf_ap):
                # Combat ended mid-round: this round does NOT count.
                alive_hp = sum(u[3] for u in units if u[3] > 0)
                elves = sum(1 for u in units if u[2] == "E" and u[3] > 0)
                return rounds, alive_hp, elves0 - elves
        units = [u for u in units if u[3] > 0]  # prune the dead
        rounds += 1


def part1(walls, units):
    r, hp, _ = run(walls, units, 3)
    return r * hp


def part2(walls, units):
    # Lowest Elf attack power with zero Elf deaths (search from 4 --
    # 3 is the Part 1 baseline).  Could early-abort the instant an
    # Elf dies; the Haskell version does, this reference keeps it
    # simple and just re-runs each full battle.
    ap = 4
    while True:
        r, hp, elf_deaths = run(walls, units, ap)
        if elf_deaths == 0:
            return r * hp
        ap += 1


def main():
    text = INPUT.read_text()
    walls, units = parse(text)
    print(f"  part 1: {part1(walls, units)}")
    print(f"  part 2: {part2(walls, units)}")


if __name__ == "__main__":
    main()
