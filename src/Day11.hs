{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : Day11
-- Description : Day 11 -- Chronal Charge
--
-- The wrist-mounted device projects a 300x300 grid of fuel cells.
-- Each cell @(x, y)@, 1-indexed from the top-left corner, has a
-- "power level" determined by a closed-form arithmetic recipe applied
-- to @(x, y)@ and the puzzle's input integer (the grid /serial
-- number/).  Power levels are integers in the range @[-5, 4]@.
--
-- Part 1: find the 3x3 square with the largest total power; report
--         its top-left coordinate as the string @"X,Y"@.
-- Part 2: find the square of /any/ size from 1x1 to 300x300 with the
--         largest total power; report it as @"X,Y,size"@.
--
-- The naive approach to Part 2 is O(N^5): five nested O(N) loops --
-- three to position the candidate square @(s, x, y)@, two more to
-- sum its @s * s@ cells.  At @N = 300@ that is about 8.3 x 10^10
-- cell additions -- many minutes of CPU.  A summed-area table
-- (a.k.a. integral image) collapses the inner @s * s@ sum into an
-- O(1) four-corner lookup, dropping the total cost to ~9 x 10^6 SAT
-- lookups and the asymptotic complexity to O(N^3) -- ~10,000x
-- fewer operations at @N = 300@.  Building the table is itself
-- O(N^2), so it earns its keep after the very first query.
--
-- Concepts introduced this day:
--
--   * Summed-area table (2D prefix sums).  Build a (301 x 301) array
--     where @sat[x, y]@ = sum of power levels over the rectangle
--     @(1..x, 1..y)@.  Then any axis-aligned subrectangle sum is a
--     four-term inclusion-exclusion in O(1).  The classical
--     competitive-programming technique for "max-rectangle-sum"
--     queries.
--   * 'runSTUArray'.  The sugar that wraps "allocate an 'STUArray',
--     mutate it, freeze the result" into a single combinator that
--     returns an immutable 'UArray'.  Day 9 used 'ST' with 'STUArray'
--     but never froze; here we want the frozen array as the
--     long-lived query target for Part 1 and Part 2.
--   * 'UArray (Int, Int) Int' -- a 2D unboxed array indexed by a
--     tuple.  GHC turns the tuple index into a linear offset for us.
--   * 'maximumBy' with 'comparing' to argmax a list comprehension.
--     We met its dual 'minimumBy' on Day 10's ternary search; here
--     the same pattern picks the best @(x, y)@ from a list of
--     scored candidates.
module Day11
  ( Puzzle (..)
  , parseInput
  , powerLevel
  , buildSat
  , squareSum
  , bestSquare
  , bestAnySize
  , part1
  , part2
  , solve
  ) where

import           Control.DeepSeq    (NFData (..))
import           Control.Monad      (forM_)
import           Control.Monad.ST   (ST)
import           Data.Array.ST      (STUArray, newArray, readArray,
                                     runSTUArray, writeArray)
