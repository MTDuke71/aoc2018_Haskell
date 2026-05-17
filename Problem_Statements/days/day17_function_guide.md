# Day 17: Reservoir Research -- Function Guide

**Problem**: A spring at `x=500, y=0` pours water onto a vertical
slice of sand with clay veins. Water falls, pools where clay contains
it, and streams off open edges. Part 1: how many tiles can water
reach (`|` flowing + `~` at rest) within the clay `y`-window. Part 2:
how many tiles hold water *at rest* (`~`) in that window.

**Answers**: Part 1 = **26910**, Part 2 = **22182**
**Code**: [Day17.hs](../../src/Day17.hs) · **Python reference**: [day17.py](../../python/day17.py)
**Runtime**: Parse 12.18 ms · Part 1 27.38 ms · Part 2 27.38 ms · Total ≈ 66.9 ms

**New concepts this day**:

- **Recursive flood fill on a mutable 2-D canvas.** An
  `STUArray s (Int,Int) Char` is *both* the simulation state and the
  visited-set; a cell already `|`/`~` short-circuits the recursion,
  which is what makes each pass terminate.
- **A recursion whose return value is a fact about the world it just
  mutated** — `drop` returns "is this cell solid now?", and the
  caller pools or streams based on that.
- **Monotone fixed-point iteration over a mutable structure.** One
  recursive sweep is *not* enough on real terrain; iterate (wipe the
  transient `|`, keep the permanent `#`/`~`, re-run) until the
  settled count stops growing.

---

## Table of contents

