{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day22
-- Description : Day 22 -- Mode Maze
--
-- A cave of square regions, each /rocky/, /wet/, or /narrow/.  The
-- type of a region is derived from its /erosion level/, which is
-- derived from its /geologic index/, which (away from the edges)
-- is the product of the erosion levels of the regions to the left
-- and above -- a classic two-neighbour dynamic-programming
-- recurrence.
--
--   * Part 1: sum of region types (0\/1\/2) over the rectangle from
--     the mouth @(0,0)@ to the target.
--   * Part 2: fewest minutes from the mouth (holding the torch) to
--     the target (holding the torch), where moving costs 1 minute,
--     switching tools costs 7, and each region type forbids one of
--     the three tools.
--
-- Concepts introduced this day:
--
--   * /Knot-tying memoization/: a lazy boxed 'Array' whose elements
--     are defined in terms of other elements of the same array.
--     Laziness turns the DP recurrence into a memo table with no
--     explicit evaluation order -- demand a cell and its
--     dependencies compute themselves, each exactly once.
--
--   * /Dijkstra's algorithm/ (uniform-cost search), the weighted
--     cousin of the BFS from Days 15 and 20.  Edge costs of 1 and 7
--     mean a FIFO queue no longer visits states in distance order;
--     a priority queue does.
--
--   * 'Data.Set' as a priority queue with /lazy deletion/:
--     'Set.minView' pops the smallest @(distance, state)@ pair, and
--     instead of decrease-key we insert duplicates and skip states
--     already settled.
--
--   * A /layered state graph/ (graph product): the search space is
--     not the grid but grid x tool.  Same trick as adding a
--     "direction" or "keys held" dimension in other path puzzles.
module Day22
  ( -- * Types
    Puzzle (..)
  , Tool (..)

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , erosionGrid
  , regionAt
  , part2Padded
  ) where

import           Control.DeepSeq (NFData (..))
import           Data.Array      (Array, listArray, range, (!))
import           Data.List       (foldl')
import qualified Data.Set        as Set

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The scan: cave depth and target coordinates.  That is the whole
-- input -- the map itself is /computed/, not given.
data Puzzle = Puzzle
  { depth  :: !Int        -- ^ cave system depth (erosion-level offset)
  , target :: !(Int, Int) -- ^ target coordinates @(x, y)@
  }
  deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle d t) = rnf d `seq` rnf t

-- | The three tools.  The 'Enum' encoding is chosen so that a tool
-- is forbidden exactly in the region type with /its own/ number:
-- rocky (0) forbids 'Neither', wet (1) forbids 'Torch', narrow (2)
-- forbids 'ClimbingGear'.  "Tool usable here" is then one
-- comparison: @fromEnum tool /= regionType@.
data Tool = Neither | Torch | ClimbingGear
  deriving (Eq, Ord, Show, Enum, Bounded)

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Two fixed-format lines:
--
-- > depth: 7740
-- > target: 12,763
parseInput :: String -> Puzzle
parseInput raw = case lines raw of
  (depthLine : targetLine : _) ->
    let d        = read (dropLabel depthLine)
        (xs, ys) = break (== ',') (dropLabel targetLine)
    in  Puzzle d (read xs, read (drop 1 ys))
  _ -> error "Day22.parseInput: expected 'depth:' and 'target:' lines"
 where
  -- everything after the ": " -- works for both labels
  dropLabel = drop 2 . dropWhile (/= ':')

-- ---------------------------------------------------------------------------
-- The erosion grid (knot-tying memoization)
-- ---------------------------------------------------------------------------

-- | Erosion levels for every region in the rectangle @(0,0)..(mx,my)@.
--
-- The array is /defined in terms of itself/: the @otherwise@ branch
-- of 'geo' reads @grid ! (x-1, y)@ and @grid ! (x, y-1)@ -- cells of
-- the very array being constructed.  This is safe because 'Array'
-- (the boxed, lazy one -- not 'Data.Array.Unboxed.UArray') stores
-- each element as a thunk: demanding cell @(x,y)@ forces its two
-- neighbours, which force theirs, and so on back to the axes.  Each
-- cell is computed at most once and cached in place -- a memo table
-- where laziness does the dependency scheduling.
erosionGrid :: Puzzle -> (Int, Int) -> Array (Int, Int) Int
erosionGrid (Puzzle d (tx, ty)) (mx, my) = grid
 where
  bnds = ((0, 0), (mx, my))
  grid = listArray bnds [ level x y | (x, y) <- range bnds ]

  level x y = (geo x y + d) `mod` 20183

  geo x y
    | x == 0 && y == 0   = 0
    | x == tx && y == ty = 0
    | y == 0             = x * 16807
    | x == 0             = y * 48271
    | otherwise          = grid ! (x - 1, y) * grid ! (x, y - 1)

-- | Region type at a coordinate: 0 = rocky, 1 = wet, 2 = narrow.
-- Just the erosion level mod 3; exposed for the prose spot-checks
-- in the tests.
regionAt :: Array (Int, Int) Int -> (Int, Int) -> Int
regionAt grid pos = grid ! pos `mod` 3

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Total risk of the mouth-to-target rectangle.  Risk per region
-- equals its type number, so this is one pass over the grid.
part1 :: Puzzle -> Int
part1 puzzle@(Puzzle _ (tx, ty)) =
  sum [ regionAt grid pos | pos <- range ((0, 0), (tx, ty)) ]
 where
  grid = erosionGrid puzzle (tx, ty)

-- ---------------------------------------------------------------------------
-- Part 2 (Dijkstra over position x tool)
-- ---------------------------------------------------------------------------

-- | A search state: where you are and what you hold.  The derived
-- 'Ord' makes @(distance, State)@ pairs sortable, which is all the
-- Set-as-priority-queue needs.
type State = ((Int, Int), Tool)

-- | Fewest minutes from @((0,0), Torch)@ to @(target, Torch)@.
--
-- The grid is conceptually unbounded to the right and below, so we
-- compute erosion on a rectangle padded beyond the target and let
-- Dijkstra treat the pad edge as a wall.  An optimal path strays at
-- most a bounded distance past the target (every extra column or
-- row costs 2 minutes there-and-back); a pad of 100 is far beyond
-- that for real inputs, and the answer is verified stable against a
-- larger pad in the tests.
part2 :: Puzzle -> Int
part2 = part2Padded 100

-- | 'part2' with an explicit pad, so tests can check the answer
-- does not depend on the cutoff.
part2Padded :: Int -> Puzzle -> Int
part2Padded pad puzzle@(Puzzle _ (tx, ty)) =
  go (Set.singleton (0, start)) Set.empty
 where
  (mx, my) = (tx + pad, ty + pad)
  grid     = erosionGrid puzzle (mx, my)

  start, goal :: State
  start = ((0, 0), Torch)
  goal  = ((tx, ty), Torch)

  -- Dijkstra with lazy deletion.  The frontier is a Set of
  -- (distance, state) pairs ordered by distance first; 'minView'
  -- pops the closest.  A state may sit in the frontier several
  -- times with different distances -- only the first (smallest) pop
  -- counts, later ones are skipped via the settled set.  The first
  -- time the goal is popped, its distance is final: that is
  -- Dijkstra's invariant.
  go :: Set.Set (Int, State) -> Set.Set State -> Int
  go frontier settled = case Set.minView frontier of
    Nothing -> error "Day22.part2: goal unreachable (pad too small?)"
    Just ((dist, st), rest)
      | st == goal              -> dist
      | st `Set.member` settled -> go rest settled
      | otherwise ->
          let settled' = Set.insert st settled
              fresh    = [ (dist + cost, st')
                         | (cost, st') <- moves st
                         , not (st' `Set.member` settled') ]
              !frontier' = foldl' (flip Set.insert) rest fresh
          in  go frontier' settled'

  -- All single actions from a state: switch to the other tool valid
  -- in this region (7 minutes), or step to an in-bounds neighbour
  -- where the current tool is still valid (1 minute).
  moves :: State -> [(Int, State)]
  moves (pos@(x, y), tool) =
    [ (7, (pos, tool'))
    | tool' <- [minBound .. maxBound]
    , tool' /= tool
    , fromEnum tool' /= regionAt grid pos
    ]
      ++
    [ (1, (pos', tool))
    | pos'@(x', y') <- [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
    , x' >= 0, y' >= 0, x' <= mx, y' <= my
    , fromEnum tool /= regionAt grid pos'
    ]

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
