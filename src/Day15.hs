{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day15
-- Description : Day 15 -- Beverage Bandits
--
-- Goblins (@G@) and Elves (@E@) fight inside a cave of walls (@#@) and
-- open floor (@.@).  Every unit has 200 hit points and 3 attack power.
-- Combat proceeds in /rounds/.  In a round, every unit -- in the
-- /reading order/ (top-to-bottom, then left-to-right) of its position
-- /at the start of the round/ -- takes a turn:
--
--   1. If no enemies remain, combat ends immediately.
--   2. If already adjacent to an enemy, skip the move.
--   3. Otherwise move one step along a shortest path toward the
--      nearest reachable square that is in range of (adjacent to) some
--      enemy.  Every tie -- which target square, and which first step
--      -- is broken by /reading order/.
--   4. After moving, if adjacent to an enemy, attack the adjacent
--      enemy with the fewest hit points (reading order breaks ties),
--      dealing @attack power@ damage.  At 0 HP the target dies and
--      vanishes from the map.
--
-- Part 1: run combat to the end with every unit at attack power 3.
-- The /outcome/ is @(full rounds completed) * (sum of remaining HP)@.
-- A round only counts if /every/ unit completed its turn; the round
-- in which a unit finds no targets does not count.
--
-- Part 2: Goblins keep attack power 3.  Find the /lowest/ Elf attack
-- power at which the Elves win with /no Elf deaths/, and report that
-- battle's outcome.
--
-- The algorithmic heart of the day is a breadth-first shortest-path
-- search with strict lexicographic ('reading order') tie-breaking,
-- run /twice/ per moving unit: once from the unit to choose the
-- destination square, and once from that square to choose the first
-- step.  This is the same asynchronous reading-order family as Day 13
-- (carts), but now the unit's action depends on a graph search over
-- the live board, not just a local rule.
--
-- Concepts introduced this day:
--
--   * Breadth-first search returning a /distance map/
--     (@Map Pos Int@), then resolving ties with @minimum@ over
--     @(distance, position)@ tuples.  Because positions are stored
--     @(y, x)@, the derived 'Ord' on the pair /is/ reading order, so
--     correct tie-breaking is just "take the minimum".
--
--   * The two-BFS shortest-step technique.  Knowing the nearest
--     reachable in-range square is not enough; the unit must step
--     onto the reading-order-first cell that lies on /some/ shortest
--     path to it.  A second BFS from the chosen square turns that
--     into another @minimum@ over @(distance, position)@.
--
--   * A pure simulation parameterised by a knob (Elf attack power)
--     and an /early-abort/ predicate (stop the moment an Elf dies).
--     Part 2 is a linear search over that knob; the abort makes the
--     doomed attempts cheap.
module Day15
  ( -- * Types
    Puzzle (..)
  , Kind (..)
  , Unit (..)
  , Pos

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , bfs
  , outcomeAt
  , lowestNoDeathOutcome
  ) where

import           Control.DeepSeq    (NFData (..))
import           Data.Array.Unboxed (UArray, bounds, listArray, (!))
import           Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IM
import           Data.List          (foldl', sortOn)
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Maybe         (mapMaybe)
import qualified Data.Set           as Set

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A board coordinate, stored @(row, col)@ == @(y, x)@.  Storing
-- @y@ first means the standard 'Ord' instance on the pair sorts in
-- /reading order/: smaller row first, then smaller column.  Every
-- tie-break in the puzzle is "first in reading order", so it reduces
-- to @minimum@ / @sortOn@ on this type with no custom comparator.
type Pos = (Int, Int)

-- | Which faction a unit belongs to.  An enum-style sum type: the
-- constructors carry no data, they are just tags (compare Day 13's
-- 'Dir' / 'Turn').
data Kind = Goblin | Elf deriving (Eq, Show)

instance NFData Kind where rnf !_ = ()

-- | One combatant.  All fields strict: HP is decremented every hit
-- and position is rewritten every move, so a lazy field would build
-- a thunk tower over thousands of turns.
data Unit = Unit
  { upos  :: !Pos
  , ukind :: !Kind
  , uhp   :: !Int
  } deriving (Eq, Show)

instance NFData Unit where
  rnf (Unit a b c) = a `seq` rnf b `seq` c `seq` ()

-- | Parsed input: the static terrain plus the initial units.
--
--   * 'grid' is @True@ for open floor (a unit /could/ stand here,
--     terrain-wise) and @False@ for wall.  It never changes during
--     combat -- only unit occupancy does, and that is tracked
--     separately as a @Map Pos Int@ rebuilt per turn.
--   * 'units0' lists the units in reading order of their starting
--     positions (the parser walks rows then columns), which is also
--     the id order used by the simulation's 'IntMap'.
data Puzzle = Puzzle
  { grid   :: !(UArray Pos Bool)
  , units0 :: ![Unit]
  } deriving (Eq, Show)

-- | @array@ ships no @NFData (UArray i e)@ for the pinned versions,
-- so 'grid' gets a plain 'seq' (a 'UArray' is spine-strict, so this
-- fully forces it).  'units0' is an ordinary list of strict records.
instance NFData Puzzle where
  rnf (Puzzle a b) = a `seq` rnf b

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse the ASCII map.
--
-- Rows are right-padded to the maximum width with @'#'@ so the grid
-- is a true rectangle (AoC inputs already have a solid wall border,
-- but padding makes the array bounds total regardless).  @'.'@, @'G'@
-- and @'E'@ are open floor (@True@); @'#'@ and padding are wall
-- (@False@).  Units are emitted in row-major order, so 'units0' is
-- already in reading order.
parseInput :: String -> Puzzle
parseInput raw =
  let rows0  = filter (not . null) (lines raw)
      h      = length rows0
      w      = maximum (1 : map length rows0)
      padded = [ r ++ replicate (w - length r) '#' | r <- rows0 ]
      tagged = [ ((y, x), c)
               | (y, row) <- zip [0 ..] padded
               , (x, c)   <- zip [0 ..] row
               ]
      -- 'mapMaybe' keeps only the Just results: cells that are units.
      us     = mapMaybe (\(p, c) -> (\k -> Unit p k 200) <$> kindOf c) tagged
      cells  = [ c /= '#' | (_, c) <- tagged ]
      arr    = listArray ((0, 0), (h - 1, w - 1)) cells
                 :: UArray Pos Bool
  in  Puzzle arr us

-- | @Just kind@ for a unit glyph, otherwise 'Nothing'.
kindOf :: Char -> Maybe Kind
kindOf 'G' = Just Goblin
kindOf 'E' = Just Elf
kindOf _   = Nothing

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

-- | The four orthogonal neighbours of a cell, already in /reading
-- order/: up, left, right, down.  Returning them pre-sorted means
-- callers that want "the reading-order-first neighbour satisfying P"
-- can just take the first / the minimum without an extra sort.
neighbors :: Pos -> [Pos]
neighbors (y, x) = [ (y - 1, x), (y, x - 1), (y, x + 1), (y + 1, x) ]

-- ---------------------------------------------------------------------------
-- Breadth-first search
-- ---------------------------------------------------------------------------

-- | Breadth-first search over open, unoccupied cells.
--
-- @bfs g blocked start@ returns a map from every reachable cell to
-- its step-distance from @start@.  A cell is traversable iff it is
-- in bounds, open floor in @g@, and not a member of @blocked@ (the
-- set of currently unit-occupied cells).  @start@ itself is seeded
-- at distance 0 and is /not/ subject to the @blocked@ test -- the
-- moving unit stands there, so its own cell must not stop its search.
--
-- The search is level-synchronous: @frontier@ is the whole current
-- ring, @d@ the distance of the next ring.  Membership in the
-- accumulating @dist@ map doubles as the "visited" set, so each cell
-- is assigned exactly once, with its (necessarily shortest) distance.
bfs :: UArray Pos Bool -> Set.Set Pos -> Pos -> Map Pos Int
bfs g blocked start = go (Map.singleton start 0) [start] 1
  where
    ((y0, x0), (y1, x1)) = bounds g
    inBounds (y, x) = y >= y0 && y <= y1 && x >= x0 && x <= x1
    go :: Map Pos Int -> [Pos] -> Int -> Map Pos Int
    go dist []       _ = dist
    go dist frontier d =
      let ring = Set.toList $ Set.fromList
                   [ p
                   | f <- frontier
                   , p <- neighbors f
                   , inBounds p
                   , g ! p
                   , not (Set.member p blocked)
                   , not (Map.member p dist)
                   ]
          dist' = foldl' (\m p -> Map.insert p d m) dist ring
      in  go dist' ring (d + 1)

-- ---------------------------------------------------------------------------
-- Combat
-- ---------------------------------------------------------------------------

-- | Occupancy index for the current population: @position -> unit id@.
-- Rebuilt once per turn.  With only a few dozen units this is far
-- cheaper than maintaining it as an invariant across every move, and
-- it removes a whole class of "the two maps disagreed" bugs.
occMap :: IntMap Unit -> Map Pos Int
occMap um = Map.fromList [ (upos u, i) | (i, u) <- IM.toList um ]

-- | Result of one unit's turn.
data TurnResult
  = NoTargets                 -- ^ combat is over: this unit saw no enemies
  | Acted !(IntMap Unit) !Bool -- ^ new population; True iff an Elf just died

-- | Play out a single unit's turn.
--
-- @eap@ is the Elf attack power (Goblins are always 3).  @i@ is the
-- acting unit's id; if it was killed earlier this round the caller
-- skips it before getting here.
unitTurn :: UArray Pos Bool -> Int -> Int -> IntMap Unit -> TurnResult
unitTurn g eap i um0 =
  let me      = um0 IM.! i
      myKind  = ukind me
      enemies = [ (j, u) | (j, u) <- IM.toList um0, ukind u /= myKind ]
  in if null enemies
       then NoTargets
       else
         let posId0 = occMap um0
             -- enemy ids orthogonally adjacent to cell p
             adjEnemy p posId um =
               [ j
               | nb       <- neighbors p
               , Just j   <- [Map.lookup nb posId]
               , ukind (um IM.! j) /= myKind
               ]
             alreadyInRange = not (null (adjEnemy (upos me) posId0 um0))

             -- Movement phase: returns the (possibly) moved unit and
             -- the population with the move applied.
             (meAfter, um1)
               | alreadyInRange = (me, um0)
               | otherwise      =
                   let occ0    = Map.keysSet posId0
                       -- open, unoccupied squares adjacent to an enemy
                       inRange = Set.fromList
                                   [ nb
                                   | (_, u) <- enemies
                                   , nb     <- neighbors (upos u)
                                   , g ! nb
                                   , not (Set.member nb occ0)
                                   ]
                       distU   = bfs g occ0 (upos me)
                       reach   = [ (d, p)
                                 | p       <- Set.toList inRange
                                 , Just d  <- [Map.lookup p distU]
                                 ]
                   in if null reach
                        then (me, um0)
                        else
                          let chosen = snd (minimum reach)
                              distC  = bfs g occ0 chosen
                              steps  = [ (d, p)
                                       | p      <- neighbors (upos me)
                                       , g ! p
                                       , not (Set.member p occ0)
                                       , Just d <- [Map.lookup p distC]
                                       ]
                              step   = snd (minimum steps)
                              me'    = me { upos = step }
                          in  (me', IM.insert i me' um0)

             -- Attack phase, from wherever the unit now stands.
             posId1 = occMap um1
             foes   = adjEnemy (upos meAfter) posId1 um1
         in case foes of
              [] -> Acted um1 False
              _  ->
                let -- adjacent enemy with fewest HP, reading order breaks ties
                    target = snd $ minimum
                               [ ((uhp (um1 IM.! j), upos (um1 IM.! j)), j)
                               | j <- foes
                               ]
                    tgt    = um1 IM.! target
                    power  = if myKind == Elf then eap else 3
                    hp'    = uhp tgt - power
                in if hp' <= 0
                     then Acted (IM.delete target um1) (ukind tgt == Elf)
                     else Acted
                            (IM.insert target tgt { uhp = hp' } um1)
                            False

-- | Play one full round.  Units act in reading order of their
-- positions /at the start of the round/; a unit killed mid-round is
-- skipped.  Returns @(combatEnded, population, anElfDied)@.  When
-- @combatEnded@ is True the round did /not/ complete and must not be
-- counted toward the outcome.
playRound :: UArray Pos Bool -> Int -> IntMap Unit -> (Bool, IntMap Unit, Bool)
playRound g eap umStart =
  let order = map fst $ sortOn (\(_, u) -> upos u) (IM.toList umStart)
      go :: [Int] -> IntMap Unit -> Bool -> (Bool, IntMap Unit, Bool)
      go []       um elf = (False, um, elf)
      go (k : ks) um elf
        | not (IM.member k um) = go ks um elf       -- died earlier this round
        | otherwise =
            case unitTurn g eap k um of
              NoTargets       -> (True, um, elf)
              Acted um' elfHit -> go ks um' (elf || elfHit)
  in  go order umStart False

-- | Run combat to completion.
--
-- @abortOnElfDeath@ stops the instant an Elf dies, returning
-- 'Nothing' -- this is what makes the Part 2 search cheap.  Otherwise
-- returns @Just (fullRounds, sumHP)@: the number of fully completed
-- rounds times nothing yet -- the caller multiplies.
runCombat
  :: UArray Pos Bool
  -> Int                    -- ^ Elf attack power
  -> Bool                   -- ^ abort the moment an Elf dies?
  -> IntMap Unit
  -> Maybe (Int, Int)       -- ^ (full rounds completed, sum of remaining HP)
runCombat g eap abortOnElfDeath = loop 0
  where
    loop :: Int -> IntMap Unit -> Maybe (Int, Int)
    loop !rounds um =
      case playRound g eap um of
        (_, _, True) | abortOnElfDeath -> Nothing
        (True, um', _)  -> Just (rounds, sumHp um')
        (False, um', _) -> loop (rounds + 1) um'
    sumHp :: IntMap Unit -> Int
    sumHp = IM.foldl' (\acc u -> acc + uhp u) 0

-- | Part 1's number, given a starting population: run everyone at
-- attack power 3, no abort, multiply rounds by remaining HP.
outcomeAt :: UArray Pos Bool -> IntMap Unit -> Int
outcomeAt g um =
  case runCombat g 3 False um of
    Just (r, hp) -> r * hp
    Nothing      -> error "Day15.outcomeAt: unreachable (no abort requested)"

-- | Part 2's number: the lowest Elf attack power (search upward from
-- 4 -- 3 is the Part 1 baseline) at which no Elf dies, and that
-- battle's outcome.  Because the abort fires the moment an Elf dies,
-- a 'Just' here means the Elves finished the fight intact, hence won.
lowestNoDeathOutcome :: UArray Pos Bool -> IntMap Unit -> Int
lowestNoDeathOutcome g um = go 4
  where
    go :: Int -> Int
    go !ap = case runCombat g ap True um of
      Just (r, hp) -> r * hp
      Nothing      -> go (ap + 1)

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

-- | Index the parsed units by id in reading order (their parse
-- order), as the simulation's 'IntMap' expects.
mkPopulation :: [Unit] -> IntMap Unit
mkPopulation us = IM.fromList (zip [0 ..] us)

-- | Part 1: outcome of combat at attack power 3.
part1 :: Puzzle -> Int
part1 (Puzzle g us) = outcomeAt g (mkPopulation us)

-- | Part 2: outcome at the lowest Elf attack power with zero Elf deaths.
part2 :: Puzzle -> Int
part2 (Puzzle g us) = lowestNoDeathOutcome g (mkPopulation us)

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
