# Day 25: Four-Dimensional Adventure -- Function Guide

**Problem**: A list of 4-D points. Two points share a *constellation*
if their Manhattan distance is ≤ 3, transitively — so constellations
are the connected components of the graph that joins every pair within
distance 3. Part 1: count the constellations. Part 2: none — Day 25's
second star is awarded for finishing the other 49.

**Answers**: Part 1 = **420**, Part 2 = *(free star)*
**Code**: [Day25.hs](../../src/Day25.hs) · **Python reference**: [day25.py](../../python/day25.py)
**Runtime**: Parse 2.98 ms · Part 1 6.75 ms · Total ≈ 9.73 ms

**New concepts this day**:

- **Union-Find (disjoint-set union).** The canonical near-constant-time
  structure for "group these things by a transitive relation." Two
  optimisations make it fast: **path compression** (flatten the tree on
  every lookup) and **union by rank** (attach the shorter tree under the
  taller). Together they give an amortised cost so close to constant
  it's governed by the inverse Ackermann function — effectively O(1).
- **Connected components without an explicit graph.** We never build an
  adjacency list. The O(n²) pairwise distance scan feeds `union`
  directly, and the component count is just the number of *roots* left
  at the end.
- **`STUArray`-backed mutable arrays in `runST`**, one more time — the
  parent and rank tables are exactly the mutable-int-array workload `ST`
  is built for (the Days 9 / 11 / 14 / 17 pattern).

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Data model](#data-model)
- [Parsing](#parsing)
- [Union-Find](#union-find)
- [`part1` and `part2`](#part1-and-part2)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

The input is ~1166 points in 4-space, one `x,y,z,w` per line
(coordinates can be negative). Define an edge between any two points
whose Manhattan distance `|Δx|+|Δy|+|Δz|+|Δw|` is at most 3. A
*constellation* is a connected component of that graph — a maximal set
of points reachable from one another by hopping along edges. The answer
is the number of components.

The worked examples pin the transitivity: in the first, `0,0,0,6`
joins a constellation not because it is within 3 of the seed, but
because it is within 3 of `0,0,0,3`, which is already in it — a *chain*.
A lone added point `6,0,0,0` would merge two constellations into one.
That "merge on contact, transitively" behaviour is the textbook cue for
**union-find**.

There is no Part 2 — Day 25 always awards its final star for free once
the rest of the calendar is complete. `part2` is a stub so the
project's four-function shape and the benchmark harness still apply.

---

## The algorithm in Python

The full reference is [day25.py](../../python/day25.py). Union-find is
clearest with mutable arrays, so the Python reads almost like the
Haskell `ST` version:

```python
def count_constellations(points):
    n = len(points)
    parent = list(range(n))          # parent[i] = i: each point its own set
    rank = [0] * n

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]   # path halving
            x = parent[x]
        return x

    def union(x, y):
        rx, ry = find(x), find(y)
        if rx == ry:
            return
        if rank[rx] < rank[ry]:
            rx, ry = ry, rx
        parent[ry] = rx
        if rank[rx] == rank[ry]:
            rank[rx] += 1

    for i in range(n):
        for j in range(i + 1, n):
            if manhattan(points[i], points[j]) <= 3:
                union(i, j)

    return sum(1 for i in range(n) if find(i) == i)
```

Three pieces: a `parent` array (each node points at its set's
representative, or itself if it is the root), a `find` that walks to the
root, and a `union` that links two roots. The double loop unions every
close pair; the answer counts roots. The Haskell version uses recursive
*path compression* (point straight at the root) where this Python uses
iterative *path halving* (point at your grandparent) — both flatten the
tree; the recursive form reads more naturally in Haskell.

---

## Data model

```haskell
type V4 = (Int, Int, Int, Int)
type Puzzle = [V4]
```

- `V4` is a bare 4-tuple. As on Day 23, a tuple gives `Eq`, `Ord`, and
  (for the benchmark) `NFData` for free — `deepseq` ships instances for
  tuples up to size 7.
- `Puzzle` is just the list of points. The union-find works on *indices*
  `0 .. n-1` into this list, not on the points themselves, so the
  points are frozen into an immutable `Array Int V4` for O(1) lookup
  during the pairwise scan:

  ```haskell
  points = listArray (0, n - 1) pts :: Array Int V4
  ```

  `listArray :: Ix i => (i, i) -> [e] -> Array i e` builds an immutable
  array from bounds and a list; `(!) :: Array i e -> i -> e` indexes it
  in O(1). (`Data.Array`, the boxed immutable array — contrast the
  unboxed `STUArray` used for the integer tables below.)

---

## Parsing

```haskell
parseInput :: String -> Puzzle
parseInput = map parseLine . filter (not . null) . lines

parseLine :: String -> V4
parseLine line = case map read (words (map commaToSpace line)) of
  [a, b, c, d] -> (a, b, c, d)
  _            -> error ("Day25.parseLine: cannot parse " ++ show line)
 where
  commaToSpace ch = if ch == ',' then ' ' else ch
```

The same blank-and-`words` trick as Day 23: turn each comma into a
space so `words` splits the line, then `read` each chunk (which handles
the leading `-` on negatives). `filter (not . null)` drops the trailing
blank line so a stray newline doesn't reach `parseLine`. The
`case ... of [a,b,c,d]` match both destructures the four coordinates and
asserts there are exactly four — a malformed line explodes loudly.

```haskell
manhattan :: V4 -> V4 -> Int
manhattan (a, b, c, d) (e, f, g, h) =
  abs (a - e) + abs (b - f) + abs (c - g) + abs (d - h)
```

Manhattan distance extended to four axes — the only geometry the puzzle
needs.

---

## Union-Find

The whole computation lives in one `runST` so the parent/rank tables can
be mutated in place, then thrown away with only the `Int` answer
escaping.

```haskell
countConstellations :: [V4] -> Int
countConstellations pts = runST action
 where
  n      = length pts
  points = listArray (0, n - 1) pts :: Array Int V4

  action :: forall s. ST s Int
  action = do
    parent <- newListArray (0, n - 1) [0 .. n - 1] :: ST s (STUArray s Int Int)
    rank   <- newArray     (0, n - 1) 0            :: ST s (STUArray s Int Int)
    ...
```

- `runST :: (forall s. ST s a) -> a` runs a stateful `ST` computation
  and returns its pure result. The `forall s.` rank-2 type is what stops
  a mutable array from leaking out of the `ST` bubble — the same safety
  trick relied on since Day 9. `action` carries the matching `forall s.`
  signature (needing `ScopedTypeVariables`) so the `s` is in scope for
  the inner `:: ST s (STUArray s Int Int)` annotations.
- `parent` starts as the identity `[0,1,2,…]` — every point is its own
  set's root. `rank` starts all-zero — every tree has height 0.
  `newListArray` builds a mutable array from a list; `newArray bounds v`
  fills one with a constant. Both are `STUArray s Int Int` — *unboxed*
  mutable arrays of `Int`, so each cell is a raw machine word with no
  pointer indirection.

### `find` with path compression

```haskell
    let find :: Int -> ST s Int
        find x = do
          p <- readArray parent x
          if p == x
            then return x
            else do
              r <- find p
              writeArray parent x r   -- path compression: point x straight at the root
              return r
```

`find x` walks parent pointers until it reaches a self-parent (the
root). The clever line is `writeArray parent x r` *after* the recursive
call: on the way back up, every node visited is re-pointed **directly at
the root**. The next `find` on any of them is then a single hop. This is
**path compression**, and it is why a long chain like the first
example's collapses to a flat star after one traversal.

### `union` by rank

```haskell
        union :: Int -> Int -> ST s ()
        union x y = do
          rx <- find x
          ry <- find y
          when (rx /= ry) $ do
            rkx <- readArray rank rx
            rky <- readArray rank ry
            case compare rkx rky of
              LT -> writeArray parent rx ry
              GT -> writeArray parent ry rx
              EQ -> do writeArray parent ry rx
                       writeArray rank rx (rkx + 1)
```

`union` finds both roots and, if they differ, links them. **Union by
rank** keeps the trees shallow: the root with the smaller `rank` (an
upper bound on tree height) is attached under the larger, so the height
never grows unnecessarily. Only when both ranks are equal does the
surviving root's rank tick up by one. `when :: Bool -> ST s () -> ST s
()` (from `Control.Monad`) runs its action only if the condition holds —
here, skip work when the two points are already in the same set.

Path compression and union by rank together give the famous bound: a
sequence of `m` operations on `n` elements costs `O(m · α(n))`, where
α is the inverse Ackermann function — at most 4 or 5 for any input that
fits in the universe. Effectively constant per operation.

### Driving it

```haskell
    forM_ [0 .. n - 1] $ \i ->
      forM_ [i + 1 .. n - 1] $ \j ->
        when (manhattan (points ! i) (points ! j) <= 3) (union i j)

    foldM (\acc i -> do
             p <- readArray parent i
             return (if p == i then acc + 1 else acc))
          0 [0 .. n - 1]
```

- `forM_ :: [a] -> (a -> ST s ()) -> ST s ()` runs an action for each
  element, discarding results (the `_` suffix means "for effect"). The
  nested `forM_` is the O(n²) pairwise scan — `[i+1 .. n-1]` for the
  inner index so each unordered pair is visited once. Every pair within
  distance 3 is `union`ed. At n ≈ 1166 that's ~680k distance checks, a
  few milliseconds.
- The final `foldM` counts **roots**: every node `i` with
  `parent[i] == i`. Each component has exactly one root, so this *is*
  the component count — no need to `find` everyone first. `foldM` is the
  monadic left fold: it threads the running count through `ST` because
  each step does a `readArray`. (We could use a pure `find`-and-collect
  into a `Set`, but counting self-parents is simplest and exact.)

Why O(n²) and not a spatial structure? With only ~1166 points the
quadratic scan is ~7 ms — far simpler than a 4-D k-d tree or grid bucket
that would shave it, and well inside budget. The function guide for
Day 23 reached for an octree because the search space was 10²⁴; here a
flat double loop is the right call.

---

## `part1` and `part2`

```haskell
part1 :: Puzzle -> Int
part1 = countConstellations

part2 :: Puzzle -> Int
part2 _ = 0
```

Part 1 is the constellation count. Part 2 is a deliberate stub: Day 25
has no second puzzle — the 50th star drops as soon as the other 49 are
collected. Keeping `part2 _ = 0` preserves the uniform four-function API
(`parseInput` / `part1` / `part2` / `solve`) and lets the benchmark
harness treat Day 25 like any other day. `solve` prints the count and a
festive line instead of a number:

```haskell
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn "  part 2: (free star -- Merry Christmas!)"
```

---

## Key patterns

- **"Merge on contact, transitively" ⇒ union-find.** Any time a problem
  groups items by a relation that should be transitive (connectivity,
  "same network," "same constellation"), disjoint-set union is the
  default tool. Build it once and the two optimisations — path
  compression in `find`, union by rank in `union` — make it effectively
  constant-time; the canonical bound is `α(n)`, the inverse Ackermann.

- **Components without a graph.** You do not need an adjacency list to
  count connected components. Feed every edge straight into `union` as
  you discover it, and read off the number of roots at the end. The
  graph is implicit in the union calls.

- **Count roots, don't re-`find`.** After all unions, the number of
  self-parents (`parent[i] == i`) equals the number of components,
  regardless of compression state — one root per set, by construction.

- **`runST` + `STUArray` for index-keyed integer scratch space.** When
  an algorithm wants a couple of mutable `Int` arrays indexed `0..n-1`
  (parent, rank, distance, visited…), `runST` with `STUArray` gives
  in-place mutation and unboxed storage, then hands back a pure result.
  This is the same shape as Days 9, 11, 14, and 17 — by Day 25 it should
  read as routine.

---

## If I were writing this in Rust

Almost a transcription. `parent: Vec<usize>` initialised to `(0..n)
.collect()`, `rank: vec![0u8; n]`. `find` is the iterative path-halving
loop (Rust discourages the deep recursion the Haskell `find` uses, and
halving is just as flat in practice). `union` is the same rank
comparison with a `mem::swap` to put the taller tree first. The pairwise
loop is `for i in 0..n { for j in i+1..n { if manhattan(p[i], p[j]) <= 3
{ uf.union(i, j) } } }`, and the answer is `(0..n).filter(|&i|
uf.find(i) == i).count()`. It would run in well under a millisecond —
Rust's flat `Vec<usize>` with in-place writes avoids the boxed-`ST`
overhead — but the algorithm, and the two optimisations that make it
fast, are identical. Union-find is one of those structures that looks
the same in every language; only the borrow-checker dance around the
recursive `find` differs.

---

*And that completes Advent of Code 2018 in Haskell — all 25 days, plus
the Day 0 warm-up. Merry Christmas!* 🎄

---

**Navigation**: [← Day 24](day24_function_guide.md) | [All Days](summary_2018.md)
