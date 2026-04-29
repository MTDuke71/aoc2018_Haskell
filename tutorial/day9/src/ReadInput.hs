-- | Day 9 — reading puzzle input from disk.
--
-- This file demonstrates the AoC pattern you will use every single
-- day for the next 25:
--
--   1. 'readFile "input.txt"' to slurp the file as a single 'String'.
--   2. 'lines' to split it into a list of one string per line.
--   3. A pure parser turns each line into a typed value.
--   4. A pure solver walks the list of values and computes the answer.
--   5. 'print' (or 'putStrLn') displays it.
--
-- The point is that steps 3 and 4 are pure — testable in GHCi without
-- any file at all — and steps 1, 2, 5 are the thin IO shell around
-- them. 'main' below is exactly that shape.

module Main where

import Data.List (foldl', scanl')
import qualified Data.Set as Set
import Data.Set (Set)

-- --------------------------------------------------------------------
-- 1. The IO functions: 'readFile' and 'writeFile'
-- --------------------------------------------------------------------
--
-- 'readFile  :: FilePath -> IO String'
-- 'writeFile :: FilePath -> String -> IO ()'
--
-- 'FilePath' is just a type synonym for 'String'. 'readFile' returns
-- the entire file contents as one 'String'; line breaks and trailing
-- newline included. We always pair it with 'lines :: String -> [String]'
-- to chop it into per-line pieces.
--
-- /Note on laziness/: in the 'base' library 'readFile' is /lazy/ —
-- the file handle is closed only when the returned string is fully
-- consumed. For AoC inputs (a few KB to a few MB) this is fine. For
-- larger files use 'Data.Text.IO.readFile' from the 'text' package
-- instead, which is strict and uses bytes-not-chars.

-- --------------------------------------------------------------------
-- 2. Parsing one line — a pure function
-- --------------------------------------------------------------------
--
-- The sample input is a list of signed integers, one per line:
--
--     +1
--     -2
--     +3
--     ...
--
-- 'parseChange' converts one such line to an 'Int'. The leading '+'
-- has to be stripped because 'read :: String -> Int' rejects it
-- ('read "-3"' works, but 'read "+3"' does not).
--
-- Returning 'Int' (not 'Maybe Int') means malformed input crashes the
-- program. That is fine for a tutorial; for real AoC code you would
-- prefer 'readMaybe' from 'Text.Read' and return 'Maybe Int'.

parseChange :: String -> Int
parseChange ('+' : rest) = read rest
parseChange s            = read s

-- --------------------------------------------------------------------
-- 3. Parsing the whole file — pure 'String -> [Int]'
-- --------------------------------------------------------------------
--
-- 'lines' splits on '\n' and discards a trailing empty line if the
-- file ends in a newline (which it should). 'map parseChange'
-- applies the per-line parser to each line.
--
-- This whole function is pure. It does not touch IO. You can call it
-- in GHCi with a hand-written 'String' and confirm it works without
-- a file in sight.

parseInput :: String -> [Int]
parseInput = map parseChange . lines

-- --------------------------------------------------------------------
-- 4. Solving Part 1 — sum of all changes
-- --------------------------------------------------------------------
--
-- AoC 2018 Day 1 Part 1, more or less. Sum the list of changes.
-- 'sum' is the Prelude version; 'foldl' (+) 0' is the explicit form
-- and matches the style from Day 6.

part1 :: [Int] -> Int
part1 = foldl' (+) 0

-- --------------------------------------------------------------------
-- 5. Solving Part 2 — first repeated running total
-- --------------------------------------------------------------------
--
-- AoC 2018 Day 1 Part 2 in spirit: walk the running totals of the
-- (possibly repeated) input and return the first total that occurs
-- twice. 'Set' from Day 8 is the right tool for "have I seen this?".
--
-- 'scanl'' (+) 0 xs' produces the running totals: [0, x1, x1+x2, ...].
-- 'firstRepeated' walks the resulting list, accumulating a 'Set Int'
-- of totals seen so far and stopping on the first hit.
--
-- For the sample input we only run through the list once, so a
-- "first repeat" might not exist. The real AoC puzzle cycles the
-- input — we will not bother for Day 9.

firstRepeated :: Ord a => [a] -> Maybe a
firstRepeated = go Set.empty
  where
    go :: Ord a => Set a -> [a] -> Maybe a
    go _    []       = Nothing
    go seen (x : xs)
      | Set.member x seen = Just x
      | otherwise         = go (Set.insert x seen) xs

part2 :: [Int] -> Maybe Int
part2 changes = firstRepeated (scanl' (+) 0 changes)

-- --------------------------------------------------------------------
-- 6. The main shell — IO at the edges, pure in the middle
-- --------------------------------------------------------------------
--
-- 'main' reads the file, parses it (pure), solves both parts (pure),
-- and prints the answers (IO). Notice that everything between the
-- first and the last line is a pure expression, named with 'let'.
-- That is the shape every AoC solution in this repo will take.

main :: IO ()
main = do
  contents <- readFile "tutorial/day9/sample.txt"
  let changes = parseInput contents
  putStrLn ("read "       ++ show (length changes) ++ " changes")
  putStrLn ("part 1 sum = " ++ show (part1 changes))
  putStrLn ("part 2 (first repeated running total) = "
            ++ show (part2 changes))
  putStrLn "Day 9 (ReadInput) complete!!!"

-- --------------------------------------------------------------------
-- Note on running this file
-- --------------------------------------------------------------------
--
-- The path "tutorial/day9/sample.txt" above is relative to the
-- /current working directory/, not to this source file. Run it from
-- the repository root:
--
--     runghc tutorial/day9/src/ReadInput.hs
--
-- If you 'cd tutorial/day9' first, the literal path will not match;
-- adjust to "sample.txt" or use 'getCurrentDirectory' to debug. This
-- is the only Day 9 gotcha worth knowing about up front — relative
-- paths bite every newcomer once.
