# Day 03: No Matter How You Slice It — Function Guide

**Problem**: ~1300 fabric claims, each a rectangle on a 1000×1000 inch sheet. Part 1 counts how many square inches lie under two or more claims; Part 2 finds the unique claim ID whose rectangle does not overlap any other.
**Answers**: Part 1 = **111485**, Part 2 = **113**
**Runtime** (mean, criterion `-O2`): Parse = **4.05 ms** | Part 1 = **175.1 ms** | Part 2 = **170.8 ms** | **Total ≈ 350.0 ms**
**Code**: [Day03.hs](../../src/Day03.hs)
**Tests**: [Day03Spec.hs](../../test/Day03Spec.hs)
**Bench**: [bench/Main.hs](../../bench/Main.hs) — `cabal bench --benchmark-options="--match prefix day03"`
**Problem statement**: [day03.md](day03.md)

**New concepts this day** (beyond Days 0–2):

- **Records with named fields** (`data Claim = Claim { claimId :: !Int, ... }`) — the first day where a tuple would have grown unwieldy. Five `Int` fields with names beat `(Int, Int, Int, Int, Int)`.
- **Strict fields** (the `!Int`). The bang annotation forces every field to weak-head normal form when the constructor is applied — for primitive types like `Int` that means *fully evaluated*. With ~1300 records on the heap this avoids carrying around a thunk per field.
- **`NFData` and `rnf`** — the `deepseq` class for forcing a value all the way to *normal* form (vs *weak-head* normal form). The solution itself never calls `rnf`; the instance exists only so the benchmark suite (which depends on `criterion`) can use `nf` on `[Claim]` values. Days 0–2 didn't need this because `[Int]` and `[String]` already have `NFData` from base/`deepseq`.
- **`Map.fromListWith`** — builds a `Map` from a list of `(key, value)` pairs, merging duplicates with a combining function. The one-liner equivalent of Day 2's `foldl' (\m c -> Map.insertWith (+) c 1 m) Map.empty`.
- **`Map.findWithDefault`** — read a value from a `Map`, returning a supplied default if the key is absent. Cleaner than `fromMaybe 0 . Map.lookup k`.
- **`Data.List.find`** — the first `Just` from `[Maybe a]`, written as a search over `[a]` with a predicate. Type: `(a -> Bool) -> [a] -> Maybe a`.
- **The "replace-then-tokenise" parsing trick** — replace every separator with a space, then `words` and `read`. Cuts a regex/parser into one line for inputs that are punctuation-separated `Int`s.
- **Nested list comprehensions enumerating a 2-D region** — `squares` walks `[(x, y)]` over a rectangle by combining two generators.

---

## Table of contents
1. [Problem summary](#problem-summary)
2. [Data model — the `Claim` record](#data-model--the-claim-record)
3. [`parseInput` and `parseClaim`](#parseinput-and-parseclaim)
4. [`squares` — the 2-D walk](#squares--the-2-d-walk)
5. [`countMap` — the fabric as a frequency `Map`](#countmap--the-fabric-as-a-frequency-map)
6. [`part1` — count overlapping squares](#part1--count-overlapping-squares)
7. [`part2` — find the lone claim](#part2--find-the-lone-claim)
8. [`solve`](#solve)
9. [Tests](#tests)
10. [Benchmarks](#benchmarks)
11. [Possible optimization — share `countMap` between parts](#possible-optimization--share-countmap-between-parts)
12. [Possible optimization — `IntMap` keyed by `x * 1001 + y`](#possible-optimization--intmap-keyed-by-x--1001--y)
13. [Key patterns](#key-patterns)
14. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The Elves have ~1300 claims on a square of fabric at least 1000 inches on a side. Each claim is a line of the form

```
#1 @ 258,327: 19x22
```

reading: claim ID `1`, top-left corner `(258, 327)` inches from the fabric's `(left, top)` edges, rectangle of width `19` and height `22`. Many claims overlap; some do not.

- **Part 1**: how many *square inches* of fabric lie under two or more claims. (Not "how many overlap pairs," not "how many overlapping rectangles" — the count is over individual `(x, y)` cells.)
- **Part 2**: there is exactly one claim whose rectangle does not overlap any other claim. Return its ID.

Worked three-claim example from the puzzle:

```
#1 @ 1,3: 4x4
#2 @ 3,1: 4x4
#3 @ 5,5: 2x2
```

Visually:

```
........
...2222.
...2222.
.11XX22.
.11XX22.
.111133.
.111133.
........
```

Four squares marked `X` are claimed by both `#1` and `#2`. Claim `#3` does not overlap anything. So Part 1 = `4`, Part 2 = `3`.

Both parts share the same auxiliary structure: a `Map (Int, Int) Int` from each fabric square to "how many claims cover it." Part 1 is "how many entries have value ≥ 2"; Part 2 is "which claim has *all* of its squares mapped to exactly 1."

---

## Data model — the `Claim` record

