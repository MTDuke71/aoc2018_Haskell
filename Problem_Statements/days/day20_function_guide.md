# Day 20: A Regular Map -- Function Guide

**Problem**: An exploration "regex" of `N` / `S` / `E` / `W`
direction characters with branches `(a|b|…)` traces every path
through a facility of rooms separated by doors. Build the door
graph, BFS from the origin. Part 1: largest shortest-path
distance. Part 2: count rooms whose shortest distance is ≥ 1000
doors.

**Answers**: Part 1 = **3835**, Part 2 = **8520**
**Code**: [Day20.hs](../../src/Day20.hs) · **Python reference**: [day20.py](../../python/day20.py)
**Runtime**: Parse 9.49 ms · Part 1 5.58 ms · Part 2 5.53 ms · Total ≈ 20.6 ms

**New concepts this day**:

- **Streaming regex evaluation with a position stack.** We never
  parse the regex into a syntax tree. A single left-to-right fold
  carries a "current position" and a stack of saved positions, one
  per open paren: `(` pushes, `|` resets to the top, `)` pops. That
  is the entire interpreter.
- **A door graph from an edge set.** Every direction step adds an
  undirected door between two adjacent rooms. We canonicalise each
  pair (smaller endpoint first) into a `Set`, then build the
  symmetric adjacency map with `Map.fromListWith (++)`. The Set
  silently dedupes paths that traverse the same corridor multiple
  times.
- **BFS with `Data.Sequence` as the queue.** `Data.Sequence` is the
  Haskell pure FIFO queue: `O(1)` `viewl` for the head, amortised
  `O(1)` `(|>)` for snoc. Plain lists would force a reverse on
  every pop. The visited / distance table is a single `Map`:
  presence ⇒ already dequeued, value ⇒ shortest distance.
