{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : Day14
-- Description : Day 14 -- Chocolate Charts
--
-- Two elves stand on an indefinitely growing /scoreboard/ of digits.
-- The scoreboard starts as @[3, 7]@; elf 1 is on index 0, elf 2 on
-- index 1.  Each /round/:
--
--   1. Let @a = scoreboard[i]@ and @b = scoreboard[j]@.  Compute
--      @a + b@.  Since @a, b@ are digits (0..9) the sum is in @0..18@,
--      so it has either one or two decimal digits.  Append those
--      digit(s), in order, to the end of the scoreboard.
--   2. Each elf advances by @1 +@ /their own current score/ positions,
--      with wraparound modulo the new scoreboard length.
--
-- Part 1 (input @N@): simulate until the scoreboard has at least
-- @N + 10@ entries; return the ten digits starting at index @N@,
-- concatenated as a string.
--
-- Part 2 (input read as a /digit pattern/): simulate until the trailing
-- edge of the scoreboard matches the pattern; return the index at which
-- the pattern first occurs.
--
-- Concepts introduced this day:
--
--   * Mutable arrays as a /growing tape/.  Day 9 used 'STUArray' as a
--     doubly-linked list (fixed-size, two index arrays).  Day 11 used
--     'STUArray' as a /built-then-frozen/ summed-area table.  Day 14
--     uses 'STUArray' as a one-shot /pre-allocated capacity/ that we
--     write forward into, tracking the populated prefix with an
--     explicit @len@ counter.  Same primitive, third pattern of use.
--
--   * 'Word8' cell type.  Each scoreboard cell is a single decimal
--     digit, so a one-byte unboxed cell is the natural choice.  At
--     Part 2's ~32M-cell capacity that is ~32 MB of contiguous bytes;
--     using @Int@ instead would cost 8x that for no benefit.  First
--     explicit cell-size tuning of the year.
--
--   * Trailing-edge string matching against a generated sequence.  We
--     check after /every/ digit appended -- patterns can land inside a
--     two-digit append, so checking only at the end of each round
--     would miss them.  Last-digit guard (compare a single byte before
--     doing the full 6-byte compare) gives ~10x speedup at trivial
--     cost; KMP / Aho-Corasick are documented in the function guide
--     as the canonical-vocabulary upgrades.
--
--   * @case ... of { Just k -> return k; Nothing -> ... }@ as a
--     single-shot early-exit idiom inside 'ST'.  The pattern repeats
--     three times inside the Part 2 loop (initial, after first digit,
--     after second digit) -- each layer is a possible exit point.
module Day14
  ( -- * Types
    Puzzle (..)

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , simulateAfter
  , simulateUntil
  ) where

import           Control.DeepSeq    (NFData)
import           Control.Monad.ST   (ST, runST)
import           Data.Array.ST      (STUArray, newArray, readArray,
                                     writeArray)
import           Data.Array.Unboxed (UArray, listArray, (!))
import           Data.Char          (digitToInt, intToDigit, isDigit)
import           Data.Word          (Word8)
import           GHC.Generics       (Generic)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | Parsed input.  The puzzle gives a single number; we keep two views:
--
--   * 'target' is the integer value, used as Part 1's
--     "skip @N@ recipes" parameter.
--   * 'needle' is the same number as a list of decimal-digit bytes,
--     which Part 2 scans the scoreboard for.
data Puzzle = Puzzle
  { target :: !Int
  , needle :: ![Word8]
  } deriving (Eq, Show, Generic)

instance NFData Puzzle

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Strip the trailing newline (or any non-digit whitespace) and parse
--   the remaining digits as both an 'Int' and a digit list.
parseInput :: String -> Puzzle
parseInput raw =
  let digits = filter isDigit raw
      n      = read digits :: Int
      pat    = [ fromIntegral (digitToInt c) | c <- digits ]
  in  Puzzle n pat

-- ---------------------------------------------------------------------------
-- Capacity tuning
-- ---------------------------------------------------------------------------

-- | Pre-allocated capacity for the Part 2 scoreboard.  Empirically, the
--   6-digit AoC inputs settle in well under 25M recipes; 32M leaves a
--   comfortable safety margin and is the power-of-two near that.
--   Cost is ~32 MB of contiguous unboxed 'Word8' storage -- a one-shot
--   allocation from the OS, not GC pressure.
part2Capacity :: Int
part2Capacity = 32_000_000

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Simulate until the scoreboard has at least @target + 10@ entries,
--   then read out indices @[target .. target + 9]@ as a decimal string.
--
--   Pre-allocates @target + 12@ cells -- one extra round can append two
--   digits, so we need at least one cell of slack past the @+10@ we
--   actually read.  The extra +2 over that is belt-and-suspenders.
simulateAfter :: Int -> String
simulateAfter n = runST $ do
  let cap = n + 12
  arr <- newArray (0, cap - 1) 0 :: ST s (STUArray s Int Word8)
  writeArray arr 0 3
  writeArray arr 1 7
  let loop !i !j !len
        | len >= n + 10 = return ()
        | otherwise = do
            a <- readArray arr i
            b <- readArray arr j
            let s = fromIntegral a + fromIntegral b :: Int
            len' <- if s >= 10
                      then do
                        writeArray arr len       (fromIntegral (s `quot` 10))
                        writeArray arr (len + 1) (fromIntegral (s `rem` 10))
                        return (len + 2)
                      else do
                        writeArray arr len (fromIntegral s)
                        return (len + 1)
            let !i' = (i + 1 + fromIntegral a) `mod` len'
                !j' = (j + 1 + fromIntegral b) `mod` len'
            loop i' j' len'
  loop 0 1 2
  -- Walk the populated cells [n .. n+9] right-to-left, consing onto an
  -- accumulator so the final list is in left-to-right order.  Avoids
  -- the O(n) cost of '++' for a final 'reverse'.
  let readOut !k acc
        | k < n     = return acc
        | otherwise = do
            v <- readArray arr k
            readOut (k - 1) (intToDigit (fromIntegral v) : acc)
  readOut (n + 9) []

-- | Part 1 -- the published puzzle answer.
part1 :: Puzzle -> String
part1 (Puzzle n _) = simulateAfter n

-- ---------------------------------------------------------------------------
-- Part 2
-- ---------------------------------------------------------------------------

-- | Simulate until the trailing @patLen@ digits of the scoreboard match
--   @pat@; return the start index of that match.
--
--   Two correctness points worth pinning down before reading the body:
--
--   * The pattern can land /inside/ a two-digit append.  A round that
--     produces @1 6@ (sum 16) could complete a needle whose last char
--     is @1@, even though a later @6@ is also appended in the same
--     round.  So we check after each appended digit, not after each
--     round.  The two nested 'case' on @m1@/@m2@ are the two
--     in-round check points.
--
--   * The seed scoreboard @[3, 7]@ could itself satisfy a single- or
--     two-character pattern.  The puzzle never asks for needles that
--     short, but the @initialCheck@ at the top of the function makes
--     'simulateUntil' total: every reachable scoreboard state -- the
--     initial included -- is checked exactly once.
simulateUntil :: [Word8] -> Int
simulateUntil pat = runST $ do
  let cap     = part2Capacity
      patLen  = length pat
      patArr :: UArray Int Word8
      patArr  = listArray (0, patLen - 1) pat
      -- Last byte of the pattern, used as a cheap "should we even
      -- bother running the full compare?" guard.  Rejects 9 of 10
      -- digits instantly, since the scoreboard's trailing digit is
      -- uniformly distributed across 0..9.
      patLast = if patLen == 0 then 0 else patArr ! (patLen - 1)
  arr <- newArray (0, cap - 1) 0 :: ST s (STUArray s Int Word8)
  writeArray arr 0 3
  writeArray arr 1 7
  initialCheck <- matchEnd arr 2 patArr patLen patLast
  case initialCheck of
    Just k  -> return k
    Nothing ->
      let loop !i !j !len = do
            a <- readArray arr i
            b <- readArray arr j
            let s = fromIntegral a + fromIntegral b :: Int
            if s >= 10
              then do
                writeArray arr len (fromIntegral (s `quot` 10))
                m1 <- matchEnd arr (len + 1) patArr patLen patLast
                case m1 of
                  Just k  -> return k
                  Nothing -> do
                    writeArray arr (len + 1) (fromIntegral (s `rem` 10))
                    m2 <- matchEnd arr (len + 2) patArr patLen patLast
                    case m2 of
                      Just k  -> return k
                      Nothing ->
                        let !len' = len + 2
                            !i'   = (i + 1 + fromIntegral a) `mod` len'
                            !j'   = (j + 1 + fromIntegral b) `mod` len'
                        in  loop i' j' len'
              else do
                writeArray arr len (fromIntegral s)
                m1 <- matchEnd arr (len + 1) patArr patLen patLast
                case m1 of
                  Just k  -> return k
                  Nothing ->
                    let !len' = len + 1
                        !i'   = (i + 1 + fromIntegral a) `mod` len'
                        !j'   = (j + 1 + fromIntegral b) `mod` len'
                    in  loop i' j' len'
      in  loop 0 1 2

-- | Trailing-edge match.  Given a populated prefix @arr[0..len-1]@ and
--   a pattern of length @patLen@ whose last byte is @patLast@, return
--   @Just (len - patLen)@ if the scoreboard's last @patLen@ cells equal
--   the pattern, else 'Nothing'.
--
--   The @patLast@ guard short-circuits 9 of 10 calls: if the last byte
--   we just appended is not the pattern's last byte, there is nothing
--   to compare.  When the guard passes we walk forward through the
--   remaining @patLen - 1@ positions; first mismatch returns 'Nothing'.
matchEnd
  :: STUArray s Int Word8
  -> Int                  -- ^ length of the populated prefix
  -> UArray Int Word8     -- ^ pattern array
  -> Int                  -- ^ patLen
  -> Word8                -- ^ pattern's last byte (cached)
  -> ST s (Maybe Int)
matchEnd arr len patArr patLen patLast
  | len < patLen = return Nothing
  | otherwise = do
      let !start = len - patLen
      lastV <- readArray arr (len - 1)
      if lastV /= patLast
        then return Nothing
        else do
          let go !k
                | k >= patLen - 1 = return True
                | otherwise = do
                    v <- readArray arr (start + k)
                    if v == patArr ! k
                      then go (k + 1)
                      else return False
          ok <- go 0
          return (if ok then Just start else Nothing)

-- | Part 2 -- the published puzzle answer.
part2 :: Puzzle -> Int
part2 (Puzzle _ pat) = simulateUntil pat

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ part1 puzzle)
  putStrLn ("  part 2: " ++ show (part2 puzzle))
