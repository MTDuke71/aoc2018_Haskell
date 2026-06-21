-- |
-- Module      : Day24
-- Description : Day 24 -- Immune System Simulator 20XX
--
-- Two armies (Immune System and Infection), each a set of /groups/.  A
-- group is a pile of identical /units/ with hit points, an attack
-- (damage + type), an initiative, and optional /weaknesses/ and
-- /immunities/.  Combat proceeds in fights; each fight has a target
-- selection phase and an attacking phase, both governed by fiddly
-- ordering rules.  Fights repeat until one army is wiped out.
--
--   * Part 1: simulate the fight and report the total units left in the
--     winning army.
--
--   * Part 2: find the smallest attack /boost/ added to every Immune
--     System group that lets the Immune System win, then report its
--     surviving units.  Some boosts cause a /stalemate/ (a fight where
--     no unit dies), which must be detected or the loop never ends.
--
-- Concepts introduced this day:
--
--   * /Tuple 'Ord' + 'Down' as a tie-break specification/.  Both combat
--     phases order groups by several keys with mixed directions.  We
--     never write a comparator -- we sort by a tuple whose lexicographic
--     'Ord' is the rule, wrapping descending keys in 'Down'.
--
--   * /'IntMap' as a population of living entities keyed by id/.  Groups
--     take damage, shrink, and die mid-fight; an @'IntMap' 'Group'@
--     keyed by a stable id lets attackers look up their (possibly
--     already-weakened or dead) target by reference.
--
--   * /Fixed-point\/stalemate detection/.  A fight that kills zero units
--     leaves combat in the same state forever; detecting it turns a
--     non-terminating simulation into a decidable @'Stalemate'@.  Same
--     idea as the cycle detection on Days 12 and 18.
--
--   * /Linear threshold search/ (Part 2): the smallest boost that flips
--     the outcome, found by trying @1, 2, 3, ...@ and taking the first
--     Immune win.  A list comprehension over @[1..]@ with a pattern
--     guard expresses it in one line.
--
--   * /Keyword-anchored parsing/: rather than a parser combinator, we
--     locate fields by the fixed words around them (@\"units\"@,
--     @\"does\"@, @\"initiative\"@) and lift the optional parenthetical
--     out separately.
module Day24
  ( -- * Types
    Army (..)
  , Group (..)
  , Outcome (..)
  , Puzzle

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , effectivePower
  , damageTo
  , runCombat
  , boostImmune
  ) where

import           Control.DeepSeq    (NFData (..))
import           Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import           Data.List          (elemIndex, foldl', maximumBy, sortOn)
import           Data.Ord           (Down (..), comparing)
import qualified Data.Set           as Set

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | Which side a group fights for.  Groups only ever target the /other/
-- army, so this is the enemy test.
data Army = Immune | Infection
  deriving (Eq, Show)

-- | A single group.  Strict fields throughout: every value is a small
-- 'Int' or a short list read once at parse time, and the simulation
-- hammers 'gUnits' \/ 'gAttack' \/ 'gHp' in tight loops -- there is no
-- reason to leave any of it as a thunk.
data Group = Group
  { gId         :: !Int       -- ^ stable identity (unique across both armies)
  , gArmy       :: !Army
  , gUnits      :: !Int
  , gHp         :: !Int
  , gWeak       :: [String]   -- ^ attack types this group takes /double/ from
  , gImmune     :: [String]   -- ^ attack types this group takes /zero/ from
  , gAttack     :: !Int       -- ^ damage per unit
  , gAttackType :: !String
  , gInit       :: !Int       -- ^ higher attacks first, wins ties
  } deriving (Eq, Show)

-- | The parsed puzzle is just every group from both armies.
type Puzzle = [Group]

-- | The result of a full combat: who won and with how many units, or a
-- 'Stalemate' (no army can finish the other off).
data Outcome = Win Army Int | Stalemate
  deriving (Eq, Show)

instance NFData Army where
  rnf Immune    = ()
  rnf Infection = ()

instance NFData Group where
  rnf (Group i a u h w im d t n) =
    rnf i `seq` rnf a `seq` rnf u `seq` rnf h `seq` rnf w `seq`
    rnf im `seq` rnf d `seq` rnf t `seq` rnf n

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Split the input into its two armies and parse every group, handing
-- each a unique id (immune groups first, then infection).
parseInput :: String -> Puzzle
parseInput input = immune ++ infection
 where
  ls          = lines input
  immuneLines = takeBlock "Immune System:" ls
  infectLines = takeBlock "Infection:"     ls
  immune      = zipWith (parseGroup Immune)    [1 ..]               immuneLines
  infection   = zipWith (parseGroup Infection) [length immune + 1 ..] infectLines

-- | The non-empty lines that follow a header, up to the next blank line.
takeBlock :: String -> [String] -> [String]
takeBlock header =
  takeWhile (not . null) . drop 1 . dropWhile (/= header)

-- | Parse one group line, e.g.
--
-- > 18 units each with 729 hit points (weak to fire; immune to cold,
-- > slashing) with an attack that does 8 radiation damage at initiative 10
--
-- The numeric fields are found by the fixed keyword next to them; the
-- optional @(...)@ clause is parsed separately.
parseGroup :: Army -> Int -> String -> Group
parseGroup army gid line = Group
  { gId         = gid
  , gArmy       = army
  , gUnits      = numBefore "units"
  , gHp         = numBefore "hit"
  , gWeak       = weak
  , gImmune     = immune
  , gAttack     = numAfter "does"
  , gAttackType = ws !! (idxOf "damage" - 1)
  , gInit       = numAfter "initiative"
  }
 where
  (weak, immune) = parseMods line
  ws             = words (stripParens line)
  idxOf kw       = case elemIndex kw ws of
                     Just i  -> i
                     Nothing -> error ("Day24.parseGroup: no " ++ show kw ++ " in " ++ show line)
  numBefore kw   = read (ws !! (idxOf kw - 1))
  numAfter  kw   = read (ws !! (idxOf kw + 1))

-- | Remove the @(...)@ clause (and the parentheses) so 'words' sees only
-- the fixed skeleton of the line.
stripParens :: String -> String
stripParens s = case break (== '(') s of
  (before, '(' : r) -> before ++ drop 1 (dropWhile (/= ')') r)
  (before, _)       -> before

-- | Parse the weaknesses and immunities out of a line's @(...)@ clause.
-- The clause is zero or more @\"weak to ...\"@ \/ @\"immune to ...\"@
-- parts separated by @\"; \"@, each a comma-separated list of types.
parseMods :: String -> ([String], [String])
parseMods line = case break (== '(') line of
  (_, '(' : r) -> foldl' addClause ([], []) (splitOn ';' (takeWhile (/= ')') r))
  _            -> ([], [])
 where
  addClause (w, i) clause =
    case words (map commaToSpace clause) of
      ("weak"   : "to" : ts) -> (w ++ ts, i)
      ("immune" : "to" : ts) -> (w, i ++ ts)
      _                      -> (w, i)
  commaToSpace c = if c == ',' then ' ' else c

-- | Split a string on a single character (dropping the separators).
splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, [])       -> [a]
  (a, _ : rest) -> a : splitOn c rest

