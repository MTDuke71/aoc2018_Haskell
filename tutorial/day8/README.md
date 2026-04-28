# Day 8 — `Data.Map.Strict` and `Data.Set`

**Goal**: graduate from `[(k, v)]` and `elem x xs` to the two containers AoC actually leans on. By the end you will reach for `Map.insertWith (+) k 1` to count things, `Map.lookup` to translate keys to values, and `Set.member` to ask "have I seen this before?" — and you will know why the strict variant of `Map` is non-negotiable.

**Source files**:
- [src/MapBasics.hs](src/MapBasics.hs) — building, looking up, inserting, updating, folding, and combining maps. The `frequencies` and `mostCommon` patterns.
- [src/SetBasics.hs](src/SetBasics.hs) — sets as fast membership tests; union/intersection/difference; the `firstDuplicate` pattern.

---

## 1. The two containers and what they replace

Up to Day 7 the only keyed structures you have are lists of pairs and lists themselves:

```haskell
ages :: [(String, Int)]               -- a "map" via list of pairs
seen :: [Int]                         -- a "set" via list with elem
```

That works for ten elements. It falls over at ten thousand. Each `lookup` is a linear scan; each `elem` is a linear scan; the `frequencies` of an input is `O(n^2)` if you do it with lists. Two AoC puzzles in, you will be staring at a solution that takes minutes when it should take milliseconds.

Haskell's standard answer:

| Question | List operator | Container | Container operator | Cost |
|---|---|---|---|---|
| "What is the value at this key?" | `lookup` (linear) | `Data.Map.Strict` | `Map.lookup` | O(log n) |
| "Is this element in the collection?" | `elem` (linear) | `Data.Set` | `Set.member` | O(log n) |
| "Count duplicates / build a histogram" | hand-rolled | `Data.Map.Strict` | `Map.insertWith (+) k 1` | O(log n) per element |

Both containers are immutable, balanced trees. "Updating" them returns a new tree that shares most of its structure with the old one — same trick that records used on Day 7 to make immutable updates cheap.

**Rust analogue**: `Data.Map.Strict` is `BTreeMap` (ordered, log n) — *not* `HashMap`. `Data.Set` is `BTreeSet`. For the hash variants you would import `Data.HashMap.Strict` from the `unordered-containers` package, but `containers` ships with GHC and the ordered variants are the right default for AoC.

---

## 2. Qualified imports — finally explained

Day 8 is the first place a qualified import is essential. Open `MapBasics.hs`:

```haskell
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
```

The first line says: "load `Data.Map.Strict`, but every name from it must be prefixed with `Map.`." The second line says: "also bring the type name `Map` into scope unprefixed, so I can write `Map String Int` in type signatures."

Why bother? Two reasons:

- **Name clashes with the Prelude.** `Data.Map.Strict` exports `lookup`, `filter`, `map`, `null`, `foldr`, `foldl'`, `insert`, `delete`, and a dozen more. If you imported them unqualified, every call site would be ambiguous and the compiler would reject the file.
- **Reading clarity at the call site.** `Map.insert k v m` and `Set.insert x s` are immediately distinguishable. `insert k v m` and `insert x s` are not. The prefix is one short word that pays dividends every time you read the code six months later.

**Rust analogue**: this is closer to writing `std::collections::HashMap::new()` rather than `use std::collections::HashMap` followed by `HashMap::new()` — except in Haskell you give the prefix any short name you want. `Map`, `M`, and `IntMap` are common conventions; consistency across a project matters more than the choice itself.

---

## 3. Building a map: `empty`, `singleton`, `fromList`

Three constructors cover almost everything:

```haskell
Map.empty                                                   -- :: Map k v
Map.singleton "alice" 30                                    -- :: Map String Int
Map.fromList [("alice", 30), ("bob", 25), ("carol", 41)]    -- :: Map String Int
```

`fromList` is the bulk loader. If two pairs share a key, the **last** one wins:

```haskell
Map.fromList [("alice", 30), ("alice", 99)]
-- => fromList [("alice", 99)]
```

That tie-breaking rule is sometimes the wrong one. When you want to combine values instead of replacing them — sum scores, concatenate strings, take a max — use `fromListWith`:

```haskell
Map.fromListWith (+) [("food", 12), ("food", 18), ("rent", 800)]
-- => fromList [("food", 30), ("rent", 800)]
```

`fromListWith f` reduces collisions by calling `f new old`. Same shape as `insertWith` below, just batched.

---

## 4. Lookup and friends

`Map.lookup` returns the `Maybe` you met on Day 5:

