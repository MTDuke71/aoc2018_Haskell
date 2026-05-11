{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : Day09
-- Description : Day 09 -- Marble Mania
--
-- @N@ players play a marble game.  Marbles numbered @1..M@ are placed
-- in turn around a circle starting from a circle of just marble @0@.
--
-- For most marbles, the next marble is inserted between the marbles
-- that are @1@ and @2@ steps clockwise of the current marble, and the
-- newly inserted marble becomes the current.  When the marble being
-- placed is a multiple of @23@, something else happens: the placing
-- player keeps that marble (adding it to their score) AND removes the
-- marble @7@ steps counter-clockwise of current, also adding it to
-- their score.  The marble immediately clockwise of the removed one
-- becomes the new current.
--
-- Part 1: with @numPlayers@ Elves and last marble @lastMarble@, what
--         is the highest single-player score?
-- Part 2: what is the highest score if @lastMarble@ is multiplied by
--         100?  (Same game, ~7 million marbles for the actual input.)
--
-- Concepts introduced this day:
--
--   * The 'ST' monad and 'STUArray'.  'ST' is Haskell's "scoped
--     mutation" monad: inside an @ST s@ action you can read and write
--     mutable cells, but the @runST :: (forall s. ST s a) -> a@
--     wrapper makes the whole computation pure from the outside -- the
--     mutation cannot escape the @s@ scope.  'STUArray' is the
--     unboxed flavour: it stores raw machine 'Int's contiguously, no
--     boxing, no thunks.  Same mental model as a Rust function that
--     takes @&mut [i64]@ internally but returns an owned @i64@.
--   * A circular doubly-linked list encoded as two parallel index
--     arrays.  @nxt[m]@ is the marble immediately clockwise of @m@,
--     @prv[m]@ is the marble immediately counter-clockwise.  Insertion
--     and removal are four pointer writes -- 'Data.Sequence' would
--     give the same /shape/ but ~10x slower for Part 2's 7M marbles.
--   * 'forall' in a type signature plus the @ScopedTypeVariables@
--     extension to bring the existential @s@ into scope inside the
--     body, so we can annotate the arrays with @STUArray s Int Int@.
--   * Bang patterns on tail-recursive accumulator parameters
--     (@!current@, @!marble@, @!best@): force strictness on the loop
--     variable so the compiled inner loop allocates no thunks per
--     iteration.  Critical at 7M iterations.

module Day09
  ( Game (..)
  , parseInput
  , play
  , part1
  , part2
  , solve
  ) where

import           Control.DeepSeq    (NFData)
import           Control.Monad      (when)
import           Control.Monad.ST   (ST, runST)
import           Data.Array.ST      (STUArray, newArray, readArray,
                                     writeArray)
import           GHC.Generics       (Generic)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The puzzle input: number of players and value of the last marble
--   that will be placed.  Both fields are strict because there is no
--   meaningful "lazy partial Game" we would ever construct.
data Game = Game
  { numPlayers :: !Int
  , lastMarble :: !Int
  } deriving (Eq, Show, Generic)

-- | @Generic@-derived deep-evaluation walker for criterion's 'nf'.
--   Empty body picks up the default implementation provided by
--   @Control.DeepSeq@ for any 'Generic' type.
instance NFData Game

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse a one-line input of the shape
--   @"464 players; last marble is worth 71730 points"@.
--
--   The line has nine words; word @0@ is the player count and word @6@
--   is the last-marble number.  Everything else is fixed boilerplate
--   we do not need to read.
parseInput :: String -> Game
parseInput s = case words s of
  (n : _ : _ : _ : _ : _ : m : _) -> Game (read n) (read m)
  _ -> error ("Day09.parseInput: unexpected line " ++ show s)

-- ---------------------------------------------------------------------------
-- The simulation
-- ---------------------------------------------------------------------------
--
-- Variable glossary for the code that follows.  Every name introduced in
-- 'play', 'playST', the local 'stepBack' helper, the 'go' loop, and the
-- local 'maxLoop' helper.  Types are spelled out so the table also tells
-- you "single Int" vs "mutable array."
--
-- Function parameters (passed in from 'play'):
--   players :: Int    -- number of Elves competing
--   lastM   :: Int    -- value of the last marble to be placed
--
-- Mutable arrays (allocated once at the top of 'playST'):
--   nxt     :: STUArray s Int Int  -- nxt[m] = marble immediately clockwise of m
--   prv     :: STUArray s Int Int  -- prv[m] = marble immediately counter-clockwise of m
--   scores  :: STUArray s Int Int  -- scores[p] = running score for player p (0-based)
--
-- 'stepBack' helper -- walks @k@ steps counter-clockwise:
--   i       :: Int    -- the marble we are stepping back from this iteration
--   k       :: Int    -- steps remaining; recursion stops at k == 0
--   p       :: Int    -- the marble one step ccw of i (read from prv[])
--
-- 'go' loop -- one iteration per marble placed:
--   current :: Int    -- the marble currently designated as "current"
--   marble  :: Int    -- the new marble being placed this iteration
--
-- 'go' branch when @marble \`mod\` 23 == 0@ (the scoring case):
--   target  :: Int    -- marble 7 ccw of current; will be removed
--   tprev   :: Int    -- marble immediately ccw of target (= prv[target])
--   tnext   :: Int    -- marble immediately cw  of target (= nxt[target])
--                     --   becomes the new current after removal
--   player  :: Int    -- 0-based index of the Elf placing @marble@
--   cur     :: Int    -- that player's score before adding @marble + target@
--
-- 'go' branch when @marble \`mod\` 23 /= 0@ (the standard insertion case):
--   one     :: Int    -- marble 1 cw of current (= nxt[current])
--   two     :: Int    -- marble 2 cw of current (= nxt[one])
--                     --   the new marble is spliced between 'one' and 'two'
--
-- 'maxLoop' helper -- linear scan of @scores@ for the maximum:
--   i       :: Int    -- player index currently being inspected
--   best    :: Int    -- highest score seen so far
--   v       :: Int    -- score at scores[i] just read

-- | Play a marble game with @players@ Elves and a final marble of
--   @lastM@; return the winning (highest) score.
--
--   The circle is represented by two unboxed mutable arrays
--   @nxt[]@ and @prv[]@ of size @lastM + 1@, indexed by marble value:
--   we never need more than @lastM + 1@ marbles so the marble's value
--   is its own array index.  An auxiliary @scores[]@ array of size
--   @players@ accumulates per-player totals.
--
--   Initially the circle is the singleton @[0]@; both @nxt[0]@ and
--   @prv[0]@ are @0@ (the marble is its own clockwise and
--   counter-clockwise neighbour).  'newArray' starts every cell at
--   @0@, which is exactly what we want.
play :: Int -> Int -> Int
play players lastM = runST (playST players lastM)

-- | The stateful core of 'play'.  Lives in the 'ST' monad with a fresh
--   region tag @s@ so the mutable arrays cannot escape 'runST'.
playST :: forall s. Int -> Int -> ST s Int
playST players lastM = do
  -- 'newArray' :: '(MArray a e m, Ix i)' => @(i, i) -> e -> m (a i e)@.
  -- We pin the array type to @STUArray s Int Int@ so GHC picks the
  -- /unboxed/ representation (raw 'Int's, no pointers).  'ScopedTypeVariables'
  -- is what lets us say @s@ here -- it refers to the @s@ from this
  -- function's @forall s@.
  nxt    <- newArray (0, lastM)        0 :: ST s (STUArray s Int Int)
  prv    <- newArray (0, lastM)        0 :: ST s (STUArray s Int Int)
  scores <- newArray (0, players - 1)  0 :: ST s (STUArray s Int Int)

  let -- Helper: walk @k@ steps counter-clockwise from @i@ in @prv[]@.
      stepBack :: Int -> Int -> ST s Int
      stepBack !i 0 = return i
      stepBack !i !k = do
        p <- readArray prv i
        stepBack p (k - 1)

      go :: Int -> Int -> ST s ()
      go !current !marble
        | marble > lastM = return ()
        | marble `mod` 23 == 0 = do
            -- Find marble 7 ccw of current, then unlink it.
            target <- stepBack current 7
            tprev  <- readArray prv target
            tnext  <- readArray nxt target
            writeArray nxt tprev tnext
            writeArray prv tnext tprev
            -- Player numbering: marble 1 is placed by player 1, marble
            -- 2 by player 2, ..., wrapping around.  We use 0-based
            -- player indices internally; the choice does not affect
            -- the maximum score.
            let player = (marble - 1) `mod` players
            cur <- readArray scores player
            writeArray scores player (cur + marble + target)
            go tnext (marble + 1)
        | otherwise = do
            -- Standard insertion: between (1 cw) and (2 cw) of current.
            -- "Between A and B" with A = nxt[current], B = nxt[A] means
            -- linking A->marble->B and B<-marble<-A; four writes.
            one <- readArray nxt current
            two <- readArray nxt one
            writeArray nxt one    marble
            writeArray prv marble one
            writeArray nxt marble two
            writeArray prv two    marble
            go marble (marble + 1)

  -- Marble 0 is its own neighbour to start; only when marble 1 is
  -- placed does the circle have more than one element.  But when
  -- @lastM == 0@ there is no game: skip the loop entirely.
  when (lastM >= 1) (go 0 1)

  -- Linear scan of the @scores@ array for the maximum.  A bang on
  -- @best@ keeps the accumulator strict.
  let maxLoop :: Int -> Int -> ST s Int
      maxLoop !i !best
        | i >= players = return best
        | otherwise = do
            v <- readArray scores i
            maxLoop (i + 1) (max best v)
  maxLoop 0 0

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

part1 :: Game -> Int
part1 g = play (numPlayers g) (lastMarble g)

part2 :: Game -> Int
part2 g = play (numPlayers g) (lastMarble g * 100)

-- ---------------------------------------------------------------------------
-- IO entry point
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let g = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 g))
  putStrLn ("  part 2: " ++ show (part2 g))
