-- | Solver for the Day 10 sample puzzle.
--
-- 'part1' is the running sum of all changes; 'part2' returns the first
-- running total that occurs twice, as we walk the list left-to-right.
-- Both are pure — they consume a list of integers and return the
-- answer, no IO involved.

module AoC.Solver
  ( part1
  , part2
  , firstRepeated
  ) where

import           Data.List (foldl', scanl')
import qualified Data.Set  as Set
import           Data.Set  (Set)

-- | Part 1: sum of every change.
part1 :: [Int] -> Int
part1 = foldl' (+) 0

-- | Part 2: the first running total that occurs twice.
--
-- Returns 'Nothing' if no repeat is reached. The full AoC 2018 Day 1
-- puzzle cycles the input until a repeat is found; for Day 10 we just
-- walk it once.
part2 :: [Int] -> Maybe Int
part2 changes = firstRepeated (scanl' (+) 0 changes)

-- | The first element of a list that appears twice, or 'Nothing'
-- if every element is unique. 'Ord a' is required so we can store
-- seen elements in a 'Set'.
firstRepeated :: Ord a => [a] -> Maybe a
firstRepeated = go Set.empty
  where
    go :: Ord a => Set a -> [a] -> Maybe a
    go _    []       = Nothing
    go seen (x : xs)
      | Set.member x seen = Just x
      | otherwise         = go (Set.insert x seen) xs
