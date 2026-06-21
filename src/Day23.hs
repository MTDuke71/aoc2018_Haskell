{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day23
-- Description : Day 23 -- Experimental Emergency Teleportation
--
-- A swarm of /nanobots/, each with an integer position @(x,y,z)@ and a
-- /signal radius/ @r@.  A bot is /in range/ of any integer coordinate
-- within Manhattan distance @r@ of its position.
--
--   * Part 1: find the bot with the largest radius; count how many
--     bots (including itself) lie within that bot's range.
--
--   * Part 2: find the integer coordinate that is in range of the
--     /most/ bots; among all such coordinates, take the one closest to
--     the origin; report that Manhattan distance.
--
-- Concepts introduced this day:
--
--   * /Manhattan (taxicab) balls/ in 3-D.  A bot's coverage is an
--     octahedron @|x-px| + |y-py| + |z-pz| <= r@.  We never enumerate
--     points -- the whole puzzle is about reasoning over these balls.
--
--   * /Branch and bound over an octree/.  Part 2's search space is all
--     of 3-space, far too large to scan.  Instead we bound a cube,
--     compute an /upper bound/ on how many bots any point inside it
--     could see, and recursively split the most promising cube into 8
--     octants until a single cell survives.  The first 1x1x1 cube
--     pulled from the queue is provably optimal.
--
--   * 'Data.Set' as a priority queue with the search key chosen so the
--     /lexicographic/ 'Ord' on a 4-tuple encodes the whole policy:
--     most bots first, then closest to origin, then smallest cube.
--     Same Set-as-PQ pattern as Day 22's Dijkstra.
--
--   * /Point-to-box Manhattan distance/ via per-axis clamping: the
--     nearest cell of an axis-aligned box to a point costs
--     @max 0 (lo - v) (v - hi)@ per axis, summed.  This is the bound
--     that makes the branch-and-bound admissible.
module Day23
  ( -- * Types
    V3
  , Nanobot (..)
  , Puzzle

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , manhattan
  , botsInRangeOf
  ) where

import           Control.DeepSeq (NFData (..))
import           Data.Char       (isDigit)
import           Data.List       (foldl', maximumBy)
import           Data.Ord        (comparing)
import qualified Data.Set        as Set

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | An integer point in 3-space.  A plain tuple gives us 'Eq'/'Ord'
-- (lexicographic) and a ready-made 'NFData' for free.
type V3 = (Int, Int, Int)

-- | One nanobot: where it sits and how far it can signal.  Strict
-- fields (@!@) keep the parsed swarm fully evaluated -- there is no
-- benefit to deferring a handful of 'Int's, and it avoids thunks
-- piling up behind the millions of distance checks Part 2 performs.
data Nanobot = Nanobot
  { botPos :: !V3
  , botR   :: !Int
  } deriving (Eq, Show)

-- | The parsed swarm.
type Puzzle = [Nanobot]

-- | Manual 'NFData' so criterion can @deepseq@ a parsed swarm.  The
-- tuple and 'Int' both already have instances; we just chain them.
instance NFData Nanobot where
  rnf (Nanobot p r) = rnf p `seq` rnf r

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | One 'Nanobot' per line, e.g. @pos=\<1,2,3\>, r=4@ (coordinates may
-- be negative).  Rather than thread a real parser through the angle
-- brackets and commas, we blank out every character that is not a
-- digit or a minus sign, then 'words' + 'read' the four integers that
-- remain.  Simple and total for this input shape.
parseInput :: String -> Puzzle
parseInput = map parseLine . lines

-- | Parse a single line into a 'Nanobot' by pulling out its integers.
parseLine :: String -> Nanobot
parseLine s = case ints s of
  [x, y, z, r] -> Nanobot (x, y, z) r
  _            -> error ("Day23.parseLine: cannot parse " ++ show s)

-- | Every signed integer appearing in a string, left to right.  We map
-- each character to itself if it is a digit or @\'-\'@, and to a space
-- otherwise, so @'words'@ then splits the integers apart cleanly.
ints :: String -> [Int]
ints = map read . words . map keep
 where
  keep c
    | isDigit c || c == '-' = c
    | otherwise             = ' '

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

-- | Manhattan (taxicab) distance between two points.
manhattan :: V3 -> V3 -> Int
manhattan (x1, y1, z1) (x2, y2, z2) =
  abs (x1 - x2) + abs (y1 - y2) + abs (z1 - z2)

-- | How many bots have @target@ within their range (Part 1's counting
-- step, reused for clarity).
botsInRangeOf :: V3 -> Int -> Puzzle -> Int
botsInRangeOf centre r =
  length . filter (\b -> manhattan centre (botPos b) <= r)

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Find the strongest bot (largest radius) and count how many bots
-- fall inside its signal range, itself included.
part1 :: Puzzle -> Int
part1 bots =
  let strongest = maximumBy (comparing botR) bots
  in  botsInRangeOf (botPos strongest) (botR strongest) bots

-- ---------------------------------------------------------------------------
-- Part 2: branch and bound over an octree
-- ---------------------------------------------------------------------------

-- | An axis-aligned cube: its minimum corner and side length.  The
-- side is always a power of two, so halving stays integral all the way
-- down to a single cell.  A cube of side @s@ at corner @(lx,ly,lz)@
-- covers the cells @[lx .. lx+s-1]@ in each axis.
data Box = Box !V3 !Int

-- | Manhattan distance from a point to the /nearest cell/ of a box.
-- Per axis the cost is how far @v@ lies outside @[lo,hi]@ (zero if
-- inside).  Summed over axes this is the closest a bot at @p@ could be
-- to any point of the box -- so @dist <= r@ means the bot's range
-- touches the box, i.e. it /could/ cover some point inside.
distPointBox :: V3 -> Box -> Int
distPointBox (px, py, pz) (Box (lx, ly, lz) s) =
  axis px lx (lx + s - 1) + axis py ly (ly + s - 1) + axis pz lz (lz + s - 1)
 where
  axis v lo hi
    | v < lo    = lo - v
    | v > hi    = v - hi
    | otherwise = 0

-- | Manhattan distance from the origin to the nearest cell of a box.
-- For a 1x1x1 box this is just that single cell's distance to origin,
-- which is the value Part 2 ultimately reports.
distBoxOrigin :: Box -> Int
distBoxOrigin (Box (lx, ly, lz) s) = axis lx (lx + s - 1)
                                   + axis ly (ly + s - 1)
                                   + axis lz (lz + s - 1)
 where
  axis lo hi
    | lo > 0    = lo
    | hi < 0    = negate hi
    | otherwise = 0

-- | Upper bound on coverage: how many bots' ranges intersect the box.
-- No point inside the box can be seen by more bots than this, and a
-- 1x1x1 box's bound is its exact coverage.
boxBound :: Puzzle -> Box -> Int
boxBound bots box = foldl' step 0 bots
 where
  step !acc (Nanobot p r)
    | distPointBox p box <= r = acc + 1
    | otherwise               = acc

-- | Split a cube into its eight half-size octants.
subdivide :: Box -> [Box]
subdivide (Box (lx, ly, lz) s) =
  [ Box (lx + dx, ly + dy, lz + dz) h
  | dx <- [0, h], dy <- [0, h], dz <- [0, h]
  ]
 where
  h = s `div` 2

-- | The smallest power-of-two cube that contains every bot position.
initialBox :: Puzzle -> Box
initialBox bots = Box (mnx, mny, mnz) size
 where
  xs            = [ x | Nanobot (x, _, _) _ <- bots ]
  ys            = [ y | Nanobot (_, y, _) _ <- bots ]
  zs            = [ z | Nanobot (_, _, z) _ <- bots ]
  (mnx, mny, mnz) = (minimum xs, minimum ys, minimum zs)
  extent        = maximum [ maximum xs - mnx
                          , maximum ys - mny
                          , maximum zs - mnz ]
  -- smallest power of two strictly greater than the extent, so the cube
  -- [mn .. mn+size-1] covers [mn .. mx] in every axis.
  size          = head (dropWhile (<= extent) (iterate (* 2) 1))

-- | The priority-queue key.  Lexicographic 'Ord' on this 4-tuple is
-- the entire search policy, smallest-first:
--
--   1. @negate count@  -- most bots first (largest coverage bound);
--   2. @distToOrigin@  -- ties broken toward the origin;
--   3. @size@          -- then prefer the smaller (more resolved) cube;
--   4. @corner@        -- final tiebreak, only to keep keys unique.
--
-- Storing @size@ and @corner@ lets us rebuild the 'Box' on pop without
-- a side table.
type Key = (Int, Int, Int, V3)

key :: Puzzle -> Box -> Key
key bots box@(Box lo s) =
  (negate (boxBound bots box), distBoxOrigin box, s, lo)

-- | Part 2.  Branch and bound: always expand the most promising cube.
-- Because the coverage bound only shrinks and the origin distance only
-- grows as cubes get smaller, the first 1x1x1 cube to reach the front
-- of the queue maximises coverage and, among those, minimises distance
-- to the origin -- exactly what the puzzle asks for.
part2 :: Puzzle -> Int
part2 bots = go (Set.singleton (key bots (initialBox bots)))
 where
  go pq = case Set.minView pq of
    Nothing -> error "Day23.part2: queue emptied without a 1x1x1 box"
    Just ((_, d, s, lo), rest)
      | s == 1    -> d
      | otherwise ->
          let children = subdivide (Box lo s)
              pq'      = foldl' (\q b -> Set.insert (key bots b) q) rest children
          in  go pq'

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
