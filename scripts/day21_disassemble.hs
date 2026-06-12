-- | One-off diagnostic for the Day 21 supplemental guide.
--
-- Loads @inputs/day21.txt@ and prints:
--
--   1. The disassembled program with jump-aware commentary: because
--      the IP is bound to a register, any instruction writing that
--      register is rendered as the jump it actually is
--      (@seti 27 0 2@ becomes @goto 28@), not as arithmetic.
--   2. The halt check ('checkInfo') and the extracted 'HashSpec'.
--   3. A step-by-step register trace of the first 45 instructions
--      (self-test, round header, first byte-feed, and the first few
--      trial-divide iterations).
--   4. An execution profile of the full run to the first check:
--      per-IP execution counts, showing where the 1,846 steps go.
--   5. The probe stream: first ten probes, the distinct count
--      before the first repeat, and which earlier probe the stream
--      closes its cycle onto.
--   6. The exact instruction counts the puzzle statement asks
--      about: how many instructions execute before halt with
--      r0 = Part 1's answer (fewest) and r0 = Part 2's answer
--      (most).  Computed with a per-round cost model derived from
--      the program template, cross-checked against the real VM for
--      the first two check arrivals.
--
-- Run from the repo root:
--
--     runghc -isrc scripts/day21_disassemble.hs > scripts/day21_disassembly.txt
--
-- The output is consumed by hand to write the analysis sections of
-- the @day21_disassembly.md@ supplement.