-- ---------------------------------------------------------------------------
-- Combat
-- ---------------------------------------------------------------------------

-- | Units times per-unit attack damage.
effectivePower :: Group -> Int
effectivePower g = gUnits g * gAttack g

-- | Damage @atk@ would deal to @def@: zero if immune, doubled if weak,
-- otherwise the attacker's full effective power.  (Unit counts are not
-- considered -- this is the raw damage figure used for both targeting
-- and the kill calculation.)
damageTo :: Group -> Group -> Int
damageTo atk def
  | gAttackType atk `elem` gImmune def = 0
  | gAttackType atk `elem` gWeak   def = 2 * effectivePower atk
  | otherwise                          = effectivePower atk

-- | Target selection.  Groups choose in decreasing effective power
-- (ties: higher initiative).  Each chooses the enemy it would damage
-- most (ties: largest effective power, then highest initiative), unless
-- it can deal no damage.  Each defender can be claimed by only one
-- attacker.  Returns @attackerId -> defenderId@.
selectTargets :: IntMap Group -> IntMap Int
selectTargets groups = go Set.empty IntMap.empty pickingOrder
 where
  pickingOrder =
    sortOn (\g -> (Down (effectivePower g), Down (gInit g))) (IntMap.elems groups)

  go _ acc [] = acc
  go taken acc (a : rest) =
    case candidates of
      [] -> go taken acc rest
      _  -> let d = maximumBy (comparing rank) candidates
            in  go (Set.insert (gId d) taken) (IntMap.insert (gId a) (gId d) acc) rest
   where
    candidates = [ d | d <- IntMap.elems groups
                     , gArmy d /= gArmy a
                     , not (gId d `Set.member` taken)
                     , damageTo a d > 0 ]
    rank d = (damageTo a d, effectivePower d, gInit d)

