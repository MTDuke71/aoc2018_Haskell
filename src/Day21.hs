{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Day21
-- Description : Day 21 -- Chronal Conversion
--
-- The Day 16\/19 device one last time.  The activation system (our
-- input) /never halts on its own/: the only way out is a single
-- @eqrr X 0 _@ instruction -- "compare register X against register
-- 0, and if they are equal, fall off the end of the program".
-- Register 0 is never read or written anywhere else, so it is a
-- pure spectator: the stream of values register X holds at that
-- comparison is completely fixed, and our only move is to choose
-- r0 to collide with one of them.
--
-- Part 1: the value of r0 that halts the program /soonest/ -- i.e.
-- the first value X takes at the check.
--
-- Part 2: the value of r0 that halts the program /latest/ while
-- still halting at all -- i.e. the last NEW value X takes before
-- the stream starts repeating (the stream is a function of its
-- previous value over a finite domain, so it must eventually cycle;
-- any value not seen before the cycle closes is never seen at all).
--
-- What the program computes between checks is a byte-at-a-time
-- hash in the FNV style: add a byte, mask to 24 bits, multiply by
-- a prime, mask again.  Each round feeds the previous check value
-- (widened with bit 16) through that hash one byte at a time.  The
-- device has no shift or divide instruction, so its @v \`div\` 256@
-- is a trial-multiply loop that eats ~95% of all executed
-- instructions -- which is exactly why Part 2 lifts the hash into
-- native Haskell instead of simulating it.
--
-- Concepts introduced this day:
--
--   * The /breakpoint/ pattern: Part 1 runs the real VM but stops
--     at a specific instruction instead of at halt -- no
--     understanding of the surrounding program required, only of
--     the one instruction that consults r0.
--
--   * Extracting constants from code instead of hard-coding them:
--     'hashSpec' pattern-matches the six-instruction hash template
--     out of the program text, so the lifted hash works for every
--     AoC input, not just ours (same trick as Day 19's
--     'Day19.firstSetupIp', pushed further).
--
--   * 'Data.IntSet' -- a set specialised to 'Int' keys (a big-endian
--     PATRICIA trie, not a balanced tree).  Same API shape as
--     'Data.Set', faster and leaner when the elements are machine
--     integers.  Rust analogue: roughly @HashSet\<u32\>@.
--
--   * Bit operators from "Data.Bits" in solution code: @.&.@ and
--     @.|.@ (Day 16 used them too, but hidden inside 'applyOp').
module Day21
  ( -- * Re-exports (the input format is exactly Day 19's)
    Program (..)
  , parseInput

    -- * Public answers
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests and GHCi)
  , checkInfo
  , runToFirstCheck
  , HashSpec (..)
  , hashSpec
  , nextProbe
  , probes
  ) where

import           Data.Bits          ((.&.), (.|.))
import qualified Data.Array         as A
import qualified Data.Array.Unboxed as U
import qualified Data.IntSet        as IS

import           Day16              (Op (..), applyOp)
import           Day19              (Program (..), parseInput)

-- ---------------------------------------------------------------------------
-- The halt check
-- ---------------------------------------------------------------------------

-- | Locate the halt check: the unique @eqrr@ that compares a
-- register against register 0.  Returns @(ip, reg)@ -- where the
-- check lives and which register it probes.  Everything else in
-- this module is anchored on this one instruction.
checkInfo :: Program -> (Int, Int)
checkInfo (Program _ is) =
  case [ (ip, reg) | (ip, i) <- A.assocs is, Just reg <- [probeReg i] ] of
    [hit] -> hit
    hits  -> error ("Day21.checkInfo: expected exactly one eqrr-vs-r0, found "
                    ++ show hits)
 where
  probeReg (Eqrr, a, 0, _) = Just a
  probeReg (Eqrr, 0, b, _) = Just b
  probeReg _               = Nothing

-- ---------------------------------------------------------------------------
-- Part 1: the VM with a breakpoint
-- ---------------------------------------------------------------------------

-- | Run the VM from all-zero registers until the instruction
-- pointer first lands on the halt check, and return the value of
-- the probed register at that moment.  This is Day 19's
-- 'Day19.runProgram' loop with one extra guard -- a breakpoint.
--
-- We never let the check execute, so register 0's value is
-- irrelevant; the first probe value arrives after only a few
-- thousand steps, well before the trial-divide loop cost matters.
runToFirstCheck :: Program -> Int
runToFirstCheck prog@(Program ipR is) = go 0 (U.listArray (0, 5) (replicate 6 0))
 where
  (checkIp, checkReg) = checkInfo prog
  bnds = A.bounds is
  go !ip !regs
    | ip == checkIp           = regs U.! checkReg
    | not (A.inRange bnds ip) = error "Day21.runToFirstCheck: halted before check"
    | otherwise =
        let (op, a, b, c) = is A.! ip
            regs'         = applyOp op a b c (regs U.// [(ipR, ip)])
            ip'           = (regs' U.! ipR) + 1
        in  go ip' regs'

-- | Part 1: the r0 that halts the program after the fewest
-- instructions -- the first value ever compared against it.
part1 :: Program -> Int
part1 = runToFirstCheck

-- ---------------------------------------------------------------------------
-- Part 2: lift the hash into native Haskell
-- ---------------------------------------------------------------------------

-- | The five constants that parameterise the hash loop.  Strict
-- fields: these are read millions of times in the inner loop and
-- must never be thunks.
data HashSpec = HashSpec
  { hashSeed :: !Int   -- ^ accumulator start each round (1765573 in our input)
  , hashMult :: !Int   -- ^ the FNV-style multiplier (65899)
  , hashMask :: !Int   -- ^ keep-24-bits mask (16777215 = 0xFFFFFF)
  , byteMask :: !Int   -- ^ low-byte mask (255); @byteMask + 1@ is the byte base
  , widenBit :: !Int   -- ^ OR'd onto the previous probe to start a round (65536)
  } deriving (Eq, Show)

-- | Pull the 'HashSpec' out of the program text.  Every published
-- AoC input is the same template with different constants, and the
-- template's @bori@ (the widen step) is the only @bori@ in the
-- whole program, so it anchors the match:
--
-- >  ip+0:  bori v  WIDEN  v      -- v   = prev | 0x10000
-- >  ip+1:  seti SEED  _   acc    -- acc = seed
-- >  ip+2:  bani v  BYTE   t      -- t   = v & 0xFF
-- >  ip+3:  addr acc t     acc    -- acc += t
-- >  ip+4:  bani acc MASK  acc    -- acc &= 0xFFFFFF
-- >  ip+5:  muli acc MULT  acc    -- acc *= 65899 (masked again at ip+6)
--
-- If a future input breaks the template we get a loud 'error', not
-- a silently wrong answer -- same contract as Day 19's
-- 'Day19.firstSetupIp'.
hashSpec :: Program -> HashSpec
hashSpec (Program _ is) =
  case [ ip | (ip, (Bori, _, _, _)) <- A.assocs is ] of
    [b] ->
      case (is A.! b, is A.! (b + 1), is A.! (b + 2), is A.! (b + 4), is A.! (b + 5)) of
        ( (Bori, _, widen, _)
          , (Seti, seed, _, _)
          , (Bani, _, byteM, _)
          , (Bani, _, mask, _)
          , (Muli, _, mult, _) )
          -> HashSpec seed mult mask byteM widen
        shape -> error ("Day21.hashSpec: unexpected hash template: " ++ show shape)
    bs -> error ("Day21.hashSpec: expected exactly one bori, found at " ++ show bs)

-- | One full round of the outer loop, computed natively: previous
-- probe value in, next probe value out.  Widen the input with bit
-- 16, then fold its bytes (low byte first) into the accumulator:
--
-- >  acc' = ((acc + byte) & 0xFFFFFF) * 65899 & 0xFFFFFF
--
-- The assembly grinds out @v \`div\` 256@ with a trial-multiply
-- loop; @div@ here does in one machine instruction what costs the
-- VM a couple of thousand.
nextProbe :: HashSpec -> Int -> Int
nextProbe (HashSpec seed mult mask byteM widen) prev = go seed (prev .|. widen)
 where
  go !acc !v
    | v <= byteM = acc'                       -- that was the last byte
    | otherwise  = go acc' (v `div` (byteM + 1))
   where
    acc' = (((acc + (v .&. byteM)) .&. mask) * mult) .&. mask

-- | The infinite stream of probe values, in the order the program
-- would compare them against r0.  @'iterate' f x@ is the lazy list
-- @[x, f x, f (f x), ..]@; the 'tail' drops the seed 0, which is a
-- register state, not a probe.
probes :: Program -> [Int]
probes prog = tail (iterate (nextProbe (hashSpec prog)) 0)

-- | Part 2: the r0 that halts the program after the /most/
-- instructions while still halting.  Each probe is a function of
-- the previous one over a finite domain (24 bits), so the stream
-- is eventually periodic; once any value repeats, no value outside
-- the already-seen set can ever appear.  The answer is therefore
-- the last fresh value before the first repeat.  'IS.member' \/
-- 'IS.insert' are the 'Data.Set' API specialised to 'Int'.
part2 :: Program -> Int
part2 prog = go IS.empty 0 (probes prog)
 where
  go !seen !prev (p : ps)
    | p `IS.member` seen = prev
    | otherwise          = go (IS.insert p seen) p ps
  go _ !prev []          = prev   -- unreachable: 'probes' is infinite

-- ---------------------------------------------------------------------------
-- Dispatcher
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let prog = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 prog))
  putStrLn ("  part 2: " ++ show (part2 prog))
