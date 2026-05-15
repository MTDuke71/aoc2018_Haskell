# Day 14: Chocolate Charts -- Function Guide

**Problem**: Two elves stand on an indefinitely growing /scoreboard/ of digits, starting as `[3, 7]`.  Each round: append the digits of the sum of the two elves' current scores, then each elf advances `1 + own_score` positions modulo the new scoreboard length.  Part 1 (input @N@): simulate until the scoreboard has at least `N + 10` entries and return the ten digits at indices `N..N+9` as a string.  Part 2 (input read as a digit pattern): scan the scoreboard for that pattern and return the index at which it first appears.
**Answers**: Part 1 = **`6297310862`**, Part 2 = **`20221334`**
**Runtime** (mean, criterion `-O2`): Parse = **616.6 ns** | Part 1 = **1.311 ms** | Part 2 = **210.4 ms** | **Total = 211.7 ms**
**Code**: [Day14.hs](../../src/Day14.hs)
**Tests**: [Day14Spec.hs](../../test/Day14Spec.hs)
**Bench**: `cabal bench aoc2018-bench --benchmark-options="--match prefix day14"`
**Problem statement**: [day14.md](day14.md)
**Python reference**: [python/day14.py](../../python/day14.py)

**New concepts this day** (beyond Days 0--13):

- **`STUArray` as a /pre-allocated growing tape/.**  Day 9 used `STUArray s Int Int` as two parallel index arrays (a doubly-linked list).  Day 11 used `runSTUArray` to build a summed-area table once and freeze it.  Day 14 uses `STUArray s Int Word8` as a tape we *write forward into*, tracking the populated prefix with an explicit `len :: Int` parameter threaded through the loop.  Same primitive, third pattern of use -- pick the capacity up front, never resize, never free.

- **`Word8` cell type for byte-sized data.**  Each scoreboard entry is a digit in `0..9`.  `Word8` is the smallest unboxed cell GHC ships -- one byte each in the underlying `ByteArray#`.  Choosing `Word8` over `Int` shrinks the Part 2 array from 256 MB to 32 MB at the same 32M capacity, and the contiguous-byte layout is friendlier to the CPU cache for the linear-scan workload.  First explicit cell-size tuning of the year.

