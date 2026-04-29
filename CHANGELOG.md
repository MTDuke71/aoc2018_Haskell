# Changelog

## 0.1.0.0

- Initial AoC 2018 cabal project.
- Skeleton modules `Day00`..`Day25` exposing `parseInput`, `part1`, `part2`,
  and `solve`; each currently returns placeholder values.
- Executable `aoc2018-solve <day>` dispatches to the matching module's
  `solve` action against `inputs/dayNN.txt`.
- Hspec test suite with `pendingWith` markers for every unsolved day.
- Day 0 (warm-up = AoC 2017 Day 1 port) will be filled in during Day 11
  of the pre-AoC tutorial.
