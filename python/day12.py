"""Day 12: Subterranean Sustainability -- AoC 2018.

Algorithm reference in Python. The shipping solution lives in
src/Day12.hs; this file is here so the algorithm reads at full speed
without Haskell syntax getting in the way.

Run from the repo root:

    python python/day12.py

Reads inputs/day12.txt and prints both parts.
"""
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day12.txt"
TARGET = 50_000_000_000


def parse(text):
    """Return (initial_live_set, productive_rules_set).

    `initial_live_set` is a set of pot indices that start with a plant.
    `productive_rules_set` is a set of 5-character window patterns
    whose rule fires (`=> #`). Patterns absent from this set are
    assumed to produce `.` (the puzzle input lists all 32 windows).
    """
    lines = text.splitlines()
    initial = {
        i for i, c in enumerate(lines[0][len("initial state: "):])
        if c == "#"
    }
    rules = {line[:5] for line in lines[2:] if line and line[9] == "#"}
    return initial, rules


def window(state, i):
    """The 5-cell window centred at pot i, as a string of '#' and '.'."""
    return "".join("#" if (i + d) in state else "." for d in range(-2, 3))


def step(state, rules):
    """One generation of the cellular automaton."""
    if not state:
        return set()
    lo, hi = min(state) - 2, max(state) + 2
    return {i for i in range(lo, hi + 1) if window(state, i) in rules}


def normalize(state):
    """Translate the live set so the leftmost pot is at index 0.

    Two states with the same normalised form differ only by a uniform
    translation -- which is exactly the property that lets Part 2
    extrapolate arithmetically once consecutive generations match.
    """
    if not state:
        return frozenset()
    m = min(state)
    return frozenset(i - m for i in state)


def part1(initial, rules):
    """Sum of live pot indices after 20 generations."""
    state = initial
    for _ in range(20):
        state = step(state, rules)
    return sum(state)


def part2(initial, rules):
    """Sum of live pot indices after TARGET generations.

    Simulate until the *shape* of the state repeats from one generation
    to the next (period-1 fixed point). Once it does, every subsequent
    generation translates by a constant `shift`, so the answer grows by
    `count * shift` per generation. Project arithmetically.
    """
    prev, cur = initial, step(initial, rules)
    g = 1
    while g < TARGET:
        if normalize(prev) == normalize(cur):
            count = len(cur)
            shift = min(cur) - min(prev)
            remaining = TARGET - g
            return sum(cur) + remaining * count * shift
        prev, cur = cur, step(cur, rules)
        g += 1
    return sum(cur)


def main():
    initial, rules = parse(INPUT.read_text())
    print(f"  part 1: {part1(initial, rules)}")
    print(f"  part 2: {part2(initial, rules)}")


if __name__ == "__main__":
    main()
