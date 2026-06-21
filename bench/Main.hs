-- | Criterion benchmarks for the AoC 2018 Haskell solutions.
--
-- Run from the package root:
--
--   cabal bench                                   -- run everything
--   cabal bench -- --match prefix day00           -- one day only
--   cabal bench -- --output bench.html            -- HTML report
--
-- Each day contributes a 'bgroup' with four benches:
--
--   * @parseInput@ — measures only the parser.
--   * @part1@      — measures Part 1 on already-parsed input.
--   * @part2@      — measures Part 2 on already-parsed input.
--   * @combined@   — measures parse + Part 1 + Part 2 from raw 'String',
--                    end-to-end. Kept as a sanity check; not the
--                    headline figure (the per-iteration list
--                    allocation it pays for inflates the number above
--                    real steady-state cost).
--
-- The summary table at "Problem_Statements/days/summary_2018.md"
-- reports @Total = Parse + Part 1 + Part 2@ (sum of the first three
-- benches, taken from criterion's @mean@).
--
-- Adding a new day is two lines: an @import qualified DayNN@ at the
-- top, and a copy-paste of 'dayBench' with the day's name.

module Main where

import           Control.DeepSeq      (NFData)
import           Criterion.Main       (Benchmark, bench, bgroup, defaultMain,
                                       env, nf)

import qualified Day00
import qualified Day01
import qualified Day02
import qualified Day03
import qualified Day04
import qualified Day05
import qualified Day06
import qualified Day07
import qualified Day08
import qualified Day09
import qualified Day10
import qualified Day11
import qualified Day12
import qualified Day13
import qualified Day14
import qualified Day15
import qualified Day16
import qualified Day17
import qualified Day18
import qualified Day19
import qualified Day20
import qualified Day21
import qualified Day22
import qualified Day23
import qualified Day24
import qualified Day25

-- | One day's bgroup. Reads the input, forces parsing once via 'env'
-- so per-bench timings are not polluted by the parse, then registers
-- all four benches under @<name>@. The result types of @part1@ and
-- @part2@ are polymorphic so days whose answer is, say, a 'String'
-- (Day 2) plug in unchanged — only the 'NFData' constraints matter
-- for criterion's 'nf'.
dayBench
  :: (NFData puzzle, NFData a, NFData b)
  => String                         -- ^ bgroup name, e.g. @\"day00\"@
  -> FilePath                       -- ^ input file path
  -> (String -> puzzle)             -- ^ parseInput
  -> (puzzle -> a)                  -- ^ part1
  -> (puzzle -> b)                  -- ^ part2
  -> Benchmark
dayBench name path parseInput part1 part2 =
  env (do raw <- readFile path
          let p = parseInput raw
          return (raw, p)) $ \ ~(raw, p) ->
    bgroup name
      [ bench "parseInput" $ nf parseInput raw
      , bench "part1"      $ nf part1      p
      , bench "part2"      $ nf part2      p
      , bench "combined"   $ nf (\r -> let pp = parseInput r
                                       in  (part1 pp, part2 pp)) raw
      ]

main :: IO ()
main = defaultMain
  [ dayBench "day00" "inputs/day00.txt" Day00.parseInput Day00.part1 Day00.part2
  , dayBench "day01" "inputs/day01.txt" Day01.parseInput Day01.part1 Day01.part2
  , dayBench "day02" "inputs/day02.txt" Day02.parseInput Day02.part1 Day02.part2
  , dayBench "day03" "inputs/day03.txt" Day03.parseInput Day03.part1 Day03.part2
  , dayBench "day04" "inputs/day04.txt" Day04.parseInput Day04.part1 Day04.part2
  , dayBench "day05" "inputs/day05.txt" Day05.parseInput Day05.part1 Day05.part2
  , dayBench "day06" "inputs/day06.txt" Day06.parseInput Day06.part1 Day06.part2
  , dayBench "day07" "inputs/day07.txt" Day07.parseInput Day07.part1 Day07.part2
  , dayBench "day08" "inputs/day08.txt" Day08.parseInput Day08.part1 Day08.part2
  , dayBench "day09" "inputs/day09.txt" Day09.parseInput Day09.part1 Day09.part2
  , dayBench "day10" "inputs/day10.txt" Day10.parseInput Day10.part1 Day10.part2
  -- Day 10 has two findMessage algorithms; bench them side by side so
  -- the function-guide table can quote concrete numbers.  Linear vs
  -- ternary search, both on the same parsed input.
  , env (do raw <- readFile "inputs/day10.txt"
            let p = Day10.parseInput raw
            return p) $ \p ->
      bgroup "day10/findMessage"
        [ bench "linear scan" $ nf Day10.findMessage        p
        , bench "ternary"     $ nf Day10.findMessageTernary p
        ]
  , dayBench "day11" "inputs/day11.txt" Day11.parseInput Day11.part1 Day11.part2
  , dayBench "day12" "inputs/day12.txt" Day12.parseInput Day12.part1 Day12.part2
  , dayBench "day13" "inputs/day13.txt" Day13.parseInput Day13.part1 Day13.part2
  , dayBench "day14" "inputs/day14.txt" Day14.parseInput Day14.part1 Day14.part2
  , dayBench "day15" "inputs/day15.txt" Day15.parseInput Day15.part1 Day15.part2
  , dayBench "day16" "inputs/day16.txt" Day16.parseInput Day16.part1 Day16.part2
  , dayBench "day17" "inputs/day17.txt" Day17.parseInput Day17.part1 Day17.part2
  , dayBench "day18" "inputs/day18.txt" Day18.parseInput Day18.part1 Day18.part2
  , dayBench "day19" "inputs/day19.txt" Day19.parseInput Day19.part1 Day19.part2
  , dayBench "day20" "inputs/day20.txt" Day20.parseInput Day20.part1 Day20.part2
  , dayBench "day21" "inputs/day21.txt" Day21.parseInput Day21.part1 Day21.part2
  , dayBench "day22" "inputs/day22.txt" Day22.parseInput Day22.part1 Day22.part2
  , dayBench "day23" "inputs/day23.txt" Day23.parseInput Day23.part1 Day23.part2
  , dayBench "day24" "inputs/day24.txt" Day24.parseInput Day24.part1 Day24.part2
  , dayBench "day25" "inputs/day25.txt" Day25.parseInput Day25.part1 Day25.part2
  -- new days drop in here as they are solved.
  ]
