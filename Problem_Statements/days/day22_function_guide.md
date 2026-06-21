# Day 22: Mode Maze -- Function Guide

**Problem**: The cave map is *computed*, not given: each region's
erosion level depends on the erosion levels of the regions to its
left and above, and erosion mod 3 gives the region's type (rocky /
wet / narrow). Part 1: sum the type numbers over the rectangle from
the mouth to the target. Part 2: fewest minutes from the mouth
(torch equipped) to the target (torch equipped), where a step costs
1 minute, a tool switch costs 7, and each region type forbids one of
the three tools.

**Answers**: Part 1 = **9899**, Part 2 = **1051**
**Code**: [Day22.hs](../../src/Day22.hs) · **Python reference**: [day22.py](../../python/day22.py)
**Runtime**: Parse 1.7 µs · Part 1 297 µs · Part 2 306 ms · Total ≈ 306 ms

**New concepts this day**:

- **Knot-tying memoization.** The erosion grid is a lazy boxed
  `Array` whose cells are defined *in terms of other cells of the
  same array*. Demand any cell and its dependencies compute
  themselves, each exactly once. This is dynamic programming where
  laziness does the dependency scheduling — no fill loop, no
  topological order, no mutable table.
- **Dijkstra's algorithm** (uniform-cost search), the weighted
  cousin of the BFS from Days 15 and 20. Once edges cost different
  amounts (1 vs 7 here), a FIFO queue no longer visits states in
  distance order; a priority queue restores that invariant.
- **`Data.Set` as a priority queue with lazy deletion.**
  `Set.minView` pops the smallest `(distance, state)` pair. Instead
  of the textbook decrease-key operation, we insert duplicates and
  skip any state that has already been settled — simpler, and the
  asymptotics survive.
