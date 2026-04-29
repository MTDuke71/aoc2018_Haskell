-- | AoC 2018 Day 12 — placeholder skeleton.
--
-- Replace 'parseInput' / 'part1' / 'part2' (and 'Puzzle' if a richer
-- representation fits) with the real solution. Add real test cases
-- in @test/Day12Spec.hs@.

module Day12
  ( Puzzle
  , parseInput
  , part1
  , part2
  , solve
  ) where

type Puzzle = [String]

parseInput :: String -> Puzzle
parseInput = lines

part1 :: Puzzle -> Int
part1 _ = 0

part2 :: Puzzle -> Int
part2 _ = 0

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle) ++ "  (skeleton)")
  putStrLn ("  part 2: " ++ show (part2 puzzle) ++ "  (skeleton)")
