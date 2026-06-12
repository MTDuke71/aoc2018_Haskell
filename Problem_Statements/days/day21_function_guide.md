# Day 21: Chronal Conversion -- Function Guide

**Problem**: The Day 16/19 device runs an *activation system* that
never halts on its own. The only exit is one `eqrr` instruction that
compares a register against register 0 — and register 0 is never
touched anywhere else in the program. Part 1: the value of r0 that
makes the program halt after the *fewest* instructions. Part 2: the
value that halts it after the *most* instructions (while still
halting at all).

**Answers**: Part 1 = **12213578**, Part 2 = **5310683**
**Code**: [Day21.hs](../../src/Day21.hs) · **Python reference**: [day21.py](../../python/day21.py)
**Runtime**: Parse 52.1 µs · Part 1 44.0 µs · Part 2 2.30 ms · Total ≈ 2.40 ms

**New concepts this day**:

- **The breakpoint pattern.** Part 1 doesn't reverse-engineer
  anything: it runs the real VM and stops the moment the IP lands
  on the one instruction that consults r0, then reads the other
  operand. A debugger move, not a compiler move.
- **Extracting constants from code instead of hard-coding them.**
  `hashSpec` pattern-matches a six-instruction template out of the
  program text, so the lifted hash works on *any* AoC input —
  Day 19's `firstSetupIp` trick, pushed further.
- **Eventually-periodic sequences and the pigeonhole argument.**
  Each probe value is a pure function of the previous one over a
  finite domain (24 bits), so the stream *must* enter a cycle; once
  any value repeats, nothing new can ever appear. That argument is
  what makes "the last new value" a well-defined answer.