```haskell
data Claim = Claim
  { claimId :: !Int  -- the #NNN tag
  , left    :: !Int  -- inches from the left edge of the fabric
  , top     :: !Int  -- inches from the top edge of the fabric
  , width   :: !Int  -- inches wide
  , height  :: !Int  -- inches tall
  } deriving (Eq, Show)

type Puzzle = [Claim]
```

This is the first day where a bare tuple would hurt readability. `(Int, Int, Int, Int, Int)` has no positional clues; `Claim { left = 258, top = 327, ... }` reads itself.

### What `data` declares

```haskell
data Claim = Claim { ... } deriving (Eq, Show)
```

Three things in one line:

1. **`data Claim`** introduces a brand-new type called `Claim`. This is *the type-level name*.
2. **`= Claim { ... }`** introduces a *constructor* (also called `Claim` here — the type and the constructor have separate namespaces, so reusing the name is fine and conventional). This is *the value-level name* you call to build one.
3. **`deriving (Eq, Show)`** auto-generates `==` and `show` for the type. Without these, `claim1 == claim2` and `print claim1` would not compile.

So `Claim` denotes both the type *and* the function `Int -> Int -> Int -> Int -> Int -> Claim` that builds one.

### Named-field syntax — what the field labels actually mean

Each label inside the braces does double duty. After this declaration, two new functions exist for each field:

```haskell
-- automatically defined by the named-field syntax:
claimId :: Claim -> Int
left    :: Claim -> Int
top     :: Claim -> Int
width   :: Claim -> Int
height  :: Claim -> Int
```

So `left c` accesses the `left` field of `c` — record syntax is *just* shorthand for declaring a constructor *and* a bunch of selector functions. There is no `c.left` syntax in Haskell (without `OverloadedRecordDot`); you write `left c`, which reads as "the `left` of `c`."

The trade-off is that field names live in the *whole module's* namespace. We can never have another type in `Day03` with a `left` field, because `left` would then be ambiguous. For 25 days each in their own module this is fine; in larger codebases people reach for the `RecordWildCards`, `DuplicateRecordFields`, or `OverloadedRecordDot` extensions.

### Building one — three equivalent forms

```haskell
-- positional (in declaration order)
Claim 1 1 3 4 4

-- named (any order, must mention every field)
Claim { claimId = 1, left = 1, top = 3, width = 4, height = 4 }

-- record-update (start from an existing claim, change one field)
let c = Claim { claimId = 1, left = 1, top = 3, width = 4, height = 4 }
in  c { left = 2 }
```

The named form is the standard for tests (see `Day03Spec.hs`), because it survives field reorderings without silently flipping `width` and `height`.

### `!Int` — strict fields

```haskell
data Claim = Claim
  { claimId :: !Int
  , ...
  }
```

The `!` (a *bang annotation*) says: *"when this constructor is applied, evaluate this field to weak-head normal form before storing it."* For `Int`, WHNF is the same as fully-evaluated — there is no further structure to walk.

Without the `!`, `Claim 1 1 3 4 4` would store five thunks (`<thunk for 1>`, `<thunk for 1>`, ...). Each thunk is a heap object that, when forced, evaluates the underlying expression and replaces itself with the result. For literal `1` the thunk is silly — there is nothing to compute — but for the parsed `read xs :: Int` we use during construction, the thunk would defer the actual `String → Int` work until *something else* finally read the field.

The `!` short-circuits this: parse cost is paid up front, the record stores 5 unboxed-ish `Int`s, and we never trip over a stale thunk later.

**Rule of thumb**: **strict fields by default for primitive types** (`Int`, `Double`, `Char`, `Bool`). Lazy fields are useful when you have an expensive value you might never read (e.g. error messages constructed only on failure); they are usually wrong for hot data.

### Why `deriving (Eq, Show)`

- **`Eq`** lets us write `parseClaim "#1 @ 1,3: 4x4" == Claim 1 1 3 4 4` in tests. Without it the test wouldn't compile.
- **`Show`** lets `hspec` pretty-print the actual value when an assertion fails — the diff message reads `expected Claim {claimId = 1, ...} but got Claim {claimId = 2, ...}` instead of an opaque `<Claim>` token.

Both are mechanically derived — the compiler walks the field list and writes the obvious `==` and `show` for us.

### `NFData` — letting `deepseq`/criterion fully evaluate a `Claim`

```haskell
import Control.DeepSeq (NFData (..))

instance NFData Claim where
  rnf c = c `seq` ()
```

`NFData` lives in the `deepseq` package; the solution itself never touches it. The reason it shows up in `Day03.hs` is that the benchmark suite ([bench/Main.hs](../../bench/Main.hs)) uses criterion's `nf` to force results to *normal form* (every nested thunk evaluated). `nf` calls `rnf x`, gets `()` back, and uses that as proof that `x` is fully evaluated. The instance teaches `Claim` how to participate.

Days 0–2 didn't need this because their puzzle types (`[Int]`, `[String]`) already have an `NFData` instance shipped with `deepseq` itself. Day 3 is the first day with a custom `data` type, so it's the first day that has to declare its own. Putting the instance alongside the type (rather than in `bench/Main.hs`) avoids an *orphan instance* — an instance defined in neither the class's module nor the type's module, which is allowed but discouraged because it can cause linker-order surprises across packages.

