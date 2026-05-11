# Advent of Code 2018 — Haskell Solutions Summary

**Status**: IN PROGRESS (10/26, including the Day 0 warm-up)
**Project**: [aoc2018.cabal](../../aoc2018.cabal) — single cabal package, library modules `Day00..Day25` in [src/](../../src/), dispatcher [app/Main.hs](../../app/Main.hs), tests in [test/](../../test/), benches in [bench/](../../bench/).

**Run a day**: `cabal run aoc2018-solve -- <n>` (reads `inputs/day<nn>.txt`).
**Run all tests**: `cabal test`.
**Run all benchmarks**: `cabal bench` (one day: `cabal bench -- --match prefix day00`; HTML report: `cabal bench -- --output bench.html`).

---

## Stats Dashboard

| Metric | Value |
|--------|-------|
| **Progress** | 10/26 (Day 0 warm-up + Days 1–9 done; Days 10–25 pending) |
| **Total Runtime** | 653.65 ms (Days 0–9) |
| **Average per Day** | 65.4 ms |

---

## Performance Table

Reported on a Windows 11 / GHC 9.6.7 / `-O2` build via `cabal bench` (criterion). Each row's **Parse**, **Part 1**, and **Part 2** columns are criterion's `mean` for the corresponding bench. **Total = Parse + Part 1 + Part 2** — the steady-state CPU cost of one solve.

| Day | Title | Parse | Part 1 | Part 2 | Total | Algorithm | Notes |
|----:|-------|------:|-------:|-------:|------:|-----------|-------|
| [00](day00_function_guide.md) | Inverse Captcha (warm-up, AoC 2017 Day 1) | 17.5 µs | 11.2 µs | 14.9 µs | 43.6 µs | Modular circular comparison | `zip ds (rotate k ds)` substitutes for indexed access; offset = 1 (P1) and n/2 (P2). |
| [01](day01_function_guide.md) | Chronal Calibration | 629.6 µs | 1.3 µs | 35.79 ms | 36.4 ms | Sum (P1); first-repeat search over `scanl (+) 0 (cycle deltas)` with `Data.Set` (P2) | Lazy infinite list pays off — `firstDup` consumes only as much of the running-total stream as it needs. |
| [02](day02_function_guide.md) | Inventory Management System | 84.7 µs | 439.9 µs | 1.02 ms | 1.54 ms | Frequency `Map.insertWith (+)` (P1); `tails`-based pair search with lazy short-circuit (P2) | First use of `Data.Map.Strict`; first day with a `String` answer (Part 2 = `tiwcdpbseqhxryfmgkvjujvza`). |
| [03](day03_function_guide.md) | No Matter How You Slice It | 4.05 ms | 175.1 ms | 170.8 ms | 350.0 ms | `Map.fromListWith (+)` over `(x,y)` keys to build a fabric frequency map; Part 2 finds the unique claim with all squares mapped to 1 | First record type (`Claim` with `!Int` fields + manual `NFData`); both parts independently rebuild the 130k-entry map — sharing it would halve the runtime (see function-guide sidebar). |
| [04](day04_function_guide.md) | Repose Record | 2.81 ms | 45.5 µs | 256 µs | 3.11 ms | Lexicographic sort of ISO timestamps; tail-recursive `go` accumulator builds `Map Int [Int]`; `maximumBy (comparing ...)` for both strategies | Sort step dominates parse time; post-parse work is µs-fast. First sum type (`Event`). |
| [05](day05_function_guide.md) | Alchemical Reduction | 344 µs | 1.04 ms | 47.7 ms | 49.1 ms | `foldl'`-as-stack reactor (P1); 26 independent reactor passes across `'a'..'z'` (P2) | Part 2 is exactly 26× Part 1 by construction; only algorithmic improvement (single-pass removal) would cut it. First day where Part 2 dominates by 40×. |
| [06](day06_function_guide.md) | Chronal Coordinates | 53.2 µs | 142.5 ms | 16.5 ms | 159.0 ms | Bounding-box Manhattan-distance Voronoi: per-cell `sort` + tie-on-head (P1); per-cell sum-of-distances threshold (P2) | Border-touching ⇒ infinite area is the trick that turns an infinite plane into a 304×308 grid; `closest` could drop ~110 ms by replacing per-cell `sort` with a two-min linear scan. |
| [07](day07_function_guide.md) | The Sum of Its Parts | 122.9 µs | 12.0 µs | 17.5 µs | 152.4 µs | Topological sort by repeated alphabetical-priority pick (P1); discrete-event 5-worker simulation, jumping to the next finish time (P2) | `Map Char (Set Char)` of prereqs doubles as ready-queue (empty value ⇒ ready) and as the "delete me from everyone" target on completion. Part 1 median of 3 runs (first was 13.45 µs / 91 % variance — warm-up noise). |
| [08](day08_function_guide.md) | Memory Maneuver | 8.30 ms | 22.2 µs | 10.7 µs | 8.33 ms | Recursive descent over a flat `[Int]`, threading `(result, leftover)` through tuple returns; Part 2 indexes children via `zip [1..]` + `lookup` + `mapMaybe` | First recursive ADT (`Tree`); first hand-rolled state-threading parser (the manual `State` monad). Parse is ~99 % of total runtime — `read :: String -> Int` over ~6500 tokens dominates. |
| [09](day09_function_guide.md) | Marble Mania | 1.41 µs | 407.2 µs | 45.5 ms | 45.95 ms | Doubly-linked list as two `STUArray s Int Int` index arrays inside `runST`; tail-recursive `go` with `BangPatterns` to keep the 7M-iteration inner loop allocation-free | First `ST` monad / scoped mutation; `ScopedTypeVariables` to bring the region tag `s` into scope inside the body. Part 2 simulates 7,173,000 placements at ~6.4 ns/marble. |
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
| [01](day01_function_guide.md) | Chronal Calibration | **576** | **77674** |
| [02](day02_function_guide.md) | Inventory Management System | **5880** | **`tiwcdpbseqhxryfmgkvjujvza`** |
| [03](day03_function_guide.md) | No Matter How You Slice It | **111485** | **113** |
| [04](day04_function_guide.md) | Repose Record | **85296** | **58559** |
| [05](day05_function_guide.md) | Alchemical Reduction | **11264** | **4552** |
| [06](day06_function_guide.md) | Chronal Coordinates | **4233** | **45290** |
| [07](day07_function_guide.md) | The Sum of Its Parts | **`GDHOSUXACIMRTPWNYJLEQFVZBK`** | **1024** |
| [08](day08_function_guide.md) | Memory Maneuver | **41521** | **19990** |
| [09](day09_function_guide.md) | Marble Mania | **380705** | **3171801582** |

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