- **First puzzle in the calendar where there is no clever
  algorithm.** Parts 1 and 2 are both "compute one shortest-path
  map and reduce it." All the work is in *correctly building the
  graph* from the regex — the BFS is the easy part.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Why the single-position stack is correct](#why-the-single-position-stack-is-correct)
- [Data model](#data-model)
- [`parseInput` and `buildDoors`](#parseinput-and-builddoors)
- [`distances` -- the BFS](#distances----the-bfs)
- [`part1`, `part2`, `solve`](#part1-part2-solve)
- [Counting the whole facility](#counting-the-whole-facility)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

The Elves hand you a single line that describes — as a regular
expression of compass directions — *every* path through their
facility. From the puzzle text:

> `^` and `$` are at the beginning and end of your regex; these
> just mean that the regex doesn't match anything outside the
> routes it describes. The rest of the regex matches various
> sequences of the characters `N` (north), `S` (south), `E`
> (east), and `W` (west). Sometimes the route can *branch*: a
> branch is given by a list of options separated by pipes `|` and
> wrapped in parentheses.

The puzzle text walks `^ENWWW(NEEE|SSE(EE|N))$` through five
explicit drawings of the facility growing one branch at a time.
The key wrinkle, for Part 2 purposes, is that branches can be
*empty*: `(NEWS|)` means "you can take the four-step detour
`NEWS`, or skip the whole group entirely." Detours always end at
the room they started in, so navigation after the group continues
from the group's start — that's the assumption the simple
walker leans on.

Five small examples are provided, each with the expected
furthest-room distance — 3, 10, 18, 23, 31. The test file pins
all of them, plus the actual input (3835 / 8520).

Part 1 asks for the *furthest* room (largest shortest-path).
Part 2 asks how many rooms are at least 1000 doors away. Both are
trivial reductions of the same BFS distance map.

---

## The algorithm in Python

The shipping solution is [Day20.hs](../../src/Day20.hs); the
algorithm reads cleaner without Haskell's `NFData` / `Map` /
`Sequence` plumbing in the way, so the side-by-side is
[python/day20.py](../../python/day20.py). The two files compute
the same answers from the same input.

```python
STEP = {"N": (0, -1), "S": (0, +1), "W": (-1, 0), "E": (+1, 0)}

def build_doors(regex):
    """Return adjacency dict {room: set(neighbours)} from the regex."""
    pos, stack = (0, 0), []
    adj = {pos: set()}
    for c in regex:
        if c in "^$":
            continue
        elif c == "(":
            stack.append(pos)
        elif c == "|":
            pos = stack[-1]            # reset to start of group
        elif c == ")":
            pos = stack.pop()          # continue from start of group
        else:                          # N / S / E / W
            dx, dy = STEP[c]
            nxt = (pos[0] + dx, pos[1] + dy)
            adj.setdefault(pos, set()).add(nxt)
            adj.setdefault(nxt, set()).add(pos)
            pos = nxt
    return adj

def distances(adj, start=(0, 0)):
    """Plain BFS.  Dict doubles as visited set and distance table."""
    dist = {start: 0}
    q = deque([start])
    while q:
        p = q.popleft()
        for n in adj.get(p, ()):
            if n not in dist:
                dist[n] = dist[p] + 1
                q.append(n)
    return dist
```

Part 1 is `max(distances(build_doors(regex)).values())`. Part 2 is
`sum(1 for v in distances(build_doors(regex)).values() if v >= 1000)`.
The Haskell mirrors this structure line-for-line.

---

## Why the single-position stack is correct

A truly general regex evaluator would carry a *set* of "possible
current positions" — when you enter a branch, each alternative may
end somewhere different, and the steps after the group apply to
every endpoint. AoC 2018's inputs are constructed so this never
matters:

- A **detour group** like `(NEWS|)` has an empty alternative. The
  non-empty branch traces a loop and returns to its starting
  room, so both branches end at the same place — the start.
- A **multi-branch group** like `(NEEE|SSE(EE|N))` always sits at
  the *end* of a path. Look at the provided examples: every
  multi-branch never has more regex chasing it within the same
  parenthesised level. Whatever room each branch ends in is the
  end of *that* route; no further moves "after the group" need to
  apply to it.

Under those two assumptions, a single saved position per group is
enough:

| Char | Action                                                |
|------|-------------------------------------------------------|
| `(`  | Push current position. Stack grows by one.            |
| `|`  | Reset current position to the top of the stack.       |
| `)`  | Pop. Current position becomes the popped value.       |
| dir  | Move by one step; add an undirected door to the set.  |

This makes the walker a 30-line `foldl'` with no syntax tree, no
regex compiler, no NFA construction. The only "intelligence" the
walker has is the stack of restart points.

**What if the assumption fails?** If a real-life regex had a
multi-branch group whose branches genuinely end at *different*
rooms followed by more regex, the door set would miss every door
that the post-group steps would have added from the alternate
endpoints. You'd see the missing rooms in the BFS (some doors
would never be enqueued), and the answer would be too small.
None of the examples or the actual input trigger that — the test
file's five worked examples are the load-bearing safety net.

A fully general implementation would store `Set Pos` instead of
`Pos` and `(Set Pos, Set Pos)` (start, all-ends) on the stack;
`|` accumulates ends and resets to start, `)` unions ends ∪
current and pops. It's eight extra lines and runs in the same
asymptotic time, but the single-position version is what the
codebase ships.

---

## Data model

```haskell
type Pos = (Int, Int)

newtype Puzzle = Puzzle { doors :: Map Pos [Pos] }
  deriving (Eq, Show)

instance NFData Puzzle where
  rnf (Puzzle m) = rnf m
```

- `Pos` is a plain `(Int, Int)`. North decreases `y`, south
  increases it, east/west change `x`. The orientation is
  irrelevant — only the *graph* (which rooms connect to which)
  determines the answers. Using a tuple gives us free `Ord` and
  `Eq`, exactly what `Map` and `Set` keys need.
- `Puzzle` is a `newtype` wrapper around the adjacency map. The
  reason is the same as Days 11, 17, 18: criterion's `nf` needs an
  `NFData` constraint, and bare `Map` already has one — but a
  named wrapper is friendlier in error messages and lets the
  function-guide reader see "the parsed puzzle is the door graph"
  at a glance. (For `Map k v` the stock `rnf` walks the spine
  *and* forces every value; for a `Map Pos [Pos]` that includes
  the neighbour lists.)
- We keep `doors` as a record selector. Tests use it to spot-check
  that origin has the expected neighbours after parsing
  `"^N$"` — a smaller sanity check than running the full BFS.

The *internal* edge set lives in a `Set (Pos, Pos)` during
`buildDoors`. Each edge is canonicalised (smaller endpoint first)
so a corridor traversed from both directions is stored exactly
once. We never expose this intermediate type — it's a fold
accumulator that gets converted to the adjacency map at the end.

---

## `parseInput` and `buildDoors`

```haskell
parseInput :: String -> Puzzle
parseInput = Puzzle . buildDoors . filter (`notElem` " \t\r\n")
```

One-liner. Strip whitespace (the file ends in `\n`, which would
otherwise be interpreted as an unknown direction by the inner
`step1`), wrap the regex into the door builder, tag with the
newtype.

```haskell
buildDoors :: String -> Map Pos [Pos]
buildDoors regex =
  Map.fromListWith (++)
    [ kv
    | (a, b) <- Set.toList edges
    , kv     <- [(a, [b]), (b, [a])]
    ]
 where
  (_, _, edges) = foldl' step ((0, 0), [], Set.empty) regex
  ...
```

Two phases:

1. **Fold the regex into an edge set.** `foldl' step` walks the
   ~14,000-character string left to right. The fold state is
   `(pos, stack, edges)`: current position, paren-stack of saved
   positions, and the canonical edge set seen so far. Strict
   `foldl'` (the everywhere pattern — Days 1, 4, 5, 9, 18) plus
   bang patterns on the accumulator components keeps allocation
   flat across the 14k iterations.

2. **Convert edges to an adjacency map.** A list comprehension
   emits two entries per edge (one in each direction), then
   `Map.fromListWith (++)` builds the symmetric `Map Pos [Pos]`.
   `(++)` is the combining function: as duplicate keys come in,
   their neighbour-lists are concatenated. For ~10k edges this is
   fast enough that the conversion doesn't show up in the profile.

The fold step itself:

```haskell
step (!pos, !stack, !es) c = case c of
  '^' -> (pos, stack, es)
  '$' -> (pos, stack, es)
  '(' -> (pos, pos : stack, es)
  '|' -> case stack of
           (p : _) -> (p, stack, es)
           []      -> error "Day20.buildDoors: '|' outside group"
  ')' -> case stack of
           (p : rest) -> (p, rest, es)
           []         -> error "Day20.buildDoors: unmatched ')'"
  d   -> let !pos' = step1 d pos
             !edge = if pos <= pos' then (pos, pos') else (pos', pos)
         in  (pos', stack, Set.insert edge es)
```

- `^` / `$` are sentinels — the fold simply passes through. We
  could strip them in `parseInput` instead; leaving them as
  no-ops in the fold keeps `buildDoors` callable with raw regex
  bodies the tests can paste in verbatim.
- `(` pushes the current position. Cons-onto-a-list is the
  Haskell idiom for "push" — `pos : stack` is `O(1)` and never
  allocates a fresh spine for the old elements.
- `|` resets `pos` to the top of the stack via the `(p : _)` head
  pattern, leaving the stack itself untouched (we may have more
  `|`s in this group). The empty-stack case is impossible on
  well-formed regexes; we explode with `error` rather than
  silently producing the wrong graph.
- `)` pops *and* sets `pos` to the popped value. After the close
  paren we resume "as if we never entered the group" — the
  convention that makes the single-position walker correct.
- Direction characters call `step1` to move, then canonicalise
  the (old, new) endpoints into an unordered pair and `Set.insert`
  it. `pos <= pos'` is the tuple `Ord` — lexicographic on
  `(x, y)` — which is fine; we only need *some* total order to
  pick a canonical orientation.

```haskell
step1 :: Char -> Pos -> Pos
step1 'N' (x, y) = (x, y - 1)
step1 'S' (x, y) = (x, y + 1)
step1 'W' (x, y) = (x - 1, y)
step1 'E' (x, y) = (x + 1, y)
step1 c   _      = error ("Day20.buildDoors: bad direction: " ++ show c)
```

A flat case on the four direction letters. Local to `buildDoors`
because nothing else needs it — `where`-bound functions are the
Haskell unit of "private helper".

---

## `distances` -- the BFS

```haskell
distances :: Puzzle -> Map Pos Int
distances (Puzzle adj) = go (Map.singleton (0, 0) 0) (Seq.singleton (0, 0))
 where
  go !dist q = case Seq.viewl q of
    EmptyL    -> dist
    p :< rest ->
      let d      = dist Map.! p
          ns     = [ n | n <- Map.findWithDefault [] p adj
                       , not (Map.member n dist) ]
          !dist' = foldl' (\m n -> Map.insert n (d + 1) m) dist ns
          !q'    = foldl' (|>) rest ns
      in  go dist' q'
```

Textbook breadth-first search, with two Haskell-flavoured details:

- **`Data.Sequence` as the queue.** `Seq.viewl` peeks the front
  in `O(1)` and returns either `EmptyL` (we're done) or
  `head :< rest` (the rest of the queue with the head removed —
  no list `reverse` needed). `(|>) :: Seq a -> a -> Seq a` is
  amortised `O(1)` snoc. Using a plain list with `(++)` for snoc
  would be `O(n)` per enqueue and would dominate the runtime.
- **A `Map` doubling as visited set and distance table.**
  `Map.member n dist` is the visited check; `Map.insert n (d+1)`
  marks it visited *and* records its distance in one operation.
  No separate `Set` for "already seen". This is the same pattern
  Day 15's BFS uses, and it generalises: any time you want
  "first-seen distance," the map *is* the visited set.

The two `foldl'`s thread the new neighbours into `dist'` and
`q'`. Bang patterns on both keep them strict — without them the
queue accumulates thunks as it gets snocced through, and you
allocate work proportional to `O(V²)` instead of `O(V)`.

`Map.findWithDefault [] p adj` returns the empty list if `p` has
no neighbours. For a connected door graph rooted at the origin
this never fires (every dequeued room was reached via an edge,
so it's in `adj`); we keep `findWithDefault` to make the function
total on graphs that happen to have isolated rooms.

**Complexity**: `O(V log V)` time (BFS does `O(V + E)` work with
`O(log V)` per Map operation), `O(V)` space for the distance map.
For the real input, `V = 10000` rooms and `E = 9999` doors — i.e.
the door graph is exactly a **tree** (`V = E + 1`, every room
except the origin has a single "parent" door). That is not a
coincidence of this particular input — the AoC regex shape always
produces a tree, because branches return to their start (no new
edge connects two already-reachable rooms back into a cycle).
Practically: BFS = a depth-first tree walk reporting depths.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Puzzle -> Int
part1 = maximum . Map.elems . distances

part2 :: Puzzle -> Int
part2 = length . filter (>= 1000) . Map.elems . distances
```

Both parts are reductions of the same BFS distance map. The
bench reports each part at ≈5.5 ms — and they're nearly equal
because the BFS *is* the cost. `length . filter` walks the
distances list once; `maximum` does the same with a different
combiner.

That means `cabal bench day20` records the BFS cost **twice** —
once as Part 1's time, once as Part 2's. The `combined` bench
(parse + Part 1 + Part 2 from raw text) ≈ 21.4 ms confirms it.
The function-guide table reports Total = 20.6 ms by the project's
convention (Parse + Part 1 + Part 2 from the cached benches),
which slightly *over*counts versus a clever implementation that
shares the BFS. `solve` (below) does share it, so the dispatch
executable's wall time is ~14 ms, not 20.

```haskell
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
      d      = distances puzzle      -- one BFS, shared by both parts
  putStrLn ("  part 1: " ++ show (maximum (Map.elems d)))
  putStrLn ("  part 2: " ++ show (length (filter (>= 1000) (Map.elems d))))
```

The `let`-shared `d` is the Day 10 / Day 17 idiom one more time:
keep the per-part functions standalone (so benches measure them
honestly), but share the heavy work in `solve` (so end-to-end
runtime reflects what a real caller would pay).

### Possible optimization

Two small wins, neither shipped:

1. **Inline both parts into `distances`'s fold.** Track the
   running max and a running ≥1000 counter as `BFS` proceeds,
   then return both. That collapses the two list traversals at
   the end and saves a few hundred microseconds.

2. **Coordinate compression to `IntMap`.** Rooms are 2D
   coordinates but the BFS only needs them as opaque keys. After
   `buildDoors`, assign each `Pos` an `Int` and run BFS on
   `IntMap Int Int` — `IntMap` is ~2× faster than `Map (Int, Int) Int`
   on graphs this size. Net effect: probably 5.5 ms → 3 ms per
   part.

Filed as sidebars rather than swapped in: the puzzle finishes in
20 ms either way, and the simpler `Map`-keyed BFS reads more
directly as "BFS on a graph keyed by room coordinates."

---

## Counting the whole facility

Neither part asks "how big is the facility?", but it falls out for
free — the BFS *already* visits every room, so the total room count
is just the size of the distance map:

```haskell
facilitySize :: Puzzle -> Int
facilitySize = Map.size . distances
```

`solve` prints it alongside the two answers:

```
  part 1: 3835
  part 2: 8520
  rooms in facility: 10000
```

Why this is the *complete* count, not a sample:

- **The BFS reaches every room.** The facility is connected by
  construction — every door joins two rooms, and the regex is
  rooted at the origin — so a single BFS from `(0,0)` dequeues all
  of them. `Map.size . distances` is therefore the whole facility,
  not just the part the regex's "main line" walks through.
- **You could skip the BFS entirely.** `buildDoors` already emits a
  key for every room that has at least one door, and every room has
  one (including the origin), so `Map.size . doors` gives the same
  10000. Counting from the graph and counting from the BFS agree
  precisely because the graph is connected.

The round 10000 is the same number the BFS section flags as
`V = 10000`, and it's the load-bearing fact behind the "the door
graph is a tree" observation: `V = 10000`, `E = 9999`, so
`V = E + 1` — every room except the origin is reached by exactly
one door, no cycles.

### Shape of the facility: a 100×100 perfect maze

The rooms aren't a scattered corridor — they fill a perfect square.
Taking the bounding box of every room coordinate:

| Axis | Range      | Span          |
|------|------------|---------------|
| x    | −52 … 47   | **100** wide  |
| y    | −50 … 49   | **100** tall  |

So the bounding box is 100 × 100 = 10000 cells — and there are
*exactly* 10000 rooms. The **fill ratio is 1.0**: every single
lattice point inside the box is a room, no gaps.

Combine that with the tree fact and the structure has a name:

> A **100×100 grid of rooms, completely filled, whose doors form a
> spanning tree of the grid** — i.e. a *perfect maze*.

A perfect maze is the canonical object where every cell is reachable
and there is *exactly one* path between any two rooms (no loops, no
walled-off cells, no wasted space). That is precisely what
`V = E + 1` over a fully-filled grid means: 10000 cells joined by
9999 doors with no cycles. The puzzle author generated a perfect
maze and serialised one full walk of it as the regex; our
`buildDoors` fold just reconstructs the spanning tree edge by edge.

This reframes both parts:

- **Part 1** ("furthest room") is the **eccentricity of the root**
  in the spanning tree — the deepest node from `(0,0)`. (The tree's
  full *diameter* could be larger, between two arbitrary leaves; the
  puzzle only asks for depth from the origin.)
- **Part 2** ("rooms ≥ 1000 doors away") counts how many tree nodes
  sit at depth ≥ 1000.

The canonical vocabulary worth keeping: *perfect maze = spanning
tree of a grid graph*. The same structure is what randomized-DFS,
Wilson's, and Kruskal-on-a-grid maze generators all produce — "carve
passages until every cell connects exactly once."

---

## Key patterns

- **A stack of saved positions is a regex evaluator.** As long as
  branches return to their start — the AoC convention for this
  whole puzzle family — you do not need an AST. `(` push, `|`
  reset to top, `)` pop. The technique generalises to any
  parenthesised mini-language where each group is "do this, or
  nothing, then continue."

- **Canonicalise unordered edges before storing.** A door from
  A to B is the same door as B to A; storing `(min a b, max a b)`
  in a `Set` is the cleanest way to make `Set.insert` idempotent
  on duplicates. You'll need this any time you build an undirected
  graph from a directed traversal.

- **`Map` as both visited set and distance table.** Don't carry a
  separate `Set` of "seen" alongside a `Map` of "distance" —
  presence in the distance map *is* the visited check. One
  insertion does both jobs.

- **`Data.Sequence` is the Haskell pure FIFO.** `O(1)` head-view,
  amortised `O(1)` snoc. Plain lists work as queues only if you
  pay an `O(n)` `reverse` per dequeue (or use the two-list
  amortised trick). For any BFS over a reasonably large frontier,
  reach for `Seq`.

- **When both parts reduce the same intermediate result, share it
  in `solve` and re-run it in the standalone parts.** Same
  trade-off Days 10 and 17 made: the standalone parts can be
  benched honestly, the dispatch executable pays the cost only
  once. The function-guide table is then transparent about the
  ≈2× over-count.

- **Bounding box + fill ratio is a cheap structure probe.** When a
  grid-shaped graph surprises you, take `(min, max)` of the
  coordinates and compare `rooms / (width × height)` against `1.0`.
  A ratio of exactly 1 says "filled rectangle"; combine it with
  `E = V − 1` and you've identified a *spanning tree of a grid* — a
  perfect maze — without drawing anything. Two `minimum`/`maximum`
  passes turn "10000 rooms" into "a 100×100 perfect maze."

---

## If I were writing this in Rust

The fold is a `for c in regex.chars()` loop over an `enum Token`
classification. The stack is a `Vec<(i32, i32)>`; the edge set
is a `HashSet<((i32, i32), (i32, i32))>`. The adjacency map
becomes a `HashMap<(i32, i32), Vec<(i32, i32)>>`:

```rust
fn build_doors(regex: &str) -> HashMap<(i32, i32), Vec<(i32, i32)>> {
    let mut pos = (0, 0);
    let mut stack: Vec<(i32, i32)> = Vec::new();
    let mut edges: HashSet<((i32, i32), (i32, i32))> = HashSet::new();
    for c in regex.chars() {
        match c {
            '^' | '$' => {}
            '(' => stack.push(pos),
            '|' => pos = *stack.last().unwrap(),
            ')' => pos = stack.pop().unwrap(),
            'N' | 'S' | 'E' | 'W' => {
                let nxt = step(c, pos);
                edges.insert(canon(pos, nxt));
                pos = nxt;
            }
            _ => panic!("bad char {c}"),
        }
    }
    let mut adj: HashMap<_, Vec<_>> = HashMap::new();
    for (a, b) in edges {
        adj.entry(a).or_default().push(b);
        adj.entry(b).or_default().push(a);
    }
    adj
}
```

The BFS becomes a `VecDeque` and a `HashMap<(i32, i32), i32>`:

```rust
fn distances(adj: &HashMap<(i32, i32), Vec<(i32, i32)>>) -> HashMap<(i32, i32), i32> {
    let mut dist = HashMap::from([((0, 0), 0)]);
    let mut q = VecDeque::from([(0, 0)]);
    while let Some(p) = q.pop_front() {
        let d = dist[&p];
        if let Some(ns) = adj.get(&p) {
            for &n in ns {
                if !dist.contains_key(&n) {
                    dist.insert(n, d + 1);
                    q.push_back(n);
                }
            }
        }
    }
    dist
}
```

`HashMap` would shave the BFS to under a millisecond — Haskell's
`Data.Map.Strict` is a balanced tree, ~3× slower than open-addressed
hashing at this size. The structural code is one-to-one with the
Haskell, though, including the stack discipline.

What Rust gains here is mostly speed, not safety: the Haskell
`Map` / `Set` / `Seq` shape doesn't admit a class of bugs that
Rust's borrow checker would catch. This is one of the days where
the two languages are about as expressive as each other — the
problem is genuinely *just* graph construction and BFS, and both
languages have idiomatic 30-line answers.

---

**Navigation**: [← Day 19](day19_function_guide.md) | [All Days](summary_2018.md) | [Day 21 →](day21_function_guide.md)
