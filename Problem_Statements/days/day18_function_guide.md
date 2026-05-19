# Day 18: Settlers of the North Pole -- Function Guide

**Problem**: A 50×50 grid of acres, each open (`.`), trees (`|`), or
a lumberyard (`#`). Every minute all acres update *simultaneously*
from their eight neighbours. The *resource value* is (number of `|`)
× (number of `#`). Part 1: resource value after 10 minutes. Part 2:
after 1,000,000,000 minutes.

**Answers**: Part 1 = **745008**, Part 2 = **219425**
**Code**: [Day18.hs](../../src/Day18.hs) · **Python reference**: [day18.py](../../python/day18.py)
**Runtime**: Parse 43.1 µs · Part 1 1.91 ms · Part 2 72.8 ms · Total ≈ 74.7 ms

**New concepts this day**:

- **General cycle detection.** A finite automaton on a finite grid
  must eventually repeat a state, then loops forever with a fixed
  period. Record `state -> minute` in a `Map`; the first repeat gives
  the period, and you project across a billion iterations with one
  modulo. Day 12 was the *period-1* special case of this; here the
  period is genuinely > 1.
- **A pure stepped `UArray`.** Each minute builds a *brand-new*
  immutable array with `listArray` over `range bnds`, reading the old
  one. No `ST` — contrast Day 17, which mutated in place because the
  flood revisited cells. Here every cell is written exactly once per
  minute, so a pure rebuild is simpler *and* fast enough.
