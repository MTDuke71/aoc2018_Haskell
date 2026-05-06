-- |
-- Module      : Day06
-- Description : Day 06 — Chronal Coordinates
--
-- A list of integer (x, y) coordinates is given.  Using Manhattan
-- distance, every integer cell of the plane is "owned" by the closest
-- input coordinate -- unless two coordinates are equally close, in
-- which case the cell has no owner.
--
-- Part 1: among the input coordinates whose Voronoi region is /finite/,
--         report the size of the largest region.
-- Part 2: report the number of cells whose total Manhattan distance to
--         /every/ input coordinate is strictly less than 10000.
--
-- Concepts introduced this day:
--   * Bounding-box reasoning -- "any owner that reaches the bounding-box
--     border has an infinite Voronoi region" is the algorithmic key to
--     Part 1, and it's what lets us search a finite grid instead of an
--     infinite plane.
--   * Manhattan-distance Voronoi without a flood-fill -- one direct
--     distance computation per (cell, coord) pair, plus a tie check.
--   * 'Data.Set' as the "exclusion list" of indices that we already
--     know to be infinite-area; membership test is O(log n).

module Day06
  ( Coord
  , parseInput
  , manhattan
  , bounds
  , gridCells
  , borderCells
  , closest
  , totalDistance
  , safeRegionSize
  , part1
  , part2
  , solve
  ) where

import           Data.List           (sort)
import qualified Data.Map.Strict     as Map
import qualified Data.Set            as Set
import           Data.Maybe          (mapMaybe)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | An input point or grid cell, as @(x, y)@.  A bare tuple is enough
--   here -- there are only two coordinates and no other fields to carry.
type Coord = (Int, Int)

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Each line is @"x, y"@.  Split on the comma and 'read' both halves.
parseInput :: String -> [Coord]
parseInput = map parseLine . lines
  where
    parseLine :: String -> Coord
    parseLine line = case break (== ',') line of
      (xs, ',' : ' ' : ys) -> (read xs, read ys)
      _                    -> error ("Day06.parseInput: bad line " ++ show line)

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

-- | Manhattan (taxicab) distance between two cells.
manhattan :: Coord -> Coord -> Int
manhattan (x1, y1) (x2, y2) = abs (x1 - x2) + abs (y1 - y2)

-- | Bounding box of a non-empty list of points: @(xMin, xMax, yMin, yMax)@.
bounds :: [Coord] -> (Int, Int, Int, Int)
bounds cs = (minimum xs, maximum xs, minimum ys, maximum ys)
  where
    xs = map fst cs
    ys = map snd cs

-- | All integer cells inside the inclusive bounding box.
gridCells :: (Int, Int, Int, Int) -> [Coord]
gridCells (xMin, xMax, yMin, yMax) =
  [(x, y) | x <- [xMin .. xMax], y <- [yMin .. yMax]]

-- | The cells lying on the border of the inclusive bounding box.
--   These are exactly the cells where x or y matches the box extremes.
borderCells :: (Int, Int, Int, Int) -> [Coord]
borderCells (xMin, xMax, yMin, yMax) =
  [ (x, y)
  | x <- [xMin .. xMax]
  , y <- [yMin .. yMax]
  , x == xMin || x == xMax || y == yMin || y == yMax
  ]

-- ---------------------------------------------------------------------------
-- Closest-coordinate logic (Part 1)
-- ---------------------------------------------------------------------------

-- | For a given cell, the index of the unique closest input coordinate,
--   or 'Nothing' if two or more coordinates are tied at the minimum
--   distance.
--
--   The list comprehension pairs each input coord with its index, then
--   computes its distance to the cell.  After 'sort' (which orders
--   pairs lexicographically -- distance first, index second), the head
--   is the smallest distance.  If the head and the next element share a
--   distance, the cell has a tie and no owner.
closest :: [Coord] -> Coord -> Maybe Int
closest cs cell = case sorted of
  []                                     -> Nothing
  [(_, i)]                               -> Just i
  (d1, i1) : (d2, _) : _
    | d1 == d2  -> Nothing               -- tie at the minimum: no owner
    | otherwise -> Just i1               -- unique closest: index wins
  where
    sorted :: [(Int, Int)]
    sorted = sort [(manhattan c cell, i) | (i, c) <- zip [0 ..] cs]

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Largest finite Voronoi-region size.
--
--   Strategy:
--
--   1. Compute the bounding box of the input coords.
--   2. For every cell inside the box, determine its owner index (if
--      any).
--   3. The set of \"infinite\" indices is exactly the set of owners
--      that occur on the /border/ of the bounding box: any region that
--      touches the box border continues to grow forever in that
--      direction, so its area is unbounded.  Indices that never own a
--      border cell have all of their territory inside the box.
--   4. Tally cell counts per index, drop the infinite ones, take the
--      maximum.
part1 :: [Coord] -> Int
part1 cs
  | null cs   = 0
  | otherwise = if Map.null counts then 0 else maximum (Map.elems counts)
  where
    bb       :: (Int, Int, Int, Int)
    bb       = bounds cs

    -- Owner index per cell, dropping ties (cells with no owner).
    cellOwners :: [Int]
    cellOwners = mapMaybe (closest cs) (gridCells bb)

    -- Indices whose Voronoi region touches the border -> infinite area.
    infinite :: Set.Set Int
    infinite = Set.fromList (mapMaybe (closest cs) (borderCells bb))

    -- Cell counts for every finite-area owner.
    counts :: Map.Map Int Int
    counts = Map.fromListWith (+)
               [ (i, 1) | i <- cellOwners, not (i `Set.member` infinite) ]

-- ---------------------------------------------------------------------------
-- Part 2
-- ---------------------------------------------------------------------------

-- | Sum of Manhattan distances from a cell to every input coord.
totalDistance :: [Coord] -> Coord -> Int
totalDistance cs cell = sum [manhattan c cell | c <- cs]

-- | Number of cells whose total distance is strictly less than the
--   given threshold.
--
--   The safe region is convex (it is an intersection of half-planes
--   under the L1 metric) and, crucially, it lives /inside/ the input
--   bounding box for every realistic (threshold, input) pair: outside
--   the bounding box, every input coord is on the same side of the
--   cell, so moving farther outward adds at least @length cs@ to the
--   total distance for each step.  The puzzle's threshold of 10 000 is
--   small enough relative to the input that the safe region is
--   comfortably bounded.
safeRegionSize :: Int -> [Coord] -> Int
safeRegionSize threshold cs =
  length [ () | cell <- gridCells (bounds cs)
              , totalDistance cs cell < threshold ]

-- | Part 2 with the puzzle's canonical threshold of 10 000.
part2 :: [Coord] -> Int
part2 = safeRegionSize 10000

-- ---------------------------------------------------------------------------
-- IO entry point
-- ---------------------------------------------------------------------------

-- | Print both answers.
solve :: String -> IO ()
solve contents = do
  let cs = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 cs))
  putStrLn ("  part 2: " ++ show (part2 cs))