- **`Data.IntSet`** — `Data.Set` specialised to `Int` keys (a
  PATRICIA trie rather than a balanced tree); same API, leaner and
  faster when the elements are machine integers.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Reading the assembly: a hash with a breakpoint](#reading-the-assembly-a-hash-with-a-breakpoint)
- [Data model](#data-model)
- [`checkInfo` and `runToFirstCheck` (Part 1)](#checkinfo-and-runtofirstcheck-part-1)
- [`hashSpec` -- constants out of the program text](#hashspec----constants-out-of-the-program-text)
- [`nextProbe` and `probes`](#nextprobe-and-probes)
- [`part2` -- last new value before the cycle](#part2----last-new-value-before-the-cycle)
- [Why not just simulate Part 2?](#why-not-just-simulate-part-2)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

Same device, same ALU, same `#ip` binding as Day 19 — the input even
parses with Day 19's parser unchanged. The difference is the
contract: this program **runs forever**. Our only lever is the
initial value of register 0, and the program only ever *reads* r0 in
exactly one place:

```
ip=28   eqrr 4 0 1     # r1 = (r4 == r0)
ip=29   addr 1 2 2     # if equal: ip = 31 -> off the end -> HALT
ip=30   seti 5 2 2     # else: loop back and compute the next r4
```

So the program generates a fixed, deterministic stream of r4 values
— call them **probes** — and halts the first time a probe equals r0.
Pick r0 = the first probe, and it halts as soon as possible
(Part 1). Pick r0 = the last probe that is *new* before the stream
starts repeating, and it halts as late as possible (Part 2) — any
value that hasn't appeared by the time the stream closes its cycle
will never appear, so choosing it would mean never halting.

The two answers are two reads of the same stream. Everything else is
about producing that stream fast enough.

---

## The algorithm in Python

The shipping solution is [Day21.hs](../../src/Day21.hs); the
algorithm reads cleaner without the array plumbing, so the
side-by-side is [python/day21.py](../../python/day21.py). What the
program between two checks actually computes is a byte-at-a-time
hash:

```python
def next_probe(spec, prev):
    """One full round: previous check value -> next check value."""
    seed, mult, hash_mask, byte_mask, widen = spec
    v = prev | widen                 # widen = 0x10000: force >= 3 bytes
    acc = seed
    while True:
        acc = (((acc + (v & byte_mask)) & hash_mask) * mult) & hash_mask
        if v <= byte_mask:
            return acc
        v //= byte_mask + 1          # v >>= 8, one byte consumed

def part2(program):
    spec = hash_spec(program)        # constants from the program text
    seen, prev = set(), 0
    probe = next_probe(spec, 0)
    while probe not in seen:
        seen.add(probe)
        prev = probe
        probe = next_probe(spec, probe)
    return prev                      # last NEW value before a repeat
```

If you've met [FNV](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function)
this shape is an old friend: *fold in a byte, multiply by a prime*,
here with `& 0xFFFFFF` keeping the accumulator to 24 bits (FNV-1a
does xor-then-multiply at 32/64 bits; this is add-then-multiply at
24 — same family). The `| 0x10000` widening guarantees every round
feeds at least three bytes, so even tiny previous probes get
scrambled.

The Python file also solves Part 1 with the **full VM** rather than
the lifted hash, and `main` asserts the two agree on round 1 — the
reference implementation cross-checks the optimised one.

---

## Reading the assembly: a hash with a breakpoint

> **Deep-dive companion**: [day21_disassembly.md](day21_disassembly.md)
> puts this program under instrumentation — the jump-idiom
> vocabulary, a step-by-step trace, a per-IP execution profile
> (98.3% of the first round is the trial-divide loop), the
> ρ-shaped probe stream (11,646-probe tail + 1,222-probe cycle),
> and the exact fewest/most instruction counts the puzzle text
> asks about (1,848 vs 2,976,386,661). Generated by
> [scripts/day21_disassemble.hs](../../scripts/day21_disassemble.hs).

Our input, register 2 bound to the IP (so `r2` *is* the program
counter), annotated in full:

```
        --- the elves' scripting-language paranoia check ---
ip=0    seti 123 0 4        # r4 = 123
ip=1    bani 4 456 4        # r4 = 123 & 456     (= 72 if & is numeric)
ip=2    eqri 4 72 4         # r4 = (r4 == 72)
ip=3    addr 4 2 2          # if ok: skip next
ip=4    seti 0 0 2          # else: goto 1 forever (bani is "stringy")

        --- outer loop: one round = one probe ---
ip=5    seti 0 5 4          # r4 = 0              (first "previous probe")
ip=6    bori 4 65536 5      # r5 = r4 | 0x10000   <- WIDEN     <- round start
ip=7    seti 1765573 9 4    # r4 = 1765573        <- SEED

        --- inner loop: fold one byte of r5 into the hash ---
ip=8    bani 5 255 1        # r1 = r5 & 0xFF      <- BYTE_MASK
ip=9    addr 4 1 4          # r4 += r1
ip=10   bani 4 16777215 4   # r4 &= 0xFFFFFF      <- HASH_MASK
ip=11   muli 4 65899 4      # r4 *= 65899         <- MULT
ip=12   bani 4 16777215 4   # r4 &= 0xFFFFFF
ip=13   gtir 256 5 1        # r1 = (256 > r5)     -- was that the last byte?
ip=14   addr 1 2 2          # if yes: goto 16
ip=15   addi 2 1 2          # else:   goto 17
ip=16   seti 27 0 2         # goto 28 (the check)

        --- r5 //= 256, the hard way (no shift instruction!) ---
ip=17   seti 0 8 1          # r1 = 0
ip=18   addi 1 1 3          # r3 = r1 + 1         <- trial loop: find the
ip=19   muli 3 256 3        # r3 *= 256              largest r1 with
ip=20   gtrr 3 5 3          # r3 = (r3 > r5)         r1 * 256 <= r5,
ip=21   addr 3 2 2          # if r3: goto 23         i.e. r1 = r5 div 256
ip=22   addi 2 1 2          # goto 24
ip=23   seti 25 1 2         # goto 26
ip=24   addi 1 1 1          # r1 += 1
ip=25   seti 17 7 2         # goto 18
ip=26   setr 1 4 5          # r5 = r1             -- one byte consumed
ip=27   seti 7 6 2          # goto 8

        --- the halt check: the ONLY use of r0 in the program ---
ip=28   eqrr 4 0 1          # r1 = (r4 == r0)
ip=29   addr 1 2 2          # if equal: ip = 31 -> HALT
ip=30   seti 5 2 2          # goto 6 (next round, r4 is the new "prev")
```

Three observations carry the whole day:

1. **ips 0–4 are the puzzle text's joke made real**: verify that
   `bani` does numeric AND (123 & 456 = 72), or spin forever. Our
   simulator passes in five steps and never looks back.
2. **ips 17–25 are a divide implemented as trial multiplication.**
   The ALU has add, multiply, AND, OR, set, and compare — no shift,
   no divide. So `r5 div 256` costs ~8 instructions per *candidate
   quotient*, i.e. ~8 · (r5/256) instructions per byte consumed.
   This loop is where a naive simulation of Part 2 goes to die.
3. **ip 28 is the only instruction whose behaviour depends on r0.**
   Everything upstream of it is a fixed sequence. That's the
   license for both parts: the probe stream doesn't care what r0
   is, so we can read the stream without ever "guessing" r0.

In C-flavoured pseudocode, one round is:

```c
v   = prev | 0x10000;            // 17..24 bits -> always 3 byte-feeds
acc = 1765573;
for (;;) {
    acc = ((acc + (v & 0xFF)) & 0xFFFFFF) * 65899 & 0xFFFFFF;
    if (v < 256) break;
    v >>= 8;                     // the ~2000-instruction trial loop
}
// acc is the next probe; compare against r0 at ip 28
```

---

## Data model

```haskell
import Day16 (Op (..), applyOp)
import Day19 (Program (..), parseInput)
```

No new parsing and no new types for the VM side — the input format
is byte-for-byte Day 19's (`#ip N` plus mnemonic lines), so `Day21`
re-exports `Day19.parseInput` and `Program` directly. This is the
trilogy paying off: Day 16 contributed the ALU, Day 19 the
IP-binding and the parser, Day 21 adds only *policy*.

The one new type holds the five constants the hash needs:

```haskell
data HashSpec = HashSpec
  { hashSeed :: !Int   -- accumulator start each round  (1765573)
  , hashMult :: !Int   -- the FNV-style multiplier      (65899)
  , hashMask :: !Int   -- keep-24-bits mask             (0xFFFFFF)
  , byteMask :: !Int   -- low-byte mask                 (0xFF)
  , widenBit :: !Int   -- OR'd onto the previous probe  (0x10000)
  } deriving (Eq, Show)
```

**Why strict fields**: these five `Int`s are read on every hash
step. `!Int` (a strictness annotation on the field, introduced back
on Day 3) guarantees they're evaluated machine integers, not
thunks, so the inner loop never pays a "check if evaluated" tax.

---

## `checkInfo` and `runToFirstCheck` (Part 1)

```haskell
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
```

Scan the program for the unique `eqrr` with `0` as one operand and
return `(where it lives, which register it probes)` — `(28, 4)` for
our input. Two pieces of machinery worth pausing on:

- `A.assocs :: Array i e -> [(i, e)]` — the array as a list of
  (index, element) pairs, like Rust's `.iter().enumerate()`.
- `Just reg <- [probeReg i]` inside a list comprehension is a
  **pattern-match filter**: `probeReg` returns a `Maybe`, the
  comprehension keeps only the `Just`s and unwraps them in one
  move. The same trick a `filter_map` does in Rust. Elements that
  produce `Nothing` are silently skipped, not errors.

The `[hit] -> hit` case insists on *exactly one* match — if an
input ever had two `eqrr ... 0 ...` instructions, we'd want a loud
failure, not a silent wrong pick.

```haskell
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

part1 :: Program -> Int
part1 = runToFirstCheck
```

This is Day 19's `runProgram` loop verbatim — write the IP into the
bound register, run one `applyOp` step, read it back, +1 — with the
halt condition swapped for a **breakpoint**: stop *before executing*
`ip == checkIp` and read the probed register. Since the check never
runs, r0's value is irrelevant; we start it at 0 like everything
else.

On our input the breakpoint fires after **1,846 steps** (five for
the bani self-test, then one full round: three byte-feeds and two
trial-divides). 44 µs, and Part 1 is done with zero understanding of
the hash — only of the one instruction that touches r0.

`prog@(Program ipR is)` is an **as-pattern** (`@`): bind the whole
value to `prog` *and* destructure it in the same pattern, so we can
pass `prog` on to `checkInfo` while using the fields directly.

---

## `hashSpec` -- constants out of the program text

```haskell
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
```

Every published AoC input is the same program template with
different constants — the puzzle generator only varies `SEED` (and
through it the answers). Conveniently the template's widen step is
the **only `bori` in the whole program**, so it anchors the match;
the seed, byte mask, hash mask, and multiplier then sit at fixed
offsets `+1, +2, +4, +5` from it (offset `+3` is the `addr` that
adds the byte — no constant to harvest there).

This is the same defensive posture as Day 19's `firstSetupIp`: we
*are* exploiting input structure, but we make the assumption
explicit and `error` loudly if it ever fails, rather than
hard-coding `1765573` and silently mis-answering someone else's
input. The unit test pins the extracted `HashSpec` for our input;
the structure check is the code itself.

The outer `case` pattern `[b]` matches only a single-element list —
zero or two `bori`s fall through to the error branch with the
evidence in the message.

---

## `nextProbe` and `probes`

```haskell
nextProbe :: HashSpec -> Int -> Int
nextProbe (HashSpec seed mult mask byteM widen) prev = go seed (prev .|. widen)
 where
  go !acc !v
    | v <= byteM = acc'                       -- that was the last byte
    | otherwise  = go acc' (v `div` (byteM + 1))
   where
    acc' = (((acc + (v .&. byteM)) .&. mask) * mult) .&. mask
```

The inner loop of the assembly, one line per concept:

- `.&.` and `.|.` from `Data.Bits` are bitwise AND/OR — Day 16's
  `applyOp` used them to *implement* `bani`/`bori`; here they appear
  in solution logic for the first time. (The dots distinguish them
  from the Boolean `&&`/`||`.)
- `acc'` is the entire hash step: add the low byte, mask to 24
  bits, multiply, mask again. Note the masked multiply: without the
  final `.&. mask` the accumulator would outgrow 24 bits — Haskell's
  `Int` is 64-bit so nothing would *overflow*, but we'd be computing
  a different (wrong) function than the device does.
- `v \`div\` (byteM + 1)` — what costs the VM ~2,000 instructions of
  trial multiplication is one hardware divide here. This single line
  is the whole Part 2 speedup.
- The `where` under a guard: `acc'` is shared by both guard
  branches; defining it once below them keeps the two exit paths
  visibly identical to the assembly's.

```haskell
probes :: Program -> [Int]
probes prog = tail (iterate (nextProbe (hashSpec prog)) 0)
```

`iterate f x` is the lazy infinite list `[x, f x, f (f x), ...]` —
last seen powering Day 1's frequency cycle. Here it turns the probe
generator into a *value*: an infinite stream in the exact order the
program would compare probes against r0. The `tail` drops the
leading `0`, which is the initial register state, not a probe the
program ever checks.

Laziness is what makes this honest: `probes` doesn't compute
anything until a consumer demands elements, and Part 2 will demand
exactly as many as it needs to spot the first repeat — no more.

A nice REPL check that the lifted hash and the real VM agree
(also pinned as a unit test):

```
ghci> raw <- readFile "inputs/day21.txt"
ghci> let prog = parseInput raw
ghci> head (probes prog) == runToFirstCheck prog
True
```

---

## `part2` -- last new value before the cycle

```haskell
part2 :: Program -> Int
part2 prog = go IS.empty 0 (probes prog)
 where
  go !seen !prev (p : ps)
    | p `IS.member` seen = prev
    | otherwise          = go (IS.insert p seen) p ps
  go _ !prev []          = prev   -- unreachable: 'probes' is infinite
```

Walk the stream keeping a set of everything seen; the moment a
probe repeats, the *previous* probe was the last new value — and
that's the r0 that maximises instructions executed.

**Why this is the answer (the pigeonhole argument)**: each probe is
`nextProbe spec` applied to the one before — a pure function from a
finite domain (24-bit integers) to itself. Such a sequence cannot
keep producing fresh values forever; within at most 2²⁴ steps it
must revisit a value, and from that revisit it replays
deterministically — a cycle. Every value the stream will *ever*
contain has therefore appeared by the time the first repeat shows
up. Choosing the latest-appearing one maximises the halt time;
choosing anything not in the seen-set means the program never
halts at all. On our input the stream produces **12,868 distinct
probes** before the first repeat.

Mechanics:

- `Data.IntSet` (imported `qualified ... as IS`) is `Set Int` with
  the key type baked in. Internally it's a big-endian **PATRICIA
  trie** keyed on bits rather than a balanced tree of comparisons —
  for dense machine-integer workloads like this it's both faster
  and smaller than `Data.Set Int`. The API is the same shape:
  `IS.member`, `IS.insert`, `IS.empty`.
- The bang patterns force `seen` and `prev` each step — by now
  (Days 9/14/17/19) the reflex: accumulators in a tail-recursive
  loop get bangs.
- The `go _ !prev [] = prev` clause is dead code — `probes` is
  infinite — but GHC's exhaustiveness checker can't know that, and
  `-Wall` rightly complains about a missing `[]` case. Writing the
  unreachable clause documents *why* it's unreachable in a comment
  instead of suppressing the warning.

---

## Why not just simulate Part 2?

We could run the breakpoint VM 12,869 times instead of once,
collecting probes at ip 28 until one repeats. Correct — but count
the instructions. Each round consumes three bytes of `v`, and each
of the first two byte-consumptions runs the trial-divide loop:
~8 · (v/256) instructions when v is up to 24 bits wide. Summing over
all rounds of our input's stream:

| Strategy | Hash steps | VM instructions | Time |
|----------|-----------:|----------------:|-----:|
| Simulate the VM until the answer probe | — | 2,976,386,661 | upwards of an hour (immutable-array VM) |
| Lift the hash, run it natively | ~38,600 | 0 | **2.3 ms** |

(That instruction count is exact — the puzzle literally asks for
the r0 that maximises it; the [disassembly supplement](day21_disassembly.md)
derives it from a per-round cost model cross-checked against the
VM.) It averages ~231,000 VM instructions per probe, of which all
but ~30 per round are the trial-divide loop — the device spends
**99.99% of its time dividing by 256**, because its ISA has no shift. The
lifted version replaces each of those ~2,000-instruction divides
with one `div`. Same trick as Day 19 (don't speed the simulator up;
stop simulating), but with a different escape hatch: Day 19 replaced
the loop with a *closed form* (σ(N)); Day 21's loop has no closed
form — hashes are designed not to — so we replace it with a *native
reimplementation* instead.

That's also why Part 2's 2.3 ms is dominated not by hashing but by
the `IntSet` bookkeeping and lazy-list plumbing around ~38,600 hash
steps — perfectly acceptable, and the idiomatic-Haskell version
stays in `src/`.

### Possible optimization

The probe stream never needs the list at all: a hand-fused loop
(`go seen prev = let p = nextProbe spec prev in ...`) would skip
allocating a cons cell per probe, and an unboxed
`Data.Vector.Unboxed.Mutable` bitmap of 2²⁴ bits (2 MB) inside
`runST` would replace `IntSet`'s O(min(W, log n)) member/insert
with O(1) indexing:

```haskell
-- pseudo-Haskell, unverified
part2' spec = runST $ do
  seen <- VUM.replicate (1 `shiftL` 24) False
  let go !prev = do
        let p = nextProbe spec prev
        dup <- VUM.read seen p
        if dup then pure prev
               else VUM.write seen p True >> go p
  go 0
```

Likely several× faster; at 2.3 ms total it would be optimising past
the point of caring, so it stays a sidebar.

---

## Key patterns

- **Find the one instruction that touches your input, and break on
  it.** When a program's behaviour depends on a value you control
  in exactly one place, you don't need to understand the program —
  you need the sequence of values flowing past that point. Part 1
  needed a breakpoint, not a disassembly.
- **A function from a finite set to itself is eventually periodic.**
  The ρ-shaped orbit (tail + cycle) is the same structure behind
  Day 18's forest cycle and every PRNG's period. Corollary used
  here: *the set of values ever produced is exactly the set produced
  before the first repeat* — which converts "halts after the most
  instructions" into "last new value", something a `Set` membership
  test can find.
- **Lift the hot loop, keep the constants symbolic.** The middle
  ground between "simulate everything" (too slow) and "hardcode
  the reverse-engineered answer" (only solves *your* input):
  reimplement the loop natively but extract its parameters from the
  program text, with loud errors when the template doesn't match.
- **An ISA tells you where the time goes.** No shift instruction ⇒
  dividing by 256 costs thousands of trial multiplications ⇒ 99.99%
  of execution is one loop. Reading the *instruction set* (not just
  the program) predicted the profile before any measurement — a very
  hardware-engineer way to find a bottleneck.

---

## If I were writing this in Rust

The breakpoint runner is Day 19's `run` with an early return:

```rust
fn run_to_first_check(prog: &Program) -> i64 {
    let (check_ip, check_reg) = check_info(prog);
    let mut regs = [0i64; 6];
    let mut ip = 0;
    loop {
        if ip == check_ip { return regs[check_reg]; }
        let (op, a, b, c) = prog.instrs[ip as usize];
        regs[prog.ip_reg] = ip;
        apply_op(op, a, b, c, &mut regs);
        ip = regs[prog.ip_reg] + 1;
    }
}
```

and the probe loop is a `HashSet`:

```rust
fn part2(spec: &HashSpec) -> u32 {
    let mut seen = HashSet::new();
    let (mut prev, mut p) = (0, next_probe(spec, 0));
    while seen.insert(p) {       // insert returns false on duplicate
        prev = p;
        p = next_probe(spec, p);
    }
    prev
}
```

Two notes for the translation:

- Rust's `seen.insert(p)` returning `bool` fuses the
  member-check-then-insert into one call; Haskell's persistent
  `IntSet` keeps them separate (`IS.member`, then `IS.insert`
  building a *new* set sharing structure with the old). Same
  asymptotics, different idiom — and the persistent version would
  let you keep every intermediate set for free if you wanted the
  history.
- `next_probe` in Rust would use `v >>= 8` and `& 0xFF` on a `u32`
  with wrapping semantics irrelevant (the mask keeps everything in
  24 bits). The Haskell uses `div` to mirror the assembly's trial
  loop and named `HashSpec` fields instead of magic literals; with
  `-O2` GHC compiles the `div` by a constant power of two down to a
  shift anyway.

---

**Navigation**: [← Day 20](day20_function_guide.md) | [All Days](summary_2018.md) | [Day 22 →](day22_function_guide.md)
