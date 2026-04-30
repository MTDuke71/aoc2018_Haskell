# Advent of Code 2018 — Haskell Solutions Summary

**Status**: IN PROGRESS (1/26, including the Day 0 warm-up)
**Project**: [aoc2018.cabal](../../aoc2018.cabal) — single cabal package, library modules `Day00..Day25` in [src/](../../src/), dispatcher [app/Main.hs](../../app/Main.hs), tests in [test/](../../test/), benches in [bench/](../../bench/).

**Run a day**: `cabal run aoc2018-solve -- <n>` (reads `inputs/day<nn>.txt`).
**Run all tests**: `cabal test`.
**Run all benchmarks**: `cabal bench` (one day: `cabal bench -- --match prefix day00`; HTML report: `cabal bench -- --output bench.html`).

---

## Stats Dashboard

| Metric | Value |
|--------|-------|
| **Progress** | 1/26 (Day 0 warm-up done; Days 1–25 pending) |
| **Total Runtime** | 43.6 µs (Day 0 only so far) |
| **Average per Day** | 43.6 µs |

---

## Performance Table

Reported on a Windows 11 / GHC 9.6.7 / `-O2` build via `cabal bench` (criterion). Each row's **Parse**, **Part 1**, and **Part 2** columns are criterion's `mean` for the corresponding bench. **Total = Parse + Part 1 + Part 2** — the steady-state CPU cost of one solve.

| Day | Title | Parse | Part 1 | Part 2 | Total | Algorithm | Notes |
|----:|-------|------:|-------:|-------:|------:|-----------|-------|
| [00](day00_function_guide.md) | Inverse Captcha (warm-up, AoC 2017 Day 1) | 17.5 µs | 11.2 µs | 14.9 µs | 43.6 µs | Modular circular comparison | `zip ds (rotate k ds)` substitutes for indexed access; offset = 1 (P1) and n/2 (P2). |
|  1 | *not yet attempted* | — | — | — | — | — | — |
|  2 | *not yet attempted* | — | — | — | — | — | — |
|  3 | *not yet attempted* | — | — | — | — | — | — |
|  4 | *not yet attempted* | — | — | — | — | — | — |
|  5 | *not yet attempted* | — | — | — | — | — | — |
|  6 | *not yet attempted* | — | — | — | — | — | — |
|  7 | *not yet attempted* | — | — | — | — | — | — |
|  8 | *not yet attempted* | — | — | — | — | — | — |
|  9 | *not yet attempted* | — | — | — | — | — | — |
| 10 | *not yet attempted* | — | — | — | — | — | — |
| 11 | *not yet attempted* | — | — | — | — | — | — |
| 12 | *not yet attempted* | — | — | — | — | — | — |
| 13 | *not yet attempted* | — | — | — | — | — | — |
| 14 | *not yet attempted* | — | — | — | — | — | — |
| 15 | *not yet attempted* | — | — | — | — | — | — |
| 16 | *not yet attempted* | — | — | — | — | — | — |
| 17 | *not yet attempted* | — | — | — | — | — | — |
| 18 | *not yet attempted* | — | — | — | — | — | — |
| 19 | *not yet attempted* | — | — | — | — | — | — |
| 20 | *not yet attempted* | — | — | — | — | — | — |
| 21 | *not yet attempted* | — | — | — | — | — | — |
| 22 | *not yet attempted* | — | — | — | — | — | — |
| 23 | *not yet attempted* | — | — | — | — | — | — |
| 24 | *not yet attempted* | — | — | — | — | — | — |
| 25 | *not yet attempted* | — | — | — | — | — | — |

---

## Answers

| Day | Title | Part 1 | Part 2 |
|----:|-------|-------:|-------:|
| [00](day00_function_guide.md) | Inverse Captcha | **1171** | **1024** |

(Filled in as days are solved; pending days omitted from this table.)

---

## How to read these numbers

Criterion reports a few statistics per benchmark:

```
benchmarking day00/combined
time                 80.04 μs   (79.62 μs .. 80.50 μs)
                     1.000 R²   (1.000 R² .. 1.000 R²)
mean                 80.46 μs   (80.09 μs .. 81.19 μs)
std dev              1.708 μs   (965.0 ns .. 3.039 μs)
```

- **time** is the OLS-regression slope — *"how many extra nanoseconds does each iteration cost on average"*. This is the most reliable headline figure.
- **R²** is the regression's goodness of fit. Anything above 0.99 means iteration count and total time scale linearly; the timing is trustworthy.
- **mean / std dev** describe the per-iteration distribution. Compare std dev to mean: roughly 2 % here (1.7 µs / 80 µs), so the result is stable.
- **variance introduced by outliers** is criterion's editorial. *"Severely inflated"* means GC or scheduling noise dominates; usually the first run during warm-up. Re-running often shrinks the figure.

The numbers in the **Performance Table** above use the **mean** column from each individual bench (`parseInput`, `part1`, `part2`), rounded to one decimal place in microseconds. **Total** is their arithmetic sum — the steady-state CPU cost of one parse + both parts. If a day is unusually noisy, its row picks the median across three back-to-back runs and notes that in the **Notes** column.

### Per-bench shape

Each day registers four benches:

| Bench         | What it times                                                  | Reported as                                            |
|---------------|----------------------------------------------------------------|--------------------------------------------------------|
| `parseInput`  | Just the parser, on the raw `String`.                          | **Parse** column.                                      |
| `part1`       | Just Part 1, on the **already-parsed** input (`env`-cached).   | **Part 1** column.                                     |
| `part2`       | Just Part 2, same.                                             | **Part 2** column.                                     |
| `combined`    | `\r -> let p = parseInput r in (part1 p, part2 p)` on raw text. | Not reported; available for cross-checking. See below. |

**Why Total = Parse + Part 1 + Part 2 (sum) rather than the `combined` bench**: `combined` builds a fresh parsed list every iteration and pays GC for it, so its mean runs noticeably higher than the sum of the parts (the cached parts amortise allocation across all criterion iterations). For Day 0, summed Total is 43.6 µs but `combined` reports ~80 µs. The summed figure is the steady-state CPU cost of the work itself; the `combined` figure is microbenchmark allocation noise on top. Report the steady-state number; keep `combined` available as a sanity check.

---

## Updating this file when a day is solved

1. **Bench it**: add a row to [bench/Main.hs](../../bench/Main.hs) (one line — the `dayBench` helper takes care of everything else), then `cabal bench -- --match prefix dayNN`.
2. **Performance Table**: replace the *not yet attempted* row with the day's title (linked to its function guide), the **Parse / Part 1 / Part 2** means from criterion, **Total = sum of the three**, the algorithm name, and a one-line note.
3. **Answers table**: append a row with Part 1 and Part 2.
4. **Stats Dashboard**: bump `Progress`, recompute `Total Runtime` (sum of every solved day's Total) and `Average per Day`.
5. Commit. Use the Day 0 row as a template — same column widths, same em-dash handling.

Detail belongs in the per-day function guide; this file stays scannable.