- **`elems` as a state key.** The row-major flattened `[Char]` is a
  cheap, `Ord`-able snapshot — exactly what a `Map` key needs.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Why cycle detection works (and why Day 12 was easier)](#why-cycle-detection-works-and-why-day-12-was-easier)
- [Data model](#data-model)
- [`parseInput`](#parseinput)
- [`step` -- one minute](#step----one-minute)
- [`transition` -- the rule](#transition----the-rule)
- [`resourceValue`](#resourcevalue)
- [`part1`, `part2`, `solve`](#part1-part2-solve)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

Strange magic: the landscape changes every minute. Three rules,
applied to every acre at once from the *old* state:

- An **open** acre (`.`) becomes **trees** (`|`) if **≥ 3** of its
  (up to 8) neighbours are trees. Otherwise it stays open.
- A **trees** acre (`|`) becomes a **lumberyard** (`#`) if **≥ 3**
  neighbours are lumberyards. Otherwise it stays trees.
- A **lumberyard** acre (`#`) **stays** a lumberyard if it is next to
  **≥ 1 lumberyard and ≥ 1 trees**. Otherwise it becomes open.

"Simultaneously" is load-bearing: every acre reads the state at the
*start* of the minute, so changes within a minute do not cascade.
This is a cellular automaton, the same family as Conway's Game of
Life and Day 12's one-dimensional pot rule.

Part 1 runs 10 minutes. Part 2 runs a billion — too many to
simulate, so we exploit periodicity.

---

## The algorithm in Python

The Haskell carries `UArray`/`newtype`/`NFData` weight that has
nothing to do with the idea. Read the algorithm here first; the
shipping copy is [python/day18.py](../../python/day18.py).

```python
DELTAS = [(dr, dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1)
          if (dr, dc) != (0, 0)]

def step(grid):
    h, w = len(grid), len(grid[0])
    out = []
    for r in range(h):
        row = []
        for c in range(w):
            trees = yards = 0
            for dr, dc in DELTAS:
                nr, nc = r + dr, c + dc
                if 0 <= nr < h and 0 <= nc < w:
                    n = grid[nr][nc]
                    if n == "|":   trees += 1
                    elif n == "#": yards += 1
            cur = grid[r][c]
            if   cur == ".": row.append("|" if trees >= 3 else ".")
            elif cur == "|": row.append("#" if yards >= 3 else "|")
            else:            row.append("#" if yards >= 1 and trees >= 1 else ".")
        out.append("".join(row))
    return out

def part2(grid, target=1_000_000_000):
    seen = {}
    t = 0
    while t < target:
        key = "\n".join(grid)
        if key in seen:                       # cycle found
            period = t - seen[key]
            remaining = (target - t) % period
            for _ in range(remaining):
                grid = step(grid)
            return resource_value(grid)
        seen[key] = t
        grid = step(grid)
        t += 1
```

`step` reads only `grid` and produces a fresh `out` — the
simultaneity is free because nothing mutates the array being read.
`part2` is the whole trick: walk minute by minute until a state
recurs, then jump.

---

## Why cycle detection works (and why Day 12 was easier)

The state space is finite: 3^2500 grids is astronomically large, but
*the trajectory the automaton actually visits* is not — it is a
single deterministic path. A deterministic function on a finite set,
iterated, must eventually revisit a state (pigeonhole). The moment it
does, the future is fully determined by the past, so it repeats with
a fixed **period** forever (a "rho" shape: a tail leading into a
loop).

So: remember the minute each state was first seen. When state `s`
recurs at minute `t`, having first appeared at `t0`:

- `period = t - t0`
- everything from `t0` on repeats every `period` minutes
- the target minute is equivalent to `t0 + (target - t0) mod period`

Implemented as: from the *current* state at minute `t`, step
`(target - t) mod period` more times. (In this input the loop
starts within a few hundred minutes and the period is small —
typically ~28 — so the `Map` stays tiny.)

**Day 12 was the period-1 case.** There the *shape* of the live set
stopped changing (only its position drifted), so a single "is this
generation's normalised shape equal to the previous one?" check
sufficed — no `Map`, just one remembered value, and the projection
was linear arithmetic on the offset. Here the grid genuinely cycles
through several distinct states, so we need the full `state -> minute`
table and a modulo. Same theorem, more general instance.

---

## Data model

```haskell
newtype Puzzle = Puzzle (UArray (Int, Int) Char)
  deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle a) = a `seq` ()
```

**Why a `UArray (Int,Int) Char`**: the grid is dense and small
(2500 cells) and `step` reads every neighbour of every cell. A
`UArray` (unboxed, contiguous) gives O(1) `!` indexing with no
pointer chasing — far better than `[String]` (`!! ` is O(n)) or a
`Map`. Indexed `(row, col)` with bounds `((0,0),(h-1,w-1))`.

**Why the `newtype` wrapper**: `deepseq` ships no
`NFData (UArray i e)` instance, and the benchmark harness's `nf`
needs one (the same wall Day 11 hit). A `newtype` lets us hang a
hand-rolled instance with zero runtime cost. For an *unboxed* array,
WHNF already implies full evaluation, so `a \`seq\` ()` is a complete
`rnf`.

`deriving (Eq, Show)`: `Eq` lets the test compare `step grid` to the
published next state directly.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput raw =
  let rows = lines raw
      h    = length rows
      w    = case rows of (r : _) -> length r; [] -> 0
  in  Puzzle (listArray ((0, 0), (h - 1, w - 1)) (concat rows))
```

- `lines :: String -> [String]` — split on `\n`.
- `length` — row count is the height; the first row's length is the
  width (`case rows of (r:_) -> ...` guards the empty input).
- `concat :: [[a]] -> [a]` — flatten the rows into one `[Char]`.
- `listArray :: Ix i => (i,i) -> [e] -> Array i e` — fill an array
  from a list in **index order**. For `((0,0),(h-1,w-1))` that order
  is row-major (second index varies fastest), which is exactly the
  order `concat rows` produces. The two line up with no transpose.

---

## `step` -- one minute

```haskell
step :: Puzzle -> Puzzle
step (Puzzle a) = Puzzle (listArray bnds [ cell (r, c) | (r, c) <- range bnds ])
 where
  bnds = bounds a
  cell (r, c) = transition (a ! (r, c)) trees yards
   where
    (trees, yards) = foldl' tally (0, 0) deltas
    tally acc@(!t, !y) (dr, dc)
      | not (inRange bnds p) = acc
      | otherwise = case a ! p of
          '|' -> (t + 1, y)
          '#' -> (t, y + 1)
          _   -> acc
      where p = (r + dr, c + dc)
```

- `bounds :: Array i e -> (i, i)` — the index range, `((0,0),(h-1,w-1))`.
- `range :: Ix i => (i,i) -> [i]` — every index in bounds, in order.
  For a 2-D tuple range that is row-major, matching `listArray`.
- The list comprehension `[ cell (r,c) | (r,c) <- range bnds ]` is
  the new grid: one fresh value per coordinate. **All reads are from
  the old array `a`** — that is what makes the update simultaneous,
  for free, with no scratch buffer.
- `(!) :: Ix i => Array i e -> i -> e` — O(1) array index.
- `inRange :: Ix i => (i,i) -> i -> Bool` — is this coordinate in
  bounds? Edge acres simply have fewer than 8 neighbours; out-of-range
  ones are skipped.
- `foldl' :: (b -> a -> b) -> b -> [a] -> b` — strict left fold
  (introduced Day 1). Here it tallies `(trees, lumberyards)` over the
  8 offsets. `acc@(!t, !y)` is an **as-pattern** with **bang
  patterns**: `acc` names the whole pair (returned unchanged when the
  neighbour is out of bounds or open), while `!t`/`!y` force the
  components so the accumulator never builds a thunk tower. (`{-# LANGUAGE
  BangPatterns #-}` is on, as in Day 17.)
- `deltas` is the 3×3 block minus the centre:

  ```haskell
  deltas = [ (dr, dc) | dr <- [-1,0,1], dc <- [-1,0,1], (dr,dc) /= (0,0) ]
  ```

Only `|` and `#` are counted; `.` falls through the `case` to `acc`
unchanged, because no rule cares how many *open* neighbours there are.

---

## `transition` -- the rule

```haskell
transition :: Char -> Int -> Int -> Char
transition '.' trees _     = if trees >= 3               then '|' else '.'
transition '|' _     yards = if yards >= 3               then '#' else '|'
transition '#' trees yards = if yards >= 1 && trees >= 1  then '#' else '.'
transition  c  _     _     = c
```

A direct transcription of the three rules, dispatched by pattern
matching on the current acre. The final `transition c _ _ = c` makes
the function **total** (every input has a result) — defensive, and it
silences the `-Wall` "non-exhaustive patterns" warning; for valid
puzzle input it is unreachable.

This is split out from `step` so it can be read against the puzzle
text line-for-line, and so the neighbour-counting machinery doesn't
obscure the actual biology.

---

## `resourceValue`

```haskell
resourceValue :: Puzzle -> Int
resourceValue (Puzzle a) = t * y
 where
  (t, y) = foldl' acc (0, 0) (elems a)
  acc (!tt, !yy) '|' = (tt + 1, yy)
  acc (!tt, !yy) '#' = (tt, yy + 1)
  acc p           _  = p
```

- `elems :: Array i e -> [e]` — the values in index order; here the
  2500 cells as a flat `[Char]`.
- One strict pair fold counts trees and lumberyards in a single pass,
  then multiplies. (Two `length . filter` passes would also work; one
  fold is the same cost as the neighbour tally and reads consistently.)

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Puzzle -> Int
part1 p = resourceValue (iterate step p !! 10)
```

- `iterate :: (a -> a) -> a -> [a]` — the lazy infinite list
  `[p, step p, step (step p), ...]` (introduced earlier in the
  series). `!! 10` forces exactly the eleventh element — minute 10 —
  and laziness means only those 10 steps are ever computed.

```haskell
part2 :: Puzzle -> Int
part2 = go Map.empty 0
 where
  target = 1000000000
  go seen t p@(Puzzle a)
    | t == target = resourceValue p
    | otherwise =
        let key = elems a
        in  case Map.lookup key seen of
              Just t0 ->
                let period    = t - t0
                    remaining = (target - t) `mod` period
                in  resourceValue (iterate step p !! remaining)
              Nothing -> go (Map.insert key t seen) (t + 1) (step p)
```

- `go` walks minute by minute. `key = elems a` is the row-major
  `[Char]` snapshot — a perfectly good `Ord` key for `Map.Map [Char] Int`.
- `Map.lookup :: Ord k => k -> Map k a -> Maybe a` — have we seen
  this exact grid?
  - `Just t0` → the loop closed. `period = t - t0`; the target lands
    `(target - t) mod period` steps past the *current* state, reached
    with a short `iterate step p !! remaining`.
  - `Nothing` → record `(key, t)` and step on (`Data.Map.Strict`, so
    the inserted minute is forced, not thunked — the default-`Map`
    space-leak guard from Day 2).
- The `t == target` guard is a safety net for the (impossible here)
  case where the target is reached before any cycle.

```haskell
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
```

Standard shape. `part1` and `part2` are independent here (no shared
prefix worth caching — Part 1 is 10 cheap steps), so `solve` just
calls both off the one parse.

---

## Key patterns

- **Finite deterministic system + huge iteration count ⇒ find the
  cycle.** The moment a state recurs, the future is a rotation of the
  past. This is the single most common "Part 2 multiplies the
  iteration count by a billion" AoC move; recognise it on sight.
- **Pure rebuild vs in-place mutation is an algorithmic choice, not a
  style one.** Day 17's flood revisited cells, so it needed a mutable
  `STUArray` and a visited-set. Day 18 writes each cell exactly once
  per minute, so a fresh `listArray` per step is both correct
  (simultaneity is automatic) and fast enough — and far simpler.
- **A flattened array is its own hash key.** `elems` turns the grid
  into something `Ord`-comparable for free; no bespoke hashing.
- **As-patterns + bang patterns** let one fold return the accumulator
  *unchanged* in the common case (`acc`) while still forcing its
  parts (`!t`, `!y`) to avoid a thunk leak.

---

## If I were writing this in Rust

`step` is a `Vec<u8>` (or `[[u8; 50]; 50]`) read into a fresh
`Vec<u8>` each minute — the exact same "read old, write new" shape;
Rust's borrow checker would actively stop you from aliasing the two,
which is the same discipline Haskell's immutability gives for free.
Neighbour counting is `DELTAS.iter().filter_map(...)` with bounds
checks, or branchless index math on a padded buffer. For Part 2 the
cycle map is `HashMap<Vec<u8>, usize>` keyed by the flattened grid —
`map.entry(state).or_insert(minute)`, then `(target - t) % period`,
identical arithmetic. `iterate step p !! n` becomes
`(0..n).fold(p, |g, _| step(&g))`. The Haskell and Rust are
structurally the same program; the only real difference is that
Haskell's `listArray`-from-list-comprehension makes the "new grid is
a pure function of the old grid" claim syntactically obvious, whereas
in Rust you assert it by not holding a `&mut` to the source.

---

**Navigation**: [← Day 17](day17_function_guide.md) | [All Days](summary_2018.md) | [Day 19 →](day19_function_guide.md)
