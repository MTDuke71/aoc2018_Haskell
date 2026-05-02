"""Verify the 'skip the cycles' optimization for AoC 2018 Day 1 Part 2.

Implements two solvers:

* `part2_naive`  — the lazy / set-based walk used by the Haskell main code.
                   Walks the cycled delta stream until the first frequency
                   repeats. O(k log k) where k is the number of frequencies
                   visited (~133,165 for our input).
* `part2_fast`   — the bucket-by-mod-drift algorithm described in the Day 1
                   function guide. Buckets the 986 within-cycle partial sums
                   by `p_j mod drift` (drift = sum of deltas = Part 1's
                   answer), sorts each bucket by partial-sum value, and finds
                   the adjacent pair whose induced second-visit step is
                   smallest. O(n log n) on n = 986.

The script runs both, asserts they agree, and prints timings.

Usage (from the project root):

    python scripts/part2_fast.py
"""

from __future__ import annotations

from itertools import accumulate, cycle as itertools_cycle
from pathlib import Path
from time import perf_counter


def load_deltas(path: Path) -> list[int]:
    return [int(s.lstrip('+')) for s in path.read_text().split() if s]


def part2_naive(deltas: list[int]) -> tuple[int, int]:
    """Return (first_repeated_freq, step_at_which_it_repeats)."""
    seen: set[int] = {0}
    freq = 0
    step = 0
    for d in itertools_cycle(deltas):
        step += 1
        freq += d
        if freq in seen:
            return freq, step
        seen.add(freq)
    raise RuntimeError("unreachable: cycle is infinite")


def part2_fast(deltas: list[int]) -> tuple[int, int]:
    """Return (first_repeated_freq, step_at_which_it_repeats).

    Algorithm: see Day 1 function guide, section "Possible optimization —
    skipping the 134 cycles".
    """
    drift = sum(deltas)
    cycle_len = len(deltas)
    if drift == 0:
        raise ValueError("zero drift: any partial sum that recurs in cycle 1 is the answer; "
                         "this case is not handled here")

    # Partial sums p_0..p_(n-1) of length cycle_len; p_j is the freq at
    # position j in cycle 1. p_n itself equals drift, which is the same
    # as p_0 of cycle 2 — exclude it to avoid a spurious match.
    partials = list(accumulate(deltas, initial=0))[:cycle_len]

    # Bucket each (partial_sum, position) by partial_sum % drift.
    buckets: dict[int, list[tuple[int, int]]] = {}
    for j, p in enumerate(partials):
        buckets.setdefault(p % drift, []).append((p, j))

    best_step: int | None = None
    best_freq: int | None = None

    for items in buckets.values():
        if len(items) < 2:
            continue
        items.sort()  # sort by (p, j); equal p means a within-cycle repeat
        for i in range(len(items) - 1):
            p_a, j_a = items[i]
            p_b, _   = items[i + 1]
            if p_a == p_b:
                # Two positions inside cycle 1 already share a frequency —
                # the answer would be that frequency at the *later* position.
                # The lazy solver would catch this in cycle 1; AoC inputs
                # are constructed so it doesn't happen, but we handle it
                # for completeness.
                _, j_b_eq = items[i + 1]
                cand_step = max(j_a, j_b_eq)
                cand_freq = p_a
            else:
                cycle_gap = (p_b - p_a) // drift
                cand_step = cycle_gap * cycle_len + j_a
                cand_freq = p_b
            if best_step is None or cand_step < best_step:
                best_step = cand_step
                best_freq = cand_freq

    assert best_step is not None and best_freq is not None
    return best_freq, best_step


def main() -> None:
    project_root = Path(__file__).resolve().parent.parent
    deltas = load_deltas(project_root / 'inputs' / 'day01.txt')

    print(f'cycle length:   {len(deltas)} deltas')
    print(f'drift (Part 1): {sum(deltas)}')
    print()

    t0 = perf_counter()
    freq_naive, step_naive = part2_naive(deltas)
    t_naive = perf_counter() - t0

    t0 = perf_counter()
    freq_fast, step_fast = part2_fast(deltas)
    t_fast = perf_counter() - t0

    print(f'naive : freq = {freq_naive:>6}, step = {step_naive:>7,}, '
          f'time = {t_naive * 1000:7.2f} ms')
    print(f'fast  : freq = {freq_fast:>6}, step = {step_fast:>7,}, '
          f'time = {t_fast * 1000:7.2f} ms')
    print()

    assert freq_naive == freq_fast, f'freq mismatch: {freq_naive} vs {freq_fast}'
    assert step_naive == step_fast, f'step mismatch: {step_naive} vs {step_fast}'
    print(f'both solvers agree: freq = {freq_fast}, step = {step_fast:,}')
    if t_fast > 0:
        print(f'speedup: {t_naive / t_fast:.1f}×')


if __name__ == '__main__':
    main()
