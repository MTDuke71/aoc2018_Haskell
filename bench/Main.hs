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

-- | One day's bgroup. Reads the input, forces parsing once via 'env'
-- so per-bench timings are not polluted by the parse, then registers
-- all four benches under @<name>@.
dayBench
  :: NFData puzzle
  => String                         -- ^ bgroup name, e.g. @\"day00\"@
  -> FilePath                       -- ^ input file path
  -> (String -> puzzle)             -- ^ parseInput
  -> (puzzle -> Int)                -- ^ part1
  -> (puzzle -> Int)                -- ^ part2
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
  -- new days drop in here as they are solved.
  ]
