# Day 02: Inventory Management System — Function Guide

**Problem**: 250 box IDs, each 26 lowercase letters. Part 1 is a frequency-based checksum; Part 2 finds the unique pair of IDs differing in exactly one position and returns their common letters.
**Answers**: Part 1 = **5880**, Part 2 = **`tiwcdpbseqhxryfmgkvjujvza`**
**Runtime** (mean, criterion `-O2`): Parse = **84.7 µs** | Part 1 = **439.9 µs** | Part 2 = **1.02 ms** | **Total ≈ 1.54 ms**
**Code**: [Day02.hs](../../src/Day02.hs)
**Tests**: [Day02Spec.hs](../../test/Day02Spec.hs)
**Bench**: [bench/Main.hs](../../bench/Main.hs) — `cabal bench --benchmark-options="--match prefix day02"`
**Problem statement**: [day02.md](day02.md)

**New concepts this day** (beyond Days 0–1):

- **`Data.Map.Strict` (qualified)** — first appearance in this project. The canonical "frequency count" via `Map.insertWith (+)`. Compare to Rust's `BTreeMap`.
- **List comprehensions with multiple generators** — `[ … | a <- xs, b <- ys, … ]` is the natural way to enumerate pairs. The two generators are nested loops; the right-most varies fastest.
- **Pattern in a generator** — `(a : rest) <- tails ids` does double duty: it iterates suffixes *and* binds the head while skipping the empty suffix.
- **`tails` from `Data.List`** — every suffix of a list, longest first. Combined with the head-pattern above, it visits each unordered pair exactly once.
- **A polymorphic answer type.** Part 1 returns `Int` (a checksum) but Part 2 returns `String` (the common letters), so the bench helper had to grow polymorphic result-type variables. First time a day's answer is not a number.

---

