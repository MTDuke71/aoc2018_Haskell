-- | AoC 2018 Day 03 — No Matter How You Slice It.
--
-- The puzzle input is ~1300 fabric claims, one per line, each of the
-- form @#1 @ 258,327: 19x22@: claim ID, the @(left, top)@ inset of the
-- rectangle in inches, and its @width x height@ in inches. The fabric
-- itself is at least 1000x1000 inches.
--
-- * Part 1: how many square inches lie under /two or more/ claims.
-- * Part 2: the unique claim ID whose rectangle does not overlap any
--   other claim — its squares are all hit by exactly one claim (its
--   own).
--
-- Both parts share the same auxiliary structure: a frequency 'Map'
-- from @(x, y)@ square to "how many claims cover it". Part 1 counts
-- the entries with value @>= 2@; Part 2 finds the claim all of whose
-- squares map to @1@.
--
-- New concepts introduced this day (beyond Days 0–2):
--
--   * Records with named fields (@data Claim = Claim { ... }@). First
--     time tuples would have grown unwieldy.
--   * Strict fields (@!Int@) — the bang annotation forces evaluation
--     when the constructor is applied. Combined with 'Data.Map.Strict',
--     this keeps the working set free of unevaluated thunks.
--   * 'NFData' / 'rnf' — the @deepseq@ class for forcing a value to
--     /normal/ form (vs /weak head/ normal form). Not used by the
--     solution itself; the instance exists so the criterion benches
--     in @bench/Main.hs@ can use 'Criterion.nf' on a @[Claim]@. Days
--     0–2 didn't need this because '[Int]' and '[String]' already
--     have an 'NFData' instance from @deepseq@. Strict fields make
--     the instance a one-liner.
--   * 'Map.fromListWith' — builds a 'Map' from a list of key\/value
--     pairs, merging duplicate keys with a combining function. The
--     one-line frequency idiom: @Map.fromListWith (+) [(k,1) | ...]@.
--   * Nested list comprehensions over a custom type ('squares').

module Day03
  ( Claim (..)
  , Puzzle
  , parseInput
  , parseClaim
  , squares
  , countMap
  , part1
  , part2
  , solve
  ) where

import           Control.DeepSeq (NFData (..))
import           Data.List       (find)
import qualified Data.Map.Strict as Map

-- | One Elf's fabric claim. Strict @!Int@ fields force every field to
-- WHNF when the constructor is applied — for primitive types like
-- 'Int' that means fully evaluated. With ~1300 claims in memory this
-- avoids carrying around five lazy thunks per record.
data Claim = Claim
  { claimId :: !Int  -- ^ the @#NNN@ tag
  , left    :: !Int  -- ^ inches from the left edge of the fabric
  , top     :: !Int  -- ^ inches from the top edge of the fabric
  , width   :: !Int  -- ^ inches wide
  , height  :: !Int  -- ^ inches tall
  } deriving (Eq, Show)

-- | 'NFData' is the @deepseq@ class for "force a value all the way
-- to normal form." The solution itself never calls 'rnf'; the
-- instance is here purely so the benchmark suite in @bench/Main.hs@
-- can use 'Criterion.nf' on @[Claim]@ values. Because every field
-- is strict, 'seq'-ing the record evaluates the constructor and
-- (transitively) every field — so @rnf c = c \`seq\` ()@ is a
-- complete instance, no need to walk the fields by hand.
instance NFData Claim where
  rnf c = c `seq` ()

type Puzzle = [Claim]

-- | One claim per line. 'lines' already strips the trailing newline.
parseInput :: String -> Puzzle
parseInput = map parseClaim . lines

-- | Parse a single line of the form @#1 @ 258,327: 19x22@.
--
-- The trick: every separator character (@\#@, @\@@, @,@, @:@, @x@) gets
-- replaced with a space, then 'words' splits on whitespace and 'read'
-- parses each chunk as an 'Int'. Five 'Int's come back, in order:
-- claim id, left, top, width, height. This avoids hand-rolling a
-- per-character parser; we will graduate to @megaparsec@ when the
-- input format finally justifies it.
parseClaim :: String -> Claim
parseClaim line = case map read (words (map normalize line)) of
  [cid, x, y, w, h] -> Claim cid x y w h
  _                 -> error ("malformed claim: " ++ line)
  where
    normalize :: Char -> Char
    normalize c
      | c `elem` ("#@,:x" :: String) = ' '
      | otherwise                    = c

-- | Every @(x, y)@ fabric square a claim covers. The list comprehension
-- mirrors a nested loop: outer over @x@, inner over @y@. Inclusive on
-- the top-left corner, exclusive on the bottom-right (the @-1@ on the
-- upper bounds turns the half-open width\/height into closed indices).
squares :: Claim -> [(Int, Int)]
squares c =
  [ (x, y)
  | x <- [left c .. left c + width c - 1]
  , y <- [top  c .. top  c + height c - 1]
  ]

-- | The fabric as a frequency 'Map' from @(x, y)@ to "how many claims
-- cover it".
--
-- 'Map.fromListWith' takes a list of @(key, value)@ pairs and merges
-- duplicate keys with the supplied function. With @(+)@ and the
-- constant value @1@ that becomes the canonical "count occurrences"
-- idiom — the one-line equivalent of 'Day02.charCounts'\'s
-- @foldl' (\\m c -> Map.insertWith (+) c 1 m)@ pattern.
--
-- The strict 'Data.Map.Strict' variant keeps the @Int@ counts
-- evaluated as the map grows; without it we would build ~130k chained
-- @1 + 1 + 1 + ...@ thunks inside the map values.
countMap :: Puzzle -> Map.Map (Int, Int) Int
countMap claims =
  Map.fromListWith (+) [ (sq, 1) | c <- claims, sq <- squares c ]

-- | Part 1: how many fabric squares lie under two or more claims.
--
-- Built point-free as @size . filter (>= 2) . countMap@. Reading
-- right-to-left: build the count map, drop entries where the count
-- is below 2, ask for the size of what is left.
part1 :: Puzzle -> Int
part1 = Map.size . Map.filter (>= 2) . countMap

-- | Part 2: the unique claim ID whose rectangle does not overlap any
-- other claim. A claim is non-overlapping iff /every/ square it
-- covers maps to a count of exactly @1@ in the global 'countMap' (it
-- is the only claim there). The puzzle guarantees exactly one such
-- claim exists.
part2 :: Puzzle -> Int
part2 claims =
  let counts = countMap claims
      isAlone c = all (\sq -> Map.findWithDefault 0 sq counts == 1) (squares c)
  in case find isAlone claims of
       Just c  -> claimId c
       Nothing -> error "Day 03 Part 2: no non-overlapping claim found"

-- | Dispatcher entry point. Parses once, prints both answers.
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