{-# LANGUAGE BangPatterns #-}

module Main where

import qualified Data.Array         as A
import qualified Data.Array.Unboxed as U
import           Data.Bits          ((.|.))
import qualified Data.IntMap.Strict as IM
import           Text.Printf        (printf)

import           Day16              (Op (..), Regs, applyOp)
import           Day19              (Program (..))
import           Day21              (HashSpec (..), checkInfo, hashSpec,
                                     nextProbe, parseInput, part1, part2,
                                     probes)

main :: IO ()
main = do
  raw <- readFile "inputs/day21.txt"
  let prog@(Program ipR is) = parseInput raw
      (checkIp, checkReg)   = checkInfo prog
      spec                  = hashSpec prog

  putStrLn ("=== Disassembly (ip bound to r" ++ show ipR ++ ") ===")
  mapM_ (\(ip, instr) ->
            printf "  %2d: %s\n" ip (disasm ipR ip instr))
        (A.assocs is)

  putStrLn ""
  putStrLn "=== The halt check ==="
  printf "  checkInfo = (ip %d, register %d)\n" checkIp checkReg
  printf "  i.e. the program halts iff r%d == r0 when ip %d executes;\n"
         checkReg checkIp
  putStrLn "  r0 is read nowhere else in the program."

  putStrLn ""
  putStrLn "=== Extracted hash constants (hashSpec) ==="
  printf "  hashSeed = %-10d  (accumulator start each round)\n" (hashSeed spec)
  printf "  hashMult = %-10d  (FNV-style multiplier)\n"         (hashMult spec)
  printf "  hashMask = %-10d  (0x%X, keep 24 bits)\n" (hashMask spec) (hashMask spec)
  printf "  byteMask = %-10d  (0x%X, low byte)\n"     (byteMask spec) (byteMask spec)
  printf "  widenBit = %-10d  (0x%X, OR'd onto the previous probe)\n"
         (widenBit spec) (widenBit spec)

  putStrLn ""
  putStrLn "=== First 45 steps, traced ==="
  putStrLn "  step  ip  instruction        regs after        [r0,r1,r2,r3,r4,r5]"
  let regs0 = U.listArray (0, 5) (replicate 6 0) :: Regs
  traceSteps ipR is 45 0 regs0 1

  putStrLn ""
  putStrLn "=== Execution profile: run to the first check ==="
  putStrLn "  Per-IP execution counts over the full run from power-on to"
  putStrLn "  the first arrival at the check (the check itself not executed)."
  let counts = profileToCheck ipR is checkIp
      total  = sum (IM.elems counts)
  mapM_ (\(ip, instr) ->
            let n = IM.findWithDefault 0 ip counts
            in printf "  %2d: %6d  (%5.1f%%)  %s\n"
                      ip n (100 * fromIntegral n / fromIntegral total :: Double)
                      (disasm ipR ip instr))
        (A.assocs is)
  printf "  total steps to first check: %d\n" total

  putStrLn ""
  putStrLn "=== The probe stream ==="
  let ps = probes prog
  putStrLn "  First ten probes (the first is Part 1's answer):"
  mapM_ (\(i, p) -> printf "    #%-2d  %d\n" (i :: Int) p)
        (zip [1 ..] (take 10 ps))
  let (distinct, lastNew, repeated, origIdx) = streamStats ps
  printf "  distinct probes before the first repeat: %d\n" distinct
  printf "  last new probe (Part 2's answer): #%d = %d\n" distinct lastNew
  printf "  first repeat: probe #%d = %d, same as probe #%d\n"
         (distinct + 1) repeated origIdx
  printf "  part1 prog = %d\n" (part1 prog)
  printf "  part2 prog = %d\n" (part2 prog)

  putStrLn ""
  putStrLn "=== Exact instruction counts (what the puzzle text asks about) ==="
  putStrLn "  Per-round cost model (this input's template; q = v `div` 256):"
  putStrLn "    self-test: 4 (the bani check passes, ip 4 is skipped)"
  putStrLn "    power-on r4 = 0: 1"
  putStrLn "    round header (bori + seti): 2"
  putStrLn "    non-final byte: 8 hash + 1 + 7q + 5 trial-divide + 2 = 16 + 7q"
  putStrLn "    final byte: 8;  check: 3 if not halting, 2 if halting"
  let prevs     = 0 : ps   -- round r hashes probe r-1 (round 1 hashes 0)
      atCheck n = 4 + 1 + sum [ 2 + roundBytes spec p | p <- take n prevs ]
                  + 3 * (n - 1)
      halting n = atCheck n + 2          -- the eqrr and the addr that jumps out
      vmCheck   = vmStepsToChecks ipR is checkIp 2
  printf "  model cross-check vs the real VM (steps at 1st and 2nd check):\n"
  printf "    VM:    %s\n" (show vmCheck)
  printf "    model: %s\n" (show [atCheck 1, atCheck 2])
  printf "  fewest instructions (halt at check #1,  r0 = %d): %d\n"
         (part1 prog) (halting 1)
  printf "  most instructions   (halt at check #%d, r0 = %d): %d\n"
         distinct (part2 prog) (halting distinct)

-- ---------------------------------------------------------------------------
-- Disassembly rendering
-- ---------------------------------------------------------------------------

-- | One disassembled line: mnemonic, operands, and a comment.  When
-- the destination is the IP-bound register the comment renders the
-- jump the instruction actually performs (including the post-step
-- @+1@), not the raw arithmetic.
disasm :: Int -> Int -> (Op, Int, Int, Int) -> String
disasm ipR ip instr@(op, a, b, c) =
  printf "%-4s %8d %8d %d   ; %s" (showOp op) a b c comment
 where
  comment
    | c /= ipR  = plain ipR instr
    | otherwise = case op of
        Seti                -> printf "goto %d" (a + 1)
        Addi | a == ipR     -> printf "goto %d" (ip + b + 1)
        Addr | a == ipR     -> printf "ip += r%d -> if r%d == 1: skip next" b b
             | b == ipR     -> printf "ip += r%d -> if r%d == 1: skip next" a a
        Mulr | a == ipR
            && b == ipR     -> "ip = ip * ip (jump out of range = halt)"
        _                   -> plain ipR instr ++ "  (writes the IP!)"

-- | Plain-English commentary, Day 16 style, six registers wide.
plain :: Int -> (Op, Int, Int, Int) -> String
plain _ (op, a, b, c) = case op of
  Addr -> printf "r%d = r%d + r%d"  c a b
  Addi -> printf "r%d = r%d + %d"   c a b
  Mulr -> printf "r%d = r%d * r%d"  c a b
  Muli -> printf "r%d = r%d * %d"   c a b
  Banr -> printf "r%d = r%d & r%d"  c a b
  Bani -> printf "r%d = r%d & %d"   c a b
  Borr -> printf "r%d = r%d | r%d"  c a b
  Bori -> printf "r%d = r%d | %d"   c a b
  Setr -> printf "r%d = r%d"        c a
  Seti -> printf "r%d = %d"         c a
  Gtir -> printf "r%d = (%d > r%d) ? 1 : 0"   c a b
  Gtri -> printf "r%d = (r%d > %d) ? 1 : 0"   c a b
  Gtrr -> printf "r%d = (r%d > r%d) ? 1 : 0"  c a b
  Eqir -> printf "r%d = (%d == r%d) ? 1 : 0"  c a b
  Eqri -> printf "r%d = (r%d == %d) ? 1 : 0"  c a b
  Eqrr -> printf "r%d = (r%d == r%d) ? 1 : 0" c a b

showOp :: Op -> String
showOp Addr = "addr"; showOp Addi = "addi"
showOp Mulr = "mulr"; showOp Muli = "muli"
showOp Banr = "banr"; showOp Bani = "bani"
showOp Borr = "borr"; showOp Bori = "bori"
showOp Setr = "setr"; showOp Seti = "seti"
showOp Gtir = "gtir"; showOp Gtri = "gtri"; showOp Gtrr = "gtrr"
showOp Eqir = "eqir"; showOp Eqri = "eqri"; showOp Eqrr = "eqrr"

-- ---------------------------------------------------------------------------
-- VM instrumentation
-- ---------------------------------------------------------------------------

-- | Print the first @n@ steps of execution.
traceSteps :: Int -> A.Array Int (Op, Int, Int, Int)
           -> Int -> Int -> Regs -> Int -> IO ()
traceSteps ipR is n ip regs step
  | step > n                       = pure ()
  | not (A.inRange (A.bounds is) ip) = putStrLn "  (halted)"
  | otherwise = do
      let instr@(op, a, b, c) = is A.! ip
          regs' = applyOp op a b c (regs U.// [(ipR, ip)])
          ip'   = (regs' U.! ipR) + 1
      printf "  %4d  %2d  %-4s %8d %8d %d   %s\n"
             step ip (showOp op) a b c (show (U.elems regs'))
      traceSteps ipR is n ip' regs' (step + 1)

-- | Per-IP execution counts from power-on until the IP first lands
-- on the check (the check is not executed or counted).
profileToCheck :: Int -> A.Array Int (Op, Int, Int, Int) -> Int -> IM.IntMap Int
profileToCheck ipR is checkIp =
  go 0 (U.listArray (0, 5) (replicate 6 0) :: Regs) IM.empty
 where
  go !ip !regs !counts
    | ip == checkIp = counts
    | otherwise =
        let (op, a, b, c) = is A.! ip
            regs'         = applyOp op a b c (regs U.// [(ipR, ip)])
            ip'           = (regs' U.! ipR) + 1
        in  go ip' regs' (IM.insertWith (+) ip 1 counts)

-- | Step counts at the first @n@ arrivals of the IP on the check.
-- (The check still executes after each arrival -- with r0 = 0 it
-- never halts -- so the run continues to the next arrival.)
vmStepsToChecks :: Int -> A.Array Int (Op, Int, Int, Int) -> Int -> Int -> [Int]
vmStepsToChecks ipR is checkIp =
  go 0 (U.listArray (0, 5) (replicate 6 0) :: Regs) 0
 where
  go !ip !regs !steps k
    | k == 0    = []
    | otherwise =
        let arrived       = ip == checkIp
            k'            = if arrived then k - 1 else k
            (op, a, b, c) = is A.! ip
            regs'         = applyOp op a b c (regs U.// [(ipR, ip)])
            ip'           = (regs' U.! ipR) + 1
        in  [steps | arrived] ++ go ip' regs' (steps + 1) k'