## Table of contents
1. [Problem summary](#problem-summary)
2. [Data model](#data-model)
3. [`parseInput`](#parseinput)
4. [`charCounts` and `Data.Map.Strict`](#charcounts-and-datamapstrict)
5. [`part1` — the checksum](#part1--the-checksum)
6. [`differByOne` and `commonLetters`](#differbyone-and-commonletters)
7. [`part2` — the pair search](#part2--the-pair-search)
8. [`solve`](#solve)
9. [Tests](#tests)
10. [Benchmarks](#benchmarks)
11. [Possible optimization — bucketing instead of pair search](#possible-optimization--bucketing-instead-of-pair-search)
12. [Key patterns](#key-patterns)
13. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The input is 250 lines, each a 26-letter lowercase box ID:

```
oiwcdpbseqgxryfmlpktnupvza
oiwddpbsuqhxryfmlgkznujvza
ziwcdpbsechxrvfmlgktnujvza
…
```

- **Part 1** is a "rudimentary checksum." Count how many IDs contain *some* letter that appears exactly twice (`twos`) and how many contain *some* letter that appears exactly three times (`threes`). One ID can contribute to both buckets but never to either bucket twice (e.g. `bababc` has two `a`'s and three `b`'s — contributes `+1` to `twos` and `+1` to `threes`, not `+2`). The checksum is `twos * threes`.
- **Part 2** is "find the prototype." Among all unordered pairs of IDs, exactly one pair differs in *exactly one position* (Hamming distance 1). Return the letters they share — equivalently, the ID with the differing position deleted. The puzzle promises the answer is unique.

Worked Part 1 example: the seven IDs `abcdef, bababc, abbcde, abcccd, aabcdd, abcdee, ababab` give `twos = 4`, `threes = 3`, checksum `12`.

Worked Part 2 example: `abcde, fghij, klmno, pqrst, fguij, axcye, wvxyz` — the unique near-pair is `fghij` / `fguij`, sharing `fgij`.

For our actual input, the winning pair is at lines 53 and 216 (0-indexed lines 52 and 215). They differ at position 17 (`e` vs `l`). Common letters: `tiwcdpbseqhxryfmgkvjujvza` — 25 characters, the original ID minus one position.

---

## Data model

```haskell
type Puzzle = [String]
```

The input is literally a list of strings. No richer structure pays off — both parts work on the raw `String`s, character-by-character. Reaching for a `Vector Char` per ID would be ceremony for 26-element strings.

A `String` in Haskell is `[Char]`, a linked list of boxed characters. That is genuinely slow for big inputs (later puzzles will switch to `Data.ByteString.Char8` or `Data.Text`), but for 250 × 26 = 6,500 characters total it costs us ~1.5 ms end-to-end and the code stays clear.

**Rust analogue**: `type Puzzle = Vec<String>`. Same shape, except Rust's `String` is a contiguous UTF-8 buffer rather than a linked list of `Char` boxes.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput = lines
```

Three letters of code: `lines` already does everything. It splits the raw input on `'\n'` and silently drops the empty trailing element produced by a trailing newline. There is nothing per-character to clean up — the input is exactly the IDs themselves.

This is the simplest parser we will see all year. Day 2's interest lies entirely downstream of parsing.

**Rust analogue**: `input.lines().map(String::from).collect::<Vec<_>>()`. Rust needs `String::from` because `&str` ≠ `String`; Haskell's `String` *is* the slice (`[Char]`).

---

## `charCounts` and `Data.Map.Strict`

```haskell
import qualified Data.Map.Strict as Map

charCounts :: String -> Map.Map Char Int
charCounts = foldl' (\m c -> Map.insertWith (+) c 1 m) Map.empty
```

`charCounts` produces a `Map Char Int` whose keys are the letters that appear in the box ID and whose values are how many times each letter appears.

This is the canonical **frequency count** idiom in Haskell, and it is the single most reused pattern across AoC. Memorize the shape.

### Token by token

Two lines, two passes — the type signature first, then the body.

**Line 1**: `charCounts :: String -> Map.Map Char Int`

| Token | What it is | What it means |
|-------|------------|---------------|
| `charCounts` | identifier being typed | name on the left of `::` is the thing we're declaring a type for |
| `::` | **"has type"** | type-signature separator |
| `String` | type | built-in alias for `[Char]` — a linked list of `Char` |
| `->` | function arrow | type-level. `A -> B` is "function from A to B" |
| `Map.Map` | qualified type constructor | `Map` (left of `.`) is the **module alias** from `import qualified Data.Map.Strict as Map`. `Map` (right of `.`) is the **type constructor** defined in that module. The duplication is unfortunate but unavoidable — the module and the type happen to share a name |
| `Char` | type | first type argument to `Map.Map` — the **key** type |
| `Int` | type | second type argument to `Map.Map` — the **value** type |

`Map.Map` has kind `* -> * -> *` (it takes two type arguments). `Map.Map Char Int` is the fully-applied type — concretely, a balanced binary tree keyed by `Char` with `Int` values. So the whole line reads: *"`charCounts` is a function from `String` to `Map Char Int`."*

**Line 2**: `charCounts = foldl' (\m c -> Map.insertWith (+) c 1 m) Map.empty`

This is **point-free**: the `String` parameter from the type signature isn't named on the left of `=`. We'll see why in a moment.

| Token | What it is | What it means |
|-------|------------|---------------|
| `charCounts` | identifier | must match the name in the type signature |
| `=` | definition | binds the right-hand side to the name |
| `foldl'` | function | strict left fold from `Data.List`. Type: `(b -> a -> b) -> b -> [a] -> b` — *"given a step, a seed, and a list, walk the list left-to-right with a strict accumulator"* |
| `(` | opens a parenthesised expression | groups the lambda into a single argument |
| `\` | starts a **lambda** | read as "λ". The next tokens before `->` are parameters |
| `m` | lambda parameter | will be the accumulator (the growing `Map`) |
| `c` | lambda parameter | will be the next `Char` from the string |
| `->` | lambda body separator | **different `->` from the type signature!** This one is term-level, separating lambda params from body |
| `Map.insertWith` | qualified function | from `Data.Map.Strict`. Type: `Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a` |
| `(+)` | operator-as-function | parens around an infix operator turn it into a regular two-arg function. `(+) === \x y -> x + y` |
| `c` | argument to `insertWith` | the **key** — the character we're inserting |
| `1` | argument to `insertWith` | the **new value** — the count to insert (or combine with the existing one) |
| `m` | argument to `insertWith` | the **existing map** — the accumulator |
| `)` | closes the lambda | |
| `Map.empty` | qualified value | the empty `Map`. From `Data.Map.Strict`. The **seed** for the fold |

### How the pieces compose

Lay out `foldl'` with named slots:

```
foldl' :: (b -> a -> b) ->   b   -> [a] -> b
            step             seed   list
```

We've supplied:

- step = `\m c -> Map.insertWith (+) c 1 m`   (a `Map Char Int -> Char -> Map Char Int`)
- seed = `Map.empty`                           (a `Map Char Int`)
- list = **not supplied**

Two arguments out of three, so `foldl' step seed` has the leftover type `[Char] -> Map Char Int`, which is exactly `String -> Map Char Int` — the type signature on line 1. That's why the body doesn't need to name the input string: partial application already produces a function of the right shape. **Point-free works because Haskell is curried.**

### Trace on `"bab"`

```
seed:      m = {}                         (Map.empty)
c = 'b':   m = {b: 1}                     (insertWith (+) 'b' 1 {})
c = 'a':   m = {a: 1, b: 1}               (insertWith (+) 'a' 1 {b:1})
c = 'b':   m = {a: 1, b: 2}               (insertWith (+) 'b' 1 {a:1,b:1}; combines to 1 + 1)
result:    {a: 1, b: 2}
```

The fold's strictness (`'` in `foldl'`) is what makes the value `2` a real evaluated `Int` rather than a thunk `(+) 1 1`. Without the `'`, you'd build a tower of unevaluated `(+) 1 (+) 1 (+) 1 …` thunks for hot characters — the classic lazy-counter space leak that motivates `Data.Map.Strict` over the lazy `Data.Map` in the first place.

### `Data.Map.Strict` and qualified imports

Day 1 introduced `Data.Set` qualified. `Data.Map.Strict` follows the same rule:

```haskell
import qualified Data.Map.Strict as Map
```

Why qualified? `Data.Map.Strict` exports `null`, `filter`, `map`, `insert`, `lookup`, `delete` — names that overlap heavily with `Prelude` and with each other (e.g. `Map.map` vs `Set.map` vs `Prelude.map`). Without the alias, every call would be ambiguous. The convention in this project is unconditional: every `containers` module is always `import qualified Foo.Bar as F`.

**Why `Data.Map.Strict` and not `Data.Map`**: the lazy `Data.Map` keeps *values* unevaluated until they are demanded. For a counter map that is a slow-motion space leak — every `+1` builds another thunk on top of the value, and the tower is not collapsed until somebody actually reads the value. `Data.Map.Strict` forces values on insert, so the count is always a real `Int`, not a tower of `0 + 1 + 1 + 1 + …`. Use the strict variant by default; reach for the lazy one only when you specifically want lazy values (rare).

The keys are stored in a balanced binary tree either way; both variants are O(log n) lookup and insert.

### `Map.insertWith (+) c 1 m` — the increment idiom

`Map.insertWith` has type:

```haskell
Map.insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
```

Read it as: *"if `k` is missing, insert the supplied default; if `k` is present, combine the supplied value with the existing one using `f`."*

So `Map.insertWith (+) c 1 m`:

- If `c` is not in `m`: inserts `(c, 1)`.
- If `c` is in `m` with value `v`: replaces it with `(c, 1 + v)`. (The combiner is called as `f new old`, so the new value goes on the *left* of `(+)`. For commutative combiners like `(+)` the order doesn't matter; for non-commutative ones — `(:)`, `(++)` — the order matters and is worth a re-read of the docs the first time.)

The whole `charCounts` body is then:

```haskell
foldl' (\m c -> Map.insertWith (+) c 1 m) Map.empty
```

A strict left fold over the string, threading the growing map. `Map.empty :: Map k v` is the empty map; the lambda updates it for each character; the final accumulator is returned.

Compare to **Rust's idiomatic counter**:

```rust
let mut counts = std::collections::BTreeMap::new();
for c in id.chars() {
    *counts.entry(c).or_insert(0) += 1;
}
```

The mental model is the same — "add one to the bucket for `c`" — but Rust mutates a single `BTreeMap`, while Haskell threads a fresh-but-structurally-shared `Map` through the fold. Both are O(n log k) with k = number of distinct keys; the Haskell version allocates more cons cells on the heap, but the per-operation work is the same.

### `hasExactly` and `Map.elems`

```haskell
hasExactly :: Int -> String -> Bool
hasExactly n boxId = n `elem` Map.elems (charCounts boxId)
```

`Map.elems :: Map k v -> [v]` returns just the values (in key order, but we don't care about order here). For `bababc` it returns `[2, 3, 1]` — the counts of `a`, `b`, `c`.

`n `elem` xs` is `xs.contains(&n)` — does the list contain `n`? `elem :: Eq a => a -> [a] -> Bool` is a Prelude built-in, often written infix with backticks for readability.

So `hasExactly 2 "bababc"` asks: "does the count list `[2, 3, 1]` contain a `2`?" — yes. `hasExactly 3 "bababc"` asks the same with `3` — yes. `hasExactly 4 "bababc"` — no.

**Rust analogue**: `counts.values().any(|&v| v == n)`. Same semantics; Rust's iterator `.any` has the short-circuit built in, while Haskell's `elem` short-circuits because `(||)` short-circuits and `elem` is defined recursively over the list with `(||)`.

---

## `part1` — the checksum

```haskell
count :: (a -> Bool) -> [a] -> Int
count p = length . filter p

part1 :: Puzzle -> Int
part1 ids = count (hasExactly 2) ids * count (hasExactly 3) ids
```

Two passes over the ID list, one looking for IDs with a doubled letter, one for IDs with a tripled letter, then multiply.

The `count` helper is so generic it almost belongs in `AOC.Common`, and per the [aoc-haskell skill guide](../../.claude/skills/aoc-haskell/SKILL.md) the rule is: extract a helper to `AOC.Common` only after writing it for the third day in a row. We have written it once now; it stays inline.

`count (hasExactly 2)` is a partial application: `count` takes a predicate and a list; we supply the predicate. The result is `[String] -> Int`. Compare to:

```haskell
part1 :: Puzzle -> Int
part1 ids = length (filter (hasExactly 2) ids)
          * length (filter (hasExactly 3) ids)
```

The `count` version reads slightly cleaner because `count` is the verb the algorithm describes. Either is fine.

### `count` token by token

`count` packs three Haskell fundamentals into two lines: type variables, function-typed arguments, and `(.)` composition. Worth a slow walk.

**Line 1**: `count :: (a -> Bool) -> [a] -> Int`

| Token | What it is | What it means |
|-------|------------|---------------|
| `count` | identifier being typed | the name on the left of `::` is what we're declaring |
| `::` | **"has type"** | type-signature separator |
| `(` | opens a parenthesised type | groups `a -> Bool` into a single argument type |
| `a` | **type variable** | lowercase = polymorphic. Stands for "any type, picked by the caller". The same `a` in both occurrences must be the same type — universally quantified |
| `->` | function arrow (type-level) | inside the parens: separates the input of the inner function from its output |
| `Bool` | type | `True` or `False` |
| `)` | closes the parenthesised type | |
| `->` | function arrow (type-level) | top-level: separates the *first argument* of `count` from the rest |
| `[a]` | list of `a` | `[]` is the list type constructor; `[a]` means "list whose elements are `a`s" |
| `->` | function arrow (type-level) | separates the second argument from the result |
| `Int` | type | the count we return |

So the type reads: *"`count` takes a predicate (a function from `a` to `Bool`), then a list of `a`s, and returns an `Int`."*

#### Why the parens around `(a -> Bool)` matter

`->` is **right-associative**. Without parens:

```haskell
count :: a -> Bool -> [a] -> Int      -- WRONG TYPE
```

would parse as `a -> (Bool -> ([a] -> Int))` — a function that takes three separate arguments: an `a`, then a `Bool`, then a `[a]`. Totally different shape from "take a function, then a list."

The parens force the inner `->` to be **inside** the first argument:

```haskell
count :: (a -> Bool) -> [a] -> Int    -- CORRECT
```

> **Rule of thumb**: any time an argument is itself a function, parens are mandatory. The compiler will not infer them.

#### Polymorphism in one paragraph

The `a` in `(a -> Bool) -> [a] -> Int` is the same `a` in both places — so if the predicate accepts `Char`, the list must also be `[Char]`. The compiler picks `a` at each call site:

- `count even [1, 2, 3]`     → `a = Int`
- `count isUpper "Hello"`    → `a = Char`
- `count null [[1],[],[2]]`  → `a = [Int]`

You write the function once; it works for everything. The Rust analogue would be a generic `fn count<A>(p: impl Fn(&A) -> bool, xs: &[A]) -> usize` — same idea, more ceremony.

**Line 2**: `count p = length . filter p`

| Token | What it is | What it means |
|-------|------------|---------------|
| `count` | identifier | must match the type signature |
| `p` | parameter | the predicate. **Only one parameter named** — the list isn't named. Point-free in the list |
| `=` | definition | binds the right-hand side to `count p` |
| `length` | function | `[b] -> Int`, returns the number of elements |
| `.` | function composition operator | infix. `f . g` means `\x -> f (g x)`. Read **right-to-left** |
| `filter` | function | `(a -> Bool) -> [a] -> [a]`, keeps elements where the predicate is `True` |
| `p` | argument to `filter` | partial application: `filter p` has type `[a] -> [a]` |

#### What `(.)` actually does

```haskell
(.) :: (b -> c) -> (a -> b) -> (a -> c)
f . g = \x -> f (g x)
```

It glues two functions end-to-end. `f . g` runs `g` first, then `f` on the result. Reads right-to-left, which feels backwards at first.

For our line:

```
filter p           :: [a] -> [a]      -- runs first (right side of .)
length             :: [a] -> Int      -- runs second (left side of .)
length . filter p  :: [a] -> Int      -- composed
```

So `count p` returns a function `[a] -> Int`. After supplying `p`, the leftover type is `[a] -> Int` — exactly the tail of the type signature.

#### The verbose, equivalent version

```haskell
count p xs = length (filter p xs)
```

Three things changed:

1. The list is now named `xs`.
2. `filter p xs` is applied first — produces a `[a]`.
3. `length` is applied to that — produces an `Int`.

Compiles to identical machine code as the `length . filter p` version. The `.` form just hides `xs` because we don't need to name it: the result of `length . filter p` is already a function that's *waiting* for an `xs`.

The pattern:

```haskell
f x = g (h x)        ===        f = g . h
```

is the most common "make this point-free" rewrite in Haskell. Once you see it, you'll see it everywhere.

#### Trace on `count (> 3) [1, 5, 2, 4, 9]`

```
input list:           [1, 5, 2, 4, 9]
filter (> 3) list:    [5, 4, 9]               (drop 1 and 2; keep 5, 4, 9)
length [5, 4, 9]:     3
result:               3
```

The composition lets us read the algorithm as one breath: *"the count is the length of the filter."*

#### `(.)` vs Rust's method chain

`length . filter p` is exactly Rust's `iter().filter(p).count()`. The dot-chain reads left-to-right because Rust uses *method syntax* (the value flows leftward through `.method()`); Haskell's `.` is a function-composition operator that reads right-to-left because of how `f (g x)` nests in mathematics.

| Rust (left-to-right, method syntax) | Haskell (right-to-left, function composition) |
|---|---|
| `xs.iter().filter(p).count()` | `(length . filter p) xs` |
| `xs.iter().map(f).max()`      | `(maximum . map f) xs` |
| `xs.iter().filter(p).sum()`   | `(sum . filter p) xs` |

Same algorithm, opposite reading direction. Most Haskellers eventually start *thinking* right-to-left for `.` chains — the `aggregate ← transform ← select` order maps onto how the data flows (rightmost function sees the input first).

### Why `(hasExactly 2)` and not `hasExactly 2`?

In Haskell, function application is left-associative and tighter than any operator. `count hasExactly 2 ids` would parse as `count(hasExactly)(2)(ids)` — three applications, which is ill-typed. The parens around `(hasExactly 2)` group it into a single one-argument function before passing it to `count`. This is the same partial-application pattern as `captchaSum 1` in Day 0; the parens are just there because the surrounding context wants the whole "predicate" as one syntactic unit.

### Could it be one pass?

Yes — a single fold could maintain `(twos, threes)` together, halving the traversal. The savings would be ~250 list-cons walks, dwarfed by the 250 × 26 = 6,500 `Map.insertWith` calls inside `charCounts`. Not worth the loss of readability. **Make it correct and obvious first; profile before optimizing.**

---

## `differByOne` and `commonLetters`

These are the two helpers Part 2 leans on.

```haskell
differByOne :: String -> String -> Bool
differByOne a b = count id (zipWith (/=) a b) == 1

commonLetters :: String -> String -> String
commonLetters a b = [ x | (x, y) <- zip a b, x == y ]
```

### `differByOne`

`zipWith :: (a -> b -> c) -> [a] -> [b] -> [c]` is `zip` plus a per-pair function rolled together. `zipWith (/=) a b` produces a `[Bool]` — one element per position, `True` where the two strings differ.

Example: `zipWith (/=) "fghij" "fguij"` → `[False, False, True, False, False]`.

Then `count id` is the classic "count the `True`s" trick. `id :: a -> a` is the identity; on `[Bool]`, `filter id` keeps the `True`s, `length . filter id` counts them. So `count id (zipWith (/=) a b)` is the **Hamming distance**.

We compare to `1` for the predicate.

**Could it short-circuit?** Yes — once two mismatches are found, we know the answer is `False` and could stop. The straightforward version walks the whole 26-character string regardless. For Day 2's input that costs at most an extra ~25 character comparisons per pair, ~25 × 31,125 pairs = ~780k extra comparisons; in the noise compared to allocating the `[Bool]` itself. The clearer code wins.

A sharper version using a manual recursion with bang patterns would short-circuit and avoid the intermediate list — Day 2 is too small to make it worth introducing bang patterns yet.

### `commonLetters`

```haskell
commonLetters a b = [ x | (x, y) <- zip a b, x == y ]
```

A list comprehension — the same shape as `captchaSum`'s in Day 0. Pair up the characters; keep the `x` from each position where they agree.

When `differByOne a b` has just returned `True`, exactly 25 of the 26 positions agree, so `commonLetters a b` is the original ID with the one differing position removed — exactly the answer Part 2 wants.

---

## `part2` — the pair search

```haskell
import Data.List (foldl', tails)

part2 :: Puzzle -> String
part2 ids = head
  [ commonLetters a b
  | (a : rest) <- tails ids
  , b          <- rest
  , differByOne a b
  ]
```

This is the headline lesson of Day 2: a list comprehension with two generators is a nested loop, and the right-most generator varies fastest.

### The mental model: two generators = nested loops

The naive way to write "for each pair `(a, b)` with `a` before `b` in `ids`" is:

```haskell
part2 ids = head
  [ commonLetters a b
  | a <- ids
  , b <- ids
  , a /= b
  , differByOne a b
  ]
```

That iterates every ordered pair (and `a /= b` excludes the diagonal), which means it visits each unordered pair *twice* — once as `(fghij, fguij)` and once as `(fguij, fghij)`. Both yield the same `commonLetters`, so the comprehension is still correct, but it does double the work.

The version we use is slightly trickier:

```haskell
[ commonLetters a b
| (a : rest) <- tails ids
, b          <- rest
, differByOne a b
]
```

`tails ids` produces *every suffix* of `ids`, longest first:

```ghci
ghci> tails [1, 2, 3]
[[1,2,3], [2,3], [3], []]
```

The pattern `(a : rest)` then matches each *non-empty* suffix, binding `a` to the head and `rest` to the elements after it. The empty suffix `[]` doesn't match `(_ : _)`, so it is silently skipped. (Pattern-match failure inside a list comprehension is a no-op, not an error — a useful contrast with `case`/function definitions, where it is a partial-pattern crash.)

So as `a` ranges over the IDs in order, `rest` is exactly *the IDs that come after `a` in the list*. The inner generator `b <- rest` then enumerates only those. The result: each unordered pair `{a, b}` is generated exactly once, with `a` always the earlier one.

For 250 IDs, the naive version visits 250 × 250 = 62,500 pairs (or 62,250 with `a /= b`), the `tails` version visits 250 × 249 / 2 = 31,125 pairs — half. The runtime cost is dominated by `differByOne` itself, so the speedup is real but modest. Picking the pattern up early is worth more than the microseconds: it generalises to every "all unordered pairs" puzzle in AoC.

### Three generators to keep in your head

```haskell
[ ... | a <- xs, b <- xs, ... ]               -- ordered pairs (i, j)  including (j, i)
[ ... | a <- xs, b <- xs, a /= b, ... ]       -- ordered pairs (i, j)  with i ≠ j  (still both directions)
[ ... | (a:rest) <- tails xs, b <- rest, ... ] -- unordered pairs (i, j) with i < j  (each pair once)
```

The third is the canonical "pair search" idiom in AoC Haskell. Internalise it.

### Why `head` is total here

`head :: [a] -> a` crashes on `[]`. We use it because the puzzle promises that exactly one pair satisfies `differByOne`. If our parser is correct and the puzzle's promise holds, the comprehension produces a non-empty list, and `head` returns the first (only) element.

For real software you'd write:

```haskell
case [...] of
  (x : _) -> x
  []      -> error "Day 02 Part 2: no near-pair found"
```

For AoC, `head` is fine — wrong input is wrong input.

### Lazy short-circuit

List comprehensions are lazy. `head [...]` only forces enough of the list to produce the first element, so the moment a pair satisfies `differByOne`, the search returns and the remaining pairs are never visited. For our input, the answer is found at pair index 31,003 (lines 53 vs 216), out of ~31,125 total pairs — so the short-circuit doesn't save much *here*, but the pattern is right and on luckier inputs it would.

### Why no `Data.Map`-based bucketing

The bucketing trick (group IDs by "ID with position k erased" for each k) would be O(n · L) instead of O(n² · L), but for n = 250 and L = 26 the constant factors swallow the asymptotic win. The pair-search version is one comprehension and is the right Day 2 lesson; the bucketing version is sketched in [Possible optimization](#possible-optimization--bucketing-instead-of-pair-search) for completeness.

---

## `solve`

```haskell
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ part2 puzzle)
```

Identical to Day 0 / Day 1 except for the last line: Part 2's answer is already a `String`, so we append it directly. Routing it through `show` would surround it with `"…"` quotes, which the dispatcher's pretty-printed output does not want.

This is the first day where `part1` and `part2` have *different* return types in this project (`Int` vs `String`). The dispatcher contract `solve :: String -> IO ()` does not care — `solve` swallows both answers internally and prints them.

Run it:

```bash
cabal run aoc2018-solve -- 2
```

Output:

```
Day 02 (input: inputs/day02.txt)
  part 1: 5880
  part 2: tiwcdpbseqhxryfmgkvjujvza
```

---

## Tests

The full test file is [Day02Spec.hs](../../test/Day02Spec.hs). Coverage:

1. **Parser shape** — `parseInput` splits on `'\n'` and tolerates a missing trailing newline.
2. **`charCounts`** — `bababc` produces `{a: 2, b: 3, c: 1}`; the empty string gives `Map.empty`. Locks in the strict-Map key/value contract.
3. **`differByOne`** — `True` for `fghij` / `fguij`; `False` for two-character difference (`abcde` / `axcye`); `False` for identical strings.
4. **`commonLetters`** — `fghij` / `fguij` → `fgij`; identical → the whole string.
5. **Part 1 example** — the seven-ID puzzle example, checksum = 12.
6. **Part 2 example** — the seven-ID puzzle example, common letters = `fgij`.
7. **Actual input** — `part1 = 5880` and `part2 = tiwcdpbseqhxryfmgkvjujvza` against `inputs/day02.txt`.

11 examples total. `cabal test` runs every spec file in `test/` automatically (the `hspec-discover` machinery). After Day 2 the project's running total is 86 examples, 0 failures, 46 still-pending stubs for Days 3–25.

The `Map` equality test for `charCounts` uses `Map.fromList`, the standard way to write a small literal map. `Map.fromList [('a',2),('b',3),('c',1)]` builds the same structure that the fold does, so `==` is a structural comparison.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`, criterion `--time-limit 8`.

| Bench               | Mean       | What it times                                                                |
|---------------------|-----------:|------------------------------------------------------------------------------|
| `day02/parseInput`  |   84.7 µs  | Just `lines` over the 7-kB raw `String` (250 lines × 27 chars incl. `\n`).   |
| `day02/part1`       |  439.9 µs  | 250 × 26 `Map.insertWith` calls, plus two passes for `hasExactly 2/3`.       |
| `day02/part2`       |   1.02 ms  | 31,003 pair tests until the unique near-pair is found.                       |
| `day02/combined`    |   2.12 ms  | `\r -> let p = parseInput r in (part1 p, part2 p)` from raw text.            |

**Total = Parse + Part 1 + Part 2 ≈ 1.54 ms.**

Two things stand out:

1. **`part1` is more expensive than `parseInput`.** Counter-intuitive — Day 1 had the parser dominating. The reason is that `charCounts` does ~26 `Map.insertWith` calls per ID × 250 IDs = 6,500 balanced-tree updates, and we run two passes (one for `hasExactly 2`, one for `hasExactly 3`). A single-pass version that maintains `(twos, threes)` together would roughly halve this; switching the per-ID counter to a 26-element `IntMap` or unboxed array would reduce the per-update constant by maybe 3×. Neither is worth the code-complexity tax at this scale — the whole day fits in 1.5 ms.
2. **`part2` is fast enough that the asymptotic-improvement bucketing version is barely worth the rewrite.** 31,000 pair tests at ~33 ns per test is exactly the 1 ms we measure. The bucketing version would be ~250 × 26 = 6,500 hashtable operations, faster, but the code reads less directly and the win is sub-millisecond.

The `combined` bench is again ~30% above the sum of the parts because it allocates a fresh parsed `[String]` every iteration, the GC noise that Day 0's guide [explains in detail](day00_function_guide.md#benchmarks). Headline figure stays at 1.54 ms (sum of the cached parts).

**Reproducing**:

```bash
cabal bench --benchmark-options="--match prefix day02"
cabal bench --benchmark-options="--match prefix day02 --time-limit 8"   # steadier
```

---

## Possible optimization — bucketing instead of pair search

The pair-search Part 2 is O(n² · L) with n = 250 IDs and L = 26 characters, which works out to ~810,000 character comparisons (worst case, before short-circuit). The structural alternative is O(n · L) and runs entirely without comparing pairs.

**The insight.** Two IDs differ in exactly one position iff there is *some* index `k` such that erasing position `k` from both leaves identical strings. So for each `k`, generate the "erased" version of every ID; if two IDs collide in the same `k`-bucket, they are the unique near-pair.

**Sketch (untested — keeping the pair-search as `part2`; this is for completeness)**:

```haskell
import qualified Data.Map.Strict as Map
import           Data.Maybe      (mapMaybe)

part2Fast :: Puzzle -> String
part2Fast ids = head (mapMaybe collisionAtPosition [0 .. width - 1])
  where
    width = length (head ids)                            -- 26 for our input

    -- The ID with position k removed.
    erase :: Int -> String -> String
    erase k s = take k s ++ drop (k + 1) s

    -- For one column k: build a Map from "erased ID" to the list of
    -- original IDs that produced it; return the first key whose
    -- bucket has two entries (only one such bucket exists per puzzle).
    collisionAtPosition :: Int -> Maybe String
    collisionAtPosition k =
      let buckets = Map.fromListWith (++) [ (erase k s, [s]) | s <- ids ]
      in  case Map.toList (Map.filter (\xs -> length xs >= 2) buckets) of
            ((commonStr, _) : _) -> Just commonStr
            []                   -> Nothing
```

**Estimated speedup.** O(n · L) is ~6,500 elementary operations; the pair search is ~810,000 in the worst case but stops at the first hit (~31,000 for our input). The realistic win is ~5–10× — somewhere in **100–200 µs** instead of 1 ms. Not the kind of difference you would notice without a benchmark.

**Why it isn't in the main code.** Three reasons.

1. **The pair search is the natural reading** of the Part 2 prompt ("among all pairs, find the one that…"). The bucketing version requires a structural insight (collision = position-k erasure) that is *not* the puzzle's framing.
2. **The pair search introduces `tails`-with-head-pattern and multiple-generator comprehensions** — both new on Day 2 and broadly useful. The bucketing version reuses `Data.Map` in a slightly different shape, but doesn't teach a new core mechanic.
3. **The wins are small** at AoC scale. For a 100,000-ID input the bucketing version would be the right call; for 250 IDs the readability tax is the dominant cost.

If a future re-read benchmarks Day 2 again and decides 1 ms is in the way, the optimization is here, ready to drop in. Until then, the pair search stays.

---

## Key patterns

Three takeaways that generalise.

1. **`Map.insertWith (+) k 1` is the frequency-count idiom in Haskell.** Every "how many of each X?" puzzle uses it. Memorize the shape; reach for `Data.Map.Strict` (not the lazy variant) so the counter stays evaluated.
2. **`(a : rest) <- tails xs` enumerates unordered pairs.** Whenever the algorithm is "for each pair `{i, j}` with `i ≠ j`," reach for this pattern. It is half the work of the naive double generator and the canonical Haskell idiom.
3. **List comprehensions short-circuit when consumed lazily.** `head [ … | … ]` walks just enough of the comprehension to produce one element. This means a brute-force pair search is often "fast enough" without any cleverness — the runtime arranges the early exit.

---

## Side-by-side with the Rust mental model

There is no committed Rust baseline for AoC 2018; the Rust mental model is sketched below.

```rust
use std::collections::BTreeMap;

fn char_counts(id: &str) -> BTreeMap<char, u32> {
    let mut m = BTreeMap::new();
    for c in id.chars() { *m.entry(c).or_insert(0) += 1; }
    m
}

fn part1(ids: &[String]) -> u32 {
    let twos   = ids.iter().filter(|s| char_counts(s).values().any(|&v| v == 2)).count();
    let threes = ids.iter().filter(|s| char_counts(s).values().any(|&v| v == 3)).count();
    (twos as u32) * (threes as u32)
}

fn part2(ids: &[String]) -> String {
    for (i, a) in ids.iter().enumerate() {
        for b in &ids[i + 1..] {
            let diffs = a.chars().zip(b.chars()).filter(|(x, y)| x != y).count();
            if diffs == 1 {
                return a.chars().zip(b.chars())
                       .filter(|(x, y)| x == y)
                       .map(|(x, _)| x).collect();
            }
        }
    }
    unreachable!()
}
```

Lined up with the Haskell version:

| Concept                            | Rust                                                          | Haskell                                                          |
|------------------------------------|---------------------------------------------------------------|------------------------------------------------------------------|
| Frequency count                    | `*map.entry(c).or_insert(0) += 1`                             | `Map.insertWith (+) c 1 m`                                       |
| "Some letter appears n times"      | `counts.values().any(|&v| v == n)`                            | `n `elem` Map.elems counts`                                      |
| Unordered pair iteration           | `for (i, a) in xs.iter().enumerate() { for b in &xs[i+1..] }` | `(a : rest) <- tails xs, b <- rest`                              |
| Hamming distance                   | `a.chars().zip(b).filter(...).count()`                        | `count id (zipWith (/=) a b)`                                    |
| Common letters                     | `.zip().filter(=).map(fst).collect::<String>()`               | `[ x | (x, y) <- zip a b, x == y ]` (list comprehension)         |
| Stop at first match                | `if … { return … }`                                           | `head [ commonLetters … | … ]` (lazy short-circuit)              |
| Container choice                   | `BTreeMap<char, u32>` — O(log n), ordered                     | `Data.Map.Strict.Map Char Int` — same                            |

Two real differences in flavour, beyond the syntactic line-up:

- **Rust uses a mutable `BTreeMap`; Haskell threads an immutable one through a fold.** Performance is similar (both O(log k) per insert with k = distinct keys); the Rust style mutates one allocation, the Haskell style makes a chain of small allocations that share most of their internal structure.
- **Rust's pair iteration is explicit indexing; Haskell's is `tails` + pattern.** The Haskell version does not name an integer index — it reads as "for each ID and the IDs after it" rather than "for each `i`, for each `j > i`". Both compile to the same loop shape; the Haskell phrasing avoids the off-by-one trap that always lurks in `i + 1..`.

For this puzzle Rust would be ~5× faster end-to-end, dominated by `String` vs `[Char]` traversal and `BTreeMap` vs `Data.Map` constant factors. We accept the gap; for 1.5 ms it does not matter.

---

**Navigation**: [Problem statement](day02.md) | [Summary table](summary_2018.md) | [← Day 1](day01_function_guide.md) | Day 3 → *(not yet attempted)*
