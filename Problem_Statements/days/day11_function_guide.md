# Day 11: Chronal Charge -- Function Guide

**Problem**: A 300×300 grid of fuel cells.  Each cell `(x, y)` has a power level in the range `[-5, 4]` computed from `(x, y)` and the puzzle's grid *serial number*.  Part 1 asks for the 3×3 square with the largest total power.  Part 2 asks for the square of *any* size 1..300 with the largest total power.
**Answers**: Part 1 = **`20,41`**, Part 2 = **`236,270,11`**
**Runtime** (mean, criterion `-O2`): Parse = **394.8 µs** | Part 1 = **1.665 ms** | Part 2 = **77.24 ms** | **Total = 79.30 ms**
**Code**: [Day11.hs](../../src/Day11.hs)
**Tests**: [Day11Spec.hs](../../test/Day11Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day11"`
**Problem statement**: [day11.md](day11.md)

**New concepts this day** (beyond Days 0--10):

- **Summed-area table (2D prefix sums)**.  Pre-compute a `(301 × 301)` array where `sat[x, y]` is the sum of power levels over the rectangle `(1..x, 1..y)`.  Then *any* axis-aligned subrectangle sum reduces to a four-term inclusion-exclusion in `O(1)`.  Drops Part 2 from `O(N⁵) ≈ 8.3 × 10¹⁰` cell additions to `O(N³) ≈ 9 × 10⁶` four-corner lookups -- a ~10,000× reduction in work at `N = 300`.
- **`runSTUArray`**.  The sugar that wraps "allocate an `STUArray`, mutate it, freeze the result" into a single combinator that hands back an immutable `UArray`.  Day 9 lived inside `ST` and returned a scalar; here we want the *frozen array itself* as the long-lived query target.
- **2D unboxed array (`UArray (Int, Int) Int`)**.  First day where the index is a tuple.  `Data.Ix` handles the row-major linearisation; we just spell the bounds as `((0, 0), (300, 300))` and index with `(!)`.
- **`newtype` to hang `NFData` off a type that hasn't got one**.  The `array` and `deepseq` packages do *not* ship an `NFData (UArray i e)` instance for our pinned versions.  Rather than declare an orphan, we wrap the table in `newtype Puzzle = Puzzle (UArray (Int, Int) Int)` and define `instance NFData Puzzle` ourselves.  Since `UArray` is unboxed-strict, `a ` seq ` ()` is a full `rnf`.
- **`maximumBy` + `comparing`** as the dual of Day 10's `minimumBy`.  Same pattern, opposite direction: argmax over a list comprehension keyed by score.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Why a summed-area table](#why-a-summed-area-table)
3. [Data model](#data-model)
4. [`parseInput`](#parseinput)
5. [`powerLevel` -- the closed-form recipe](#powerlevel-the-closed-form-recipe)
6. [`buildSat` -- the `ST` build, line by line](#buildsat-the-st-build-line-by-line)
7. [`squareSum` -- the inclusion-exclusion lookup](#squaresum-the-inclusion-exclusion-lookup)
8. [`bestSquare` and Part 1](#bestsquare-and-part-1)
9. [`bestAnySize` and Part 2](#bestanysize-and-part-2)
10. [`part1`, `part2`, `solve`](#part1-part2-solve)
11. [Tests](#tests)
12. [Benchmarks](#benchmarks)
13. [Why inclusion-exclusion is correct](#why-inclusion-exclusion-is-correct)
14. [Possible optimizations](#possible-optimizations)
15. [Key patterns](#key-patterns)
16. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)
17. [Further reading](#further-reading)

---

## Problem summary

The puzzle input is a single integer -- the *grid serial number*.  For my input it is `9435`.  Every cell `(x, y)` with `1 ≤ x, y ≤ 300` has a power level given by:

```
rackId   = x + 10
step     = (rackId * y + serial) * rackId
hundreds = (step `div` 100) `mod` 10
level    = hundreds - 5
```

So `level ∈ {-5, -4, ..., 3, 4}` -- the "hundreds digit" extraction is a deterministic map of the integer line onto `0..9`, and the `- 5` shifts it to be symmetric around zero.

Part 1 asks for the `(x, y)` top-left of the **3×3 square** with the largest total power, written as the literal string `"x,y"`.  Part 2 lifts the size restriction: the dial now selects squares of *any* size from 1×1 to 300×300; report the winner as `"x,y,size"`.

The puzzle examples (which the tests pin):

| Serial | Part 1 (3×3)        | Part 2 (any size)            |
|--------|---------------------|------------------------------|
| 18     | `33,45` (power 29)  | `90,269,16` (power 113)      |
| 42     | `21,61` (power 30)  | `232,251,12` (power 119)     |
| 9435   | **`20,41`**         | **`236,270,11`**             |

---

## Why a summed-area table

Part 1 is small.  298 × 298 = 88,804 candidate top-left positions, each summing 9 cells -- under a million scalar operations.  A naive Python loop would finish this in a fraction of a second.  We could stop reading the puzzle right here.

Part 2 is the rub.  Brute force is *five* nested `O(N)` loops -- three to position the candidate square `(s, x, y)`, two more to sum its `s × s` cells:

```
for s  in 1..300:            # size                    ~N choices
  for x  in 1..(301-s):      # top-left x              ~N choices
    for y  in 1..(301-s):    # top-left y              ~N choices
      sum = 0
      for dx in 0..s-1:      # inner column offset     O(s) = O(N)
        for dy in 0..s-1:    # inner row offset        O(s) = O(N)
          sum += power[x+dx, y+dy]
      ...
```

The candidate-position space `(x, y, s)` is `O(N³)`; the inner cell sum is `O(s²)` per candidate.  Multiplied out:

```
total ops = Σ_{s=1}^{300} (301 - s)² × s²
          ≈ 8.3 × 10¹⁰
```

About 83 billion power-level additions -- minutes of CPU at any realistic per-add cost.  We want under a second.

The summed-area table is the classical fix.  Build a 2D prefix-sum array once -- `O(N²)` work, ~90 K cells -- and every subsequent subrectangle sum is **constant time**: four array reads and three additions, regardless of the rectangle's size.

```
sum of (x1..x2, y1..y2)
    = sat[x2, y2] - sat[x1-1, y2] - sat[x2, y1-1] + sat[x1-1, y1-1]
```

The SAT collapses the inner `(dx, dy)` double-loop into a constant -- two of the five nested `O(N)` loops disappear.  Part 2's asymptotic cost drops from `O(N⁵)` to `O(N³)`: `Σ_{s=1}^{300} (301 - s)² = 9,045,050` constant-time lookups, a ~10,000× reduction in work at `N = 300`.  At ~8.5 ns per lookup -- a handful of array reads plus a triple allocation -- the actual benchmark finishes in 77 ms.

This pattern -- *"any axis-aligned rectangle sum after one O(N²) preprocessing pass"* -- shows up everywhere in computer vision (the Viola-Jones face detector was the breakthrough use), computational geometry, and competitive programming.  It is worth recognising the moment a puzzle asks for "all rectangle sums."

---

## Data model

```haskell
newtype Puzzle = Puzzle (UArray (Int, Int) Int)

instance NFData Puzzle where
  rnf (Puzzle a) = a `seq` ()
```

A `UArray (Int, Int) Int` from `Data.Array.Unboxed`:

- **Unboxed.**  Stores raw machine `Int`s, not boxed pointers.  No thunks, no element-level GC.  Same shape as a Rust `[i64]`.
- **2D index.**  The index type is a tuple `(Int, Int)`.  `Data.Ix` defines an `Ix (a, b)` instance whenever `Ix a` and `Ix b` exist; it linearises row-major using the supplied bounds.  We pass `((0, 0), (300, 300))`, so `(x, y)` lives at offset `x * 301 + y` (or vice versa -- the order is an implementation detail of `Ix`).
- **Indices include 0.**  Storing a padding row `y = 0` and padding column `x = 0` (both zero by `newArray`'s default) lets `squareSum` do its four-corner lookup uniformly without a special case for the leftmost column or topmost row.

### Why `newtype Puzzle` rather than `type Puzzle = UArray (Int, Int) Int`

Two pragmatic reasons:

1. **Criterion needs `NFData`** on whatever `parseInput` returns, because `nf parseInput raw` deep-evaluates the result to subtract laziness-deferred work from the timing.  `UArray` does not ship an `NFData` instance in `deepseq-1.4.x` for our pinned bounds; the obvious orphan declaration

   ```haskell
   instance NFData (UArray (Int, Int) Int) where
     rnf a = a `seq` ()
   ```

   would trigger GHC's *orphan-instance* warning.  Orphan instances are also a one-way ticket to surprise behaviour if a downstream module imports the same instance from elsewhere.  The `newtype` is the standard workaround: the instance is local to the type we defined.

2. **`a ` seq ` ()` really is enough for an unboxed array.**  `UArray` has no lazy fields and no thunks at the element level (that is the whole point of "unboxed").  Forcing the array reference to weak head normal form is identical to deep evaluation.

The cost is one constructor wrap and one pattern-match in `part1` / `part2`.  Both are erased at runtime by GHC's `newtype` representation (no boxing).

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput raw =
  let serial = read (filter (\c -> c == '-' || isDigit c) raw) :: Int
  in  Puzzle (buildSat serial)
```

The input file is essentially `"9435\n"` -- one integer with possibly a trailing newline.  The whitespace-tolerant idiom from Day 10 (`filter` for digits, then `read`) handles any extra characters without a parser.

Heavy lifting moves into `parseInput`: `buildSat` is the 301 × 301 SAT build, which is `O(N²) = 90,000` cells, each three reads and one write.  Criterion will credit this work to **Parse** and the per-part square-sum queries to **Part 1 / Part 2** -- the right shape for the "data preparation vs. query" decomposition.

### `read :: Read a => String -> a`

We met `read` on Day 0.  The recap: it parses a `String` into any `Read`-instance type, dispatching on the *expected* return type.  Here we annotate the result `:: Int` so GHC picks the `Int` parser; without the annotation it would be `Integer` (arbitrary precision) which would be correct but slower.

Like Day 10 we accept that `read` will *crash* on malformed input.  For AoC this is fine; the input is trusted.

---

## `powerLevel` -- the closed-form recipe

```haskell
powerLevel :: Int -> Int -> Int -> Int
powerLevel serial x y =
  let rackId   = x + 10
      step     = (rackId * y + serial) * rackId
      hundreds = (step `div` 100) `mod` 10
  in  hundreds - 5
```

A direct transcription of the puzzle's recipe.  Worth dwelling on three things.

### Currying

`powerLevel :: Int -> Int -> Int -> Int` reads as *"give me a serial, then an `x`, then a `y`, then I will give you back an `Int`."*  Every Haskell function of multiple arguments is curried -- it is actually `Int -> (Int -> (Int -> Int))`, a chain of one-argument functions returning further functions.

In the SAT build we will call `powerLevel serial x y` with all three arguments; GHC inlines the chain and produces the same machine code as a Rust function `fn power_level(serial: i64, x: i64, y: i64) -> i64`.  No performance penalty for the curried shape.

The curried shape *does* let us write `let p = powerLevel serial` and then `p 3 5` later -- partial application is free.  We do not use that here, but it is the foundation for higher-order combinators like `map (powerLevel serial 3) [1..10]`.

### The "hundreds digit" trick

The puzzle text says "keep only the hundreds digit of the power level."  The arithmetic spelling:

```
hundreds = (step `div` 100) `mod` 10
```

- `div 100` shifts the decimal representation right by two digits.  `12345 ` div ` 100 == 123`.
- `mod 10` keeps only the units digit of what remains.  `123 ` mod ` 10 == 3`.

So the composition picks out exactly the third-from-right digit of `step` (1-indexed from the right is the units place; "hundreds" is third-from-right).  This is the same idiom you would use in C: `(step / 100) % 10`.

### `div` versus `quot`, `mod` versus `rem`

Haskell ships two integer-division pairs:

- `(div, mod)` -- rounds toward negative infinity.  `(-7) ` div ` 2 == -4`, `(-7) ` mod ` 2 == 1`.
- `(quot, rem)` -- rounds toward zero.  `(-7) ` quot ` 2 == -3`, `(-7) ` rem ` 2 == -1`.

For non-negative operands they agree.  `step` here is always non-negative (the recipe takes a positive `rackId * y + serial` and multiplies by positive `rackId`, all `Int`s in the same sign range), so either pair would work.  We use `div` / `mod` because they are the more common Haskell idiom and because the *floored* semantics are what mathematicians mean by "modular reduction."

---

## `buildSat` -- the `ST` build, line by line

```haskell
buildSat :: Int -> UArray (Int, Int) Int
buildSat serial = runSTUArray (buildSatST serial)

buildSatST :: forall s. Int -> ST s (STUArray s (Int, Int) Int)
buildSatST serial = do
  a <- newArray ((0, 0), (300, 300)) 0 :: ST s (STUArray s (Int, Int) Int)
  forM_ [1 .. 300] $ \y ->
    forM_ [1 .. 300] $ \x -> do
      let p = powerLevel serial x y
      l  <- readArray a (x - 1, y)
      u  <- readArray a (x, y - 1)
      ul <- readArray a (x - 1, y - 1)
      writeArray a (x, y) (p + l + u - ul)
  return a
```

A faithful copy of the Day 9 `play` / `playST` split: the pure wrapper hands the `ST` core to the magic-purifying combinator (`runST` there, `runSTUArray` here), and the core gets to mutate freely inside `ST`.

### `runSTUArray`

```haskell
runSTUArray
  :: Ix i
  => (forall s. ST s (STUArray s i e))
  -> UArray i e
```

The signature: pass me an `ST` action that produces an `STUArray`; I will run it, freeze the result, and hand you back the immutable `UArray`.

The `forall s.` is the same trick as `runST`: it forbids the array from escaping the `ST` scope via any sneaky path.  GHC's type-checker rejects any program that would let the mutable `STUArray` survive past `runSTUArray` -- only the frozen `UArray` can.  In Rust terms: it is like a function whose mutable borrow only exists inside the function body; outside the body, callers see an owned immutable value.

The "freeze" step is an *unsafe freeze* under the hood -- it reuses the same memory rather than copying, because the type system guarantees no one else holds a reference to the mutable phase.  Effectively free.

### `newArray ((0, 0), (300, 300)) 0`

`newArray :: (MArray a e m, Ix i) => (i, i) -> e -> m (a i e)` allocates a fresh mutable array with the given inclusive bounds, every cell pre-filled with the supplied value.

We pass `((0, 0), (300, 300))` -- inclusive on both endpoints -- which gives a `301 × 301 = 90,601`-cell array.  The padding row `y = 0` and padding column `x = 0` are zero by construction; that is what makes `squareSum`'s inclusion-exclusion uniform.

The trailing type annotation `:: ST s (STUArray s (Int, Int) Int)` is *load-bearing*.  Without it GHC sees `newArray ...` returning some `MArray a e m`-instance type and cannot decide whether to pick `STArray` (boxed) or `STUArray` (unboxed).  The annotation pins it to the unboxed flavour.

The `ScopedTypeVariables` extension brings `s` into scope inside the function body -- without it we could not name `s` in the annotation.  Same recipe as Day 9.

### `forM_ [1 .. 300] $ \y -> forM_ [1 .. 300] $ \x -> ...`

```haskell
forM_ :: (Foldable t, Monad m) => t a -> (a -> m b) -> m ()
```

`forM_` is `mapM_` with the arguments flipped, intended to read as "for each element of this list, do this action."  It is the same shape as a Rust `for y in 1..=300 { ... }` loop nested inside another.

The outer loop iterates `y = 1, 2, ..., 300`; for each `y`, the inner loop iterates `x = 1, 2, ..., 300`.  At each `(x, y)` we read the three already-filled neighbours and write the new SAT value.

#### Why `y` outer, `x` inner

The SAT recurrence reads `sat[x-1, y]`, `sat[x, y-1]`, `sat[x-1, y-1]` -- all *strictly* lower in `(x, y)` than the cell being written.  As long as we visit cells in any order that respects the partial order `<` componentwise, the recurrence's reads will all find filled values.

Row-major (`y` outer, `x` inner) is one such order: by the time we reach `(x, y)`, every `(x', y')` with `y' < y` is done, and every `(x', y)` with `x' < x` is also done.  Column-major would work equally well; we picked row-major to match a typical reader's expectation of "fill across the row, then move to the next row."

### `do`-notation in `ST`

`buildSatST` is a *do block* in the `ST s` monad.  Each `<-` line is a monadic bind: `l <- readArray a (x-1, y)` says "perform the side-effecting read and bind the resulting `Int` to `l`."  Each `let` line is a *pure* binding, no monadic effect involved.

The reason these compose so cleanly is the same reason `do` works in `IO`: the desugaring threads the implicit state (the `RealWorld` token, or in this case the `ST` region tag `s`) through every step, so the *order* of statements is fixed by the desugar, exactly as in an imperative language.

For a Rust analogue, think of `do` in `ST` as `&mut` flowing through every statement in a function -- you cannot reorder statements that all need to borrow the same array, the compiler keeps the sequence honest, and the result type tracks "I produced an `Int` in this scope" without leaking the borrow.

---

## `squareSum` -- the inclusion-exclusion lookup

```haskell
squareSum :: UArray (Int, Int) Int -> Int -> Int -> Int -> Int
squareSum sat x y s =
  let !x2 = x + s - 1
      !y2 = y + s - 1
  in  sat ! (x2, y2)
    - sat ! (x - 1, y2)
    - sat ! (x2, y - 1)
    + sat ! (x - 1, y - 1)
```

The classical 2D inclusion-exclusion identity.  Pictorially, with `A`, `B`, `C`, `D` the four SAT corners:

```
                          B  ←-------- D
                          ←            ←
                          ←   target   ←
                          A  ←-------- C
```

`A = sat ! (x-1, y-1)`, `B = sat ! (x-1, y+s-1)`, `C = sat ! (x+s-1, y-1)`, `D = sat ! (x+s-1, y+s-1)`.

- `D` is the sum of the big rectangle `(1..x+s-1, 1..y+s-1)`.
- `B` and `C` are the sums of the two strips that overshoot the target on each axis.
- `A` is the corner where `B` and `C` overlap, double-subtracted.

`D - B - C + A` cancels the strips and adds back the over-cancelled corner, leaving exactly the sum of `(x..x+s-1, y..y+s-1)`.  Four array reads, three additions, constant work.

### The `(!)` operator

```haskell
(!) :: (IArray a e, Ix i) => a i e -> i -> e
```

Immutable array indexing.  Reads the value at the supplied index in `O(1)`.  Compare with Day 9's mutable `readArray :: MArray a e m => a i e -> i -> m e` -- same operation, no monadic wrapper because the array is immutable.

A bounds violation will crash; in our case `1 ≤ x` and `x + s - 1 ≤ 300` (enforced by the call site) guarantee every read lands inside `((0, 0), (300, 300))`.

### Why the bang patterns on `x2` and `y2`

```haskell
let !x2 = x + s - 1
    !y2 = y + s - 1
```

Without the bangs, `x2` and `y2` would be lazy thunks evaluated when first used.  They are *both* used in two array indices, so the second use would re-evaluate the thunk.  GHC's CSE will usually catch this for trivial expressions, but spelling out the bang makes the strictness intent explicit and doesn't depend on optimiser luck.  At 9 million calls per Part 2 run, it is worth being explicit.

---

## `bestSquare` and Part 1

```haskell
bestSquare :: UArray (Int, Int) Int -> Int -> (Int, Int)
bestSquare sat s =
  fst $
    maximumBy (comparing snd)
      [ ((x, y), squareSum sat x y s)
      | x <- [1 .. 301 - s]
      , y <- [1 .. 301 - s]
      ]
```

For each top-left `(x, y)` whose `s × s` square fits in the grid, score it with `squareSum`, then pick the `(x, y)` with the highest score.

### `maximumBy :: Foldable t => (a -> a -> Ordering) -> t a -> a`

The "give me the max according to *this* comparator" combinator.  Together with:

```haskell
comparing :: Ord b => (a -> b) -> a -> a -> Ordering
comparing f x y = compare (f x) (f y)
```

we get `maximumBy (comparing snd)` -- the argmax by the second component of each tuple.  The result is the *whole* tuple `((x, y), score)`; `fst $` keeps just the coordinate half.

Day 10 used `minimumBy (comparing snd)` for the ternary-search probe.  Same pattern, opposite direction.

### List comprehension as the candidate stream

```haskell
[ ((x, y), squareSum sat x y s)
| x <- [1 .. 301 - s]
, y <- [1 .. 301 - s]
]
```

Equivalent to a doubly-nested `for` in an imperative language: for each `x`, for each `y`, emit one tuple.  GHC fuses the list into the consuming `maximumBy` so no intermediate list materialises -- the same loop a hand-rolled accumulator would compile to.

### Part 1 specifically

`part1 = bestSquare sat 3` with `s = 3` scans 298 × 298 = 88,804 squares.  At a few hundred picoseconds per `squareSum` (four array reads + arithmetic) plus tuple allocation in the comprehension, the bench reports **1.665 ms**.

Most of that 1.665 ms is allocation overhead, not arithmetic.  A hand-rolled bang-pattern fold over a `forM_`-style loop could shave it -- but at 1.7 ms it is already two orders of magnitude under the project's "under one second" target.

---

## `bestAnySize` and Part 2

```haskell
bestAnySize :: UArray (Int, Int) Int -> (Int, Int, Int)
bestAnySize sat = (bx, by, bs)
  where
    (bx, by, bs, _) =
      foldl' step (1, 1, 1, squareSum sat 1 1 1)
        [ (x, y, s)
        | s <- [1 .. 300]
        , x <- [1 .. 301 - s]
        , y <- [1 .. 301 - s]
        ]

    step :: (Int, Int, Int, Int) -> (Int, Int, Int) -> (Int, Int, Int, Int)
    step best@(_, _, _, !bestP) (x, y, s) =
      let !p = squareSum sat x y s
      in  if p > bestP then (x, y, s, p) else best
```

The triple comprehension enumerates every valid `(x, y, s)` -- 9,045,050 of them.  `foldl'` walks the list with a strict accumulator `(bestX, bestY, bestS, bestPower)`, replacing it whenever the candidate's power beats the running max.

### Why not `maximumBy (comparing snd)` here too

It would work, but at 9 M candidates the boxing matters:

- `maximumBy` builds 9 M `(Int, Int, Int, Int)` tuples (one per candidate), keeps each long enough to compare, throws all but one away.
- The strict `foldl' step` builds a 3-tuple `(x, y, s)` per candidate (the comprehension element), reads `squareSum` *inside* `step`, and reuses the accumulator's 4-tuple in place when the comparison fails -- no tuple allocation in the steady state once the running max is set.

The bang `!bestP` in the accumulator pattern forces the running max to weak head normal form before the comparison, so we never carry an unevaluated `Int` thunk across the 9 M iterations.  Without it, the comparison chain would tower up into a giant deferred expression.

### Why is the inner `squareSum` strict (`let !p = ...`)?

Same reason: if we used `let p = ...` (lazy) and immediately compared `p > bestP`, GHC would force `p` *during* the comparison and the bang is redundant.  But spelling it out makes the intent clear and protects against a refactor that uses `p` elsewhere (in the future tuple, or in a `where`-bound helper) without forcing it first.

### How fast in practice

9,045,050 strict steps × (4 array reads + 3 arithmetic ops + 1 comparison + occasional tuple replacement) ≈ 77.24 ms.  That works out to ~8.5 ns per candidate -- a handful of L1 cache hits, plus tuple allocation pressure.  Well inside target.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Puzzle -> String
part1 (Puzzle sat) =
  let (x, y) = bestSquare sat 3
  in  show x ++ "," ++ show y

part2 :: Puzzle -> String
part2 (Puzzle sat) =
  let (x, y, s) = bestAnySize sat
  in  show x ++ "," ++ show y ++ "," ++ show s

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ part1 puzzle)
  putStrLn ("  part 2: " ++ part2 puzzle)
```

Three small notes:

1. **The pattern-match `(Puzzle sat)` is a `newtype` unwrap**, free at runtime.  GHC compiles `Puzzle` to a phantom -- there is no constructor box.
2. **AoC wants the answer as a literal string** -- not as `(20, 41) :: (Int, Int)`.  `show x ++ "," ++ show y` is the cheapest possible formatter; for fancier cases we'd reach for `printf`.
3. **`solve` shares the parse via the `let` binding**.  `puzzle` is bound once and used for both parts; the SAT is built once, queried twice.  Bench's `combined` -- which inlines `parseInput` inside the function it benchmarks -- *does* re-parse on each iteration (that is part of what `combined` is measuring), so `solve` is faster in practice than `combined`'s mean would suggest.

---

## Tests

Coverage in [Day11Spec.hs](../../test/Day11Spec.hs):

1. **`powerLevel`** -- four worked examples from the puzzle text (the in-spec `(3, 5, serial 8) -> 4` and three additional spot-checks).
2. **`buildSat` / `squareSum`** -- single-cell sums agree with `powerLevel`.  Sanity check on the recurrence; if the SAT padding row or `squareSum`'s inclusion-exclusion is off by one, this trips.
3. **`bestSquare`** -- the puzzle's two worked Part 1 examples: serial 18 → `(33, 45)` with power 29, serial 42 → `(21, 61)` with power 30.
4. **Part 1 string formatting** -- `part1 (parseInput "18") == "33,45"` and the same for serial 42.
5. **`bestAnySize`** -- the puzzle's two Part 2 worked examples: serial 18 → `(90, 269, 16)` with power 113, serial 42 → `(232, 251, 12)` with power 119.
6. **Part 2 string formatting** -- `part2 (parseInput "18") == "90,269,16"` and the same for serial 42.
7. **Actual input** -- pinned `expectedPart1 = "20,41"`, `expectedPart2 = "236,270,11"`.

The dual worked-example tests for both parts are why a regression in `buildSat` or `squareSum` would be caught at *all four* serial numbers (8, 18, 42, 9435), not just on the actual input.  The puzzle text is generous with examples; we use every one.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench                | Mean      | What it times |
|----------------------|----------:|---------------|
| `day11/parseInput`   | 394.8 µs  | `read` + 301 × 301 SAT build via `runSTUArray`. |
| `day11/part1`        | 1.665 ms  | 88,804 `squareSum` queries + `maximumBy`. |
| `day11/part2`        | 77.24 ms  | 9,045,050 strict `foldl'` iterations + per-iter `squareSum`. |
| `day11/combined`     | 79.80 ms  | End-to-end from raw string -- approximately Parse + Part 1 + Part 2. |

**Total = Parse + Part 1 + Part 2 = 79.30 ms.**

Three observations from the numbers.

### Part 2 / Part 1 ratio

`Part 2 / Part 1 ≈ 46×`.  The candidate count ratio is `9,045,050 / 88,804 ≈ 102×`.  Why the gap?

Two reasons:

1. **Part 1 is cache-friendlier.**  It scans 88 k cells in a tight `(x, y)` grid that fits in L2 cache; Part 2 sweeps the full 90 K-cell SAT for every size and pulls cold-cache reads as `s` grows.
2. **Part 1 has fewer accumulator updates.**  Most Part 1 candidates have power well below the running max and skip the tuple replacement; Part 2 candidates also mostly skip, but the running-max replacement happens often *enough* during the early sweep to add up.

A purely arithmetic prediction would put Part 2 at 102 × Part 1 ≈ 170 ms.  The measured 77 ms is *faster* than that -- GHC's `foldl'` with bang patterns is doing real work, and the L1-resident SAT helps amortise.

### `parseInput` dominates by allocation, not work

394.8 µs for parsing **one integer** is a lot.  Almost all of that is the SAT build: 90,000 `readArray + writeArray` pairs inside `ST`, each one a memory read and write through the `STUArray`.  The `read . filter` step on the input string is a rounding error.

If parsing time mattered we would inline `buildSat` and the surrounding `solve` -- the per-cell work is so simple that a fused loop with `unsafeWrite` would shave maybe 30 %.  But 395 µs is invisible in a benchmark whose total is 79 ms.

### Combined ≈ Total

`combined = 79.80 ms`, `Total = 79.30 ms` -- a 0.5 ms gap.  This is the *per-iteration* allocation difference between criterion's `nf parseInput raw` (which builds a fresh `Puzzle` each time and pays for its GC) versus the `env`-cached parts (which run on a single shared `Puzzle`).  At ~80 ms total the gap is in the noise; on Day 0's microsecond-scale benchmarks it doubles the apparent runtime.  Use `Total` as the headline figure.

---

## Why inclusion-exclusion is correct

The `squareSum` identity:

```
sum(x..x+s-1, y..y+s-1)
    = sat[x+s-1, y+s-1]
    - sat[x-1,   y+s-1]
    - sat[x+s-1, y-1]
    + sat[x-1,   y-1]
```

is one of those formulas that is *obviously true once you see it* but worth deriving once.  Let `S(a, b) = sat[a, b]` denote the sum of `power[i, j]` over `1 ≤ i ≤ a, 1 ≤ j ≤ b` (so `S(0, b) = S(a, 0) = 0` by the zero padding).

Then for any rectangle `(x..x+s-1, y..y+s-1)` with `x ≥ 1` and `y ≥ 1`:

```
sum(x..x+s-1, y..y+s-1)
    = sum(1..x+s-1, 1..y+s-1)              -- big NW rectangle
    - sum(1..x-1,   1..y+s-1)              -- strip on the left  (W band)
    - sum(1..x+s-1, 1..y-1)                -- strip above        (N band)
    + sum(1..x-1,   1..y-1)                -- corner of the strips overlap (NW)
```

Each `sum(1.., 1..)` term *is* an `S(_, _)` lookup, so the identity reads directly.  Drawing two L-shaped strips around a rectangle and noticing they overlap once is the geometric core; the algebra is the same inclusion-exclusion principle that underlies the formula for `|A ∪ B|`.

The zero padding at row 0 and column 0 is what makes the formula uniform: for a rectangle that *starts* at `x = 1` or `y = 1`, the "strip" terms would be empty and the corner term would be doubly empty.  Without padding we would write a special case; with padding all four indices are in-bounds and look up `0` for the empty strips automatically.

This is a recurring trick.  Whenever an inclusion-exclusion identity touches an array boundary, pad the boundary with the appropriate identity element of the operation (`0` for sums, `1` for products, `True` for any-quantifiers, `False` for all-quantifiers).

---

## Possible optimizations

The current solution finishes in 79 ms and the project's target is "under a second."  These are documented for the reader, not because we plan to ship them.

### 1.  Hand-rolled triple loop with a 1D `STUArray` accumulator

```haskell
bestAnySizeST :: UArray (Int, Int) Int -> ST s (Int, Int, Int)
bestAnySizeST sat = ...
```

Replace the list-comprehension stream + `foldl'` 4-tuple with three nested loops over `s`, `x`, `y`, threading the running max through bang-pattern locals.  No tuple allocation per iteration.  Estimated speedup: 2--4× on Part 2.  Worth doing if Part 2 ever blocks a future puzzle dependency.

### 2.  `STRef`-backed running max

Keep `(bestX, bestY, bestS, bestPower) :: STRef s (Int, Int, Int, Int)` instead of threading the accumulator through the recursion.  Slightly cleaner code than the bang-tuple approach but no faster -- `STRef` writes still allocate the boxed tuple inside the cell.

### 3.  `IORef`/unboxed mutable ref for the running max

`Data.Primitive.PrimVar (Mutable s Int)` for each component of the running max would dodge tuple allocation entirely.  Combined with optimisation 1 this is the route to ~20--30 ms Part 2.  Adds a primitive dependency we do not have today.

### 4.  Avoid the SAT entirely with the "summed-area variant" trick

For Part 2 specifically: for each fixed top-left `(x, y)`, the sums `S(x, y, s)` over `s = 1, 2, ..., min(301-x, 301-y)` can be computed incrementally with `S(x, y, s+1) = S(x, y, s) + (new L-shaped frame)`.  The new frame has `2s + 1` cells.  Total work: `Σ_{s=1}^{300} (301-s)² × (2s + 1) ≈ 2 × N³ / 3`.  Slightly *worse* than SAT inclusion-exclusion in the worst case, but with much better cache locality (every cell is read in sequence rather than skipping).  Empirically I've seen this approach run Part 2 in ~30 ms in Rust.  In Haskell, the gain over our 77 ms is likely real but smaller -- probably 1.5--2×.

### 5.  Closed-form factoring of `powerLevel`

The recipe `((x + 10) * y + serial) * (x + 10)` expands to a polynomial in `(x, y)`.  We could populate the entire 300 × 300 power grid in one fused pass over `Data.Vector.Unboxed` with the polynomial inlined.  No measurable change over the current `runSTUArray` path -- the bottleneck is the 90 K reads/writes, not the 90 K arithmetic ops.

---

## Key patterns

1. **Pre-compute a query data structure in `parseInput`.**  When both parts of a puzzle want the same heavy data structure (here: a 2D prefix-sum array), build it once during parse and pass it as the `Puzzle` value.  Both parts get O(1) queries; the bench credits the build to Parse where it belongs.
2. **`runSTUArray` is the Haskell equivalent of *"allocate, mutate, freeze."*** When the long-lived result of an `ST` computation is an *array*, use `runSTUArray` rather than `runST` + `freeze`.  It picks the right unsafe freeze under the hood (memory reuse, no copy), and the type system enforces that no mutable reference survives.
3. **`newtype` to attach a missing type-class instance.**  Whenever a library type lacks an instance you need (`NFData` was today's case; `Show`, `Eq`, `Ord`, `Semigroup`, ... are common), the textbook idiom is `newtype` + a local instance.  Zero runtime cost, no orphans, plays well with strict-evaluation libraries like `deepseq` and `criterion`.
4. **Inclusion-exclusion + boundary padding.**  Whenever a formula references "the rectangle one unit before me on each axis," pad the array with the identity element of the operation so the formula does not need a special case.  This is a recurring trick in dynamic programming, image processing, and competitive geometry.
5. **`foldl'` over a triple-nested list comprehension.**  When you need an argmax over a multi-dimensional grid, the comprehension keeps the search space declarative and the strict left-fold keeps the running max allocation-free in the steady state.  Bang the running-score component so comparisons don't tower up.

---

## Side-by-side with the Rust mental model

```rust
fn power_level(serial: i64, x: i64, y: i64) -> i64 {
    let rack_id = x + 10;
    let mut p = (rack_id * y + serial) * rack_id;
    p = (p / 100) % 10;
    p - 5
}

fn build_sat(serial: i64) -> Vec<Vec<i64>> {
    let mut sat = vec![vec![0; 301]; 301];
    for y in 1..=300 {
        for x in 1..=300 {
            let p = power_level(serial, x, y);
            sat[x as usize][y as usize] =
                p
                + sat[(x - 1) as usize][y as usize]
                + sat[x as usize][(y - 1) as usize]
                - sat[(x - 1) as usize][(y - 1) as usize];
        }
    }
    sat
}

fn square_sum(sat: &[Vec<i64>], x: usize, y: usize, s: usize) -> i64 {
    let x2 = x + s - 1;
    let y2 = y + s - 1;
    sat[x2][y2] - sat[x - 1][y2] - sat[x2][y - 1] + sat[x - 1][y - 1]
}

fn best_any_size(sat: &[Vec<i64>]) -> (usize, usize, usize) {
    let (mut bx, mut by, mut bs, mut bp) = (1, 1, 1, square_sum(sat, 1, 1, 1));
    for s in 1..=300 {
        for x in 1..=(301 - s) {
            for y in 1..=(301 - s) {
                let p = square_sum(sat, x, y, s);
                if p > bp {
                    bx = x;
                    by = y;
                    bs = s;
                    bp = p;
                }
            }
        }
    }
    (bx, by, bs)
}
```

Lined up:

| Concept                            | Rust                                                            | Haskell                                              |
|------------------------------------|------------------------------------------------------------------|------------------------------------------------------|
| Mutable 2D grid build              | `let mut sat = vec![vec![0; 301]; 301]; for y { for x { ... } }` | `runSTUArray $ do a <- newArray ...; forM_ ... readArray + writeArray; return a` |
| Mutable reference, scoped          | `&mut [Vec<i64>]` in a function body                              | `STUArray s (Int, Int) Int` inside `ST s`            |
| Mutable → immutable handoff        | implicit at function return (`Vec<Vec<i64>>` is owned)            | `runSTUArray` explicitly freezes (zero copy)         |
| 2D indexing                        | `sat[x as usize][y as usize]`                                    | `sat ! (x, y)`                                       |
| Strict accumulator on a fold       | `let mut bp = ...; if p > bp { bp = p; }`                         | `foldl' step (..., !bestP) candidates`               |
| Triple-nested search               | three `for` loops + early `if`                                    | triple list comprehension + `foldl' step`            |
| Inclusion-exclusion identity       | identical -- pure arithmetic, no language differences            | identical                                            |
| String formatting `"x,y"`          | `format!("{},{}", x, y)`                                          | `show x ++ "," ++ show y`                            |

The interesting structural difference is *what happens at the mutable/immutable boundary*.  In Rust, the boundary is invisible: the function returns an owned `Vec<Vec<i64>>` and the caller treats it as if it had never been mutable.  Idiomatic, ergonomic, but the type system makes no special claim about purity.

In Haskell, the boundary is explicit: `runSTUArray :: (forall s. ST s (STUArray s i e)) -> UArray i e`.  The `forall s.` is the load-bearing trick -- the type system *proves* that the mutable phase does not escape, which is what lets `runSTUArray` use an unsafe in-place freeze and still hand back a referentially transparent `UArray`.  Once you have it, the immutable `UArray` is genuinely pure -- multiple callers can share it, GHC can common-subexpression-eliminate around it, criterion can `nf` it without surprises.

The Rust version *also* hands back a referentially transparent value once the function returns; the difference is just that Haskell's type system makes the proof explicit.  In a system that takes purity seriously enough to enforce it at compile time -- which Haskell is, by default, and Rust is, when you `&mut` carefully -- both styles work.  Haskell happens to make the proof part of the API; Rust happens to make it a property of the call graph.

---

## Further reading

The summed-area table has a forty-year history outside competitive programming -- texture filtering in graphics, real-time face detection in computer vision, soft-shadow rendering on the GPU.  The picks below are layered by depth.

### One-page reference

- [**Summed-area table** -- Wikipedia](https://en.wikipedia.org/wiki/Summed-area_table).  The formula, the four-corner identity, the history (Crow 1984, renamed "integral image" by Viola-Jones in 2001), and a list of variant forms (summed-area variance, summed table for higher moments).  Best starting point for a 30-minute orientation.

### The original paper

- [**Summed-area tables for texture mapping** -- Frank Crow, SIGGRAPH 1984](https://dl.acm.org/doi/10.1145/800031.808600).  Six pages, very readable.  Crow introduces the data structure to solve the *"what is the average colour of this rectangular patch of texture under perspective foreshortening"* problem in real-time graphics.  Worth reading once for the historical framing; the modern competitive-programming pitch is the same idea without the texture-mapping context.
- [SIGGRAPH History retrospective on Crow's paper](https://history.siggraph.org/learning/summed-area-tables-for-texture-mapping-by-crow/) -- context on why the paper mattered.

### Long-form tutorials with worked code

- [**Prefix Sums and Summed Area Tables** -- Demofox blog](https://blog.demofox.org/2018/04/16/prefix-sums-and-summed-area-tables/).  The best teaching-oriented walkthrough I've seen.  Builds up from 1D prefix sums to 2D to applications (box blur, average filters, variance via second moments).  C++ samples but the algorithm is language-agnostic.  If you read only one, read this one.
- [Fast Local Sums, Integral Images, and Integral Box Filtering -- MATLAB / *Steve on Image Processing*](https://blogs.mathworks.com/steve/2023/01/09/integral-image-box-filtering/).  Practical signal-processing angle; covers MATLAB's `integralImage` and shows how O(1) box filtering wallops Gaussian-filter speeds.
- [Computer Vision -- The Integral Image](https://computersciencesource.wordpress.com/2010/09/03/computer-vision-the-integral-image/).  The Viola-Jones face-detection framing.  Shows how the four-corner lookup is what enabled real-time face detection in 2001 -- cameras can compute Haar features at video rates because the rectangle sums are O(1) each.

### Modern advanced applications

- [**Summed-Area Variance Shadow Maps** -- GPU Gems 3, Chapter 8 (NVIDIA)](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-8-summed-area-variance-shadow-maps).  For the engine-builder angle: the same data structure on the GPU for soft-shadow filtering.  Includes a variance-shadow-maps extension that stores both `sum(x)` and `sum(x²)` so you can compute Chebyshev bounds in O(1) per shadow query.

### When AoC needs *dynamic* rectangle sums instead of static ones

The SAT we built today is read-only after `parseInput`.  If a puzzle needs the grid to *change* mid-query (point updates with rectangle sums), the upgrade is the 2D Binary Indexed Tree:

- [Binary Indexed Tree -- 2D BIT](https://cp-algorithms.com/data_structures/fenwick.html#two-dimensional-bit) -- on `cp-algorithms` (the competitive-programming reference site).  Trades the SAT's O(1) query / O(N²) rebuild for `O(log² N)` query and `O(log² N)` point update.  Overkill for Day 11; worth knowing the upgrade path exists.

---

**Navigation**: [Problem statement](day11.md) | [Summary table](summary_2018.md) | [<- Day 10](day10_function_guide.md) | Day 12 -> *(not yet attempted)*
