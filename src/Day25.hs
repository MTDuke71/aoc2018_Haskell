{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : Day25
-- Description : Day 25 -- Four-Dimensional Adventure
--
-- A list of 4-D points.  Two points are in the same /constellation/ if
-- their Manhattan distance is at most 3, transitively: constellations
-- are the connected components of the graph that joins every pair of
-- points within distance 3.
--
--   * Part 1: how many constellations are there.
--   * Part 2: none -- Day 25's second star is awarded for completing the
--     other 49.  'part2' is a stub so the four-function shape holds.
--
-- Concepts introduced this day:
--
--   * /Union-Find (disjoint-set union)/ -- the canonical near-constant
--     connected-components structure, with /path compression/ and
--     /union by rank/.  Implemented over 'STUArray's for the parent and
--     rank tables, in the same @runST@ style as Days 9, 11, 14, 17.
--
--   * /Connected components without building the graph/: we never
--     materialise an adjacency list -- the @O(n^2)@ pairwise distance
--     scan feeds 'union' directly, and the answer is the number of
--     /roots/ (self-parents) left at the end.
module Day25
  ( -- * Types
    V4
  , Puzzle

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , manhattan
  , countConstellations
  ) where

import           Control.Monad    (foldM, forM_, when)
import           Control.Monad.ST (ST, runST)
import           Data.Array       (Array, listArray, (!))
import           Data.Array.ST    (STUArray, newArray, newListArray, readArray,
                                   writeArray)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A point in 4-space.  A 4-tuple gives 'Eq'/'Ord'/'NFData' for free.
type V4 = (Int, Int, Int, Int)

-- | The parsed puzzle: every fixed point in spacetime.
type Puzzle = [V4]

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | One comma-separated 4-tuple per line, e.g. @8,6,7,-5@.  Blank lines
-- (a trailing newline) are dropped.
parseInput :: String -> Puzzle
parseInput = map parseLine . filter (not . null) . lines

-- | Parse a single @"x,y,z,w"@ line.  Commas become spaces so 'words'
-- can split, then each chunk is 'read' (handling the leading @-@).
parseLine :: String -> V4
parseLine line = case map read (words (map commaToSpace line)) of
  [a, b, c, d] -> (a, b, c, d)
  _            -> error ("Day25.parseLine: cannot parse " ++ show line)
 where
  commaToSpace ch = if ch == ',' then ' ' else ch

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

-- | Manhattan distance between two 4-D points.
manhattan :: V4 -> V4 -> Int
manhattan (a, b, c, d) (e, f, g, h) =
  abs (a - e) + abs (b - f) + abs (c - g) + abs (d - h)

-- ---------------------------------------------------------------------------
-- Union-Find
-- ---------------------------------------------------------------------------

-- | Count the connected components ("constellations") of the points,
-- where an edge joins any two within Manhattan distance 3.
--
-- A disjoint-set forest over @[0 .. n-1]@: every point starts as its own
-- singleton, each close-enough pair is 'union'ed, and the number of
-- components is the number of /roots/ (nodes that are their own parent)
-- left at the end.
countConstellations :: [V4] -> Int
countConstellations pts = runST action
 where
  n      = length pts
  points = listArray (0, n - 1) pts :: Array Int V4

  action :: forall s. ST s Int
  action = do
    -- parent[i] = i (each point is its own set); rank[i] = 0.
    parent <- newListArray (0, n - 1) [0 .. n - 1] :: ST s (STUArray s Int Int)
    rank   <- newArray     (0, n - 1) 0            :: ST s (STUArray s Int Int)

    -- Find the representative of x, compressing the path on the way back.
    let find :: Int -> ST s Int
        find x = do
          p <- readArray parent x
          if p == x
            then return x
            else do
              r <- find p
              writeArray parent x r   -- path compression: point x straight at the root
              return r

        -- Merge the sets of x and y, attaching the shorter tree under the taller.
        union :: Int -> Int -> ST s ()
        union x y = do
          rx <- find x
          ry <- find y
          when (rx /= ry) $ do
            rkx <- readArray rank rx
            rky <- readArray rank ry
            case compare rkx rky of
              LT -> writeArray parent rx ry
              GT -> writeArray parent ry rx
              EQ -> do writeArray parent ry rx
                       writeArray rank rx (rkx + 1)

    -- Every pair within distance 3 joins the same constellation.
    forM_ [0 .. n - 1] $ \i ->
      forM_ [i + 1 .. n - 1] $ \j ->
        when (manhattan (points ! i) (points ! j) <= 3) (union i j)

    -- The answer is the number of roots remaining.
    foldM (\acc i -> do
             p <- readArray parent i
             return (if p == i then acc + 1 else acc))
          0 [0 .. n - 1]

-- ---------------------------------------------------------------------------
-- Answers
-- ---------------------------------------------------------------------------

-- | Number of constellations.
part1 :: Puzzle -> Int
part1 = countConstellations

-- | Day 25 has no second puzzle; the final star is free once the other
-- 49 are collected.  Kept as a stub so the four-function shape (and the
-- benchmark harness) still apply.
part2 :: Puzzle -> Int
part2 _ = 0

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn "  part 2: (free star -- Merry Christmas!)"