- [Problem summary](#problem-summary)
- [Why one sweep is not enough](#why-one-sweep-is-not-enough)
- [The algorithm in Python](#the-algorithm-in-python)
- [Data model](#data-model)
- [`parseInput`](#parseinput)
- [`simulate` -- the flood](#simulate----the-flood)
- [`drop'` -- fall, then spread](#drop----fall-then-spread)
- [`scan` -- how far does a row reach](#scan----how-far-does-a-row-reach)
- [The fixed-point loop](#the-fixed-point-loop)
- [`part1`, `part2`, `solve`](#part1-part2-solve)
- [Tests](#tests)
- [Benchmarks](#benchmarks)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

The scan lists horizontal and vertical clay veins. Sand is
everywhere else. A spring at `(500, 0)` produces water forever.

- Water **falls** straight down through sand.
- When it lands on clay or already-settled water it **spreads**
  sideways.
- A row that is walled by clay on **both** sides fills with
  **settled** water (`~`).
- A row open on either side **overflows**: that row is sand the water
  merely **flowed** through (`|`), and the water keeps falling at the
  open edge(s).

Count tiles only between the smallest and largest clay `y`
(`pMinY..pMaxY`) — that ignores the dry rows above the first clay and
the infinite fall past the bottom.

- **Part 1**: all tiles water can reach = `|` plus `~` in the window.
- **Part 2**: only water at rest = `~` in the window.

---

## Why one sweep is not enough

The textbook recursive flood fill is a single call from the spring:
`drop` recurses down, and on the way back up it spreads each row,
returning "is this cell solid now?" so the caller can decide to pool.
Filling a basin makes the recursion return `True` up the stack and
the level rises within one call. That is elegant, it passes the
puzzle's worked example exactly (57 / 29), and on this input it gives
**490** — water never gets below `y = 65` of a `y = 1895` map.

The reason is **internal clay islands**. The real input has sealed
clay boxes sitting inside larger basins (literally a `####` / `#..#`
/ `####` pocket in the scan). When the recursion spreads a row that
straddles such an island, the single left-to-right `scan` resolves
*one* side of the island and the bounded/overflow decision for that
row is made before the *other* side — which can only receive water
after a neighbouring pool fills — has been considered. One sweep
commits to a wrong "this row overflows" verdict and the water that
should have backed up and risen never does.

The fix is to stop trying to be clever and **iterate to a fixed
point**:

1. Wipe every transient stream (`|`) back to sand. Clay (`#`) and
   settled water (`~`) are permanent.
2. Re-run `drop` from the spring. This pass sees *more* settled water
   than the last, so `scan` finds floor where last time it found a
   gap, and more rows now pool.
3. Stop when a full pass settles no new water.

Settled water only ever grows, so the count is monotone increasing
and bounded by the grid size — the iteration converges (here in ~35
passes). This is the same shape as Day 12's fixed-point detection,
now over a 2-D mutable grid instead of a 1-D cellular rule.

---

## The algorithm in Python

The shipping solution is [Day17.hs](../../src/Day17.hs); the
type-free reference is [python/day17.py](../../python/day17.py):

```
$ python python/day17.py
  part 1: 26910
  part 2: 22182
```

The recursion and the fixed-point wrapper, condensed:

```python
def drop(x, y):
    if y > maxy:            return False     # off the bottom
    c = grid.get((x, y), ".")
    if c in "#~":           return True      # solid: supports water above
    if c == "|":            return False     # already a stream
    if not drop(x, y + 1):                   # resolve below first
        grid[(x, y)] = "|"; return False
    lx, lw = scan(-1); rx, rw = scan(1)      # spread this row
    if lw and rw:                            # walled both sides: pool
        for xx in range(lx, rx + 1): grid[(xx, y)] = "~"
        return True
    for xx in range(lx, rx + 1): grid[(xx, y)] = "|"   # overflow
    if not lw: drop(lx, y + 1)
    if not rw: drop(rx, y + 1)
    return False

while True:
    for k in [k for k, v in grid.items() if v == "|"]: del grid[k]
    drop(500, 0)
    cur = sum(v == "~" for v in grid.values())
    if cur == prev: break
    prev = cur
```

The Haskell is a faithful port; the differences are `ST` mutation
instead of a dict, and explicit array bounds.

---

## Data model

```haskell
type Pos = (Int, Int)               -- (x, y): x right, y down

data Puzzle = Puzzle
  { clay  :: !(Set Pos)
  , pMinY :: !Int, pMaxY :: !Int     -- clay y-extent: the count window
  , pXlo  :: !Int, pXhi  :: !Int     -- array x-bounds, clay ±1
  } deriving (Eq, Show)
```

**`clay` is a `Set Pos`** at parse time — the input is a sparse list
of veins; a set is the natural "is this cell clay?" structure before
we rasterise it into the array.

**`pMinY`/`pMaxY`** are the counting window the puzzle defines. They
are stored on the `Puzzle` so the parser computes them once.

**`pXlo`/`pXhi` are the clay `x`-range widened by one.** Water that
overflows a basin falls down the column immediately outside the clay,
so the simulation array needs one spare column on each side; one is
enough because a basin's overflow always falls *adjacent* to the clay
that contained it, never further out.

**`NFData` is hand-written** (`rnf c \`seq\` ...`) because
`Data.Set` is fine for `rnf` but the record mixes it with bare
`Int`s; spelling it out matches Days 13/15's manual instances.

---

## `parseInput`

```haskell
ints :: String -> [Int]
ints = map read . words
     . map (\ch -> if ch `elem` ('-' : ['0' .. '9']) then ch else ' ')

parseInput :: String -> Puzzle
parseInput raw =
  let cells = concatMap lineCells (lines raw)
      cset  = Set.fromList cells
      ys = map snd cells ; xs = map fst cells
  in  Puzzle cset (minimum ys) (maximum ys)
             (minimum xs - 1) (maximum xs + 1)
  where
    lineCells (axis : _) | [a, b, c] <- ints (axis : _) =
      if axis == 'x' then [ (a, y) | y <- [b .. c] ]
                      else [ (x, a) | x <- [b .. c] ]
    lineCells _ = []
```

- **`ints`** is the same "non-digits to spaces, then `words`/`read`"
  trick as Day 16's `nums`, extended to keep `-` (defensive; this
  input has no negatives). `'-' : ['0'..'9']` is the char set `"-0..9"`.
- **`concatMap lineCells`** — `concatMap f = concat . map f`. Each
  scan line expands to *all* the clay cells of that vein; `concatMap`
  flattens the list-of-lists into one cell list. (First explicit use
  this year; it is `flatMap` from other languages.)
- A line is `x=A, y=B..C` or `y=A, x=B..C`. `axis` (the first char)
  says which coordinate is fixed; the three integers are always
  `[A, B, C]`, so one pattern handles both orientations.
- `Set.fromList` rasterises the veins; `minimum`/`maximum` over the
  cell coordinates give the window and the array bounds in one pass.

---

## `simulate` -- the flood

`simulate` is the whole day. It runs in `runST` so the grid can be a
mutable `STUArray s Pos Char` (`'#'` clay, `'|'` flowing, `'~'`
settled, `'.'` untouched sand), and returns **both** answers as a
pair so the work is done once:

```haskell
simulate :: Puzzle -> (Int, Int)
simulate (Puzzle cset minY maxY xlo xhi) = runST run
 where
  inBounds (x, y) = x >= xlo && x <= xhi && y >= 0 && y <= maxY
  solidC ch       = ch == '#' || ch == '~'
  run :: forall s. ST s (Int, Int)
  run = do
    g <- newArray ((xlo, 0), (xhi, maxY)) '.' :: ST s (STUArray s Pos Char)
    forM_ (Set.toList cset) $ \p -> when (inBounds p) (writeArray g p '#')
    ...
```

New mechanics here, first appearances:

- **`runST :: (forall s. ST s a) -> a`** — escape `ST` back to a pure
  value once all mutation is done. (Seen Days 9/11/14; here the
  result is a pure `(Int, Int)`.)
- **`run :: forall s. ST s (Int, Int)`** — the explicit `forall s.`
  with `ScopedTypeVariables` brings the region tag `s` into scope so
  the *inner* helpers (`drop'`, `scan`, the loop) can be given
  `ST s ...` signatures. Without a named `s`, GHC generalises the
  inner workers with an ambiguous `MArray` constraint and the module
  will not compile — this is the canonical fix for "inner ST function
  needs a type signature".
- **`solidC`** — clay or settled water both act as a floor. Flowing
  water (`|`) does *not* support water above it, which is exactly why
  `|` and `~` are different characters.

---

## `drop'` -- fall, then spread

```haskell
drop' :: Int -> Int -> ST s Bool
drop' x y
  | y > maxY  = pure False                 -- fell off the bottom
  | otherwise = do
      c <- readArray g (x, y)
      case c of
        '#' -> pure True
        '~' -> pure True
        '|' -> pure False                  -- already a stream here
        _   -> do
          solidBelow <- drop' x (y + 1)
          if not solidBelow
            then do writeArray g (x, y) '|'; pure False
            else do
              (lx, lWall) <- scan x y (-1)
              (rx, rWall) <- scan x y   1
              if lWall && rWall
                then do
                  forM_ [lx .. rx] $ \xx -> writeArray g (xx, y) '~'
                  pure True
                else do
                  forM_ [lx .. rx] $ \xx -> writeArray g (xx, y) '|'
                  unless lWall (void (drop' lx (y + 1)))
                  unless rWall (void (drop' rx (y + 1)))
                  pure False
```

The contract: **`drop' x y` returns `True` iff `(x, y)` ended up
solid** (clay or settled water) and can therefore support water in
the row above.

- `y > maxY` → the water left the scanned region: not solid (`False`).
- clay / settled → already solid (`True`).
- **`'|' -> pure False`** is the per-pass visited guard. Within one
  pass a stream cell is revisited constantly (overflows reconverge);
  returning immediately makes the recursion terminate. It is *safe*
  because the cross-pass correctness comes from the fixed-point loop
  wiping all `|` and re-running, not from this single sweep.
- sand → **resolve below first** (`drop' x (y+1)`). If below is not
  solid, water just streams through: mark `|`, return `False`. If
  below *is* solid, spread along this row:
  - `scan` both directions for the reach and whether a clay wall
    stopped it.
  - **walled both sides** → fill `[lx..rx]` with `~`, return `True`
    (this row pooled; the caller may now pool the row above).
  - **open on a side** → fill `[lx..rx]` with `|`; recurse `drop'` at
    each open edge so the overflow falls; return `False`.
- **`unless`/`void`** — `unless p act = when (not p) act`; `void`
  discards the recursive `drop'`'s `Bool` (we only want its
  side-effects on the grid here). Both from `Control.Monad`.

---

## `scan` -- how far does a row reach

```haskell
scan :: Int -> Int -> Int -> ST s (Int, Bool)
scan x y dx = go x
  where
    go cx = do
      let nx = cx + dx
      nIsClay <- (== '#') <$> readArray g (nx, y)
      if nIsClay
        then pure (cx, True)               -- clay wall: bounded at cx
        else do
          belowSolid <-
            if y + 1 > maxY then pure False
                            else solidC <$> readArray g (nx, y + 1)
          if belowSolid then go nx          -- floor holds: keep going
                        else pure (nx, False)  -- no floor: falls at nx
```

Walk outward from `x` along row `y` in direction `dx` (−1 left,
+1 right). Two ways to stop:

- The next cell is **clay** → this row is *walled* on this side; the
  last open cell is `cx`. Return `(cx, True)`.
- The next cell is open but has **no floor under it** (`(nx, y+1)`
  isn't clay or settled) → water *falls* here. Return `(nx, False)`.

`(== '#') <$> readArray ...` is `fmap (== '#')` over the `ST` read —
"read the cell, then test if it's clay" in one expression. `scan`
reads only; it never mutates, so it can be a pure-ish probe used
twice per spreading row.

---

## The fixed-point loop

```haskell
clearFlow :: ST s ()
clearFlow = forM_ [xlo .. xhi] $ \x ->
              forM_ [0 .. maxY] $ \y -> do
                v <- readArray g (x, y)
                when (v == '|') (writeArray g (x, y) '.')

countSettled :: ST s Int                    -- strict nested accumulate
countSettled = goX xlo 0
  where
    goX !x !acc | x > xhi   = pure acc
                | otherwise = goY x 0 acc >>= goX (x + 1)
    goY !x !y !acc | y > maxY  = pure acc
                   | otherwise = do
                       v <- readArray g (x, y)
                       goY x (y + 1) (if v == '~' then acc + 1 else acc)

loop :: Int -> ST s ()
loop prev = do
  clearFlow
  _   <- drop' 500 0
  cur <- countSettled
  if cur == prev then pure () else loop cur
loop (-1)
```

- **`clearFlow`** resets every `|` to `.`; `#` and `~` survive. This
  is what makes each pass start from "all the water that has settled
  so far, nothing transient".
- **`countSettled`** is a hand-rolled strict double loop (the
  `BangPatterns` on `!x !acc` keep the accumulator from thunking over
  ~360 000 cells × ~35 passes). It is the scalar convergence signal.
- **`loop`** runs passes until `countSettled` stops changing. Seeded
  with `-1` so the first real count (always ≥ 0) differs and at least
  one pass runs. The settled set is monotone, so `cur == prev` means
  a true fixed point, not a transient plateau.

After the loop the grid is frozen once (`M.freeze`) and `assocs`
gives every `(Pos, Char)`; `filter` + `length` count the window two
ways for the two parts.

---

## `part1`, `part2`, `solve`

```haskell
part1 = fst . simulate
part2 = snd . simulate

solve contents = do
  let puzzle   = parseInput contents
      (p1, p2) = simulate puzzle
  putStrLn ("  part 1: " ++ show p1)
  putStrLn ("  part 2: " ++ show p2)
```

`simulate` returns the pair, so `solve` runs the flood **once** and
projects both answers — the parse-once / simulate-once discipline.
(The `part1`/`part2` entry points each re-run `simulate`; that is
deliberate so the benchmark can time them independently, and is why
the Part 1 and Part 2 means below are identical. `solve` and the real
program share the single run.)

---

## Tests

[test/Day17Spec.hs](../../test/Day17Spec.hs) pins five cases. The
puzzle's worked example is the load-bearing one because it exercises
stacked basins, an overflow, and a left-only spill — exactly the
tie-break-free but ordering-sensitive logic:

```haskell
it "reaches 57 tiles"  $ fst (simulate (parseInput exampleScan)) `shouldBe` 57
it "settles 29 tiles"  $ snd (simulate (parseInput exampleScan)) `shouldBe` 29
```

The example *also* passed back when the single-sweep version was
wrong (it has no internal islands), which is the lesson: a green
example is necessary, not sufficient. The two real-input answers
(26910 / 22182) are pinned via `actualPart1`/`actualPart2`; they are
what caught the single-sweep bug, since 490 is obviously not a real
Day 17 answer. The `exampleScan` name avoids colliding with
`Test.Hspec.example`.

---

## Benchmarks

| Bench | Mean |
|-------|------|
| `parseInput` | 12.18 ms |
| `part1` | 27.38 ms |
| `part2` | 27.38 ms |
| **Total (Parse+P1+P2)** | **≈ 66.9 ms** |

- **Parse is 12 ms** — `ints`/`read` over ~1600 vein lines, then
  `Set.fromList` rasterising ~18 000 clay cells. Same `read`-bound
  story as Days 8/16.
- **Part 1 == Part 2 == 27 ms** because each calls `simulate`, which
  runs the *entire* ~35-pass fixed-point flood; `fst`/`snd` just pick
  a field. The honest steady-state cost of the puzzle is one
  `simulate` (~27 ms), not 54; the summary's `Parse + P1 + P2`
  convention double-counts the flood here, exactly as Day 10's
  re-run search does.
- 35 passes over a ~360 k-cell array is the cost. The obvious
  optimisation — make `clearFlow` walk only the cells touched last
  pass rather than the whole array, or stop clearing entirely and use
  a generation counter — would roughly halve it; 67 ms total is well
  under budget so it is left simple.

---

## Key patterns

1. **A green example can hide an ordering bug.** The single recursive
   sweep is correct on island-free terrain (the example) and wrong on
   the real input. When an answer's *magnitude* is implausible (490
   for a 1895-deep map), trust that over the passing example and find
   the structural case the example omits.

2. **When one pass can't see the whole picture, iterate to a fixed
   point.** Keep the permanent part, discard the transient part,
   re-run, stop on a stable scalar. It is slower than a clever
   single pass but it is *obviously correct* and monotone
   convergence is easy to argue. Same tool as Day 12.

3. **The mutable grid is also the visited-set.** Marking `|`/`~`
   doubles as memoisation; the `'|' -> pure False` early-out is what
   makes each pass terminate. Recognising that the state *is* the
   visited set avoids a second structure.

---

## If I were writing this in Rust

The structure ports directly; the differences are recursion depth
and the grid type.

- `STUArray s Pos Char` → a `Vec<u8>` of `width*height` indexed
  `y*width + x`, or an `ndarray`. Same O(1) read/write, contiguous.
- `drop'`'s deep recursion (the map is ~1895 tall, and overflow
  recursion nests further) → Rust's default 8 MB main-thread stack
  handles it, but the careful version spawns a thread with an
  explicit large stack (`std::thread::Builder::stack_size`), exactly
  as the Python reference does with `threading.stack_size`. Haskell's
  `ST` recursion grows the heap-allocated stack and just works.
- The fixed-point loop is identical: a `loop { clear |; drop; if
  settled == prev break }`. `BangPatterns` strict accumulators
  become ordinary `let mut acc` — Rust is strict by default, so the
  space-leak guard the Haskell needs is free.
- `(== '#') <$> readArray g p` → `grid[idx(p)] == CLAY`. The functor
  lift over `ST` is just "the read happens to be effectful here"; in
  Rust the read is a plain expression.

The takeaway: this is a simulation puzzle, language-neutral in logic.
The only Haskell-specific friction is plumbing the `ST` region tag
`s` into inner signatures (`forall s.` + `ScopedTypeVariables`); the
only Rust-specific friction is asking for a bigger stack. Both are
one-liners once you know them.

---

**Navigation**: [← Day 16](day16_function_guide.md) | [All Days](summary_2018.md) | [Day 18 →](day18_function_guide.md)