import           Data.Array.Unboxed (UArray, (!))
import           Data.Char          (isDigit)
import           Data.List          (foldl', maximumBy)
import           Data.Ord           (comparing)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The parsed puzzle: the fully built summed-area table.
--
--   Building the SAT in 'parseInput' lets 'part1' and 'part2' both
--   query in O(1) per square, and matches the project's
--   @Total = Parse + Part 1 + Part 2@ benchmark convention -- the
--   heavy 2D pass is credited to Parse, the queries to the parts.
--
--   The serial number itself is consumed by 'buildSat' and not stored;
--   nothing downstream needs to look at it again.
--
--   We wrap in a @newtype@ rather than using a type synonym so we
--   can hang a hand-rolled 'NFData' instance off it without an
--   orphan declaration.  'UArray' is unboxed (strict in every cell
--   by construction), so forcing the array to weak head normal form
--   is equivalent to deep evaluation -- @rnf (Puzzle a) = a \`seq\` ()@
--   is all criterion's 'nf' needs.
newtype Puzzle = Puzzle (UArray (Int, Int) Int)

instance NFData Puzzle where
  rnf (Puzzle a) = a `seq` ()

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse the input into a 'Puzzle'.  The raw file is a single integer
--   (e.g. @"9435\\n"@); 'filter' keeps just the digits and an optional
--   leading minus sign, 'read' parses to 'Int', then 'buildSat' turns
--   that serial into the 301 x 301 summed-area table.
parseInput :: String -> Puzzle
parseInput raw =
  let serial = read (filter (\c -> c == '-' || isDigit c) raw) :: Int
  in  Puzzle (buildSat serial)

-- ---------------------------------------------------------------------------
-- Power level
-- ---------------------------------------------------------------------------

-- | Power level of fuel cell @(x, y)@ in a grid with the given serial.
--
--   The puzzle's recipe in code form:
--
-- @
--   rackId   = x + 10
--   step     = (rackId * y + serial) * rackId
--   hundreds = (step \`div\` 100) \`mod\` 10
--   level    = hundreds - 5
-- @
--
--   The "hundreds digit" rule (puzzle text: \"keep only the hundreds
--   digit of the power level\") is exactly the @div 100 ; mod 10@
--   pipeline: 'div' by 100 shifts the decimal representation right by
--   two digits, and 'mod' by 10 keeps only the units digit of what is
--   left.  For example, @12345 \`div\` 100 == 123@ and @123 \`mod\` 10
--   == 3@ -- the 3 was originally the hundreds digit of 12345.
powerLevel :: Int -> Int -> Int -> Int
powerLevel serial x y =
  let rackId   = x + 10
      step     = (rackId * y + serial) * rackId
      hundreds = (step `div` 100) `mod` 10
  in  hundreds - 5

-- ---------------------------------------------------------------------------
-- Summed-area table
-- ---------------------------------------------------------------------------

-- | Build the 301 x 301 summed-area table for the given serial.
--
--   Indices @(0, _)@ and @(_, 0)@ are zero-padded -- 'newArray'
--   initialises every cell to 0 -- so the inclusion-exclusion in
--   'squareSum' works uniformly without a special case for the
--   leftmost column or topmost row.  For @x, y >= 1@:
--
-- @
--   sat[x, y] = power[x, y]
--             + sat[x-1, y] + sat[x, y-1]
--             - sat[x-1, y-1]
-- @
--
--   The recurrence reads three already-filled neighbours per cell, so
--   we fill in row-major order (y outer, x inner) to satisfy the data
--   dependency.  'STUArray' gives cheap O(1) reads and writes during
--   construction; 'runSTUArray' freezes the final state into an
--   immutable 'UArray' without ever exposing the mutable phase.
buildSat :: Int -> UArray (Int, Int) Int
buildSat serial = runSTUArray (buildSatST serial)

-- | The 'ST' core of 'buildSat'.  Lives in a fresh 's' region so the
--   mutable array cannot escape; 'runSTUArray' takes the result and
--   hands back the frozen 'UArray'.
--
--   The 'forall s.' header plus @ScopedTypeVariables@ lets us write
--   the 'STUArray' type annotation on 'newArray' below, which pins
--   GHC to the /unboxed/ representation (raw machine 'Int's, no
--   pointers).  Same trick used in 'Day09.playST'.
buildSatST :: forall s. Int -> ST s (STUArray s (Int, Int) Int)
buildSatST serial = do
  a <- newArray ((0, 0), (300, 300)) 0 :: ST s (STUArray s (Int, Int) Int)
  forM_ [1 .. 300] $ \y ->
    forM_ [1 .. 300] $ \x -> do
      let p = powerLevel serial x y
      l  <- readArray a (x - 1, y)
      u  <- readArray a (x, y - 1)
      ul <- readArray a (x - 1, y - 1)
      writeArray a (x, y) (p + l + u - ul)
  return a

-- | Sum of the @s x s@ square whose top-left fuel cell is at @(x, y)@.
--
--   Inclusion-exclusion on the four corners of the SAT:
--
-- @
--   sum(x..x+s-1, y..y+s-1)
--     = sat[x+s-1, y+s-1]
--     - sat[x-1,   y+s-1]
--     - sat[x+s-1, y-1]
--     + sat[x-1,   y-1]
-- @
--
--   Four 'UArray' reads and three additions -- O(1) regardless of
--   @s@.  This is the whole point of the SAT.
squareSum :: UArray (Int, Int) Int -> Int -> Int -> Int -> Int
squareSum sat x y s =
  let !x2 = x + s - 1
      !y2 = y + s - 1
  in  sat ! (x2, y2)
    - sat ! (x - 1, y2)
    - sat ! (x2, y - 1)
    + sat ! (x - 1, y - 1)

-- ---------------------------------------------------------------------------
-- Searching for the best square
-- ---------------------------------------------------------------------------

-- | The top-left @(x, y)@ of the size-@s@ square with the maximum
--   total power.
--
--   For each valid top-left @(x, y)@ -- @1 <= x, y@ and
--   @x + s - 1 <= 300@ -- score it with 'squareSum' and pick the
--   argmax with 'maximumBy' / 'comparing'.  At @s = 3@ this scans
--   298 * 298 = 88,804 squares; well inside "free."
bestSquare :: UArray (Int, Int) Int -> Int -> (Int, Int)
bestSquare sat s =
  fst $
    maximumBy (comparing snd)
      [ ((x, y), squareSum sat x y s)
      | x <- [1 .. 301 - s]
      , y <- [1 .. 301 - s]
      ]

-- | The @(x, y, s)@ of the square of /any/ size 1..300 with the
--   maximum total power.
--
--   Sweeps the full @(x, y, s)@ space with a strict 'foldl'' tracking
--   the running best @(x, y, s, power)@.  Bang pattern on the score
--   field of the accumulator keeps the comparison strict -- otherwise
--   ~9 million unevaluated comparison thunks would tower up.  The
--   'squareSum' call lives inside 'step' (not in the comprehension
--   itself) so each candidate allocates one 3-tuple, not one 4-tuple
--   plus an unforced 'Int'.
--
--   Counts of squares per size sum to @sum_{s=1}^{300} (301 - s)^2 =
--   sum_{k=1}^{300} k^2 = 9,045,050@ -- about 9 million 'squareSum'
--   calls in total, each a handful of array reads.
bestAnySize :: UArray (Int, Int) Int -> (Int, Int, Int)
bestAnySize sat = (bx, by, bs)
  where
    (bx, by, bs, _) =
      foldl' step (1, 1, 1, squareSum sat 1 1 1)
        [ (x, y, s)
        | s <- [1 .. 300]
        , x <- [1 .. 301 - s]
        , y <- [1 .. 301 - s]
        ]

    step :: (Int, Int, Int, Int) -> (Int, Int, Int) -> (Int, Int, Int, Int)
    step best@(_, _, _, !bestP) (x, y, s) =
      let !p = squareSum sat x y s
      in  if p > bestP then (x, y, s, p) else best

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

-- | Part 1: the top-left of the best 3x3 square, formatted as
--   @\"X,Y\"@ -- the literal string AoC asks for.
part1 :: Puzzle -> String
part1 (Puzzle sat) =
  let (x, y) = bestSquare sat 3
  in  show x ++ "," ++ show y

-- | Part 2: the @(x, y, s)@ of the best square of any size, formatted
--   as @\"X,Y,size\"@.
part2 :: Puzzle -> String
part2 (Puzzle sat) =
  let (x, y, s) = bestAnySize sat
  in  show x ++ "," ++ show y ++ "," ++ show s

-- ---------------------------------------------------------------------------
-- IO entry point
-- ---------------------------------------------------------------------------

-- | Parse once via the shared @let@ binding -- the SAT is built a
--   single time and reused for both parts.
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ part1 puzzle)
  putStrLn ("  part 2: " ++ part2 puzzle)
