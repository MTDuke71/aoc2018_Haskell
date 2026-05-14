# Day 12: Subterranean Sustainability -- Function Guide

**Problem**: A 1-D cellular automaton on an infinite row of pots numbered `..., -2, -1, 0, 1, 2, ...`.  Each pot is alive (`#`) or empty (`.`).  Rules of the form `LLCRR => N` determine, for every 5-cell neighbourhood, whether the centre is alive in the next generation.  Part 1 asks for the sum of live pot indices after **20** generations.  Part 2 asks for the same after **50,000,000,000** generations.
**Answers**: Part 1 = **`3230`**, Part 2 = **`4400000000304`**
**Runtime** (mean, criterion `-O2`): Parse = **8.92 µs** | Part 1 = **290.4 µs** | Part 2 = **2.806 ms** | **Total = 3.11 ms**
**Code**: [Day12.hs](../../src/Day12.hs)
**Tests**: [Day12Spec.hs](../../test/Day12Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day12"`
**Problem statement**: [day12.md](day12.md)

**New concepts this day** (beyond Days 0--11):

- **1-D cellular automaton with a 5-cell neighbourhood.**  Same shape as Conway's Game of Life but one-dimensional, and the rule table is *given* in the input rather than fixed.  Day 18 (lumber collection area) reuses the pattern with a 9-cell neighbourhood and a different stabilisation flavour.
- **Sparse state via `Set Int`.**  The pots live on an infinite tape, but only a few hundred are ever alive.  Storing the *live* indices in a `Set Int` lets us cover negative pot numbers for free and skips the dead majority of the tape -- a strictly better fit than a `String` or `UArray` for this puzzle's shape.
- **Translation-equivariance of a local rule.**  If `f` depends only on a fixed-width window, then `f` commutes with translation: `step (shift k s) == shift k (step s)`.  This is the algebraic foundation of the period-1 cycle detection in Part 2.
- **Fixed-point detection over astronomically many generations.**  The state's *shape* (normalised by subtracting the leftmost live index) stabilises after a few hundred generations; from that point the live region just slides by a constant offset per step.  Compare consecutive normalised shapes; the first time they match, project to generation `50_000_000_000` arithmetically.  This same trick reappears on Day 18.
- **`Set.mapMonotonic`.**  The `Set` API has a fast path for strictly-monotonic functions: it knows the element order is preserved and rebuilds the tree in `O(n)` without re-sorting.  Used here to translate a live set in linear time.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Why 50 billion generations forces the algorithm](#why-50-billion-generations-forces-the-algorithm)
3. [The algorithm in Python](#the-algorithm-in-python)
4. [Data model](#data-model)
5. [`parseInput`](#parseinput)
6. [`window` and `step`](#window-and-step)
7. [`sumPots` and `normalize`](#sumpots-and-normalize)
8. [`runFor` and Part 1](#runfor-and-part-1)
9. [`extrapolate` and Part 2](#extrapolate-and-part-2)
10. [`part1`, `part2`, `solve`](#part1-part2-solve)
11. [Tests](#tests)
12. [Benchmarks](#benchmarks)
13. [Why translation-equivariance lets us extrapolate](#why-translation-equivariance-lets-us-extrapolate)
14. [What the algorithm finds: a spaceship](#what-the-algorithm-finds-a-spaceship)
15. [Possible optimizations](#possible-optimizations)
16. [Key patterns](#key-patterns)
17. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)
18. [Further reading](#further-reading)

---

## Problem summary

The input has two parts:

```
initial state: ####..##.##..##..#..###..#....#.######..############.#...#.##..####.###.#.###.###..#.####..#.#..##..#

.#.## => .
...## => #
..#.. => .
...
```

The first line lists the initial state, beginning at pot 0 and extending rightward.  Subsequent (32) lines spell out the transition rule for *every* 5-cell window (`#` and `.`, all 32 combinations).  Pots outside the initial state -- including all negative-indexed pots -- start empty.

Each generation, every pot's new state is determined by its current state and the four pots immediately around it (two left, two right):

```
generation g    pots:  ..., x[i-2], x[i-1], x[i], x[i+1], x[i+2], ...
                                    \____________ window __________/
                                                 |
                                          rules[window]
                                                 |
                                                 v
generation g+1  pots:                          x'[i]
```

Part 1 asks for `sum [i | pot i is alive at gen 20]`.  Part 2 asks for the same at gen `50,000,000,000`.

The worked example in the puzzle uses an initial state of `#..#.#..##......###...###` and converges to a sum of **325** after 20 generations.  That is the spec test in `Day12Spec.hs`.

---

## Why 50 billion generations forces the algorithm

Part 1 is trivially simulatable: 20 generations, each a single pass over a couple hundred pots.  `runFor rules 20 initial` finishes in 290 µs.

Part 2 demands `5 × 10^10` generations.  At 290 µs per 20 generations -- ~15 µs per generation -- a naive simulation would take roughly `15 µs × 5 × 10^10 ≈ 8.6 years`.  Not a typo.

So Part 2 needs an algorithmic insight, not a constant-factor optimisation.  The insight is **fixed-point detection**: after roughly 100--200 generations on every real AoC 2018 Day 12 input I've seen, the live region settles into a **rigid shape that translates by a constant offset per generation**.  Once you spot that the *normalised* shape is the same as the previous generation's, the rest is arithmetic:

```
sum at gen target = sum at gen g + (target - g) * count * shift
```

where `count` is the (now-fixed) number of live pots and `shift` is how many pots the shape moved in one step.  On my input the stabilisation kicks in around generation 125; we exit the simulator loop there and finish Part 2 in ~2.8 ms total.

The function-guide section ["Why translation-equivariance lets us extrapolate"](#why-translation-equivariance-lets-us-extrapolate) below proves that the extrapolation is exact, not just empirical.

---

## The algorithm in Python

Before walking the Haskell, here is the same algorithm in Python -- short enough to read in one sitting and free of language ceremony.  The full file lives at [python/day12.py](../../python/day12.py); the Haskell that follows is a transliteration of these same six functions.

```python
TARGET = 50_000_000_000

def parse(text):
    lines = text.splitlines()
    initial = {
        i for i, c in enumerate(lines[0][len("initial state: "):])
        if c == "#"
    }
    rules = {line[:5] for line in lines[2:] if line and line[9] == "#"}
    return initial, rules

def window(state, i):
    return "".join("#" if (i + d) in state else "." for d in range(-2, 3))

def step(state, rules):
    if not state:
        return set()
    lo, hi = min(state) - 2, max(state) + 2
    return {i for i in range(lo, hi + 1) if window(state, i) in rules}

def normalize(state):
    if not state:
        return frozenset()
    m = min(state)
    return frozenset(i - m for i in state)

def part1(initial, rules):
    state = initial
    for _ in range(20):
        state = step(state, rules)
    return sum(state)

def part2(initial, rules):
    prev, cur = initial, step(initial, rules)
    g = 1
    while g < TARGET:
        if normalize(prev) == normalize(cur):
            count = len(cur)
            shift = min(cur) - min(prev)
            remaining = TARGET - g
            return sum(cur) + remaining * count * shift
        prev, cur = cur, step(cur, rules)
        g += 1
    return sum(cur)
```

Reads top-to-bottom in about a minute.  Six functions, no classes, no decorators, no comprehension tricks beyond a set-comp and a generator-comp.

### The data structures

- **`initial`** is a `set` of pot indices that start with a plant.  Membership is `O(1)` average via Python's hash table.  Negative pot numbers are fine -- the set has no notion of "out of bounds."
- **`rules`** is a `set` of 5-character strings.  Each string is one of the productive LHS patterns -- the ones whose rule's RHS is `#`.  The parser drops `... => .` rules entirely; their absence from the set is what causes the corresponding pot to die.

That is it.  No grid, no array, no "infinite tape" data structure.  The infinite tape is implicit: a pot exists iff its index is in `initial` (or, later, in some descendant of it).  The Haskell solution uses the same two sets, with `set` → `Set Int` for the live pots and `set` → `Set String` for the rules.

### What each function does

1. **`parse(text)`** -- slice off the `"initial state: "` prefix to read the starting live set; for each remaining non-empty line, keep the rule's LHS (first 5 chars) only if its RHS (character at index 9) is `#`.

2. **`window(state, i)`** -- build the 5-character snapshot centred on pot `i`.  Pure I/O: five set-membership tests glued into a string.

3. **`step(state, rules)`** -- one generation.  The candidate range is `[min - 2, max + 2]` because any pot beyond that boundary has a window of `.....`, and `.....` produces `.` on every real input.  Inside that range, a pot survives into the next generation iff its window is in `rules`.

4. **`normalize(state)`** -- subtract the minimum so the leftmost live pot lands at index 0.  This is what lets us compare *shapes* between generations.  Returns a `frozenset` because it is going to be compared for equality and possibly hashed -- a frozen set can be a dict key, a regular set cannot.

5. **`part1`** -- the obvious thing: simulate 20 generations, sum the result.

6. **`part2`** -- the algorithmically interesting one:

   - Step generation by generation, tracking the *previous* and *current* states.
   - After each step, ask: does the current shape match the previous shape (modulo translation)?  If yes, we have hit the period-1 translating fixed point that this puzzle is designed around.
   - Once the shapes match, every future generation translates the live set by the same `shift = min(cur) - min(prev)` and grows the sum by `count * shift`.  So the answer at generation `TARGET` is `sum(cur) + remaining * count * shift`.
   - If we somehow reach `TARGET` without ever detecting a cycle (we won't on a real input), fall back to the running simulation result.

### The Haskell that follows

Every section from [Data model](#data-model) onward maps to one piece of this Python:

| Python | Haskell section |
|--------|------------------|
| `initial`, `rules` -- the two sets | [Data model](#data-model) |
| `parse` | [`parseInput`](#parseinput) |
| `window`, `step` | [`window` and `step`](#window-and-step) |
| `sum`, `normalize` | [`sumPots` and `normalize`](#sumpots-and-normalize) |
| `part1` -- iterate 20 times | [`runFor` and Part 1](#runfor-and-part-1) |
| `part2` -- cycle detect + extrapolate | [`extrapolate` and Part 2](#extrapolate-and-part-2) |

The Python is the spec; the Haskell is the same shape with stricter types and a few performance trims.  If a Haskell explanation gets confusing, jump back here -- the Python line will usually clarify what is being computed.

---

## Data model

```haskell
data Puzzle = Puzzle
  { initial :: !(Set Int)
  , rules   :: !(Set String)
  } deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle a b) = a `seq` b `seq` ()
```

Two `Set`s, both strict by `Set`'s spine-strict construction (and explicit `!` bangs on the fields for documentation):

- **`initial :: Set Int`** -- the indices of pots that contain a plant at gen 0.  No upper bound is stored; pots not in the set are empty.  Negative indices appear naturally as soon as the rules light up `i = -1` or below.
- **`rules :: Set String`** -- the 5-character window patterns whose right-hand side is `#`.  Patterns whose RHS is `.` are *absent* from the set; "not in `rules`" is equivalent to "produces an empty pot."  This halves the average lookup cost and trims the `Set` to ~14 entries on the worked example and ~17 on my real input.

### Why `Set String` and not `Set [Bool]` or `UArray Word8 Bool`

Three choices, ranked by tradeoff:

| Representation                | Pros                                                    | Cons                                                            |
|-------------------------------|---------------------------------------------------------|------------------------------------------------------------------|
| `Set String` (current)        | Trivial parse, trivial `window`, no encoding step       | `String` is `[Char]` -- five allocations + a `Set.member` walk per query (`O(log n)` comparisons of 5 chars each = ~25 char compares). |
| `Set [Bool]`                  | Slightly smaller than `String`                          | Same allocation pattern, no real win                             |
| `UArray Word8 Bool` indexed 0..31 | One `Word8` per query, `O(1)` lookup                | Needs an encoder (5 bits → `Word8`) and decoder for the parser   |

The current code's "hot path" cost is `Set.member (window s i) rules`.  `window` builds a 5-character `String` per call -- about 5 cons cells and a comparison -- and `Set.member` does an `O(log 32) ≈ 5` comparisons through the tree.  At the ~1000 `step` calls × 200-pot windows we make in Part 2, that is ~10^6 `String` builds and ~10^6 `Set.member` walks.  Total: about 3 ms (most of the time we measure is Part 2's simulation loop running until cycle detection).

A `UArray Word8 Bool` lookup would drop this to about ~10 cycles per query, plausibly shaving Part 2 to under 1 ms.  We document the optimisation in the sidebar but keep the `String` version for readability.

### Why both `Set`s are strict in the `Puzzle`

Criterion's `nf` deep-evaluates `parseInput`'s output to subtract laziness from the timing.  The `!` bangs on the record fields plus the hand-rolled `NFData` make the `nf` correspondence honest -- the parse work is credited to Parse, not to Part 1 / Part 2.  Without it, `parseInput`'s laziness would defer the `Set.fromList` work into the first query, inflating the per-part numbers.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput raw = case lines raw of
  []                -> Puzzle Set.empty Set.empty
  initLine : rest   ->
    let initStr = drop 15 initLine  -- length "initial state: " == 15
        initSet = Set.fromList [i | (i, '#') <- zip [0 ..] initStr]
        ruleSet = Set.fromList
                    [ take 5 ln
                    | ln <- filter (not . null) rest
                    , length ln >= 10
                    , ln !! 9 == '#'
                    ]
    in  Puzzle initSet ruleSet
```

Three threading-of-data tricks worth dwelling on.

### `case` over `let`-pattern

The body destructures `lines raw` as `initLine : rest`.  With a `let`-pattern binding (`let (initLine : rest) = lines raw`), GHC emits a `-Wincomplete-uni-patterns` warning -- the empty list is unmatched.  Wrapping it in a `case` with the explicit empty branch silences the warning and documents the empty-input fallback (return an empty puzzle).

For real puzzle inputs the empty branch is unreachable.  The warning-clean alternative -- a `case` -- is one extra line of code and zero runtime cost, since GHC inlines the case into the single live branch when used.

### `[i | (i, '#') <- zip [0..] initStr]`

A list-comprehension idiom worth filing away.  `zip [0..] initStr` pairs each character with its index; the pattern `(i, '#')` in the generator is *both* a binding and a filter -- only tuples whose second component is `'#'` survive, and from those we keep `i`.

This is the same shape as Day 4's `[(t, parseTime) | line <- lines, let parseTime = ...]` but using pattern-match filtering instead of a `guard`.  The equivalent with explicit guards:

```haskell
[ i | (i, c) <- zip [0..] initStr, c == '#' ]
```

The pattern-match form is slightly more efficient (the `Char` comparison is fused into the pattern) and slightly more idiomatic.

### `ln !! 9 == '#'` to detect productive rules

Each rule line is `LLCRR => N` -- exactly 10 characters: 5 for the window, ` ` at 5, `=` at 6, `>` at 7, ` ` at 8, and the result `#` or `.` at index 9.  Filtering by `ln !! 9 == '#'` keeps only rules whose RHS is `#`, since rules of the form `... => .` would not contribute any new live pot.

The `length ln >= 10` guard is belt-and-suspenders: `filter (not . null) rest` should already eliminate the blank line, but the length check ensures `ln !! 9` never indexes past a stray short line.

### Why the parser dominates the bench at 8.92 µs

Almost all 8.92 µs goes to building two `Set`s.  `Set.fromList` is `O(n log n)` in the input size; with 100 initial pots and 32 rules, that is ~700 comparisons.  The real cost is the allocations -- balanced-binary-tree nodes are not free.

The `length ln >= 10` check is `O(|ln|)` per line, but at 32 lines × 10 characters each, it is invisible.

---

## `window` and `step`

```haskell
window :: Set Int -> Int -> String
window s i = [ if Set.member j s then '#' else '.' | j <- [i - 2 .. i + 2] ]

step :: Set String -> Set Int -> Set Int
step rs s
  | Set.null s = Set.empty
  | otherwise =
      let !lo = Set.findMin s - 2
          !hi = Set.findMax s + 2
      in  Set.fromList
            [ i
            | i <- [lo .. hi]
            , window s i `Set.member` rs
            ]
```

The two-function core of the simulator.

### `window` builds a 5-cell snapshot

For pot index `i`, build the 5-character string `[i-2, i-1, i, i+1, i+2]` where each position is `#` or `.` based on `Set.member j s`.  Five `Set.member` lookups, each `O(log |s|) ≈ O(log 100) ≈ 7` comparisons.  This is the inner-loop primitive of `step`.

The list comprehension here is sugar for `map (\j -> if Set.member j s then '#' else '.') [i-2 .. i+2]`.  GHC fuses the comprehension into the consumer (the `Set.member` call in `step`), so no intermediate list materialises for the 5-character string in the steady state.

### Why `step` only scans `[min - 2 .. max + 2]`

A pot at index `j` outside `[min - 2, max + 2]` has `window s j == "....."` -- it has no live neighbours within range.  On every real puzzle input the rule `..... => .` is present (otherwise the universe would spawn infinite life from any vacuum), so such a pot cannot become alive.

The bang patterns `!lo = Set.findMin s - 2` / `!hi = Set.findMax s + 2` force the bounds upfront; without them the lazy `[lo .. hi]` enumerator would re-evaluate the `Set.findMin` / `Set.findMax` thunks at every consumer demand.

### Why `Set.null s` is the recursive base case

If the input becomes empty (no live pots), every window is `"....."`, every rule produces `.`, and the next generation is also empty.  Bailing out with `Set.empty` keeps the `Set.findMin` / `Set.findMax` calls safe (they crash on an empty `Set`).

In practice this branch never fires on real inputs -- the live region drifts but never empties.  It is here for correctness, not performance.

### The cost of one `step` call

For my input, each generation has ~100 live pots in a span of ~150 positions.  So `step` does ~150 iterations of:

- One `Set.findMin` + one `Set.findMax`: `O(log 100) ≈ 7` each.
- 150 × `window` calls: each one does 5 × `O(log 100)` = ~35 comparisons.  Total: ~5,000 comparisons.
- 150 × `Set.member ... rs` calls: each one does `O(log 17) ≈ 5` comparisons.  Total: ~750 comparisons.
- A final `Set.fromList` of ~100 surviving pots: `O(100 log 100) ≈ 700` comparisons.

Roughly 6500 comparisons per generation.  At a few nanoseconds per comparison plus allocation overhead, that is ~30 µs per generation -- which lines up with Part 1's 290 µs / 20 generations = 14.5 µs per generation (the timing is a touch faster because GHC fuses some of the comprehensions).

---

## `sumPots` and `normalize`

```haskell
sumPots :: Set Int -> Int
sumPots = Set.foldl' (+) 0

normalize :: Set Int -> Set Int
normalize s
  | Set.null s = Set.empty
  | otherwise  = let !m = Set.findMin s in Set.mapMonotonic (subtract m) s
```

### `Set.foldl'`

The strict left fold over a `Set` traverses the tree in ascending key order, accumulating each element into the running sum.  `foldl'` (with the bang) keeps the `Int` accumulator in WHNF; without the strict variant, GHC would build a tower of unevaluated `0 + i1 + i2 + ...` thunks across the whole set.

We met `foldl'` on lists from Day 0 onward; `Set.foldl'` is the same combinator specialised to `Set`.

For `Int`, an alternative is `sum . Set.toList`, which `Data.List.sum` *does* implement strictly under `Prelude.sum`'s `Numeric` -- but it goes through an intermediate list (allocation pressure), so the direct `Set.foldl'` is preferred.

### `Set.mapMonotonic`

```haskell
Set.mapMonotonic :: (a -> b) -> Set a -> Set b
```

The "trust me, this function is strictly increasing" variant of `Set.map`.  When `f x < f y` whenever `x < y`, the output set has the same shape as the input -- no rebalancing needed -- and `mapMonotonic` rebuilds the tree in linear time.  `Set.map`'s general version does a `Set.fromList`, `O(n log n)`.

`subtract m` is strictly increasing for any `m`: for `x < y`, `(x - m) < (y - m)`.  So `mapMonotonic` is the right tool.

The `!m` bang forces the minimum eagerly; without it `Set.mapMonotonic (subtract m) s` would carry a deferred `Set.findMin s` inside every key.

### Why normalize?

The point of `normalize` is to compare *shapes* up to translation.  Two states that differ only by a uniform offset have the same normalised form: `normalize {3, 7, 10} == normalize {103, 107, 110} == {0, 4, 7}`.  In `extrapolate`, we use this to detect when consecutive generations have the same shape.

`Set.mapMonotonic` is what makes this comparison cheap enough to do at every generation: an `O(n)` translation per check instead of an `O(n log n)` rebuild.

---

## `runFor` and Part 1

```haskell
runFor :: Set String -> Int -> Set Int -> Set Int
runFor rs n = (!! n) . iterate (step rs)

part1 :: Puzzle -> Int
part1 (Puzzle s0 rs) = sumPots (runFor rs 20 s0)
```

The `iterate f x !! n` idiom is the canonical "apply `f` exactly `n` times" combinator.  `iterate f x = [x, f x, f (f x), ...]` is a lazy infinite list of repeated applications; `!! n` walks `n` steps in and returns that element.

GHC fuses the `iterate` / `!!` pair into a tail-recursive loop -- no list ever materialises.  The cost is exactly `n` calls to `step`, each forcing the previous state to a fully-evaluated `Set Int` because `step` pattern-matches on it (via `Set.null`).  No thunk accumulation across generations.

For Part 1 with `n = 20`, the cost is 20 × ~14 µs ≈ 290 µs, matching the bench.

### Why not just write the recursion?

The hand-rolled equivalent would be:

```haskell
runFor :: Set String -> Int -> Set Int -> Set Int
runFor _  0 s = s
runFor rs n s = runFor rs (n - 1) (step rs s)
```

Identical at runtime -- GHC compiles both to the same loop.  `iterate ... !! n` is the more idiomatic Haskell phrasing and reads as "the `n`-th iterate."  Same shape will appear on Day 18.

---

## `extrapolate` and Part 2

```haskell
extrapolate :: Set String -> Int -> Set Int -> Int
extrapolate rs target s0
  | target <= 0 = sumPots s0
  | otherwise   = go 1 s0 (step rs s0)
  where
    go !g !prev !cur
      | g >= target = sumPots cur
      | normalize prev == normalize cur =
          let !count     = Set.size cur
              !shift     = Set.findMin cur - Set.findMin prev
              !remaining = target - g
          in  sumPots cur + remaining * count * shift
      | otherwise = go (g + 1) cur (step rs cur)
```

The heart of Part 2.  Three things to dwell on.

### The walking-window invariant

At every recursive call, `prev = state at gen (g - 1)` and `cur = state at gen g`.  So `g = 1` corresponds to one application of `step` to `s0`; `g = k` corresponds to `k` applications.  This shape is critical for the cycle-detection check:

`normalize prev == normalize cur` is true *iff* the transition from gen `(g - 1)` to gen `g` produced a shape congruent (up to translation) to its predecessor.  By translation-equivariance ([proof below](#why-translation-equivariance-lets-us-extrapolate)), every *subsequent* transition will also produce the same shape translated by the same offset.  We have found a period-1 fixed point in the *shape* domain.

### The arithmetic projection

Once the shape stabilises at gen `g`, the sum at gen `g + k` is:

```
sumPots state_{g+k} = sumPots state_g + k * (count * shift)
```

where `count = |state_g|` and `shift = min state_g - min state_{g-1}`.

Why?  Each subsequent generation translates the live set by exactly `shift` more.  The sum of the live indices grows by `count * shift` per generation (each of the `count` indices increases by `shift`).  Linear extrapolation.

`remaining = target - g`, so `sumPots cur + remaining * count * shift` reads as "the current sum, plus `count * shift` more for each of the `remaining` generations to come."

### Why `g >= target` (not `g == target`)

A safety hedge.  In the common case the cycle detection fires at some `g < target` and we never reach the `g >= target` branch.  But if for some weirdly contrived input the simulation runs all the way to `g == target` without ever stabilising, we still want a defined answer.  `>=` handles "what if `target = 0` but I started simulating anyway" via the outer guard, and "what if the simulation walked past target somehow" -- belt-and-suspenders.

### Bang patterns on `count`, `shift`, `remaining`

Each one is read exactly once in the final expression `sumPots cur + remaining * count * shift`.  Without the bangs the laziness is harmless, but spelling them out makes the strictness intent explicit and protects against a future refactor that uses one of them more than once.

### How fast in practice

On my input the cycle detection fires at generation 125 (confirmed by [python/day12_trace.py](../../python/day12_trace.py)).  125 calls to `step` × ~14 µs/generation = ~1.75 ms -- plus ~125 × `normalize` calls (~1 µs each = ~0.1 ms) and 125 × `Set.fromList` allocations in `step`.  Total ~2.8 ms, lining up with the bench.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Puzzle -> Int
part1 (Puzzle s0 rs) = sumPots (runFor rs 20 s0)

part2 :: Puzzle -> Int
part2 (Puzzle s0 rs) = extrapolate rs 50000000000 s0

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
```

Three small notes:

1. **Both parts re-derive from the parsed `Puzzle`.**  `part1` does not call `extrapolate` because at `target = 20` the cycle has almost certainly not fired yet (and even if it had, `runFor` is conceptually clearer for the small-horizon case).  Sharing the simulation between the two parts would shave maybe 100 µs off the bench -- not worth the structural complication.

2. **`50_000_000_000 :: Int` is fine on a 64-bit platform.**  `Int` is at least 64 bits in any GHC build we care about, so `5 × 10^10` fits with 18 orders of magnitude to spare.  On a 32-bit platform we would need `Int64`.  The bench host is 64-bit Windows, so we are safe.

3. **`solve` shares the parse via the `let` binding.**  `puzzle` is bound once and used for both parts; the rules and initial state are parsed once, queried twice.  The combined bench inlines `parseInput` inside `nf`, which re-parses on each iteration -- which is why `combined = 3.36 ms` is slightly more than `Total = 3.11 ms`.

---

## Tests

Coverage in [Day12Spec.hs](../../test/Day12Spec.hs):

1. **`parseInput`** -- extracts the correct initial set from the worked example, keeps 14 productive rules, drops `... => .` rules.
2. **`window`** -- always five characters wide, centres on `i` reading `[-2..+2]`, returns `"....."` when no live pot is within 2.
3. **`step`** -- produces the documented gen-1 live set from the puzzle's worked example.  This is the cross-check that the rule table and window indexing line up correctly; if the window is off by one, this test trips.
4. **`runFor` / `part1`** -- the worked example sums to **325** after 20 generations.
5. **`extrapolate`** -- agrees with `runFor` on small horizons (targets 20 and 50); returns the initial sum at `target = 0`.
6. **`normalize`** -- translates to start at 0, is identity on already-normalised sets, handles the empty set.
7. **Actual input** -- pinned `expectedPart1 = 3230`, `expectedPart2 = 4400000000304`.

The agreement test (5) is the one I am most happy about.  It exercises the cycle-detection path on the *same input* as the brute-force `runFor` path and checks they produce the same answer on a horizon long enough to trigger the cycle on the worked example.  If we ever refactor `extrapolate`'s arithmetic, this test catches a sign error or off-by-one immediately.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean      | What it times |
|--------------------|----------:|---------------|
| `day12/parseInput` | 8.923 µs  | `lines` + two `Set.fromList` builds (~100 initial pots, ~17 productive rules). |
| `day12/part1`      | 290.4 µs  | 20 calls to `step` -- ~14.5 µs per generation. |
| `day12/part2`      | 2.806 ms  | 125 calls to `step` (until cycle detection at gen 125) + an O(n) `normalize` per step. |
| `day12/combined`   | 3.356 ms  | End-to-end from raw string -- approximately Parse + Part 1 + Part 2. |

**Total = Parse + Part 1 + Part 2 = 3.105 ms.**

Three observations from the numbers.

### Part 2 / Part 1 ratio is ~9.7×, not 2.5 × 10^9

The naive ratio -- `50_000_000_000 / 20 = 2.5 × 10^9` -- is what brute force would cost.  We get `~9.7×` instead because cycle detection short-circuits at generation 125: `125 / 20 ≈ 6.25×` more simulation work than Part 1, plus the `normalize` comparison overhead at each step.  This 6× ratio is the *real* "asymptotic constant" of Part 2 on this puzzle.

### The `normalize` cost

`normalize` is called twice per generation in `extrapolate` -- once on `prev`, once on `cur`.  On my input that is 125 generations × 2 = 250 `normalize` calls.  Each one is `Set.findMin` + `Set.mapMonotonic`, roughly `O(n) ≈ 88` operations (the steady-state live-pot count).  Total: ~22,000 operations across the run, less than 0.1 ms.

If we were paranoid, we could cache `normalize cur` across iterations (the next iteration's `prev` *is* the previous iteration's `cur`), shaving the work in half.  Not worth the complication at 2.8 ms.

### Combined ≈ Total

`combined = 3.36 ms`, `Total = 3.11 ms` -- a 0.25 ms gap.  This is the per-iteration cost of `parseInput`'s `Set.fromList` builds that the cached parts amortise away.  At a 3 ms scale the gap is in the noise; use `Total` as the headline figure.

---

## Why translation-equivariance lets us extrapolate

The claim is:

> If `step rs prev` and `step rs cur` produce the same shape up to translation -- and `cur = step rs prev` -- then *every* subsequent generation also has that same shape, translated by the same offset.

This deserves a real argument.

### The shift operator

Define translation: `shift k s = Set.map (+ k) s`.  (On `Set Int`, this is `Set.mapMonotonic (+ k)` if `k > 0` else `Set.mapMonotonic (subtract (-k))`; the algebra below is invariant to which is used.)

For any local rule `step rs` -- where the next state of pot `i` depends only on a fixed-width window around `i` in the current state:

```
step rs (shift k s) = shift k (step rs s)
```

In words: translating then stepping is the same as stepping then translating.

The proof is just unfolding the definition.  `step rs s = { i | window s i `member` rs }`.  Then:

```
step rs (shift k s)
  = { j | window (shift k s) j `member` rs }      -- definition of step
  = { j | window s (j - k) `member` rs }          -- window depends on relative positions
  = { i + k | window s i `member` rs }            -- substitute i = j - k
  = shift k (step rs s)                           -- definition of shift
```

The crucial step is `window (shift k s) j == window s (j - k)`: shifting the whole set by `k` is the same as shifting the *index of inquiry* by `-k`.  This is immediate from `window`'s definition (a local lookup over `[j - 2 .. j + 2]`).

### From equivariance to extrapolation

Suppose at some generation `g` we detect `normalize prev == normalize cur`.  That is, `cur = shift d prev` for some integer `d = min cur - min prev`.  Then by equivariance:

```
state_{g+1}
  = step rs cur
  = step rs (shift d prev)
  = shift d (step rs prev)
  = shift d cur                              -- because prev's next is cur
```

So `state_{g+1} = shift d cur`.  Repeating, `state_{g+k} = shift (k * d) cur` for every `k ≥ 0`.

The sum of a shifted set is the original sum plus `|s| * d`:

```
sum (shift d s) = sum {i + d | i in s} = sum s + |s| * d
```

So `sumPots state_{g+k} = sumPots cur + k * count * shift`, with `count = |cur|`, `shift = d`.  Substituting `k = target - g`:

```
sumPots state_target = sumPots cur + (target - g) * count * shift
```

Which is *exactly* the formula `extrapolate` evaluates.  The extrapolation is *not* a heuristic -- it is the closed-form consequence of equivariance plus the observed period-1 stabilisation.

### What about higher-period cycles?

The argument above assumed `cur = shift d prev` -- a *period-1* cycle in the shape domain.  If instead the shape settles into period 2 (alternating between two shapes), `normalize prev == normalize cur` would never fire.  A more general detector would track the normalised shape of *every* past generation in a `Map (Set Int) (Int, Int, Int)` and fire on the first repeat.

On every AoC 2018 Day 12 input I have seen the period is 1.  The function-guide sidebar [Possible optimizations](#possible-optimizations) documents the period-`k` generalisation; the current solver intentionally favours simplicity over generality.

---

## What the algorithm finds: a spaceship

The translating fixed point we detect has a name in the cellular-automata literature.  It is a **spaceship**: a pattern that returns to its original shape after some number of generations, but translated by a nonzero vector.  Everyone who has played with Conway's Game of Life has seen one -- the **glider**, a 5-cell pattern that returns to its initial shape every 4 generations, shifted by `(1, 1)`:

```
gen 0:    .#.        gen 1:    ...        gen 2:    .#.        gen 3:    ..#        gen 4:    ...
          ..#                  #.#                  ..##                 .##                  #.#
          ###                  .##                  .#.                  .#.                  .##
                               .#.                                       ..#                  .#.
```

After 4 steps the glider is back to its starting shape, one cell down and one cell to the right.  We say it has **period 4** and **velocity `(1, 1) / 4`** -- it moves diagonally at speed `c/4`, where `c` is the "speed of light" in CA-land (the maximum rate at which information can propagate per generation, equal to the window's half-width).

### Day 12 finds a 1-D spaceship at half-lightspeed

The stable shape that emerges at generation 125 on the real input is a **period-1 spaceship** with **velocity `+1` pot per generation** -- 88 live plants in a periodic `#..##.#..##.` motif that translates right by exactly one pot each step.  (See [python/day12_trace.py](../../python/day12_trace.py) for the full congealing-out-of-chaos trace.)

Four immediate facts fall out of naming the pattern:

1. **The speed of light in this CA is 2, not 1.**  Information propagates at most `window_half_width` cells per generation -- two cells here, because the window covers `[i-2, i+2]`.  So the *theoretical* maximum spaceship velocity for Day 12 is `±2 / gen`.  The puzzle's stable shape moves at `+1 / gen`, i.e. **half the speed limit**.

   Is a `±2` spaceship achievable in principle?  Yes -- but only with rules of a specific shape.  For `shift = +2`, the new leftmost pot is at position `m + 2`, where `m` was the old leftmost.  That pot's window is `[m, m+1, m+2, m+3, m+4]` -- starting with `#` because `m` is alive.  So a productive rule of form `#xxxx => #` must exist, and the surrounding `..#yz / .#xyz` rules must *not* fire for the corresponding pots.  Your input has **5 productive rules of form `#xxxx`** (`####.`, `##.#.`, `#.#.#`, `#..#.`, `#...#`), so the necessary precondition is met -- yet across all 125 generations of the simulation, the configuration never lines up.  The combinatorial requirement (a single `#xxxx` rule firing while the `..#`/`.#` neighbours simultaneously die) is too restrictive.  Empirically, all observed shifts in the trace are `∈ {-1, 0, +1}`; +2 / -2 are *possible* but never *occur*.

   See the `PRODUCTIVE RULES` and `SPEED-LIMIT ANALYSIS` sections at the top of [python/day12_trace_output.txt](../../python/day12_trace_output.txt) for the rule-by-rule breakdown.

2. **Conway's Game of Life doesn't achieve lightspeed either.**  CGoL uses a 3-cell window (Moore neighbourhood, half-width 1), so *its* speed of light is `c = 1`.  Yet the fastest known CGoL spaceships move at `c/2` orthogonal (LWSS/MWSS/HWSS, period 4, velocity `(2,0)/4`) and `c/4` diagonal (the glider).  No `c`-velocity spaceship exists in CGoL; it's been proven impossible by the B3/S23 rules.  So both CAs we are discussing fall *short* of their respective speed limits -- a recurring theme in CA research.

3. **Period-1 spaceships are impossible in CGoL but easy here.**  Any 2-D pattern that "shifts by exactly one cell in one step" would require simultaneous birth at the leading edge and simultaneous death at the trailing edge, which CGoL's B3/S23 rules cannot sustain together.  That is why the glider has to be period-4: three "rearranging" generations between each shape-repetition.  In 1-D with a 5-cell window, period-1 spaceships are common -- the rule table has many more degrees of freedom (`2^32` possible rule tables instead of CGoL's single fixed rule).

4. **Day 12 is a "find the spaceship" puzzle.**  Rephrased:

   > Given an initial state and a CA rule, find the spaceship the system evolves into and compute its position 50 billion generations later.

   On the real input the first **125 generations** are the *chaotic transient phase*: the live region grows, shrinks, oscillates, and otherwise rearranges itself.  Then the spaceship locks in -- 88 live plants moving at velocity `+1` per generation, contributing `count * shift = 88` to the sum every step -- and the system is in steady-state forever after.  Cycle detection is the bridge from the chaotic phase ("simulate it") to the steady-state phase ("apply algebra").

   The helper script [python/day12_trace.py](../../python/day12_trace.py) prints the normalised pattern, the leftmost pot's position, and the per-generation shift for every generation until the cycle locks in.  Running it on the real input shows the spaceship congealing out of static around gen 100 and stabilising at gen 125, then the full extrapolation arithmetic at the bottom.  Recommended viewing for the "huh, I can *see* it form" moment.

### Why the formula has the shape it does

Once you see the system as a spaceship, the extrapolation formula is no longer a clever trick -- it is the obvious closed-form expression for "where will the spaceship be at time `target`?"

Let `cur` be the live set at the moment the spaceship locks in (generation `g`).  The puzzle's answer is the **sum of pot indices** of live plants, not the *count* of plants -- and this is the key:

```
sum_{i in shift(k, cur)} i  =  sum_{i in cur} (i + k)
                            =  sum_{i in cur} i  +  count * k
                            =  sum(cur)         +  count * k
```

Each of the `count` plants contributes `+k` to the new sum when the spaceship advances by `k`.  Over `remaining` generations the spaceship advances by `remaining * shift`, so:

```
sum at gen target  =  sum(cur)  +  remaining * count * shift
```

The `count * shift` factor is the **per-generation sum increment** of a spaceship of `count` plants moving at velocity `shift`.  It is the spaceship's *momentum* in pot-index space, if you want a one-word handle.

### The three CA archetypes and what the formula collapses to

Every CA pattern eventually classifies into one of three shapes (and "die out entirely" as a degenerate fourth).  The closed-form expression for "sum of live indices at generation `g + k`" depends on which archetype:

| CA archetype | Period | Translates? | Closed-form sum at gen `g + k` |
|---|:--:|:--:|---|
| **Still life** -- never changes (e.g. CGoL's *block*, *beehive*) | 1 | No | `sum(cur)` (constant) |
| **Oscillator** -- cycles without moving (e.g. CGoL's *blinker*, *pulsar*) | `p > 1` | No | `sum_at_phase((g + k) mod p)` -- table lookup |
| **Spaceship** -- cycles with translation (e.g. CGoL's *glider*; **Day 12's stable shape**) | `p >= 1` | Yes | `sum(cur) + (k / p) * count * shift_per_period`  -- linear growth |
| (extinction) | -- | -- | `0` |

Day 12 lands in the spaceship row with `p = 1` and `shift_per_period = shift`, so the formula simplifies to `sum(cur) + k * count * shift` -- which is exactly what `extrapolate` computes.

This three-row table is the vocabulary you want to carry into the rest of AoC 2018:

- **Day 18 (Settlers of The North Pole)** is a 2-D CA on a *bounded* grid -- so the live region cannot translate forever (it would walk off the grid).  It lands in the **oscillator** row.  Cycle detection still works, but the closed-form is the table-lookup version rather than the linear-growth one.

- **AoC 2017 Day 6 / Day 16 / Day 25** (your Rust repo) are not CAs but have the same "find the cycle" structure.  Each lands somewhere on this same archetype taxonomy -- usually an oscillator -- once you squint at the state as a CA state.

### The naming-the-thing payoff

A common pattern when learning algorithms: an unfamiliar trick feels like a clever ad-hoc insight the first time you see it, and only later -- after you have seen it three or four times -- do you realise it has a name and a 50-year literature.  Today's "detect the translating shape and project arithmetically" trick is one of those.  Its name is **spaceship detection**, and the algebra above is the standard closed-form expression for spaceship-driven dynamical systems.

You can now recognise it the next time it shows up.

---

## Possible optimizations

The current solution finishes in 3 ms and the project's target is "under a second."  These are documented for the reader, not because we plan to ship them.

### 1.  Encode windows as `Word8`, use a `UArray Word8 Bool` rule table

```haskell
encode :: Set Int -> Int -> Word8
encode s i =
  let bit j = if Set.member j s then 1 else 0
  in   bit (i - 2) `shiftL` 4
     + bit (i - 1) `shiftL` 3
     + bit  i      `shiftL` 2
     + bit (i + 1) `shiftL` 1
     + bit (i + 2)

rules :: UArray Word8 Bool
```

`window s i` becomes a single `Word8` computation; `Set.member ... rs` becomes a `UArray ! w` lookup.  Expected speedup: 3--5× on Part 2, getting it under 1 ms.

The parser needs to emit a 32-entry `UArray Word8 Bool` instead of a `Set String`, but the surrounding code is otherwise unchanged.

### 2.  Cache `normalize cur` across iterations

In `extrapolate`'s `go`, we compute `normalize prev` and `normalize cur` every iteration.  But next iteration's `prev` *is* this iteration's `cur`, so we are recomputing `normalize` of the same set.  Pass it as an additional accumulator:

```haskell
go !g !prev !normPrev !cur =
  let !normCur = normalize cur
  in  if normPrev == normCur then ... else go (g + 1) cur normCur (step rs cur)
```

Halves the `normalize` cost.  Saves ~50 µs on Part 2 -- ~2% -- not worth it on a 3 ms baseline.

### 3.  Period-`k` cycle detection

Replace the period-1 check with a generic `Map (Set Int) (Int, Int)` keyed on normalised shape, value `(generation, leftmostPot)`.  On a hit, compute period `g - g'` and shift `min cur - leftmostPot'`, then apply the same arithmetic.

For period > 1, the leftover-generations cost (`target - g) `mod` period`) requires actual simulation, not arithmetic.  Slightly more code, but handles inputs with shape periods other than 1.

Not needed for the actual AoC 2018 Day 12 input.

### 4.  Represent the state as a `String` with an offset

`(Int, String)` where the `Int` is the index of the first character -- the leftmost candidate pot, including padding `.`s.  `step` becomes a window over the string with `take 5 . drop (i - offset)`.  Allocates one string per generation but no `Set` trees.

For dense states this would be faster; for sparse states it could be slower or about the same.  Empirically I have seen this approach run ~50% faster than `Set Int` in C++, but in Haskell the `String` cons cells are typically slower than a balanced-tree `Set`.  Worth measuring if you wanted to push the bench down.

### 5.  `Data.IntSet` instead of `Data.Set Int`

`IntSet` is `Set Int` with specialised internals (Patricia trie, no comparisons).  Typical 2-3× faster than `Set Int` for membership and insertion.  Drop-in replacement.

Likely the easiest 2× speedup available; ironically I did not reach for it because the `Set String` for rules and the `Set Int` for state share API shape and I wanted to keep the code parallel.

---

## Key patterns

1. **Sparse 1-D state ⇒ `Set Int` of live indices.**  When the live region is small relative to the index range (and especially when the index range is unbounded -- like the infinite-pot tape), `Set Int` is the right representation.  Negative indices are free; the dead majority of the tape costs nothing to represent.

2. **Translation-equivariance of a local rule.**  If a function `f` depends only on a fixed-width window of its input, then `f (shift k s) = shift k (f s)`.  This identity *is* what allows astronomical-step puzzles to be solved by detecting a fixed shape and projecting arithmetically.  Worth recognising the moment a puzzle asks "simulate for N generations" with `N >> 10^6`.

3. **Compare normalised shapes to detect translating fixed points.**  `normalize s = Set.mapMonotonic (subtract minS) s` strips the position and leaves the shape.  When two consecutive normalisations match, the system is in a period-1 translating fixed point and the rest is arithmetic.

4. **Stream of generations via `iterate f x !! n` (or hand-rolled tail-recursion).**  The `iterate` / `!!` pair is the canonical "apply `f` exactly `n` times" combinator.  GHC fuses it into a loop.  When you need extra state (a cycle-detection cache), drop down to hand-rolled tail-recursion in a `where`-block helper.

5. **Bench-time `NFData` on records with `Set` fields.**  Hand-write `instance NFData Puzzle where rnf (Puzzle a b) = a `seq` b `seq` ()`.  `Set` is spine-strict, so `seq` is `rnf`; the record-level instance lets `criterion`'s `nf parseInput` honestly deep-evaluate the parse output.

---

## Side-by-side with the Rust mental model

```rust
use std::collections::BTreeSet;

struct Puzzle {
    initial: BTreeSet<i64>,
    rules: BTreeSet<[char; 5]>,
}

fn window(s: &BTreeSet<i64>, i: i64) -> [char; 5] {
    let mut w = ['.'; 5];
    for d in -2..=2 {
        if s.contains(&(i + d)) {
            w[(d + 2) as usize] = '#';
        }
    }
    w
}

fn step(rs: &BTreeSet<[char; 5]>, s: &BTreeSet<i64>) -> BTreeSet<i64> {
    if s.is_empty() {
        return BTreeSet::new();
    }
    let lo = *s.iter().next().unwrap() - 2;
    let hi = *s.iter().rev().next().unwrap() + 2;
    (lo..=hi).filter(|i| rs.contains(&window(s, *i))).collect()
}

fn normalize(s: &BTreeSet<i64>) -> BTreeSet<i64> {
    if let Some(&m) = s.iter().next() {
        s.iter().map(|i| i - m).collect()
    } else {
        BTreeSet::new()
    }
}

fn extrapolate(rs: &BTreeSet<[char; 5]>, target: i64, s0: BTreeSet<i64>) -> i64 {
    if target <= 0 {
        return s0.iter().sum();
    }
    let mut prev = s0.clone();
    let mut cur  = step(rs, &s0);
    let mut g    = 1_i64;
    while g < target {
        if normalize(&prev) == normalize(&cur) {
            let count = cur.len() as i64;
            let shift = cur.iter().next().unwrap() - prev.iter().next().unwrap();
            let remaining = target - g;
            return cur.iter().sum::<i64>() + remaining * count * shift;
        }
        let next = step(rs, &cur);
        prev = cur;
        cur  = next;
        g   += 1;
    }
    cur.iter().sum()
}
```

Lined up:

| Concept                                | Rust                                                            | Haskell                                              |
|----------------------------------------|------------------------------------------------------------------|------------------------------------------------------|
| Sparse live-pot set                    | `BTreeSet<i64>`                                                  | `Set Int`                                            |
| Window snapshot                        | `[char; 5]` stack-allocated array                                | 5-character `String` (heap-allocated list)           |
| Rule lookup                            | `BTreeSet<[char; 5]>` (cheap, `[char; 5]: Copy`)                 | `Set String` (allocation-heavy)                      |
| One generation                         | `for i in lo..=hi { if rs.contains(&window(s, i)) { ... } }`     | `Set.fromList [i | i <- [lo..hi], window s i `member` rs]` |
| Min/max of a sorted set                | `s.iter().next()` / `s.iter().rev().next()`                      | `Set.findMin` / `Set.findMax`                        |
| Translate a set                        | `s.iter().map(|i| i - m).collect()`  (`O(n log n)`)              | `Set.mapMonotonic (subtract m) s`  (`O(n)`)          |
| Repeated stepping                      | `let mut cur = s0; for _ in 0..n { cur = step(rs, &cur); }`     | `iterate (step rs) s0 !! n`                          |
| Tail-recursive accumulator             | `while g < target { ... g += 1; }`                              | `go (g + 1) cur (step rs cur)`                       |
| Sum of a set                           | `s.iter().sum::<i64>()`                                          | `Set.foldl' (+) 0 s`                                 |
| Strictness on accumulator              | implicit (Rust is strict by default)                             | bang patterns (`!count`, `!shift`, `!remaining`)     |
| Big-integer target literal             | `50_000_000_000_i64`                                             | `50000000000 :: Int`                                 |

The interesting Haskell-specific tool is **`Set.mapMonotonic`**.  Rust's `BTreeSet::iter().map(...).collect()` always pays `O(n log n)` because the standard library has no way to *trust* the user that the function is order-preserving -- and so it must re-sort.  Haskell's `Data.Set` exposes the "trust me" variant as a separate function; the type system does not enforce monotonicity, but the function name does, and the optimisation is real (10-100× faster for big sets).

A Rust equivalent would be unsafe code that builds a `BTreeMap` from a pre-sorted iterator -- doable, but a different API surface.  Haskell's `mapMonotonic` is the kind of "performance escape hatch that trusts the caller" that shows up across the `containers` package (`Map.mapKeysMonotonic`, `Set.fromAscList`, etc.).

---

## Further reading

Cellular automata, fixed-point detection, and the algebra of local rules.

### One-page references

- [**Cellular automaton** -- Wikipedia](https://en.wikipedia.org/wiki/Cellular_automaton).  History, terminology, basic results.  Covers the elementary 1-D case (256 possible rules with 3-cell neighbourhoods, classified by Wolfram into Class 1-4 behaviours) which is the same shape as Day 12 with one fewer neighbour-cell.
- [**Elementary cellular automaton** -- Wolfram MathWorld](https://mathworld.wolfram.com/ElementaryCellularAutomaton.html).  The 256 elementary CA rules and which produce chaotic, periodic, or self-replicating patterns.  Day 12's 32-entry rule table is a "second-order" variant (5-cell window, 2^32 possible rule tables).

### The translation-equivariance idea

- [**Equivariant function** -- Wikipedia](https://en.wikipedia.org/wiki/Equivariant_map).  The general categorical / group-theoretic notion.  Any function that "commutes with a group action" is equivariant; local-window rules are equivariant with respect to the translation group on `Z`.
- [**Convolutional neural networks** -- Stanford CS231n notes](https://cs231n.github.io/convolutional-networks/).  The same mathematical structure: a CNN's convolution layer is exactly a local-window function that is translation-equivariant.  The empirical success of CNNs on image classification is in part a consequence of "we already know images have translational symmetry, let us bake that into the architecture."

### Fixed-point detection in long simulations

- [**Cycle detection** -- Wikipedia](https://en.wikipedia.org/wiki/Cycle_detection).  Floyd's tortoise and hare, Brent's algorithm.  These are `O(1)` memory algorithms for detecting cycles in deterministic dynamical systems; our `Map`-based approach is `O(n)` memory but simpler to implement.  AoC 2017 Day 6 / AoC 2017 Day 16 / AoC 2018 Day 18 all reward this technique.
- [**Pollard's rho algorithm** -- Wikipedia](https://en.wikipedia.org/wiki/Pollard%27s_rho_algorithm_for_logarithms).  A canonical cryptographic application of Floyd's cycle detection -- finding discrete logs in `O(sqrt(p))` time with constant memory.  Same algorithm, very different application.

### Going deeper on 1-D cellular automata

- [**Wolfram's** *A New Kind of Science*](https://www.wolframscience.com/nks/).  Stephen Wolfram's 1200-page treatise on the universal computational power of simple cellular automata.  Notorious for its ambition; chapters 2-3 (the systematic 1-D CA exploration) are the most reliably useful.  Rule 110 (a 3-neighbour 1-D CA) is **Turing-complete**, a result so surprising that it took a decade to be formally proven after Wolfram's conjecture.
- [**Conway's Game of Life** -- LifeWiki](https://www.conwaylife.com/wiki/Main_Page).  The 2-D successor.  Same translation-equivariance, same fixed-point-detection tricks, but with much richer pattern menagerie ("gliders," "blinkers," "pulsars," "Gosper guns").  AoC 2020 Day 17 has a 4-D Life variant; the techniques generalise straightforwardly.

### AoC 2018 callbacks

- **Day 18** (Settlers of The North Pole): a 2-D CA with a 9-cell neighbourhood, also asks for billions of generations.  Same cycle-detection trick.  When you reach it, the `extrapolate`-shaped helper from today should port nearly verbatim -- just `Map (Set (Int, Int)) (Int, Int)` instead of `Set Int` for the state.

---

**Navigation**: [Problem statement](day12.md) | [Summary table](summary_2018.md) | [<- Day 11](day11_function_guide.md) | [Day 13 ->](day13_function_guide.md)
