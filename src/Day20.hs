{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day20
-- Description : Day 20 -- A Regular Map
--
-- An /exploration regex/ of @N@/@S@/@E@/@W@ direction characters,
-- with branches @(a|b|...)@, tracing every path through a facility
-- of rooms separated by doors.  The job is to /build the door
-- graph/, then BFS from the origin:
--
--   * Part 1: the largest shortest-path distance (the room
--     "furthest" from you, measured in doors).
--   * Part 2: how many rooms have a shortest path of at least 1000
--     doors.
--
-- Concepts introduced this day:
--
--   * Streaming regex evaluation with a /position stack/.  We never
--     parse the regex into a syntax tree -- a single left-to-right
--     fold suffices.  One stack entry per open paren remembers the
--     position to /reset/ to on @'|'@ and to /continue from/ on
--     @')'@.  Correct for AoC's "detour and return" regex shape,
--     where every branch ends at the position the group started in.
--
--   * Door graph as a symmetric @'Map' 'Pos' ['Pos']@.  Edges live
--     first in a 'Set' of canonicalised unordered pairs (smaller
--     coordinate first), so walking the same corridor from both
--     ends does not double-count.  The final adjacency map is then
--     built by 'Map.fromListWith' (@++@).
--
--   * BFS over a 'Map'-keyed graph using 'Data.Sequence' as the
--     queue.  The visited table doubles as the distance map: a key
--     is in the map iff it has been dequeued, with value = its
--     shortest distance from the origin.
module Day20
  ( -- * Types
    Pos
  , Puzzle (..)

    -- * Public answers
  , parseInput
  , part1
  , part2
  , facilitySize
  , solve

    -- * Building blocks (exposed for tests)
  , buildDoors
  , distances
  ) where

import           Control.DeepSeq    (NFData (..))
import           Data.List          (foldl')
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Sequence      (ViewL (..), (|>))
import qualified Data.Sequence      as Seq
import qualified Data.Set           as Set

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A room coordinate.  @(0,0)@ is the starting room; the puzzle's
-- orientation (N decreases @y@, etc.) is irrelevant -- only the
-- /graph/ structure matters for the answers.
type Pos = (Int, Int)

-- | Parsed input: the door graph as an adjacency map.  Wrapped in a
-- @newtype@ so we can pin an 'NFData' instance (the stock
-- @NFData (Map k v)@ already forces both spine and elements; the
-- wrapper just lets criterion deepseq the puzzle without lifting it
-- to @Map@ at every call site).
newtype Puzzle = Puzzle { doors :: Map Pos [Pos] }
  deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle m) = rnf m

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Strip whitespace from the input and feed the regex body to
-- 'buildDoors'.  The puzzle file is one long regex; trailing newlines
-- (and any incidental spaces) would confuse the @'^'@/@'$'@ sentinels.
parseInput :: String -> Puzzle
parseInput = Puzzle . buildDoors . filter (`notElem` " \t\r\n")

-- | Walk the regex left to right, accumulating a door graph.
--
-- The fold state is a triple:
--
--   * @pos@   -- the "current" room, advanced by each direction step.
--   * @stack@ -- one saved position per open paren.  @'('@ pushes
--                the current @pos@; @'|'@ resets @pos@ to the top
--                (so the next branch /starts/ where this group
--                started); @')'@ pops (so navigation /after/ the
--                group continues from the group's start).
--   * @es@    -- the door set so far, with each unordered pair
--                stored canonically (smaller endpoint first).
--
-- The "reset to top on @|@, pop on @)@" convention is the well-known
-- shortcut for AoC's regex shape: every branch in the puzzle returns
-- to its starting position (either it's a detour like @(NEWS|)@ with
-- an empty alternative, or all branches end at the same room by
-- construction).  Under that assumption tracking a single position
-- is enough; we never need a /set/ of "possible current rooms".
buildDoors :: String -> Map Pos [Pos]
buildDoors regex =
  Map.fromListWith (++)
    [ kv
    | (a, b) <- Set.toList edges
    , kv     <- [(a, [b]), (b, [a])]
    ]
 where
  (_, _, edges) = foldl' step ((0, 0), [], Set.empty) regex

  step (!pos, !stack, !es) c = case c of
    '^' -> (pos, stack, es)
    '$' -> (pos, stack, es)
    '(' -> (pos, pos : stack, es)
    '|' -> case stack of
             (p : _) -> (p, stack, es)
             []      -> error "Day20.buildDoors: '|' outside group"
    ')' -> case stack of
             (p : rest) -> (p, rest, es)
             []         -> error "Day20.buildDoors: unmatched ')'"
    d   -> let !pos' = step1 d pos
               !edge = if pos <= pos' then (pos, pos') else (pos', pos)
           in  (pos', stack, Set.insert edge es)

  step1 :: Char -> Pos -> Pos
  step1 'N' (x, y) = (x, y - 1)
  step1 'S' (x, y) = (x, y + 1)
  step1 'W' (x, y) = (x - 1, y)
  step1 'E' (x, y) = (x + 1, y)
  step1 c   _      = error ("Day20.buildDoors: bad direction: " ++ show c)

-- ---------------------------------------------------------------------------
-- BFS
-- ---------------------------------------------------------------------------

-- | Shortest-path distance from the origin to every reachable room.
--
-- Plain breadth-first search.  The queue is a 'Data.Sequence' for
-- @O(1)@ head-view and amortised @O(1)@ snoc; the @visited / distance@
-- map is a single 'Map.Map' -- presence in the map means "already
-- dequeued", and the stored value is its distance.  Each room is
-- inserted exactly once.
distances :: Puzzle -> Map Pos Int
distances (Puzzle adj) = go (Map.singleton (0, 0) 0) (Seq.singleton (0, 0))
 where
  go !dist q = case Seq.viewl q of
    EmptyL    -> dist
    p :< rest ->
      let d      = dist Map.! p
          ns     = [ n | n <- Map.findWithDefault [] p adj
                       , not (Map.member n dist) ]
          !dist' = foldl' (\m n -> Map.insert n (d + 1) m) dist ns
          !q'    = foldl' (|>) rest ns
      in  go dist' q'

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

-- | The largest shortest-path distance from the origin -- the room
-- requiring the most doors to reach.
part1 :: Puzzle -> Int
part1 = maximum . Map.elems . distances

-- | Number of rooms whose shortest distance from the origin is at
-- least 1000 doors.
part2 :: Puzzle -> Int
part2 = length . filter (>= 1000) . Map.elems . distances

-- | Total number of rooms in the facility -- i.e. every room the
-- regex describes.  The BFS reaches all of them (the door graph is
-- connected, rooted at the origin), so the count is just the size of
-- the distance map.  Not a puzzle answer; exposed because "how big is
-- the whole place?" is the natural follow-up question to Parts 1/2.
facilitySize :: Puzzle -> Int
facilitySize = Map.size . distances

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
      d      = distances puzzle      -- one BFS, shared by both parts
  putStrLn ("  part 1: " ++ show (maximum (Map.elems d)))
  putStrLn ("  part 2: " ++ show (length (filter (>= 1000) (Map.elems d))))
  putStrLn ("  rooms in facility: " ++ show (Map.size d))
