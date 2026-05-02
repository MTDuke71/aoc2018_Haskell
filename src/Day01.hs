-- | AoC 2018 Day 01 — Chronal Calibration.
--
-- The puzzle input is a list of signed frequency deltas, one per line
-- (@+13@, @-12@, ...). Starting from frequency 0, both parts walk
-- those deltas:
--
-- * Part 1: apply every delta once; report the final frequency
--   (= the sum of the list).
-- * Part 2: cycle the list endlessly; report the first frequency
--   that is reached twice (the initial 0 counts as the first frequency
--   we ever reach).
--
-- New concepts introduced this day (beyond Day 0's list pipeline):
--
--   * 'lines' for line-oriented input.
--   * Operator sections like @(=='+')@ — a partially applied operator
--     becomes a one-argument function.
--   * 'cycle' to build an infinite list, plus a worked example of
--     /lazy infinite lists/ paying off: 'firstDup' walks the lazy
--     stream only as far as it needs to.
--   * 'scanl' to expose every running total of a fold.
--   * Qualified imports of 'Data.Set.Strict' for fast membership
--     testing — the first time we reach for @containers@ in this
--     project.

module Day01
  ( Puzzle
  , parseInput
  , part1
  , part2
  , solve
  ) where

import           Data.List (foldl')
import qualified Data.Set  as Set

-- | A parsed puzzle: just the signed deltas, in input order.
type Puzzle = [Int]

-- | Read each line as a signed integer. The Prelude's 'read' for 'Int'
-- accepts a leading @-@ but /not/ a leading @+@, so we strip the
-- optional plus sign first via @dropWhile (=='+')@.
--
-- @(=='+')@ is an /operator section/: a binary operator with one
-- argument supplied becomes a one-argument function. Here it is
-- @\\c -> c == '+'@ — a 'Char' predicate that is true only for the
-- plus character.
parseInput :: String -> Puzzle
parseInput = map (read . dropWhile (== '+')) . lines

-- | Part 1: the resulting frequency is just the sum of all deltas.
-- 'foldl'' is the strict left fold — same answer as 'sum', but the
-- explicit fold makes the "fold over deltas with @(+)@ starting at 0"
-- shape obvious, and it is the right habit for any larger
-- accumulation.
part1 :: Puzzle -> Int
part1 = foldl' (+) 0

-- | Part 2: cycle the deltas, walk the running totals, return the
-- first total seen twice. Splits naturally into:
--
--   1. @cycle deltas@ — an infinite list that repeats @deltas@ forever.
--   2. @scanl (+) 0 ...@ — the running totals starting at 0, /also/
--      infinite (and lazy, so nothing is computed yet).
--   3. @firstDup@ — walks that lazy stream, tracking what it has seen
--      in a 'Set.Set', and stops as soon as a value repeats.
--
-- Laziness is what makes this safe: 'cycle' and 'scanl' would be
-- catastrophic if Haskell were strict, but 'firstDup' only forces as
-- many elements as it needs.
part2 :: Puzzle -> Int
part2 deltas = firstDup (scanl (+) 0 (cycle deltas))

-- | Walk a (potentially infinite) list, returning the first element
-- that has already been seen. 'Set.member' is O(log n); the whole
-- search is O(k log k) where k is the index of the first repeat.
--
-- The empty-list case is unreachable for the puzzle inputs we feed it
-- — 'cycle' on a non-empty list is always infinite — but GHC's
-- @-Wall@ wants the pattern to be total, so we name the impossible
-- branch with 'error'.
firstDup :: Ord a => [a] -> a
firstDup = go Set.empty
  where
    go _    []       = error "firstDup: finite list with no duplicate"
    go seen (x : xs)
      | x `Set.member` seen = x
      | otherwise           = go (Set.insert x seen) xs

-- | Dispatcher entry point. Same shape as every other day in this
-- project: parse once, print both parts.
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
