{-# LANGUAGE DeriveGeneric #-}

-- |
-- Module      : Day16
-- Description : Day 16 -- Chronal Classification
--
-- A tiny CPU with four registers and sixteen opcodes.  We are given
-- the /behaviour/ of each opcode (the 16 ALU operations -- @addr@,
-- @addi@, ...), but not which numeric code maps to which behaviour.
-- The input has two sections:
--
--   * /samples/: @Before@ register state, a raw 4-number instruction
--     @(op, a, b, c)@, and the @After@ register state it produced.
--   * /test program/: a straight list of raw instructions.
--
-- Part 1: how many samples are consistent with /three or more/ of the
-- sixteen operations?
--
-- Part 2: deduce the numeric-code to operation mapping by constraint
-- propagation across all samples, then run the test program from
-- zeroed registers and report register 0.
--
-- This is the first of the year's "build a tiny VM" puzzles (Days 16,
-- 19, 21 are the trilogy).  The shape is the same one as a bytecode
-- interpreter's dispatch loop: an opcode enum, a pure transition
-- @Op -> Instr -> Regs -> Regs@, and a table of all opcodes to fold
-- over.  Part 2 adds an /exact-matching/ deduction: each opcode
-- number's candidate set is the intersection of "ops that explain
-- this sample" over every sample with that number; then the classic
-- "find a singleton, assign it, eliminate it everywhere, repeat"
-- (the same elimination used for Sudoku naked singles, or for
-- resolving a bipartite perfect matching greedily when one exists).
--
-- Concepts introduced this day:
--
--   * An instruction set as a Haskell @data@ enum plus a single
--     pure interpreter function.  Compare a @clox@-style bytecode
--     VM: @Op@ is the opcode, 'applyOp' is the @switch@ in @run()@,
--     registers are the VM's locals.  Immediate vs register operands
--     are the @i@/@r@ suffix, decoded inside 'applyOp'.
--
--   * Constraint propagation by set intersection, then singleton
--     elimination, to solve a 16x16 assignment.  'Data.IntMap' of
--     code -> candidate 'Data.Set' of ops; iterate "remove a solved
--     op from every other candidate set" to a fixed point.
--
--   * @UArray Int Int@ as a fixed 4-cell register file, updated with
--     the bulk-update operator @(//)@.  Same unboxed-array primitive
--     as Days 9/11/14, used here as CPU state rather than a tape.
module Day16
  ( -- * Types
    Op (..)
  , Sample (..)
  , Puzzle (..)
  , Regs

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , allOps
  , applyOp
  , matchingOps
  , deduceCodes
  ) where

import           Control.DeepSeq    (NFData)
import           Data.Array.Unboxed (UArray, elems, listArray, (!), (//))
import           Data.Bits          ((.&.), (.|.))
import           Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IM
import           Data.List          (foldl')
import           Data.Set           (Set)
import qualified Data.Set           as Set
import           GHC.Generics       (Generic)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The four-register file.  A fixed-size unboxed array indexed
-- @0..3@ -- the puzzle's "registers 0 through 3".  Unboxed because
-- every cell is an 'Int' and the access pattern is read/overwrite,
-- exactly what 'UArray' is for.
type Regs = UArray Int Int

-- | The sixteen ALU operations.  An enum-style sum type (no payload;
-- the constructors are tags), the same shape as Day 13's 'Dir' and
-- Day 15's 'Kind'.  The @r@/@i@ suffix is the operand mode: @r@ =
-- "argument is a register number, read it"; @i@ = "argument is an
-- immediate, use it literally".
data Op
  = Addr | Addi | Mulr | Muli
  | Banr | Bani | Borr | Bori
  | Setr | Seti
  | Gtir | Gtri | Gtrr
  | Eqir | Eqri | Eqrr
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Every operation, derived from 'Enum'/'Bounded' so the list can
-- never drift out of sync with the 'Op' definition.
allOps :: [Op]
allOps = [minBound .. maxBound]

-- | One captured sample: registers before, the raw 4-number
-- instruction @[code, a, b, c]@, and registers after.
data Sample = Sample
  { sBefore :: ![Int]
  , sInstr  :: ![Int]
  , sAfter  :: ![Int]
  } deriving (Eq, Show, Generic)

instance NFData Sample

-- | Parsed input: the samples plus the test program (raw
-- instructions, each @[code, a, b, c]@).
data Puzzle = Puzzle
  { samples :: ![Sample]
  , program :: ![[Int]]
  } deriving (Eq, Show, Generic)

instance NFData Puzzle

-- ---------------------------------------------------------------------------
-- The interpreter
-- ---------------------------------------------------------------------------

-- | Apply one operation.  @applyOp op a b c regs@ is the new register
-- file after running @op@ with operands @a@, @b@ and output register
-- @c@.  This is the whole instruction set: the @switch@ a bytecode
-- VM would have in its inner loop, written as one total function.
--
-- Reading the suffixes: the first letter after the verb is operand
-- @A@'s mode, the second is operand @B@'s.  @r@ means "look up the
-- register numbered by this operand"; @i@ means "use this operand
-- literally".  @C@ is always a register to write.
applyOp :: Op -> Int -> Int -> Int -> Regs -> Regs
applyOp op a b c regs = regs // [(c, result)]
  where
    r i      = regs ! i                 -- register-mode read
    bool t   = if t then 1 else 0       -- comparisons store 0/1
    result   = case op of
      Addr -> r a +   r b
      Addi -> r a +   b
      Mulr -> r a *   r b
      Muli -> r a *   b
      Banr -> r a .&. r b
      Bani -> r a .&. b
      Borr -> r a .|. r b
      Bori -> r a .|. b
      Setr -> r a
      Seti -> a
      Gtir -> bool (a   >  r b)
      Gtri -> bool (r a >  b)
      Gtrr -> bool (r a >  r b)
      Eqir -> bool (a   == r b)
      Eqri -> bool (r a == b)
      Eqrr -> bool (r a == r b)

-- | The operations consistent with a single sample: those whose
-- effect on @Before@ (using the sample's @a, b, c@) produces exactly
-- @After@.  The opcode /number/ is ignored here -- that is the whole
-- point of a sample.
matchingOps :: Sample -> [Op]
matchingOps (Sample before [_, a, b, c] after) =
  [ op
  | op <- allOps
  , elems (applyOp op a b c (toRegs before)) == after
  ]
matchingOps s = error ("Day16.matchingOps: malformed sample " ++ show s)

-- | A 4-element list to a register file.
toRegs :: [Int] -> Regs
toRegs = listArray (0, 3)

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Pull every run of digits out of a line as 'Int's.  Replacing all
-- non-digits with spaces and then 'words' is the cheapest way to
-- ignore the @"Before: ["@, commas and brackets without a real
-- parser -- the same trick Day 4 used for timestamps.
nums :: String -> [Int]
nums = map read . words . map (\ch -> if ch `elem` "0123456789" then ch else ' ')

-- | Split into the samples section and the test program.
--
-- Drop blank lines, then peel @Before@/instr/@After@ triples off the
-- front for as long as the next line starts with @\"Before\"@.  The
-- first line that does not is the start of the test program; every
-- remaining non-blank line is one program instruction.
parseInput :: String -> Puzzle
parseInput raw = go (filter (not . null) (lines raw)) []
  where
    go (b : i : a : rest) acc
      | take 6 b == "Before" =
          go rest (Sample (nums b) (nums i) (nums a) : acc)
    go rest acc =
      Puzzle (reverse acc) (map nums rest)

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | How many samples are explained by three or more operations.
part1 :: Puzzle -> Int
part1 (Puzzle ss _) =
  length [ () | s <- ss, length (matchingOps s) >= 3 ]

-- ---------------------------------------------------------------------------
-- Part 2: deduce the opcode numbers
-- ---------------------------------------------------------------------------

-- | Resolve every numeric opcode (0..15) to its 'Op' by constraint
-- propagation.
--
-- Step 1 (constraint intersection): for each sample, the operation
-- behind its numeric code must be one of @matchingOps@.  Intersect
-- those candidate sets across every sample sharing a code, giving
-- @code -> Set Op@ of still-possible operations.
--
-- Step 2 (singleton elimination): repeatedly take a code whose
-- candidate set has exactly one operation, fix that assignment, and
-- delete that operation from every other code's candidates.  A
-- well-formed AoC input always collapses to a unique solution this
-- way -- the same "naked single" rule that cracks easy Sudoku, and
-- the greedy resolution of a bipartite perfect matching when one is
-- guaranteed to exist.
deduceCodes :: [Sample] -> IntMap Op
deduceCodes ss = solve' candidates0 IM.empty
  where
    -- code -> intersection of matching-op sets over its samples
    candidates0 :: IntMap (Set Op)
    candidates0 =
      foldl'
        (\m s ->
           let code = head (sInstr s)
               ops  = Set.fromList (matchingOps s)
           in  IM.insertWith Set.intersection code ops m)
        IM.empty
        ss

    solve' :: IntMap (Set Op) -> IntMap Op -> IntMap Op
    solve' cand solved
      | IM.null cand = solved
      | otherwise =
          case [ (code, Set.findMin os)
               | (code, os) <- IM.toList cand
               , Set.size os == 1 ] of
            []            -> error "Day16.deduceCodes: no singleton; \
                                   \input underdetermined"
            ((code, op) : _) ->
              let cand'   = IM.map (Set.delete op) (IM.delete code cand)
                  solved' = IM.insert code op solved
              in  solve' cand' solved'

-- | Run the test program from zeroed registers under a resolved
-- opcode table; return the final register file.
runProgram :: IntMap Op -> [[Int]] -> Regs
runProgram codeOf = foldl' step (listArray (0, 3) [0, 0, 0, 0])
  where
    step regs [code, a, b, c] = applyOp (codeOf IM.! code) a b c regs
    step _ instr = error ("Day16.runProgram: malformed instr " ++ show instr)

-- | Part 2: register 0 after running the test program.
part2 :: Puzzle -> Int
part2 (Puzzle ss prog) = runProgram (deduceCodes ss) prog ! 0

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
