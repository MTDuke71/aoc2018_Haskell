# Day 08: Memory Maneuver -- Function Guide

**Problem**: A flat list of integers encodes a tree. Each node is laid out as `<numChildren> <numMeta> <child_1> <child_2> ... <meta_1> <meta_2> ...`, where every child is itself a node in the same shape. Part 1 sums every metadata entry across the whole tree. Part 2 computes the root's "value": leaves sum their own metadata; internal nodes treat each metadata entry as a 1-based index into their children and sum the referenced children's values (skipping zero / out-of-range, double-counting repeats).
**Answers**: Part 1 = **41521**, Part 2 = **19990**
**Runtime** (mean, criterion `-O2`): Parse = **8.297 ms** | Part 1 = **22.18 µs** | Part 2 = **10.67 µs** | **Total = 8.330 ms**
**Code**: [Day08.hs](../../src/Day08.hs)
**Tests**: [Day08Spec.hs](../../test/Day08Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day08"`
**Problem statement**: [day08.md](day08.md)

**New concepts this day** (beyond Days 0--7):

- **Recursive algebraic data types**. `data Tree = Tree { children :: ![Tree], metadata :: ![Int] }` -- the first day where a `data` declaration *refers to itself*. Mechanically the same shape as a Rust `struct Tree { children: Vec<Tree>, metadata: Vec<i32> }`, but the recursion is an everyday Haskell building block (every list `[a]` is itself a recursive ADT), so no `Box` ceremony is needed.
- **State-threading by return tuple**. `parseTree :: [Int] -> (Tree, [Int])` consumes a prefix of the token stream and hands back the parsed node *and* the leftover tokens. The caller feeds that leftover into the next call. This is the manual, beginner-friendly version of the `State` monad we will meet later -- no monads required to understand the pattern.
- **`splitAt :: Int -> [a] -> ([a], [a])`**. One-pass split of a list at an index, returning both halves.
- **`zip` against an infinite list**. `zip [1..] xs` attaches a 1-based index to each element. Laziness makes the infinite `[1..]` safe -- `zip` stops at the shorter input.
- **`lookup :: Eq k => k -> [(k, v)] -> Maybe v`**. Linear scan of an association list, returning `Nothing` if the key is missing. Maps `Maybe` semantics directly onto "skip references to non-existent children."
- **`mapMaybe :: (a -> Maybe b) -> [a] -> [b]`** from `Data.Maybe`. Maps a partial function across a list, dropping `Nothing` and unwrapping `Just` in one pass. Cleaner than `catMaybes . map`.
- **`Generic`-derived `NFData`**. `deriving (Generic)` plus an empty `instance NFData Tree` gives criterion the deep-evaluation it needs to measure the parser without leaving thunks behind. First day where the parsed type is a custom recursive ADT, so first day this matters.

Pattern matching on constructors, list comprehensions with guards, `foldl'`, and the `Map`/`Set` Prelude are all reused from Days 2--7 and not re-explained here.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Data model](#data-model)
3. [`parseInput`](#parseinput)
4. [`parseTree` -- the recursive parser, token by token](#parsetree)
5. [`parseChildren`](#parsechildren)
6. [`sumMetadata` and `part1`](#sumMetadata-and-part1)
7. [`nodeValue` -- the Part 2 fold, token by token](#nodevalue)
8. [`part2`](#part2)
9. [`solve`](#solve)
10. [Tests](#tests)
11. [Benchmarks](#benchmarks)
12. [Why state-threading by tuple is the manual `State` monad](#why-state-threading-by-tuple-is-the-manual-state-monad)
13. [Possible optimizations](#possible-optimizations)
14. [Key patterns](#key-patterns)
15. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The license file is one long line of space-separated integers -- 16 KB of them in the actual input, ~6500 tokens. The number stream encodes a tree by depth-first preorder:

- The first integer is the number of children of the current node.
- The second integer is the number of metadata entries.
- Then come the children in order, each laid out by the same rule (depth-first descent).
- Finally come this node's metadata entries.

That order is what makes a single recursive parser work: by the time you reach the metadata, you have already consumed every descendant. There is no length-prefix on the entire subtree -- you only know how many *direct* children to expect, and the recursion takes care of the rest.

**Part 1** asks for the total of every metadata entry in the whole tree. There is no use for the tree's *shape* in Part 1 -- you could collect the answer from a streaming pass that ignores child/metadata structure entirely, as long as it tokenises in the right order.

**Part 2** *needs* the shape. Each internal node's value is `sum [ value (children !! (i-1)) | i <- metadata, i in range ]`, where references to child positions that do not exist are dropped (zero is one such case, and any number greater than the child count is another). A leaf's value is just `sum metadata`.

Two parts share the parsed tree. The teaching arc this day is the parser; the algorithms on top are short.

---

## Data model

```haskell
data Tree = Tree
  { children :: ![Tree]
  , metadata :: ![Int]
  } deriving (Eq, Show, Generic)

instance NFData Tree
```

A record with two fields, both strict (`!`). The recursion is in `children :: ![Tree]` -- a tree's children are themselves trees. This is the first day where a `data` declaration refers to itself; if it feels strange, remember that `[Char]` (which is just `String`) is also a recursive ADT (`data [a] = [] | a : [a]`), so you have been using recursive types all along.

### Why strict fields?

The `!` on each field tells GHC to *evaluate* the field to weak-head normal form when the constructor is built, instead of storing a thunk. For Part 1 the laziness would not bite us -- `sumMetadata` walks the whole tree and forces everything anyway. But the cost of `!` is essentially zero, the win is real for any future code that touches the tree without forcing it, and "`!` on every field of a parser-output record" is a habit worth forming early.

### `deriving (Generic)` and `instance NFData Tree`

Criterion's `nf` benchmark forces the *full* result to normal form. For `Int` and `String` results that happens automatically (their `NFData` instances ship with the library). For our custom `Tree`, we need to tell `Control.DeepSeq` how to walk the structure.

The shortest path:

```haskell
{-# LANGUAGE DeriveGeneric #-}
import GHC.Generics  (Generic)
import Control.DeepSeq (NFData)

data Tree = ... deriving (..., Generic)
instance NFData Tree
```

`Generic` is a type-class instance derived by GHC that exposes the structure of `Tree` in a generic shape (a sum of products of fields). `NFData` has a default implementation that walks any `Generic` type and forces every field. So the empty `instance NFData Tree` body is *not* a placeholder -- it is the complete instance, picked up from the default. No method bodies needed.

Without it, `cabal bench day08` would not type-check (`nf parseInput :: ... -> Benchmarkable` requires `NFData (parseInput input)`). Day 7 did not need this because `Edge = (Char, Char)` already has a stock `NFData` instance.

---

## `parseInput`

```haskell
parseInput :: String -> Tree
parseInput = fst . parseTree . map read . words
```

Read right-to-left like a Unix pipeline:

1. **`words`** splits the raw input on whitespace, producing a `[String]`. Whitespace includes spaces *and* newlines, so the trailing newline contributes nothing.
2. **`map read`** converts each token to an `Int`. `read :: Read a => String -> a` is a partial function -- it panics on garbled input -- but for trusted AoC input that is fine. (In production code the discipline would be `readMaybe` plus a `Maybe` chain.)
3. **`parseTree`** consumes the `[Int]` and produces `(Tree, [Int])` -- a parsed node plus whatever tokens remain.
4. **`fst`** drops the leftover and keeps just the root tree. The actual input has no leftover, but defensively returning only the root keeps `parseInput`'s public type a clean `String -> Tree`.

The `(.)` operator is function composition -- `(f . g) x = f (g x)`. We have used it on every prior day; it is the glue between stages of a pipeline.

### Why parse to a list of `Int` first, then walk it?

Two-stage tokenise-then-parse is much easier to teach than a single-pass character-level parser. Stage 1 is "tokens out of text"; stage 2 is "tree out of tokens." `parseTree` only ever has to think about *integers*, not whitespace or end-of-line.

For performance, this *is* slower than streaming parsers (we allocate the full `[Int]` once, plus the original `[String]` and individual `String` tokens). The 8.3 ms parse time is dominated by `read :: String -> Int`, which is a generic mechanism that goes through an intermediate parser combinator. A faster but less idiomatic approach would tokenise and parse a strict `Data.ByteString.Char8` -- see [Possible optimizations](#possible-optimizations).

---

## `parseTree`

```haskell
parseTree :: [Int] -> (Tree, [Int])
parseTree (nChildren : nMeta : rest0) =
  let (cs,  rest1) = parseChildren nChildren rest0
      (mds, rest2) = splitAt        nMeta    rest1
  in  (Tree cs mds, rest2)
parseTree _ =
  error "Day08.parseTree: ran out of input before reading a node header"
```

The recursive workhorse. Pattern-matches the first two integers (the node header), peels off the children with `parseChildren`, then peels off the metadata with `splitAt`, then packs the result.

### Token by token through the matching arm

| Token / phrase                                 | Meaning |
|------------------------------------------------|---------|
| `parseTree (nChildren : nMeta : rest0)`        | Pattern match: the first integer becomes `nChildren`, the second `nMeta`, and everything after is bound as `rest0`. The `(:)` constructor is the list cons -- `[10, 11, 12]` matches `(10 : 11 : [12])` or `(10 : 11 : 12 : [])`. |
| `let (cs, rest1) = parseChildren nChildren rest0` | Tuple-pattern destructuring on the recursive child parser's result. `cs :: [Tree]` is the parsed children, and `rest1 :: [Int]` is what remains of the token stream after consuming all of them. |
| `(mds, rest2) = splitAt nMeta rest1`           | After the children, the next `nMeta` integers are this node's metadata; `splitAt nMeta rest1` returns them paired with the unconsumed tail. |
| `(Tree cs mds, rest2)`                         | Pack the parsed `Tree` together with the leftover tokens. The leftover flows back to the caller, who will use it for the *next* node. |
| `parseTree _ = error "..."`                    | The catch-all arm: if `parseTree` is called on a list shorter than two elements, the input was truncated. We throw rather than return a partial tree because the AoC input is trusted -- if we ever hit this arm, the bug is in our parser, not the puzzle. |

### `splitAt`

```haskell
splitAt :: Int -> [a] -> ([a], [a])
```

Split a list at a given index, returning the prefix of that length and the rest. `splitAt 3 [10, 11, 12, 99] == ([10, 11, 12], [99])`. One pass through the list, both halves returned together. This is exactly the right tool for "the next `n` items are mine; everything after is yours."

If the list is shorter than `n`, `splitAt` happily returns the whole list as the prefix and `[]` as the suffix -- it does not throw. For our use case that is a silent bug: we would build a `Tree` with too few metadata entries and the leftover would be `[]`. We accept the risk because `parseInput` guarantees a well-formed token stream from `read`-ing AoC input.

### Where does the recursion happen?

`parseTree` does not call itself. The recursion lives in `parseChildren`, which calls `parseTree` once per child. The split makes the two responsibilities crisp: `parseTree` peels exactly *one* node; `parseChildren` peels *N* sibling nodes. Every recursive node-parse goes through exactly one `parseTree` and (potentially) one `parseChildren` -- a clean tree of calls that mirrors the puzzle's tree of nodes.

---

## `parseChildren`

```haskell
parseChildren :: Int -> [Int] -> ([Tree], [Int])
parseChildren 0 xs = ([], xs)
parseChildren n xs =
  let (c,  xs')  = parseTree xs
      (cs, xs'') = parseChildren (n - 1) xs'
  in  (c : cs, xs'')
```

Parse exactly `n` sibling trees in left-to-right order, threading the leftover tokens between them.

| Token / phrase                              | Meaning |
|---------------------------------------------|---------|
| `parseChildren 0 xs = ([], xs)`             | Base case: zero children to parse, no children consumed, input unchanged. |
| `parseChildren n xs = ...`                  | Recursive case: one child, then `n - 1` more. |
| `(c, xs') = parseTree xs`                   | Parse one child, consuming some prefix of `xs` and naming the remainder `xs'`. |
| `(cs, xs'') = parseChildren (n - 1) xs'`    | Recursively parse the remaining `n - 1` siblings, starting from where the previous parse left off. Note: pass `xs'`, not `xs`. The leftover *threads through*. |
| `(c : cs, xs'')`                            | Cons the first child onto the recursively-parsed tail; return the final leftover. |

### The state-threading idiom in one phrase

Each call returns "what I parsed *and* what's left for you." The caller never has to track a cursor; it just feeds the leftover into the next call. The tail recursion keeps the `(leftover)` value moving forward; by the time we're back at the top, the leftover is whatever the entire subtree did not consume.

This is the *manual* version of the `State` monad. Once we meet `State`, the same parser would look like:

```haskell
-- with State monad (preview, not in this file):
parseTree' :: State [Int] Tree
parseTree' = do
  nChildren <- popInt
  nMeta     <- popInt
  cs        <- replicateM nChildren parseTree'
  mds       <- popInts nMeta
  pure (Tree cs mds)
```

But we are not there yet. The hand-rolled `(result, leftover)` version is precisely what `State` desugars to under the hood, and writing it out explicitly first makes the eventual jump to `State` feel inevitable, not magical.

### Why not `replicateM_` or a fold?

`replicateM` requires a monad (because each iteration depends on the previous one's effect on the implicit state). Without monads, the natural shape *is* a hand-written recursive function. We could use `foldr` or `mapAccumL`, but the explicit recursion makes the threading visible, which is the whole pedagogical point.

---

## `sumMetadata` and `part1`

```haskell
sumMetadata :: Tree -> Int
sumMetadata (Tree cs mds) = sum mds + sum (map sumMetadata cs)

part1 :: Tree -> Int
part1 = sumMetadata
```

Pattern-match the constructor, sum this node's metadata, recurse on each child, sum those results, add. Three lines of code that say exactly what the puzzle says.

### Why `sum (map sumMetadata cs)` and not `sum [ sumMetadata c | c <- cs ]`?

Both are fine. `map` + `sum` is the more common Prelude idiom and reads "evaluate `sumMetadata` on every child, then sum the results"; the comprehension says the same thing in a slightly more verbose syntax. `map` wins on brevity for the simple "apply f to each, then aggregate" case; comprehensions win when there is also a guard or a pattern.

### `part1` as an alias

`part1 = sumMetadata` is a one-line alias. Two reasons to keep both names:

1. The dispatcher (`app/Main.hs`) calls `part1` -- consistency across days matters more than concision.
2. `sumMetadata` describes *what* the function does; `part1` says *which puzzle question* it answers. Two different vocabularies; both are useful in different contexts.

---

## `nodeValue`

```haskell
{-# ANN nodeValue ("HLint: ignore Avoid lambda using `infix`" :: String) #-}
nodeValue :: Tree -> Int
nodeValue (Tree []  mds) = sum mds
nodeValue (Tree cs  mds) =
  let indexed :: [(Int, Int)]
      indexed = zip [1..] (map nodeValue cs)
  in  sum (mapMaybe (\i -> lookup i indexed) mds)
```

Two equations -- the leaf case and the internal case -- mirroring the puzzle's split into "no children" vs "has children."

### The leaf case

```haskell
nodeValue (Tree [] mds) = sum mds
```

`[]` in the pattern position matches the empty list. If `children` is `[]`, this node is a leaf, and its value is just the sum of its own metadata. That is the puzzle's exact rule for B and D.

### Token by token through the internal case

| Token / phrase                                | Meaning |
|-----------------------------------------------|---------|
| `nodeValue (Tree cs mds)`                     | This pattern fires when the leaf pattern did not, i.e. when `cs` is non-empty. Both `cs` and `mds` are bound. |
| `let indexed :: [(Int, Int)]`                 | Local binding with an explicit type. Not strictly required (GHC would infer it), but writing it out turns the reader's eyes to "this is an association list of (1-based index, child value) pairs." |
| `indexed = zip [1..] (map nodeValue cs)`      | Two operations in one line. `map nodeValue cs` evaluates each child's value, returning `[Int]` of the same length as `cs`. `zip [1..] ...` then prefixes a 1-based index to each. |
| `sum (mapMaybe (\i -> lookup i indexed) mds)` | For each metadata entry `i`, look it up in the indexed child-value list. `lookup` returns `Maybe Int` -- `Just v` when `i` is in range and `Nothing` when it is not. `mapMaybe` discards the `Nothing`s and unwraps the `Just`s. `sum` adds the survivors. |

### `zip [1..]`

```haskell
zip :: [a] -> [b] -> [(a, b)]
```

Pair two lists element-wise; stop at the shorter one. The trick we use here is that `[1..]` is an *infinite* list of `Int` -- `[1, 2, 3, 4, 5, ...]` going on forever. In a strict language that would be a memory bomb; in Haskell it is fine because the values are produced lazily. `zip` only ever asks `[1..]` for as many integers as `cs` has children, so the rest of the infinite list is never evaluated.

This is the canonical "I want a 1-based index" idiom. The 0-based version is `zip [0..]`. Both are O(n) in the length of the finite input and allocate exactly that many cells.

### `lookup`

```haskell
lookup :: Eq k => k -> [(k, v)] -> Maybe v
```

Linear scan of an association list. Returns `Just v` on the first key match, `Nothing` if the key is absent. Three properties make `lookup` the right tool here:

1. *Returns `Maybe`*. A metadata entry of `0` does not match any 1-based key. A metadata entry of `99` (out of range) does not match either. Both fall out as `Nothing`, exactly matching the puzzle's "skip this reference" rule -- we did not have to write any explicit bounds-check.
2. *Returns the first match only*. Our `indexed` list has unique keys (`[1..n]`), so "first match" and "the match" coincide. `lookup` would still work if there were duplicate keys, but the question becomes "which `Just`?" -- not relevant here.
3. *O(n)* per call. For Part 2 we call `lookup` once per metadata entry, walking up to the full child list each time. For our input the worst node has ~9 children and ~9 metadata, so each call is at most 9 element comparisons. With ~600 internal nodes, total `lookup` work is in the low-thousands of comparisons -- imperceptible.

If `n` were thousands per node, a `Data.Map.Strict.Map Int Int` for `indexed` would drop to O(log n) per lookup. The list-of-pairs version stays clearer at our scale.

### `mapMaybe`

```haskell
mapMaybe :: (a -> Maybe b) -> [a] -> [b]
```

Apply a function that may fail to each element; keep only the successes, unwrapping the `Just`. `mapMaybe f xs = catMaybes (map f xs)` semantically, but in one pass and with one allocation instead of two.

The lambda `\i -> lookup i indexed` is the partial function. For every `i` in `mds`, `lookup` returns `Just v` (the referenced child's value) or `Nothing` (out of range). `mapMaybe` collects only the survivors into `[Int]`, which `sum` then totals.

### Why share via the `let`?

The expression `map nodeValue cs` pre-computes every child's value *once* and stores them in `indexed`. If we had instead written

```haskell
sum [ nodeValue (cs !! (i - 1)) | i <- mds, 1 <= i, i <= length cs ]  -- DON'T
```

we would re-evaluate `nodeValue` on the same child every time the metadata pointed to it. The puzzle explicitly says "a child node can be referenced multiple times and counts each time," so duplicates *do* occur. By storing computed values in `indexed`, each child's recursive value is computed exactly once and reused. Sharing through `let` is what gives us this memoisation for free -- no `Data.Map` cache, no manual memoisation table.

### `{-# ANN nodeValue ... #-}`

The HLint linter would suggest replacing `\i -> lookup i indexed` with the point-free `(`lookup` indexed)` (using backtick-infix syntax plus a right section). That equivalent is correct Haskell but stacks two pieces of unfamiliar syntax for a beginner -- you have to know that backticks turn a prefix function into infix *and* that `(`f` x)` partial-applies the second argument.

The lambda is more readable because it names its argument and reads left-to-right. The annotation `{-# ANN nodeValue ("HLint: ignore ...") #-}` silences the lint for this one binding without disabling it elsewhere. We will absorb backtick-infix and right-sections later, in a context where they actually clarify the code.

---

## `part2`

```haskell
part2 :: Tree -> Int
part2 = nodeValue
```

One-line alias. Same reasoning as `part1 = sumMetadata`: keep the algorithmic name and the puzzle-question name as two different identifiers.

---

## `solve`

```haskell
solve :: String -> IO ()
solve contents = do
  let tree = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 tree))
  putStrLn ("  part 2: " ++ show (part2 tree))
```

Parse once via the shared `let tree`, print both answers. The two parts share the parsed tree; sharing through `let` means `parseInput` runs exactly once even though both `part1 tree` and `part2 tree` reference it. Haskell laziness plus `let`-binding gives us the single-parse guarantee for free, and `tree` lives long enough that both reads happen before garbage collection.

---

## Tests

Coverage in [Day08Spec.hs](../../test/Day08Spec.hs):

1. **`parseTree` consumes the entire example token stream** -- after parsing the root, `leftover == []`. This is the strongest single check that the parser is shaped correctly: any off-by-one in `splitAt` or `parseChildren` would show up as a non-empty leftover.
2. **Structural breakdown of the example tree** -- root has 2 children and metadata `[1, 1, 2]`; child B is a leaf with metadata `[10, 11, 12]`; child C has one child D and metadata `[2]`; D is a leaf with metadata `[99]`. Pinning the example's exact shape catches regressions in the recursion that would still happen to give the right metadata sum by accident.
3. **`nodeValue` cases from the puzzle text** -- B = 33, D = 99, C = 0, A = 66. The puzzle gives these explicitly; pinning each one makes regressions show up against the documented case rather than the aggregate.
4. **Puzzle example aggregates** -- Part 1 = 138 and Part 2 = 66.
5. **Actual input** -- Part 1 = 41521, Part 2 = 19990.

The structural tests are unusually granular because Day 8's correctness pivots on the parser, and a parser bug can hide in the actual-input answer (a tree with thousands of nodes can swallow off-by-one errors in the recursive descent without changing the metadata sum). Spelling out the example tree's shape makes any future refactor's first failure point clear.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean       | What it times |
|--------------------|-----------:|---------------|
| `day08/parseInput` | 8.297 ms   | `lines` + `words` + `read` over ~6500 integer tokens (~16 KB of text). |
| `day08/part1`      | 22.18 µs   | One depth-first pass summing metadata across ~600 internal nodes. |
| `day08/part2`      | 10.67 µs   | Depth-first pass with `zip [1..]` + `lookup`-per-metadata; faster than Part 1 because most nodes are leaves and skip the indexing work. |
| `day08/combined`   | 8.567 ms   | End-to-end from raw string. |

**Total = Parse + Part 1 + Part 2 = 8.330 ms.**

The parser is **~99% of total runtime**. The two parts together cost ~33 µs -- below the noise floor of a benchmark. This is the first day where the parser conclusively dominates and the algorithms are essentially free.

### Why is Part 2 *faster* than Part 1?

Counter-intuitive at first: Part 2 does *more* work per internal node (it builds an `indexed` list, calls `lookup` per metadata entry, recurses with `mapMaybe`), and yet it runs at half the time of Part 1. Two effects compound:

1. **Lazy `sum mds + sum (map sumMetadata cs)` has overhead Part 2 skips.** Part 1 always computes both sums, even at leaves where one is `0`. Part 2's leaf case (`nodeValue (Tree [] mds) = sum mds`) short-circuits immediately for leaves -- no second `sum` over an empty list, no `map` allocation. The actual input has many leaves, so the saving compounds.
2. **`map` over `cs` allocates a list of `Int`s in both parts**, but Part 2 also forces those values through `lookup`, which in turn forces them, which means GHC can keep them on the stack and avoid heap allocation through better strictness. Part 1's intermediate `map sumMetadata cs` tends to materialise as a list, then get summed.

A profiler would confirm; the 2x gap is small enough that GC cadence and inlining decisions are plausible explanations. The takeaway is "don't assume more code = slower" -- structural choices (leaf vs. internal recursion) and laziness interact in ways that beat a token-counting heuristic.

---

## Why state-threading by tuple is the manual `State` monad

The `parseTree :: [Int] -> (Tree, [Int])` shape is the same thing as a `State [Int] Tree`. Worth pausing on the equivalence because it makes the eventual transition to `State` feel like notation, not a new concept.

### The pattern

Every parser function in this file has the same arrow shape:

```
parseTree     :: [Int] -> (Tree,   [Int])
parseChildren :: Int -> [Int] -> ([Tree], [Int])  -- (count, then state)
```

The input is "the current state plus my arguments," and the output is "my result paired with the new state." Composition is *call this parser, then call the next one with the leftover the first parser produced*.

### What `State` does for us

`Control.Monad.State` from `mtl` packages this same pattern as a type:

```haskell
newtype State s a = State { runState :: s -> (a, s) }
```

A `State s a` is *exactly* a function from state to (result, new state) -- the same shape as our parsers, with `s = [Int]` and `a = Tree`. The library then provides:

- `get :: State s s`           -- "what's the current state?"
- `put :: s -> State s ()`     -- "set the state to this"
- `modify :: (s -> s) -> State s ()` -- "transform the state"
- `do`-notation for sequencing.

In `do`-notation, `parseTree` would look like:

```haskell
parseTree :: State [Int] Tree
parseTree = do
  nChildren <- popInt
  nMeta     <- popInt
  cs        <- replicateM nChildren parseTree
  mds       <- popInts nMeta
  pure (Tree cs mds)
```

The leftover threading happens in the desugaring of `<-`. We do not see it in the source. That is `State`'s sole superpower.

### Why we wrote it by hand instead

Three reasons we will keep doing manual threading for a while longer:

1. **The threading is the lesson.** Hiding it inside `State` *before* you understand it is bad pedagogy -- you would just be using a black box. After you have written `(result, leftover)` plumbing twice, `State` is "oh, *that's* what it abstracts away."
2. **`State` introduces a new typeclass (`Monad`) and a new control structure (`do`).** Each of those is a multi-day topic. We can teach the parsing pattern *without* teaching them simultaneously by writing the threading explicitly.
3. **Performance is the same.** The hand-written version is what `State` desugars to, with the same allocation profile. Choosing `State` has no runtime cost or benefit; the choice is purely about syntax and abstraction.

Day 8's parser is the manual control case. When the puzzle pressure goes up (a parser with optional matches, branching, look-ahead) we will reach for `megaparsec` -- which uses the `State`-style monadic plumbing under the hood -- and the conceptual jump will be small.

---

## Possible optimizations

### `Data.ByteString.Char8` parser to halve the parse time

`parseInput` is **8.3 ms**, dominated by `read :: String -> Int` over ~6500 tokens. `read` walks each character through a generic parsing dispatch. A direct integer parse over a strict `ByteString` skips that dispatch:

```haskell
import qualified Data.ByteString.Char8 as BS
import Data.Maybe (fromMaybe)

parseInput' :: BS.ByteString -> Tree
parseInput' = fst . parseTree . parseInts
  where
    parseInts :: BS.ByteString -> [Int]
    parseInts s = case BS.readInt (BS.dropWhile (== ' ') s) of
      Nothing       -> []
      Just (n, s')  -> n : parseInts s'
```

`BS.readInt` is a hand-tuned integer parser that runs on the raw bytes -- typically 5--10x faster than `read`. With the parser dropped to ~1 ms, total time would be dominated by file I/O.

For Day 8 the extra dependency is overkill -- the answer comes back in under a second either way. Worth doing when puzzle inputs grow into the megabytes.

### Streaming Part 1 without building the tree

Part 1 only needs the metadata sum, not the tree shape. A streaming variant could pop the header off `[Int]`, push the leaf-count requirement onto a stack, and accumulate metadata as it goes -- never materialising a `Tree`:

```haskell
streamingPart1 :: [Int] -> Int
streamingPart1 = go [] 0
  where
    go []        acc []       = acc
    go (m : ms)  acc xs       = go ms (acc + m) xs       -- pending metadata
    go pending   acc (n : k : xs) =                       -- header
      ... pseudo-code: descend into n children, then collect k metadata ...
```

This would avoid the (small) cost of building 600 `Tree` nodes. Part 1 already runs in 22 µs, so the win would be a few µs at most -- below the noise floor. A teaching exercise more than a real optimisation.

### Lazy vs. strict child evaluation in `nodeValue`

Currently `map nodeValue cs` forces every child's value, even children that no metadata entry references. For the puzzle as stated, every child has at least one referencing metadata in practice (the inputs are constructed that way), so forcing all of them is no worse than computing on demand. If a future puzzle had many "dead" children, a lazy `IntMap` of demanded child values would save those evaluations.

---

## Key patterns

1. **Recursive ADT mirrors the recursive shape of the data.** A tree-shaped puzzle wants a tree-shaped type. Resist flattening the structure into `[(parent, child)]` edge lists when the input gives you a true tree -- the algorithms on `Tree` will be one `case`-on-constructors away from reading like the puzzle text.
2. **`(result, leftover)` is the manual `State` monad.** Any time a function consumes a prefix of a stream and needs to hand the rest to the next consumer, return both as a tuple and let the caller pattern-match on it. This is the same shape `Megaparsec`, `attoparsec`, and `State [Int]` all encode under the hood.
3. **`zip [1..]` for indexed traversal.** When you need 1-based (or 0-based) indices alongside elements, pair the list against an infinite enumeration. Laziness keeps the infinite list cheap.
4. **`Maybe` + `mapMaybe` + `lookup` for "look up these indices, drop misses."** Three Prelude tools combine to express "fetch by key, allowing failure" without any explicit bounds checks. The `Maybe` chain encodes the bounds check, and `mapMaybe` collapses the cleanup.
5. **`Generic`-derived `NFData` for one-line deep-evaluation instances.** Whenever a custom ADT is the parsed-input type for a `criterion` bench, `deriving (Generic)` plus `instance NFData YourType` is the boilerplate. No method bodies needed.

---

## Side-by-side with the Rust mental model

```rust
#[derive(Debug, PartialEq, Eq)]
struct Tree {
    children: Vec<Tree>,
    metadata: Vec<i32>,
}

fn parse_input(s: &str) -> Tree {
    let mut iter = s.split_whitespace().map(|t| t.parse::<i32>().unwrap());
    parse_tree(&mut iter)
}

fn parse_tree<I: Iterator<Item = i32>>(iter: &mut I) -> Tree {
    let n_children = iter.next().unwrap() as usize;
    let n_meta     = iter.next().unwrap() as usize;
    let children   = (0..n_children).map(|_| parse_tree(iter)).collect();
    let metadata   = iter.by_ref().take(n_meta).collect();
    Tree { children, metadata }
}

fn sum_metadata(t: &Tree) -> i32 {
    t.metadata.iter().sum::<i32>()
        + t.children.iter().map(sum_metadata).sum::<i32>()
}

fn node_value(t: &Tree) -> i32 {
    if t.children.is_empty() {
        return t.metadata.iter().sum();
    }
    let child_values: Vec<i32> = t.children.iter().map(node_value).collect();
    t.metadata
        .iter()
        .filter_map(|&i| {
            let idx = (i as usize).checked_sub(1)?;
            child_values.get(idx).copied()
        })
        .sum()
}
```

Lined up:

| Concept                            | Rust                                                    | Haskell                                              |
|------------------------------------|---------------------------------------------------------|------------------------------------------------------|
| Recursive struct/ADT               | `struct Tree { children: Vec<Tree>, metadata: Vec<i32> }` | `data Tree = Tree { children :: ![Tree], metadata :: ![Int] }` |
| Tokenise to integers               | `s.split_whitespace().map(|t| t.parse().unwrap())`      | `map read . words`                                   |
| Streaming consumption              | mutable `&mut I: Iterator` advances in place            | functional `(result, leftover)` returned from each call |
| "Take next N items"                | `iter.by_ref().take(n_meta).collect()`                  | `splitAt nMeta rest1` (two-tuple result)             |
| Recursion over children            | `(0..n_children).map(|_| parse_tree(iter)).collect()`   | hand-rolled `parseChildren` with explicit threading  |
| Sum metadata of subtree            | `.metadata.iter().sum() + .children.iter().map(sum_metadata).sum()` | `sum mds + sum (map sumMetadata cs)`            |
| Skip out-of-range references       | `i.checked_sub(1)? + child_values.get(idx).copied()`    | `lookup i indexed :: Maybe Int` (zero and OOB both `Nothing`) |
| Drop misses / sum survivors        | `.filter_map(...).sum()`                                | `sum (mapMaybe (\i -> lookup i indexed) mds)`        |
| Memoise child values               | `let child_values: Vec<i32> = t.children.iter().map(node_value).collect()` | `let indexed = zip [1..] (map nodeValue cs)`     |

The Rust version uses a *mutable* iterator (`&mut I`) to thread the cursor through the recursive calls. The Haskell version uses an *immutable* `[Int]` and threads the leftover via tuple returns. Both express "consume some, hand the rest to the next caller" -- one mutates a borrowed cursor, the other shadows a name.

The most interesting line is `child_values.get(idx).copied()` vs `lookup i indexed`. Rust's `Vec::get` returns `Option<&T>`, which `.copied()` converts to `Option<T>` -- the `Option` already encodes the OOB check. Haskell's `lookup` does the same with `Maybe`, except it uses an association list rather than indexed access. Both versions get the "skip missing" rule for free from the option/maybe type.

---

**Navigation**: [Problem statement](day08.md) | [Summary table](summary_2018.md) | [<- Day 7](day07_function_guide.md) | [Day 9 ->](day09_function_guide.md)
