# Day 19: Go With The Flow -- Function Guide

**Problem**: The same six-letter ALU as Day 16, but the instruction
pointer can now be *bound to a register*: each step, the IP is
copied into the bound register, the instruction runs, then the
bound register is copied back to the IP and incremented. This is
how the device gets `jmp` without a real branch opcode.
Part 1: run from all zeros, report register 0. Part 2: run with
register 0 = 1, report register 0.

**Answers**: Part 1 = **1620**, Part 2 = **15827082**
**Code**: [Day19.hs](../../src/Day19.hs) · **Python reference**: [day19.py](../../python/day19.py)
**Runtime**: Parse 56.7 µs · Part 1 194.0 ms · Part 2 5.7 µs · Total ≈ 194.1 ms

**New concepts this day**:

- **Reverse-engineering a tiny assembly program.** Part 2's
  simulator would run for ~10^14 inner-loop iterations. The point
  is *not* to make the simulator faster — it is to read the
  assembly, notice it is a brute-force divisor sum, and compute
  σ(N) in O(√N) instead. This is the calendar's marquee
  reverse-engineering puzzle and the centrepiece of the
  Days 16/19/21 VM trilogy.
- **Binding the IP to a register.** A concrete recipe for making
  any register file into a program counter: write the IP in, run
  one ALU step, read the IP back out, +1. This is structurally how
  every real CPU works, demystified.
- **Reusing a previous day's interpreter.** Day 16 exported
  `Op`/`applyOp`; Day 19 imports them verbatim and bolts on the
  control flow. The first time a module in this project depends on
  another puzzle's code.