-- | One fight: select targets, then attack in decreasing initiative
-- order.  Returns the surviving groups and the total units killed (zero
-- means a stalemate).
fight :: IntMap Group -> (IntMap Group, Int)
fight groups = foldl' attackStep (groups, 0) attackOrder
 where
  targets     = selectTargets groups
  attackOrder = map gId
              . sortOn (Down . gInit)
              . filter ((`IntMap.member` targets) . gId)
              $ IntMap.elems groups

  attackStep (gs, killed) aid =
    case IntMap.lookup aid gs of
      Nothing  -> (gs, killed)            -- attacker died earlier this fight
      Just atk ->
        case IntMap.lookup (targets IntMap.! aid) gs of
          Nothing  -> (gs, killed)        -- (shouldn't happen: targets are live)
          Just def ->
            let dead = min (gUnits def) (damageTo atk def `div` gHp def)
                def' = def { gUnits = gUnits def - dead }
                gs'  | gUnits def' <= 0 = IntMap.delete (gId def) gs
                     | otherwise        = IntMap.insert (gId def) def' gs
            in  (gs', killed + dead)

-- | Run fights to the end.  Stops when an army is wiped out (a win) or
-- when a fight kills nobody (a stalemate -- the state would repeat).
runCombat :: [Group] -> Outcome
runCombat gs0 = go (IntMap.fromList [ (gId g, g) | g <- gs0 ])
 where
  go gs
    | not immuneLeft || not infectLeft =
        Win (if immuneLeft then Immune else Infection) (sum (map gUnits elems))
    | otherwise =
        let (gs', killed) = fight gs
        in  if killed == 0 then Stalemate else go gs'
   where
    elems      = IntMap.elems gs
    immuneLeft = any ((== Immune)    . gArmy) elems
    infectLeft = any ((== Infection) . gArmy) elems

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Units left in the winning army with no boost.
part1 :: Puzzle -> Int
part1 gs = case runCombat gs of
  Win _ n   -> n
  Stalemate -> error "Day24.part1: unexpected stalemate"

-- ---------------------------------------------------------------------------
-- Part 2
-- ---------------------------------------------------------------------------

-- | Add @b@ to every Immune System group's per-unit attack damage.
boostImmune :: Int -> [Group] -> [Group]
boostImmune b = map bump
 where
  bump g
    | gArmy g == Immune = g { gAttack = gAttack g + b }
    | otherwise         = g

-- | The Immune System's surviving units under the smallest boost that
-- lets it win.  Try boosts @1, 2, 3, ...@; the list comprehension's
-- pattern @Win Immune n@ silently skips boosts that lose or stalemate,
-- and 'head' takes the first success.
part2 :: Puzzle -> Int
part2 gs = head [ n | b <- [1 ..], Win Immune n <- [runCombat (boostImmune b gs)] ]

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
