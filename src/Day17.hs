{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : Day17
-- Description : Day 17 -- Reservoir Research
--
-- A vertical slice of ground: sand with veins of clay (@#@).  A
-- spring at @x=500, y=0@ pours water forever.  Water falls straight
-- down through sand; when it lands on clay or already-settled water
-- it spreads sideways.  If the row it spreads along is walled on
-- /both/ sides it settles (@~@, water at rest); otherwise it streams
-- off the open edge(s) and keeps falling (@|@, sand the water has
-- merely passed through).
--
-- Part 1: how many tiles can water reach -- @~@ /and/ @|@ -- counting
-- only rows between the minimum and maximum clay @y@ (so the infinite
-- fall off the bottom, and the dry rows above the first clay, do not
-- count).
--
-- Part 2: how many tiles hold water /at rest/ -- just @~@ -- in the
-- same @y@ window.
--
-- The algorithm is the classic recursive *flood fill* (the same
-- family as a paint-bucket / scanline fill in graphics), with one
-- twist: a @drop@ recursion that returns whether the cell it was
-- asked about ended up *solid* (clay or settled water).  The caller
-- uses that boolean to decide whether its own row can pool.
--
-- A single recursive sweep is /not/ enough on real terrain: when the
-- map has internal clay islands, a row that should settle only after
-- a neighbouring pool fills is missed on the first pass.  So the
-- flood is iterated to a /fixed point/: each pass wipes the transient
-- streams (@|@), re-runs the drop with the larger settled set from
-- the previous pass, and stops when no more water comes to rest.
-- Settled water only ever grows, so the iteration is monotone and
-- converges (here in ~35 passes).
--
-- Concepts introduced this day:
--
--   * Recursive flood fill on a mutable 2-D canvas.  An
--     @STUArray s (Int,Int) Char@ is both the simulation state and
--     the visited-set: a cell already marked @|@ or @~@ short-
--     circuits the recursion, which is what makes each pass
--     terminate.
--
--   * Monotone fixed-point iteration over a mutable structure: keep
--     the permanent part (@#@, @~@), discard the transient part
--     (@|@), re-run, and stop when a scalar signal (the settled
--     count) stabilises.  Same shape as Day 12's fixed-point search,
--     here over a 2-D grid instead of a 1-D rule.
--
--   * Parse-once / simulate-once: 'simulate' runs the whole iterated
--     flood in a single 'runST' and returns both answers as a pair;
--     'part1'/'part2' just project, and 'solve' shares the run.
module Day17
  ( -- * Types
    Puzzle (..)

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , simulate
  ) where

import           Control.DeepSeq  (NFData (..))
import           Control.Monad    (forM_, unless, void, when)
import           Control.Monad.ST (ST, runST)
import           Data.Array.ST    (STUArray, newArray, readArray, writeArray)
import           Data.Array.Unboxed (UArray, assocs)
import qualified Data.Array.MArray as M
import           Data.Set         (Set)
import qualified Data.Set         as Set

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

type Pos = (Int, Int)               -- (x, y): x right, y down

-- | Parsed scan.  'clay' is the set of clay cells; 'pMinY'/'pMaxY'
-- are the clay @y@ extent (the counting window); 'pXlo'/'pXhi' are
-- the array @x@ bounds, one tile wider than the clay on each side so
-- water that overflows a basin has a column to fall down.
data Puzzle = Puzzle
  { clay  :: !(Set Pos)
  , pMinY :: !Int
  , pMaxY :: !Int
  , pXlo  :: !Int
  , pXhi  :: !Int
  } deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle c a b d e) =
    rnf c `seq` a `seq` b `seq` d `seq` e `seq` ()

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Every signed integer run in a string, as 'Int's.  Same
-- "non-digits to spaces, then words/read" trick as Day 16's @nums@.
ints :: String -> [Int]
ints = map read . words
     . map (\ch -> if ch `elem` ('-' : ['0' .. '9']) then ch else ' ')

-- | Parse the scan.  Each line is either @x=A, y=B..C@ or
-- @y=A, x=B..C@; the leading character says which axis is fixed, and
-- the three integers are always @[A, B, C]@.
parseInput :: String -> Puzzle
parseInput raw =
  let cells = concatMap lineCells (lines raw)
      cset  = Set.fromList cells
      ys    = map snd cells
      xs    = map fst cells
  in  Puzzle
        { clay  = cset
        , pMinY = minimum ys
        , pMaxY = maximum ys
        , pXlo  = minimum xs - 1
        , pXhi  = maximum xs + 1
        }
  where
    lineCells :: String -> [Pos]
    lineCells [] = []
    lineCells l@(axis : _) =
      case ints l of
        [a, b, c]
          | axis == 'x' -> [ (a, y) | y <- [b .. c] ]
          | otherwise   -> [ (x, a) | x <- [b .. c] ]
        _ -> []

-- ---------------------------------------------------------------------------
-- Simulation
-- ---------------------------------------------------------------------------

-- | Run the flood once and return @(reachable, atRest)@:
--
--   * @reachable@ = tiles with @|@ or @~@ and @pMinY <= y <= pMaxY@
--     (Part 1).
--   * @atRest@    = tiles with @~@ in the same window (Part 2).
--
-- The grid is an @STUArray s (Int,Int) Char@ over
-- @((pXlo,0),(pXhi,pMaxY))@: @'#'@ clay, @'|'@ flowing, @'~'@
-- settled, @'.'@ untouched sand.  Water enters at the spring column
-- @x=500@, @y=0@.
simulate :: Puzzle -> (Int, Int)
simulate (Puzzle cset minY maxY xlo xhi) = runST run
 where
  inBounds :: Pos -> Bool
  inBounds (x, y) = x >= xlo && x <= xhi && y >= 0 && y <= maxY

  solidC :: Char -> Bool
  solidC ch = ch == '#' || ch == '~'

  run :: forall s. ST s (Int, Int)
  run = do
    g <- newArray ((xlo, 0), (xhi, maxY)) '.'
           :: ST s (STUArray s Pos Char)
    forM_ (Set.toList cset) $ \p ->
      when (inBounds p) (writeArray g p '#')

    -- @drop' x y@: water arrives at (x,y) moving down.  Returns True
    -- iff (x,y) is now /solid/ (clay or settled water) and so can act
    -- as a floor for the row above.
    let drop' :: Int -> Int -> ST s Bool
        drop' x y
          | y > maxY  = pure False               -- fell off the bottom
          | otherwise = do
              c <- readArray g (x, y)
              case c of
                '#' -> pure True
                '~' -> pure True
                '|' -> pure False                -- already a stream here
                _   -> do
                  solidBelow <- drop' x (y + 1)
                  if not solidBelow
                    then do                      -- water streams through
                      writeArray g (x, y) '|'
                      pure False
                    else do                      -- floor below: spread
                      (lx, lWall) <- scan x y (-1)
                      (rx, rWall) <- scan x y   1
                      if lWall && rWall
                        then do                  -- walled both sides: pool
                          forM_ [lx .. rx] $ \xx ->
                            writeArray g (xx, y) '~'
                          pure True
                        else do                  -- overflows: stream the row
                          forM_ [lx .. rx] $ \xx ->
                            writeArray g (xx, y) '|'
                          unless lWall (void (drop' lx (y + 1)))
                          unless rWall (void (drop' rx (y + 1)))
                          pure False

        -- Walk outward along row y from x in direction dx.  Returns
        -- @(boundaryX, hitWall)@: hitWall True means clay stopped us
        -- at @boundaryX@ (the last open cell); False means the floor
        -- ran out under @boundaryX@, so water falls there.
        scan :: Int -> Int -> Int -> ST s (Int, Bool)
        scan x y dx = go x
          where
            go :: Int -> ST s (Int, Bool)
            go cx = do
              let nx = cx + dx
              nIsClay <- (== '#') <$> readArray g (nx, y)
              if nIsClay
                then pure (cx, True)
                else do
                  belowSolid <-
                    if y + 1 > maxY
                      then pure False
                      else solidC <$> readArray g (nx, y + 1)
                  if belowSolid
                    then go nx
                    else pure (nx, False)

        -- Reset the transient streams (@|@) back to sand; clay and
        -- settled water are permanent across passes.
        clearFlow :: ST s ()
        clearFlow =
          forM_ [xlo .. xhi] $ \x ->
            forM_ [0 .. maxY] $ \y -> do
              v <- readArray g (x, y)
              when (v == '|') (writeArray g (x, y) '.')

        -- Total settled (@~@) cells -- the convergence signal.
        countSettled :: ST s Int
        countSettled = goX xlo 0
          where
            goX :: Int -> Int -> ST s Int
            goX !x !acc
              | x > xhi   = pure acc
              | otherwise = goY x 0 acc >>= goX (x + 1)
            goY :: Int -> Int -> Int -> ST s Int
            goY !x !y !acc
              | y > maxY  = pure acc
              | otherwise = do
                  v <- readArray g (x, y)
                  goY x (y + 1) (if v == '~' then acc + 1 else acc)

    -- A single recursive drop does not converge when the geometry
    -- has internal clay islands: water that should settle only after
    -- a neighbouring pool fills is missed in one pass.  So iterate --
    -- wipe the streams, re-run the drop with the larger settled set
    -- from last time, and stop when no more water settles.  The
    -- settled set only grows, so this is a monotone fixed point.
    let loop :: Int -> ST s ()
        loop prev = do
          clearFlow
          _   <- drop' 500 0
          cur <- countSettled
          if cur == prev then pure () else loop cur
    loop (-1)

    frozen <- M.freeze g :: ST s (UArray Pos Char)
    let inWindow ((_, y), ch) =
          y >= minY && y <= maxY && (ch == '|' || ch == '~')
        atRest ((_, y), ch) = y >= minY && y <= maxY && ch == '~'
        cells = assocs frozen
    pure ( length (filter inWindow cells)
         , length (filter atRest  cells) )

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

-- | Part 1: every tile water can reach (@|@ and @~@) in the window.
part1 :: Puzzle -> Int
part1 = fst . simulate

-- | Part 2: only the water at rest (@~@) in the window.
part2 :: Puzzle -> Int
part2 = snd . simulate

solve :: String -> IO ()
solve contents = do
  let puzzle      = parseInput contents
      (p1, p2)    = simulate puzzle
  putStrLn ("  part 1: " ++ show p1)
  putStrLn ("  part 2: " ++ show p2)
