# Day 07: The Sum of Its Parts -- Function Guide

**Problem**: A list of dependency edges (`"Step X must be finished before step Y can begin."`) describes a partial order over single-letter steps. Part 1 asks for the unique completion order produced by always picking the alphabetically smallest step whose prerequisites are all done. Part 2 has 5 workers cooperating; step `c` takes `60 + (c - 'A' + 1)` seconds. Report total elapsed time.
**Answers**: Part 1 = **`GDHOSUXACIMRTPWNYJLEQFVZBK`**, Part 2 = **1024**
**Runtime** (mean, criterion `-O2`): Parse = **122.9 µs** | Part 1 = **12.0 µs** | Part 2 = **17.5 µs** | **Total = 152.4 µs**
**Code**: [Day07.hs](../../src/Day07.hs)
**Tests**: [Day07Spec.hs](../../test/Day07Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day07"`
**Problem statement**: [day07.md](day07.md)

**New concepts this day** (beyond Days 0--6):

- **Graph as `Map Char (Set Char)` -- prereqs, not successors**. The right shape for "which step is ready?" is the *reverse* adjacency: each key carries the set of steps that must finish before it. "Ready" is then "value set is empty," and `Map.toAscList` hands those candidates back in alphabetical order automatically.
- **Topological sort by repeated pick**. No queue, no Kahn's-algorithm bookkeeping; the `Map` itself is the queue. Pick the alphabetically smallest ready key, append it, then walk the map and remove it from every other prereq set.
- **Discrete-event simulation in pure Haskell**. Part 2 has no `while` loop, no mutable workers; the simulator is a recursive `go` that threads `(now, prereqs, busyWorkers)` through its arguments and jumps directly to the next finish event instead of ticking second-by-second.
- **`Data.List.partition`** for one-pass split into matches and non-matches; **`Map.fromSet`** for seeding a map of empty sets keyed by every node.

`Map.insertWith`, `Set` for membership, `foldl'`, list comprehensions, and pattern matching are reused from Days 2--6.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Data model](#data-model)
3. [`parseInput`](#parseinput)
4. [`prereqs` -- the graph in one map](#prereqs)
5. [`topoOrder` -- alphabetical-priority topo sort](#topoorder)
6. [`part1`](#part1)
7. [`stepDuration`](#stepduration)
8. [`finishTime` -- discrete-event simulation, token by token](#finishtime)
9. [`part2`](#part2)
10. [`solve`](#solve)
11. [Tests](#tests)
12. [Benchmarks](#benchmarks)
13. [Why "ready key with empty value" is the right ready test](#why-the-map-is-the-queue)
14. [Possible optimizations](#possible-optimizations)
15. [Key patterns](#key-patterns)
16. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The puzzle input is a list of dependency edges over 26 possible steps `'A'..'Z'`. The actual input has all 26. Each line specifies one ordering constraint: `"Step C must be finished before step A can begin."` says C must precede A.

**Part 1** -- produce the unique completion order. The DAG can have multiple valid topological orders; the puzzle pins one by tie-breaking *between simultaneously-ready steps* alphabetically. The example, with 6 steps and 7 edges, yields `CABDFE`.

**Part 2** -- now 5 workers cooperate. Each step `c` takes `60 + (c - 'A' + 1)` seconds (so A = 61, Z = 86); no setup time between steps. When multiple steps are ready and a worker is free, the alphabetically smallest ready step is assigned. Part 2 reports the total elapsed time. The puzzle gives an example with 2 workers and a 0-second base (so A = 1, Z = 26), which finishes at second 15.

The two parts share the prereq map and the alphabetical-priority logic; Part 2 adds the worker-pool simulation.

---

## Data model

```haskell
type Edge = (Char, Char)
```

A bare 2-tuple, just like Day 6's `Coord`. The two letters are the *prerequisite* and the *dependent*, in that order, and the order is the only thing that distinguishes them -- a record with named fields would only add ceremony. `[Edge]` is the puzzle's parsed shape.

```haskell
prereqs :: [Edge] -> Map Char (Set Char)
```

The interesting type is the result of `prereqs`. A `Map Char (Set Char)` keyed by every step that appears anywhere, valued by the set of steps that must finish before it. Source steps (no prereqs) keep an empty `Set`. *That is the graph* -- there is no separate node list, no edge list, no successor map. One value, two queries:

| Query                         | Operation                              | Cost |
|-------------------------------|----------------------------------------|------|
| Which steps are ready?        | filter keys whose value is `Set.empty` | O(n) per pick |
| Mark step `s` complete        | `Map.delete s` + `Map.map (Set.delete s)` | O(n log n) |
| Which steps are alphabetically first? | `Map.toAscList` -- already sorted by key | free |

`Map.toAscList` is the load-bearing one: `Data.Map.Strict` keys live in sorted order on disk, so iterating ascending costs nothing extra. The alphabetical tie-break in the puzzle is *the very ordering the `Map` already maintains*, which is why a generic priority queue would be overkill.

---

## `parseInput`

```haskell
parseInput :: String -> [Edge]
parseInput = map parseLine . lines
  where
    parseLine :: String -> Edge
    parseLine line = case words line of
      [_, [a], _, _, _, _, _, [b], _, _] -> (a, b)
      _ -> error ("Day07.parseInput: bad line " ++ show line)
```

Every line has exactly the same shape -- ten whitespace-separated words, with a single-letter step at index 1 and at index 7. `words "Step C must be finished before step A can begin."` returns

```
["Step", "C", "must", "be", "finished", "before", "step", "A", "can", "begin."]
```

The pattern `[_, [a], _, _, _, _, _, [b], _, _]` matches a list of exactly ten elements, ignoring eight of them and binding the second and eighth to `Char` variables `a` and `b` via the inner `[a]` / `[b]` patterns.

### The `[a]` pattern

`[a]` matches a `String` (i.e. a `[Char]`) of length exactly 1, and binds `a :: Char` to the lone character. We have used this once before -- on Day 4's parser, where each event line begins with `[1518-...]` -- but it is worth naming explicitly: `[a]` is *not* "match a single-element list of any type" generically; it is "match a list of length 1 and bind the element to `a`," where the element type is whatever `a` infers to. Here `parseLine`'s return type forces `a, b :: Char`.

### Why pattern-match instead of `splitOn`?

`words` is already a one-shot whitespace splitter and gives a `[String]`. Pattern-matching the resulting list extracts the two interesting tokens by *position* in a single expression. The alternative would be `import Data.List.Split (splitOn)` plus index arithmetic; the `words`+pattern combo is shorter and gives an exhaustiveness check (the underscore catamorphism arm) for free.

---

## `prereqs`

```haskell
prereqs :: [Edge] -> Map Char (Set Char)
prereqs es = foldl' insertEdge seed es
  where
    seed :: Map Char (Set Char)
    seed = Map.fromSet (const Set.empty)
                       (Set.fromList ([a | (a, _) <- es] ++ [b | (_, b) <- es]))

    insertEdge :: Map Char (Set Char) -> Edge -> Map Char (Set Char)
    insertEdge m (a, b) = Map.insertWith Set.union b (Set.singleton a) m
```

Two passes over the edge list:

1. **Seed**. `Set.fromList ([a | (a, _) <- es] ++ [b | (_, b) <- es])` collects every letter that ever appears, on either side of an edge. `Map.fromSet (const Set.empty) thatSet` builds a `Map` whose keys are exactly that set and whose values are all `Set.empty`. The seed is essential -- without it, any *source* step (one that never appears as the right-hand side of any edge) would not have a key in the final map, and the topo-sort loop would never see it as a candidate.
2. **Insert edges**. `foldl'` walks `es`. For each `(a, b)`, `Map.insertWith Set.union b (Set.singleton a) m` looks up `b` and unions `{a}` into its prereq set. We have used `Map.insertWith (+)` on Days 3 and 4 with numeric values; this is the same shape with `Set.union` as the combining function and `Set.singleton a` as the new value to merge in.

### `Map.fromSet`

```haskell
Map.fromSet :: (k -> a) -> Set k -> Map k a
```

Build a map whose key set is exactly `Set k` and whose value at each key is the function applied to the key. Here we throw away the key (`const Set.empty`), giving a map of empty sets. `fromSet` is O(n) -- it does not re-sort the keys, because a `Set` is already in key order. That makes it the fastest way to construct a map of "every node, no info yet."

---

## `topoOrder`

```haskell
topoOrder :: [Edge] -> String
topoOrder = go . prereqs
  where
    go :: Map Char (Set Char) -> String
    go pre
      | Map.null pre = []
      | otherwise =
          case [c | (c, ps) <- Map.toAscList pre, Set.null ps] of
            []      -> error "Day07.topoOrder: cycle (no ready steps)"
            (s : _) -> s : go (Map.map (Set.delete s) (Map.delete s pre))
```

Recursive Kahn-style topological sort, with one twist: *we only need the head of the ready list*. The puzzle says "if more than one step is ready, choose the step which is first alphabetically," and `Map.toAscList` already gives keys in ascending order, so the `[c | ...]` comprehension yields the ready letters alphabetically and we take the first.

### Token by token through `go`

| Token / phrase                                    | Meaning |
|---------------------------------------------------|---------|
| `go pre`                                          | Single argument: the current prereq map. The accumulator (the answer string) is built lazily on the way back up the recursion. |
| `\| Map.null pre = []`                              | Guard: if there are no steps left, the result is the empty string. |
| `\| otherwise =`                                    | Otherwise, find a ready step and recurse. |
| `[c \| (c, ps) <- Map.toAscList pre, Set.null ps]`  | List comprehension over the map's `(key, value)` pairs in *ascending key order*. The guard `Set.null ps` keeps only entries whose prereq set is empty -- the steps with all dependencies done. |
| `case ... of [] -> error ...`                     | A non-empty map with no ready steps means the graph has a cycle. The puzzle inputs are DAGs, but the arm makes the failure mode explicit instead of a silent infinite loop. |
| `(s : _)`                                         | Pattern-matching the head of the ready list. We take the first (= alphabetically smallest) candidate; the remaining ready steps will be reconsidered next iteration. |
| `s : go (...)`                                    | Cons `s` onto the recursive result. This is the answer-building step. |
| `Map.delete s pre`                                | Remove `s` as a key. It is "done" -- no other code should treat it as a node. |
| `Map.map (Set.delete s) ...`                      | Walk every remaining value `Set` and drop `s` from it. This is what marks `s` as "satisfied" for everyone that depended on it. After this, some other step's prereq set may have just become empty -- it will surface as ready next iteration. |

### Why one pick per recursion?

A more aggressive algorithm would gather *all* currently-ready steps and emit them in alphabetical order before recursing. That is what *parallel* topo sort wants -- it is what Part 2 effectively does -- but Part 1 is *sequential*: when you finish step C, both A and F become ready simultaneously, but A is alphabetically first, so it goes next; only after A finishes do B and D join F as ready, and B beats D and F alphabetically. Picking one at a time keeps the algorithm honest about that.

For example: after C is done, ready = `[A, F]`. If we emitted both in order we would get `CAF...`. But the real answer is `CABDFE` -- the second pick must reconsider the ready set after A's effects propagate, because A's completion makes B and D ready, and B beats F alphabetically. Hence: one pick per iteration.

### Cost

Each recursion does a `Map.toAscList` (O(n)), filters (O(n)) to find the ready list, then a `Map.delete` and `Map.map (Set.delete s)` (O(n) each, since the values are tiny `Set`s). With n = 26 and 26 iterations, the total is tiny -- sub-microsecond per pick, and ~12 µs for all 26 picks, dominated by `Map.map` allocating fresh value sets.

---

## `part1`

```haskell
part1 :: [Edge] -> String
part1 = topoOrder
```

Trivial -- the answer is exactly the order. Worth keeping the alias instead of inlining `topoOrder`, because the puzzle phrasing ("Part 1") and the algorithm's name (`topoOrder`) are different vocabulary, and `part1` is what the dispatcher calls. The function-guide reader sees both names and can connect them.

---

## `stepDuration`

```haskell
stepDuration :: Int -> Char -> Int
stepDuration base c = base + (ord c - ord 'A' + 1)
```

`ord :: Char -> Int` from `Data.Char` returns the Unicode codepoint of a `Char`. For ASCII letters that is exactly the codepoint we want: `ord 'A' = 65`, `ord 'B' = 66`, ..., `ord 'Z' = 90`. So `ord c - ord 'A' + 1` is `1` for `'A'`, `2` for `'B'`, ..., `26` for `'Z'`. Add `base` and we have the puzzle's formula.

Parameterising on `base` is what lets the example (`base = 0`) and the actual input (`base = 60`) share the same simulator. The Part 2 entry point pins `base = 60` for the puzzle's canonical answer; the test file uses `base = 0` for the worked example.

---

## `finishTime`

```haskell
finishTime :: Int -> Int -> [Edge] -> Int
finishTime numWorkers base es = go 0 (prereqs es) []
  where
    go :: Int -> Map Char (Set Char) -> [(Char, Int)] -> Int
    go now pre busy =
      let free   = numWorkers - length busy
          ready  = take free [c | (c, ps) <- Map.toAscList pre, Set.null ps]
          pre'   = foldl' (flip Map.delete) pre ready
          busy'  = busy ++ [(c, now + stepDuration base c) | c <- ready]
      in case busy' of
           [] -> now
           _  ->
             let nextTime              = minimum [t | (_, t) <- busy']
                 (finishing, stillBusy) = partition (\(_, t) -> t == nextTime) busy'
                 pre''                 = foldl' removeFinished pre' finishing
             in go nextTime pre'' stillBusy

    removeFinished :: Map Char (Set Char) -> (Char, Int) -> Map Char (Set Char)
    removeFinished m (c, _) = Map.map (Set.delete c) m
```

The simulator. Three pieces of state, threaded through `go`:

| State    | Type                         | What it represents |
|----------|------------------------------|--------------------|
| `now`    | `Int`                        | Current simulation clock, in seconds. |
| `pre`    | `Map Char (Set Char)`        | Steps not yet started, with their unmet prereqs. |
| `busy`   | `[(Char, Int)]`              | Workers currently executing: which step, and at what clock time it will finish. |

The simulation ends when both `pre` and `busy` are empty -- nothing left to start, no worker still running.

### Token by token through one iteration

The algorithm in five sentences:

1. Count free workers; pick the alphabetically smallest ready steps to fill them.
2. Move those steps from `pre` to `busy`, scheduling their finish time.
3. Skip the clock forward to the earliest finish time.
4. Mark the steps that finish at that time as done -- delete them from every other step's prereq set.
5. Recurse.

Walking the `let` block:

| Line | Meaning |
|------|---------|
| `free = numWorkers - length busy` | How many idle workers are there right now? With `numWorkers = 5`, `busy = [('A',61),('B',62)]`, this is 3. |
| `ready = take free [c \| (c, ps) <- Map.toAscList pre, Set.null ps]` | Alphabetical list of steps with empty prereq sets, capped at the number of idle workers. Crucial: we never assign a step to *no* worker, so we never need a separate "queue of ready things." |
| `pre' = foldl' (flip Map.delete) pre ready` | Remove the just-assigned steps from `pre`. They are no longer "not yet started" -- they are running. `flip Map.delete` is `\m k -> Map.delete k m` because `foldl'`'s function takes the accumulator first. |
| `busy' = busy ++ [(c, now + stepDuration base c) \| c <- ready]` | Append the new assignments to the worker list, each tagged with its absolute finish time. |
| `case busy' of [] -> now` | If after assignment we still have no busy workers, both queues are empty -- we are done, return `now`. |
| `nextTime = minimum [t \| (_, t) <- busy']` | The earliest finish time across all workers. We will jump the clock to here next. |
| `partition (\(_, t) -> t == nextTime) busy'` | Split `busy'` into "workers finishing at `nextTime`" and "everyone else." Multiple workers can finish at the same second, hence `partition` rather than "extract one." |
| `pre'' = foldl' removeFinished pre' finishing` | For each step that just finished, walk `pre'` and delete that step from every value `Set`. Steps whose prereq sets just became empty will surface as ready in the next recursion. |
| `go nextTime pre'' stillBusy` | Recurse with the advanced clock, the updated prereq map, and the workers that are still running. |

### Why discrete events and not seconds?

A naive simulator would loop second-by-second: at each second, check if any worker just finished, assign newly-ready steps, increment time. For the actual input that is ~1024 ticks; each tick is cheap, so it would still be fast. But the discrete-event version is *both* faster and more elegant: we only ever recurse `O(steps)` times, not `O(seconds)`, and the code reads exactly like the algorithm description. There is no "tick a clock." The clock simply jumps to where the next interesting thing happens.

26 steps means ~26 recursions for Part 2. The 17.5 µs total runtime is mostly `Map` housekeeping per step, not simulation overhead.

### Why move ready steps out of `pre` immediately?

If we left a step in `pre` while it was running, the next iteration's ready filter would re-pick it. We would either need a separate "in-progress" set to exclude (extra state, easy to get wrong) or we move started steps out of `pre`. The latter is one line and self-evidently correct.

The design rule: `pre` holds "things not yet started"; `busy` holds "things in progress." A step is in exactly one of the two, or it is `done` (in neither). Done-ness is *implicit* -- there is no `Set Char` of completed steps. The only place we need to know a step finished is in the propagation step (`Map.map (Set.delete c) m`), and we have the finishing list right there.

### `Data.List.partition`

```haskell
partition :: (a -> Bool) -> [a] -> ([a], [a])
```

One pass through the list; returns `(matches, non-matches)` preserving original order in each. Equivalent to `(filter p xs, filter (not . p) xs)` in result, but with one traversal. We use it to split workers finishing now from workers still busy. New helper for this codebase.

### `flip Map.delete`

`Map.delete` has the signature `Char -> Map Char v -> Map Char v` (key first, map second). `foldl'`'s combining function takes the accumulator (the map) first and the element (the key) second. So `foldl' Map.delete` is a type error: the arguments come in in the wrong order. `flip Map.delete` swaps them: `Map Char v -> Char -> Map Char v`, which is exactly what `foldl'` wants.

`flip :: (a -> b -> c) -> b -> a -> c` is a tiny but recurring tool when you compose generic helpers (`Map`, `Set`, `Maybe`, `Either`) with generic combinators (`foldl'`, `foldr`). Naming it explicitly here, because it will keep coming up.

---

## `part2`

```haskell
part2 :: [Edge] -> Int
part2 = finishTime 5 60
```

Pin the puzzle's canonical parameters. The general `finishTime` is the workhorse; `part2` is just a partial application. In Rust this would be `|es| finish_time(5, 60, es)`; in Haskell partial application is the default and the `\es ->` is implicit -- `finishTime 5 60` already has type `[Edge] -> Int`.

---

## `solve`

```haskell
solve :: String -> IO ()
solve contents = do
  let es = parseInput contents
  putStrLn ("  part 1: " ++ part1 es)
  putStrLn ("  part 2: " ++ show (part2 es))
```

Parse once via the shared `let es`, print both answers. The two parts have no algorithmic overlap -- Part 1 is a sequential alphabetical pick over the prereq map, Part 2 is a parallel-worker simulation -- but they share the parser and the prereq construction, which is what `parseInput` and `prereqs` are for.

---

## Tests

Coverage in [Day07Spec.hs](../../test/Day07Spec.hs):

1. **`parseInput`** -- the seven example edges parse exactly to the expected `[(Char, Char)]`.
2. **`prereqs` (example)** -- key set is `"ABCDEF"`; C has no prereqs; A and F have `{C}`; B and D have `{A}`; E has `{B, D, F}`. This is the entire example DAG, pinned.
3. **`stepDuration`** -- A and Z at base 60 give 61 and 86 (the puzzle text's two anchor cases); A and F at base 0 give 1 and 6 (the sub-example).
4. **Puzzle example** -- Part 1 = `"CABDFE"` and Part 2 with 2 workers and base 0 = 15.
5. **Actual input** -- Part 1 = `GDHOSUXACIMRTPWNYJLEQFVZBK`, Part 2 = 1024.

The `prereqs`-on-example tests are unusually granular for this project, but Day 7's correctness rests on the prereq map being shaped correctly. If a future refactor breaks the seed step (sources missing as keys), or the union step (multiple prereqs for E being collapsed), one of those tests will catch it directly rather than through a wrong final answer.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean       | What it times |
|--------------------|-----------:|---------------|
| `day07/parseInput` | 122.9 µs   | ~100 lines through `lines` + `words` + a 10-element pattern match. |
| `day07/part1`      | 12.0 µs    | 26 iterations of `Map.toAscList` filter + `Map.map (Set.delete _)`; median of 3 runs (first was 13.45 µs / 91 % variance, warm-up noise). |
| `day07/part2`      | 17.5 µs    | ~26 simulation events, each doing a `partition` over a 5-element list and a `Map.map` over the 26-key prereq map. |
| `day07/combined`   | 179.3 µs   | End-to-end from raw string. |

**Total = Parse + Part 1 + Part 2 = 152.4 µs.**

This is by far the fastest solved day after the Day 0 warm-up (43.6 µs). The algorithmic work is microscopic -- 26 nodes, ~100 edges -- and the dominant cost is `parseInput` reading `String` lines and tokenising them. Switching the parser to `Data.ByteString.Char8` would probably halve `parseInput`'s mean, but at 123 µs there is no reason to.

Part 1 and Part 2 are within a factor of 1.5 of each other. The simulator costs slightly more because each of its ~26 events does two `Map`-walking operations (`removeFinished` and the next ready filter) where Part 1 does one.

---

## Why the Map is the queue

The choice to represent the graph as `Map Char (Set Char)` of *prereqs* is what collapses the algorithm to a few lines. It is worth pausing on why that representation is the right one for this puzzle.

### The two natural graph representations

Given the edges `(a, b)` meaning "a precedes b," there are two adjacency-style maps you could build:

1. **Successors**: `Map Char (Set Char)` keyed by `a`, valued by the set of `b`s that `a` enables.
2. **Prereqs**: `Map Char (Set Char)` keyed by `b`, valued by the set of `a`s that must come first.

Both encode the same information. The textbook Kahn's algorithm uses representation (1), tracks an integer in-degree per node externally, and maintains a separate ready queue. Each completion decrements in-degrees; nodes whose in-degree drops to zero are pushed onto the ready queue.

Representation (2) collapses two of those data structures into one. The "in-degree" of node `b` is just `Set.size (pre Map.! b)`, and "in-degree zero" is just `Set.null (pre Map.! b)` -- no separate counter to maintain. The ready queue is the *filter* `Set.null . snd` over `Map.toAscList pre`; no separate `Seq` or `MinHeap`.

### Why prereqs win for *this* puzzle

The cost of using prereqs instead of successors is that step completion requires walking the entire map (O(n)) to delete the step from every value set. For a graph with millions of nodes, that is wasteful -- you would rather walk just the successors of the completed step.

For 26 nodes it does not matter at all. We pay 26 ops per completion times 26 completions = 676 ops total, all on tiny `Set`s. `Map.map (Set.delete s)` over a 26-key map is sub-microsecond.

The alphabetical tie-break is the second reason. With representation (1) and a separate ready queue, we would need a `Set Char` or `Data.Set` for the queue (so smallest-first is `Set.findMin`) and a `Map Char Int` for in-degrees, and two side-channels to wire them together. With representation (2), `Map.toAscList` already gives keys in alphabetical order, and the ready filter trivially preserves that order. One data structure, one query.

### When to switch back to successors

If the graph were big (10k+ nodes) and edges sparse, the O(n) walk in `Map.map (Set.delete s)` would start to matter. The fix is to *also* keep a successor map, so that completion of `s` walks only `succ Map.! s` instead of all keys. That is the canonical Kahn's implementation. For Day 7, the simpler representation is much clearer and just as fast.

---

## Possible optimizations

### Bitmask in-degree counts instead of `Set Char`

26 letters fit in a 32-bit `Word`. Each prereq set is a bitmask; "ready" is `bitmask == 0`; completion is one `xor` per remaining node. The whole prereq map fits in 26 `Word`s -- a `Data.Vector.Unboxed Word32`. Per-step work drops by another order of magnitude, mostly because there is no `Map`/`Set` allocation churn.

```haskell
import qualified Data.Vector.Unboxed as V
import Data.Bits ((.&.), complement, bit)
import Data.Word (Word32)

-- prereqs as 26 Word32 masks; index by ord c - ord 'A'
type PreVec = V.Vector Word32

readyMask :: PreVec -> Word32
readyMask = V.ifoldl' (\acc i p -> if p == 0 then acc .|. bit i else acc) 0

complete :: Int -> PreVec -> PreVec
complete i = V.map (.&. complement (bit i))
```

For 26 nodes this would shave Part 1 from ~12 µs to ~2 µs and Part 2 from ~17 µs to ~3 µs. Untested, included as a teaching sketch -- the gain is real but the AoC numbers do not justify the bookkeeping.

### Successor map for completion propagation

As discussed above, building a successor map alongside the prereq map turns `complete s` into "walk the successors of `s` and delete `s` from each one's prereq set" instead of walking the entire map. For 26 nodes, irrelevant; for a bigger DAG, the canonical optimisation.

### `Data.ByteString.Char8` for the parser

`parseInput` is the bulk of total runtime (123 µs of 152 µs). Switching from `String` lines to a strict `ByteString` parser would probably halve it. Not worth doing for a fast day, but worth flagging as the *next* place a profiler would point.

---

## Key patterns

1. **`Map k v` whose value `v` doubles as "is the entry ready?"**. When the puzzle has a question of the form "find me the smallest key whose payload satisfies P," sorting plus filtering on `Map.toAscList` is the one-liner. No separate priority queue needed if your `Ord` already matches the priority you want.
2. **Discrete-event recursion as a `while`-loop replacement**. State threads through arguments; the next event time is computed from `busy`; the recursion advances. Anywhere you would write `while (workers || queue) { ... }` in Rust or C, the Haskell shape is `go now state busy`. The simulator size in lines stays roughly constant as the state grows.
3. **`partition` for "split into matches and rest" in one pass**. Whenever you find yourself writing `(filter p xs, filter (not . p) xs)`, reach for `Data.List.partition` instead.
4. **`Map.fromSet (const v) someSet`** -- the shortest way to seed a map of identical default values keyed by a known set of keys. Avoids re-sorting and avoids `foldr`-with-`Map.insert` pyramids.

---

## Side-by-side with the Rust mental model

```rust
use std::collections::{BTreeMap, BTreeSet};

type Edge = (char, char);

fn prereqs(edges: &[Edge]) -> BTreeMap<char, BTreeSet<char>> {
    let mut pre: BTreeMap<char, BTreeSet<char>> = BTreeMap::new();
    for &(a, b) in edges {
        pre.entry(a).or_default();
        pre.entry(b).or_default().insert(a);
    }
    pre
}

fn topo_order(edges: &[Edge]) -> String {
    let mut pre = prereqs(edges);
    let mut out = String::new();
    while let Some((&s, _)) = pre.iter().find(|(_, ps)| ps.is_empty()) {
        out.push(s);
        pre.remove(&s);
        for ps in pre.values_mut() {
            ps.remove(&s);
        }
    }
    out
}

fn step_duration(base: u32, c: char) -> u32 {
    base + (c as u32 - 'A' as u32 + 1)
}

fn finish_time(num_workers: usize, base: u32, edges: &[Edge]) -> u32 {
    let mut pre = prereqs(edges);
    let mut busy: Vec<(char, u32)> = Vec::new();
    let mut now: u32 = 0;
    loop {
        // 1) assign ready -> idle workers, alphabetically
        let free = num_workers - busy.len();
        let ready: Vec<char> = pre.iter()
            .filter(|(_, ps)| ps.is_empty())
            .map(|(&c, _)| c)
            .take(free)
            .collect();
        for c in &ready {
            pre.remove(c);
            busy.push((*c, now + step_duration(base, *c)));
        }
        if busy.is_empty() { return now; }
        // 2) jump to next finish event
        let next = busy.iter().map(|&(_, t)| t).min().unwrap();
        let (finishing, still): (Vec<_>, Vec<_>) =
            busy.into_iter().partition(|&(_, t)| t == next);
        // 3) propagate completion
        for (c, _) in &finishing {
            for ps in pre.values_mut() { ps.remove(c); }
        }
        now = next;
        busy = still;
    }
}
```

Lined up with Haskell:

| Concept                      | Rust                                                | Haskell                                                       |
|------------------------------|-----------------------------------------------------|---------------------------------------------------------------|
| Sorted-key associative map   | `BTreeMap<char, BTreeSet<char>>`                    | `Data.Map.Strict.Map Char (Data.Set.Set Char)`                |
| Seed every node              | `pre.entry(c).or_default()` per endpoint            | `Map.fromSet (const Set.empty) (Set.fromList ...)`            |
| Insert prereq                | `entry(b).or_default().insert(a)`                   | `Map.insertWith Set.union b (Set.singleton a) m`              |
| First ready key alphabetically | `pre.iter().find(\|(_, ps)\| ps.is_empty())`          | `[c \| (c, ps) <- Map.toAscList pre, Set.null ps]` then head   |
| Mark complete (delete + propagate) | `pre.remove(&s); for ps in pre.values_mut(){ ps.remove(&s); }` | `Map.map (Set.delete s) (Map.delete s pre)` |
| Step duration                | `base + (c as u32 - 'A' as u32 + 1)`                | `base + (ord c - ord 'A' + 1)`                                |
| Loop-vs-recursion            | `loop { ... }` mutates `now`, `pre`, `busy` in place | `go now pre busy = ...` recurses with updated state          |
| Split list in one pass       | `Vec::into_iter().partition(p)`                     | `Data.List.partition p :: [a] -> ([a], [a])`                  |
| Drop key from map            | `pre.remove(&c)`                                    | `Map.delete c pre`                                            |
| Walk and update every value  | `for ps in pre.values_mut() { ps.remove(&c); }`     | `Map.map (Set.delete c) pre`                                  |
| Partial application of params | closure: `\|es\| finish_time(5, 60, es)`              | `finishTime 5 60` -- partial application is the default       |

Both versions are about 45--50 lines of core algorithm. The Rust version mutates `pre`, `busy`, and `now` in place and uses `loop` + `return`; the Haskell version threads them through `go` and recurses. The bookkeeping is the same: at most three pieces of state, and a discrete event = one iteration. The Haskell `Map.map (Set.delete c)` is the line where Rust would look more imperative (`for ps in pre.values_mut() { ... }`), but both express "walk the map's values and update each one" in idiomatic style.

---

**Navigation**: [Problem statement](day07.md) | [Summary table](summary_2018.md) | [<- Day 6](day06_function_guide.md) | [Day 8 ->](day08_function_guide.md)
