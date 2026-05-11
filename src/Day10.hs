{-# LANGUAGE BangPatterns  #-}
{-# LANGUAGE DeriveGeneric #-}

-- |
-- Module      : Day10
-- Description : Day 10 -- The Stars Align
--
-- Each input line records a 2D point with constant velocity:
--
--     position=<-52775,  31912> velocity=< 5, -3>
--
-- All points start at @t = 0@ and advance by their velocity each
-- second.  At some moment they briefly align to spell a short message
-- in capital letters; the puzzle wants both the message (Part 1) and
-- the second at which it appears (Part 2).
--
-- The trick: while the points drift toward and then through the
-- aligned configuration, the bounding-box area first shrinks, hits a
-- minimum at the moment the message is readable, and then grows
-- again.  That makes the area a quasi-convex function of @t@, so a
-- naive "step until area stops shrinking" loop finds the right
-- moment in @O(t * n)@ work without any algebra.
--
-- Concepts introduced this day:
--
--   * Quasi-convex search by stepping.  We rely on the area function
--     being unimodal in @t@ for /this/ puzzle's inputs; if it were
--     not, ternary search or a closed-form fit on @t@ would be
--     needed.  The naive step works because the inputs are
--     constructed to converge cleanly.
--   * The first day where the puzzle answer is a /multi-line/
--     'String' (an ASCII picture).  No OCR is run; we render the
--     bounding box at the minimum-area moment and the human reads
--     the eight letters out of the picture.  Part 2 then hands back
--     the integer @t@ for which that picture was rendered.
--   * 'Set' membership for sparse-grid rendering: we build a 'Set'
--     of @(x, y)@ occupancy once, then pour it into a comprehension
--     that walks every cell of the bounding box exactly once.
--   * Robust whitespace-tolerant integer parsing without 'Text.Read'
--     or @megaparsec@: replace every non-digit, non-minus character
--     with a space, then 'words' + 'read'.  Idiomatic for noisy
--     fixed-format AoC lines.

module Day10
  ( Point (..)
  , parseInput
  , parseLine
  , step
  , advance
  , bboxArea
  , findMessage
  , findMessageTernary
  , estimateUpperBound
  , render
  , part1
  , part2
  , solve
  ) where

import           Control.DeepSeq (NFData)
import           Data.Char       (isDigit)
import           Data.List       (foldl', minimumBy)
import           Data.Ord        (comparing)
import qualified Data.Set        as Set
import           GHC.Generics    (Generic)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A point with position @(px, py)@ and velocity @(vx, vy)@.  All
--   four fields are strict 'Int's: lazy fields would build up a tower
--   of @+@ thunks across the simulation steps and balloon memory.
data Point = Point
  { px :: !Int
  , py :: !Int
  , vx :: !Int
  , vy :: !Int
  } deriving (Eq, Show, Generic)

-- | Empty body picks up the @Generic@-derived deep-evaluation walker
--   so 'criterion' can force a parsed @['Point']@ through 'nf'.
instance NFData Point

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse the raw input into a list of 'Point'.  One point per line.
parseInput :: String -> [Point]
parseInput = map parseLine . lines

-- | Parse a single line of the shape
--   @"position=<-52775,  31912> velocity=< 5, -3>"@.
--
--   We sidestep a real parser by replacing every character that is
--   not a digit and not a minus sign with a space, leaving exactly
--   the four signed integers we want surrounded by whitespace.
--   'words' + 'read' do the rest.
parseLine :: String -> Point
parseLine s = case map read (words (map keep s)) of
  [a, b, c, d] -> Point a b c d
  _            -> error ("Day10.parseLine: bad line " ++ show s)
  where
    keep :: Char -> Char
    keep ch
      | ch == '-' || isDigit ch    = ch
      | otherwise                  = ' '

-- ---------------------------------------------------------------------------
-- The simulation
-- ---------------------------------------------------------------------------

-- | Advance every point by one second.  Velocities never change, so
--   the only field that updates is the position.
step :: [Point] -> [Point]
step = map (\(Point x y dx dy) -> Point (x + dx) (y + dy) dx dy)

-- | Area of the axis-aligned bounding box around the points.
--
--   We use a single 'foldl'' that threads four extrema through the
--   list, so each coordinate is read once and there is no
--   intermediate list of just @x@s or just @y@s allocated.  With
--   ~300 points the difference is invisible, but the pattern is the
--   right reflex when 'bboxArea' is called once per simulation tick.
bboxArea :: [Point] -> Int
bboxArea []     = 0
bboxArea (p:ps) =
  let (xMin, xMax, yMin, yMax) = foldl' extend (px p, px p, py p, py p) ps
  in (xMax - xMin) * (yMax - yMin)
  where
    extend :: (Int, Int, Int, Int) -> Point -> (Int, Int, Int, Int)
    extend (!a, !b, !c, !d) (Point x y _ _) =
      (min a x, max b x, min c y, max d y)

-- | Step the simulation forward as long as the bounding-box area
--   keeps shrinking; stop on the first tick where it would grow.
--   Returns @(t, points)@ at the moment of minimum area.
--
--   We compare against /next/, not /current/: as soon as @area next@
--   is no longer smaller than @area current@, the previous tick was
--   the minimum and we hand back @(t, current)@.
findMessage :: [Point] -> (Int, [Point])
findMessage pts0 = go 0 pts0 (bboxArea pts0)
  where
    go :: Int -> [Point] -> Int -> (Int, [Point])
    go !t !pts !a =
      let nextPts = step pts
          aNext   = bboxArea nextPts
      in if aNext < a
         then go (t + 1) nextPts aNext
         else (t, pts)

-- | Advance every point by @t@ seconds in a single pass, without
--   stepping through intermediate ticks.  Uses the closed-form
--   @position(t) = position(0) + t * velocity@.  Crucial for
--   'findMessageTernary', which evaluates 'bboxArea' at arbitrary
--   @t@ rather than walking forward one tick at a time.
--
--   For @t = 1@ this is the same shape as 'step' but allocates a
--   fresh list; for larger @t@ it /skips/ the intermediate ticks
--   entirely instead of materialising each one.
advance :: Int -> [Point] -> [Point]
advance t = map (\(Point x y dx dy) -> Point (x + t * dx) (y + t * dy) dx dy)

-- | A generous ceiling on @t_min@ derived from the y-spread and the
--   maximum vertical velocity.  Even if every point moved straight
--   toward the centre at its full @|vy|@, the y-range could not
--   close faster than @yRange / maxAbsVy@ ticks.  Doubling that gives
--   ternary search slack to land safely on the far side of the true
--   minimum, where its convergence guarantees kick in.
--
--   For the actual puzzle input this returns ~40,000 -- generous
--   relative to the true @t_min = 10595@, but not so big that the
--   log-factor cost of ternary search blows up.
estimateUpperBound :: [Point] -> Int
estimateUpperBound pts =
  let ys       = map py pts
      yRange   = maximum ys - minimum ys
      maxAbsVy = maximum (map (abs . vy) pts)
  in  2 * yRange `div` max 1 maxAbsVy

-- | Ternary-search variant of 'findMessage'.  Same return contract,
--   different algorithm: instead of stepping through every tick from
--   0 to @t_min@, we exploit the bbox area's unimodality and probe
--   only @~ log_{3/2} (searchRange)@ values of @t@ (~26 evaluations
--   for the actual input vs ~10,500 ticks for the linear scan).
--
--   The key primitive is 'advance', which lets us evaluate 'bboxArea'
--   at /arbitrary/ @t@ in O(n) regardless of distance from 0.  Each
--   iteration probes two interior points @m1 < m2@ of the current
--   search interval; the relative ordering of @bboxArea@ at those
--   points tells us which third of the interval the minimum cannot
--   be in, and we shrink accordingly.
--
--   Correctness rests on the area function being /unimodal/ in @t@.
--   That property is documented in detail in the function guide; it
--   is empirically true of every AoC 2018 Day 10 input but not
--   formally proved.  For pathological inputs with non-unique minima
--   or plateaus, prefer 'findMessage' (whose "step until growth"
--   shape is robust to those cases).
findMessageTernary :: [Point] -> (Int, [Point])
findMessageTernary pts0 = (bestT, advance bestT pts0)
  where
    bestT :: Int
    bestT = go 0 (estimateUpperBound pts0)

    go :: Int -> Int -> Int
    go !lo !hi
      | hi - lo <= 2 =
          fst (minimumBy (comparing snd)
                 [ (t, bboxArea (advance t pts0))
                 | t <- [lo .. hi] ])
      | aM1 < aM2    = go lo m2           -- min must be in [lo, m2]
      | aM1 > aM2    = go m1 hi           -- min must be in [m1, hi]
      | otherwise    = go m1 m2           -- plateau: min in [m1, m2]
      where
        m1  = lo + (hi - lo) `div` 3
        m2  = hi - (hi - lo) `div` 3
        aM1 = bboxArea (advance m1 pts0)
        aM2 = bboxArea (advance m2 pts0)

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- | Render the points as an ASCII picture cropped to their bounding
--   box.  @#@ marks an occupied cell, @.@ an empty one.  Lines are
--   newline-terminated via 'unlines'.
render :: [Point] -> String
render []  = ""
render pts =
  let xs   = map px pts
      ys   = map py pts
      x0   = minimum xs
      x1   = maximum xs
      y0   = minimum ys
      y1   = maximum ys
      pset = Set.fromList [(px p, py p) | p <- pts]
  in unlines
       [ [ if (x, y) `Set.member` pset then '#' else '.'
         | x <- [x0 .. x1] ]
       | y <- [y0 .. y1] ]

-- ---------------------------------------------------------------------------
-- Public answers
-- ---------------------------------------------------------------------------

-- | Part 1: the message rendered as multi-line ASCII.  The caller
--   prints it; a human reads the letters off the picture.  We do not
--   attempt OCR.
part1 :: [Point] -> String
part1 = render . snd . findMessage

-- | Part 2: the second at which the message appeared.
part2 :: [Point] -> Int
part2 = fst . findMessage

-- ---------------------------------------------------------------------------
-- IO entry point
-- ---------------------------------------------------------------------------

-- | Parse once via the shared @let@ binding, find the message once
--   (so Part 2 reuses Part 1's search), print the picture and the
--   second at which it appeared.
solve :: String -> IO ()
solve contents = do
  let pts         = parseInput contents
      (t, msgPts) = findMessage pts
  putStrLn "  part 1:"
  mapM_ (putStrLn . ("    " ++)) (lines (render msgPts))
  putStrLn ("  part 2: " ++ show t)
