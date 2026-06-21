# Day 23: Experimental Emergency Teleportation -- Function Guide

**Problem**: A swarm of *nanobots*, each with an integer position
`(x,y,z)` and a *signal radius* `r`. A bot is *in range* of any integer
point within Manhattan distance `r`. Part 1: find the strongest bot
(largest radius) and count how many bots lie in its range. Part 2: find
the integer point in range of the *most* bots; among ties, the one
closest to the origin; report that Manhattan distance.

**Answers**: Part 1 = **433**, Part 2 = **107272899**
**Code**: [Day23.hs](../../src/Day23.hs) · **Python reference**: [day23.py](../../python/day23.py)
**Runtime**: Parse 4.30 ms · Part 1 9.94 µs · Part 2 12.78 ms · Total ≈ 17.1 ms

**New concepts this day**:

- **Manhattan (taxicab) balls in 3-D.** A bot's coverage is the set
  `|x-px| + |y-py| + |z-pz| <= r` — an octahedron, the L¹ analogue of
  a sphere. The whole puzzle is reasoning about these balls; we never
  enumerate the points inside one.
- **Branch and bound over an octree.** Part 2's search space is a
  ~10⁸-wide cube of integer points — unscannable. Instead we bound a
  cube, compute an *upper bound* on how many bots any point inside it
  could see, and recursively split the most promising cube into 8
  octants. The first 1×1×1 cube to surface is provably optimal. This
  is the same idea as alpha-beta pruning in a chess engine: keep a
  bound, expand the most promising branch, prune the rest.
- **An admissible bound that is monotone under refinement.** The cube's
  bot-count can only *shrink* as the cube shrinks, and its distance to
  the origin can only *grow*. Those two monotonicities are exactly what
  make the best-first search correct — the same role an admissible,
  consistent heuristic plays in A\*.