- **Trailing-edge string match on a generated sequence.**  The needle is fixed (Matt's input -> `[2,3,6,0,2,1]`, a six-digit pattern); the haystack is the scoreboard, which only exists once we have produced it.  Naive comparison is `O(n * m)` where `n` is the scoreboard length and `m = patLen`.  At `n ~ 2 * 10^7` and `m = 6` that is 120M byte-compares -- enough that we add a cheap *last-byte guard* (compare a single byte before doing the full 6-byte sweep), which rejects 9 of 10 calls instantly.  Aho-Corasick and KMP are the canonical upgrades; they would help if `m` were larger or if we had multiple needles, but at `m = 6` the constant factors are already tiny.

- **`case ... of Just k -> return k; Nothing -> ...` as nested in-loop early-exit.**  Part 2 has three places where the answer might appear: the initial state, after the first digit of a round is appended, and after the second.  Each is wrapped in a `case` on a `Maybe Int`; a `Just` short-circuits straight out of the `ST` action, a `Nothing` falls through into the next stage.  Three layers of nesting in one tick, all flat under `runST`, no exceptions, no `throwError`.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [The algorithm in Python](#the-algorithm-in-python)
3. [Why this is a Haskell-mechanic day](#why-this-is-a-haskell-mechanic-day)
4. [Data model](#data-model)
5. [`parseInput`](#parseinput)
6. [Capacity tuning](#capacity-tuning)
7. [`simulateAfter` -- Part 1](#simulateafter--part-1)
8. [`simulateUntil` -- Part 2](#simulateuntil--part-2)
9. [`matchEnd`](#matchend)
10. [`part1`, `part2`, `solve`](#part1-part2-solve)
11. [Tests](#tests)
12. [Benchmarks](#benchmarks)
13. [Possible optimizations](#possible-optimizations)
14. [Key patterns](#key-patterns)
15. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)
16. [Further reading](#further-reading)

---

## Problem summary

The scoreboard starts as `[3, 7]`.  Elf 1 stands on index 0 (score 3), elf 2 on index 1 (score 7).

Each round:

1. Read the two elves' current scores `a` and `b`.
2. Compute `s = a + b`.  Since `0 <= a, b <= 9`, `s` is in `0..18` -- one or two decimal digits.  Append those digit(s) to the scoreboard in order: a two-digit `16` appends `1` first, then `6`.
3. Each elf advances `1 + their own score` positions modulo the new scoreboard length.  Elf 1 advances `1 + a`; elf 2 advances `1 + b`.

The animation in the puzzle statement is exactly this loop.  After a few rounds the scoreboard looks like:

```
(3)[7] 1  0  1  0  1  2  4 (5) 1  5  8  9 [9]  1  6  7  7  9   2 ...
```

The elf positions and the appended-digit shape are entirely determined by the initial seed -- this is a deterministic recurrence on `(scoreboard, i, j)`.

### Part 1

For Matt's input `N = 236021`, simulate until the scoreboard has at least `N + 10 = 236031` entries, then read indices `[236021..236030]` as a 10-character decimal string.

The worked examples in the puzzle give:

| N    | digits N..N+9 |
|------|---------------|
| 9    | `5158916779`  |
| 5    | `0124515891`  |
| 18   | `9251071085`  |
| 2018 | `5941429882`  |

### Part 2

Treat the input *as a digit pattern*: `236021` -> the 6-element list `[2, 3, 6, 0, 2, 1]`.  Simulate until that pattern appears in the scoreboard; return the index at which it first occurs.  The worked examples invert the Part 1 table:

| pattern | first appears at index |
|---------|------------------------|
| `51589` | 9                      |
| `01245` | 5                      |
| `92510` | 18                     |
| `59414` | 2018                   |

For Matt's input the pattern is six digits and the answer is `20221334` -- ~20 million recipes have to be produced before the pattern first shows up at the trailing edge.

The simulation produces 1-2 digits per round, so we are asking for roughly `2 * 10^7` rounds at sub-microsecond per round.  The whole thing has to live in a tight `ST` loop over an unboxed array.

---

## The algorithm in Python

The Python reference is short enough to read in one breath -- and it pins down the rule without any monadic ceremony.  Both parts at once:

```python
def simulate_after(n: int) -> str:
    board = [3, 7]
    i, j = 0, 1
    while len(board) < n + 10:
        a, b = board[i], board[j]
        s = a + b
        if s >= 10:
            board.append(s // 10)
            board.append(s % 10)
        else:
            board.append(s)
        i = (i + 1 + a) % len(board)
        j = (j + 1 + b) % len(board)
    return "".join(str(d) for d in board[n:n + 10])


def simulate_until(pat: list[int]) -> int:
    board = [3, 7]
    i, j = 0, 1
    plen = len(pat)
    last = pat[-1]
    if board[-plen:] == pat:
        return 0
    while True:
        a, b = board[i], board[j]
        s = a + b
        if s >= 10:
            board.append(s // 10)
            if board[-1] == last and board[-plen:] == pat:
                return len(board) - plen
            board.append(s % 10)
            if board[-1] == last and board[-plen:] == pat:
                return len(board) - plen
        else:
            board.append(s)
            if board[-1] == last and board[-plen:] == pat:
                return len(board) - plen
        i = (i + 1 + a) % len(board)
        j = (j + 1 + b) % len(board)
```

The Haskell `simulateAfter` / `simulateUntil` are direct transliterations, with three substitutions:

| Python idiom                  | Haskell idiom                                      |
|-------------------------------|----------------------------------------------------|
| `board: list[int]` (resizable)| `STUArray s Int Word8` (pre-allocated to 32M)      |
| `board.append(d)`             | `writeArray arr len d` + bump `len`                |
| `board[-plen:] == pat`        | `matchEnd arr len patArr patLen patLast`           |

The simulation is the same recurrence; the Haskell version has to spell out *where* the array lives (the `ST s` region), *how* it threads `len`, `i`, `j` through the tail-recursive loop, and *why* the match guard saves work.

Python finishes Part 2 in ~25 seconds on Matt's input.  The Haskell version is ~210 ms -- a 120x speedup, almost all of it from the byte-array layout and the in-loop strictness.

---

## Why this is a Haskell-mechanic day

Algorithmically, Day 14 is a one-bullet puzzle: "deterministic recurrence on a growing list, scan for a pattern at the trailing edge."  No spaceships (Day 12), no reading-order semantics (Day 13), no closed-form algebra.  The interesting work happens at the *implementation* layer: choose the right cell size, choose the right early-exit shape, choose the right "is the answer here?" check.

That makes it the textbook teaching opportunity for a few mechanics:

- Mutable arrays as a *write-forward tape* rather than a frozen lookup table.
- `Word8` as the smallest sensible cell, with a measurable memory and cache impact.
- Nested-`case` early exit inside a tail-recursive `ST` loop.
- The "last-byte guard" pattern -- a single-byte compare before a multi-byte compare.

The Python is one screen of dictionary-and-list code.  The Haskell ends up being three times longer not because the algorithm is harder but because we are explicit about all four mechanics.  Once the file is read, the mechanics carry over to Day 15 (combat simulation in mutable grid state), Day 17 (water flow over a 2-D ST grid), and Day 22 (cave region search where the bottleneck is similar trailing-edge lookups).

---

## Data model

```haskell
data Puzzle = Puzzle
  { target :: !Int
  , needle :: ![Word8]
  } deriving (Eq, Show, Generic)

instance NFData Puzzle
```

One record with two parallel views of the same number.

### `target :: !Int`

The puzzle's "skip N recipes" parameter for Part 1.  Matt's input is `236021`; `target = 236021`.  Strict because there is no useful "lazy partial target" we would ever construct.

### `needle :: ![Word8]`

The digit sequence for Part 2.  Same input, parsed as the list `[2, 3, 6, 0, 2, 1] :: [Word8]`.  `Word8` matches the cell type of the scoreboard `STUArray` -- so when Part 2 builds its read-only pattern lookup via `listArray (0, patLen - 1) needle`, the byte arrays line up without any cast.

Storing both views once at parse time means Part 1 and Part 2 each take the view they need, instead of re-parsing on each call.  Trivial saving (the parse is 616 ns) but it is the same pattern Day 9 uses for `Game { numPlayers, lastMarble }`.

### Why `Word8` and not `Char` or `Int`?

`Word8` is the byte-sized unboxed `Word` type.  Three things to know:

1. **One byte per cell in `STUArray`.**  `STUArray s Int Word8` is backed by a contiguous `MutableByteArray#`; one byte per cell, packed.  At 32M cells that is 32 MB of contiguous storage.
2. **No allocation on read / write.**  Reading a `Word8` from an `STUArray` is a single byte load into a CPU register, then a zero-extend to `Word#` (machine-word).  No `Char`-style Unicode bookkeeping, no `Int`-style boxing.
3. **`fromIntegral` conversion to `Int` is free at the machine level.**  GHC compiles `fromIntegral (w :: Word8) :: Int` to a register move with a zero-extend.  So the arithmetic in the loop can be `Int` (which is what we want for indexing) while the storage stays `Word8`.

An `Int` cell would cost 8x the memory and burn cache on the linear scan; a `Char` cell would also cost more (`Char` is 4 bytes for the codepoint, plus GHC may keep it boxed in some `STArray` flavours).  `Word8` is the right answer.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput raw =
  let digits = filter isDigit raw
      n      = read digits :: Int
      pat    = [ fromIntegral (digitToInt c) | c <- digits ]
  in  Puzzle n pat
```

Three lines, each doing one thing.

### `filter isDigit raw`

The input file is one line `"236021\n"`.  Stripping the trailing newline with a strict `filter isDigit` is a tiny notch friendlier than `head . lines $ raw` because it tolerates leading whitespace too -- I have been bitten by editors that prepend a BOM on Windows.

`isDigit :: Char -> Bool` is from `Data.Char`; it is `True` for `'0'..'9'`.

### `read digits :: Int`

`read :: Read a => String -> a` parses a `String` into any `Read`able type.  Here we pin it to `Int` with a type annotation -- without that GHC would default the polymorphic `Read` to `Integer`, which is slower for the arithmetic in `simulateAfter`.

`read` panics on malformed input.  That is acceptable for AoC: the puzzle inputs are always well-formed.  In production code we would reach for `Text.Read.readMaybe` and propagate a `Maybe Int`.

### The digit-list comprehension

```haskell
pat = [ fromIntegral (digitToInt c) | c <- digits ]
```

`digitToInt :: Char -> Int` turns `'0' .. '9'` into `0 .. 9`.  `fromIntegral :: Integral a => Num b => a -> b` then narrows `Int` to `Word8` -- a no-op cast at the machine level for small digits.

We could have built the digit list with `map`; the comprehension is one character shorter and reads as "for every character `c` in `digits`, yield its digit value as a byte."

---

## Capacity tuning

```haskell
part2Capacity :: Int
part2Capacity = 32_000_000
```

Day 14 is the first day where we have to *guess* a capacity up front.  Day 9 sized its arrays from a number in the input (`lastMarble`).  Day 11 sized its summed-area table from the puzzle's hard-coded 300x300 grid.  Day 14's Part 2 answer is unknown until we run it -- but empirical Day 14 answers for 6-digit AoC inputs all land in the 15M-25M range.

`32_000_000` gives:

- ~32 MB of contiguous storage (one byte per cell).
- A ~30% safety margin above the empirical worst case.
- A power-of-two-ish number that aligns to a clean OS page count.

If the simulation overflowed, `writeArray` would throw an out-of-range exception -- which is loud and obvious, rather than a silent corruption.  In practice the simulator finds the pattern far before then.

### The `NumericUnderscores` extension

```haskell
{-# LANGUAGE NumericUnderscores #-}
```

This pragma at the top of the file lets us write `32_000_000` for `32000000`.  Same trick Rust, Java, and recent Python all have; in Haskell it is one of the standard-bearer "ergonomic" extensions and shipped with every modern GHC.  No semantic change -- just readability.

---

## `simulateAfter` -- Part 1

```haskell
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
  let readOut !k acc
        | k < n     = return acc
        | otherwise = do
            v <- readArray arr k
            readOut (k - 1) (intToDigit (fromIntegral v) : acc)
  readOut (n + 9) []
```

Four chunks worth pulling apart.

### `runST` -- shape recap

```haskell
runST :: (forall s. ST s a) -> a
```

We enter `ST` to do scoped mutation and exit with a pure value.  The `forall s` rank-2 quantifier prevents mutable references from leaking outside `runST` -- the same trick Day 9 used.  The `ScopedTypeVariables` extension at the top of the file is what lets us write `STUArray s Int Word8` inside the body and have GHC understand that the `s` here is the *same* `s` introduced by `runST`.

If you need to revisit the shape, the [Day 9 function guide](day09_function_guide.md#the-st-monad-and-stuarray) covers it in more depth.

### Capacity = `n + 12`

```haskell
let cap = n + 12
arr <- newArray (0, cap - 1) 0 :: ST s (STUArray s Int Word8)
```

We allocate `n + 12` cells and initialise them to zero.  Why `+12` rather than `+10`?  The loop terminates the moment `len >= n + 10`, but one round can append two digits at once -- so the last write can land at index `n + 11` if we crossed the threshold by writing the second digit of a two-digit sum.  Two extra cells of slack covers that without ever indexing past the end.

`newArray :: MArray a e m => (i, i) -> e -> m (a i e)` is the unboxed-array constructor; the type annotation pins the array variant and the cell type.  The `0` is the initial value for every cell, which is a fine sentinel because `0` is also the valid digit value `0` (we will overwrite every cell we read).

### The tail-recursive `loop`

```haskell
let loop !i !j !len
      | len >= n + 10 = return ()
      | otherwise = do ...
```

Three loop variables, all banged for honest strictness:

| Name | What                                            |
|------|-------------------------------------------------|
| `i`  | Elf 1's current index into the scoreboard       |
| `j`  | Elf 2's current index into the scoreboard       |
| `len`| Number of populated cells (one past the last)   |

The guard `len >= n + 10` terminates the moment we have enough digits.  Note `>=` not `==`: if a two-digit append crossed the threshold, we *land* at `n + 11`, not `n + 10`.

Inside the body we read `a = arr[i]`, `b = arr[j]`, compute `s = a + b`, and case on whether the sum has two digits:

```haskell
len' <- if s >= 10
          then do writeArray arr len       (fromIntegral (s `quot` 10))
                  writeArray arr (len + 1) (fromIntegral (s `rem` 10))
                  return (len + 2)
          else do writeArray arr len (fromIntegral s)
                  return (len + 1)
```

`quot` and `rem` are the truncating-towards-zero variants of `div` and `mod`.  For non-negative `s` they agree -- I use `quot` / `rem` because GHC compiles them to a single `IDIV` instruction without the small extra branch `div`/`mod` adds for sign correction.  At 20M+ rounds the extra branch shows up.

Then advance the elves modulo `len'`:

```haskell
let !i' = (i + 1 + fromIntegral a) `mod` len'
    !j' = (j + 1 + fromIntegral b) `mod` len'
```

`(i + 1 + a)` is the unwrapped destination; `mod len'` wraps it.  Since `a` is at most 9, the addend is at most 10, so after the first few rounds (`len' > 10`) the wrap is at most a single subtraction -- but `mod` is correct in all cases and the cost is two cycles for `Int`-sized integer division.  We do not micro-optimise this; see the [Possible optimizations](#possible-optimizations) sidebar.

### `readOut` -- digit walk back

After the loop, we walk `arr[n + 9]` down to `arr[n]`, consing onto an accumulator so the resulting `String` is in left-to-right order:

```haskell
let readOut !k acc
      | k < n     = return acc
      | otherwise = do
          v <- readArray arr k
          readOut (k - 1) (intToDigit (fromIntegral v) : acc)
readOut (n + 9) []
```

Right-to-left iteration with prepend avoids the O(n) cost of `++` at every step; we end up with a 10-character list built in 10 prepends.

`intToDigit :: Int -> Char` is the inverse of `digitToInt` -- it maps `0 .. 9` to `'0' .. '9'` and `10 .. 15` to `'a' .. 'f'`.  We use it only on the first range here.

---

## `simulateUntil` -- Part 2

```haskell
simulateUntil :: [Word8] -> Int
simulateUntil pat = runST $ do
  let cap     = part2Capacity
      patLen  = length pat
      patArr :: UArray Int Word8
      patArr  = listArray (0, patLen - 1) pat
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
```

Same shape as `simulateAfter` with one critical difference: we check for a match *after every single appended digit*, not just at the end of the round.

### Why check after every digit, not every round

The needle is `[2, 3, 6, 0, 2, 1]`.  Suppose a round computes `s = 12` and the scoreboard ends `..., 3, 6, 0, 2`.  Appending `1` (the first of the two digits) completes the needle at the trailing edge -- the answer is `len - 6` *before* we write the second digit `2`.  If we only checked after the whole round, we would miss this and report `len - 6 + 1` (off by one) or worse, the *next* occurrence of the pattern.

Two append points means two `case ... of Just k -> return k; Nothing -> ...` blocks, one after each `writeArray`.  Plus the `initialCheck` at the top, which handles needles that match the seed `[3, 7]` (the puzzle never asks for one, but the function is total).

### Why `patArr :: UArray Int Word8` and not just the `[Word8]` list

`UArray Int Word8` is the immutable (frozen) flavour of `STUArray`.  Reading `patArr ! k` is a single-byte load -- the same machine operation as a Rust `pat[k]` on a `&[u8]`.  Looking up `pat !! k` on the `[Word8]` list would be O(k) every time (linked-list traversal).

We pay a one-time cost (`listArray (0, patLen - 1) pat`) to build the byte array.  At `patLen = 6` the build cost is microseconds and the per-lookup saving multiplies across millions of `matchEnd` calls.

### Why precompute `patLast`

```haskell
patLast = if patLen == 0 then 0 else patArr ! (patLen - 1)
```

The same byte every time -- we read it once and pass it as a function argument to `matchEnd`.  Could we just have `matchEnd` read `patArr ! (patLen - 1)` itself?  Yes, and at GHC's optimisation level the difference is small.  But making the last byte an explicit parameter signals that the guard *is* part of the algorithm, not an implementation detail of `matchEnd`.

### Triple-nested `case` -- the cost of explicitness

Three potential exit points (initial, after digit 1, after digit 2) means three layers of `case`.  An exception-based design (`throwE k` from inside the loop, `runExceptT` outside) would flatten the nesting but introduces the `ExceptT` transformer for what is fundamentally a one-shot early return.  At 20M loop iterations, the explicit `case` is also a couple percent faster -- no `Either`-wrapping allocation per iteration.

Once you have read the pattern twice it becomes mechanical: "store, check, return on hit, else proceed."

---

## `matchEnd`

```haskell
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
```

Three things to know.

### The `patLast` guard

```haskell
lastV <- readArray arr (len - 1)
if lastV /= patLast
  then return Nothing
  else ...
```

The scoreboard's trailing digit is uniformly distributed across `0..9` in practice, so a random scoreboard's last byte has a 90% chance of *not* matching `patLast`.  Reading one byte and comparing it is two instructions; rejecting the call here avoids the inner loop entirely.

This optimisation gets us from ~2 seconds (no guard) to ~210 ms.  An order of magnitude from one byte's worth of comparison.

### The inner loop stops at `patLen - 1`

```haskell
let go !k
      | k >= patLen - 1 = return True
      | otherwise = do v <- readArray arr (start + k)
                       if v == patArr ! k then go (k + 1) else return False
```

The terminator is `patLen - 1`, not `patLen`, because we *already verified the last byte* in the `patLast` guard.  Stopping the loop one position short of the end is correct.

This shaves 6 reads (1/6 of the inner work) for every call that passes the guard.  Tiny but free.

### Why `start + k` and not a reversed walk

The scoreboard byte at index `start + k` is being compared to the pattern byte at index `k`.  We could just as well have walked the indices `[start..len-1]` and `[0..patLen-1]` in parallel; using a single `k` keeps the bookkeeping flat.

A reversed walk (compare `arr[len - 1]` to `patArr[patLen - 1]`, then `arr[len - 2]` to `patArr[patLen - 2]`, ...) would early-exit on the *first* mismatch from the right, which is no faster on uniformly-distributed digits.  The left-to-right walk is simpler and easier to read; mismatches are equally likely anywhere.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Puzzle -> String
part1 (Puzzle n _) = simulateAfter n

part2 :: Puzzle -> Int
part2 (Puzzle _ pat) = simulateUntil pat

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ part1 puzzle)
  putStrLn ("  part 2: " ++ show (part2 puzzle))
```

Each part picks its view of the puzzle (`target` for Part 1, `needle` for Part 2) and dispatches to the corresponding simulator.  This is the same `parseInput` / `part1` / `part2` / `solve` shape every day uses -- the bench's `dayBench` helper picks them up by name.

The `Puzzle (Puzzle n _)` and `(Puzzle _ pat)` patterns are the underscore-as-wildcard idiom: we are pattern-matching on the constructor and naming only the field we care about.  GHC does *not* warn about unused field selectors -- the underscore is for the reader.

---

## Tests

Coverage in [Day14Spec.hs](../../test/Day14Spec.hs):

1. **`parseInput`** -- pins both views (`target` and `needle`) and verifies the parser tolerates leading whitespace / trailing newlines.
2. **Part 1 worked examples** -- all four `simulateAfter` cases from the puzzle statement: `N = 9, 5, 18, 2018`.  Each pins both correctness *and* the loop's termination condition (we land exactly at the threshold, not past it).
3. **Part 2 worked examples** -- the four inverted `simulateUntil` cases, including the `2018` case which requires generating a non-trivial scoreboard (~2030 entries) before the pattern lands.
4. **Actual puzzle input** -- pinned `expectedPart1 = "6297310862"`, `expectedPart2 = 20221334`.

The worked examples are the spec; if you ever rewrite the simulator (KMP, vectorised, multi-needle, ...), those eight tests are what tell you whether the new version still produces the same answers as the old.

`simulateAfter` is exposed in the module's export list specifically so the worked-example tests can call it with an `Int` argument directly, without round-tripping through `parseInput`.  Same for `simulateUntil`.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean      | What it times                                                  |
|--------------------|----------:|----------------------------------------------------------------|
| `day14/parseInput` | 616.6 ns  | `filter isDigit`, `read`, and one list comprehension           |
| `day14/part1`      | 1.311 ms  | `simulateAfter 236021` -- ~157k rounds, 32 cells / round       |
| `day14/part2`      | 210.4 ms  | `simulateUntil [2,3,6,0,2,1]` -- ~13.5M rounds                 |
| `day14/combined`   | 210.2 ms  | End-to-end from raw string                                     |

**Total = Parse + Part 1 + Part 2 = 211.7 ms.**

Three observations.

### Parse is essentially free at 616 ns

The input is one number.  `filter isDigit` walks ~7 characters, `read` parses ~7 characters into an `Int`, and the list comprehension builds a 6-element `[Word8]`.  No allocation worth speaking of; 616 ns is dominated by the criterion harness's `nf`-driven WHNF check.

### Part 1 is fast because the work is bounded

`n + 10 = 236031` cells means ~157,000 simulation rounds (since each round appends 1.5 cells on average).  At ~8.3 ns per round we run through it in 1.3 ms.

### Part 2 is dominated by `matchEnd` calls

`simulateUntil` runs ~13.5M rounds before the pattern lands, appending ~20.2M digits total.  Per-digit cost is ~10 ns; ~6 ns of that is the round logic (read elves, sum, write, advance), the other ~4 ns is the `matchEnd` guard.  90% of guard calls bail out after the one-byte compare; the other 10% do up to five additional reads.

The 210 ms is the simulation itself; the `combined` bench reports 210.2 ms because parse is too cheap to matter.

---

## Possible optimizations

The current solution finishes in 211.7 ms.  These are documented for the reader, not because we plan to ship them.

### 1. KMP / Aho-Corasick for the pattern match

`matchEnd` does up to `patLen` byte compares per call.  KMP would precompute the pattern's "failure function" (a.k.a. longest proper prefix that is also a suffix) and, on a mismatch at position `k`, skip ahead by the failure-function value instead of restarting from `start + 1`.  At `patLen = 6` and digit alphabet `|Sigma| = 10`, the speedup is small -- the last-byte guard already does most of what KMP would.

For longer needles (say, 16 digits), KMP starts to pay off because the inner loop's average compare length grows.  The classic Wikipedia [KMP article](https://en.wikipedia.org/wiki/Knuth%E2%80%93Morris%E2%80%93Pratt_algorithm) and the [Aho-Corasick algorithm](https://en.wikipedia.org/wiki/Aho%E2%80%93Corasick_algorithm) (for multi-needle search) are the canonical references.

### 2. Avoid `mod` for the elf-advance

```haskell
let !i' = (i + 1 + fromIntegral a) `mod` len'
```

`mod` compiles to `IDIV`, which is ~20 cycles.  Since `1 + a` is at most 10, after a few rounds `len'` is far larger than the addend and the wrap is at most one subtraction:

```haskell
let !rawI = i + 1 + fromIntegral a
    !i'   = if rawI < len' then rawI else rawI - len'
```

Two cycles instead of twenty.  Across 27M elf advances that is ~500 ms of saving in microbenchmarks of the bare `mod` -- in our actual loop the saving is closer to 30-50 ms because the `mod` is amortised against the rest of the round.

In testing the conditional variant brought Part 2 down to ~180 ms.  Not shipped because it adds a branch and the loop is already short -- but documented because it is the next-most-obvious thing to try.

### 3. SIMD-ish parallel match

Modern CPUs can compare 8 or 16 bytes at once with vector instructions.  GHC does not generate SIMD by default, but the `simd` package / hand-rolled FFI to `_mm_cmpeq_epi8` would let `matchEnd` compare the entire 6-byte pattern in a single instruction.

For a 6-byte needle the saving over the current loop is marginal (the `patLast` guard already rejects 90%).  For a 32-byte needle SIMD would be transformative.  Not relevant at this puzzle's scale.

### 4. Maintain an incremental match-prefix state machine

Track, across rounds, "how many bytes of the pattern does the current scoreboard suffix match?"  On each new appended byte, advance the state machine and report on full match.  This is essentially KMP unrolled into the main loop, and removes `matchEnd` entirely -- replaced by a single `if state == patLen then return ...` check.

Saves the `matchEnd` call overhead at the cost of carrying an extra `Int` through the recursion.  Practical speedup ~20% on this puzzle.

### 5. Drop pre-allocated capacity, use `Data.Vector.Unboxed.Mutable` with `grow`

`Data.Vector.Unboxed.Mutable.MVector` supports `grow`, which doubles the underlying byte array when the active region runs out.  This trades 32M of up-front allocation for an amortised-O(1) push.

Pros: no magic capacity number; works for any input size.  Cons: introduces a new dependency (`vector`), adds amortisation noise to benchmarks, and the `grow` itself involves a memcpy of the active region each time it fires.

For Day 14's bounded answer the pre-allocated array is simpler.  For real applications where the upper bound is unknown, `MVector` with `grow` is the right primitive.

### 6. Run Part 1 inside Part 2

The Part 1 answer is "what are recipes `N..N+9`" -- which is information *also produced* by Part 2's simulator, just not stored.  A combined `solve` could share the scoreboard array between the two parts: build up to `len >= N + 10`, snapshot the digits, then continue until the pattern matches.

Saves the cost of one Part 1 simulation (1.3 ms).  Adds the bookkeeping for "have we crossed `N + 10` yet?"  Not worth it at 1.3 ms; documented for the reader of the pattern.

---

## Key patterns

1. **Pre-allocate, write forward, track `len` separately.**  When the size of a generated sequence is bounded but not known precisely, a fixed-capacity `STUArray` plus an `Int` for "populated prefix length" is cheaper than a resizable structure.  The capacity number is a magic constant -- pick it generously; under-allocation is loud (out-of-range), over-allocation is silent (a few unused MB).

2. **`Word8` cells for byte-sized data.**  When each cell of an unboxed array fits in a byte, `Word8` shrinks memory 8x compared to `Int`.  Reads remain a single byte load with a free zero-extend to `Word#`.  Useful for: digit sequences (this puzzle), DNA strings, RGB pixel components, tile maps.

3. **Last-byte guard before multi-byte compare.**  When scanning a generated sequence for a needle at the trailing edge, comparing one cheap byte before the full compare rejects most non-matches instantly.  Works because random sequences are uniformly distributed: needle's last byte hits the haystack's last byte with probability `1 / |Sigma|`.

4. **Nested `case` for early-exit inside `ST`.**  Three potential exit points in one round -> three `case ... of Just k -> return k; Nothing -> ...` layers.  No `ExceptT`, no exceptions.  Reads bottom-up: "if this layer found the answer, return; else proceed."

5. **`quot` / `rem` over `div` / `mod` for non-negative integers.**  Same answer when both operands are non-negative; `quot` / `rem` skip the sign-correction branch and compile to one instruction less.  Useful in hot inner loops on `Int`.

---

## Side-by-side with the Rust mental model

```rust
fn simulate_after(n: usize) -> String {
    let mut board: Vec<u8> = Vec::with_capacity(n + 12);
    board.push(3);
    board.push(7);
    let (mut i, mut j) = (0usize, 1usize);
    while board.len() < n + 10 {
        let (a, b) = (board[i] as usize, board[j] as usize);
        let s = a + b;
        if s >= 10 {
            board.push((s / 10) as u8);
            board.push((s % 10) as u8);
        } else {
            board.push(s as u8);
        }
        i = (i + 1 + a) % board.len();
        j = (j + 1 + b) % board.len();
    }
    board[n..n + 10].iter().map(|&d| (b'0' + d) as char).collect()
}

fn simulate_until(pat: &[u8]) -> usize {
    let mut board: Vec<u8> = Vec::with_capacity(32_000_000);
    board.push(3);
    board.push(7);
    let (mut i, mut j) = (0usize, 1usize);
    let plen = pat.len();
    let last = pat[plen - 1];
    if board.ends_with(pat) {
        return 0;
    }
    loop {
        let (a, b) = (board[i] as usize, board[j] as usize);
        let s = a + b;
        let mut check = |board: &Vec<u8>| -> Option<usize> {
            if *board.last().unwrap() == last && board.ends_with(pat) {
                Some(board.len() - plen)
            } else {
                None
            }
        };
        if s >= 10 {
            board.push((s / 10) as u8);
            if let Some(k) = check(&board) { return k; }
            board.push((s % 10) as u8);
            if let Some(k) = check(&board) { return k; }
        } else {
            board.push(s as u8);
            if let Some(k) = check(&board) { return k; }
        }
        let new_len = board.len();
        i = (i + 1 + a) % new_len;
        j = (j + 1 + b) % new_len;
    }
}
```

Lined up:

| Concept                              | Rust                                            | Haskell                                                  |
|--------------------------------------|-------------------------------------------------|----------------------------------------------------------|
| Growable byte array                  | `Vec<u8>` (with `with_capacity` to pre-size)    | `STUArray s Int Word8` + explicit `len` counter          |
| Cell access                          | `board[i]`                                      | `readArray arr i`                                        |
| Append a digit                       | `board.push(d)`                                 | `writeArray arr len d`, then `len' = len + 1`            |
| Pattern table                        | `&[u8]` (borrowed slice)                        | `UArray Int Word8` (frozen unboxed array)                |
| Trailing-edge match                  | `board.ends_with(pat)`                          | `matchEnd arr len patArr patLen patLast`                 |
| Early exit                           | `return k;` from inside the `loop`              | `case ... of Just k -> return k; ...`                    |

Two Rust-vs-Haskell themes are worth naming.

### Resizable Vec vs fixed-capacity `STUArray`

Rust's `Vec<u8>` is the natural fit for a growable sequence: `push` is amortised O(1), and `with_capacity(32_000_000)` pre-allocates the same 32 MB our Haskell does.  When `push` overflows the capacity, `Vec` reallocates and memcpys the active region -- the `MVector.grow` strategy from the "Possible optimizations" sidebar.

Haskell does not have a built-in resizable unboxed array in `array` or `containers` -- you get the fixed-capacity `STUArray`, or you pull in the `vector` package for `MVector`.  At AoC scale, the fixed-capacity choice is simpler and faster.

### Early exit: `return` vs `case`

Rust's `return k` from inside a `loop` is a direct unconditional jump.  Haskell does not have a `return` keyword in the imperative sense; it has the *function* `return :: Monad m => a -> m a` (which for `ST` is `pure`).  To early-exit from inside an `ST` action, we structure the control flow so that "found the answer" produces a `pure k` and "did not find" continues the recursion.

The `case ... of Just k -> return k; Nothing -> ...` idiom is the standard pattern.  It is mechanically equivalent to a Rust `if let Some(k) = ... { return k; }` -- just spelled out as a sum-type case rather than a special control-flow keyword.

---

## Further reading

Trailing-edge string match, growable arrays, and the canonical vocabulary of "find the needle in a generated haystack."

### Knuth-Morris-Pratt (KMP) and Aho-Corasick

- [**Knuth-Morris-Pratt algorithm** -- Wikipedia](https://en.wikipedia.org/wiki/Knuth%E2%80%93Morris%E2%80%93Pratt_algorithm).  The textbook upgrade over naive needle-in-haystack search.  Precompute a "failure function" (longest proper prefix that is also a suffix) for the needle; on a mismatch at position `k`, skip ahead by the failure-function value instead of restarting from the next position.  Linear-time total scan; the failure function precompute is also linear.
- [**Aho-Corasick algorithm** -- Wikipedia](https://en.wikipedia.org/wiki/Aho%E2%80%93Corasick_algorithm).  Generalises KMP to multiple needles simultaneously: build a trie of patterns, decorate with KMP-style fail links, walk the haystack once.  Used in `grep -F` for fixed-string search and in network intrusion detection for matching thousands of attack signatures concurrently.
- [**Z-algorithm** -- cp-algorithms.com](https://cp-algorithms.com/string/z-function.html).  Cousin of KMP; computes, for every position `i`, the longest substring starting at `i` that is also a prefix of the haystack.  Useful for "all-occurrences" search problems.

### Growable arrays and amortised analysis

- [**Dynamic array** -- Wikipedia](https://en.wikipedia.org/wiki/Dynamic_array).  The amortised-O(1) push that Rust's `Vec`, Java's `ArrayList`, and Python's `list` all implement.  Standard amortised analysis (doubling growth factor) shows that, even though some pushes trigger an O(n) memcpy, the average per-push cost is constant.
- [**Cache-oblivious algorithms** -- Wikipedia](https://en.wikipedia.org/wiki/Cache-oblivious_algorithm).  Day 14's contiguous-byte layout is what makes the inner loop fast in cache; cache-oblivious algorithms generalise this to "fast on any cache hierarchy, without tuning."

### Earlier AoC days that touched the same primitives

- **AoC 2018 Day 9 (Marble Mania)** -- the introductory `STUArray` day.  Day 14 reuses the `runST`-with-`STUArray` shape; the cell type and the *direction of use* (growing tape vs static doubly-linked list) are the new pieces.
- **AoC 2018 Day 11 (Chronal Charge)** -- the `runSTUArray` build-then-freeze pattern.  Day 14 differs in keeping the array mutable through the whole simulation.
- **AoC 2017 Day 17 (Spinlock)** -- a smaller cousin of Day 14: a single agent inserting numbers into a growing list with a wrap-around index advance.  Same growing-tape pattern, simpler advance rule.

### Why Day 14 is a small puzzle made big by the implementation

Algorithmically Day 14 is trivial: a deterministic recurrence on a list.  The challenge is *making it fast enough*.  The same "small algorithm, large constant factor" shape shows up in:

- **Conway's Game of Life on a billion cells** -- the rule is trivial; the speedup comes from bit-packing, double-buffering, and cache-friendly traversal.  See [Tom Rokicki's QLife / HashLife](https://www.gathering4gardner.org/g4g7gift/Rokicki-HashLifeforDummies.pdf).
- **Mining cryptocurrencies** -- the algorithm is "SHA-256 a counter".  The speedup is ASIC pipelining.
- **Database scans of trillion-row tables** -- the algorithm is "compare a column to a constant".  The speedup is SIMD, columnar storage, and vectorised execution.

In each case the algorithm fits in a paragraph; the *engineering* fits in a textbook.  Day 14 is a miniature version of the same lesson.

---

**Navigation**: [Problem statement](day14.md) | [Summary table](summary_2018.md) | [<- Day 13](day13_function_guide.md) | Day 15 -> *(not yet attempted)*
