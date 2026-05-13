{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day12
-- Description : Day 12 -- Subterranean Sustainability
--
-- A 1-D cellular automaton on an infinite tape of pots numbered
-- @..., -2, -1, 0, 1, 2, ...@.  Each pot is either alive (@#@) or
-- empty (@.@).  A set of rules of the form @LLCRR => N@ specifies,
-- for every 5-cell neighbourhood, whether the centre cell is alive
-- in the next generation.
--
-- Part 1: simulate 20 generations, sum the indices of the alive pots.
-- Part 2: same, but for @50,000,000,000@ generations.
--
-- The state is sparse (the live set stays in the low hundreds even
-- after thousands of generations) so we represent it as a
-- @'Set' 'Int'@ -- the live pot indices.  The 5-cell window at index
-- @i@ is built by looking up @i-2..i+2@ in the set; the new state is
-- @i | rule (window i)@ for every @i@ in @[min - 2 .. max + 2]@.
--
-- Part 2 cannot be simulated directly -- 50 billion generations would
-- take roughly forever.  The trick is that 'step' is
-- /translation-equivariant/: shifting a state by @k@ pots shifts the
-- next generation by exactly the same @k@.  So once the *normalised*
-- shape of consecutive generations matches -- i.e. the live set is
-- identical up to a uniform shift -- it will stay that way for every
-- subsequent generation.  At that point the sum grows by exactly
-- @count * shift@ per generation, where @count@ is the number of
-- live pots and @shift@ is how far they translated in one step.  We
-- project arithmetically to generation @50,000,000,000@.
--
-- Concepts introduced this day:
--
--   * Cellular automaton with a 5-cell neighbourhood.  Same shape as
--     Conway's Game of Life but 1-D and with arbitrary rules.  AoC
--     2018 will reuse the pattern on Day 18 (lumber collection area)
--     with a 9-cell neighbourhood.
--
--   * Sparse state via @'Set' 'Int'@.  We do not allocate the
--     infinite tape; we track only the live pots.  Suits the
--     puzzle's sparsity (the live region drifts but does not grow
--     unbounded), and lets the simulator span the negative pot
--     indices for free.
--
--   * Translation-equivariance of a local rule.  If @f@ depends only
--     on a fixed-width window, then @f@ commutes with translation:
--     @step (translate k s) = translate k (step s)@.  This is the
--     foundation of the period-1 cycle detection.
--
--   * Fixed-point detection for huge generation counts.  Maintain the
--     normalised shape of consecutive generations; the first time
--     they match, extrapolate arithmetically.  Same idea will return
--     on Day 18 (lumber CA) and shows up in any "simulate for a
--     stupidly large number of steps" puzzle.
--
--   * 'Set.mapMonotonic'.  When the function applied to every
--     element is strictly increasing, the Set's element ordering is
--     preserved and the new tree can be built in @O(n)@ without
--     re-sorting.  Used here to translate a live set in linear time.
module Day12
  ( Puzzle (..)
  , parseInput
  , step
  , window
  , normalize
  , sumPots
  , runFor
  , extrapolate
  , part1
  , part2
  , solve
  ) where

import           Control.DeepSeq (NFData (..))
import           Data.Set        (Set)
import qualified Data.Set        as Set

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The parsed input: an initial set of live pot indices and the set
--   of 5-cell window patterns that produce a live pot in the next
--   generation.
--
--   We store rule patterns as 5-character @String@s rather than a
--   @Word8@ bitmask -- it keeps the parser one line long and the
--   simulator's hottest call ('window') already builds a 5-char list.
--   The function guide's optimisation sidebar covers the bitmask
--   route for the curious.
data Puzzle = Puzzle
  { initial :: !(Set Int)
  , rules   :: !(Set String)
  } deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle a b) = a `seq` b `seq` ()

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse the puzzle input.
--
--   The expected layout is:
--
--   @
--   initial state: \#..\#.\#..\#\#......\#\#\#...\#\#\#
--
--   ...\#\# => \#
--   ..\#.. => \#
--   ...
--   @
--
--   The first line begins with the literal @"initial state: "@
--   (15 characters); everything after that is the initial pattern.
--   Subsequent non-blank lines are 10-character rules; we keep only
--   the ones whose right-hand side is @\#@, since the absence of a
--   rule pattern from 'rules' is equivalent to "produces @.@".
parseInput :: String -> Puzzle
parseInput raw = case lines raw of
  []                -> Puzzle Set.empty Set.empty
  initLine : rest   ->
    let initStr = drop 15 initLine  -- length "initial state: " == 15
        initSet = Set.fromList [i | (i, '#') <- zip [0 ..] initStr]
        ruleSet = Set.fromList
                    [ take 5 ln
                    | ln <- filter (not . null) rest
                    , length ln >= 10
                    , ln !! 9 == '#'
                    ]
    in  Puzzle initSet ruleSet