`seq :: a -> b -> b` is a built-in primitive: evaluate the first argument to weak-head normal form, then return the second. So `c \`seq\` ()` says *"force `c` to WHNF, then return `()`."* For `Claim` that means evaluating the constructor — *and because every field is strict, evaluating the constructor evaluates every field*. The instance is therefore a one-liner.

A field-by-field instance would look like:

```haskell
instance NFData Claim where
  rnf (Claim a b c d e) = rnf a `seq` rnf b `seq` rnf c `seq` rnf d `seq` rnf e
```

That is what you would write for a record with **non-strict** fields: walk every field, force it to NF, glue the calls with `seq`. For our all-strict-`Int` record the one-liner is equivalent and faster to read.

**Why criterion needs this at all**: lazy languages tempt you into "I returned an `Int`" benchmarks that actually return a thunk that *would compute* an `Int`. The microbench then measures thunk-allocation time, not arithmetic time. `nf` insists on a real, fully-evaluated value before stopping the clock. `NFData` is the type-class plumbing that makes `nf` polymorphic.

---

## `parseInput` and `parseClaim`

```haskell
parseInput :: String -> Puzzle
parseInput = map parseClaim . lines

parseClaim :: String -> Claim
parseClaim line = case map read (words (map normalize line)) of
  [cid, x, y, w, h] -> Claim cid x y w h
  _                 -> error ("malformed claim: " ++ line)
  where
    normalize :: Char -> Char
    normalize c
      | c `elem` ("#@,:x" :: String) = ' '
      | otherwise                    = c
```

### The "replace-then-tokenise" trick

`parseClaim` works on `#1 @ 258,327: 19x22`. The shape is *five integers, separated by punctuation*. The temptation is to write a `splitOn`-based parser, or `break` the string repeatedly on each separator:

```haskell
-- the painful way
let cid              = read (drop 1 hashId)
    (xs, ys)         = break (== ',') coords
    x                = read xs
    y                = read (init (drop 1 ys))
    (ws, hs)         = break (== 'x') dims
    w                = read ws
    h                = read (drop 1 hs)
in Claim cid x y w h
```

That works. It is also tedious and easy to get wrong (the `init . drop 1` to skip the leading `,` and trailing `:` is a per-field land mine).

The cleaner version *eliminates the separators altogether* before tokenising:

1. Map each character through `normalize`, which turns every separator (`#`, `@`, `,`, `:`, `x`) into a space and leaves everything else untouched. `#1 @ 258,327: 19x22` becomes `" 1   258 327  19 22"` (multiple spaces — that's fine).
2. `words` collapses runs of whitespace into separators and returns `["1","258","327","19","22"]`.
3. `map read` parses each chunk as `Int`, giving `[1, 258, 327, 19, 22]`.
4. Pattern-match the five-element list into a `Claim`.

Five lines down to one expression. The trick generalises to any input whose fields are integers separated by *any* set of single characters — Day 4's date stamps, Day 23's coordinates, plenty of others. Memorise the shape:

```haskell
case map read (words (map normalize line)) of
  [a, b, c, ...] -> ...
  _              -> error ("malformed: " ++ line)
  where
    normalize ch | ch `elem` SEPARATORS = ' '
                 | otherwise            = ch
```

### Token by token: `[cid, x, y, w, h] -> Claim cid x y w h`

| Token | What it is | What it means |
|-------|------------|---------------|
| `[` | list pattern bracket | matches a *list* constructor — but only of a specific length, given how many element patterns appear inside |
| `cid, x, y, w, h` | five comma-separated patterns | match exactly five elements; bind each to its name |
| `]` | closes the list pattern | |
| `->` | case-arm separator | "if the pattern on the left matches, evaluate the expression on the right" |
| `Claim cid x y w h` | constructor application | calls the `Claim` constructor positionally, in declaration order |

The five-element list pattern is *strict in length*: `[a, b]` matches `[1, 2]` but not `[1, 2, 3]`. So the wildcard `_ -> error ...` catches malformed lines (wrong field count) and gives a useful diagnostic instead of a silent miscount.

### Why `error` instead of `Maybe`

For AoC, malformed input is *operator error* — you ran the wrong file. A noisy crash with the offending line is more useful than a silent `Nothing` that cascades into a wrong answer. Production code parsing untrusted input would use `readMaybe` and `Either String Claim`; AoC code uses `read` + `error`.

### `normalize` as a `where` clause

```haskell
parseClaim line = case ... of
  ...
  where
    normalize :: Char -> Char
    normalize c
      | c `elem` ("#@,:x" :: String) = ' '
      | otherwise                    = c
```

Two beginner-relevant things in this snippet:

1. **`where` introduces local bindings** scoped to the surrounding equation. `normalize` is visible inside `parseClaim` and nowhere else — it stays out of the module's top-level namespace. Compare to `let ... in ...` which is an *expression*; `where` clauses are *definitions* that hang off an equation.
2. **Guards (`|`)** chain `Bool` conditions. Each guard is a `Bool` expression; the first one that evaluates to `True` selects the corresponding right-hand side. `otherwise` is just `True` re-named for readability — it is a regular Prelude binding, not a keyword.

The annotation `("#@,:x" :: String)` on the literal is a *type ascription*. Without it the compiler can't decide whether `"#@,:x"` is a `String` or some other `IsString` type (the project doesn't enable `OverloadedStrings`, so this is moot here — but the annotation makes the intent obvious and silences a future warning when string-overloading is enabled). It is a no-op at runtime.

