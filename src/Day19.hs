{-# LANGUAGE BangPatterns  #-}
{-# LANGUAGE DeriveGeneric #-}

-- |
-- Module      : Day19
-- Description : Day 19 -- Go With The Flow
--
-- The same six-letter ALU as Day 16 -- @addr@, @addi@, ..., @eqrr@ --
-- with one twist: the /instruction pointer/ can be bound to one of
-- the six registers.  Before each instruction the current IP is
-- copied /into/ the bound register; after the instruction runs the
-- bound register is copied back /out/ to the IP, which is then
-- incremented by one.  Execution halts when the IP falls outside
-- the program.  This turns @setr@/@seti@ into absolute jumps,
-- @addr@/@addi@ into relative jumps, and lets the assembler express
-- loops without any real branch opcode.
--
-- The input has two parts:
--
--   * a @#ip N@ directive saying which register is bound to the IP;
--   * a list of instructions, each @mnemonic a b c@ (now we get the
--     names, not the numeric codes -- contrast Day 16).
--
-- Part 1: run from all-zero registers and report register 0.
--
-- Part 2: run with register 0 initialised to /one/ and report
-- register 0.  The naive simulator does not finish in any
-- reasonable time -- the program is a brute-force divisor sum on a
-- number around 10^7, i.e. about 10^14 inner-loop iterations.  Read
-- the assembly, recognise the pattern, and compute the answer in
-- O(sqrt N) instead.  This is the calendar's marquee
-- reverse-engineering puzzle.
--
-- Concepts introduced this day:
--
--   * Reverse-engineering a tiny assembly program from a short
--     trace, then replacing the simulation with a closed-form
--     calculation when Part 2's iteration count blows up.  The
--     simulator is correct, just too slow; the algorithm has to
--     come out of /reading the code/.
--
--   * The "binding the IP to a register" trick.  Concretely: write
--     the IP into the bound register, run one ALU step, read the
--     bound register back as the new IP, +1.  Same effect as a
--     real CPU's program counter -- this is how the program can
--     jump at all.
--
--   * @Array Int Instr@ for O(1) instruction fetch by IP.  Boxed,
--     because each instruction is an ADT tuple, not an unboxed
--     primitive; the program is small (35 ops) so a boxed array
--     is fine.  Contrast Day 16's program, which was a straight
--     'foldl'' over a list because the IP was always +1.
--
--   * Reusing 'Day16.applyOp'.  The ALU is identical; only the
--     control flow changes.
module Day19
  ( -- * Re-exports from Day 16
    Op (..)
  , Regs

    -- * Day-19-specific types
  , Instr
  , Program (..)

    -- * Public answers
  , parseInput
  , part1
  , part2
  , solve

    -- * Building blocks (exposed for tests)
  , runProgram
  , runUntilSetupComplete
  , sumOfDivisors
  , firstSetupIp
  ) where

import           Control.DeepSeq    (NFData (..))
import           Data.Array         (Array)
import qualified Data.Array         as A
import qualified Data.Array.Unboxed as U
import           GHC.Generics       (Generic)

import           Day16              (Op (..), Regs, applyOp)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | One decoded instruction: opcode plus three integer operands
-- @(op, a, b, c)@.  Operand semantics are exactly Day 16's -- the
-- @r@/@i@ suffix of the opcode says which of @a@ and @b@ are
-- registers vs immediates; @c@ is always a destination register.
type Instr = (Op, Int, Int, Int)

-- | A parsed program: which register is bound to the instruction
-- pointer, plus the instructions indexed by IP.  Storing
-- instructions in a boxed 'Array' (rather than a list) gives O(1)
-- fetch by IP, which matters because the program jumps.
data Program = Program
  { ipReg  :: !Int                  -- ^ register number bound to the IP
  , instrs :: !(Array Int Instr)    -- ^ instructions, indexed from 0
  } deriving (Eq, Show, Generic)

instance NFData Program where
  -- Force the spine of the instruction array and every element.
  -- 'deepseq' has no 'NFData' instance for 'Data.Array.Array', so
  -- we walk 'A.elems' ourselves; per-element 'rnf' then delegates
  -- to the tuple-4 instance (which now has 'NFData Op').
  rnf (Program i a) = i `seq` walk (A.elems a)
    where
      walk []         = ()
      walk (e : rest) = rnf e `seq` walk rest

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse the input.  First non-blank line is @#ip N@ (binding
-- declaration); every following non-blank line is one instruction.
parseInput :: String -> Program
parseInput raw =
  case filter (not . null) (lines raw) of
    (h : rest) | take 3 h == "#ip" ->
      let ipR  = read (drop 4 h)
          is   = map parseInstr rest
          arr  = A.listArray (0, length is - 1) is
      in  Program ipR arr
    _ -> error "Day19.parseInput: missing #ip directive"

-- | One instruction line: @\"mnemonic a b c\"@.
parseInstr :: String -> Instr
parseInstr line = case words line of
  [op, a, b, c] -> (parseOp op, read a, read b, read c)
  _             -> error ("Day19.parseInstr: " ++ line)

-- | Lowercase mnemonic to 'Op'.  Day 16 only ever saw the numeric
-- codes, so it never needed this; Day 19's input is by name.
parseOp :: String -> Op
parseOp s = case s of
  "addr" -> Addr ; "addi" -> Addi
  "mulr" -> Mulr ; "muli" -> Muli
  "banr" -> Banr ; "bani" -> Bani
  "borr" -> Borr ; "bori" -> Bori
  "setr" -> Setr ; "seti" -> Seti
  "gtir" -> Gtir ; "gtri" -> Gtri ; "gtrr" -> Gtrr
  "eqir" -> Eqir ; "eqri" -> Eqri ; "eqrr" -> Eqrr
  _      -> error ("Day19.parseOp: unknown mnemonic " ++ show s)

-- ---------------------------------------------------------------------------
-- Interpreter
-- ---------------------------------------------------------------------------

-- | Six zeroed registers, except register 0 set to the seed value
-- the caller wants (0 for Part 1, 1 for Part 2).
initRegs :: Int -> Regs
initRegs r0 = U.listArray (0, 5) [r0, 0, 0, 0, 0, 0]

-- | Run the program from the given starting registers to halt.
-- /Halt/ means "the IP falls outside the instruction array".
--
-- One step is the literal definition from the puzzle text:
--
--   1. Write the current IP into the bound register.
--   2. Run the instruction at that IP (Day 16's 'applyOp').
--   3. Read the bound register back out as the new IP.
--   4. Add one.
--
-- The strict bang patterns on @ip@ and @regs@ keep the tail
-- recursion allocation-free; on Part 1 this loop runs about a
-- thousand iterations, on Part 2's brute simulation it would run
-- ~10^14.  Part 2's escape is /not/ running this loop -- see
-- 'part2' below.
runProgram :: Program -> Regs -> Regs
runProgram (Program ipR is) = go 0
 where
  bnds = A.bounds is
  go !ip !regs
    | not (A.inRange bnds ip) = regs
    | otherwise =
        let (op, a, b, c) = is A.! ip
            regs'         = applyOp op a b c (regs U.// [(ipR, ip)])
            ip'           = (regs' U.! ipR) + 1
        in  go ip' regs'

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Part 1: run to halt from all-zero registers, return register 0.
part1 :: Program -> Int
part1 prog = runProgram prog (initRegs 0) U.! 0

-- ---------------------------------------------------------------------------
-- Part 2: reverse engineering
-- ---------------------------------------------------------------------------
--
-- The Day 19 input has a very specific shape:
--
--   ip=0: addi <ipR> K <ipR>     -- "jump K+1 ahead": into the setup
--   ip=1..K: the main loop (a doubly nested counter)
--   ip=K+1..end: setup that populates a register with a target
--                value N, then jumps back to ip=1
--
-- The main loop is a textbook brute-force divisor sum:
--
--     r0 = 0
--     for r5 in 1..N:
--       for r3 in 1..N:
--         if r5 * r3 == N:
--           r0 += r5
--     halt
--
-- i.e. @r0 = sum [ d | d <- [1..N], N \`mod\` d == 0 ]@ -- the sum
-- of divisors of N.  With N around 10^7 the simulator's roughly
-- N^2 = 10^14 inner iterations are completely out of reach, but
-- the answer is trivially computable in O(sqrt N) once we know
-- what N is.
--
-- The setup phase computes N differently depending on the initial
-- value of register 0 (Part 1 vs Part 2).  So the plan is: simulate
-- only the setup phase with the right seed, harvest N out of the
-- registers, and compute @sumOfDivisors N@ directly.

-- | The first IP that belongs to the /setup/ region, derived from
-- the program itself.  The first instruction is invariably
-- @addi <ipR> K <ipR>@, meaning "@r_ipR += K@"; the post-step
-- increment then puts the IP at @K + 1@, which is where setup
-- begins.
firstSetupIp :: Program -> Int
firstSetupIp (Program _ is) = case is A.! 0 of
  (Addi, _, k, _) -> k + 1
  i               -> error ("Day19.firstSetupIp: expected 'addi' at ip=0, got: "
                            ++ show i)

-- | Step the program forward only as long as setup is still doing
-- something.  We are looking for the moment control transfers
-- back to the main loop: the first step at which the IP is in
-- @[0 .. firstSetupIp - 1]@ after having visited @[firstSetupIp ..]@.
-- At that point the registers hold the divisor-sum target the
-- main loop is about to grind through.
runUntilSetupComplete :: Program -> Regs -> Regs
runUntilSetupComplete prog@(Program ipR is) regs0 = go 0 regs0 False
 where
  bnds        = A.bounds is
  setupStart  = firstSetupIp prog
  go !ip !regs !visited
    | not (A.inRange bnds ip)         = regs       -- safety net
    | ip < setupStart && visited      = regs       -- back in main loop
    | otherwise =
        let (op, a, b, c) = is A.! ip
            regs'         = applyOp op a b c (regs U.// [(ipR, ip)])
            ip'           = (regs' U.! ipR) + 1
        in  go ip' regs' (visited || ip >= setupStart)

-- | Sum of positive divisors of @n@.  Pairs each divisor @d <= sqrt n@
-- with its complement @n \`div\` d@, so the loop runs in O(sqrt n)
-- instead of O(n).  Perfect squares contribute their square root
-- once, not twice.
--
-- Example: @sumOfDivisors 28 = 1 + 2 + 4 + 7 + 14 + 28 = 56@.
sumOfDivisors :: Int -> Int
sumOfDivisors n
  | n <= 0 = 0
  | otherwise =
      sum [ d + complement d
          | d <- [1 .. isqrt n]
          , n `mod` d == 0
          ]
 where
  complement d
    | d * d == n = 0                                  -- avoid double-counting
    | otherwise  = n `div` d
  isqrt :: Int -> Int
  isqrt = floor . (sqrt :: Double -> Double) . fromIntegral

-- | Part 2: simulate only the setup phase with register 0 = 1, read
-- the divisor-sum target out of the registers (it is the largest
-- value -- the others are tiny scratch values and the IP itself),
-- then compute the sum of divisors directly.
part2 :: Program -> Int
part2 prog =
  let regs = runUntilSetupComplete prog (initRegs 1)
      n    = maximum (U.elems regs)
  in  sumOfDivisors n

-- ---------------------------------------------------------------------------
-- Dispatcher
-- ---------------------------------------------------------------------------

solve :: String -> IO ()
solve contents = do
  let prog = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 prog))
  putStrLn ("  part 2: " ++ show (part2 prog))