- **`Data.Array` (boxed) for O(1) instruction fetch.** Instructions
  are tuples of an ADT and three `Int`s — not unboxable — so the
  program lives in `Array Int Instr`. Contrast Day 16's straight
  list (`foldl'` was always +1), and Day 11/14's `UArray` for
  primitives.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Reading the assembly: where σ(N) comes from](#reading-the-assembly-where-σn-comes-from)
- [Data model](#data-model)
- [`parseInput`](#parseinput)
- [`runProgram` -- the simulator](#runprogram----the-simulator)
- [`firstSetupIp` and `runUntilSetupComplete`](#firstsetupip-and-rununtilsetupcomplete)
- [`sumOfDivisors`](#sumofdivisors)
- [`part1`, `part2`, `solve`](#part1-part2-solve)
- [Why Part 1 is 30,000× slower than Part 2](#why-part-1-is-30000-slower-than-part-2)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

The Day 16 device gets one quality-of-life upgrade: a register can
be *bound to the instruction pointer* via a `#ip N` declaration. The
puzzle text spells out the contract precisely:

> The instruction pointer's value is written to the bound register
> just before each instruction executes, and the value of that
> register is written back to the instruction pointer immediately
> after each instruction finishes. Afterward, move to the next
> instruction by adding one to the instruction pointer.

That mechanism turns ordinary opcodes into jumps:

- `setr` / `seti` writing into the bound register ⇒ an **absolute
  jump** (the new IP becomes whatever value was set, +1).
- `addr` / `addi` on the bound register ⇒ a **relative jump**.
- `eqrr` / `gtrr` followed by `addr <result> <ipR> <ipR>` ⇒ a
  **conditional skip** (skip the next instruction if the test
  passed).

Part 1 runs the program from all-zero registers and asks for
register 0. The naive simulator finishes in a couple of seconds —
slow, but tractable. Part 2 sets register 0 to **one** and asks
again; *that* run, naively simulated, would take roughly a million
years. The puzzle is daring you to read the program.

---

## The algorithm in Python

The shipping solution is [Day19.hs](../../src/Day19.hs); the
algorithm reads cleaner without Haskell's `NFData` / unboxed-array
plumbing in the way, so the side-by-side is
[python/day19.py](../../python/day19.py). The two files compute the
same answers from the same input.

```python
def apply_op(op, a, b, c, regs):
    """Day 16's ALU, verbatim."""
    out = list(regs)
    r = regs.__getitem__
    if   op == "addr": out[c] = r(a) + r(b)
    elif op == "addi": out[c] = r(a) + b
    elif op == "mulr": out[c] = r(a) * r(b)
    elif op == "muli": out[c] = r(a) * b
    # ... eleven more cases ...
    return out

def run(ip_reg, program, regs):
    """One step = write IP in, run op, read IP back, +1."""
    ip = 0
    while 0 <= ip < len(program):
        op, a, b, c = program[ip]
        regs = apply_op(op, a, b, c,
                        regs[:ip_reg] + [ip] + regs[ip_reg+1:])
        ip = regs[ip_reg] + 1
    return regs

def sum_of_divisors(n):
    """O(sqrt n) divisor sum."""
    total = 0
    for d in range(1, isqrt(n) + 1):
        if n % d == 0:
            total += d
            if d * d != n:
                total += n // d
    return total

def part2(ip_reg, program):
    # Run only the setup phase -- a few dozen steps.
    regs = run_until_setup_complete(ip_reg, program, [1, 0, 0, 0, 0, 0])
    n = max(regs)                       # the divisor-sum target
    return sum_of_divisors(n)
```

The Haskell `Day19.runProgram` is the loop above; the Haskell
`part2` is exactly that closed form.

---

## Reading the assembly: where σ(N) comes from

The input has a very specific shape — and so does *every* AoC
puzzler's Day 19 input, because the puzzle generator is the same.

Annotating it with comments (here `r0..r5` for registers and treating
the IP-bound register `r4` as just "ip"):

```
ip=0   addi 4 16 4    # ip += 16  (post-step: ip = 17, jump to setup)
ip=1   seti 1 3 5     # r5 = 1            <-- MAIN LOOP starts here
ip=2   seti 1 1 3     # r3 = 1
ip=3   mulr 5 3 1     # r1 = r5 * r3
ip=4   eqrr 1 2 1     # r1 = (r1 == r2)
ip=5   addr 1 4 4     # if r1: skip next  (i.e. ip += r1)
ip=6   addi 4 1 4     # ip += 1           (skip the "+= r5" if test failed)
ip=7   addr 5 0 0     # r0 += r5          <-- r5 is a divisor of r2
ip=8   addi 3 1 3     # r3 += 1
ip=9   gtrr 3 2 1     # r1 = (r3 > r2)
ip=10  addr 4 1 4     # if r3 > r2: skip next
ip=11  seti 2 8 4     # ip = 2            (continue inner loop on r3)
ip=12  addi 5 1 5     # r5 += 1
ip=13  gtrr 5 2 1     # r1 = (r5 > r2)
ip=14  addr 1 4 4     # if r5 > r2: halt  (jump past ip=16)
ip=15  seti 1 3 4     # ip = 1            (continue outer loop on r5)
ip=16  mulr 4 4 4     # ip = ip * ip      (out of range -> halt)
ip=17  ...                                <-- SETUP starts here
       (10 instructions for Part 1, 18 for Part 2)
       ...
       seti 0 ... 4   # ip = 0  -> next step ip = 1: enter main loop
```

Distilling the main loop:

```
r0 = 0
for r5 in 1..r2:                          # outer loop
    for r3 in 1..r2:                      # inner loop
        if r5 * r3 == r2:
            r0 += r5
return r0
```

That is *exactly* the sum of every `r5 ≤ r2` such that `r5` divides
`r2` — i.e. `r0 = sum_of_divisors(r2)`.

The setup phase computes the target value `r2 = N`. For Part 1 (r0
starts at 0), setup ends at ip=26 with `r2 = 986`. For Part 2 (r0
starts at 1), an `addr 4 0 4` at ip=25 conditionally takes a longer
path through the setup, ending with `r2 = 10551386`. The two
divisors-sum targets are:

- **Part 1**: N = 986 = 2 × 17 × 29  ⇒  σ(N) = 3 × 18 × 30 = **1620**.
- **Part 2**: N = 10551386 = 2 × 5275693 (5275693 is prime)  ⇒
  σ(N) = 3 × 5275694 = **15827082**.

So the Part 2 trick is not algorithmic cleverness in the ALU sense
— it is recognising what the assembly *is*. Once you see σ(N), the
puzzle is two lines: simulate setup, then call `sum_of_divisors`.

---

## Data model

```haskell
type Instr = (Op, Int, Int, Int)

data Program = Program
  { ipReg  :: !Int
  , instrs :: !(Array Int Instr)
  } deriving (Eq, Show, Generic)
```

- `Op` is imported from Day 16 unchanged — the 16-constructor enum.
- `Instr` is the same `(op, a, b, c)` shape Day 16 stored as
  `[Int]`; here we keep the decoded `Op` so we don't re-lookup on
  every step.
- `Program` is the parsed input: which register is the IP, and the
  instruction list as a boxed `Array Int Instr`.

**Why a boxed `Array Int Instr`**: the IP jumps, so we need O(1)
random access. `[Instr] !! ip` would be O(ip). `IntMap` would also
work but `Array` is denser (the instructions are 0..n contiguous).
We use the *boxed* `Data.Array.Array`, not `UArray`, because `Instr`
is an algebraic data type — there is no way to pack `(Op, Int, Int, Int)`
into a flat byte buffer. The program is 35 instructions; the boxed
overhead is negligible.

**Strict fields**: `!Int` and `!Array Int Instr` on the record
ensure that once a `Program` is forced, the IP register and the
spine of the instruction array are too. (Day 11 hit the same wall
with `UArray` not having `NFData`; here we walk the elements
manually in `rnf`, see the source.)

**`Regs` is imported from Day 16**: a `UArray Int Int` indexed
`(0, 5)` (six registers this time, vs Day 16's four). The
`applyOp` ALU works on whatever bounds you hand it; only Day 19's
`initRegs` decides the size.

---

## `parseInput`

```haskell
parseInput :: String -> Program
parseInput raw =
  case filter (not . null) (lines raw) of
    (h : rest) | take 3 h == "#ip" ->
      let ipR = read (drop 4 h)
          is  = map parseInstr rest
          arr = A.listArray (0, length is - 1) is
      in  Program ipR arr
    _ -> error "Day19.parseInput: missing #ip directive"
```

- `filter (not . null) (lines raw)` — split into lines, drop blank
  ones. Same shape as Day 16's pre-processing.
- `take 3 h == "#ip"` — first non-blank line must start with `#ip`.
  Then `drop 4 h` skips `"#ip "` and `read` parses the register
  number.
- Each remaining line goes through `parseInstr`.
- `A.listArray :: (Ix i) => (i, i) -> [e] -> Array i e` — same
  builder as `UArray`, but boxed. The instructions land at indices
  `0..length is - 1`, indexable by IP.

```haskell
parseInstr :: String -> Instr
parseInstr line = case words line of
  [op, a, b, c] -> (parseOp op, read a, read b, read c)
  _             -> error ("Day19.parseInstr: " ++ line)
```

- `words :: String -> [String]` — splits on whitespace.
- The four-element pattern is a sanity check; anything else explodes
  loudly (acceptable for trusted AoC input).

```haskell
parseOp :: String -> Op
parseOp s = case s of
  "addr" -> Addr ; "addi" -> Addi
  -- ... 14 more ...
  _      -> error ("Day19.parseOp: unknown mnemonic " ++ show s)
```

A flat case over the sixteen mnemonics. Day 16 never needed this
because its inputs were numeric codes — the deduction puzzle was
the whole point. Here the names are given, so we just look them up.

---

## `runProgram` -- the simulator

```haskell
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
```

The four steps from the puzzle, one per line:

1. `regs U.// [(ipR, ip)]` — write the current IP into the bound
   register. `(U.//) :: UArray i e -> [(i, e)] -> UArray i e` is the
   bulk-update operator from Day 16 (and Day 11/14 before it).
2. `applyOp op a b c ...` — run the ALU. *This is the entire Day 16
   interpreter, reused unchanged.* The whole new contribution of
   Day 19 is the wrapper around it.
3. `regs' U.! ipR` — read the bound register back out. `(U.!) :: UArray i e -> i -> e`
   is O(1) array index.
4. `+ 1` — increment.

`go !ip !regs` uses **bang patterns** (introduced Day 17) to keep
the tail recursion strict: both arguments are forced before the
recursive call, so the function runs in constant heap with no
thunk tower. On the Part 1 simulation, `go` is called about 1.6
million times — a thunk per call would be catastrophic.

`A.inRange :: Ix i => (i, i) -> i -> Bool` — is this index within
the array's bounds? When false, the IP is off the end of the
program; the puzzle says that halts execution.

**Re-using Day 16's ALU is not just stylistic** — it's the whole
point. `applyOp` is a 16-case pure function with no notion of
control flow. Day 19 hands it a register file (now 6-wide instead
of 4-wide; same `UArray Int Int` type, different bounds) and wires
it into a loop. That separation is what lets the same ALU appear
again in Day 21.

---

## `firstSetupIp` and `runUntilSetupComplete`

The Part 2 trick lives here. We need to simulate *only* the setup
phase, then stop and harvest N out of the registers.

```haskell
firstSetupIp :: Program -> Int
firstSetupIp (Program _ is) = case is A.! 0 of
  (Addi, _, k, _) -> k + 1
  i               -> error ("Day19.firstSetupIp: expected 'addi' at ip=0, "
                            ++ "got: " ++ show i)
```

Every Day 19 input begins with `addi <ipR> K <ipR>`, which means
"add K to the IP-bound register". Combined with the post-step `+1`,
the next instruction is at IP `K + 1`. So the main loop occupies
IPs `1..K` and the setup begins at `K + 1`. We derive that boundary
from the input itself rather than hardcoding 17 — defensive, and a
nice example of metadata living in the program.

The pattern match `(Addi, _, k, _)` is on a **4-tuple** whose first
component is the `Op` constructor `Addi`. Tag enums in Haskell are
matched by name; the underscores ignore the operands we don't need.

```haskell
runUntilSetupComplete :: Program -> Regs -> Regs
runUntilSetupComplete prog@(Program ipR is) regs0 = go 0 regs0 False
 where
  bnds        = A.bounds is
  setupStart  = firstSetupIp prog
  go !ip !regs !visited
    | not (A.inRange bnds ip)         = regs     -- safety net
    | ip < setupStart && visited      = regs     -- back in main loop
    | otherwise =
        let (op, a, b, c) = is A.! ip
            regs'         = applyOp op a b c (regs U.// [(ipR, ip)])
            ip'           = (regs' U.! ipR) + 1
        in  go ip' regs' (visited || ip >= setupStart)
```

Same simulator as `runProgram`, with one extra termination
condition: stop the moment the IP drops back into the main-loop
region (`ip < setupStart`) *after* having visited the setup
(`visited`). At that exact step, the registers hold the final
values setup produced — in particular, the divisor-sum target N.

The boolean `visited` is one bit of state threaded through the
recursion, exactly the way you'd thread it through a Rust closure
or a `for` loop with a `visited = true` toggle.

**Why "max of the registers" gives N**: after setup, the IP-bound
register is small (it equals the current IP), the inner-loop
counters haven't started yet (so r3, r5, r1 are 0 or 1), and r0 is
the seed (0 or 1). The only register holding anything large is the
one the setup populated with N. We pick it out with
`maximum (elems regs)` — no need to know *which* register the
particular input chose to use.

---

## `sumOfDivisors`

```haskell
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
    | d * d == n = 0
    | otherwise  = n `div` d
  isqrt :: Int -> Int
  isqrt = floor . (sqrt :: Double -> Double) . fromIntegral
```

This is σ(N), the divisor-sum function from elementary number
theory. The list comprehension reads:

> for every `d` from 1 to ⌊√n⌋, if `d` divides `n`, take both `d`
> and `n / d` — except when they're equal (perfect square), in
> which case take `d` once.

The pairing is what makes it O(√n). For N = 10,551,386 that's
about 3,250 iterations instead of 10,551,386 — and instead of the
brute simulator's ~10^14.

- `[1 .. isqrt n]` is a lazy list; `sum` walks it once.
- `n \`mod\` d == 0` is the divisibility test.
- `isqrt` casts through `Double` for `sqrt`. For N up to ~2^52 the
  cast is safe (doubles have 53 bits of mantissa); puzzle inputs
  are well within that.

**A subtle point on perfect squares**: if you wrote
`d + n \`div\` d` unconditionally, perfect squares would
double-count their square root (e.g. for 36, when d=6, both d and
n/d are 6). The `complement` helper short-circuits that case.

**Quick sanity check**: σ(28) = 1 + 2 + 4 + 7 + 14 + 28 = 56.
σ(986) = (1+2)(1+17)(1+29) = 3·18·30 = 1620, matching Part 1's
answer. The test file pins both.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Program -> Int
part1 prog = runProgram prog (initRegs 0) U.! 0
```

Just run the simulator to halt and read register 0. About 1.6
million calls to `go`, ~200 ms wall time.

```haskell
part2 :: Program -> Int
part2 prog =
  let regs = runUntilSetupComplete prog (initRegs 1)
      n    = maximum (U.elems regs)
  in  sumOfDivisors n
```

Two lines and a `let`:

1. Step the simulator only through setup (~18 instructions for the
   Part 2 path through the setup).
2. Grab N out of the registers (the largest value).
3. Return σ(N).

```haskell
solve :: String -> IO ()
solve contents = do
  let prog = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 prog))
  putStrLn ("  part 2: " ++ show (part2 prog))
```

Standard shape. Both parts share the parsed `prog` via the `let`.

---

## Why Part 1 is 30,000× slower than Part 2

| Bench       | Time     | Inner-loop iterations |
|-------------|---------:|----------------------:|
| Parse       | 56.7 µs  | (parser, 35 lines)    |
| Part 1      | 194.0 ms | ~1,600,000            |
| Part 2      | 5.7 µs   | ~3,250 (σ(N))         |

Part 1 walks the brute-force inner loop to completion — N ≈ 986,
inner-loop hits ≈ 986·986 = ~973,000, total step calls ≈ 1.6 M
when you include the skip-instructions and outer-loop bookkeeping.

Part 2's seed of `1` makes N about 10,700× larger (because the
setup conditionally tacks on `27 · 28 · 29 · 30 · 14 · 32` ≈
1.05·10^7 to r2), so the *brute-force* version of Part 2 would be
roughly 10,700² ≈ 10^8 times slower than Part 1. Call it 6 million
hours, and you see why the puzzle is daring you to read the code.

By doing the algebra by hand and shelling out to `sumOfDivisors`,
we collapse the ~10^14 simulator steps to ~3,250 trial divisions.

We *could* apply the same trick to Part 1 (run setup, harvest N,
call `sumOfDivisors`) and shave it from 194 ms to a few
microseconds. Leaving the brute simulator in Part 1 is deliberate:
it documents that the simulator is *correct*, and makes the Part
2 leap legible. The function-guide reader can see the 30,000×
gap right in the bench table.

### Possible optimization

If you wanted Part 1 fast too, replace it with:

```haskell
part1Fast :: Program -> Int
part1Fast prog =
  let regs = runUntilSetupComplete prog (initRegs 0)
      n    = maximum (U.elems regs)
  in  sumOfDivisors n
```

(unverified — pseudo-Haskell; the exact same logic as `part2`,
with a different seed.) That would drop the day's total runtime
from ~194 ms to ~10 µs. Filed as a function-guide sidebar rather
than swapped in.

---

## Key patterns

- **When the simulator runs for N² iterations and N is millions,
  the puzzle isn't asking you to simulate.** AoC 2018 has only two
  puzzles in this league — Day 19 Part 2 and Day 21 Part 2 — and
  they share a signature: a tiny assembly program, an inscrutably
  long runtime, an obvious "read me!" invitation.
- **The IP-binding mechanism is one line of code.** A "real CPU"
  emerges from "the IP lives in a register; write it in, run the
  step, read it back, +1". This is one of those moments where a
  software construction matches an electrical-engineering one
  bit-for-bit; the `r4` of this puzzle is the PC of any chip.
- **σ(N) (sum-of-divisors) is O(√n).** Pair each d ≤ √n with n/d;
  handle the perfect-square boundary. Worth memorising — it's the
  shape of half a dozen AoC "secret number theory" puzzles.
- **Derive structural constants from the program itself.** The
  setup/loop boundary is `K + 1` where K is the immediate on the
  first instruction — no need to hardcode 17. Self-describing
  programs are easier to trust.

---

## If I were writing this in Rust

The Day 16 `apply_op` (16-arm `match`) would be reused verbatim;
that's the lesson Day 16 already taught, restated. The wrapper:

```rust
fn run(ip_reg: usize, prog: &[Instr], regs: &mut [i64; 6]) {
    let mut ip = 0i64;
    while (0..prog.len() as i64).contains(&ip) {
        let (op, a, b, c) = prog[ip as usize];
        regs[ip_reg] = ip;
        apply_op(op, a, b, c, regs);
        ip = regs[ip_reg] + 1;
    }
}
```

`prog: &[Instr]` is the borrowed-slice version of the boxed
`Array`; both give O(1) indexing without aliasing the registers.
The Part 2 closed form is identical:

```rust
fn sum_of_divisors(n: i64) -> i64 {
    let mut total = 0;
    let s = (n as f64).sqrt() as i64;
    for d in 1..=s {
        if n % d == 0 {
            total += d;
            if d * d != n { total += n / d; }
        }
    }
    total
}
```

The thing Rust *would* enforce that Haskell merely encourages: the
ALU's exclusive mutable borrow of `regs` makes it structurally
impossible to read a stale IP from the bound register mid-step.
In Haskell we get the same guarantee by recreating `regs` with
`U.//` (a fresh array per step), then explicitly reading the IP
back from the *new* one (`regs' U.! ipR`). Same discipline, opposite
mechanism: Rust forbids aliasing, Haskell avoids mutation entirely.

---

**Navigation**: [← Day 18](day18_function_guide.md) | [All Days](summary_2018.md) | [Day 20 →](day20.md)