```haskell
Map.lookup :: Ord k => k -> Map k v -> Maybe v
```

The `Ord k =>` constraint says "this only works when keys can be ordered." Type classes are the topic of a future day; for now read it as "any type that has a `compare`/`<`/`>` definition." Strings, `Int`, tuples, and any `data` you derived `Ord` for on Day 7 all qualify.

```haskell
Map.lookup "alice" ages                       -- Just 30
Map.lookup "dave"  ages                       -- Nothing
Map.findWithDefault 0 "dave" ages             -- 0
Map.member "bob"  ages                        -- True
Map.size           ages                       -- 3
```

Pattern-match on the `Maybe` with `case`, with `fromMaybe`, or with a guard — same options Day 5 gave you for any `Maybe`. The shape that comes up most in AoC:

```haskell
case Map.lookup k m of
  Just v  -> ...
  Nothing -> ...
```

---

## 5. Insert, delete, update — and why the result is a new map

```haskell
Map.insert  :: Ord k => k -> v -> Map k v -> Map k v
Map.delete  :: Ord k => k ->      Map k v -> Map k v
Map.adjust  :: Ord k => (v -> v) -> k -> Map k v -> Map k v
```

Every one returns a **new** map; the input is unchanged. Because the underlying tree is a balanced binary structure with shared subtrees, the new map shares O(n − log n) of its nodes with the old one — only the path from root to the inserted key needs fresh allocation. Updates are therefore cheap *and* persistent: you can hold on to the old version and compare or backtrack at no extra cost.

```haskell
withDave    = Map.insert "dave" 22 ages       -- ages still has 3 entries
bumpAlice   = Map.insert "alice" 31 ages      -- "insert" overwrites
withoutBob  = Map.delete "bob" ages
incrAlice   = Map.adjust (+1) "alice" ages    -- no-op if "alice" missing
```

`adjust` is "if the key is here, run this function on the value." For "if absent, here is a default" use `alter` (not shown — overkill for Day 8) or the next section's workhorse, `insertWith`.

---

## 6. The workhorse: `insertWith`

Half of all AoC puzzles touch a map of counters. The named function for that is `insertWith`:

```haskell
Map.insertWith :: Ord k => (v -> v -> v) -> k -> v -> Map k v -> Map k v
```

Read the function argument as `f new old -> combined`. If the key is absent, `insertWith` behaves like `insert` with the supplied value. If the key is present, it stores `f new old`. To count: insert `1` each time, combine with `(+)`.

```haskell
frequencies :: Ord a => [a] -> Map a Int
frequencies = foldl' bump Map.empty
  where bump m x = Map.insertWith (+) x 1 m
```

That is six lines that replace twenty. `frequencies "mississippi"` returns `fromList [('i',4),('m',1),('p',2),('s',4)]`.

### Why `Data.Map.Strict` and not `Data.Map`

Haskell ships two map modules: `Data.Map` (lazy values) and `Data.Map.Strict` (strict values). They have **identical** APIs and identical performance for everything except value updates. The difference shows up exactly with `insertWith`:

```haskell
-- Imagine we used the lazy Data.Map for frequencies.
-- The first time we hit 's' we insert 1.
-- The second time we hit 's' the value at the key becomes (1 + 1)
--   …but it is *not evaluated*. It stays as a thunk.
-- The third time:           ((1 + 1) + 1)
-- The fourth time:         (((1 + 1) + 1) + 1)
-- ...and so on, one thunk per occurrence.
```

That tower of unevaluated additions is exactly the same pathology Day 6 fixed with `foldl'`. The strict map's `insertWith` forces the new value to weak head normal form before storing it, so the tower never builds. Unless you have a very specific reason for lazy values, **always import `Data.Map.Strict`**.

This is the only point in Day 8 where you must *think* about laziness. Pick the strict module by default and the rest is muscle memory.

---

## 7. Walking a map

Three "extract everything" helpers and a fold:

```haskell
Map.keys   ages    -- ["alice", "bob", "carol"]   -- ascending key order
Map.elems  ages    -- [30, 25, 41]                -- values in key order
Map.toList ages    -- [("alice",30),("bob",25),("carol",41)]

Map.foldl' (+) 0 ages          -- folds values
Map.foldlWithKey' f z ages     -- folds keys + values together
```

The ordering guarantee — ascending by key — is the killer feature of `Data.Map` over `Data.HashMap`. When you need deterministic output, sorted iteration, or a sliding window over keys, the ordered map gives it to you for free.

`Map.foldl'` is the strict left fold from Day 6, lifted to maps. Same rule: prefer it over `Map.foldl`.

---