- **`Data.Set` as a priority queue, take two.** Day 22 used it for
  Dijkstra; here the search key is a 4-tuple whose lexicographic `Ord`
  encodes the entire policy: most bots, then closest to origin, then
  smallest cube.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Why the branch and bound is correct](#why-the-branch-and-bound-is-correct)
- [Data model](#data-model)
- [`parseInput`](#parseinput)
- [`part1`](#part1)
- [`part2` — branch and bound over an octree](#part2--branch-and-bound-over-an-octree)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

The input is 1000 lines, each one bot:

```
pos=<59777541,48321754,69013496>, r=69839895
```

Coordinates can be negative and are up to ~10⁸ in magnitude.

**Part 1** is a warm-up: pick the bot with the largest `r`, then count
how many of the 1000 bots (including itself) have their *position*
within Manhattan distance `r` of that bot. A single linear scan.

**Part 2** is the hard one, and it is easy to misread. You are *not*
looking for a bot — you are looking for a *point in space* (any integer
coordinate, not necessarily where a bot sits) that is inside the most
bots' ranges simultaneously. The worked example:

```
pos=<10,12,12>, r=2
pos=<12,14,12>, r=2
pos=<16,12,12>, r=4
pos=<14,14,14>, r=6
pos=<50,50,50>, r=200
pos=<10,10,10>, r=5
```

The point `(12,12,12)` is in range of the first five bots (the most
any point achieves here) and lies 36 from the origin, so the answer is
**36**. Note `(12,12,12)` is not any bot's position — it is a sweet
spot where five octahedra overlap.

The difficulty is scale. The bots span a cube roughly 2×10⁸ on a side,
so there are ~10²⁴ integer points. You cannot scan them, and you cannot
even build a coarse grid fine enough to be sure you hit the optimum. We
need a search that *prunes* almost all of space without looking at it.

---

## The algorithm in Python

The full reference is [day23.py](../../python/day23.py). Part 1 is a
one-liner; the interesting code is Part 2's octree search.

Part 1:

```python
def part1(bots):
    pos, r = max(bots, key=lambda b: b[1])      # strongest = largest radius
    return sum(1 for p, _ in bots if manhattan(pos, p) <= r)
```

Part 2 rests on two distance helpers. The first is the key to the whole
algorithm — the closest a point can be to *any* cell of a cube:

```python
def dist_point_box(p, lo, size):
    """Manhattan distance from p to the nearest cell of [lo .. lo+size-1]^3."""
    total = 0
    for v, l in zip(p, lo):
        h = l + size - 1
        if v < l:   total += l - v          # p is left of the box on this axis
        elif v > h: total += v - h          # p is right of the box
        # else p is inside the box's span on this axis -> 0
    return total
```

If `dist_point_box(botpos, lo, size) <= r`, the bot's range *touches*
the cube, so it could cover some point inside it. Counting such bots
gives an upper bound on coverage for the whole cube. The second helper
is the same idea against the origin (for the tiebreak), and the search
itself is a best-first loop:

```python
def part2(bots):
    # one power-of-two cube covering all bot positions
    lo = (min xs, min ys, min zs);  size = smallest power of two > extent

    def count(lo, size):
        return sum(1 for p, r in bots if dist_point_box(p, lo, size) <= r)

    heap = [(-count(lo, size), dist_box_origin(lo, size), size, lo)]
    while heap:
        neg_c, d, size, lo = heapq.heappop(heap)
        if size == 1:
            return d                         # first 1x1x1 popped is optimal
        h = size // 2
        for dx in (0, h):
            for dy in (0, h):
                for dz in (0, h):
                    nlo = (lo[0]+dx, lo[1]+dy, lo[2]+dz)
                    heapq.heappush(heap, (-count(nlo, h), dist_box_origin(nlo, h), h, nlo))
```

The heap key `(-count, dist_to_origin, size, lo)` is the entire policy.
Python pops the smallest tuple, so negating the count makes "most bots"
come first; ties break toward the origin, then toward smaller cubes.
The Haskell version is a structural mirror of this, with `Data.Set`
standing in for `heapq`.

---

## Why the branch and bound is correct

This is the part worth slowing down on, because it is easy to write a
plausible search that returns a slightly-wrong answer. There is a
popular shortcut for this puzzle — project each bot onto a 1-D axis of
"distance to origin" as an interval `[d-r, d+r]`, then find the point of
maximum interval overlap. It happens to give the right number on many
inputs, but it is **not sound**: two intervals overlapping on that axis
does not guarantee a common 3-D point. We use the octree instead, which
*is* sound. Here is the argument.

**The bound is admissible (never an underestimate).** For a cube `C`,
`count(C)` is the number of bots whose range intersects `C`. Any single
point `q ∈ C` is in range of bot `b` only if `b`'s range intersects `C`
(it contains `q`). So `coverage(q) ≤ count(C)` for every `q ∈ C` — the
cube's count is an upper bound on what any point inside can achieve.
For a 1×1×1 cube, the cube *is* the point, so the bound is exact.

**The bound is monotone under refinement.** When we split `C` into
octants, each child `C'` is a subset of `C`. Any bot whose range
intersects `C'` also intersects `C`, so `count(C') ≤ count(C)`. Coverage
bounds only shrink as we drill down — they never rebound.

**Origin distance is monotone the other way.** The nearest point of a
child cube to the origin is no closer than the nearest point of its
parent (a subset cannot get closer to a fixed point). So `dist_to_origin`
only grows as cubes shrink.

Put those together with a best-first queue ordered by
`(count desc, dist asc)`:

- When a 1×1×1 cube `q` reaches the front, its key `(C₀, D₀)` is the
  smallest in the queue, i.e. `q` has the **largest count** of anything
  remaining. Every other cube has `count ≤ C₀`, and splitting only
  lowers that, so no unexplored point can beat `C₀`. `q` is a
  max-coverage point.
- Among max-coverage cubes, the queue is ordered by distance, and any
  cube tying on count that is still in the queue must have
  `dist ≥ D₀` (otherwise it would have been popped first). Splitting
  only raises distance. So `q` also has the **minimum origin distance**
  among max-coverage points.

That is exactly the pair the puzzle asks for. The first 1×1×1 cube
popped is the answer — no need to drain the queue.

This is the classic **branch and bound** skeleton, and the chess-engine
analogy is exact: the cube count is an *optimistic evaluation* of a
position (branch), the priority queue is your move-ordering, and a child
whose optimistic score can't beat what you've effectively already
secured is pruned unexamined — alpha-beta with a spatial tree instead of
a game tree.

---

## Data model

```haskell
type V3 = (Int, Int, Int)

data Nanobot = Nanobot
  { botPos :: !V3
  , botR   :: !Int
  } deriving (Eq, Show)

type Puzzle = [Nanobot]
```

- `V3` is a bare `(Int, Int, Int)`. A tuple gives us lexicographic
  `Ord` and `Eq` for free and — crucially for the benchmark — a
  ready-made `NFData` instance, since `deepseq` ships instances for
  tuples up to size 7.
- `Nanobot` is a record with **strict fields** (`!`). There is no
  upside to leaving a handful of `Int`s as thunks, and Part 2 performs
  millions of distance checks against `botPos`/`botR`; strict fields
  guarantee those are bare machine integers, not deferred computations.
- `Puzzle` is just `[Nanobot]`. A list is fine — both parts traverse
  the whole swarm linearly, and 1000 elements is nothing.

```haskell
instance NFData Nanobot where
  rnf (Nanobot p r) = rnf p `seq` rnf r
```

A manual `NFData` so criterion's `nf` can force a parsed swarm to normal
form. `rnf` ("reduce to normal form") fully evaluates its argument;
`seq` forces its left operand before returning its right. We chain the
two field forces — the tuple and the `Int` already have `rnf`, so this
just sequences them. (Same hand-rolled-instance move as Days 3, 11, 22.)

The internal Part 2 type is a cube:

```haskell
data Box = Box !V3 !Int     -- minimum corner, side length (a power of two)
```

A cube of side `s` at corner `(lx,ly,lz)` covers cells `[lx .. lx+s-1]`
on each axis. Keeping `s` a power of two means halving stays integral
all the way down to `s = 1`, where a `Box` is a single point.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput = map parseLine . lines

parseLine :: String -> Nanobot
parseLine s = case ints s of
  [x, y, z, r] -> Nanobot (x, y, z) r
  _            -> error ("Day23.parseLine: cannot parse " ++ show s)

ints :: String -> [Int]
ints = map read . words . map keep
 where
  keep c
    | isDigit c || c == '-' = c
    | otherwise             = ' '
```

The line format `pos=<1,2,3>, r=4` has angle brackets, commas, equals
signs, and letters wrapped around four integers. Rather than write a
parser that knows about that punctuation, `ints` **blanks out
everything that isn't a digit or a minus sign**, turning the line into
`"   1 2 3    4"`, then lets `words` split on the spaces and `read`
parse each chunk.

New vocabulary this introduces:

- `lines :: String -> [String]` — split on `\n` (seen many times).
- `map keep` — `keep :: Char -> Char` maps each character to itself or
  to a space. Applied with `map` it rewrites the whole string.
- `isDigit :: Char -> Bool` from `Data.Char` — true for `'0'..'9'`.
- `words :: String -> [String]` — split on runs of whitespace, dropping
  empties. This is why mapping junk to spaces works: consecutive blanks
  collapse, so `"pos=<1,"` → `"    1 "` → `["1"]`.
- `read :: Read a => String -> a` — parse a `String` into (here) an
  `Int`. It handles a leading `-`, so negative coordinates survive.
  `read` panics on malformed input, which is fine for trusted puzzle
  data; in production you'd reach for `readMaybe`.

The `case ints s of [x,y,z,r] -> ...` match both destructures the
four-element list and asserts its length: anything other than exactly
four integers on a line falls through to the `error`. That is a cheap
total-ness check — a malformed line fails loudly instead of silently
dropping a coordinate.

The Manhattan helper rounds out the geometry primitives:

```haskell
manhattan :: V3 -> V3 -> Int
manhattan (x1, y1, z1) (x2, y2, z2) =
  abs (x1 - x2) + abs (y1 - y2) + abs (z1 - z2)
```

---

## `part1`

```haskell
part1 :: Puzzle -> Int
part1 bots =
  let strongest = maximumBy (comparing botR) bots
  in  botsInRangeOf (botPos strongest) (botR strongest) bots

botsInRangeOf :: V3 -> Int -> Puzzle -> Int
botsInRangeOf centre r =
  length . filter (\b -> manhattan centre (botPos b) <= r)
```

- `maximumBy :: (a -> a -> Ordering) -> [a] -> a` (from `Data.List`)
  returns the greatest element under a custom comparison.
- `comparing :: Ord b => (a -> b) -> a -> a -> Ordering` (from
  `Data.Ord`) builds that comparison from a projection. `comparing botR`
  means "compare two bots by their radius." Together,
  `maximumBy (comparing botR)` is the idiomatic "argmax by a field" —
  the Rust `iter().max_by_key(|b| b.r)`.
- `botsInRangeOf` is written point-free in its last argument:
  `length . filter (...)` is a function awaiting the list. It counts the
  bots whose position is within `r` of the chosen centre.

That is the entire puzzle for Part 1: one argmax, one filtered count.
At ~10 µs it is the cheapest part of the day; the 4.3 ms parse
dominates, exactly as on the other `read`-heavy days (8, 16).

---

## `part2` — branch and bound over an octree

Three small geometry functions, then the search. First, the admissible
bound's core — point-to-cube distance:

```haskell
distPointBox :: V3 -> Box -> Int
distPointBox (px, py, pz) (Box (lx, ly, lz) s) =
  axis px lx (lx + s - 1) + axis py ly (ly + s - 1) + axis pz lz (lz + s - 1)
 where
  axis v lo hi
    | v < lo    = lo - v        -- point is below the box on this axis
    | v > hi    = v - hi        -- point is above the box on this axis
    | otherwise = 0             -- point's coordinate lies within [lo,hi]
```

Manhattan distance separates across axes, so the nearest cell of the box
to a point is found one axis at a time: if the point's coordinate is
inside the box's span on that axis it costs 0, otherwise it costs the
gap to the nearer face. Sum the three axes. Origin distance is the same
shape with the point fixed at 0:

```haskell
distBoxOrigin :: Box -> Int
distBoxOrigin (Box (lx, ly, lz) s) = axis lx (lx + s - 1)
                                   + axis ly (ly + s - 1)
                                   + axis lz (lz + s - 1)
 where
  axis lo hi
    | lo > 0    = lo            -- whole span is positive: nearest is lo
    | hi < 0    = negate hi     -- whole span is negative: nearest is hi
    | otherwise = 0             -- span straddles 0: origin is reachable
```

The coverage bound and the octant split:

```haskell
boxBound :: Puzzle -> Box -> Int
boxBound bots box = foldl' step 0 bots
 where
  step !acc (Nanobot p r)
    | distPointBox p box <= r = acc + 1
    | otherwise               = acc

subdivide :: Box -> [Box]
subdivide (Box (lx, ly, lz) s) =
  [ Box (lx + dx, ly + dy, lz + dz) h
  | dx <- [0, h], dy <- [0, h], dz <- [0, h]
  ]
 where
  h = s `div` 2
```

- `boxBound` is a strict left fold counting bots whose range touches the
  cube. `foldl'` with a bang on the accumulator (`!acc`) keeps the
  running count a bare `Int` — without the strictness this fold would
  build a 1000-deep thunk tower per cube, the canonical Haskell space
  leak. We use an explicit fold rather than `length . filter` here
  because this runs on the hot path (once per cube created) and the
  fused fold avoids materialising an intermediate list.
- `subdivide` is a three-generator list comprehension producing the 2³ =
  8 octants. Each child has side `h = s/2` and a corner offset by 0 or
  `h` on each axis. Reads like the maths: "all corners `(dx,dy,dz)` with
  each component 0 or half."

The initial cube and the search key:

```haskell
initialBox :: Puzzle -> Box
initialBox bots = Box (mnx, mny, mnz) size
 where
  xs              = [ x | Nanobot (x, _, _) _ <- bots ]
  ys              = [ y | Nanobot (_, y, _) _ <- bots ]
  zs              = [ z | Nanobot (_, _, z) _ <- bots ]
  (mnx, mny, mnz) = (minimum xs, minimum ys, minimum zs)
  extent          = maximum [ maximum xs - mnx
                            , maximum ys - mny
                            , maximum zs - mnz ]
  size            = head (dropWhile (<= extent) (iterate (* 2) 1))

type Key = (Int, Int, Int, V3)

key :: Puzzle -> Box -> Key
key bots box@(Box lo s) =
  (negate (boxBound bots box), distBoxOrigin box, s, lo)
```

- `initialBox` lower-corners the cube at the per-axis minimum and sizes
  it to a single power of two covering the largest extent. The
  list-comprehension generators `[ x | Nanobot (x,_,_) _ <- bots ]`
  destructure each bot inline — a pattern in a comprehension's generator
  acts as both binding and (here trivially total) filter.
- `iterate (* 2) 1` is the infinite list `[1, 2, 4, 8, ...]`;
  `dropWhile (<= extent)` discards powers up to the extent; `head` takes
  the first one strictly greater, guaranteeing the cube `[mn .. mn+size-1]`
  covers `[mn .. mx]` on every axis. Laziness makes the infinite list
  free — only the prefix we inspect is ever built.
- `Key` is `(negate count, distToOrigin, size, corner)`. Haskell derives
  **lexicographic `Ord`** for tuples, so comparing two keys compares
  counts first (negated, so larger counts sort smaller → first),
  breaking ties by origin distance, then cube size, then corner. That
  derived ordering *is* the search policy — there is no comparator to
  write. The `corner` is there only to make keys unique (two different
  cubes can share count, distance, and size), so the `Set` never
  collapses two live cubes into one.

The search:

```haskell
part2 :: Puzzle -> Int
part2 bots = go (Set.singleton (key bots (initialBox bots)))
 where
  go pq = case Set.minView pq of
    Nothing -> error "Day23.part2: queue emptied without a 1x1x1 box"
    Just ((_, d, s, lo), rest)
      | s == 1    -> d
      | otherwise ->
          let children = subdivide (Box lo s)
              pq'      = foldl' (\q b -> Set.insert (key bots b) q) rest children
          in  go pq'
```

- `Data.Set` is the priority queue, exactly as in Day 22's Dijkstra.
  `Set.minView :: Set a -> Maybe (a, Set a)` pops the smallest element
  (our most-promising cube) and returns the rest, or `Nothing` if empty.
  A `Set` is a balanced tree, so `minView` and `insert` are both
  `O(log n)`.
- We **store the key, not the box.** The key carries `size` and
  `corner`, which is everything `Box` needs, so on pop we rebuild
  `Box lo s` to subdivide. This keeps each cube's expensive `boxBound`
  computed exactly once (at insert time) rather than recomputed on pop.
- The guard `s == 1` is the termination and the answer in one line: the
  first single-cell cube to surface has, by the correctness argument
  above, maximum coverage and minimum origin distance, and `d` is that
  distance. We return immediately — the rest of the queue is irrelevant.
- The `otherwise` branch splits the popped cube and folds its 8 children
  back into the queue. `foldl' (\q b -> Set.insert (key bots b) q) rest
  children` threads the growing set `q` through the children, inserting
  each child's key. (`foldl'` here is over the 8-element child list, so
  strictness is about cleanliness, not space — but it is the right
  default.)

Why is this fast — 12.8 ms, not minutes? Best-first search with an
admissible bound prunes ferociously. The queue never holds more than a
few thousand cubes: as soon as one region reveals a high coverage count,
every competing cube with a lower bound sinks to the bottom of the
`Set` and is never expanded. We explore a thin frontier down one
corridor of the octree, not the whole tree. The depth is ~28 (log₂ of a
2×10⁸ extent), and we touch on the order of 10⁴ cubes total, each a
1000-bot fold — well under a million distance checks.

### Possible optimization

Two standard upgrades, neither needed at 12.8 ms (untested
pseudo-Haskell):

1. **Carry the cube's bot subset down the tree.** Right now every cube
   re-folds all 1000 bots. But a child can only be touched by bots that
   touch its parent, so threading the surviving sublist into `subdivide`
   shrinks each fold as you descend. Near the leaves the lists are tiny.
   Costs memory per queue entry; typically a 2–4× win.

2. **`Data.IntMap`-bucketed queue or a pairing heap.** `Data.Set` of
   tuples is a fine priority queue but pays `O(log n)` with a biggish
   constant and boxes every key. A specialised heap (e.g. the
   `pqueue` package's `MinQueue`) or bucketing by count would trim the
   queue overhead. Minor next to the fold cost, so not worth the
   dependency here.

---

## Key patterns

- **Branch and bound = optimistic bound + best-first expansion +
  prune.** When the search space is astronomically large but you can
  cheaply *over*-estimate the value of a whole region, bound the region,
  expand the most promising one, and let everything worse starve in the
  queue. The skeleton is identical whether the "region" is a cube of
  space (here), a chess position (alpha-beta), or a partial assignment
  (ILP). The art is finding a bound that is both cheap and admissible.

- **Admissible + monotone is what makes best-first correct.** The bound
  must never underestimate (so you can't prune away the true optimum),
  and it should tighten monotonically under refinement (so the first
  fully-resolved item you pop is provably best). This is the same
  contract A\* asks of its heuristic; recognising it lets you reuse the
  "first goal popped is optimal" proof verbatim.

- **Put the whole policy in a tuple and let `Ord` do the work.** A
  derived lexicographic ordering on `(negate count, dist, size, corner)`
  replaces a hand-written comparator *and* a separate uniqueness key.
  Negate a field to flip its sort direction; append a discriminator to
  keep elements distinct in a `Set`.

- **Manhattan distance separates across axes.** Both the point-to-box
  and box-to-origin distances are sums of independent per-axis clamps.
  Any time you are working in an L¹ metric, look to decompose the
  problem one coordinate at a time — it turns 3-D geometry into three
  one-liners.

- **Blank-and-`read` is the fast path for integer-only input.** When a
  line is "some integers buried in punctuation," mapping every non-digit
  (keep the minus!) to a space and `words`-ing is shorter and more
  robust than a structured parser, and good enough for trusted AoC data.

---

## If I were writing this in Rust

Part 1 is `bots.iter().max_by_key(|b| b.r)` then a
`filter(...).count()` — a direct translation of the `maximumBy` /
`filter` / `length` chain.

Part 2 maps cleanly onto a `BinaryHeap<Cmp>` where `Cmp` is a struct (or
tuple) with a hand-tuned `Ord`. Rust's `BinaryHeap` is a *max*-heap, so
the sign conventions invert relative to the Haskell `Set.minView` /
Python `heapq` min-orderings: you'd order by `count` ascending-as-worst
naturally, or wrap fields in `std::cmp::Reverse` to get the "closest to
origin wins ties" behaviour. The cube is a `struct Box { lo: [i64; 3],
size: i64 }`; `dist_point_box` and `dist_box_origin` are the same
per-axis clamp loops; `subdivide` is a `for dx in [0, h]` triple loop
pushing eight children. The whole thing would run in well under a
millisecond — the 12.8 ms here is mostly `Data.Set`'s boxed-tree
overhead, which a `BinaryHeap<i64-keyed>` sidesteps. The *algorithm*,
though, is identical; nothing about the branch and bound is
language-specific.

One Rust-flavoured win that is awkward in idiomatic Haskell: carrying a
`&[usize]` slice of surviving bot indices down the recursion (optimization
#1 above) is natural with Rust's cheap slicing and would make the Rust
version pull further ahead near the leaves.

---

**Navigation**: [← Day 22](day22_function_guide.md) | [All Days](summary_2018.md) | [Day 24 →](day24_function_guide.md)