- **A layered state graph** (a *graph product*). The search space
  is not the grid; it is grid × tool. Three copies of the cave
  stacked on top of each other, with 7-minute "elevators" between
  layers. Most hard path puzzles are exactly this trick with a
  different second dimension.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Data model](#data-model)
- [`parseInput`](#parseinput)
- [`erosionGrid` — tying the knot](#erosiongrid--tying-the-knot)
- [`part1`](#part1)
- [`part2` — Dijkstra over position × tool](#part2--dijkstra-over-position--tool)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

The whole input is two numbers:

```
depth: 7740
target: 12,763
```

Everything else is derived. Each region `(x, y)` has a **geologic
index**:

| Case | Geologic index |
|------|----------------|
| `(0,0)` (the mouth) | `0` |
| the target | `0` |
| `y == 0` | `x * 16807` |
| `x == 0` | `y * 48271` |
| otherwise | `erosion(x-1, y) * erosion(x, y-1)` |

and an **erosion level** `(geo + depth) mod 20183`. Erosion mod 3
is the region's **type**: 0 rocky, 1 wet, 2 narrow.

The last row of the table is the interesting one: a region's value
depends on the *computed* values of its left and upper neighbours.
That is a textbook dynamic-programming recurrence — the same shape
as Day 11's summed-area table, except there the combination was `+`
and here it is `*` followed by a `mod`.

### The magic numbers are a PRNG

The constants `16807`, `48271`, and `20183` aren't arbitrary, and
they aren't (all) prime:

| Number | Status | What it is |
|--------|--------|------------|
| `16807` | composite, `7⁵` | the original *minimal standard* LCG multiplier (Park & Miller, 1988) |
| `48271` | prime | the *improved* MINSTD multiplier (Park, Miller & Stockmeyer, 1993) |
| `20183` | prime | the working modulus the puzzle uses to keep values bounded |

`16807` and `48271` are the two most famous multipliers of the
**Lehmer / MINSTD pseudo-random number generator** — the linear
congruential generator `x ↦ (a · x) mod m` that shipped in decades
of C `rand()` implementations and numerical-recipes folklore. In
their canonical home they pair with modulus `m = 2³¹ − 1 =
2147483647`, a **Mersenne prime**; that is the number that's
"specially prime" in this family, even though it doesn't appear here.

Read the recurrence in that light and the whole erosion field *is* a
**hand-rolled LCG laid out on a 2D grid**:

```
y == 0:  geo = x * 16807     -- MINSTD multiplier #1
x == 0:  geo = y * 48271     -- MINSTD multiplier #2
else:    geo = erosion(x-1, y) * erosion(x, y-1)
erosion  = (geo + depth) mod 20183
```

Each cell multiplies and mods exactly like one LCG step, so
`erosion mod 3` produces a map that *looks* random — rocky / wet /
narrow scattered with no visible pattern — while being fully
deterministic and reproducible from the two seed inputs (`depth`,
`target`). That determinism is what lets the DP and the Dijkstra
recompute the identical cave on every run. `20183` is just a prime
the author picked for the modulus; the only nicety is that it isn't
divisible by 3, so the downstream `mod 3` doesn't get a skewed
type distribution.

The canonical vocabulary worth keeping: **the Day 22 cave is a 2D
Lehmer LCG**, and `16807` (`7⁵`) and `48271` are its signature
multipliers. Same lineage as Day 14's recipe scoreboard and any
"deterministic noise from a tiny seed" generator — when puzzle
constants look like magic, check whether they're a PRNG's.

**Part 1** sums the type numbers over the mouth-to-target rectangle
(13 × 764 regions for our input).

**Part 2** turns the cave into a pathfinding problem. You carry a
torch, climbing gear, or neither; each region type forbids exactly
one of the three (rocky forbids neither-equipped, wet forbids the
torch, narrow forbids the gear). Moving to an adjacent region your
current tool allows costs 1 minute; switching tools (to the other
one valid in your current region) costs 7. Start at the mouth with
the torch; finish *at the target with the torch*. The cave extends
beyond the target in both directions, and the fastest route may use
that space.

---

## The algorithm in Python

The full reference is [day22.py](../../python/day22.py); the two
load-bearing pieces fit on a screen. First the DP fill — in Python
you schedule the dependencies yourself by filling in row-major
order, so `(x-1, y)` and `(x, y-1)` are always ready before `(x, y)`:

```python
def erosion_table(depth, target, mx, my):
    tx, ty = target
    erosion = {}
    for y in range(my + 1):
        for x in range(mx + 1):
            if (x, y) in ((0, 0), (tx, ty)):
                geo = 0
            elif y == 0:
                geo = x * 16807
            elif x == 0:
                geo = y * 48271
            else:
                geo = erosion[x - 1, y] * erosion[x, y - 1]
            erosion[x, y] = (geo + depth) % 20183
    return erosion
```

Then Dijkstra with a binary heap. Tools are encoded `0 neither,
1 torch, 2 climbing gear` — deliberately, so that tool `t` is
forbidden exactly in region type `t`, and "can I be here holding
this?" is one comparison:

```python
heap = [(0, ((0, 0), TORCH))]
settled = set()
while heap:
    dist, state = heapq.heappop(heap)
    if state == goal:
        return dist
    if state in settled:
        continue
    settled.add(state)
    (x, y), tool = state

    for other in (NEITHER, TORCH, GEAR):            # switch: 7 min
        if other != tool and other != region[x, y]:
            heapq.heappush(heap, (dist + 7, ((x, y), other)))

    for nx, ny in neighbours(x, y):                 # step: 1 min
        if in_bounds(nx, ny) and tool != region[nx, ny]:
            heapq.heappush(heap, (dist + 1, ((nx, ny), tool)))
```

That `while` loop *is* Dijkstra's algorithm: always expand the
unsettled state with the smallest known distance, and the first time
you pop a state, that distance is final. The `settled` check
implements **lazy deletion** — a state can sit in the heap several
times with different distances; only the first (smallest) pop
counts, the rest are skipped on arrival.

The Haskell version is the same algorithm with two substitutions:
the hand-scheduled fill loop becomes a lazy self-referential array,
and `heapq` becomes `Data.Set`.

---

## Data model

```haskell
data Puzzle = Puzzle
  { depth  :: !Int        -- cave system depth (erosion-level offset)
  , target :: !(Int, Int) -- target coordinates (x, y)
  }
  deriving (Eq, Show)

data Tool = Neither | Torch | ClimbingGear
  deriving (Eq, Ord, Show, Enum, Bounded)

type State = ((Int, Int), Tool)
```

**Why these types**:

- `Puzzle` is a two-field record because the input genuinely is just
  two values. Strict fields (`!Int`) as always; the `NFData`
  instance is two `rnf` calls so criterion can deep-force it.
- `Tool` is the day's small delight. The constructor *order* is
  chosen so `fromEnum` gives `Neither = 0`, `Torch = 1`,
  `ClimbingGear = 2` — and the puzzle's three forbidden-tool rules
  collapse to "tool `t` is forbidden in region type `t`" (rocky = 0
  forbids `Neither`, wet = 1 forbids `Torch`, narrow = 2 forbids
  `ClimbingGear`). Every validity check in the search is then
  `fromEnum tool /= regionType`. `deriving Enum` gives us
  `fromEnum` for free, `Bounded` gives `[minBound .. maxBound]` as
  the self-maintaining list of all tools — the same trick as Day
  16's `allOps`.
- `State` is a plain pair, and that is load-bearing: the **derived
  `Ord`** on `((Int, Int), Tool)` is what lets `(distance, State)`
  pairs live in a `Data.Set` ordered by distance first, state as
  tie-break. No hand-written comparator anywhere.

A small aside on the two valid tools per region: since the three
tool numbers sum to `0 + 1 + 2 = 3`, the two tools valid in region
type `r` sum to `3 - r`, so "the other valid tool" is
`3 - r - current`. The code spells out the filter instead
(`tool' /= tool, fromEnum tool' /= regionAt grid pos`) because a
list comprehension over three candidates reads better than modular
arithmetic — but it's a nice party trick to know is there.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput raw = case lines raw of
  (depthLine : targetLine : _) ->
    let d        = read (dropLabel depthLine)
        (xs, ys) = break (== ',') (dropLabel targetLine)
    in  Puzzle d (read xs, read (drop 1 ys))
  _ -> error "Day22.parseInput: expected 'depth:' and 'target:' lines"
 where
  dropLabel = drop 2 . dropWhile (/= ':')
```

Two fixed-format lines, so no parser machinery — just three Prelude
functions we've met before (`dropWhile`, `drop`, `read`) and one
that's new this day:

- `break :: (a -> Bool) -> [a] -> ([a], [a])` — splits a list at
  the *first* element satisfying the predicate, returning
  `(before, rest-including-match)`. `break (== ',') "12,763"`
  gives `("12", ",763")`, which is why the second `read` needs a
  `drop 1` to skip the comma. Rust analogue:
  `s.split_once(',')`, except `break` keeps the delimiter.
- `dropLabel` is `drop 2 . dropWhile (/= ':')` — skip up to the
  colon, then skip the colon and the space. Written once, used for
  both lines, so the label text never needs to be spelled out (and
  can't be misspelt).

---

## `erosionGrid` — tying the knot

The day's marquee Haskell idea. Here is the whole function:

```haskell
erosionGrid :: Puzzle -> (Int, Int) -> Array (Int, Int) Int
erosionGrid (Puzzle d (tx, ty)) (mx, my) = grid
 where
  bnds = ((0, 0), (mx, my))
  grid = listArray bnds [ level x y | (x, y) <- range bnds ]

  level x y = (geo x y + d) `mod` 20183

  geo x y
    | x == 0 && y == 0   = 0
    | x == tx && y == ty = 0
    | y == 0             = x * 16807
    | x == 0             = y * 48271
    | otherwise          = grid ! (x - 1, y) * grid ! (x, y - 1)
```

Look at the last guard of `geo`: it indexes `grid` — **the very
array being defined**. `grid` is defined in terms of `level`, which
calls `geo`, which reads `grid`. In a strict language this is a
use-before-initialise bug. In Haskell it is a standard idiom with a
folklore name: **tying the knot**.

Why it works, step by step:

1. `Array` (the boxed one from `Data.Array` — *not*
   `Data.Array.Unboxed.UArray`) stores each element as a pointer to
   a possibly-unevaluated **thunk**. `listArray bnds [...]`
   allocates the spine of the array immediately but evaluates none
   of the elements.
2. When somebody demands `grid ! (5, 3)`, the runtime starts
   evaluating that cell's thunk: `level 5 3` needs `geo 5 3`,
   which reads `grid ! (4, 3)` and `grid ! (5, 2)` — forcing those
   thunks, which force theirs, and so on. The recursion bottoms out
   at the axes and the two special zero cells, where `geo` doesn't
   look at `grid` at all.
3. Each forced thunk is **overwritten in place with its value**
   (that's just how GHC's laziness works — every thunk is evaluated
   at most once). The second time anything reads `grid ! (4, 3)` it
   gets the cached `Int` directly. That update-in-place is the
   memoization: the array *is* the memo table.

Termination is exactly the DP argument: every dependency strictly
decreases `x + y`, so the demand chain always reaches the axes.
There is no infinite loop hiding here — but note that the same idiom
with a *cyclic* dependency would simply deadlock at runtime
(`<<loop>>`), which is why the dependency structure deserves a
moment's thought before you write this.

Three things worth saying out loud:

- **This must be a boxed `Array`.** A `UArray` stores flat
  unboxed `Int#`s with no room for thunks — there is nothing to
  defer, so a self-referential `UArray` cannot exist. The cost of
  boxing is real (a pointer per cell, cache-unfriendly), and the
  optimization sidebar below talks about when to give the idiom up.
- **No evaluation order was specified anywhere.** The Python
  version had to choose row-major order and argue it satisfies the
  dependencies. The Haskell version states the recurrence; demand
  computes exactly the cells needed, in exactly a valid order. For
  Part 1 every cell of the rectangle is demanded anyway, but the
  idiom shines when the demand pattern is sparse or unknown ahead
  of time.
- **Canonical name-dropping**: this is *memoization* of a
  *dynamic-programming recurrence*; the lazy-array flavour is
  "tying the knot", and you'll find it under that name in Haskell
  folklore (along with the more exotic circular-program tricks of
  Bird's "repmin"). The transferable idea: in a lazy language, a
  data structure can be its own memo table.

`range :: Ix i => (i, i) -> [i]` (new this day, from `Data.Ix` via
`Data.Array`) enumerates every index between a pair of bounds — for
pair indices that's `[(0,0), (0,1), ..., (0,my), (1,0), ...]`, i.e.
first coordinate slowest. `listArray` zips that enumeration with
the supplied list, so writing the comprehension over `range bnds`
guarantees list order and array order agree.

`regionAt` is the two-line helper that turns erosion into terrain:

```haskell
regionAt :: Array (Int, Int) Int -> (Int, Int) -> Int
regionAt grid pos = grid ! pos `mod` 3
```

---

## `part1`

```haskell
part1 :: Puzzle -> Int
part1 puzzle@(Puzzle _ (tx, ty)) =
  sum [ regionAt grid pos | pos <- range ((0, 0), (tx, ty)) ]
 where
  grid = erosionGrid puzzle (tx, ty)
```

Risk per region *equals* its type number (rocky 0, wet 1, narrow 2),
so Part 1 is "build the rectangle, sum erosion mod 3". The grid is
sized exactly to the target — Part 1 never needs the padding that
Part 2 will. The 13 × 764 = 9,932 thunks all get forced by the
`sum`, each exactly once: 297 µs total.

---

## `part2` — Dijkstra over position × tool

### Why BFS stops being enough

Days 15 and 20 both used breadth-first search, and both times the
correctness argument was: *the queue visits states in distance
order, because every edge costs exactly 1*. Day 22 breaks that
premise — a step costs 1 but a tool switch costs 7. Run plain BFS
here and a 3-step-plus-switch route (cost 10) gets visited before a
12-step route (cost 12) is finished, yet BFS would have "settled"
states along the second route at hop-count 3 with wrong distances.

**Dijkstra's algorithm** is the repair, and it is a small one:
replace the FIFO queue with a priority queue keyed on
*accumulated cost*, and the visit-in-distance-order invariant comes
back. (In the AI-search literature the same algorithm under the
same name barely exists — they call it *uniform-cost search*. Same
thing: Dijkstra from a single source, stopping at a goal.) BFS is
the special case of Dijkstra where all edges cost 1 and the
priority queue degenerates into a FIFO.

### The layered graph

The other conceptual move: the thing you're pathfinding over is not
the grid. A position alone doesn't determine what you can do next —
it matters what you're holding. So the node set is

```haskell
type State = ((Int, Int), Tool)
```

— three full copies of the cave (one per tool), where moving within
a layer costs 1 (when the layer's tool is valid in the destination
region) and moving *between* layers costs 7 (when both tools are
valid where you stand). Formally this is a **graph product**; in
puzzle terms, "add the hidden state to the node". It's the same
move as Day 13 carting around `(position, direction, next-turn)`
rather than position — and the same move that turns "maze with
keys", "maze with portals", or a chess endgame ("squares × whose
move it is") into ordinary shortest-path problems.

The goal is `((tx, ty), Torch)` — *with the torch* — which the
layered graph handles with zero special-casing: arriving at the
target holding the gear simply isn't the goal node, and the final
7-minute switch (if needed) is just one more edge.

### The search loop

```haskell
go :: Set.Set (Int, State) -> Set.Set State -> Int
go frontier settled = case Set.minView frontier of
  Nothing -> error "Day22.part2: goal unreachable (pad too small?)"
  Just ((dist, st), rest)
    | st == goal              -> dist
    | st `Set.member` settled -> go rest settled
    | otherwise ->
        let settled' = Set.insert st settled
            fresh    = [ (dist + cost, st')
                       | (cost, st') <- moves st
                       , not (st' `Set.member` settled') ]
            !frontier' = foldl' (flip Set.insert) rest fresh
        in  go frontier' settled'
```

The frontier is a `Set (Int, State)` — and because tuples compare
lexicographically, the set's minimum element is always the
smallest-distance entry. That makes `Data.Set` a perfectly good
priority queue:

- `Set.minView :: Set a -> Maybe (a, Set a)` (new this day) pops
  the minimum: it returns the smallest element *and* the set
  without it, in O(log n). It's `Map.minViewWithKey`'s sibling and
  plays the role `heapq.heappop` played in the Python.
- There is no decrease-key. When we find a better route to a state
  already in the frontier, we just insert a second entry with the
  smaller distance. The smaller one pops first and settles the
  state; when the stale larger one surfaces later, the
  `st `Set.member` settled` guard discards it. This is **lazy
  deletion**, and it's the standard way to do Dijkstra in any
  language whose heap lacks decrease-key (Python's `heapq`, Rust's
  `BinaryHeap`, and Haskell's `Data.Set` alike). The frontier can
  hold up to E entries instead of V — for this graph, harmless.
- Termination at first goal pop is Dijkstra's central theorem: when
  a state is popped with distance `d`, no other route to it can be
  shorter (every other frontier entry already costs ≥ `d`, and
  edge costs are non-negative). So returning `dist` the moment the
  goal surfaces is not an optimisation — it *is* the algorithm's
  correctness guarantee. One sanity note: the guard order matters.
  Goal check before settled check costs nothing; settled check
  before *expanding* prevents exponential re-expansion.

`moves` enumerates at most 2 + 4 actions (two other tools minus
validity, four neighbours minus bounds and validity), each a
`(cost, state)` pair. Both validity tests are the one-comparison
encoding trick: `fromEnum tool /= regionAt grid pos`.

### The pad

The cave is unbounded to the right and below, and the prose warns
the best route may pass the target. An infinite Dijkstra would
still terminate (it stops at the goal), but our erosion grid is an
*array* and needs concrete bounds. So `part2 = part2Padded 100`:
compute erosion out to `target + 100` in each direction and let the
pad edge act as a wall.

Why is a finite pad sound? An exchange argument: a route that
strays `k` columns past the target spends at least `2k` minutes on
the excursion (1 minute per column out, 1 back) — so if *any* route
of cost `U` exists, no optimal route strays more than `U / 2`. Our
answer is 1051, the in-rectangle Manhattan distance alone is 775,
and routes near that bound exist without leaving the rectangle —
the optimal excursion is therefore far smaller than 100 columns.
Rather than formalise that, the test suite pins it empirically:

```haskell
it "Part 2 is pad-independent on the real cave" $ do
  raw <- readFile "inputs/day22.txt"
  part2Padded 200 (parseInput raw) `shouldBe` actualPart2
```

If 100 were too tight, doubling it would change the answer and the
test would fail. (And if the pad were somehow so small the goal got
walled off entirely, the `Nothing` branch panics with a message
naming the pad as the suspect.)

### How far does the optimal path actually stray?

The exchange argument above shows the pad is *sufficient*. It's
worth confirming empirically that a pad is also *necessary* — i.e.
the optimal path really does leave the mouth-to-target rectangle.
Sweeping the pad and reconstructing the shortest path each time:

| pad | answer | path max x | path max y |
|----:|-------:|-----------:|-----------:|
| 0 (clamped to target) | **1112** | 12 | 763 |
| 5   | 1074 | 17 | 763 |
| 10+ | **1051** | **22** | 763 |

Two things fall out:

- **Clamping to the tight rectangle gives the wrong answer.** With
  `pad = 0` the search is boxed into the `(0,0)..(12,763)` rectangle
  and returns **1112** — 61 minutes worse than the true optimum of
  **1051**. The shortest route genuinely needs to exit the
  rectangle; the pad is not just defensive padding, it's load-bearing.
- **The straying is asymmetric: east, not south.** The optimal path
  reaches `x = 22` — ten columns *past* the target's `x = 12` — but
  never goes below `y = 763` (the target's own row). That's a
  consequence of the rectangle's shape. The target `(12, 763)` makes
  a tall, narrow strip: only 13 columns wide but 764 rows tall. With
  so few columns, the cheapest route can't line up favourable
  region/tool combinations without busting out sideways; vertically
  it already has ample room, so descending past the target buys
  nothing. The answer converges by `pad = 10`, comfortably inside
  the shipped `pad = 100`.

So the picture is complete: the exchange argument bounds the stray
from above (≤ `U/2` columns), and this sweep shows the stray is
strictly positive (≈10 columns east). A correct solver must pad;
the only question the argument settles is *how much*.

### Possible optimization

306 ms is comfortably inside budget, but two standard upgrades are
worth knowing about (untested pseudo-Haskell, as usual):

1. **A\* search.** Dijkstra expands states in *every* direction —
   including 100 columns of pad to the right and 100 rows below the
   target, none of which can be on an optimal path. A\* fixes the
   priority to `dist + heuristic(state)` where the heuristic is an
   *admissible* (never-overestimating) guess of the remaining cost:

   ```haskell
   heuristic ((x, y), tool) =
     abs (tx - x) + abs (ty - y) + if tool == Torch then 0 else 7
   ```

   Manhattan distance is admissible (every step costs ≥ 1 and moves
   1 closer at best), and the `+ 7` is sound because a non-torch
   finish must pay one switch. Chess-engine framing: Dijkstra is
   brute-force search ordered by cost-so-far `g`; A\* is the same
   search with an evaluation function `g + h` steering it toward
   the goal — and admissibility is what keeps the "evaluation" from
   ever causing a wrong answer, unlike a chess eval. Typical
   speedup here is 2–4× from expanding roughly half the states.

2. **Flat mutable state tables.** The `Set`-based frontier and
   settled set pay a `log n` constant and pointer-chase per
   operation. The state space is small and dense —
   `(mx+1) × (my+1) × 3 ≈ 293k` states — so both tables flatten
   into unboxed arrays indexed by `(x * height + y) * 3 + tool`:
   an `STUArray s Int Int` of best-known distances replacing the
   settled set, and (because edge costs are only 1 and 7) even the
   priority queue can become a **bucket queue** — an array of
   distance buckets scanned in increasing order (Dial's algorithm),
   making every queue operation O(1). That's the same
   Map-to-unboxed-array move as Day 15's sidebar; expect roughly
   an order of magnitude.

---

## Key patterns

- **A lazy structure can be its own memo table.** Define the
  recurrence, index the structure inside its own definition, and
  let demand schedule the evaluation. Works for any DP whose
  dependency graph is acyclic; fails loudly (`<<loop>>`) when it
  isn't. Boxed `Array` is the workhorse; the idiom does not exist
  in strict languages.
- **Dijkstra = BFS + priority queue.** The moment edge costs
  differ, swap the FIFO for a min-priority structure and the
  visit-in-distance-order invariant returns. `Data.Set` of
  `(cost, state)` pairs with `minView` is a perfectly serviceable
  priority queue, with lazy deletion replacing decrease-key.
- **Put the hidden state in the node.** If "what you can do next"
  depends on more than position, the graph's nodes are
  position × that extra thing. Tools here; direction on Day 13;
  keys, portals, or side-to-move elsewhere.
- **Encode so the rule becomes arithmetic.** Numbering tools so
  that tool `t` is forbidden exactly in region type `t` turned
  three prose rules into `fromEnum tool /= regionType`. Worth a
  minute of thought at type-design time on any puzzle with a
  compatibility table.
- **Pin your approximations.** The pad is the solution's one leap
  of faith, so a test doubles it and demands the same answer. Same
  spirit as Day 17's "implausible magnitude" lesson: make the
  assumption checkable, then check it.

---

## If I were writing this in Rust

The Dijkstra half translates almost token for token:
`BinaryHeap<Reverse<(u32, State)>>` is the frontier (`Reverse`
because Rust's heap is a max-heap), `HashSet<State>` the settled
set, and the lazy-deletion pattern — push duplicates, skip settled
pops — is exactly what the `std::collections::binary_heap` docs
recommend, since `BinaryHeap` has no decrease-key either. `Tool` as
a fieldless `enum` with `#[repr(u8)]` gives the same
`tool as u8 != region` encoding trick, and the derived `Ord` on a
tuple struct mirrors the derived `Ord` on the Haskell pair.

The erosion grid is where the languages genuinely diverge. The
knot-tied self-referential array is simply not expressible in Rust —
initialising a `Vec` from its own not-yet-written elements is
use-before-init, and the borrow checker is right to refuse. You'd
write what the Python writes: allocate `vec![0u32; w * h]`, fill it
in row-major order, and carry the proof-of-dependency-order in your
head (or a comment) instead of letting the runtime discover it.
Strict languages make you the evaluation scheduler; that's the
trade Haskell's boxing overhead buys back.

---

**Navigation**: [← Day 21](day21_function_guide.md) | [All Days](summary_2018.md) | [Day 23 →](day23_function_guide.md)
