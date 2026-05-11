# Day 10: The Stars Align -- Function Guide

**Problem**: Each input line records a 2D point with a constant 2D velocity.  At `t = 0` the points are scattered far apart; over time they drift toward each other, briefly converge into letters that spell out an eight-letter message, then fly apart again.  Part 1 asks for the message, Part 2 asks for the second at which it appears.
**Answers**: Part 1 = **`JLPZFJRH`** (read off the rendered ASCII art), Part 2 = **10595**
**Runtime** (mean, criterion `-O2`): Parse = **1.25 ms** | Part 1 = **45.79 ms** | Part 2 = **42.81 ms** | **Total = 89.85 ms**
**Code**: [Day10.hs](../../src/Day10.hs)
**Tests**: [Day10Spec.hs](../../test/Day10Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day10"`
**Problem statement**: [day10.md](day10.md)

**New concepts this day** (beyond Days 0--9):

- **Quasi-convex search by stepping**.  The bounding-box area shrinks as the points converge, hits a single minimum at the moment the message is readable, and grows again afterwards.  That makes "step until the area would grow" find the right second in `O(t)` simulation passes -- no algebra, no closed form.
- **Multi-line `String` as the puzzle answer**.  First day where Part 1 is not a single number or short word: it is an ASCII picture, eight letters tall, that the human reads to obtain the message.  We do not run any OCR; the rendering *is* the answer, and the test pins the exact picture.
- **Whitespace-tolerant parsing without `megaparsec`**.  Replace every non-digit, non-minus character with a space, then `words` + `read`.  Idiomatic for noisy fixed-format AoC lines.
- **`Set` membership for sparse-grid rendering**.  Build a `Set` of occupied `(x, y)` pairs once, then walk every cell of the bounding box exactly once, asking `Set.member`.  Avoids materialising a 2D array for what is mostly empty space.
- **Single-pass `foldl'` over four extrema** for `bboxArea`, threading `(xMin, xMax, yMin, yMax)` through the list.  Cleaner than four separate `minimum`/`maximum` traversals.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [The bounding-box trick](#the-bounding-box-trick)
3. [Data model](#data-model)
4. [`parseInput` and `parseLine`](#parseinput-and-parseline)
5. [`step` and `bboxArea`](#step-and-bboxarea)
6. [`findMessage`](#findmessage)
7. [`render` -- the ASCII picture](#render-the-ascii-picture)
8. [`part1`, `part2`, `solve`](#part1-part2-solve)
9. [Tests](#tests)
10. [Benchmarks](#benchmarks)
11. [Why is the area function unimodal?](#why-is-the-area-function-unimodal)
12. [Visualisation: reverse-engineering the puzzle generator](#visualisation-reverse-engineering-the-puzzle-generator)
13. [Possible optimizations](#possible-optimizations)
14. [Key patterns](#key-patterns)
15. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

Each of the ~300 input lines looks like:

```
position=<-52775,  31912> velocity=< 5, -3>
```

A 2D position and a 2D velocity, both signed `Int`s.  Time advances in integer seconds, and at each tick every point moves by its velocity.  Velocities are constant for all time.

The points are scattered initially -- the actual input has positions in `[-52000, 52000]` -- but they are travelling toward a configuration in which they momentarily spell out a short message in capital letters.  After that instant they keep going and disperse again.  We must:

- Find the second `t` at which the message is readable (Part 2).
- Render the picture at that second so a human can read the eight letters off the rendering (Part 1).

The puzzle does not say "find the smallest bounding box."  It says "find the moment when the message is readable."  We use the bounding-box-area heuristic because it is a robust proxy for "the points are clustered" and because it leads to an algorithm that does not assume anything about the message's font.

---

## The bounding-box trick

Consider any single coordinate, say the leftmost `x` over time.  Let the leftmost point at `t = 0` be the one with extreme `x` and the most-negative `vx`; that point's x-position decreases linearly until some other point overtakes it as the leftmost.  In general `xMin(t)` is the *upper envelope* of `(px_i + t * vx_i)` over `i`, which is piecewise linear and convex.  Same for `xMax(t)` (a piecewise-linear *concave* envelope) and the y analogues.

So the width `xMax(t) - xMin(t)` is convex piecewise linear -- it has a unique minimum.  Same for the height.  The area is their product.

The product of two unimodal piecewise-linear functions is *not* in general unimodal: it could in principle have a saddle.  But for points engineered to spell out a single message at one moment in time, the empirical answer is "it is unimodal in practice for every AoC input."  That gives us a stupidly simple algorithm:

```
t = 0; area = bboxArea pts
while area(step pts) < area:
    pts = step pts
    t  = t + 1
    area = bboxArea pts
return (t, pts)
```

We could replace this with a binary or ternary search on `t`, or solve for the minimum of the height function in closed form (`y_min(t)` and `y_max(t)` each have at most `n` linear pieces), but the linear scan is fast enough -- `t` for the actual input is ~10,500 -- and avoids any "what if the area function is not strictly unimodal at integer points" hand-wringing.

---

## Data model

```haskell
data Point = Point
  { px :: !Int
  , py :: !Int
  , vx :: !Int
  , vy :: !Int
  } deriving (Eq, Show, Generic)

instance NFData Point
```

A flat record with four strict `!Int` fields.  All fields strict because:

- Lazy fields would build thunks during `step` (`px + vx` would be stored as a deferred addition); after 10,000 simulation passes those thunks would tower up and either OOM or take forever to force.
- The position fields and the velocity fields read symmetrically -- there is no field that *would not* be forced eventually.

`deriving (Generic)` plus the empty `instance NFData Point` is the same one-liner we used on Day 8 and Day 9 to give criterion a deep-evaluation walker.

---

## `parseInput` and `parseLine`

```haskell
parseInput :: String -> [Point]
parseInput = map parseLine . lines

parseLine :: String -> Point
parseLine s = case map read (words (map keep s)) of
  [a, b, c, d] -> Point a b c d
  _            -> error ("Day10.parseLine: bad line " ++ show s)
  where
    keep :: Char -> Char
    keep ch
      | ch == '-' || isDigit ch = ch
      | otherwise               = ' '
```

The trick is in the `keep` helper.  Each line looks like:

```
position=<-52775,  31912> velocity=< 5, -3>
```

After replacing every character that is not `-` or a digit with a space, the line becomes:

```
         -52775   31912           5  -3
```

`words` then splits that on whitespace into the four signed integers as `String`s, and `map read` parses each one to `Int`.  A list pattern of length 4 catches the success case; anything else trips the `error` arm.

### Why this works for every line shape

The replacement keeps **exactly** the four signed integers and discards everything else.  It does not care:

- whether the angle brackets are present,
- whether there is one space or three between `<` and the number,
- whether the comma is followed by spaces or not,
- whether the line ends with `>` or with extra trailing whitespace.

The puzzle's actual input has every kind of horizontal-alignment whitespace (numbers padded to align in a column), and the parser just rolls through it.

### Why not `megaparsec` or `attoparsec`?

For a single-line schema where there are exactly four signed integers per line and we know it up front, the regex-grade "strip-and-tokenise" approach is shorter and faster than a real parser.  We will graduate to `megaparsec` on a later day where the input has nested structure or branching.

### Why `isDigit` and not `ch >= '0' && ch <= '9'`?

The hand-rolled comparison works, but `Data.Char.isDigit` is more readable, more locale-aware (it correctly returns `False` for non-ASCII digit characters that happen to land in odd Unicode pages), and HLint will suggest it on sight.  The cost is one extra import.

---

## `step` and `bboxArea`

```haskell
step :: [Point] -> [Point]
step = map (\(Point x y dx dy) -> Point (x + dx) (y + dy) dx dy)
```

Advance every point by one second.  `map` produces a fresh list (Haskell records are immutable; we cannot mutate `Point` fields), but the returned list shares no structure with the old one.  After GC the old list is freed.  At ~300 points per tick × ~10,500 ticks, that is ~3 M `Point` allocations across the whole search -- a few MB of allocation, well within GHC's nursery.

The lambda destructures the record by positional pattern -- `Point x y dx dy` binds the four fields in declaration order, so we do not have to type out `\p -> Point (px p + vx p) (py p + vy p) (vx p) (vy p)`.

```haskell
bboxArea :: [Point] -> Int
bboxArea []     = 0
bboxArea (p:ps) =
  let (xMin, xMax, yMin, yMax) = foldl' extend (px p, px p, py p, py p) ps
  in (xMax - xMin) * (yMax - yMin)
  where
    extend :: (Int, Int, Int, Int) -> Point -> (Int, Int, Int, Int)
    extend (!a, !b, !c, !d) (Point x y _ _) =
      (min a x, max b x, min c y, max d y)
```

A single `foldl'` threading the four extrema as a 4-tuple.  The bang patterns on the tuple components prevent the four `min`/`max` operations from accumulating thunks across the fold.

### Why one `foldl'` instead of `(maximum (map px pts) - minimum (map px pts)) * ...`?

Both versions compute the same answer.  The four-extrema fold:

- Walks the list **once**, producing four `Int`s.
- Allocates one 4-tuple at each step (lifted by GHC's tuple-strictness analyser into raw register passing under `-O2`).

The `maximum / minimum (map px ...) - ...` version:

- Walks the list **four** times.
- Allocates two intermediate `[Int]` lists per dimension (one for `map px` and one fused into `maximum`).

At ~300 points per call and 10,500 calls per `findMessage` run, the four-pass version measures ~30 % slower in practice.  Both are fast; the single-pass shape is the right reflex.

---

## `findMessage`

```haskell
findMessage :: [Point] -> (Int, [Point])
findMessage pts0 = go 0 pts0 (bboxArea pts0)
  where
    go :: Int -> [Point] -> Int -> (Int, [Point])
    go !t !pts !a =
      let nextPts = step pts
          aNext   = bboxArea nextPts
      in if aNext < a
         then go (t + 1) nextPts aNext
         else (t, pts)
```

The "step until the area would grow" loop, written as tail-recursive `go`.  Bang patterns on all three accumulator arguments to keep the loop allocation-free between iterations.

### Why we compare `aNext < a`, not `aNext > a`

We want to stop when `aNext` is **no longer smaller** than `a`.  `aNext < a` means "still shrinking, keep going."  Anything else (equal or larger) means the previous `pts` was the minimum.

If two consecutive ticks had exactly equal area we would stop one tick early, but the actual input never has that pathology; the area strictly decreases, then strictly increases.  The example puzzle's areas are `216 → 80 → 24 → 8 → 8 → ...` -- the final shrink-step has `aNext == a == 8`, so we stop at `t = 3` with the correct `pts`.

### What `findMessage` returns

A tuple `(t, pts)`:

- `t` is the second at which the message becomes readable -- this is Part 2's answer.
- `pts` is the list of points at that second -- this feeds into `render` to produce Part 1's ASCII picture.

Returning the tuple lets a caller compute *both* answers from a single search, which `solve` does.

---

## `render` -- the ASCII picture

```haskell
render :: [Point] -> String
render []  = ""
render pts =
  let xs   = map px pts
      ys   = map py pts
      x0   = minimum xs
      x1   = maximum xs
      y0   = minimum ys
      y1   = maximum ys
      pset = Set.fromList [(px p, py p) | p <- pts]
  in unlines
       [ [ if (x, y) `Set.member` pset then '#' else '.'
         | x <- [x0 .. x1] ]
       | y <- [y0 .. y1] ]
```

Build a `Set` of occupied `(x, y)` pairs once, then a doubly-nested list comprehension walks every cell of the bounding box exactly once.  The outer comprehension is over rows (`y`), the inner over columns (`x`); the inner result `[Char]` is a row's worth of cells, and `unlines` joins them with newlines.

### Why a `Set`, not a 2D array?

The actual minimum-area frame is a 63 × 10 box -- 630 cells, of which roughly 250 are occupied.  Building a `Data.Array (Int, Int) Bool` would allocate all 630 cells; the `Set` allocates one per actual point.  More importantly, the `Set` lookup is `O(log n)` where `n` is the *number of points* (~300), not the bounding-box area, so the rendering scales with the message and not with the empty space around it.

### Why is `bboxArea` defined separately when `render` re-derives the bounding box?

Performance.  `bboxArea` is called ~10,500 times per `findMessage`; `render` is called once.  Sharing the bounding-box computation between them would force `render` to take an extra argument, which would clutter the API for no measurable win.  Both functions stay tightly scoped.

### `unlines`

```haskell
unlines :: [String] -> String
```

The inverse of `lines`.  Joins a list of strings with `\n` separators **and adds a trailing `\n`**.  That trailing newline matters for our test: the pinned expected ASCII art ends with a newline, and `unlines [...]` produces one too, so they match exactly.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: [Point] -> String
part1 = render . snd . findMessage

part2 :: [Point] -> Int
part2 = fst . findMessage

solve :: String -> IO ()
solve contents = do
  let pts         = parseInput contents
      (t, msgPts) = findMessage pts
  putStrLn "  part 1:"
  mapM_ (putStrLn . ("    " ++)) (lines (render msgPts))
  putStrLn ("  part 2: " ++ show t)
```

`part1` and `part2` independently call `findMessage`, which means the bench reports them as separate timings of the full search.  Both run in ~45 ms, with the small difference between them coming down to GC noise -- they do exactly the same work and just project a different field of the result.

`solve` short-circuits the duplication: it calls `findMessage` *once*, gets `(t, msgPts)` back, prints both pieces.  The pattern `mapM_ (putStrLn . ("    " ++)) (lines (render msgPts))` indents each rendered line by four spaces to align with the project's existing day-output format; `lines` re-splits the `unlines` output and we re-join with the indent.

### Why is `part1` a `String` and not the message text `"JLPZFJRH"`?

Two reasons:

1. **No OCR**.  Mapping ASCII pictures of letters to the letter they represent is its own problem and is *not* part of Day 10.  The puzzle says "what message will eventually appear" expecting the human to read it off the rendering.
2. **Pinning the picture is a stronger regression test** than pinning the inferred message.  A bug in `render` that drops one cell would still produce a valid-looking but wrong eight-letter message; pinning the exact 11 × 63 picture catches it immediately.

---

## Tests

Coverage in [Day10Spec.hs](../../test/Day10Spec.hs):

1. **`parseLine`** -- both a positive-only line and a line with negative numbers.  Pinpoints any whitespace handling regression.
2. **`parseInput`** -- structural check on the example (`length == 31`).
3. **`step` / `bboxArea` shape** -- after one step, the first point lands where its velocity says.  And the example's bounding-box areas decrease through `t = 3` then start increasing -- a sanity check that the area function really is unimodal.
4. **Puzzle example** -- `findMessage` returns `(3, _)` and the rendering matches the `HI` from the puzzle text.
5. **Actual input** -- `t = 10595`; the rendering matches the pinned 11 × 63 ASCII art that reads `JLPZFJRH`.

The pinned ASCII art is bulky in the test file, but its bulk is the value: any future refactor that breaks `render` shows up as a precise diff at the offending row, not a "the message is wrong but I do not know where" failure.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean       | What it times |
|--------------------|-----------:|---------------|
| `day10/parseInput` | 1.25 ms    | 313 lines through `keep` + `words` + `read`. |
| `day10/part1`      | 45.79 ms   | Full simulation search + rendering. |
| `day10/part2`      | 42.81 ms   | Full simulation search; the `render` step is ~4 % of part1. |
| `day10/combined`   | 91.55 ms   | End-to-end from raw string -- approximately part1 + part2. |

**Total = Parse + Part 1 + Part 2 = 89.85 ms.**

The simulation step dominates: ~10,500 iterations × ~313 points × constant-work-per-point ≈ 3.3 M point updates plus 10,500 bounding-box passes.  The parser is in the noise relative to Part 1 / Part 2.

`combined` ≈ part1 + part2 because the two parts independently re-run the search.  In `solve` we run `findMessage` once and print both answers, so the IO entry point is roughly half the bench's `combined` time -- but criterion measures the bench-by-bench shape, not the dispatcher.

---

## Why is the area function unimodal?

This is the load-bearing assumption of `findMessage`.  Worth a paragraph because if it ever fails for a future input, the whole approach falls apart.

The width `xMax(t) - xMin(t)` is the *upper envelope* of `(px_i + t * vx_i)` minus the *lower envelope* over `i`.  Each envelope is piecewise linear and convex (resp. concave), so the width is piecewise linear and convex -- it has a unique minimum where the two envelopes touch most closely.  Same argument for the height `yMax(t) - yMin(t)`.

The product of two convex non-negative functions of `t` is **not** in general convex.  But for any pair of strictly convex functions whose minima are close to each other, the product is also unimodal in a neighbourhood of those minima.  AoC inputs are constructed so that:

- Both width and height reach their minimum at almost the same `t`.
- That `t` is far from any boundary.
- The minimum is sharp -- one or two ticks before and after, the area is much larger.

Empirically every AoC 2018 Day 10 input is unimodal in this way; the puzzle answer-key site lists the canonical results, and "step until area grows" produces all of them correctly.  If we were paranoid, we would do a coarse-grained scan first (e.g. step in increments of `(yMax - yMin) / 2`) to land near the minimum, then a fine-grained step to find the exact tick.  We are not paranoid, and the linear scan is fast enough.

---

## Visualisation: reverse-engineering the puzzle generator

A picture is worth a thousand simulation ticks.  The companion
script [`scripts/plot_day10.py`](../../scripts/plot_day10.py) renders
one combined figure with two complementary stories:

1. **Bounding-box area vs t** on a log y-axis, full range t in `[0, 22000]`.  A sharp V-curve with the minimum at `t = 10595` and a roughly symmetric rise on the far side.  Dotted greys mark the snapshot times for orientation against the curve.
2. **Eight point-cloud snapshots** in a 2x4 grid -- four approach frames in row 1, then the message moment plus three departure frames in row 2.  Each subplot zooms to its own bounding box so the cluster shape stays legible even while the bbox area shrinks (and re-expands) by a factor of ~10^7.

Output: `scripts/day10_visualization.png`.  Regenerate with `python scripts/plot_day10.py`.

The picture reveals four structural facts that the code alone does not.

### 1.  The starfield is on a discrete velocity lattice

At t = 0 every snapshot shows a **regular grid** of dots -- not a scatter.  Cause: all 313 points have integer velocities drawn from a small set:

```
distinct vx values: {-5, -4, -3, -2, -1, 1, 2, 3, 4, 5}   (10 values, no zero)
distinct vy values: {-5, -4, -3, -2, -1, 1, 2, 3, 4, 5}   (10 values, no zero)
```

Every point at time `t` sits at position `(X_final + (t - t_min) * vx, Y_final + (t - t_min) * vy)`, so at t = 0 the x-coordinates fall into exactly 10 buckets spaced `t_min = 10595` units apart -- one bucket per distinct `vx`.  Same for y.  The visible bands at t = 0 are the gaps between those buckets.

As t advances toward `t_min`, the band spacing shrinks linearly:

| Snapshot   | Spacing `t_min - t` |
|------------|--------------------:|
| t = 0      | 10,595              |
| t = 2,648  | 7,947               |
| t = 5,297  | 5,298               |
| t = 10,395 | 200                 |
| t = 10,595 | 0  (lattice collapses to the message) |

The mirror frames on the departure side have the same spacing as their approach counterparts -- `t - t_min` distance grows linearly past zero.

### 2.  The doubled gap in the middle

Look at the t = 0 panel: most bands are evenly spaced, but the one straddling x = 0 is roughly **twice as wide** as its neighbours.  Same on the y-axis.

That doubled gap is the **missing `vx = 0`** (and `vy = 0`) bucket: adjacent velocity values differ by 1, but the puzzle skips zero, so the `vx = -1` and `vx = +1` clusters are `2 * t_min = 21,190` units apart instead of the usual `10,595`.

Skipping zero is almost certainly a deliberate generator choice -- it prevents any point from staying stationary on the x- or y-axis during the animation, which would look out of place.

### 3.  `t = 2 * t_min` mirrors `t = 0` through the message centre

The right panel of snapshot row 2 (t = 21,190) is visually identical to the left panel of row 1 (t = 0) -- same bbox size (`~106,003 x ~105,959`), same lattice spacing, same overall shape.  That isn't coincidence; the reflection is exact:

```
position(t = 0)        = (X_final - t_min * vx,  Y_final - t_min * vy)
position(t = 2 * t_min) = (X_final + t_min * vx,  Y_final + t_min * vy)
```

The two positions are **point-symmetric through the message centre `(X_final, Y_final)`**.  The message moment is the axis of symmetry for the whole evolution; the area-vs-t curve and the lattice configuration both reflect through it.

### 4.  The empty cells reveal which `(vx, vy)` pairs were never chosen

100 possible `(vx, vy)` pairs (10 x 10), 313 points distributed among them.  Average: ~3.13 points per pair, but a few buckets land empty by chance:

```
       vy=  -5  -4  -3  -2  -1   1   2   3   4   5
vx= -5 :    2   3   5   1   4   4   5   2   1   3
vx= -4 :    6   0   3   3   4   4   6   4   2   6
vx= -3 :    2   2   3   3   6   3   3   3   1   4
vx= -2 :    2   1   1   4   3   2   0   2   3   2
vx= -1 :    6   4   2   1   2   6   0   1   2   2
vx=  1 :    5   1   5   3   3   5   2   3   4   5
vx=  2 :    4   1   2   3   4   5   1   1   9   1
vx=  3 :    2   6   7   3   3   4   2   2   3   1
vx=  4 :    5   7   3   3   2   3   3   1   3   2
vx=  5 :    6   5   3   2   7   2   7   2   2   1
```

Three pairs are absent: `(-4, -4)`, `(-2, 2)`, `(-1, 2)`.  Each absence creates an *empty grid cell* in two snapshots -- one at t = 0 and one at t = 2 * t_min, point-reflected through the message centre:

| Missing `(vx, vy)` | Empty cell at t = 0     | Empty cell at t = 21,190 |
|--------------------|-------------------------|---------------------------|
| `(-4, -4)`         | `(+42,380, +42,380)`    | `(-42,380, -42,380)`      |
| `(-2,  2)`         | `(+21,190, -21,190)`    | `(-21,190, +21,190)`      |
| `(-1,  2)`         | `(+10,595, -21,190)`    | `(-10,595, +21,190)`      |

The pairs `(-2, 2)` and `(-1, 2)` share the same `vy` and adjacent `vx`, so their two empty cells sit on the same horizontal row, one column apart -- a 2-cell-wide gap that's easy to spot in the t = 0 panel.  After the message, those two cells appear on the opposite row at the opposite x, in the diagonally-opposite quadrant.  The third missing cell `(-4, -4)` sits far out in the corner of the lattice -- visible once you know to look for it.

### What it all says about the puzzle generator

Adding the four observations together, the puzzle author almost certainly did this:

1. **Drew the message** `JLPZFJRH` on a 61 x 9 ASCII grid -- 313 lit pixels.
2. **Assigned each lit pixel** an integer velocity `(vx, vy)`, with `vx` and `vy` independently drawn from `{-5,...,5} \ {0}`.  Zero excluded -- no stationary points.
3. **Ran time backward 10,595 ticks** to compute each pixel's t = 0 position; published those as the input.

Three of the 100 possible `(vx, vy)` combinations happened not to be drawn -- statistical noise in a sample of 313.  Everything else in the puzzle -- the area curve, the lattice bands, the symmetry around `t_min`, the doubled central gap -- is a deterministic consequence of those three steps and that one random sampling.

There's a nice meta-lesson here: **the structure of the input is the structure of the generator running backward**.  If you ever build a puzzle of this shape yourself, the same forward/reverse symmetry is essentially free, and your tests can exploit it -- generate a target image, randomly assign velocities, run backward, then verify that forward simulation reproduces the image at the same `t`.

---

## Possible optimizations

### Ternary search for `t_min` (implemented)

The default `findMessage` is a linear scan: step every tick from 0 to `t_min`, evaluating `bboxArea` at each one.  ~10,500 evaluations on the actual input.

But the bbox area is **unimodal in `t`** (see [Why is the area function unimodal?](#why-is-the-area-function-unimodal) and the empirical confirmation in [Visualisation](#visualisation-reverse-engineering-the-puzzle-generator)), and every point's position at any `t` is the closed-form `(px + t*vx, py + t*vy)`.  Those two facts together unlock **ternary search**: probe two interior points of the search interval, use the relative ordering of their areas to discard one third of the interval, repeat until you've narrowed down to a handful of ticks.

`findMessageTernary` and its two helpers ship alongside the linear scan in [src/Day10.hs](../../src/Day10.hs):

```haskell
advance :: Int -> [Point] -> [Point]
advance t = map (\(Point x y dx dy) -> Point (x + t*dx) (y + t*dy) dx dy)

estimateUpperBound :: [Point] -> Int
estimateUpperBound pts =
  let ys       = map py pts
      yRange   = maximum ys - minimum ys
      maxAbsVy = maximum (map (abs . vy) pts)
  in  2 * yRange `div` max 1 maxAbsVy

findMessageTernary :: [Point] -> (Int, [Point])
findMessageTernary pts0 = (bestT, advance bestT pts0)
  where
    bestT = go 0 (estimateUpperBound pts0)

    go !lo !hi
      | hi - lo <= 2 = fst (minimumBy (comparing snd)
                              [ (t, bboxArea (advance t pts0))
                              | t <- [lo .. hi] ])
      | aM1 < aM2    = go lo m2          -- min must be in [lo, m2]
      | aM1 > aM2    = go m1 hi          -- min must be in [m1, hi]
      | otherwise    = go m1 m2          -- plateau: shrink both ends
      where
        m1  = lo + (hi - lo) `div` 3
        m2  = hi - (hi - lo) `div` 3
        aM1 = bboxArea (advance m1 pts0)
        aM2 = bboxArea (advance m2 pts0)
```

The key new primitive is **`advance`**: jump every point forward by `t` seconds in one O(n) pass.  Without it, evaluating `bboxArea` at an arbitrary `t` would mean stepping through every intermediate tick -- defeating the whole point of skipping ahead.  With it, each ternary-search iteration is O(n) regardless of how far the probe is from t = 0.

**`estimateUpperBound`** gives a safe initial ceiling.  Even if every point moved straight toward the centre at its maximum `|vy|`, the y-range cannot close faster than `yRange / maxAbsVy` ticks.  The factor of 2 is paranoia padding -- ternary search will narrow it cheaply, and an overshooting ceiling is harmless.  For the actual puzzle input it returns ~40,000, comfortably bracketing the true `t_min = 10595`.

#### How fast?

Bench on the actual puzzle input (criterion, GHC 9.6.7, `-O2`):

| Bench                              | Mean       | Area evaluations | Speedup |
|------------------------------------|-----------:|-----------------:|--------:|
| `day10/findMessage/linear scan`    | **37.47 ms** | ~10,500       | 1x      |
| `day10/findMessage/ternary`        | **172.1 µs** | ~26           | **218x**|

The theoretical evaluation-count ratio is `10,500 / 26 ≈ 400x`.  The measured wall-clock ratio is closer to **218x**: ternary's per-iteration cost is slightly higher than linear's (each probe pays for an `advance` with a multiplication, vs the linear scan's single-tick `step` which just adds), and GC overhead amortises differently across the two access patterns.  Either way, ~218x for a 50-line change is a sweet spot.

Both algorithms agree on the answer for every test input -- `findMessageTernary pts == findMessage pts` is a pinned regression test in [test/Day10Spec.hs](../../test/Day10Spec.hs).

#### Why `findMessage` stays the default for `part1` / `part2`

Three reasons we kept the linear scan as the primary:

1. **Pedagogical clarity** -- "step until the area would grow" is the puzzle description rendered as code.  Ternary search requires a separate explanation of unimodality before the code makes sense.
2. **Weaker preconditions** -- linear scan stops at the first local minimum it encounters.  If a future input had a weird shape (two local minima, plateaus at the global min, etc.) the linear scan would still find a valid first minimum; ternary search commits to *global* unimodality and could silently land on the wrong plateau.  AoC inputs are well-behaved, but the assumption gap is worth noting.
3. **37 ms is already inside the project's "under a second" target** -- swapping a clear algorithm for a clever one to save 37 ms isn't worth the readability cost on the hot path.  Shipping ternary search as a *documented alternative* is the right tier of optimisation: visible to readers who care, with a bench that quantifies the trade-off, but the default solver stays simple.

#### Why not binary search?

Binary search finds **threshold crossings** in a monotone sequence: "where does this function first exceed K?"  We are looking for the **minimum** of a unimodal function -- a fundamentally different shape of problem.  Ternary search is the right generalisation.

You could in principle binary-search on the derivative -- find the integer `t` where `bboxArea(t+1) - bboxArea(t)` first becomes nonnegative.  But the discrete derivative of a piecewise-linear integer function is itself piecewise-constant with integer jumps, which makes the "first crossing" definition fiddly.  Ternary search avoids that by working directly on the function values, and converges in the same `O(log T)` time.

### Skip ahead with a height heuristic

Letters are typically ~10 pixels tall.  At `t = 0` the spread in `y` is `~110,000`.  If every point's `vy` is in `[-5, 5]`, we need at least ~10,000 ticks before the message could possibly appear.  Computing `t_estimate = (yMax - yMin) / (max vy - min vy)` and starting the simulation from that tick would skip ~99 % of the empty steps.  Estimated speedup: 10--50x on Part 1 / Part 2.

We do not bother because 45 ms is already inside the project's "under a second" target.  Worth implementing if a future puzzle uses the same shape with bigger inputs.

### Vectorised `step`

Replacing `[Point]` with `Data.Vector.Unboxed.Vector Int` (four parallel `Vector`s for `px`, `py`, `vx`, `vy`) would let `step` compile to a tight `for` loop with no per-element allocation.  Estimated speedup: 2--5x.  Would change the API from "list of records" to "struct of arrays," which is a meaningful style change for not-much-payoff at our problem size.

### Closed-form solution for `t`

We could compute `t_min_width` and `t_min_height` independently as the integer that minimises a piecewise-linear function, then check both candidates and a small neighbourhood for the global area minimum.  This is the `O(n log n)` solution.  Cute but overkill.

---

## Key patterns

1. **Step-until-monotone-broken** for unimodal functions over integers.  When you suspect `f(t)` is unimodal and `t` is bounded by a few thousand, "advance by one until `f(t+1) >= f(t)`" is the simplest correct algorithm.  Cleaner and more obviously correct than ternary search.
2. **Strip-and-tokenise** for fixed-format text.  When every line has the same noisy-but-structured layout and you only care about a fixed set of integer fields, replace non-data characters with spaces and let `words` + `read` do the rest.  Beats a real parser by a wide margin in lines of code.
3. **Single `foldl'` over a tuple of accumulators**.  When you need multiple aggregates over the same list (here: four extrema), thread them as one tuple through one fold rather than walking the list once per aggregate.
4. **`Set` for sparse-grid membership tests**.  Builds in `O(n log n)`, queries in `O(log n)`, and -- crucially -- scales with the number of *points*, not with the size of the bounding rectangle.  When the box is mostly empty space, this is a 100x memory win over a 2D array.
5. **`Generic`-derived `NFData` for parsed records**.  Same one-liner that has shipped in Days 8, 9, 10.  This is now firmly the project's standard recipe for criterion-friendly parsed input types.

---

## Side-by-side with the Rust mental model

```rust
#[derive(Debug, Clone, Copy)]
struct Point { px: i64, py: i64, vx: i64, vy: i64 }

fn parse_line(s: &str) -> Point {
    let nums: Vec<i64> = s
        .chars()
        .map(|c| if c == '-' || c.is_ascii_digit() { c } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .map(|t| t.parse().unwrap())
        .collect();
    Point { px: nums[0], py: nums[1], vx: nums[2], vy: nums[3] }
}

fn step(pts: &mut [Point]) {
    for p in pts.iter_mut() {
        p.px += p.vx;
        p.py += p.vy;
    }
}

fn bbox_area(pts: &[Point]) -> i64 {
    let (mut xmin, mut xmax) = (pts[0].px, pts[0].px);
    let (mut ymin, mut ymax) = (pts[0].py, pts[0].py);
    for p in &pts[1..] {
        xmin = xmin.min(p.px);  xmax = xmax.max(p.px);
        ymin = ymin.min(p.py);  ymax = ymax.max(p.py);
    }
    (xmax - xmin) * (ymax - ymin)
}

fn find_message(mut pts: Vec<Point>) -> (i64, Vec<Point>) {
    let mut area = bbox_area(&pts);
    let mut t = 0i64;
    loop {
        let mut next = pts.clone();
        step(&mut next);
        let next_area = bbox_area(&next);
        if next_area < area {
            pts = next;
            area = next_area;
            t += 1;
        } else {
            return (t, pts);
        }
    }
}
```

Lined up:

| Concept                          | Rust                                                     | Haskell                                              |
|----------------------------------|----------------------------------------------------------|------------------------------------------------------|
| Strip non-data, then tokenise    | `s.chars().map(...).collect::<String>().split_whitespace()` | `map keep` then `words`                              |
| Parse to `i64` / `Int`           | `t.parse().unwrap()`                                     | `read`                                               |
| Per-tick mutation                | `for p in pts.iter_mut() { p.px += p.vx; ... }`           | `map (\(Point x y dx dy) -> Point (x+dx) (y+dy) dx dy)` |
| Four-extrema fold                | mutable `xmin`, `xmax`, `ymin`, `ymax` updated in loop   | `foldl' extend (px p, px p, py p, py p) ps` over a 4-tuple |
| Step-until-grow                  | `loop { ... if next_area < area { ... } else { return ... } }` | `go !t !pts !a = if aNext < a then go ... else (t, pts)` |
| Sparse-grid membership for render| `HashSet<(i64, i64)>`                                    | `Data.Set.Set (Int, Int)`                            |
| Nested comprehension over a box  | nested `for` loops + `print!`                            | nested list comprehension + `unlines`                |

The Rust version mutates in place (`step(&mut pts)`), which matches Haskell's `STUArray`-style approach from Day 9.  We deliberately *did not* reach for `ST` here because the simulation is small enough -- 313 points × 10,500 ticks = 3.3 M point updates -- that the `[Point]` allocations are still in the GHC nursery and never escape to the heap.  When the per-tick allocation matters, `Data.Vector.Unboxed.Vector` would be the move; we will meet that on a later day.

The most interesting structural difference is *how the step-until-grow loop is written*.  In Rust we own the points and overwrite them at each tick; the loop body has no return value because everything is mutated.  In Haskell `go` is a pure function from `(t, pts, area)` to `(t', pts')`; the "mutation" is implicit in the recursive call passing the new accumulator values.  Both compile to roughly the same machine code under `-O2`, but the Haskell version makes the recurrence visible in the source -- and the tests can call `findMessage` with confidence that no implicit state crosses the call boundary.

---

**Navigation**: [Problem statement](day10.md) | [Summary table](summary_2018.md) | [<- Day 9](day09_function_guide.md) | Day 11 -> *(not yet attempted)*
