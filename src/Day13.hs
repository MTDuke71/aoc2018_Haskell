{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day13
-- Description : Day 13 -- Mine Cart Madness
--
-- A 2-D grid of tracks (@-@, @|@, @/@, @\\@, @+@) with carts (@^v<>@)
-- riding the rails.  Every tick, every cart moves one cell in its
-- facing direction -- in /reading order/: top-to-bottom by row,
-- left-to-right within a row.  Curves reflect, and at a @+@
-- intersection each cart cycles L-S-R-L-S-R independently.
--
-- Part 1: report the coordinates of the first cart-on-cart collision,
-- formatted as @\"x,y\"@.
-- Part 2: continue running -- removing both carts of every crash --
-- until exactly one cart survives; report /its/ coordinates as
-- @\"x,y\"@.
--
-- Unlike Day 12, the algorithmic shape here is a /discrete-event
-- simulation/ rather than a synchronous-update cellular automaton.
-- The interesting bit is the mid-tick semantics: a cart that has not
-- moved yet can still collide with a cart that has just moved, and
-- (Part 2 only) carts that crash earlier in a tick are removed
-- before later carts process -- so a cart that would have crashed
-- into one of them ends up gliding past where they used to be.
--
-- The state is two strict maps:
--
--   * @track  :: UArray (Int,Int) Char@ -- the static, immutable grid.
--   * tick state: @IntMap Cart@ keyed by cart id, plus
--     @Map (Int,Int) Int@ giving the cart-id currently at each cell.
--
-- Movement is per-cart: at each cart's turn we delete its old cell
-- from the position map, compute its new cell, ask whether anyone
-- else is already there, and either record a crash (deleting both
-- carts) or insert the new cell.  Reading-order traversal is
-- @sortOn (\\(_, c) -> (cartY c, cartX c)) . IM.toList@.
--
-- Concepts introduced this day:
--
--   * Reading-order discrete-event simulation.  Compare with Day 12:
--     a CA updates /every/ cell in lock-step, but here each cart
--     moves /independently/ and the world it sees is whatever the
--     prior moves this tick produced.  The dual structures of
--     synchronous (Day 12) vs asynchronous (Day 13) updates show up
--     repeatedly in AoC -- e.g. AoC 2017 Day 22 (synchronous
--     virus), Day 15 of this year (Goblins & Elves, asynchronous).
--
--   * @IntMap@ keyed by integer id, where the id is allocated at
--     parse time and never reused.  This is the standard pattern
--     for "track a population of agents that can be removed".
--     'IM.lookup' returning 'Nothing' is how we know an id was
--     killed earlier in the same tick (Part 2).
--
--   * Two-map state (id -> Cart) plus (pos -> id), with the
--     position map maintained as an invariant under every move.
--     The pos map exists purely so that "is there a cart at this
--     cell?" is @O(log n)@; without it we would have to scan every
--     other cart on every move, turning each tick into @O(n^2)@.
--
--   * Tuple-state @foldl'@ with @!@ bangs on both components.  The
--     accumulator is @([(Int,Int)], TickState)@; bangs on both
--     parts of the pair prevent thunk pile-up across the fold.
--
--   * Sum types for direction / turn that have only structurally
--     distinct constructors (@U@ | @D@ | @L@ | @R@; @TLeft@ |
--     @TStraight@ | @TRight@).  No data inside the constructors, so
--     they are tiny -- the values are essentially tags.  This is
--     the textbook "enum-style ADT" usage of Haskell @data@.
module Day13
  ( -- * Types
    Puzzle (..)
  , Cart (..)
  , Dir (..)
  , Turn (..)
  , TickState (..)

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , mkTickState
  , tick
  , firstCrash
  , lastSurvivor
  , moveCart
  , applyTile
  , stepDir
  , reflectSlash
  , reflectBackslash
  , intersectTurn
  , nextTurn
  ) where

import           Control.DeepSeq    (NFData (..))
import           Data.Array.Unboxed (UArray, listArray, (!))
import           Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IM
import           Data.List          (foldl', sortOn)
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | Cardinal direction a cart is facing.
data Dir = U | D | L | R deriving (Eq, Show)

-- | Next turn a cart will take at an intersection.  The puzzle says
-- carts cycle left / straight / right / left / straight / right / ...
-- so we just store the upcoming choice and bump it after every @+@.
data Turn = TLeft | TStraight | TRight deriving (Eq, Show)

instance NFData Dir  where rnf !_ = ()
instance NFData Turn where rnf !_ = ()

-- | A single cart's complete state.  Position is stored as
-- @(cartY, cartX)@ so that the reading-order tuple
-- @(cartY, cartX)@ sorts correctly with the default 'Ord'
-- instance for pairs.
data Cart = Cart
  { cartY    :: !Int
  , cartX    :: !Int
  , cartDir  :: !Dir
  , cartTurn :: !Turn
  } deriving (Eq, Show)

instance NFData Cart where
  rnf (Cart a b c d) = a `seq` b `seq` c `seq` d `seq` ()

-- | The parsed input: the static track grid, plus every cart's
-- initial state.  Carts are listed in parse order; 'mkTickState'
-- assigns each one an integer id based on its index in this list.
data Puzzle = Puzzle
  { track :: !(UArray (Int,Int) Char)
  , carts :: ![Cart]
  } deriving (Eq, Show)

-- | The @array@ + @deepseq@ packages do not ship an
-- @NFData (UArray i e)@ instance for our pinned versions, so the
-- @track@ field gets a plain 'seq' -- safe because 'UArray' is
-- spine-strict.  The 'carts' field is a regular list of strict
-- records, so 'rnf' suffices.
instance NFData Puzzle where
  rnf (Puzzle a b) = a `seq` rnf b

-- | The mutable bookkeeping of a tick.
--
--   * 'tsCarts' is the population, keyed by an immutable cart id.
--     The id is allocated at parse time (see 'mkTickState') and
--     stable across the whole simulation.
--   * 'tsPos' is a /derived/ map from cell to cart id.  It is the
--     invariant @forall i c. IM.lookup i tsCarts == Just c ==> Map.lookup (cartY c, cartX c) tsPos == Just i@
--     and the inverse.  Every move maintains both sides.
data TickState = TickState
  { tsCarts :: !(IntMap Cart)
  , tsPos   :: !(Map (Int, Int) Int)
  } deriving (Eq, Show)

instance NFData TickState where
  rnf (TickState a b) = rnf a `seq` rnf b

-- ---------------------------------------------------------------------------
-- Direction algebra
-- ---------------------------------------------------------------------------

-- | The @(dy, dx)@ offset of one step in a given direction.  Note
-- that screen-style "y grows downward" is in force here: 'U' is
-- @(-1, 0)@ because moving up decreases the row number.
stepDir :: Dir -> (Int, Int)
stepDir U = (-1,  0)
stepDir D = ( 1,  0)
stepDir L = ( 0, -1)
stepDir R = ( 0,  1)

-- | Reflection at a @/@ curve.  Geometrically: the curve is the
-- north-east / south-west diagonal.  A cart heading east bounces
-- north; a cart heading north bounces east; symmetrically for the
-- other two.
reflectSlash :: Dir -> Dir
reflectSlash U = R
reflectSlash D = L
reflectSlash L = D
reflectSlash R = U

-- | Reflection at a @\\@ curve.  The other diagonal: east <-> south,
-- north <-> west.
reflectBackslash :: Dir -> Dir
reflectBackslash U = L
reflectBackslash D = R
reflectBackslash L = U
reflectBackslash R = D

-- | Apply an intersection turn to a direction.
--
-- For a left turn: rotate 90 degrees counter-clockwise
-- (@U->L->D->R->U@).  For a right turn: rotate 90 degrees clockwise
-- (@U->R->D->L->U@).  Straight is the identity.
intersectTurn :: Turn -> Dir -> Dir
intersectTurn TStraight d = d
intersectTurn TLeft     U = L
intersectTurn TLeft     L = D
intersectTurn TLeft     D = R
intersectTurn TLeft     R = U
intersectTurn TRight    U = R
intersectTurn TRight    R = D
intersectTurn TRight    D = L
intersectTurn TRight    L = U

-- | The L-S-R-L-S-R cycle a cart applies on successive @+@s.
nextTurn :: Turn -> Turn
nextTurn TLeft     = TStraight
nextTurn TStraight = TRight
nextTurn TRight    = TLeft

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse the puzzle input.
--
-- The input is a rectangular block of ASCII art.  Each row may have
-- trailing whitespace stripped, so we measure the maximum row width
-- and right-pad shorter rows with spaces before flattening into a
-- 'UArray (Int,Int) Char'.
--
-- Carts are picked out by @cartDirOf@; every cart's underlying tile
-- is the straight piece that matches its facing
-- (@^/v -> |@, @<\/> -> -@) per the puzzle statement.
parseInput :: String -> Puzzle
parseInput raw =
  let rows0   = lines raw
      h       = length rows0
      w       = maximum (0 : map length rows0)
      padded  = [ r ++ replicate (w - length r) ' ' | r <- rows0 ]
      tagged  = [ ((y, x), c)
                | (y, row) <- zip [0 ..] padded
                , (x, c)   <- zip [0 ..] row
                ]
      cs      = [ Cart y x d TLeft
                | ((y, x), ch) <- tagged
                , Just d       <- [cartDirOf ch]
                ]
      cells   = map (underTrack . snd) tagged
      arr     = listArray ((0, 0), (h - 1, w - 1)) cells
                  :: UArray (Int, Int) Char
  in  Puzzle arr cs

-- | @Just dir@ if the character is a cart glyph, otherwise 'Nothing'.
cartDirOf :: Char -> Maybe Dir
cartDirOf '^' = Just U
cartDirOf 'v' = Just D
cartDirOf '<' = Just L
cartDirOf '>' = Just R
cartDirOf _   = Nothing

-- | The straight-track piece that lies under a cart at parse time.
-- The puzzle guarantees each cart sits on the straight piece that
-- matches its facing, so this is a deterministic 4-case rewrite.
underTrack :: Char -> Char
underTrack '^' = '|'
underTrack 'v' = '|'
underTrack '<' = '-'
underTrack '>' = '-'
underTrack c   = c

-- ---------------------------------------------------------------------------
-- Movement
-- ---------------------------------------------------------------------------

-- | Apply the tile-arrival rule.  Curves reflect; intersections
-- pick the cart's next intersection turn and bump the cart's
-- 'cartTurn' counter; everything else (straight track, off-grid)
-- is a no-op on direction.
applyTile :: Char -> Cart -> Cart
applyTile '/'  c = c { cartDir = reflectSlash     (cartDir c) }
applyTile '\\' c = c { cartDir = reflectBackslash (cartDir c) }
applyTile '+'  c = c { cartDir  = intersectTurn (cartTurn c) (cartDir c)
                     , cartTurn = nextTurn (cartTurn c)
                     }
applyTile _    c = c

-- | Move a cart one step and apply the tile rule at the new cell.
--
-- The track is indexed by @(y, x)@.  Every cart movement is exactly
-- one cell, so the @(!)@ lookup is safe as long as the track has
-- been padded to cover the full bounding box -- which 'parseInput'
-- guarantees.
moveCart :: UArray (Int, Int) Char -> Cart -> Cart
moveCart tr c =
  let (dy, dx) = stepDir (cartDir c)
      !ny     = cartY c + dy
      !nx     = cartX c + dx
      !tile   = tr ! (ny, nx)
      !moved  = c { cartY = ny, cartX = nx }
  in  applyTile tile moved

-- ---------------------------------------------------------------------------
-- Tick state
-- ---------------------------------------------------------------------------

-- | Build the initial 'TickState' from a parsed cart list.  Cart
-- ids run from 0 upwards in the order the parser produced them
-- (which is reading order, since 'parseInput' iterates rows then
-- columns).
mkTickState :: [Cart] -> TickState
mkTickState cs =
  let idxed = zip [0 ..] cs
      cm    = IM.fromList idxed
      pm    = Map.fromList [ ((cartY c, cartX c), i) | (i, c) <- idxed ]
  in  TickState cm pm

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

-- | One tick.  Returns the crash positions produced /this tick/, in
-- @(y, x)@ form, in the reading order they occurred, plus the new
-- 'TickState'.
--
-- The tick processes carts in the reading order of their /positions
-- at the start of the tick/.  A cart that has been killed by an
-- earlier crash in this same tick is skipped (the 'IM.lookup'
-- returns 'Nothing').  All collisions are resolved Part-2 style:
-- both carts are removed and the crash is recorded.  Part 1 just
-- stops after the first one.
tick :: UArray (Int, Int) Char -> TickState -> ([(Int, Int)], TickState)
tick tr ts0 =
  let orderedIds =
        map fst
          $ sortOn (\(_, c) -> (cartY c, cartX c))
          $ IM.toList (tsCarts ts0)
      (revCrashes, ts1) = foldl' (stepOne tr) ([], ts0) orderedIds
  in  (reverse revCrashes, ts1)

-- | One cart's contribution to a tick.  Strictness everywhere so
-- the foldl''s tuple accumulator does not grow thunks.
stepOne
  :: UArray (Int, Int) Char
  -> ([(Int, Int)], TickState)
  -> Int
  -> ([(Int, Int)], TickState)
stepOne tr (!crs, TickState !cm !pm) i =
  case IM.lookup i cm of
    Nothing -> (crs, TickState cm pm)            -- already crashed this tick
    Just c  ->
      let !old   = (cartY c, cartX c)
          !c'    = moveCart tr c
          !new   = (cartY c', cartX c')
          !pm0   = Map.delete old pm
      in  case Map.lookup new pm0 of
            Just j  ->
              let !pm1 = Map.delete new pm0
                  !cm1 = IM.delete i (IM.delete j cm)
              in  (new : crs, TickState cm1 pm1)
            Nothing ->
              let !pm1 = Map.insert new i pm0
                  !cm1 = IM.insert i c' cm
              in  (crs, TickState cm1 pm1)

-- ---------------------------------------------------------------------------
-- Top-level runners
-- ---------------------------------------------------------------------------

-- | Run ticks until the first crash, return its @(y, x)@.  Carts
-- that survive after the crashing tick are not returned -- Part 1
-- only needs the crash position.
firstCrash :: UArray (Int, Int) Char -> TickState -> (Int, Int)
firstCrash tr = go
  where
    go !ts =
      let (crs, ts') = tick tr ts
      in  case crs of
            (c : _) -> c
            []      -> go ts'

-- | Run ticks until at most one cart remains; return that cart.
-- The puzzle guarantees the surviving population stays odd in
-- practice, so we reach exactly one survivor on real inputs.  We
-- still handle the "0 carts left" case as an explicit 'error' --
-- that means the caller fed us an input that crashed everyone, and
-- there is no answer to return.
lastSurvivor :: UArray (Int, Int) Char -> TickState -> Cart
lastSurvivor tr = go
  where
    go !ts
      | IM.size (tsCarts ts) <= 1 =
          case IM.elems (tsCarts ts) of
            (c : _) -> c
            []      -> error "Day13.lastSurvivor: no carts left"
      | otherwise =
          let (_, ts') = tick tr ts
          in  go ts'

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

-- | Format an @(x, y)@ pair the way the puzzle wants: @\"x,y\"@.
fmtXY :: Int -> Int -> String
fmtXY x y = show x ++ "," ++ show y

-- | Part 1: coordinates of the first cart-on-cart collision.
part1 :: Puzzle -> String
part1 (Puzzle tr cs) =
  let (y, x) = firstCrash tr (mkTickState cs)
  in  fmtXY x y

-- | Part 2: coordinates of the last surviving cart.
part2 :: Puzzle -> String
part2 (Puzzle tr cs) =
  let c = lastSurvivor tr (mkTickState cs)
  in  fmtXY (cartX c) (cartY c)

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ part1 puzzle)
  putStrLn ("  part 2: " ++ part2 puzzle)
