-- |
-- Module      : Day05
-- Description : Day 05 — Alchemical Reduction
--
-- A polymer is a string of letter-units.  Two adjacent units /react/ and
-- destroy each other if they are the same letter but opposite case
-- (e.g. @\'a\'@ and @\'A\'@, @\'b\'@ and @\'B\'@).  Reactions are not
-- limited to a single pass — each elimination may expose a new adjacent
-- pair that also reacts.
--
-- Part 1: fully react the puzzle polymer; return the count of surviving
--         units.
-- Part 2: for each letter a–z, remove all units of that type (both cases)
--         from the polymer, fully react the remainder, and return the
--         length of the shortest result.
--
-- Concepts introduced this day:
--   * @foldl'@ as a stack processor — the canonical idiom for
--     left-to-right string transformations that depend on the most
--     recently produced output.
--   * 'Data.Char.toLower' / 'Data.Char.isLetter' — character-level
--     operations for case-insensitive comparison.
--   * Why @foldl'@ beats @foldr@ here: the reaction checks the /top/ of
--     the stack (the immediately preceding surviving unit), which is the
--     left end of the accumulator list — naturally served by @foldl'@.
--     A @foldr@-based formulation would build the output right-to-left
--     and could not check the \"already processed\" left context.
--   * 'minimum' over a list comprehension — exhaustive search across
--     26 single-letter candidates in one readable line.

module Day05
  ( parseInput
  , reacts
  , react
  , removeUnit
  , part1
  , part2
  , solve
  ) where

import Data.List (foldl')
import Data.Char (toLower, isLetter)

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Strip everything that is not a polymer unit (newlines, carriage returns,
--   whitespace).  For the actual puzzle input this is a single long line of
--   mixed-case letters; 'isLetter' is the safest filter.
parseInput :: String -> String
parseInput = filter isLetter

-- ---------------------------------------------------------------------------
-- Core reaction logic
-- ---------------------------------------------------------------------------

-- | Two polymer units react if they are the same letter but different case.
--
--   @reacts \'a\' \'A\' = True@  — same letter, opposite polarity
--   @reacts \'a\' \'a\' = False@ — same letter, same polarity (no reaction)
--   @reacts \'a\' \'B\' = False@ — different letters (no reaction)
reacts :: Char -> Char -> Bool
reacts a b = a /= b && toLower a == toLower b

-- | Fully react the polymer.
--
--   Uses @foldl'@ to walk the input left-to-right, maintaining a /stack/
--   as the accumulator.  On each step:
--
--   * If the stack is empty, push the current unit.
--   * If the top of the stack reacts with the current unit, pop the stack
--     (the pair annihilates).
--   * Otherwise push the current unit onto the stack.
--
--   The result is the surviving units in /reverse/ order.  Both 'part1'
--   and 'part2' only need the /length/, so the reversal is harmless.
--   Call @reverse . react@ if you need the units in original order.
--
--   Time: O(n).  Space: O(n) in the worst case (no reactions at all).
react :: String -> String
react = foldl' step []
  where
    step :: String -> Char -> String
    step []           c = [c]
    step (top : rest) c
      | reacts top c = rest            -- pair annihilates; pop the stack
      | otherwise    = c : top : rest  -- no reaction; push onto the stack

-- | Remove all units of the given type from the polymer (both upper- and
--   lower-case variants).
--
--   @removeUnit \'c\' \"dabAcCaCBAcCcaDA\" = \"dabAaBAaDA\"@
removeUnit :: Char -> String -> String
removeUnit c = filter (\x -> toLower x /= c)

-- ---------------------------------------------------------------------------
-- Solutions
-- ---------------------------------------------------------------------------

-- | Part 1: length of the fully-reacted polymer.
part1 :: String -> Int
part1 = length . react

-- | Part 2: for each letter a–z, remove that unit type and react.
--   Return the length of the shortest surviving polymer.
part2 :: String -> Int
part2 polymer =
  minimum [length (react (removeUnit c polymer)) | c <- ['a' .. 'z']]

-- | Print both answers.
solve :: String -> IO ()
solve contents = do
  let polymer = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 polymer))
  putStrLn ("  part 2: " ++ show (part2 polymer))