## 8. Combining maps: `union`, `unionWith`

Two maps; one result.

```haskell
Map.union     :: Ord k =>             Map k v -> Map k v -> Map k v   -- left-biased
Map.unionWith :: Ord k => (v -> v -> v) -> Map k v -> Map k v -> Map k v
```

`union` keeps the **left** map's value on conflict — the same "first one wins" rule you would get from `Map.fromList (Map.toList left ++ Map.toList right)`. `unionWith f` lets you say what to do on conflict — sum, max, append, whatever.

```haskell
scoresWeek1 = Map.fromList [("alice", 10), ("bob", 7)]
scoresWeek2 = Map.fromList [("alice", 5),  ("carol", 9)]

Map.union scoresWeek1 scoresWeek2          -- alice keeps 10 (left)
Map.unionWith (+) scoresWeek1 scoresWeek2  -- alice gets 15
```

`unionWith` is the way you merge per-day counters into a season total without flattening to a list and re-grouping.

---

## 9. `Data.Set` — the membership half

A `Set a` is a `Map a ()` with the unit erased. Same balanced tree, same O(log n) operations, no values to track.

```haskell
import qualified Data.Set as Set
import Data.Set (Set)

primes :: Set Int
primes = Set.fromList [2, 3, 5, 7, 11, 13]

Set.member 7 primes        -- True
Set.size   primes          -- 6
Set.insert 15 primes       -- new set with 15 added
Set.delete  2 primes       -- new set with 2 removed
```

`Set.fromList` deduplicates and sorts as a side effect — `Set.toAscList . Set.fromList` is a one-line `unique`:

```haskell
unique :: Ord a => [a] -> [a]
unique = Set.toAscList . Set.fromList
```

Notice there is no `Data.Set.Strict`. Sets store keys, not values; keys are forced anyway whenever the tree rebalances; strictness is not a knob you can turn here.

### Set algebra

Three operations from school maths, each O(m + n) worst case:

```haskell
Set.union        a b   -- everything in either set
Set.intersection a b   -- everything in both sets
Set.difference   a b   -- in a but not in b
```

```haskell
Set.intersection evens primes      -- {2}    -- the only even prime
Set.difference   primes evens      -- {3,5,7,11,13}
```

These are direct AoC building blocks: "which positions appear in path A *and* path B?", "which IDs do I see today that I did not see yesterday?".

---

## 10. The `firstDuplicate` pattern — sets earn their keep

The motivating pattern for `Set` in AoC is simple: walk a sequence, remember what you have seen, stop on the first repeat.

```haskell
firstDuplicate :: Ord a => [a] -> Maybe a
firstDuplicate = go Set.empty
  where
    go seen []       = Nothing
    go seen (x : xs)
      | Set.member x seen = Just x
      | otherwise         = go (Set.insert x seen) xs
```

A few things worth noticing:

- **The `Set` carries the work that a list cannot.** With `seen :: [a]`, `Set.member` becomes `elem`, and the whole pass is O(n^2). With `seen :: Set a`, every step is O(log n) and the pass is O(n log n).
- **Hand-rolled recursion, not a fold.** A fold walks the whole list; we want to stop early. A right fold *can* short-circuit (laziness in the accumulator), but the recursive shape is clearer for a learner and idiomatic Haskell.
- **`Ord a =>` again.** The constraint comes from `Set` itself: balanced trees need to compare elements to place them. Day 7's `deriving (Ord)` is exactly what makes your own `data` types eligible to live in a `Set`.

This is AoC 2018 Day 1 Part 2 in disguise: scan the running totals of a stream of frequency changes, return the first total you see twice. You will write this exact function (give or take a `scanl'`) in three weeks.

---

## 11. Walkthrough of the source files

`MapBasics.hs` is laid out as six numbered sections that mirror this README:

1. Building maps — `empty`, `singleton`, `fromList`, `fromListWith`.
2. Lookup, membership, size — `lookup`, `member`, `size`, `findWithDefault`.
3. Insert, delete, update — `insert`, `delete`, `adjust`.
4. The workhorse — `insertWith` and the `frequencies` function.
5. Walking a map — `keys`, `elems`, `toList`, `foldl'`, plus the `mostCommon` example using the Day 6 strict left fold.
6. Combining maps — `union` (left-biased) and `unionWith`.

`SetBasics.hs` follows a similar five-section shape:

1. Building sets — `empty`, `singleton`, `fromList`, plus the `unique` one-liner.
2. Membership and queries — `member`, `size`, `null`.
3. Insert and delete returning new sets.
4. Set algebra — `union`, `intersection`, `difference`.
5. The `firstDuplicate` pattern — set-as-accumulator in an explicitly recursive walk.