### `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput = map parseClaim . lines
```

Point-free composition. Reading right-to-left:

1. `lines` splits the raw input into a `[String]`, one per claim.
2. `map parseClaim` turns each `String` into a `Claim`.
3. The whole pipeline has type `String -> [Claim]`, matching the signature.

The same shape as Day 0–2, just with a more interesting per-element parser.

---

## `squares` — the 2-D walk

```haskell
squares :: Claim -> [(Int, Int)]
squares c =
  [ (x, y)
  | x <- [left c .. left c + width c - 1]
  , y <- [top  c .. top  c + height c - 1]
  ]
```

Generates every `(x, y)` square covered by a claim. For `#1 @ 1,3: 4x4` it produces

```
[(1,3),(1,4),(1,5),(1,6),(2,3),(2,4),(2,5),(2,6),(3,3),...,(4,6)]
```

— 16 pairs, all the cells of the 4×4 rectangle.

### Two generators = nested loops (revisited)

Day 2 introduced nested generators for *unordered pairs*. Day 3 uses the same shape to *enumerate a rectangle*: outer loop over `x`, inner loop over `y`, yield `(x, y)`. The right-most generator varies fastest, so the output is column-major (`(x, top), (x, top+1), ..., (x, top+h-1), (x+1, top), ...`).

The order doesn't matter for `Map.fromListWith (+)` (it builds the same map regardless), so we don't need to think about it. What matters is the *shape*: list comprehensions that walk `[outer]` × `[inner]` are how Haskell writes a double `for`.

### Inclusive/exclusive bookkeeping

`[a .. b]` in Haskell is **inclusive on both ends**. So `[left c .. left c + width c - 1]` is *width* values (`-1` because `..` includes `b`). Equivalently:

```haskell
[left c .. left c + width c - 1]   -- inclusive endpoints
```

is the exact 0..n-1 idiom Rust spells `(left ..(left + width))` (half-open). The off-by-one trap is the same as ever; pick one convention and stick with it. This file uses inclusive ranges, so every upper bound has a `-1`.

### Performance footnote

`squares` is pure list-cons allocation: ~130k cons cells for the actual input (1311 claims averaging ~100 squares each). That is the dominant allocation cost in `countMap`. Switching to `Data.Vector.Unboxed` would eliminate the cons overhead but require restructuring the fold; for 350 ms the win isn't worth the complexity yet. See [the `IntMap` sidebar](#possible-optimization--intmap-keyed-by-x--1001--y) for a cheaper change.

---

## `countMap` — the fabric as a frequency `Map`

```haskell
countMap :: Puzzle -> Map.Map (Int, Int) Int
countMap claims =
  Map.fromListWith (+) [ (sq, 1) | c <- claims, sq <- squares c ]
```

The whole computation in two lines.

### `Map.fromListWith` — the "frequency count" idiom in one line

Day 2 introduced the long form:

```haskell
charCounts = foldl' (\m c -> Map.insertWith (+) c 1 m) Map.empty
```

`Map.fromListWith` packages exactly that fold:

```haskell
Map.fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
```

Read it as: *"build a `Map` from this list of `(key, value)` pairs; if the same key appears more than once, combine the values with `f`."* With `(+)` and the constant value `1`, that is the canonical "count occurrences" idiom — one line instead of three.

The two forms are functionally identical:

```haskell
Map.fromListWith (+) [ (sq, 1) | c <- claims, sq <- squares c ]
-- ≡
foldl' (\m (k, v) -> Map.insertWith (+) k v m) Map.empty
       [ (sq, 1) | c <- claims, sq <- squares c ]
```

Pick `fromListWith` when you naturally have (or can write) a `[(k, v)]`; pick `insertWith` inside an existing fold when the per-step logic is more complex than a single `(+)`.

### The combiner and `Data.Map.Strict`

The `Strict` qualifier matters here for the same reason as Day 2: the lazy `Data.Map` would defer every `+1` until *something* read the value, building thunks like `1 + 1 + 1 + 1 + ...` inside the map. For ~130k inserts the thunk tower alone would be a noticeable allocation drag, even before the eventual `Map.size . Map.filter (>= 2)` walk forces them all. **Always reach for `Data.Map.Strict` when the values are numeric counters.**

### Inside the comprehension

```haskell
[ (sq, 1) | c <- claims, sq <- squares c ]
```

