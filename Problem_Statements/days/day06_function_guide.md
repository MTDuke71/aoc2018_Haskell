# Day 06: Chronal Coordinates -- Function Guide

**Problem**: 50 integer points in the plane partition every other integer cell into Manhattan-distance Voronoi regions; cells equidistant from two or more points have no owner. Part 1 asks for the largest region whose area is *finite*. Part 2 asks how many cells have a *total* Manhattan distance to all 50 points strictly less than 10000.
**Answers**: Part 1 = **4233**, Part 2 = **45290**
**Runtime** (mean, criterion `-O2`): Parse = **53.2 µs** | Part 1 = **142.5 ms** | Part 2 = **16.5 ms** | **Total = 159.0 ms**
**Code**: [Day06.hs](../../src/Day06.hs)
**Tests**: [Day06Spec.hs](../../test/Day06Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day06"`
**Problem statement**: [day06.md](day06.md)

**New concepts this day** (beyond Days 0--5):

- **Bounding-box reasoning**. The plane is infinite, but Part 1 reduces to a finite question because *every input coord whose Voronoi region touches the bounding-box border has an infinite area*, and every coord that does not touch the border has all of its territory inside the box. The box is enough.
- **Manhattan-distance Voronoi**, computed directly: for each cell, sort the 50 (distance, index) pairs and check whether the two smallest distances are tied. No flood-fill, no priority queue.
- **The bare-tuple type**. Day 3 introduced records, Day 4 introduced sum types, but Day 6 deliberately stays with `type Coord = (Int, Int)` -- two fields, both `Int`, no other context. Custom records earn their keep when there are 3+ fields or the fields would otherwise be confusable.

`mapMaybe`, `Map.fromListWith`, `Set`, list comprehensions with two generators, and `where` clauses are all reused from earlier days.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Data model](#data-model)
3. [`parseInput`](#parseinput)
4. [`manhattan`](#manhattan)
5. [`bounds`, `gridCells`, `borderCells`](#bounds-gridcells-bordercells)
6. [`closest` -- ties via two smallest distances](#closest)
7. [`part1` -- the bounding-box trick](#part1)
8. [`totalDistance`, `safeRegionSize`, `part2`](#part2)
9. [`solve`](#solve)
10. [Tests](#tests)
11. [Benchmarks](#benchmarks)
12. [Why the bounding box is enough -- and when it would not be](#why-the-bounding-box-is-enough)
13. [Possible optimizations](#possible-optimizations)
14. [Key patterns](#key-patterns)
15. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The puzzle gives 50 integer points (the actual input; the worked example uses 6). Each *integer* cell of the plane is assigned to its closest input point under the Manhattan metric `d((x1, y1), (x2, y2)) = |x1 - x2| + |y1 - y2|`. If two or more input points are tied at the minimum distance, the cell has no owner.

**Part 1** -- the size of the largest *finite* Voronoi region. The example's largest finite region has 17 cells (around point `E`).

**Part 2** -- count cells whose *sum* of Manhattan distances to all input points is strictly less than 10000 (the example uses a smaller threshold of 32 -- answer 16). This is a single threshold over the L1-distance-sum field, not a per-point Voronoi question.

The two parts share the Manhattan-distance helper and the cell-grid generator; everything else is independent.

---

## Data model

```haskell
type Coord = (Int, Int)
```

`Coord` is a *type synonym*: `Coord` and `(Int, Int)` are interchangeable everywhere. Day 3 and Day 4 used `data` declarations (`Claim`, `Event`) to add structure; Day 6 keeps the bare tuple because:

- Two fields, both the same type, in a fixed and obvious order.
- The same shape (`x, y`) describes both *input points* and *grid cells* -- a single type avoids unnecessary wrapping/unwrapping.
- Pattern-matching on a tuple (`(x, y)`) is as ergonomic as on a record.

If the puzzle had introduced a third field (a label, a weight, a colour), `data Coord = Coord !Int !Int !X` would have been worth the constructor name. It does not, so we save the keystrokes.

---

## `parseInput`

```haskell
parseInput :: String -> [Coord]
parseInput = map parseLine . lines
  where
    parseLine :: String -> Coord
    parseLine line = case break (== ',') line of
      (xs, ',' : ' ' : ys) -> (read xs, read ys)
      _                    -> error ("Day06.parseInput: bad line " ++ show line)
```

Two new bits of plumbing:

- **`break :: (a -> Bool) -> [a] -> ([a], [a])`** splits a list at the first element that satisfies the predicate. The predicate's element is *kept on the right*. So `break (== ',') "181, 47"` returns `("181", ", 47")` -- everything before the comma on the left, the comma and tail on the right.
- **The pattern `(xs, ',' : ' ' : ys)`** consumes the comma and the space at the head of the right half before binding `ys` to the rest. If the input does not have a `", "` separator the pattern fails to match, and the explicit `_ -> error ...` arm catches the malformed line with a useful message.

The remaining `read xs` / `read ys` are the standard Day 1 / Day 0 idiom.

### Why not `words` like Day 1?

`words "181, 47"` returns `["181,", "47"]` -- the comma is glued to the first token. We would have to `init xs` to drop it before `read`. The `break`-based parser is one expression and tells the reader exactly what shape is expected.

---

## `manhattan`

```haskell
manhattan :: Coord -> Coord -> Int
manhattan (x1, y1) (x2, y2) = abs (x1 - x2) + abs (y1 - y2)
```

Pattern-matches the two tuples, sums the absolute coordinate differences. `abs :: Num a => a -> a` is the unsigned magnitude. Symmetric (`manhattan a b == manhattan b a`) and zero on equal points -- both checked in the test file.

---

## `bounds`, `gridCells`, `borderCells`

```haskell
bounds :: [Coord] -> (Int, Int, Int, Int)
bounds cs = (minimum xs, maximum xs, minimum ys, maximum ys)
  where
    xs = map fst cs
    ys = map snd cs
```

A 4-tuple `(xMin, xMax, yMin, yMax)`. The two `where`-bindings build the X and Y projections once; calling `minimum` and `maximum` on the same list twice is fine because `where` shares the binding.

For the actual input, `bounds` returns `(54, 357, 40, 347)` -- a 304 by 308 box, 93 632 cells.

```haskell
gridCells :: (Int, Int, Int, Int) -> [Coord]
gridCells (xMin, xMax, yMin, yMax) =
  [(x, y) | x <- [xMin .. xMax], y <- [yMin .. yMax]]
```

Two-generator list comprehension, exactly the shape we used on Day 3 to enumerate the squares of a `Claim`. `[xMin .. xMax]` is an *enumeration*: it expands to `[xMin, xMin+1, ..., xMax]`. The comprehension iterates `x` over the X range and, for each `x`, walks `y` over the Y range -- a flat list of all grid cells, in column-major order.

```haskell
borderCells :: (Int, Int, Int, Int) -> [Coord]
borderCells (xMin, xMax, yMin, yMax) =
  [ (x, y)
  | x <- [xMin .. xMax]
  , y <- [yMin .. yMax]
  , x == xMin || x == xMax || y == yMin || y == yMax
  ]
```

Same comprehension shape, plus a *guard*: a Boolean expression after the generators that filters the output. We keep only cells where x or y matches the box extreme -- exactly the cells on the border. For a 304 by 308 box that is `2 * 304 + 2 * 308 - 4 = 1220` cells (the `-4` removes the four corners that would otherwise be double-counted by the OR test).

We could write `borderCells` as four edge ranges concatenated with `++`, but the comprehension+guard form is one sweep of the same grid we already enumerate for `gridCells` and reads as "cells on the box, where x or y is extreme."

---

## `closest`

```haskell
closest :: [Coord] -> Coord -> Maybe Int
closest cs cell = case sorted of
  []                                     -> Nothing
  [(_, i)]                               -> Just i
  (d1, i1) : (d2, _) : _
    | d1 == d2  -> Nothing
    | otherwise -> Just i1
  where
    sorted :: [(Int, Int)]
    sorted = sort [(manhattan c cell, i) | (i, c) <- zip [0 ..] cs]
```

For a given cell, return the index of the unique closest input point, or `Nothing` if two are tied at the minimum.

### Pairing each coord with its index

```haskell
zip [0 ..] cs
```

`zip :: [a] -> [b] -> [(a, b)]` walks two lists in parallel, stopping when the shorter runs out. `[0 ..]` is the *infinite* list of non-negative `Int`s; `zip` consumes only as much of it as `cs` is long, so we get `[(0, c0), (1, c1), ..., (49, c49)]` for the actual input. Pairing with the index lets `Map.fromListWith` later count cells per coord without an extra index tracking step.

The list comprehension `[(manhattan c cell, i) | (i, c) <- zip [0 ..] cs]` rebuilds each pair as `(distance, index)` -- distance first, because we want to sort by distance.

### `sort` on tuples

```haskell
sort :: Ord a => [a] -> [a]   -- from Data.List
```

`Data.List.sort` is stable and sorts using the type's `Ord` instance. For tuples, `Ord` is *lexicographic*: `(d1, i1) <= (d2, i2)` iff `d1 < d2`, or `d1 == d2 && i1 <= i2`. So `sort` orders the list primarily by distance and breaks ties by index. The smallest distance is at the head; the second-smallest is the second element.

### Tie detection on the head

```haskell
(d1, i1) : (d2, _) : _
  | d1 == d2  -> Nothing
  | otherwise -> Just i1
```

Pattern-matching the first two elements off the sorted list and applying a guard: if the two smallest distances coincide, the cell is tied at the minimum and has no owner. Otherwise the head is the unique winner.

The `[]` and `[(_, i)]` arms are a safety net -- the puzzle always gives at least one input point, but pattern-matching incompletely would leave a `-Wincomplete-patterns` warning. With the `[]` and singleton arms, the pattern is exhaustive.

### Why sort the whole list when we only need the top 2?

50 elements; sort runs in O(n log n) ≈ 282 comparisons per cell. A two-min linear scan would be O(n) ≈ 50 comparisons per cell -- a 5x improvement, multiplied by ~94 000 cells. The current implementation is the more readable form; the optimisation sidebar below has the linear scan written out.

---

## `part1`

```haskell
part1 :: [Coord] -> Int
part1 cs
  | null cs   = 0
  | otherwise = if Map.null counts then 0 else maximum (Map.elems counts)
  where
    bb       = bounds cs
    cellOwners = mapMaybe (closest cs) (gridCells bb)
    infinite = Set.fromList (mapMaybe (closest cs) (borderCells bb))
    counts   = Map.fromListWith (+)
                 [ (i, 1) | i <- cellOwners, not (i `Set.member` infinite) ]
```

Read the `where` clause top-down -- it is the recipe.

1. **`bb = bounds cs`**. The bounding box of the input coords. Defines the search space.
2. **`cellOwners = mapMaybe (closest cs) (gridCells bb)`**. For every cell inside the box, ask `closest cs` for its owner; `mapMaybe` keeps only the `Just` indices and drops the ties. The result is a list of length `(box area) - (tied cell count)`.
3. **`infinite = Set.fromList (mapMaybe (closest cs) (borderCells bb))`**. Owner indices for the *border* cells of the box -- exactly the indices whose Voronoi region escapes the box. `Set.fromList` deduplicates them for O(log n) membership tests later.
4. **`counts = Map.fromListWith (+) [(i, 1) | ... not (i `Set.member` infinite)]`**. Count cell ownership per coord, but skip indices that are in the `infinite` set. The comprehension produces one `(index, 1)` pair per finite-area cell; `fromListWith (+)` groups by key and sums.
5. **`maximum (Map.elems counts)`**. Largest finite-area count.

The two guards on the function -- `null cs` and `Map.null counts` -- protect against degenerate inputs (an empty coord list, or every coord touching the border). For the actual puzzle they never trigger, but they keep `maximum` safe (which would panic on an empty list).

### The bounding-box trick

The crux of Part 1: *we never look outside the bounding box.*

**Claim**: a coordinate's Voronoi region is finite if and only if it does not own any cell on the bounding-box border.

**Why "only if"**: if coord `k` owns a border cell `(x, y)` on (say) the right edge `x = xMax`, then for every `x' > xMax` the cell `(x', y)` is also strictly closer to `k` than to any other coord. This is because moving rightward past the bounding box increases the distance from every coord by 1 per step; what matters is the *relative ordering* of distances, which is preserved. So once `k` owns a border cell, it owns an infinite ray of cells outward.

**Why "if"**: contrapositive. If `k` does *not* own any border cell, then the boundary of `k`'s Voronoi region is fully inside the box -- it never escapes -- so the region is bounded.

This is what lets us replace an infinite plane with a finite grid of ~94 000 cells: the question "what is the largest finite Voronoi area" becomes "what is the largest count among coords that do not appear as owners of border cells," and that question is purely about a finite grid.

A more rigorous treatment is in [the dedicated section below](#why-the-bounding-box-is-enough).

---

## `part2`

```haskell
totalDistance :: [Coord] -> Coord -> Int
totalDistance cs cell = sum [manhattan c cell | c <- cs]

safeRegionSize :: Int -> [Coord] -> Int
safeRegionSize threshold cs =
  length [ () | cell <- gridCells (bounds cs)
              , totalDistance cs cell < threshold ]

part2 :: [Coord] -> Int
part2 = safeRegionSize 10000
```

Part 2 is *not* a Voronoi question -- it does not ask which coord is closest, only the *sum* of distances to all of them. For each cell in the bounding box, compute the sum, and count how many cells fall under the threshold.

### `length [() | cell <- ..., predicate]`

The `()` (read "unit") is the singleton of the unit type -- it carries no information. `[() | x <- xs, p x]` is the list-comprehension idiom for "count how many `x` satisfy `p`":

- The generator iterates over `xs`.
- The guard `p x` filters.
- The yield is `()` -- one element per surviving `x`.
- `length` of the resulting list is the count.

Equivalent forms:

```haskell
length (filter (\cell -> totalDistance cs cell < threshold) (gridCells bb))
sum [1 | cell <- gridCells bb, totalDistance cs cell < threshold]
```

All three produce the same answer. The `() | ... , predicate` form reads slightly more like prose: "one tally for every cell whose total distance is below the threshold." The `filter` form is shorter when there is a single predicate; the comprehension form generalises cleanly to multiple generators.

### Why the bounding box is enough for Part 2

Outside the bounding box, every input coord lies on the same side of the cell, so moving one step further out increases *every* coord's distance by 1 -- the total distance increases by `length cs = 50` per step. With threshold 10 000, the safe region cannot extend more than `10000 / 50 = 200` steps past the box; in practice the centroid is comfortably central and the safe region is well inside the box. For this puzzle, restricting to `gridCells (bounds cs)` is sound. (See [Why the bounding box is enough](#why-the-bounding-box-is-enough) for the argument.)

---

## `solve`

```haskell
solve :: String -> IO ()
solve contents = do
  let cs = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 cs))
  putStrLn ("  part 2: " ++ show (part2 cs))
```

`parseInput` runs once; both parts read the shared `cs` binding. The two parts have no algorithmic overlap (Part 1's per-cell sort vs Part 2's per-cell sum), so there is no second-level sharing to extract.

---

## Tests

Coverage in [Day06Spec.hs](../../test/Day06Spec.hs):

1. **`parseInput`** -- the six example coords parse exactly.
2. **`manhattan`** -- zero on identical points, symmetric, two non-trivial cases including a negative coordinate.
3. **`bounds`** -- the example's `(1, 8, 1, 9)` box.
4. **`closest`** on the example -- a unique winner, a tie (`(5, 0)` between `A` and `C`), and two cases where the cell is *on* an input coord (distance 0 wins).
5. **Puzzle example** -- Part 1 = 17 (region around `E`), Part 2 with threshold 32 = 16.
6. **Actual input** -- Part 1 = 4233, Part 2 = 45290.

The example tests pin the algorithm against the puzzle description. The actual-input tests pin the recorded answers so a future refactor cannot silently break them.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean      | What it times |
|--------------------|----------:|---------------|
| `day06/parseInput` |  53.2 µs  | 50 lines of `"x, y"` through `break` + `read`. |
| `day06/part1`      | 142.5 ms  | 93 632 cells * (50-element sort + tie check); plus 1220 border cells; plus a `Map.fromListWith` count. |
| `day06/part2`      |  16.5 ms  | 93 632 cells * (50-element distance sum). |
| `day06/combined`   | 159.1 ms  | End-to-end from raw string. |

**Total = Parse + Part 1 + Part 2 = 159.0 ms.**

Part 1 dominates Part 2 by roughly 9x. Both walk the same ~94 000 cells, but Part 1's per-cell work (sort + pattern-match the head) is about an order of magnitude heavier than Part 2's per-cell work (sum). The `combined` bench overhead vs. summed is 0.1 ms -- below noise, as expected when the parse is microscopic.

---

## Why the bounding box is enough

The bounding-box trick deserves the rigorous version of the argument, because it is the heart of why Part 1 is computable at all.

### Setup

Let `cs = [c_0, ..., c_{n-1}]` be the input coords, and let `bb = (xMin, xMax, yMin, yMax) = bounds cs`. Let `R_k` be the Voronoi region of coord `c_k` -- the set of cells where `c_k` is the unique nearest under Manhattan distance.

### Lemma 1: if `R_k` extends rightward past `xMax`, then `c_k` owns at least one border cell on the right edge

Suppose there is a cell `(x*, y*)` with `x* > xMax` and `(x*, y*)` belongs to `R_k`. Then for every other coord `c_j = (xj, yj)`:

```
manhattan c_k (x*, y*) < manhattan c_j (x*, y*)
```

Now consider the cell `(xMax, y*)`. The horizontal component of every distance changes by the same amount (`x* - xMax`) when moving from `(x*, y*)` to `(xMax, y*)`, because every input coord has `xj <= xMax`, so `|x* - xj| - |xMax - xj| = (x* - xj) - (xMax - xj) = x* - xMax`. The vertical component is unchanged. So *every distance decreases by exactly* `x* - xMax`, and the *strict* ordering is preserved:

```
manhattan c_k (xMax, y*) < manhattan c_j (xMax, y*)
```

Hence `(xMax, y*)` is also in `R_k`, and it lies on the right border of the bounding box. The same argument applies symmetrically to the other three edges.

### Lemma 2: if `c_k` owns no cell on the bounding-box border, then `R_k` is bounded

Direct contrapositive of Lemma 1. If `R_k` were unbounded, it would extend past one of the four edges of the bounding box, and by Lemma 1 `c_k` would own a corresponding border cell -- contradicting the hypothesis.

### Conclusion

`R_k` is finite iff `c_k` does not own any bounding-box border cell. The set `infinite` in `part1` is therefore *exactly* the set of indices with infinite Voronoi area, and excluding it leaves a list of the finite-area indices and their per-cell counts.

### When the bounding box would not be enough

Two scenarios where the trick does not apply unchanged:

1. **Other distance metrics**. Under Euclidean distance the same lemma fails -- moving a Voronoi cell past the bounding box does not preserve strict orderings, because horizontal and vertical components do not contribute equally. A different geometric argument is needed.
2. **Asking about *infinite* areas**. The bounding box can tell us *which* coords have infinite areas, but cannot give us a meaningful *count*. For Part 1 we only need the maximum finite count, so this is irrelevant.

For Part 2 the argument is different: as established above, moving outside the box monotonically increases every coord's distance, so the total-distance threshold cuts off well within the box.

---

## Possible optimizations

### Two-min scan instead of `sort`

`closest` currently does a full `sort` on 50 (distance, index) pairs to read the smallest two. A linear scan that tracks "best distance, best index, tie flag" runs in O(n) and avoids allocating the intermediate list:

```haskell
closestFast :: [Coord] -> Coord -> Maybe Int
closestFast cs cell = finalize (foldl' step (maxBound, -1, False) (zip [0 ..] cs))
  where
    step :: (Int, Int, Bool) -> (Int, Coord) -> (Int, Int, Bool)
    step (best, bi, tie) (i, c) =
      let d = manhattan c cell
      in case compare d best of
           LT -> (d,    i, False)   -- new strict winner
           EQ -> (best, bi, True)   -- tie at the current best
           GT -> (best, bi, tie)
    finalize (_,    _,  True)  = Nothing
    finalize (_,    bi, False) = Just bi
```

For 50 coords across ~94 000 cells this would shave Part 1 from ~140 ms to roughly ~30 ms. Untested, included as a teaching sketch.

### Voronoi via flood-fill instead of per-cell brute force

A multi-source BFS from all input points outward, stopping at the bounding-box border, can label each cell in amortised O(1) work per cell rather than O(n) (where `n = 50`). For Manhattan distance it requires careful tie-breaking (cells reached at the same step from two seeds are ties), but it is a strict improvement when `n` grows. For 50 input points, the per-cell brute-force factor of 50 is the headline cost; for 500 it would matter a lot.

Both optimisations are sketches -- the current code is fast enough for AoC.

---

## Key patterns

1. **Bounding box + border touch = finite-vs-infinite oracle.** Whenever a Voronoi-style problem gives you *integer points + Manhattan distance + an infinite plane*, the bounding box of the input points is the search space, and "owns a border cell" is the infinite-area test. This trick generalises beyond Day 6.
2. **`sort` + head pattern-match for "second smallest" tie checks.** When you need to know whether the smallest element is unique, sort and pattern-match `(x : y : _)`; the guard `x == y` is a tie. For two values this is the cleanest expression; for a *k*-way tie use `groupBy`.
3. **`length [() | x <- xs, p x]` for counts.** The unit-yield comprehension is the idiomatic "count how many" when you do not need the elements themselves. `filter` is shorter for a single predicate; the comprehension generalises to multiple generators / guards without restructuring.
4. **`type Coord = (Int, Int)` is fine.** Resist the urge to wrap a 2-tuple in a `data` declaration. Records earn their keep when the fields would otherwise be ambiguous (3+ fields, mixed types, or distinct semantic roles).

---

## Side-by-side with the Rust mental model

```rust
type Coord = (i32, i32);

fn manhattan(a: Coord, b: Coord) -> i32 {
    (a.0 - b.0).abs() + (a.1 - b.1).abs()
}

fn closest(cs: &[Coord], cell: Coord) -> Option<usize> {
    let mut dists: Vec<(i32, usize)> = cs
        .iter()
        .enumerate()
        .map(|(i, &c)| (manhattan(c, cell), i))
        .collect();
    dists.sort();
    match dists.as_slice() {
        []                                  => None,
        [(_, i)]                            => Some(*i),
        [(d1, i1), (d2, _), ..] if *d1 == *d2 => None,
        [(_,  i1), ..]                      => Some(*i1),
    }
}

fn part1(cs: &[Coord]) -> usize {
    let (x_min, x_max, y_min, y_max) = bounds(cs);
    let owners: Vec<usize> = (x_min..=x_max)
        .flat_map(|x| (y_min..=y_max).map(move |y| (x, y)))
        .filter_map(|cell| closest(cs, cell))
        .collect();
    let infinite: HashSet<usize> = (x_min..=x_max)
        .flat_map(|x| (y_min..=y_max).map(move |y| (x, y)))
        .filter(|&(x, y)| x == x_min || x == x_max || y == y_min || y == y_max)
        .filter_map(|cell| closest(cs, cell))
        .collect();
    let mut counts: HashMap<usize, usize> = HashMap::new();
    for i in owners {
        if !infinite.contains(&i) {
            *counts.entry(i).or_insert(0) += 1;
        }
    }
    counts.values().copied().max().unwrap_or(0)
}
```

Lined up with Haskell:

| Concept                     | Rust                                              | Haskell                                                                 |
|-----------------------------|---------------------------------------------------|-------------------------------------------------------------------------|
| 2D point                    | `(i32, i32)`                                      | `(Int, Int)` -- via `type Coord = (Int, Int)`                           |
| Manhattan distance          | `(a.0 - b.0).abs() + (a.1 - b.1).abs()`           | `abs (x1 - x2) + abs (y1 - y2)`                                         |
| Index a sequence            | `cs.iter().enumerate()`                           | `zip [0 ..] cs`                                                         |
| Build `(distance, index)`   | `.map(\|(i, &c)\| (manhattan(c, cell), i))`         | `[(manhattan c cell, i) \| (i, c) <- zip [0 ..] cs]`                     |
| Sort tuples by first, then second | `.sort()` (lexicographic on `(i32, usize)`) | `Data.List.sort` (lexicographic on `(Int, Int)`)                        |
| Pattern-match top 2         | `match slice { [a, b, ..] if a.0 == b.0 => ... }` | `(d1, i1) : (d2, _) : _ \| d1 == d2 -> Nothing`                          |
| Grid enumeration            | `.flat_map(...).map(...)`                         | `[(x, y) \| x <- [xMin..xMax], y <- [yMin..yMax]]`                       |
| Filter-map                  | `.filter_map(closest)`                            | `mapMaybe (closest cs)`                                                  |
| Set of infinite indices     | `HashSet<usize>`                                  | `Data.Set.Set Int` -- `Set.fromList`                                     |
| Frequency map               | `*entry.or_insert(0) += 1`                        | `Map.fromListWith (+) [(i, 1) \| ...]`                                   |
| Max over a `HashMap`        | `counts.values().max().unwrap_or(0)`              | `maximum (Map.elems counts)` (with empty-map guard)                     |
| Total distance              | `cs.iter().map(\|&c\| manhattan(c, cell)).sum()`    | `sum [manhattan c cell \| c <- cs]`                                      |
| Count cells under threshold | `cells.iter().filter(\|...\|...).count()`           | `length [() \| cell <- ..., totalDistance cs cell < threshold]`           |

Both implementations sort 50 distances per cell and walk the same grid. The Rust version pays for the `Vec` allocation per cell that the `closestFast` Haskell sketch above would also pay (until the optimiser fuses it). The Haskell `Map.fromListWith (+)` and Rust `HashMap::entry` are exact analogues -- one builds a `Map` from a list, the other accumulates inline.

---

**Navigation**: [Problem statement](day06.md) | [Summary table](summary_2018.md) | [<- Day 5](day05_function_guide.md) | [Day 7 ->](day07_function_guide.md)
