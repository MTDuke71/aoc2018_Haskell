# Python reference solutions

The shipping solutions for AoC 2018 are in [src/](../src/) — Haskell, with full tests and benches. The `python/` directory holds **algorithm-reference solutions only**: short, idiomatic Python files that capture the algorithm without language-mechanic noise.

The Python is the spec; the Haskell is the main solve. When a function guide says "the algorithm is …," the Python file is the executable version of that explanation.

## Conventions

- **Stdlib only.** No `requirements.txt`, no `pytest`. Run a day with:

  ```
  python python/day<NN>.py
  ```

  from the repo root. Each file reads `inputs/day<NN>.txt` and prints `part 1` and `part 2`.

- **Short.** A typical day is 30–60 lines. Don't port Haskell optimisations — the Python file's job is to make the algorithm legible, not to be fast. (Most days finish in < 1 s anyway.)

- **Same algorithm as the Haskell.** Not a different approach. The function guide's algorithm section walks the Python; the Haskell explanation that follows is a transliteration of the same logic.

## Coverage

| Day | Title | Python | Haskell | Trace / extras |
|----:|-------|:------:|:-------:|:--------------:|
| 12 | Subterranean Sustainability | [day12.py](day12.py) | [Day12.hs](../src/Day12.hs) | [day12_trace.py](day12_trace.py) — prints normalised pattern + shift per generation until the spaceship locks in |
| 13 | Mine Cart Madness | [day13.py](day13.py) | [Day13.hs](../src/Day13.hs) | — |
| 14 | Chocolate Charts | [day14.py](day14.py) | [Day14.hs](../src/Day14.hs) | — |

(Earlier days will be backfilled on demand.)