| Symbol | Read as | What happens |
|--------|---------|--------------|
| `(sq, 1)` | yield expression | the `(key, value)` pair we want in the input list |
| `\|` | "such that" | separates yield from clauses |
| `c <- claims` | outer generator | for each claim in the puzzle |
| `,` | "and" | clause separator |
| `sq <- squares c` | inner generator | for each square that claim covers |

Two generators, but no filter. The output is a flat `[((Int, Int), Int)]` containing one `(square, 1)` pair per `(claim, square)` combination. For the actual input that is ~130k pairs, all with value `1`. `fromListWith (+)` then merges duplicate keys — the squares covered by multiple claims get incremented past `1`.

Reads in plain English: *"for every claim, for every square it covers, emit `(square, 1)`."*

### Why a `Map (Int, Int)`, not a 2-D array

A `Data.Array` or unboxed `Vector` indexed by `(x, y)` would be faster — random access is O(1) instead of O(log n). Two reasons we don't reach for one yet:

1. **No new concept needed.** We already know `Data.Map.Strict` from Day 2; tuples-as-keys is a small extension. A `Data.Array` would introduce array indexing, bounds-checking, and the `Ix` class — three new things at once.
2. **The cost is real but tolerable.** ~350 ms total. A 2-D array drops it to ~50 ms. For a learning project, the `Map`-based version teaches more and runs comfortably under a second. The optimisation is sketched in [the `IntMap` sidebar](#possible-optimization--intmap-keyed-by-x--1001--y) for completeness.

---

## `part1` — count overlapping squares

```haskell
part1 :: Puzzle -> Int
part1 = Map.size . Map.filter (>= 2) . countMap
```

Three composed functions. Reading right-to-left:

1. `countMap` builds the frequency map from claims.
2. `Map.filter (>= 2)` keeps only the entries whose value is `2` or more — exactly the squares covered by 2+ claims.
3. `Map.size` counts the surviving entries.

`Map.filter :: (a -> Bool) -> Map k a -> Map k a` is the `Data.Map.Strict` analogue of list `filter`, but it filters by *value*. `Map.filterWithKey` would also see the key. We only need the value here.

### `(>= 2)` — operator section

`(>= 2)` is an *operator section*: a partially applied infix operator. It expands to `\x -> x >= 2`. Day 1 introduced this with `(== '+')`; the same trick works for `(>= 2)`, `(* 3)`, `(++ "!")`, `((:) 0)`, etc.

Two flavours, both useful:

```haskell
(>= 2)    -- left section: \x -> x >= 2
(2 >=)    -- right section: \x -> 2 >= x   (note the flip!)
```

The number of arguments on the *outside* of the parens equals the number not yet supplied. For `(>= 2)` we supplied the right argument, so the leftover is the left argument. The exception is `(- 2)`, which Haskell parses as the literal negative number `-2` rather than a section; for that case write `subtract 2` instead.

### Point-free composition again

```haskell
part1 = Map.size . Map.filter (>= 2) . countMap
```

Three functions glued with `.`. Equivalent to:

```haskell
part1 puzzle = Map.size (Map.filter (>= 2) (countMap puzzle))
```

The point-free version is shorter and reads as a *pipeline*, which matches how the algorithm actually works — "first build the map, then filter to the heavy-weights, then count."

---

## `part2` — find the lone claim

```haskell
import Data.List (find)

part2 :: Puzzle -> Int
part2 claims =
  let counts = countMap claims
      isAlone c = all (\sq -> Map.findWithDefault 0 sq counts == 1) (squares c)
  in case find isAlone claims of
       Just c  -> claimId c
       Nothing -> error "Day 03 Part 2: no non-overlapping claim found"
```

Find the unique claim whose every square has count `1` in the global map.

### The structural insight

A claim does not overlap any other iff every square it covers is hit by *no other claim*. In `countMap`, every square is hit by *at least* the owning claim (count ≥ 1). So a claim is non-overlapping iff every square it owns has count *exactly* 1 — its own contribution and nothing else.

This is much cheaper than the naive "for each pair of claims, check rectangle intersection" pair-search (O(n²) pair-tests). We re-use the already-built `countMap` and walk one claim at a time, ~100 squares per claim, ~1300 claims = ~130k lookups. The lookups are O(log n) on `Map`, so total cost is roughly the same as `countMap` itself.

### `let counts = ... in ...` — a shared binding

Both Part 2 and Part 1 compute `countMap claims`. Inside `part2` we bind it once and re-use it for every `isAlone` call — without that binding, Haskell's referential transparency would *let* us write `countMap claims` inside `isAlone` and the compiler would technically be allowed to share the work, but in practice it would not, and we would rebuild the 130k-entry map for every claim.

**Rule of thumb**: when a value is used more than once and is non-trivial to compute, give it a name with `let`. Sharing is *guaranteed* once a value has a name; without a name, sharing depends on the optimiser's mood.

(The two parts *across* `part1` and `part2` still build `countMap` separately — that's why both bench rows are ~170 ms. Sharing across the two parts requires restructuring the API; see the [share-`countMap`](#possible-optimization--share-countmap-between-parts) sidebar.)

### `all (\sq -> ... == 1) (squares c)`

`all :: (a -> Bool) -> [a] -> Bool` returns `True` if the predicate holds for every element. Short-circuits on the first `False` — important here, because once we find a square with count > 1 we know the claim overlaps and we can stop.

Read literally: *"every square of the claim has a `countMap` value of 1."*

### `Map.findWithDefault 0 sq counts`

```haskell
Map.findWithDefault :: a -> k -> Map k a -> a
```

*"Look up `sq` in `counts`; if it's missing, return `0`."* Cleaner than the longer

```haskell
fromMaybe 0 (Map.lookup sq counts)
```

though the two are equivalent. For our use case the key *is* always present (every square that some claim covers is in the map by construction), so `Map.findWithDefault 0` and `counts Map.! sq` would behave the same. The `0` default is a defensive belt-and-braces in case future refactoring breaks the invariant — costless.

### `Data.List.find`

```haskell
find :: (a -> Bool) -> [a] -> Maybe a
```

Returns the first element satisfying the predicate, wrapped in `Just`, or `Nothing` if none. Lazy — like every list-consumer, it stops at the first match.

So `find isAlone claims` walks `claims` until it finds the lone non-overlapping one. For the actual input that is claim ID `113`, somewhere in the list. The remaining claims are never tested.

### Pattern-matching `Maybe`

```haskell
case find isAlone claims of
  Just c  -> claimId c
  Nothing -> error "Day 03 Part 2: no non-overlapping claim found"
```

Two constructors, two cases. `Just c` binds the wrapped value to `c`; `Nothing` matches the absence and lets us produce a useful error message. The puzzle promises a unique solution, so the `Nothing` branch is unreachable on valid input — the explicit branch is for the case where our logic is buggy.

`Maybe a` is the Haskell analogue of Rust's `Option<T>`:

| Haskell | Rust | Meaning |
|---------|------|---------|
| `Just x` | `Some(x)` | "have a value" |
| `Nothing` | `None` | "no value" |
| `Maybe a` | `Option<T>` | the type itself |
| `fromJust` | `.unwrap()` | extract or panic — avoid in real code |
| `fromMaybe` | `.unwrap_or(...)` | extract or supply a default |
| `mapMaybe` | `.filter_map(...)` | map and drop the `Nothing`s |

This is the first time we pattern-match a `Maybe` directly in this project (Day 1's `Data.Set` uses were always membership tests, never `lookup`). Day 4 will lean on `Maybe` more heavily once parsing gets richer.

### Could it `find` over `(squares c, isAlone c)` more directly?

A point-free `claimId <$> find isAlone claims` would also work and avoid the `case` entirely:

```haskell
part2 claims =
  let counts = countMap claims
      isAlone c = all (\sq -> Map.findWithDefault 0 sq counts == 1) (squares c)
  in maybe (error "...") claimId (find isAlone claims)
```

Either is fine. The `case` form is louder about the failure case — easier for a reader to follow. We'll see `maybe` and `<$>` arrive in earnest on later days.

---

## `solve`

```haskell
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
```

Same shape as every previous day. Both parts return `Int`, so both go through `show`.

Run it:

```bash
cabal run aoc2018-solve -- 3
```

Output:

```
Day 03 (input: inputs/day03.txt)
  part 1: 111485
  part 2: 113
```

---

## Tests

The full test file is [Day03Spec.hs](../../test/Day03Spec.hs). Coverage:

1. **`parseClaim`** — multi-digit fields (`#123 @ 3,2: 5x4` → `Claim 123 3 2 5 4`) and the first line of the puzzle example.
2. **`parseInput`** — the three-line example splits into three claims.
3. **`squares`** — a 2×2 claim enumerates four pairs; a zero-area claim enumerates none.
4. **`countMap`** — the four overlap squares of the puzzle example all map to `2`.
5. **Part 1 example** — the three-claim puzzle, answer `4`.
6. **Part 2 example** — the three-claim puzzle, non-overlapping claim ID `3`.
7. **Actual input** — `part1 = 111485` and `part2 = 113` against `inputs/day03.txt`.

10 examples total. After Day 3 the project's running total is 94 examples, 0 failures, 44 still-pending stubs for Days 4–25.

The use of named-field syntax in test expectations (`Claim { claimId = 1, ... }`) is deliberate: any future re-ordering of fields would break a positional comparison silently, but the named form would still type-check and produce a meaningful diff if the *meaning* of a field changed. Worth the extra characters for tests.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`, criterion default time-limit.

| Bench               | Mean       | What it times                                                                |
|---------------------|-----------:|------------------------------------------------------------------------------|
| `day03/parseInput`  |   4.05 ms  | `map parseClaim . lines` over the 28 KB raw `String` (1311 lines).           |
| `day03/part1`       |  175.1 ms  | `countMap` over ~130k squares + filter + size.                               |
| `day03/part2`       |  170.8 ms  | `countMap` again + per-claim `all` walk until `find` succeeds.               |
| `day03/combined`    |  352.1 ms  | `\r -> let p = parseInput r in (part1 p, part2 p)` from raw text.            |

**Total = Parse + Part 1 + Part 2 ≈ 350.0 ms.**

Three things worth noting:

1. **Parse is no longer a rounding error.** 4 ms versus 84 µs on Day 2 — `parseClaim`'s `map normalize` over each line, plus five `read` calls per claim, plus the cons-cells for the resulting list of records, adds up. Switching to `Data.ByteString.Char8` and a hand-rolled `Int` parser would drop this by 5–10×; for now 4 ms inside a 350 ms total isn't worth the complexity tax.
2. **Part 1 and Part 2 cost the same.** Both spend ~170 ms inside `countMap`, which dominates everything else. The actual *post-`countMap`* work is microseconds (one `Map.filter` for Part 1; ~100k `findWithDefault` calls for Part 2, both finishing well under 5 ms). If we could share `countMap` between the two parts the total would drop to ~180 ms (Parse + one `countMap` + tiny tails). See the [share sidebar](#possible-optimization--share-countmap-between-parts) below.
3. **`combined` lines up with the sum of the parts.** ~352 ms vs 350 ms — close enough that the GC-noise overhead Day 0 / Day 2 saw is dwarfed by `countMap`'s allocation cost. When the inner work is heavy, the per-iteration parse overhead disappears into the noise.

**Reproducing**:

```bash
cabal bench --benchmark-options="--match prefix day03"
cabal bench --benchmark-options="--match prefix day03 --time-limit 8"   # steadier
```

---

## Possible optimization — share `countMap` between parts

The two-part split forced by `aoc2018-solve`'s contract (one solver per part) means `part1` and `part2` each rebuild the 130k-entry frequency map. That is roughly half the total runtime spent twice.

**Sketch**:

```haskell
solveBoth :: Puzzle -> (Int, Int)
solveBoth claims =
  let counts = countMap claims
      p1     = Map.size (Map.filter (>= 2) counts)
      isAlone c = all (\sq -> Map.findWithDefault 0 sq counts == 1) (squares c)
      p2     = case find isAlone claims of
                 Just c  -> claimId c
                 Nothing -> error "no lone claim"
  in (p1, p2)
```

`solve` would then call `solveBoth` once and print both answers from the resulting tuple. Estimated total runtime: **~180 ms** instead of 350 ms — almost 2× faster.

**Why it isn't in the main code.** The `dayBench` helper benches `parseInput`, `part1`, `part2` independently (so we can see *which part* is expensive), and the `cabal run aoc2018-solve -- 3` dispatcher prints them separately. Both contracts assume `part1 :: Puzzle -> Int` and `part2 :: Puzzle -> Int` are independent. Sharing `countMap` would either:

- Add a third public function `solveBoth` that the dispatcher calls and the bench ignores, or
- Memoize `countMap` via some module-level cache, which is a different teaching topic (`Data.IORef` or `unsafePerformIO`).

For Day 3, the readability cost of either change isn't worth the 170 ms saving. The note exists so that future-Matt re-reading this file knows where the easy 50% live.

---

## Possible optimization — `IntMap` keyed by `x * 1001 + y`

The fabric is at most ~1000×1000 inches. Every `(x, y)` pair fits in a single `Int` via `x * 1001 + y`, so a `Data.IntMap.Strict Int Int` would replace the boxed `(Int, Int)` keys with raw `Int`s. `IntMap` uses a Patricia trie internally — typically 2–4× faster than `Map (Int, Int)` for this kind of dense numeric key, with no functional change to the rest of the code.

**Sketch**:

```haskell
import qualified Data.IntMap.Strict as IM

key :: Int -> Int -> Int
key x y = x * 1001 + y

countMapIM :: Puzzle -> IM.IntMap Int
countMapIM claims =
  IM.fromListWith (+)
    [ (key x y, 1) | c <- claims
                   , x <- [left c .. left c + width c - 1]
                   , y <- [top  c .. top  c + height c - 1]
                   ]

part1IM :: Puzzle -> Int
part1IM = IM.size . IM.filter (>= 2) . countMapIM
```

Estimated total runtime: **~80–120 ms** — roughly 3× faster than the `Map (Int, Int)` version, no algorithmic change.

**Why it isn't in the main code.** Day 3's headline lesson is *records + the frequency-map idiom over a tuple key*. Switching to `IntMap` and a packed integer key would need a paragraph explaining Patricia tries and key-encoding choices, which doesn't pay off for a 250 ms saving on a single day. We will reach for `IntMap` for real on Day 9 (the marble game) and Day 12 (plant pots), where the keys are *already* `Int`s and no encoding step is needed.

A `Data.Array.Unboxed Int` covering the whole 1001×1001 grid would be even faster (~10 ms), at the cost of allocating 4 MB up front for a sparse-ish grid. Right answer for an industrial pipeline; overkill for AoC.

---

## Key patterns

Three takeaways that generalise.

1. **`Map.fromListWith (+)` is the one-line frequency idiom.** Any time the algorithm is "build a list of `(key, 1)` pairs and count them," this is the call. Drop the explicit fold from your fingers; reach for `fromListWith` first.
2. **Records with strict fields are cheap and clarifying.** Five-field tuples are pain; five-field strict records are the same memory layout (because of `!`) plus named accessors and pattern syntax. Use `data ... = ... { ... } deriving (Eq, Show)` from Day 3 onward; reach for tuples only when there are 2 fields *and* both have obvious meaning at the call site.
3. **A frequency map serves both "count the heavies" and "find the lone".** Build it once, ask different questions of it for Part 1 and Part 2. Many AoC days fit this shape — the parse-once-share-the-structure pattern is at least as important as any specific data structure.

---

## Side-by-side with the Rust mental model

There is no committed Rust baseline for AoC 2018; the Rust mental model is sketched below.

```rust
use std::collections::{BTreeMap, HashMap};

#[derive(Debug)]
struct Claim { id: u32, left: u32, top: u32, width: u32, height: u32 }

fn parse_claim(line: &str) -> Claim {
    let parts: Vec<u32> = line
        .replace(['#', '@', ',', ':', 'x'], " ")
        .split_whitespace()
        .map(|t| t.parse().unwrap())
        .collect();
    Claim { id: parts[0], left: parts[1], top: parts[2], width: parts[3], height: parts[4] }
}

fn count_map(claims: &[Claim]) -> HashMap<(u32, u32), u32> {
    let mut m = HashMap::new();
    for c in claims {
        for x in c.left .. c.left + c.width {
            for y in c.top .. c.top + c.height {
                *m.entry((x, y)).or_insert(0) += 1;
            }
        }
    }
    m
}

fn part1(claims: &[Claim]) -> usize {
    count_map(claims).values().filter(|&&v| v >= 2).count()
}

fn part2(claims: &[Claim]) -> u32 {
    let counts = count_map(claims);
    claims.iter().find(|c| {
        (c.left .. c.left + c.width).all(|x|
            (c.top .. c.top + c.height).all(|y| counts[&(x, y)] == 1)
        )
    }).unwrap().id
}
```

Lined up with the Haskell version:

| Concept                            | Rust                                                          | Haskell                                                          |
|------------------------------------|---------------------------------------------------------------|------------------------------------------------------------------|
| Record / struct                    | `struct Claim { id: u32, left: u32, ... }`                    | `data Claim = Claim { claimId :: !Int, left :: !Int, ... }`      |
| Strict field                       | (Rust fields are always strict)                               | `!Int` (bang annotation)                                         |
| Replace separators with space      | `line.replace(['#', '@', ',', ':', 'x'], " ")`                | `map normalize line` (custom one-line `normalize`)               |
| Tokenise + parse                   | `.split_whitespace().map(|t| t.parse().unwrap()).collect()`   | `map read . words`                                               |
| Frequency map                      | `*m.entry(k).or_insert(0) += 1`                               | `Map.insertWith (+) k 1 m`  /  `Map.fromListWith (+) [(k,1)..]`  |
| Tuple key                          | `HashMap<(u32, u32), u32>`                                    | `Map (Int, Int) Int`                                             |
| 2-D iteration                      | `for x in left..left+w { for y in top..top+h { ... } }`       | `[(x, y) \| x <- [..] , y <- [..]]`                              |
| Filter values, count               | `m.values().filter(|&&v| v >= 2).count()`                     | `Map.size . Map.filter (>= 2)`                                   |
| Find element matching predicate    | `iter.find(|c| ...).unwrap().id`                              | `case find isAlone claims of { Just c -> claimId c; ... }`       |
| Lookup with default                | `*m.get(&k).unwrap_or(&0)`                                    | `Map.findWithDefault 0 k m`                                      |

Two real differences in flavour, beyond the syntactic line-up:

- **Haskell uses an immutable `Map` threaded through a build; Rust uses a mutable `HashMap`.** Performance diverges here: Rust's `HashMap` is O(1) per insert and contiguous; Haskell's `Map (Int, Int)` is O(log n) per insert and tree-allocated. The 3× perf gap on `countMap` is mostly this. Switching Haskell to `Data.HashMap.Strict` from `unordered-containers` would close most of it; switching to `Data.IntMap.Strict` with a packed key (the [sidebar](#possible-optimization--intmap-keyed-by-x--1001--y) above) would close it further while staying in the standard `containers` package.
- **Haskell's enumeration of the rectangle is a list comprehension; Rust's is a nested `for`.** Both compile to the same loop shape. The Haskell version is *eager in producing the list*: it really does allocate ~130k cons cells before `fromListWith` consumes them. Rust's nested `for` writes directly into the `HashMap` without an intermediate vector. A `foldl'` over the comprehension would let the compiler see the same fusion opportunity, but at our scale the cons-cell allocation is a small fraction of the cost — the `Map`-update cost dominates either way.

For this puzzle Rust would be ~5–10× faster end-to-end, dominated by `HashMap` vs `Map`. We accept the gap; for 350 ms it doesn't matter at this stage.

---

**Navigation**: [Problem statement](day03.md) | [Summary table](summary_2018.md) | [← Day 2](day02_function_guide.md) | Day 4 → *(not yet attempted)*
