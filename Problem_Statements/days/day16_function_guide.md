# Day 16: Chronal Classification -- Function Guide

**Problem**: A 4-register CPU has 16 opcodes whose *behaviours* are
known but whose *numbers* are not. The input is a list of samples
(register state before, a raw `[code a b c]` instruction, state
after) and a test program. Part 1: how many samples are consistent
with ≥3 of the operations? Part 2: deduce code→operation from the
samples, run the program, report register 0.

**Answers**: Part 1 = **640**, Part 2 = **472**
**Code**: [Day16.hs](../../src/Day16.hs) · **Python reference**: [day16.py](../../python/day16.py)
**Runtime**: Parse 8.61 ms · Part 1 647 µs · Part 2 802 µs · Total ≈ 10.06 ms

**New concepts this day**:

- **An instruction set as one pure function.** `Op` is an enum of the
  16 operations; `applyOp` is the entire ALU — the `switch` a
  bytecode VM has in its run loop, written as a total function.
- **Constraint propagation + singleton elimination.** Each sample
  narrows its opcode number's candidate set; intersect across
  samples, then repeatedly fix any singleton and strike it everywhere.
  This is the Sudoku "naked single" rule and the greedy resolution of
  a bipartite perfect matching.
- **`deriving (Enum, Bounded)` to get `allOps` for free.** The list
  of every operation is `[minBound .. maxBound]`, so it can never
  drift out of sync with the `Op` definition.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Data model](#data-model)
- [`applyOp` -- the whole instruction set](#applyop----the-whole-instruction-set)
- [`matchingOps` -- what a sample is consistent with](#matchingops----what-a-sample-is-consistent-with)
- [`parseInput` -- two sections, one pass](#parseinput----two-sections-one-pass)
- [Part 1](#part-1)
- [`deduceCodes` -- constraint propagation](#deducecodes----constraint-propagation)
- [Part 2](#part-2)
- [Tests](#tests)
- [Benchmarks](#benchmarks)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

The device has four registers (`0..3`) and 16 opcodes. Every
instruction is four numbers: `opcode A B C`. The opcode decides the
operation; `A` and `B` are operands; `C` is always the destination
register. Operations come in `r`/`i` pairs by operand mode —
`addr` adds *register* A and *register* B; `addi` adds *register* A
and the *immediate* B. There are 16 in all: add, mul, bitwise and/or
(each in `r` and `i` forms), set (`setr`/`seti`), and greater-than /
equality tests (`gt__`, `eq__`).

We do **not** know which number is which operation. We do have
samples: a `Before` register file, a raw instruction, and the `After`
it produced. A sample "behaves like" an operation if running that
operation on `Before` reproduces `After`.

- **Part 1**: count samples that behave like **three or more**
  operations (opcode numbers ignored entirely).
- **Part 2**: each sample's *number* must be one of the operations it
  behaves like. Cross-reference all samples to pin every number to one
  operation, then execute the test program from zeroed registers and
  read register 0.

This is the first of the year's "build a tiny VM" puzzles — Days 16,
19 and 21 are the trilogy, and Day 19 Part 2 is the calendar's
marquee reverse-engineering puzzle. Day 16 builds the ALU those days
reuse.

---

## The algorithm in Python

The shipping solution is [Day16.hs](../../src/Day16.hs); the
type-free reference is [python/day16.py](../../python/day16.py):

```
$ python python/day16.py
  part 1: 640
  part 2: 472
```

The ALU is a dispatch table — the same shape as a `clox` VM's
`run()` switch:

```python
OPS = {
    "addr": lambda g, a, b, c: _w(g, c, g[a] + g[b]),
    "addi": lambda g, a, b, c: _w(g, c, g[a] + b),
    ...
    "eqrr": lambda g, a, b, c: _w(g, c, 1 if g[a] == g[b] else 0),
}
```

and the deduction is constraint intersection then singleton
elimination:

```python
for be, ins, af in samples:
    code = ins[0]
    cand[code] = cand.get(code, set(OPS)) & matching(be, ins, af)

while cand:
    code, ops = next((k, v) for k, v in cand.items() if len(v) == 1)
    op = next(iter(ops)); solved[code] = op; del cand[code]
    for k in cand: cand[k].discard(op)
```

The Haskell is a near-transliteration; the differences are types,
strict folds, and `Data.Set`/`Data.IntMap` for the candidate maps.

---

## Data model

```haskell
type Regs = UArray Int Int          -- registers 0..3

data Op
  = Addr | Addi | Mulr | Muli
  | Banr | Bani | Borr | Bori
  | Setr | Seti
  | Gtir | Gtri | Gtrr
  | Eqir | Eqri | Eqrr
  deriving (Eq, Ord, Show, Enum, Bounded)

allOps :: [Op]
allOps = [minBound .. maxBound]

data Sample = Sample
  { sBefore :: ![Int], sInstr :: ![Int], sAfter :: ![Int] }
  deriving (Eq, Show, Generic)

data Puzzle = Puzzle
  { samples :: ![Sample], program :: ![[Int]] }
  deriving (Eq, Show, Generic)
```

**`Regs` is a `UArray Int Int`** — a fixed 4-cell unboxed array, the
same primitive Days 9/11/14 used as a tape, here used as CPU state.
Index = register number; the only mutation is "write one cell", which
`(//)` expresses directly.

**`Op` derives `Enum` and `Bounded`.** That is the load-bearing
deriving clause: `allOps = [minBound .. maxBound]` is *every* operation
in declaration order, generated by the compiler. Add a 17th opcode and
`allOps` updates itself — there is no hand-maintained list to forget.
It also derives `Ord` so `Op` can be a `Data.Set` element in Part 2.
This is the same enum-style sum type as Day 13's `Dir` / Day 15's
`Kind`, now with `Enum`/`Bounded` pulling extra weight.

**`deriving Generic` + `instance NFData`** — the same zero-boilerplate
`NFData` route Day 14 used, so the benchmark can force the parsed
`Puzzle` to normal form. (`UArray` has no `NFData`, but `Regs` never
appears *inside* `Puzzle` — only `[Int]` lists do — so the derived
instance is fine here, unlike Days 13/15 which needed a manual one.)

---

## `applyOp` -- the whole instruction set

```haskell
applyOp :: Op -> Int -> Int -> Int -> Regs -> Regs
applyOp op a b c regs = regs // [(c, result)]
  where
    r i    = regs ! i               -- register-mode read
    bool t = if t then 1 else 0     -- comparisons store 0/1
    result = case op of
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
```

This single function *is* the CPU. New vocabulary:

- **`(!) :: UArray i e -> i -> e`** — array indexing. `regs ! i` reads
  register `i`. (Seen Day 13/15 on grids; here the index is a register
  number.)
- **`(//) :: UArray i e -> [(i, e)] -> UArray i e`** — bulk update:
  return a new array with the listed cells replaced. `regs // [(c,
  result)]` is "registers, but cell `c` is now `result`". Because `C`
  is *always* a register write, every opcode shares this one update —
  only `result` differs, which is why the `case` computes just the
  value.
- **`(.&.)`, `(.|.)`** from `Data.Bits` — bitwise AND / OR on `Int`.
  First use of `Data.Bits` this year; they are the exact analogues of
  C's `&` and `|`.
- The `r`/`i` suffix decoded: the local `r` applies register-mode;
  writing the operand bare (`b`, `a`) is immediate mode. Lining the 16
  cases up vertically makes the `r b` vs `b` column the entire
  difference between, say, `Addr` and `Addi` — the spec's "many
  opcodes are similar except how they interpret arguments" made
  literal.

`where` introduces `r` and `bool` as local helpers shared by all
branches — cleaner than repeating `regs ! ` and the `if` sixteen
times.

---

## `matchingOps` -- what a sample is consistent with

```haskell
matchingOps :: Sample -> [Op]
matchingOps (Sample before [_, a, b, c] after) =
  [ op
  | op <- allOps
  , elems (applyOp op a b c (toRegs before)) == after
  ]
matchingOps s = error ("Day16.matchingOps: malformed sample " ++ show s)

toRegs :: [Int] -> Regs
toRegs = listArray (0, 3)
```

For each of the 16 operations, run it on the sample's `Before` with
the sample's `a b c`, and keep the ones whose result equals `After`.

- **`elems :: UArray i e -> [e]`** — the array's values as a list, in
  index order. `applyOp` returns a `Regs`; the sample's `After` is a
  `[Int]`; `elems` bridges them so `==` is a plain list compare.
- **The pattern `[_, a, b, c]`** destructures the 4-element instruction
  directly in the function head, discarding the opcode number with `_`
  (Part 1 does not care which number it is — that is the entire point
  of a sample). The fall-through `matchingOps s = error ...` keeps the
  function total and documents the shape assumption; AoC input is
  trusted, so a malformed line is a bug, not a recoverable case.
- **`toRegs = listArray (0, 3)`** — point-free: `listArray` partially
  applied to the bounds, waiting for the 4-element list. Builds the
  register file from `Before`.

---

## `parseInput` -- two sections, one pass

```haskell
nums :: String -> [Int]
nums = map read . words
     . map (\ch -> if ch `elem` "0123456789" then ch else ' ')

parseInput :: String -> Puzzle
parseInput raw = go (filter (not . null) (lines raw)) []
  where
    go (b : i : a : rest) acc
      | take 6 b == "Before" =
          go rest (Sample (nums b) (nums i) (nums a) : acc)
    go rest acc = Puzzle (reverse acc) (map nums rest)
```

`nums` is the "numbers out of a noisy line" trick (Day 4 used it for
timestamps): rewrite every non-digit to a space, `words`, `read` each.
It turns `"Before: [3, 2, 1, 1]"` into `[3,2,1,1]` and `"9 2 1 2"`
into `[9,2,1,2]` with no bracket/comma handling.

`go` walks the blank-stripped lines with an accumulator:

- If the next three lines exist **and** the first starts with
  `"Before"`, that is one sample — consume the triple, prepend it,
  recurse. The guard `take 6 b == "Before"` is the section boundary
  detector: samples all start with `Before`, program lines do not.
- Otherwise the samples are exhausted; everything left is the test
  program. `reverse acc` restores source order (we prepended for O(1)
  cons, same idiom as Day 13's crash list).

One pass, no separate "find the blank-line gap" step — the structure
itself (`Before` prefix) marks where samples end.

---

## Part 1

```haskell
part1 :: Puzzle -> Int
part1 (Puzzle ss _) =
  length [ () | s <- ss, length (matchingOps s) >= 3 ]
```

Count samples that behave like ≥3 operations. The `[ () | ... ]`
comprehension yields one unit per qualifying sample and `length`
counts them — the idiomatic Haskell "count things matching a
predicate" when you do not need the elements, only the tally. The
test program is ignored (`_`).

---

## `deduceCodes` -- constraint propagation

```haskell
deduceCodes :: [Sample] -> IntMap Op
deduceCodes ss = solve' candidates0 IM.empty
  where
    candidates0 :: IntMap (Set Op)
    candidates0 =
      foldl'
        (\m s ->
           let code = head (sInstr s)
               ops  = Set.fromList (matchingOps s)
           in  IM.insertWith Set.intersection code ops m)
        IM.empty ss

    solve' cand solved
      | IM.null cand = solved
      | otherwise =
          case [ (code, Set.findMin os)
               | (code, os) <- IM.toList cand
               , Set.size os == 1 ] of
            [] -> error "Day16.deduceCodes: no singleton; \
                        \input underdetermined"
            ((code, op) : _) ->
              let cand'   = IM.map (Set.delete op) (IM.delete code cand)
                  solved' = IM.insert code op solved
              in  solve' cand' solved'
```

Two phases.

**Phase 1 — intersection.** `candidates0` maps each opcode *number* to
the set of operations still possible for it. Every sample with code
`k` asserts "the op behind `k` is one of `matchingOps s`". The
constraint across many samples is the **intersection** of those sets —
expressed by `IM.insertWith Set.intersection`: insert the set if the
key is new, otherwise combine the old and new sets with
`Set.intersection`. `foldl'` keeps the accumulating `IntMap` strict.

- **`IM.insertWith :: (v -> v -> v) -> k -> v -> IntMap v -> IntMap v`**
  — like `Map.insertWith` (Day 2/3), but `IntMap` for integer keys.
  The combining function receives `(new, old)`; `Set.intersection` is
  commutative so the order does not matter here.

**Phase 2 — singleton elimination.** While any code's set is a
singleton `{op}`: that code *must* be `op`. Record it, delete the code
from the working map, and `Set.delete op` from every remaining set
(`IM.map (Set.delete op) ...`). Removing the now-known op shrinks other
sets, creating new singletons; recurse to a fixed point.

- **`Set.findMin`** — the sole element of a singleton set (cheapest
  way to extract "the one element").
- The `error` on "no singleton" documents the precondition: a
  well-formed AoC input always collapses uniquely. This is exactly the
  Sudoku **naked single** technique, and equivalently the greedy
  resolution of a **bipartite perfect matching** (codes on one side,
  ops on the other) when the puzzle guarantees one exists — naming the
  technique is what makes it transfer to later constraint puzzles.

---

## Part 2

```haskell
runProgram :: IntMap Op -> [[Int]] -> Regs
runProgram codeOf = foldl' step (listArray (0, 3) [0, 0, 0, 0])
  where
    step regs [code, a, b, c] = applyOp (codeOf IM.! code) a b c regs
    step _ instr = error ("Day16.runProgram: malformed instr " ++ show instr)

part2 :: Puzzle -> Int
part2 (Puzzle ss prog) = runProgram (deduceCodes ss) prog ! 0
```

With the table resolved, the program is a left fold over the
instruction list: thread the register file through `applyOp`, starting
from all-zeros. `codeOf IM.! code` looks up the operation for the raw
number, then it is the same `applyOp` Part 1 used. `! 0` reads
register 0 from the final state. The ALU is written once and serves
both the sample analysis and the program execution — the parse-once,
reuse-the-machinery discipline, now for code rather than data.

---

## Tests

[test/Day16Spec.hs](../../test/Day16Spec.hs) pins four cases:

```haskell
it "the puzzle sample behaves like exactly mulr, addi, seti" $
  sort (matchingOps sample) `shouldBe` sort [Mulr, Addi, Seti]
```

The narrated sample `Before [3,2,1,1] / 9 2 1 2 / After [3,2,2,1]`
behaves like exactly those three (the text walks through why), which
exercises `applyOp` across register/immediate/set modes in one
assertion. A structural `parseInput` check (samples and program both
non-empty, every instruction 4-wide) guards the section split, and the
two real-input answers are pinned via `actualPart1`/`actualPart2`.
`sort` on both sides makes the set comparison order-independent.

---

## Benchmarks

| Bench | Mean |
|-------|------|
| `parseInput` | 8.61 ms |
| `part1` | 647 µs |
| `part2` | 802 µs |
| **Total (Parse+P1+P2)** | **≈ 10.06 ms** |

The parser is ~85 % of the runtime — the same story as Day 8.
`nums` runs `read` over the digit-runs of ~3200 sample lines plus the
program, and `read :: String -> Int` over thousands of tiny strings
dominates. Both parts operate on the already-parsed structure and are
sub-millisecond: Part 1 is 16 `applyOp`s × ~800 samples; Part 2 adds
the deduction (16 set intersections + 16 elimination rounds, all on
≤16-element sets) and a fold over the short program. If the parser
ever mattered, `Data.ByteString.Char8`'s `readInt` would gut the
`read` cost — noted, not needed at 10 ms.

---

## Key patterns

1. **One function is the whole VM.** An opcode enum plus a single
   `Op -> operands -> State -> State` transition is all an
   instruction set is. The same `applyOp` serves Part 1's "could this
   be op X?" and Part 2's "execute". Days 19 and 21 extend exactly
   this skeleton with an instruction pointer.

2. **Constraints as set intersection, then naked singles.** When each
   observation narrows a set of possibilities and a unique solution is
   guaranteed, intersect per key, then iterate "assign a singleton,
   eliminate it everywhere". It cracks code→op here, Sudoku
   elsewhere, and any "guaranteed-unique bipartite matching".

3. **`deriving (Enum, Bounded)` for the universe of a type.**
   `[minBound .. maxBound]` is every constructor, compiler-maintained.
   Reach for it whenever you need "all values of this enum" and want
   it to never go stale.

---

## If I were writing this in Rust

The structure maps almost one-to-one; the differences are dispatch
style and the candidate-set plumbing.

- `Op` enum + `applyOp`'s `case` → a Rust `enum Op` and a `match op {
  Op::Addr => ... }` in `fn apply(op, a, b, c, regs) -> [i64; 4]`.
  Identical shape; Rust's exhaustive `match` gives the same
  "forgot a case = compile error" guarantee Haskell's `case` does.
- `allOps = [minBound..maxBound]` → Rust has no built-in enum
  iteration; you would hand-write `const ALL: [Op; 16] = [..]` or pull
  in `strum`. This is one place Haskell's `deriving (Enum, Bounded)`
  is strictly less boilerplate.
- `IntMap (Set Op)` → `HashMap<usize, HashSet<Op>>` (or a
  `[u16; 16]` bitmask per code — 16 ops fit in a `u16`, and "intersect"
  becomes `&=`, "eliminate" becomes `&= !bit`; that bitmask version is
  the fast idiomatic Rust and is also a fine optional optimisation
  here).
- `foldl' step zero prog` → `prog.iter().fold([0i64;4], |r, ins|
  apply(codeof[ins[0]], ins[1], ins[2], ins[3], r))`, or a plain
  `for` loop mutating `regs` in place. Haskell threads a fresh array
  via `(//)`; Rust mutates one. Same computation, different default.

The honest takeaway: this is a language-neutral puzzle. The only real
Haskell win is `deriving (Enum, Bounded)` for `allOps`; the only
real Rust win is the `u16` bitmask for candidate sets — and that is
available in Haskell too (`Data.Bits` on an `Int`) if 10 ms ever
needs to be 1 ms.

---

**Navigation**: [← Day 15](day15_function_guide.md) | [All Days](summary_2018.md) | [Day 17 →](day17_function_guide.md)