-- ---------------------------------------------------------------------------
-- Probe-stream statistics and the instruction-cost model
-- ---------------------------------------------------------------------------

-- | (distinct count, last new value, first repeated value, index of
-- the probe it repeats).
streamStats :: [Int] -> (Int, Int, Int, Int)
streamStats = go IM.empty 0 1
 where
  go !firstIdx !prev !i (p : ps) =
    case IM.lookup p firstIdx of
      Just j  -> (i - 1, prev, p, j)
      Nothing -> go (IM.insert p i firstIdx) p (i + 1) ps
  go _ prev i [] = (i - 1, prev, 0, 0)   -- unreachable: stream is infinite

-- | VM instructions spent hashing one probe (everything between the
-- round header and the check): per non-final byte 16 + 7q where
-- q = v `div` 256 is the trial-divide quotient, final byte 8.
roundBytes :: HashSpec -> Int -> Int
roundBytes spec prev = go (prev .|. widenBit spec)
 where
  go v
    | v <= byteMask spec = 8
    | otherwise          = let q = v `div` (byteMask spec + 1)
                           in  16 + 7 * q + go q

-- Suppress unused warnings for imports kept for interactive use.
_unusedNextProbe :: HashSpec -> Int -> Int
_unusedNextProbe = nextProbe
