-- | AoC 2018 Day 02 — Inventory Management System.
--
-- The puzzle input is 250 box IDs, one per line, each 26 lowercase
-- letters. Both parts treat each ID as a 'String'.
--
-- * Part 1: a checksum. Count how many IDs contain /any/ letter that
--   appears exactly twice (call that count @twos@) and how many
--   contain /any/ letter that appears exactly three times (@threes@).
--   The checksum is @twos * threes@. A single ID can contribute to
--   both buckets and to neither, but never to either bucket twice.
-- * Part 2: among all pairs of IDs, find the unique pair that differs
--   in exactly one position; return the letters they share (i.e. the
--   ID with the differing position deleted).
--
-- New concepts introduced this day (beyond Day 0\/Day 1):
--
--   * 'Data.Map.Strict' (qualified) — first appearance in this
--     project. Used for the canonical "frequency count" idiom via
--     'Map.insertWith'.
--   * List comprehensions with /multiple generators/ — the natural
--     way to write the @for a in xs, for b in xs@ pair search of
--     Part 2.
--   * 'Data.List.tails' — produces every suffix of a list. Combined
--     with a head-pattern in a comprehension, it iterates each
--     unordered pair exactly once.

module Day02
  ( Puzzle
  , parseInput
  , part1
  , part2
  , charCounts
  , differByOne
  , commonLetters
  , solve
  ) where

import           Data.List       (foldl', tails)
import qualified Data.Map.Strict as Map

-- | A parsed puzzle: the box IDs in input order. No richer structure
-- is justified — both parts work directly on the list of 'String's.
type Puzzle = [String]

-- | One line per box ID. 'lines' already drops the trailing newline,
-- so no extra cleanup is needed.
parseInput :: String -> Puzzle
parseInput = lines

-- | Letter-frequency map for one box ID. The classic "increment a
-- counter" idiom: @Map.insertWith (+) c 1 m@ inserts @1@ if @c@ is
-- absent and adds @1@ to the existing value otherwise. Folded over
-- the string with 'foldl'' so the accumulator stays strict.
charCounts :: String -> Map.Map Char Int
charCounts = foldl' (\m c -> Map.insertWith (+) c 1 m) Map.empty

-- | True iff some letter in the box ID appears /exactly/ @n@ times.
-- 'Map.elems' returns just the counts; we ask whether @n@ is one of
-- them.
hasExactly :: Int -> String -> Bool
hasExactly n boxId = n `elem` Map.elems (charCounts boxId)

-- | Counts how many elements satisfy the predicate. The same shape
-- as the @count@ helper in 'AOC.Common' from the skill guide; lifted
-- inline here because it is the only day that has needed it so far.
count :: (a -> Bool) -> [a] -> Int
count p = length . filter p

-- | Part 1: @(IDs with a doubled letter) * (IDs with a tripled letter)@.
-- The IDs that have both a 2 and a 3 are counted in both factors —
-- that is exactly what the puzzle asks for.
part1 :: Puzzle -> Int
part1 ids = count (hasExactly 2) ids * count (hasExactly 3) ids

-- | True iff two equal-length strings differ in /exactly/ one
-- position. 'zipWith' walks both lists in lockstep, producing one
-- 'Bool' per position; we count how many came back 'True'.
differByOne :: String -> String -> Bool
differByOne a b = count id (zipWith (/=) a b) == 1

-- | The characters at positions where two strings agree. After
-- 'differByOne' has returned 'True', this is the answer to Part 2:
-- the original ID with the one differing letter removed.
commonLetters :: String -> String -> String
commonLetters a b = [ x | (x, y) <- zip a b, x == y ]

-- | Part 2: find the unique pair of IDs differing in one position
-- and return their common letters. 'tails' produces every suffix of
-- the list (@[xs, tail xs, tail (tail xs), ..., []]@); the pattern
-- @(a:rest)@ in the generator skips the empty suffix and binds @a@
-- to each ID in turn while @rest@ holds the IDs that come after it.
-- Each unordered pair is therefore visited exactly once.
--
-- The puzzle promises exactly one matching pair, so 'head' on the
-- comprehension is total. Lazy evaluation means the search stops at
-- the first match — we do not enumerate every remaining pair.
part2 :: Puzzle -> String
part2 ids = head
  [ commonLetters a b
  | (a : rest) <- tails ids
  , b          <- rest
  , differByOne a b
  ]

-- | Dispatcher entry point. Same 'String -> IO ()' shape every day in
-- this project follows; the only twist is that Part 2's answer is a
-- 'String', so we append it directly instead of routing it through
-- 'show' (which would surround it with quotes).
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ part2 puzzle)
