"""Day 25: Four-Dimensional Adventure -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day25.hs; this file is here so the union-find reads without
Haskell's STUArray plumbing in the way.

The input is a list of 4-D points.  Two points are in the same
"constellation" if their Manhattan distance is at most 3, transitively
-- so constellations are the connected components of the graph that
joins every pair of points within distance 3.

  * Part 1: how many constellations are there.
  * Part 2: none -- Day 25's second star is free once the other 49 are
    collected.

The components are found with union-find (disjoint-set union): every
point starts in its own set, each close-enough pair is merged, and the
answer is the number of distinct roots left.

Run from the repo root:

    python python/day25.py

Reads inputs/day25.txt and prints the constellation count.
"""
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day25.txt"


def parse(text):
    return [tuple(int(c) for c in line.split(","))
            for line in text.split() if line.strip()]


def manhattan(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def count_constellations(points):
    n = len(points)
    parent = list(range(n))          # parent[i] = i: each point its own set
    rank = [0] * n

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]   # path halving
            x = parent[x]
        return x

    def union(x, y):
        rx, ry = find(x), find(y)
        if rx == ry:
            return
        if rank[rx] < rank[ry]:
            rx, ry = ry, rx
        parent[ry] = rx
        if rank[rx] == rank[ry]:
            rank[rx] += 1

    for i in range(n):
        for j in range(i + 1, n):
            if manhattan(points[i], points[j]) <= 3:
                union(i, j)

    return sum(1 for i in range(n) if find(i) == i)


def main():
    points = parse(INPUT.read_text())
    print("part 1:", count_constellations(points))
    print("part 2: (free star -- Merry Christmas!)")


if __name__ == "__main__":
    main()
