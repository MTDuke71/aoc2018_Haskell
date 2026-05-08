-- |
-- Module      : Day07
-- Description : Day 07 -- The Sum of Its Parts
--
-- The puzzle input is a list of dependency edges of the form
-- @"Step X must be finished before step Y can begin."@.  Each step is
-- a single uppercase letter.
--
-- Part 1: produce the order in which the steps must be completed,
--         breaking ties between simultaneously-ready steps in
--         alphabetical order.
-- Part 2: simulate five workers cooperating on the same dependency
--         graph, where step @c@ takes @60 + (c - \'A\' + 1)@ seconds.
--         Report the total time to finish.
--
-- Concepts introduced this day:
--   * Graph-as-'Map' representation: a step's value is the 'Set' of
--     steps that must finish before it.  "Ready" steps are exactly the
--     keys whose value 'Set' is empty -- 'Map.toAscList' then gives
--     them in alphabetical order for free.
--   * Topological sort by repeated alphabetical-priority pick.  No
--     queue, no Kahn's-algorithm bookkeeping -- the 'Map' /is/ the
--     queue, because alphabetical order is the natural 'Ord' on 'Char'.
--   * Discrete-event simulation in pure Haskell: instead of a 'while'
--     loop with mutable workers, the simulator is a recursive function
--     that threads @(now, prereqs, busyWorkers)@ through its arguments
--     and jumps directly to the next worker-finish time.
--   * 'Data.List.partition' for one-pass split into matches and
--     non-matches; 'Map.fromSet' for seeding a map of empty sets keyed
--     by every node in one allocation.

module Day07
  ( Edge
  , parseInput
  , prereqs
  , topoOrder
  , stepDuration
  , finishTime
  , part1
  , part2
  , solve
  ) where

import           Data.Char        (ord)
import           Data.List        (foldl', partition)
import qualified Data.Map.Strict  as Map
import           Data.Map.Strict  (Map)
import qualified Data.Set         as Set
import           Data.Set         (Set)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A dependency edge @(a, b)@ reads "step @a@ must finish before
--   step @b@ can begin."
type Edge = (Char, Char)

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Each line has exactly the shape
--   @"Step X must be finished before step Y can begin."@ -- ten
--   whitespace-separated words, with the prerequisite letter in word
--   index 1 and the dependent letter in word index 7.
--
--   The pattern @[a]@ matches a single-character 'String' and binds
--   the lone 'Char' to @a@.  Any line that does not split into ten
--   words with single-letter slots in those positions falls through to
--   the @_ -> error ...@ arm, which is enough safety for trusted AoC
--   input.
parseInput :: String -> [Edge]
parseInput = map parseLine . lines
  where
    parseLine :: String -> Edge
    parseLine line = case words line of
      [_, [a], _, _, _, _, _, [b], _, _] -> (a, b)
      _ -> error ("Day07.parseInput: bad line " ++ show line)

-- ---------------------------------------------------------------------------
-- Graph: prereq map
-- ---------------------------------------------------------------------------

-- | Reverse-adjacency representation: every step that appears anywhere
--   in the edge list becomes a key, and its value is the 'Set' of
--   steps that must finish before it.  Steps with no prereqs (sources)
--   keep an empty 'Set'.
--
--   Why this shape rather than a forward-adjacency map?  Both Part 1
--   and Part 2 repeatedly ask the question "which steps are ready?",
--   which is "which keys map to an empty 'Set'?".  Having the
--   prereqs-of relation already inverted makes that query trivial
--   ('Set.null' on the value), and it lets us "complete" a step by
--   walking the map once and removing the step from every value 'Set'.
prereqs :: [Edge] -> Map Char (Set Char)
prereqs es = foldl' insertEdge seed es
  where
    -- Seed the map with every node that appears as either endpoint,
    -- each starting with an empty prereq set.  Without this seed,
    -- source nodes (those that never appear on the right-hand side of
    -- any edge) would be missing keys, and the topo-sort loop below
    -- would never see them as candidates.
    seed :: Map Char (Set Char)
    seed = Map.fromSet (const Set.empty)
                       (Set.fromList ([a | (a, _) <- es] ++ [b | (_, b) <- es]))

    -- For each edge @(a, b)@, append @a@ to @b@'s prereq set.
    insertEdge :: Map Char (Set Char) -> Edge -> Map Char (Set Char)
    insertEdge m (a, b) = Map.insertWith Set.union b (Set.singleton a) m

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Repeatedly pick the alphabetically smallest step whose prereq set
--   is empty, append it to the output, then delete it as a key and as
--   a member of every other prereq set.  Returns the step letters in
--   completion order.
topoOrder :: [Edge] -> String
topoOrder = go . prereqs
  where
    go :: Map Char (Set Char) -> String
    go pre
      | Map.null pre = []
      | otherwise =
          case [c | (c, ps) <- Map.toAscList pre, Set.null ps] of
            []      -> error "Day07.topoOrder: cycle (no ready steps)"
            (s : _) -> s : go (Map.map (Set.delete s) (Map.delete s pre))

part1 :: [Edge] -> String
part1 = topoOrder

-- ---------------------------------------------------------------------------
-- Part 2: parallel-worker simulation
-- ---------------------------------------------------------------------------

-- | Time to complete step @c@: a fixed @base@ plus @1@ for @\'A\'@,
--   @2@ for @\'B\'@, ..., @26@ for @\'Z\'@.  The puzzle uses
--   @base = 60@.
stepDuration :: Int -> Char -> Int
stepDuration base c = base + (ord c - ord 'A' + 1)

-- | Finish time for @numWorkers@ workers cooperating on the dependency
--   graph, with each step taking @stepDuration base@ seconds.
--
--   The simulation is a tail-recursive @go@ over three pieces of state:
--
--   * @now@   -- the current simulation clock.
--   * @pre@   -- the prereq map of /not-yet-started/ steps.  When a
--                worker picks up a step, that step's key is removed
--                from @pre@ immediately, so it is never picked twice.
--   * @busy@  -- the list of in-progress @(step, finishTime)@ pairs.
--
--   On each iteration we (1) assign every available ready step to a
--   free worker in alphabetical order, (2) jump @now@ forward to the
--   nearest finish event, (3) remove the just-finished steps from
--   every other step's prereq set, and (4) recurse.  The simulation
--   ends when both @pre@ and @busy@ are empty -- everyone is idle and
--   nothing is left to do.
finishTime :: Int -> Int -> [Edge] -> Int
finishTime numWorkers base es = go 0 (prereqs es) []
  where
    go :: Int -> Map Char (Set Char) -> [(Char, Int)] -> Int
    go now pre busy =
      let free   = numWorkers - length busy
          ready  = take free [c | (c, ps) <- Map.toAscList pre, Set.null ps]
          pre'   = foldl' (flip Map.delete) pre ready
          busy'  = busy ++ [(c, now + stepDuration base c) | c <- ready]
      in case busy' of
           [] -> now           -- pre and busy both empty: everything is done
           _  ->
             let nextTime              = minimum [t | (_, t) <- busy']
                 (finishing, stillBusy) = partition (\(_, t) -> t == nextTime) busy'
                 pre''                 = foldl' removeFinished pre' finishing
             in go nextTime pre'' stillBusy

    removeFinished :: Map Char (Set Char) -> (Char, Int) -> Map Char (Set Char)
    removeFinished m (c, _) = Map.map (Set.delete c) m

-- | Part 2 with the puzzle's canonical parameters: 5 workers, 60-second
--   base step duration.
part2 :: [Edge] -> Int
part2 = finishTime 5 60

-- ---------------------------------------------------------------------------
-- IO entry point
-- ---------------------------------------------------------------------------

-- | Parse once, print both answers.
solve :: String -> IO ()
solve contents = do
  let es = parseInput contents
  putStrLn ("  part 1: " ++ part1 es)
  putStrLn ("  part 2: " ++ show (part2 es))