Run them like the previous days:

```bash
cd tutorial/day8
runghc src/MapBasics.hs
runghc src/SetBasics.hs
```

Or open one in GHCi:

```bash
ghci src/MapBasics.hs
```

```
ghci> :t Map.insertWith
Map.insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
ghci> frequencies "abracadabra"
fromList [('a',5),('b',2),('c',1),('d',1),('r',2)]
ghci> mostCommon "abracadabra"
Just ('a',5)
```

```bash
ghci src/SetBasics.hs
```

```
ghci> firstDuplicate [3, 1, 4, 1, 5, 9, 2, 6]
Just 1
ghci> Set.intersection (Set.fromList "hello") (Set.fromList "world")
fromList "lo"
```

---

## 12. Try it

Small exercises. Do them in GHCi with the relevant file loaded.

1. Define `wordFrequencies :: String -> Map String Int` using `frequencies` and `words`. Test on `"the quick brown fox jumps over the lazy dog the fox"` and check that `"the"` shows up 3 times.
2. Write `lookupOr :: Ord k => v -> k -> Map k v -> v` that returns the value at `k`, or the default if absent. Confirm it agrees with `Map.findWithDefault`. Pattern: `case Map.lookup k m of …`.
3. Add an entry to `ages` and observe in GHCi that the original `ages` is still the original three names. Persistence in action.
4. Write `mostCommonExcept :: Ord a => a -> [a] -> Maybe (a, Int)` — like `mostCommon`, but ignoring one specific value. Pattern: build the `frequencies`, call `Map.delete` on the excluded key, then fold.
5. Define `intersectAll :: Ord a => [Set a] -> Set a` using `foldr1 Set.intersection`. (Use `foldr1`, not `foldr`, so the empty-list case errors out — what you want here.) Test on `[Set.fromList "hello", Set.fromList "world", Set.fromList "lord"]`.
6. Write `firstRepeatedSum :: [Int] -> Maybe Int` — given a list of changes, walk the running totals (use `scanl' (+) 0` from `Data.List`) and return the first total that repeats. This is *exactly* AoC 2018 Day 1 Part 2.
7. Use `Map.foldlWithKey'` to write `kvSum :: Map String Int -> Int` that returns the sum of the *lengths of the keys* plus the values. Forces you to walk keys and values together.

---

## 13. What you should remember

- **Reach for `Data.Map.Strict` and `Data.Set` whenever you would otherwise scan a list.** O(log n) instead of O(n) per operation; that gap dominates AoC runtimes.
- **Always import the strict variant of `Map`.** `import qualified Data.Map.Strict as Map`. Lazy maps leak thunks through `insertWith`, exactly the way `foldl` leaked thunks on Day 6.
- **Qualified imports are the convention** for these modules. `Map.lookup`, `Set.member`, `Map.insertWith` read clearly and avoid Prelude name clashes.
- **`fromList` is the bulk loader** — `fromListWith` if duplicate keys need combining instead of overwriting.
- **`insertWith (+) k 1` is the counter pattern.** Folded over a list, it is `frequencies`.
- **`Map.union` is left-biased; `Map.unionWith f` lets you choose.** Same rule as `Map.fromList` deduplication: by default the "first one in" wins.
- **`Set` is `Map` without values** — same tree, same operations, same O(log n) costs. Use it whenever the question is "have I seen this?".
- **`Set.fromList . ...` deduplicates and sorts in one step.** The `unique` one-liner is the most-stolen idiom on the planet.
- **The `firstDuplicate` shape** — walk a list, accumulate into a `Set`, stop on the first hit — is the cycle/duplicate detector for half of AoC.
- **`Ord` is the entry ticket.** Anything you store in a `Map` key or a `Set` must have an `Ord` instance. Day 7's `deriving (Ord)` is what makes your own `data` types eligible.
- **Rust analogue summary**: `Data.Map.Strict` ↔ `BTreeMap` (ordered, log n); `Data.Set` ↔ `BTreeSet`; `Map.insertWith (+) k 1 m` ↔ `*map.entry(k).or_insert(0) += 1`; `Set.member` ↔ `BTreeSet::contains`; `Map.unionWith (+)` ↔ merging two maps with `entry().and_modify(…).or_insert(…)`.

---

**Next**: Day 9 — `IO`, `do` notation, and `readFile`. Until now every example has been pure: a function from input to output with no side effects. Day 9 introduces the part of Haskell that talks to the outside world — reading puzzle input from disk, printing the answer, and the `do` block that lets you sequence those effects.
