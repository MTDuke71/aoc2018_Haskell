"""Day 20: A Regular Map -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day20.hs; this file is here so the *algorithm* reads without
Haskell's NFData / Sequence / Map plumbing in the way.

The input is one long regex of N/S/E/W direction characters with
branches `(a|b|...)`.  Every step the regex takes is a door between
two adjacent rooms; the goal is to assemble the resulting door graph
and BFS it.

  * Part 1: the largest shortest-path distance from the origin.
  * Part 2: how many rooms have a shortest-path distance >= 1000.

We never parse the regex into a tree.  A single left-to-right walk
with a stack of "saved positions" (one per open paren) is enough:

    '(' : push the current position.
    '|' : reset position to the top of the stack -- next branch
          starts where this group started.
    ')' : pop -- after the group, continue from where it started.

This is correct because AoC 2018's regexes are built so that every
branch returns to its starting position (either a "(NEWS|)"-style
detour with an empty alternative, or all branches end at the same
room).  Under that assumption we never need to carry a *set* of
possible current positions.

Run from the repo root:

    python python/day20.py

Reads inputs/day20.txt and prints both parts.
"""
from collections import deque
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day20.txt"


# ---------------------------------------------------------------------------
# Build the door graph
# ---------------------------------------------------------------------------

STEP = {
    "N": (0, -1),
    "S": (0, +1),
    "W": (-1, 0),
    "E": (+1, 0),
}


def build_doors(regex):
    """Return adjacency dict {room: set(neighbours)} from the regex."""
    pos = (0, 0)
    stack = []
    adj = {pos: set()}

    for c in regex:
        if c in "^$":
            continue
        elif c == "(":
            stack.append(pos)
        elif c == "|":
            pos = stack[-1]
        elif c == ")":
            pos = stack.pop()
        else:                              # N / S / E / W
            dx, dy = STEP[c]
            nxt = (pos[0] + dx, pos[1] + dy)
            adj.setdefault(pos, set()).add(nxt)
            adj.setdefault(nxt, set()).add(pos)
            pos = nxt
    return adj


# ---------------------------------------------------------------------------
# BFS
# ---------------------------------------------------------------------------

def distances(adj, start=(0, 0)):
    """Shortest-path distance from `start` to every reachable room."""
    dist = {start: 0}
    q = deque([start])
    while q:
        p = q.popleft()
        d = dist[p]
        for n in adj.get(p, ()):
            if n not in dist:
                dist[n] = d + 1
                q.append(n)
    return dist


# ---------------------------------------------------------------------------

def part1(regex):
    return max(distances(build_doors(regex)).values())


def part2(regex):
    return sum(1 for v in distances(build_doors(regex)).values() if v >= 1000)


def main():
    regex = INPUT.read_text().strip()
    print(f"  part 1: {part1(regex)}")
    print(f"  part 2: {part2(regex)}")


if __name__ == "__main__":
    main()
