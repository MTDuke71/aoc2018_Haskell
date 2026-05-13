"""Day 12 spaceship-emergence trace.

Walks the CA generation by generation, printing the normalised live
pattern, the leftmost pot's position, the shift from the previous
generation, the count of live pots, and the sum -- up to the point
where the cycle locks in.

Useful for *seeing* the spaceship form out of the chaotic transient
phase, and for watching the extrapolation arithmetic materialise.

Run from the repo root:

    python python/day12_trace.py
"""
from day12 import INPUT, TARGET, parse, step


def normalize_to_pattern(state):
    """Render a state as (min, pattern_string) where pattern_string is the
    normalised shape: '#' / '.' starting at the leftmost live pot."""
    if not state:
        return 0, ""
    m = min(state)
    width = max(state) - m + 1
    return m, "".join("#" if (m + i) in state else "." for i in range(width))


def print_rules(rules):
    """Print all productive rules with annotations, then a speed-limit analysis."""
    print("PRODUCTIVE RULES (rules whose RHS is '#')")
    print("=" * 100)
    print(f"  {len(rules)} of 32 possible 5-cell windows produce a live pot;")
    print(f"  the other {32 - len(rules)} produce '.' and are absent from the rule set.")
    print()
    print("  pattern  live  cell positions in window (-2..+2 relative to centre)")
    print("  -------  ----  ----------------------------------------------------")
    for pat in sorted(rules):
        positions = [i - 2 for i, c in enumerate(pat) if c == "#"]
        live = len(positions)
        pos_str = ", ".join(f"{p:+d}" for p in positions)
        print(f"  {pat}     {live}    {pos_str}")
    print()
    print("SPEED-LIMIT ANALYSIS")
    print("=" * 100)
    print("  The window covers cells [i-2 .. i+2], so information can propagate at")
    print("  most 2 cells per generation. Theoretical max |shift| per step = 2.")
    print()
    print("  For shift = +2 to be possible (new leftmost jumps 2 to the right):")
    print("    The pot at position m+2 must become alive, where m was the old")
    print("    leftmost. Its window is [m, m+1, m+2, m+3, m+4] -- starting with '#'")
    print("    (since m is alive). So a productive rule of form #xxxx must exist.")
    print()
    print("  For shift = -2 to be possible (new leftmost jumps 2 to the left):")
    print("    The pot at position m-2 must become alive, with window")
    print("    [m-4, m-3, m-2, m-1, m] -- ending with '#'. So a productive rule")
    print("    of form xxxx# must exist.")
    print()
    starts_hash = sorted(p for p in rules if p[0] == "#")
    ends_hash = sorted(p for p in rules if p[4] == "#")
    print(f"  Productive rules of form #xxxx (could enable +2 shift): "
          f"{len(starts_hash)}")
    for p in starts_hash:
        print(f"    {p}")
    print()
    print(f"  Productive rules of form xxxx# (could enable -2 shift): "
          f"{len(ends_hash)}")
    for p in ends_hash:
        print(f"    {p}")
    print()
    if not starts_hash:
        print("  >>> No productive rule starts with '#'. "
              "Shift = +2 is IMPOSSIBLE on any state.")
    if not ends_hash:
        print("  >>> No productive rule ends with '#'. "
              "Shift = -2 is IMPOSSIBLE on any state.")
    if starts_hash and ends_hash:
        print("  >>> Both directions have eligible rules; whether +2/-2 actually")
        print("      occurs depends on whether the simulation ever lands in a state")
        print("      that matches one of them with the surrounding dies-off rules.")
    print()


def main():
    initial, rules = parse(INPUT.read_text())

    print("Day 12 spaceship-emergence trace")
    print("=" * 100)
    print(f"Initial state: count={len(initial)}, sum={sum(initial)}, "
          f"min={min(initial)}, max={max(initial)}")
    print()

    print_rules(rules)
    print(f"{'gen':>4} | {'min':>4} | {'shift':>5} | "
          f"{'count':>5} | {'sum':>10} | normalized pattern")
    print("-" * 100)

    state = initial
    prev_min = None
    prev_pattern = None
    gen = 0
    cap = 10_000  # safety cap; never triggers on real input

    while gen < cap:
        if not state:
            print(f"\nState went extinct at generation {gen}.")
            return

        cur_min, pattern = normalize_to_pattern(state)
        count = len(state)
        cur_sum = sum(state)

        if prev_min is None:
            shift_str = "  -  "
            cycle = False
        else:
            shift_val = cur_min - prev_min
            shift_str = f"{shift_val:>+5d}"
            cycle = (pattern == prev_pattern)

        # If the pattern is huge (early generations), truncate the display.
        display = pattern if len(pattern) <= 80 else pattern[:77] + "..."

        marker = ""
        if cycle:
            marker = f"  <-- SHAPE MATCHES GEN {gen - 1}"

        print(f"{gen:>4} | {cur_min:>4} | {shift_str} | "
              f"{count:>5} | {cur_sum:>10} | {display}{marker}")

        if cycle:
            real_shift = cur_min - prev_min
            remaining = TARGET - gen
            increment = count * real_shift
            answer = cur_sum + remaining * increment

            print()
            print("=" * 100)
            print(f"Cycle detected at generation {gen}.")
            print(f"  period               = 1 (consecutive generations have the same shape)")
            print(f"  shift per generation = {real_shift} pot(s) to the {'right' if real_shift > 0 else 'left'}")
            print(f"  count of live pots   = {count}")
            print(f"  current sum          = {cur_sum}")
            print()
            print(f"  Per-generation sum increment: count * shift = "
                  f"{count} * {real_shift} = {increment}")
            print()
            print(f"Extrapolation to generation {TARGET:,}:")
            print(f"  sum(target) = current_sum + remaining * count * shift")
            print(f"              = {cur_sum} + ({TARGET:,} - {gen}) * {count} * {real_shift}")
            print(f"              = {cur_sum} + {remaining:,} * {increment}")
            print(f"              = {cur_sum} + {remaining * increment:,}")
            print(f"              = {answer:,}")
            print()
            print(f"Part 2 answer: {answer}")
            return

        prev_min = cur_min
        prev_pattern = pattern
        state = step(state, rules)
        gen += 1

    print(f"\nNo cycle found within {cap} generations -- this input may be "
          "atypical.")


if __name__ == "__main__":
    main()
