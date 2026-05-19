{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day18
-- Description : Day 18 -- Settlers of the North Pole
--
-- A 50x50 grid of acres, each @.@ open, @|@ trees, or @#@
-- lumberyard.  Every minute all acres update *simultaneously* from
-- the state of their eight neighbours -- a classic two-dimensional
-- *cellular automaton*, the same family as Day 12's one-dimensional
-- pot rule and Conway's Game of Life:
--
--   * open      -> trees       if >= 3 adjacent acres are trees
--   * trees     -> lumberyard  if >= 3 adjacent acres are lumberyards
--   * lumberyard-> stays       if adjacent to >= 1 lumberyard /and/
--                              >= 1 trees, otherwise becomes open
--
-- The /resource value/ is (number of @|@) * (number of @#@).
--
-- Part 1: resource value after 10 minutes -- just step ten times.
--
-- Part 2: resource value after 1,000,000,000 minutes.  A billion
-- steps is infeasible directly, but a finite automaton on a finite
-- grid must eventually repeat a state, and once it does it cycles
-- forever with a fixed period.  So we *detect the cycle*: remember
-- the minute each state was first seen; the first repeat at minute
-- @t@ of a state last seen at @t0@ gives @period = t - t0@.  The
-- answer at the target minute is then the state @(target - t) \`mod\`
-- period@ steps further on.  This is the same trick as Day 12, but
-- Day 12 collapsed to a /period-1/ fixed point (the shape stopped
-- changing); here the period is genuinely > 1, so we need the full
-- "seen-state -> minute" map rather than a single previous value.
--
-- Concepts introduced this day:
--
--   * General cycle detection via a @Map state minute@.  Day 12 was
--     the period-1 special case; this is the general "find the loop,
--     project across a billion iterations" pattern.
--
--   * An immutable @UArray (Int,Int) Char@ stepped purely: each
--     minute builds a brand-new array with 'listArray' over
--     @'range' bnds@, reading the previous array.  No @ST@ needed --
--     contrast Day 17, which mutated one grid in place because the
--     flood revisited cells; here every cell is written exactly once
--     per minute, so a pure rebuild is both simpler and fast enough.
--
--   * 'elems' of the array as a cheap, 'Ord'-able state key for the
--     cycle 'Map' -- a 2500-character row-major snapshot.
module Day18
  ( -- * Types
    Puzzle (..)

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , step
  , resourceValue
  ) where

import           Control.DeepSeq    (NFData (..))
import           Data.Array.Unboxed (UArray, bounds, elems, listArray, range,
                                     inRange, (!))
import           Data.List          (foldl')
import qualified Data.Map.Strict    as Map

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The acre grid, indexed @(row, col)@ with bounds
-- @((0,0),(h-1,w-1))@.  Cells are the raw puzzle characters
-- @\'.\'@/@\'|\'@/@\'#\'@.
--
-- A @newtype@ wrapper (not a bare @UArray@) so we can hang a
-- hand-rolled 'NFData' on it: the @deepseq@ package ships no
-- @NFData (UArray i e)@ instance, and the benchmark harness needs
-- one.  For an /unboxed/ array WHNF already implies full
-- evaluation, so @a \`seq\` ()@ is a complete @rnf@ -- same pattern
-- as Day 11.
newtype Puzzle = Puzzle (UArray (Int, Int) Char)
  deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle a) = a `seq` ()

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Read the grid.  @lines@ splits on @\'\\n\'@; the first line's
-- length is the width, the line count the height.  'listArray' fills
-- the array in row-major order from the flattened character list,
-- which matches 'range' @((0,0),(h-1,w-1))@ exactly (it also walks
-- the second index fastest).
parseInput :: String -> Puzzle
parseInput raw =
  let rows = lines raw
      h    = length rows
      w    = case rows of (r : _) -> length r; [] -> 0
  in  Puzzle (listArray ((0, 0), (h - 1, w - 1)) (concat rows))

-- ---------------------------------------------------------------------------
-- Simulation
-- ---------------------------------------------------------------------------

-- | The eight neighbour offsets (the 3x3 block minus the centre).
deltas :: [(Int, Int)]
deltas =
  [ (dr, dc) | dr <- [-1, 0, 1], dc <- [-1, 0, 1], (dr, dc) /= (0, 0) ]

-- | One minute of the automaton.  Build a fresh array: for every
-- coordinate in @'range' bnds@ (row-major, so this lines up with
-- 'listArray'), apply 'cell' to the old value and its in-bounds
-- neighbours.  All reads are from the /old/ array @a@, so the update
-- is simultaneous by construction -- no half-stepped state can leak
-- in.
step :: Puzzle -> Puzzle
step (Puzzle a) = Puzzle (listArray bnds [ cell (r, c) | (r, c) <- range bnds ])
 where
  bnds = bounds a

  cell :: (Int, Int) -> Char
  cell (r, c) = transition (a ! (r, c)) trees yards
   where
    -- Tally trees (@|@) and lumberyards (@#@) among the <= 8
    -- in-bounds neighbours in a single strict left fold.  'foldl''
    -- (strict accumulator) avoids a thunk tower over the 2500-cell
    -- grid x ~1000 minutes; here the accumulator is the pair counts.
    (trees, yards) = foldl' tally (0, 0) deltas
    tally :: (Int, Int) -> (Int, Int) -> (Int, Int)
    tally acc@(!t, !y) (dr, dc)
      | not (inRange bnds p) = acc
      | otherwise = case a ! p of
          '|' -> (t + 1, y)
          '#' -> (t, y + 1)
          _   -> acc
      where p = (r + dr, c + dc)

-- | The transition rule, given the current acre and the
-- (trees, lumberyards) counts among its neighbours.
transition :: Char -> Int -> Int -> Char
transition '.' trees _     = if trees >= 3              then '|' else '.'
transition '|' _     yards = if yards >= 3              then '#' else '|'
transition '#' trees yards = if yards >= 1 && trees >= 1 then '#' else '.'
transition  c  _     _     = c          -- total: unreachable for valid input

-- | Resource value = (count of @|@) * (count of @#@).  One pass over
-- 'elems' (the row-major flattened cells) with a strict pair fold.
resourceValue :: Puzzle -> Int
resourceValue (Puzzle a) = t * y
 where
  (t, y) = foldl' acc (0, 0) (elems a)
  acc :: (Int, Int) -> Char -> (Int, Int)
  acc (!tt, !yy) '|' = (tt + 1, yy)
  acc (!tt, !yy) '#' = (tt, yy + 1)
  acc p           _  = p

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

-- | Part 1: ten minutes, then resource value.  @iterate step p@ is
-- the lazy infinite list @[p, step p, step (step p), ...]@; @!! 10@
-- forces exactly the eleventh element (minute 10).
part1 :: Puzzle -> Int
part1 p = resourceValue (iterate step p !! 10)

-- | Part 2: resource value after one billion minutes, by cycle
-- detection.  Walk minute by minute, recording @state -> minute@ in
-- a 'Map'.  On the first state we have seen before (first seen at
-- @t0@, now at @t@) the automaton is periodic with @period = t - t0@;
-- the target lands @(target - t) \`mod\` period@ steps past the
-- current state, which we reach with a short 'iterate'.
part2 :: Puzzle -> Int
part2 = go Map.empty 0
 where
  target :: Int
  target = 1000000000

  go :: Map.Map [Char] Int -> Int -> Puzzle -> Int
  go seen t p@(Puzzle a)
    | t == target = resourceValue p          -- target before any cycle
    | otherwise =
        let key = elems a
        in  case Map.lookup key seen of
              Just t0 ->
                let period    = t - t0
                    remaining = (target - t) `mod` period
                in  resourceValue (iterate step p !! remaining)
              Nothing -> go (Map.insert key t seen) (t + 1) (step p)

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
