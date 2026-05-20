-- | One-off diagnostic for the Day 16 supplemental guide.
--
-- Loads @inputs/day16.txt@, runs Day 16's 'deduceCodes' to recover
-- the numeric-code -> 'Op' mapping for this particular input, then
-- prints:
--
--   1. The 16-entry opcode mapping table.
--   2. The per-code candidate set after constraint intersection
--      (the starting state of singleton elimination).
--   3. The singleton-elimination trace, one line per round, showing
--      which code resolves to which op and why.
--   4. The disassembled test program, one line per instruction:
--      @ip mnemonic  a b c   ; commentary@.
--   5. A step-by-step register trace of the test program (one row
--      per instruction).
--
-- Run from the repo root:
--
--     runghc -isrc scripts/day16_disassemble.hs > scripts/day16_disassembly.txt
--
-- The output is consumed by hand to write the analysis sections of
-- the @day16_disassembly.md@ supplement.

module Main where

import           Data.Array.Unboxed (elems, listArray)
import qualified Data.IntMap.Strict as IM
import           Data.IntMap.Strict (IntMap)
import           Data.List          (foldl', intercalate, sort)
import           Data.Maybe         (fromJust)
import           Data.Set           (Set)
import qualified Data.Set           as Set
import           Text.Printf        (printf)

import           Day16              (Op (..), Regs, Sample, allOps, applyOp,
                                     deduceCodes, matchingOps, parseInput,
                                     program, sInstr, samples)

main :: IO ()
main = do
  raw <- readFile "inputs/day16.txt"
  let p          = parseInput raw
      ss         = samples p
      codeOf     = deduceCodes ss
      prog       = program p
      cand0      = buildCandidates ss
      sampleCnt  = sampleCountByCode ss

  putStrLn "=== Opcode mapping (number -> mnemonic) ==="
  mapM_ (\(n, op) -> printf "  %2d -> %s\n" n (showOp op)) (IM.toList codeOf)

  putStrLn ""
  putStrLn "=== Per-code candidate set after constraint intersection ==="
  putStrLn "  Each line: 'code N (samples=K): {Op,Op,...}' -- the ops"
  putStrLn "  consistent with EVERY sample that uses code N.  Singletons"
  putStrLn "  here are forced by intersection alone; larger sets need the"
  putStrLn "  elimination loop to resolve."
  mapM_ (\n ->
    let ops = IM.findWithDefault Set.empty n cand0
        k   = IM.findWithDefault 0 n sampleCnt
    in  printf "  code %2d (samples=%3d): {%s}\n"
               n k (intercalate ", " (map showOp (Set.toAscList ops))))
    [0 .. 15]

  putStrLn ""
  putStrLn "=== Singleton elimination trace ==="
  putStrLn "  Each round: pick a code whose candidate set is a singleton"
  putStrLn "  {op}, fix code -> op, and remove op from every other code's"
  putStrLn "  candidate set.  Repeat to a fixed point."
  _ <- runEliminate cand0 1

  putStrLn ""
  putStrLn "=== Disassembled test program ==="
  mapM_ (\(ip, instr) ->
            printf "  %3d: %s\n" (ip :: Int) (disasm codeOf instr))
        (zip [0..] prog)

  putStrLn ""
  putStrLn "=== Step-by-step register trace ==="
  putStrLn "  ip  mnemonic    a b c   before              after"
  let initRegs = listArray (0, 3) [0, 0, 0, 0]
  _ <- foldM' (traceStep codeOf) initRegs (zip [0..] prog)
  pure ()

-- | foldl' that runs an IO action per step.
foldM' :: (a -> b -> IO a) -> a -> [b] -> IO a
foldM' _ acc []       = pure acc
foldM' f acc (x : xs) = do { acc' <- f acc x; acc' `seq` foldM' f acc' xs }

traceStep :: IM.IntMap Op -> Regs -> (Int, [Int]) -> IO Regs
traceStep codeOf regs (ip, instr) = case instr of
  [code, a, b, c] -> do
    let op    = codeOf IM.! code
        regs' = applyOp op a b c regs
    printf "  %3d  %-5s %2d %2d %2d  %-20s %-20s\n"
           ip
           (showOp op)
           a b c
           (show (elems regs))
           (show (elems regs'))
    pure regs'
  _ -> do
    printf "  malformed: %s\n" (show instr)
    pure regs

-- | A short, decoded one-line annotation for an instruction.
disasm :: IM.IntMap Op -> [Int] -> String
disasm codeOf [code, a, b, c] =
  printf "%-5s %2d %2d %2d   ; %s"
         (showOp op) a b c
         (commentary op a b c)
  where op = fromJust (IM.lookup code codeOf)
disasm _ instr = "malformed: " ++ show instr

-- | Render an 'Op' as the four-letter mnemonic used in the puzzle text.
showOp :: Op -> String
showOp Addr = "addr"; showOp Addi = "addi"
showOp Mulr = "mulr"; showOp Muli = "muli"
showOp Banr = "banr"; showOp Bani = "bani"
showOp Borr = "borr"; showOp Bori = "bori"
showOp Setr = "setr"; showOp Seti = "seti"
showOp Gtir = "gtir"; showOp Gtri = "gtri"; showOp Gtrr = "gtrr"
showOp Eqir = "eqir"; showOp Eqri = "eqri"; showOp Eqrr = "eqrr"

-- | Plain-English commentary per opcode (using r0..r3 for registers).
commentary :: Op -> Int -> Int -> Int -> String
commentary op a b c =
  case op of
    Addr -> printf "r%d = r%d + r%d" c a b
    Addi -> printf "r%d = r%d + %d"   c a b
    Mulr -> printf "r%d = r%d * r%d" c a b
    Muli -> printf "r%d = r%d * %d"   c a b
    Banr -> printf "r%d = r%d & r%d" c a b
    Bani -> printf "r%d = r%d & %d"   c a b
    Borr -> printf "r%d = r%d | r%d" c a b
    Bori -> printf "r%d = r%d | %d"   c a b
    Setr -> printf "r%d = r%d"        c a
    Seti -> printf "r%d = %d"         c a
    Gtir -> printf "r%d = (%d > r%d) ? 1 : 0"  c a b
    Gtri -> printf "r%d = (r%d > %d) ? 1 : 0"  c a b
    Gtrr -> printf "r%d = (r%d > r%d) ? 1 : 0" c a b
    Eqir -> printf "r%d = (%d == r%d) ? 1 : 0"  c a b
    Eqri -> printf "r%d = (r%d == %d) ? 1 : 0"  c a b
    Eqrr -> printf "r%d = (r%d == r%d) ? 1 : 0" c a b

-- ---------------------------------------------------------------------------
-- Deduction-trace helpers
-- ---------------------------------------------------------------------------

-- | Day 16's 'candidates0' verbatim: per-code, intersect 'matchingOps'
-- across every sample that uses that code.
buildCandidates :: [Sample] -> IntMap (Set Op)
buildCandidates =
  foldl' (\m s ->
            let code = head (sInstr s)
                ops  = Set.fromList (matchingOps s)
            in  IM.insertWith Set.intersection code ops m)
         IM.empty

-- | How many samples use each numeric code.  Used to annotate the
-- candidate-set table ("this code had K samples").
sampleCountByCode :: [Sample] -> IntMap Int
sampleCountByCode =
  foldl' (\m s -> IM.insertWith (+) (head (sInstr s)) 1 m) IM.empty

-- | Run Day 16's singleton-elimination loop, printing one line per
-- resolution: round, code, op, the candidate set just before this
-- pick (so the reader sees /why/ this code was a singleton this
-- round, e.g. "{Setr} -- forced by intersection alone" or
-- "{Setr, Addr} -> {Setr} after round 3 removed Addr").
runEliminate :: IntMap (Set Op) -> Int -> IO (IntMap Op)
runEliminate cand round_
  | IM.null cand = pure IM.empty
  | otherwise = case [ (code, Set.findMin os, os)
                     | (code, os) <- IM.toAscList cand
                     , Set.size os == 1 ] of
      [] -> do
        printf "  ROUND %2d: no singleton; deduction stuck.\n" round_
        pure IM.empty
      ((code, op, _) : _) -> do
        printf "  round %2d: code %2d -> %-5s   (was %s)\n"
               round_ code (showOp op)
               (showSet (cand IM.! code))
        let cand' = IM.map (Set.delete op) (IM.delete code cand)
        rest <- runEliminate cand' (round_ + 1)
        pure (IM.insert code op rest)

-- | Render a set of 'Op' as @{Op, Op, Op}@, sorted for readability.
showSet :: Set Op -> String
showSet s = "{" ++ intercalate ", " (map showOp (Set.toAscList s)) ++ "}"

-- Suppress an "unused" warning for the 'allOps' import (we re-derive
-- 'allOps' implicitly via the 'Bounded'/'Enum' instances; the import
-- is kept for future expansion).
_unusedAllOps :: [Op]
_unusedAllOps = allOps

-- Likewise for 'sort': handy when adding more analyses later.
_unusedSort :: Ord a => [a] -> [a]
_unusedSort = sort
