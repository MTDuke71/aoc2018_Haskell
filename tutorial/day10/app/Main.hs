-- | The Day 10 executable: a thin IO shell over the pure library.
--
-- Build and run with:
--
--     cabal run day10-solve
--
-- 'cabal run' executes inside the package directory, so the relative
-- path "sample.txt" resolves correctly without 'cd'-ing first.

module Main where

import AoC.Parsing (parseInput)
import AoC.Solver  (part1, part2)

main :: IO ()
main = do
  contents <- readFile "sample.txt"
  let changes = parseInput contents
  putStrLn ("read "       ++ show (length changes) ++ " changes")
  putStrLn ("part 1 sum = " ++ show (part1 changes))
  putStrLn ("part 2 (first repeated running total) = "
            ++ show (part2 changes))