-- ---------------------------------------------------------------------------
-- Simulation
-- ---------------------------------------------------------------------------

-- | The 5-cell window centred at pot index @i@, as a @String@ of
--   @\#@s and @.@s.  This is what we look up in 'rules'.
window :: Set Int -> Int -> String
window s i = [ if Set.member j s then '#' else '.' | j <- [i - 2 .. i + 2] ]

-- | One generation of the automaton.
--
--   For every pot @i@ in @[min - 2 .. max + 2]@, compute the window
--   and ask whether 'rules' fires.  Pots outside that range cannot
--   possibly become alive: their window is @"....."@, and on any
--   real input @"....." => .@ (otherwise the universe would spawn
--   infinite life from any vacuum and the puzzle would be ill-posed).
step :: Set String -> Set Int -> Set Int
step rs s
  | Set.null s = Set.empty
  | otherwise =
      let !lo = Set.findMin s - 2
          !hi = Set.findMax s + 2
      in  Set.fromList
            [ i
            | i <- [lo .. hi]
            , window s i `Set.member` rs
            ]

-- | Sum of the live pot indices.  The puzzle's answer to both parts.
sumPots :: Set Int -> Int
sumPots = Set.foldl' (+) 0

-- | Translate a state so its leftmost live pot is at @0@.  Used to
--   compare two states "up to translation."
normalize :: Set Int -> Set Int
normalize s
  | Set.null s = Set.empty
  | otherwise  = let !m = Set.findMin s in Set.mapMonotonic (subtract m) s

-- | Run the automaton for @n@ generations.
--
--   The classic @'iterate' f x !! n@ idiom.  Each generation is
--   forced by 'sumPots' downstream, so no thunk accumulation -- but
--   the @Set@ values themselves are strict by construction, so even
--   intermediate generations are not lazy.
runFor :: Set String -> Int -> Set Int -> Set Int
runFor rs n = (!! n) . iterate (step rs)

-- | Run until the normalised shape stabilises, then extrapolate to
--   @target@.
--
--   At each generation @g@ we compare the normalised shapes of the
--   previous and current states.  When they match, the system has
--   entered a /translating fixed point/: every further generation
--   produces the same shape shifted by @shift = min cur - min prev@.
--   In that regime,
--
--   @
--   sumPots state_{g+k} = sumPots state_g + k * count * shift
--   @
--
--   where @count@ is the (now stable) number of live pots.  If the
--   shapes have not stabilised by @target@, we just return the
--   accumulated sum at @target@.
extrapolate :: Set String -> Int -> Set Int -> Int
extrapolate rs target s0
  | target <= 0 = sumPots s0
  | otherwise   = go 1 s0 (step rs s0)
  where
    go !g !prev !cur
      | g >= target = sumPots cur
      | normalize prev == normalize cur =
          let !count     = Set.size cur
              !shift     = Set.findMin cur - Set.findMin prev
              !remaining = target - g
          in  sumPots cur + remaining * count * shift
      | otherwise = go (g + 1) cur (step rs cur)

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

part1 :: Puzzle -> Int
part1 (Puzzle s0 rs) = sumPots (runFor rs 20 s0)

part2 :: Puzzle -> Int
part2 (Puzzle s0 rs) = extrapolate rs 50000000000 s0

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
