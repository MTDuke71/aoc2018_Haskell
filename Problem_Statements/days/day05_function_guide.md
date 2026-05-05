# Day 05: Alchemical Reduction -- Function Guide

**Problem**: A polymer string reacts by repeatedly removing adjacent same-letter/opposite-case pairs until no more reactions are possible. Part 1 counts surviving units in the reacted input polymer. Part 2 tries removing each letter type in turn, reacts the remainder, and returns the shortest result.
**Answers**: Part 1 = **11264**, Part 2 = **4552**
**Runtime** (mean, criterion `-O2`): Parse = **344 µs** | Part 1 = **1.04 ms** | Part 2 = **47.7 ms** | **Total = 49.1 ms**
**Code**: [Day05.hs](../../src/Day05.hs)
**Tests**: [Day05Spec.hs](../../test/Day05Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day05"`
**Problem statement**: [day05.md](day05.md)

**New concepts this day** (beyond Days 0--4):

- **`foldl'` as a stack processor** -- the canonical Haskell idiom for left-to-right string transformations where each step depends on the most recently produced output. This day makes the "accumulator is a stack" shape concrete.
- **`Data.Char.toLower` / `isLetter`** -- character-level case operations.
- **Why `foldl'` beats `foldr` here** -- the reaction needs the *immediately preceding surviving unit* (top of the stack), which is naturally the head of the `foldl'` accumulator. `foldr` processes right-to-left and cannot "look left" at already-processed output.
- **`minimum` over a list comprehension** -- exhaustive search over 26 choices in one readable expression.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Data model](#data-model)
3. [`parseInput`](#parseinput)
4. [`reacts`](#reacts)
5. [`react` -- `foldl'` as a stack processor](#react)
6. [`removeUnit`](#removeunit)
7. [`part1`](#part1)
8. [`part2`](#part2)
9. [`solve`](#solve)
10. [Tests](#tests)
11. [Benchmarks](#benchmarks)
12. [`foldl'` vs `foldr` -- when each belongs](#foldl-vs-foldr)
13. [Possible optimization -- single-pass Part 2](#possible-optimization)
14. [Key patterns](#key-patterns)
15. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The polymer is a string of letter-units such as `dabAcCaCBAcCcaDA`. Two adjacent units *react* and are destroyed if they are the same letter but opposite case: `aA` and `Aa` react; `aa`, `AA`, and `aB` do not. After one reaction, the remaining units might expose a new adjacent pair, so reactions can chain:

```
dabA*cC*aCBAcCcaDA   -- 'cC' reacts
dab*Aa*CBAcCcaDA     -- 'Aa' reacts
dabCBA*cCc*aDA       -- 'cC' (or 'Cc') reacts
dabCBAcaDA           -- no more reactions; 10 units remain
```

**Part 1**: react the full puzzle polymer; return the unit count (11264).

**Part 2**: for each letter `a`--`z`, remove all units of that type (both cases) from the polymer, react the result, record the length. Return the minimum length across all 26 choices (4552 -- achieved by removing the letter whose elimination most breaks up reaction chains).

---

## Data model

```haskell
-- no custom type needed; the polymer is just a String
parseInput :: String -> String
```

A polymer is a `String = [Char]` -- Haskell's linked list of `Char`. For a 50 KB input with 50000 characters, a linked list is not the most memory-efficient representation (each `Char` node has a box pointer), but for a once-through reaction the allocation pattern is manageable. See [the optimization sidebar](#possible-optimization) for a `Data.Text` or `Data.ByteString` upgrade path if this ever becomes a bottleneck.

---

## `parseInput`

```haskell
parseInput :: String -> String
parseInput = filter isLetter
```

`Data.Char.isLetter :: Char -> Bool` returns `True` for any Unicode letter. For ASCII polymer input it is equivalent to `\c -> (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')`. Using `isLetter` is both shorter and more defensive: it silently discards newlines, carriage returns (`\r` in Windows-format files), and any stray whitespace without requiring a special case.

---

## `reacts`

```haskell
reacts :: Char -> Char -> Bool
reacts a b = a /= b && toLower a == toLower b
```

Two units react iff they are the same letter (`toLower a == toLower b`) but different case (`a /= b`). The two-part test covers all cases:

| `a` | `b` | `a /= b` | `toLower` equal | Result |
|-----|-----|----------|-----------------|--------|
| `a` | `A` | True     | True            | **True** (react) |
| `A` | `a` | True     | True            | **True** (react) |
| `a` | `a` | False    | True            | False (same polarity) |
| `A` | `A` | False    | True            | False (same polarity) |
| `a` | `B` | True     | False           | False (different letter) |

`Data.Char.toLower :: Char -> Char` converts a character to lower-case; upper-case letters become lower-case and everything else is unchanged.

`/=` is Haskell's "not equal" operator (the infix form of `neq`, but written without the space needed for `!=`). It is the negation of `==`.

---

## `react`

```haskell
react :: String -> String
react = foldl' step []
  where
    step :: String -> Char -> String
    step []           c = [c]
    step (top : rest) c
      | reacts top c = rest            -- pair annihilates; pop the stack
      | otherwise    = c : top : rest  -- no reaction; push onto the stack
```

### `foldl'` as a stack processor

`foldl' :: (b -> a -> b) -> b -> [a] -> b` folds a list left-to-right with a *strict* accumulator. The general shape:

```
foldl' f z [x1, x2, x3, ...]
= f (f (f z x1) x2) x3 ...
```

Here the accumulator `b = String` is a *stack* (a list used only at its head). The fold processes the polymer character by character, left-to-right:

- **Empty stack (`[]`)**: push the character -- no one to react with.
- **Non-empty stack (`top : rest`)**: check whether the new character `c` reacts with the top. If yes, pop (`rest` -- both units vanish). If no, push (`c : top : rest`).

After the full fold, the accumulator holds the surviving units in *reverse* order (head of the list = last surviving unit). Since Part 1 and Part 2 only need `length`, the reversal is harmless. Call `reverse . react` if you need the units in original order.

### Tracing `"abBA"`

| Input char | Stack before | Action | Stack after |
|------------|-------------|--------|-------------|
| `'a'`      | `[]`        | empty -- push | `['a']` |
| `'b'`      | `['a']`     | `reacts 'a' 'b'`? No -- push | `['b','a']` |
| `'B'`      | `['b','a']` | `reacts 'b' 'B'`? Yes -- pop | `['a']` |
| `'A'`      | `['a']`     | `reacts 'a' 'A'`? Yes -- pop | `[]` |

Length 0. Correct: `"abBA"` fully annihilates.

### Tracing `"abAB"`

| Input char | Stack before | Action | Stack after |
|------------|-------------|--------|-------------|
| `'a'`      | `[]`        | push | `['a']` |
| `'b'`      | `['a']`     | `reacts 'a' 'b'`? No -- push | `['b','a']` |
| `'A'`      | `['b','a']` | `reacts 'b' 'A'`? No (different letter) -- push | `['A','b','a']` |
| `'B'`      | `['A','b','a']` | `reacts 'A' 'B'`? No (different letter) -- push | `['B','A','b','a']` |

Length 4. Correct: `"abAB"` has no reactions.

### Why the result is reversed (and why it does not matter)

The stack grows leftward: each push prepends to the head. After processing `"abAB"`, the stack is `['B','A','b','a']` -- the last character processed (`B`) is at the head. The "correct" remaining polymer in original order would be `"abAB"`, i.e. `['a','b','A','B']`. These are reverses of each other.

For `length` this makes no difference: `length ['B','A','b','a'] == 4` just as `length ['a','b','A','B'] == 4`. If you needed the actual remaining string for display or further processing, you would write `reverse (react polymer)`.

### Why `foldl'` and not `foldr`

The reaction checks the *top of the stack* -- the unit that was most recently added to the output. This is a *left context*: we look backward into already-processed output.

`foldr` processes the list *right-to-left*, building the result from the right end. In a `foldr`-based formulation, when we process element `x` we would know what comes *after* it in the input, not what we have already added to the output. We cannot "look left" at the most recently produced output.

`foldl'` processes left-to-right and keeps the most recently produced output at the head of the accumulator -- exactly the look-back we need. See the [dedicated section below](#foldl-vs-foldr).

---

## `removeUnit`

```haskell
removeUnit :: Char -> String -> String
removeUnit c = filter (\x -> toLower x /= c)
```

Removes all units of type `c` from the polymer. The predicate `\x -> toLower x /= c` matches any unit whose lower-case form differs from `c`. Since `c` is always passed as a lower-case letter (`'a'..'z'`), this removes both `'c'` and `'C'` when called as `removeUnit 'c'`.

The call `removeUnit 'c' "dabAcCaCBAcCcaDA"` produces `"dabAaBAaDA"`, which then reacts to 4 units.

---

## `part1`

```haskell
part1 :: String -> Int
part1 = length . react
```

Two composed functions: react the polymer, count surviving units. The composition reads right-to-left: apply `react` first, then `length`.

---

## `part2`

```haskell
part2 :: String -> Int
part2 polymer =
  minimum [length (react (removeUnit c polymer)) | c <- ['a' .. 'z']]
```

A list comprehension that tries all 26 letters, reacts each reduced polymer, collects the lengths, and takes the minimum. Reading the comprehension:

| Part | Meaning |
|------|---------|
| `length (react (removeUnit c polymer))` | the yield expression -- the length after removing `c` and reacting |
| `c <- ['a'..'z']` | generate each lower-case letter in turn |

`['a'..'z']` is an *arithmetic sequence* (also called an *enumeration*): `[a, a+1, ..., z]`. For `Char`, GHC uses the Unicode code-point order, which for ASCII letters matches alphabetical order. This is `'a', 'b', ..., 'z'` -- exactly the 26 letters we want.

`minimum :: Ord a => [a] -> a` returns the smallest element of a non-empty list. For `Int`, this is the arithmetic minimum.

### Performance note

`part2` runs 26 full `react` passes over a ~50000-character polymer. Each pass is O(n) = ~50000 character comparisons. Total: 26 * O(50000) = O(1.3M) operations. At ~47 ms this is well within tolerance, but it is the most expensive step in the whole project so far for a single part.

---

## `solve`

```haskell
solve :: String -> IO ()
solve contents = do
  let polymer = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 polymer))
  putStrLn ("  part 2: " ++ show (part2 polymer))
```

`parseInput` is called once. Both `part1` and `part2` receive the same `polymer` binding -- the parse is not repeated. This is enforced by sharing, not by any special mechanism: once `polymer` is bound in the `let`, every reference to it in the same scope reads the same thunk, which is forced once and cached.

---

## Tests

Coverage in [Day05Spec.hs](../../test/Day05Spec.hs):

1. **`reacts`** -- five cases covering all combinations of same/different case and same/different letter, plus symmetry.
2. **`react`** -- four small examples from the puzzle description, testing both full annihilation and no-reaction.
3. **Part 1 on puzzle example** -- `"dabAcCaCBAcCcaDA"` reduces to 10 units.
4. **Part 2 on puzzle example** -- minimum after removing one letter type is 4 (removing `c`/`C`).
5. **Actual input** -- Part 1 = 11264, Part 2 = 4552.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean     | What it times |
|--------------------|----------:|---------------|
| `day05/parseInput` |  344 µs  | `filter isLetter` over the 50 KB raw input. |
| `day05/part1`      | 1.04 ms  | One `react` pass over ~50000 characters. |
| `day05/part2`      | 47.7 ms  | 26 `removeUnit` + `react` passes, total ~1.3 M character operations. |
| `day05/combined`   | 50.5 ms  | End-to-end from raw string. |

**Total = Parse + Part 1 + Part 2 = 49.1 ms.**

Part 2 dominates: 26 sequential `react` calls, each touching the whole polymer. The gap between Part 1 (1 ms) and Part 2 (48 ms) is exactly 26x, as expected.

The `combined` bench reports 50.5 ms vs the summed 49.1 ms -- the 1.4 ms overhead is the extra `parseInput` + GC cost inside `combined`. For this day the discrepancy is small because Part 2 is so dominant.

---

## `foldl'` vs `foldr`

This day is the natural place to make the `foldl'` / `foldr` distinction concrete, because the reaction algorithm *requires* `foldl'`. Let us see why.

### The fundamental difference

```haskell
foldl' f z [a, b, c] = f (f (f z a) b) c  -- left to right, strict accumulator
foldr  g z [a, b, c] = g a (g b (g c z))  -- right to left, lazy intermediate values
```

`foldl'` builds the result from the left, producing a value at each step. The accumulator is strictly evaluated after each `f` call (that's what the `'` means -- it uses `seq` to force the accumulator before the next step).

`foldr` builds the result from the right: `g a` receives the *not-yet-computed* `g b (g c z)` as its second argument. The final result is only produced when all of `g`'s applications are forced.

### When `foldl'` is the right choice

Use `foldl'` when:

1. **You need left-to-right context.** This day: each unit's reaction depends on what came before it (the stack top). The stack naturally lives in the `foldl'` accumulator.
2. **The result is a single value (Int, Map, Set, String) that must be fully evaluated.** `foldl'` pays the accumulator cost eagerly; `foldl` (without the `'`) defers it and risks a thunk tower.
3. **The input is finite and you need all of it.** `foldl'` cannot short-circuit; it always processes the whole list.

**Numeric reductions** (`sum`, `product`, `length`) always belong to `foldl'`. Building a `Map` via `Map.insertWith` belongs to `foldl'`. This day's `react` belongs to `foldl'`.

### When `foldr` is the right choice

Use `foldr` when:

1. **You need right-to-left structure.** Constructing a list from left to right naturally uses `foldr`: `foldr (:) [] xs = xs`. `foldl' (:) [] xs = reverse xs` -- you get the list reversed for free, but that is usually not what you want.
2. **You may short-circuit.** `foldr` is lazy in its second argument. This means functions like `any`, `all`, and `find` (which can stop early) are implemented via `foldr` and stop as soon as the answer is known. A `foldl'`-based `any` would always process the entire list.
3. **The input is infinite.** `foldr` can produce output before it has seen the full input. `foldl'` can never do this: it needs the rightmost element before it can start producing the final value.

### Summary for beginners

| Situation | Use |
|-----------|-----|
| Sum, product, count | `foldl'` |
| Build a `Map` or `Set` | `foldl'` |
| String/list transformation with look-back | `foldl'` |
| Reconstruct a list (map, filter equivalent) | `foldr` |
| Short-circuit search (`any`, `all`) | `foldr` (or built-ins that use it) |
| Infinite input | `foldr` |

**Rule of thumb**: start with `foldl'`. Reach for `foldr` only when you specifically need the laziness or the right-to-left structure.

---

## Possible optimization

### Part 2: process all 26 reductions in a single pass

The current `part2` does 26 independent `react` passes. A smarter approach: build the reaction stack once, tagging each unit with its original letter. Then, for each candidate letter `c`, simulate how removing all `c`/`C` units from the *stack* would merge its neighbors.

This is conceptually sound but requires careful bookkeeping (the removal of a unit can trigger new reactions among its former neighbors). The implementation would use a doubly-linked list or a zipper to do local fixups in O(n) total work across all 26 candidates, for an overall O(26n) -> O(n) improvement. In practice, on this input, the difference would be ~50 ms -> ~3 ms.

**Sketch** (untested):

```haskell
-- Build the reacted stack, keeping each unit tagged with its type.
-- For each removal candidate c:
--   1. Start from the reacted stack.
--   2. Remove all units of type c.
--   3. Apply local re-reactions: wherever removing a unit exposed two
--      units that now react, propagate the reaction outward until stable.
-- The minimum stack length is the answer.
```

The current 26-pass approach is simpler and 49 ms is fast enough for AoC. The sketch lives here for future reference.

### Part 1: `Data.Text` for the polymer

`String = [Char]` allocates one cons cell per character. For 50000 characters that is 50000 heap objects. `Data.Text` (or `Data.ByteString.Char8`) stores characters as a contiguous array, reducing allocation by an order of magnitude and improving cache locality. Switching the polymer type to `Text` and using `T.foldl'` would likely drop Part 1 from 1 ms to ~0.3 ms. For a 1 ms measurement there is no practical need.

---

## Key patterns

1. **`foldl' step []` for stack-based string processing.** Whenever an algorithm says "walk left to right, and each step depends on the most recently produced output," reach for this shape. The accumulator is the stack; `step` pushes or pops.
2. **The result of `foldl'`-as-stack is reversed.** If you need the output in forward order, apply `reverse`. If you only need the length, skip it.
3. **`minimum [f x | x <- candidates]` for exhaustive search.** Comprehension + `minimum` replaces an explicit loop and running minimum. The list is fully materialized (26 elements), but that is trivially cheap.
4. **`filter isLetter` is the safest one-line polymer parser.** It handles `\n`, `\r`, and any other whitespace without special-casing. Use `filter isDigit` for digit-only inputs, `filter isAlphaNum` when you want both.

---

## Side-by-side with the Rust mental model

```rust
fn reacts(a: char, b: char) -> bool {
    a != b && a.to_lowercase().next() == b.to_lowercase().next()
}

fn react(polymer: &str) -> Vec<char> {
    let mut stack: Vec<char> = Vec::new();
    for c in polymer.chars() {
        match stack.last() {
            Some(&top) if reacts(top, c) => { stack.pop(); }
            _                             => stack.push(c),
        }
    }
    stack
}

fn part1(polymer: &str) -> usize {
    react(polymer).len()
}

fn part2(polymer: &str) -> usize {
    ('a'..='z')
        .map(|c| {
            let reduced: String = polymer
                .chars()
                .filter(|&x| x.to_ascii_lowercase() != c)
                .collect();
            react(&reduced).len()
        })
        .min()
        .unwrap()
}
```

Lined up with Haskell:

| Concept | Rust | Haskell |
|---------|------|---------|
| Stack | `Vec<char>` (push/pop at the end) | `[Char]` (push/pop at the head via `:`) |
| Fold over string | `for c in polymer.chars()` | `foldl' step []` |
| Push | `stack.push(c)` | `c : top : rest` |
| Pop | `stack.pop()` | `rest` |
| Look at top | `stack.last()` | pattern `(top : rest)` in `step` |
| Reaction test | `reacts(top, c)` | `reacts top c` |
| Remove unit type | `.filter(\|&x\| x.to_ascii_lowercase() != c)` | `filter (\x -> toLower x /= c)` |
| Exhaustive search | `('a'..='z').map(...).min()` | `minimum [...\| c <- ['a'..'z']]` |

Key difference: Rust's stack is a `Vec` that grows at the *right* (push/pop at the end, O(1) amortized). Haskell's stack grows at the *left* (cons/uncons at the head, O(1) exact). Both are O(1) per step. The Haskell result is reversed relative to Rust's, but `length` is the same.

The other difference is eagerness: Rust's `react` builds the whole stack eagerly in a mutable `Vec`. Haskell's `foldl'` also forces the accumulator at every step (the `'` ensures this), so both algorithms are strictly equivalent in their evaluation order.

---

**Navigation**: [Problem statement](day05.md) | [Summary table](summary_2018.md) | [<- Day 4](day04_function_guide.md) | Day 6 -> *(not yet attempted)*
