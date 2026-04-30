-- | AoC 2018 Day 00 — warm-up: a Haskell port of AoC 2017 Day 1
-- ("Inverse Captcha"). The input is a single line of digits treated
-- as a circular list; both parts sum the digits that match a partner
-- at a fixed offset.
--
-- * Part 1: partner is the next digit (offset 1).
-- * Part 2: partner is the digit halfway around (offset n\/2).
--
-- Concepts this day exercises (all already covered in tutorial Days
-- 1–10): list pipelines (@map@\/@filter@), 'Data.Char' helpers,
-- 'zip' to pair a list with a shifted copy of itself, list
-- comprehensions, and the @cabal@ project layout from Day 10.

module Day00
  ( Puzzle
  , parseInput
  , part1
  , part2
  , captchaSum
  , solve
  ) where

import Data.Char (digitToInt, isDigit)

-- | Parsed puzzle: just the list of digits, in the order they appear.
type Puzzle = [Int]

-- | Strip whitespace\/newlines and convert each digit character to its
-- numeric value. 'filter' keeps only the chars matching 'isDigit', so
-- a trailing @\\n@ (or stray spaces) cannot poison 'digitToInt'.
parseInput :: String -> Puzzle
parseInput = map digitToInt . filter isDigit

-- | Sum every digit that equals its partner @offset@ steps ahead in
-- the circular list. The trick is to pair @ds@ with a left-rotated
-- copy of itself: @zip ds (rotate offset ds)@. Then a list
-- comprehension keeps only the matching pairs and we sum them.
--
-- @rotate k xs = drop k xs ++ take k xs@ — the prefix moves to the
-- end. A @circular@ comparison becomes a plain elementwise one.
--
-- Both parts are O(n) single-pass; the Rust baseline indexes
-- @digits[(i + offset) % len]@, which is the same idea written
-- differently.
captchaSum :: Int -> Puzzle -> Int
captchaSum offset ds =
  sum [ d | (d, e) <- zip ds (rotate offset ds), d == e ]
  where
    rotate :: Int -> [Int] -> [Int]
    rotate k xs = drop k xs ++ take k xs

-- | Part 1: partner is the next digit. Offset is fixed at 1.
part1 :: Puzzle -> Int
part1 = captchaSum 1

-- | Part 2: partner is the digit halfway around. The puzzle promises
-- the list length is even, so @length ds \`div\` 2@ is exact.
part2 :: Puzzle -> Int
part2 ds = captchaSum (length ds `div` 2) ds

-- | Dispatcher entry point: parse once, print both parts. Matches
-- the @String -> IO ()@ shape that "app/Main.hs" expects for every
-- day's @solve@.
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
