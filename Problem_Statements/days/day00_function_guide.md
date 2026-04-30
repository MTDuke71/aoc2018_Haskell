# Day 00 (AoC 2017 Day 1): Inverse Captcha — Function Guide

**Problem**: A circular list of digits. Sum the digits that match a partner at a fixed offset.
**Answers**: Part 1 = **1171**, Part 2 = **1024**
**Runtime** (mean, criterion `-O2`): Parse = **17.5 µs** | Part 1 = **11.2 µs** | Part 2 = **14.9 µs** | **Total = 43.6 µs**
**Code**: [Day00.hs](../../src/Day00.hs)
**Tests**: [Day00Spec.hs](../../test/Day00Spec.hs)
**Bench**: [bench/Main.hs](../../bench/Main.hs) — `cabal bench -- --match prefix day00`
**Rust baseline**: [day01.rs](../../reference/rust_baseline_2017/src/solver/day01.rs) (4.26 µs combined — Rust ~10× faster than Haskell's 43.6 µs, expected for tight integer-arithmetic code over a boxed list)

**Why this puzzle, on Day 0 of AoC 2018**: a tiny port that exercises the Day 10 cabal layout end-to-end — parse a real input file, solve two parts, run a passing hspec suite — before the actual 2018 calendar starts. It is also Day 11 of the [pre-AoC tutorial](../../tutorial/README.md): the bridge from "I learned the syntax" to "I can solve a puzzle."

**New concepts this day** (beyond what Days 1–10 already covered):
- A **two-component cabal project** that holds 26 day-modules at once (`Day00`..`Day25`), each behind one `solve` entry point.
- **Pairing a list with a shifted copy of itself** via `zip ds (rotate offset ds)` — the Haskell answer to the Rust `digits[(i + offset) % len]` indexing trick.
- **Ignoring whitespace at the parser** with `filter isDigit` instead of `trim`, because `String` has no built-in `trim`.

---

## Table of contents
1. [Problem summary](#problem-summary)
2. [Data model](#data-model)
3. [`parseInput`](#parseinput)
4. [`captchaSum` — the shared core](#captchasum--the-shared-core)
5. [`part1` and `part2`](#part1-and-part2)
6. [`solve` — the dispatcher entry point](#solve--the-dispatcher-entry-point)
7. [Tests](#tests)
8. [Benchmarks](#benchmarks)
9. [Key patterns](#key-patterns)
10. [Side-by-side with the Rust baseline](#side-by-side-with-the-rust-baseline)

---

## Problem summary

The input is a single line of digits — for the real input, 2074 digits long. Treat the line as a **circular list**: the digit after the last is the first.

- **Part 1**: sum every digit that equals the **next** digit (offset 1 in the cycle).
- **Part 2**: sum every digit that equals the digit **halfway around** (offset `n/2`). The puzzle promises `n` is even.

Worked examples (from the problem statement):

| Input      | Part 1 | Part 2 |
|------------|-------:|-------:|
| `1122`     | 3      | —      |
| `1111`     | 4      | —      |
| `1234`     | 0      | —      |
| `91212129` | 9      | —      |
| `1212`     | —      | 6      |
| `1221`     | —      | 0      |
| `123425`   | —      | 4      |
| `123123`   | —      | 12     |
| `12131415` | —      | 4      |

Both parts are the **same algorithm with a different stride**, so the solver factors that stride out as a parameter.

---

## Data model

```haskell
type Puzzle = [Int]
```

A `type` synonym, not a `data` declaration: a `Puzzle` is *literally* a list of `Int`, just renamed for documentation. The compiler treats `Puzzle` and `[Int]` as interchangeable.

**Why `[Int]` and not `Vector Int` or `String`**:
- The list is short (≈ 2 000 digits) and we only ever traverse it once per part. `[Int]` is fast enough; reaching for `Data.Vector` here would be ceremony.
- The Rust baseline uses `Vec<u32>` because Rust's idiomatic indexing is O(1). In Haskell we *do not index*; we shift the whole list once. That makes a list the right shape.
- We could keep the input as a `String` and compare characters, but converting to `Int` at the parse step means we get `sum :: [Int] -> Int` for free — no second `digitToInt` call later.

**Rust analogue**: `type Puzzle = [Int]` is `type Puzzle = Vec<i32>;`. A type alias in both languages.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput = map digitToInt . filter isDigit
```

A two-stage **point-free pipeline**, read right-to-left because of `(.)`:

1. `filter isDigit :: String -> String` — keeps only the characters where `isDigit c == True`. A trailing `\n`, accidental whitespace, anything non-digit: gone.
2. `map digitToInt :: String -> [Int]` — `digitToInt :: Char -> Int` turns `'7'` into `7`. `map` applies it to every surviving character.

Composed: `String -> String -> [Int]`, i.e. `String -> [Int]`. Exactly the type signature.

**The functions in play, first appearance in this codebase**:

| Function       | Type                                | What it does                             |
|----------------|-------------------------------------|------------------------------------------|
| `filter`       | `(a -> Bool) -> [a] -> [a]`         | Keeps elements satisfying the predicate. |
| `isDigit`      | `Char -> Bool`                      | True for `'0'`..`'9'`. From `Data.Char`. |
| `map`          | `(a -> b) -> [a] -> [b]`            | Applies `f` to every element.            |
| `digitToInt`   | `Char -> Int`                       | `'7' ↦ 7`. From `Data.Char`.             |
| `(.)`          | `(b -> c) -> (a -> b) -> a -> c`    | Function composition: `f . g $ x = f (g x)`. |

**Why `filter isDigit` instead of `trim`**: `String` is `[Char]`, and `Prelude` has no `trim`. The reference Rust uses `.trim()` to drop the trailing newline, which works because `&str` has it built in. In Haskell, dropping non-digit characters at the parser is one line and slightly more robust — it tolerates a stray space too.

**Rust analogue**:
```rust
input.trim().chars().map(|c| c.to_digit(10).unwrap()).collect::<Vec<u32>>()
```
- `.trim()` ↔ `filter isDigit` (looser in Haskell — drops *all* non-digits, not just leading/trailing whitespace).
- `.chars().map(...)` ↔ `map digitToInt` — `String` *is* `[Char]`, no extra step.
- `.collect()` ↔ nothing — the result is already a list.
- `unwrap()` ↔ nothing — `digitToInt` is total over the digit chars we just filtered for.

---

## `captchaSum` — the shared core

```haskell
captchaSum :: Int -> Puzzle -> Int
captchaSum offset ds =
  sum [ d | (d, e) <- zip ds (rotate offset ds), d == e ]
  where
    rotate :: Int -> [Int] -> [Int]
    rotate k xs = drop k xs ++ take k xs
```

Both parts go through this function. The only difference is the offset.

### The trick: rotate, then zip

The naive version (the Rust one) indexes:

```rust
digits.iter().enumerate()
      .filter(|&(i, &d)| d == digits[(i + offset) % len])
      .map(|(_, &d)| d).sum()
```

For each index `i` it asks "does digit `i` equal digit `(i + offset) mod n`?" That works in Rust because `Vec` indexing is O(1).

In Haskell, indexing into a list with `!!` is O(n) per lookup. Doing it `n` times would be O(n²). The fix: **don't index**. Instead, build a parallel list where position `i` holds the partner of `ds[i]`, then walk the two lists in lockstep.

That parallel list is the **rotation** of `ds` by `offset`: drop the first `offset` elements and stick them on the end.

```
ds            = [9, 1, 2, 1, 2, 1, 2, 9]
rotate 1 ds   = [1, 2, 1, 2, 1, 2, 9, 9]
                                     ^-- the 9 wraps around to be paired with itself
```

Now `zip ds (rotate 1 ds)` gives:

```
[(9,1), (1,2), (2,1), (1,2), (2,1), (1,2), (2,9), (9,9)]
```

Each pair is `(digit, its partner offset steps ahead in the cycle)`. The list comprehension keeps the matching pairs and we `sum` the digit halves.

### The list comprehension

```haskell
[ d | (d, e) <- zip ds (rotate offset ds), d == e ]
```

Reads as: *"for each pair `(d, e)` drawn from `zip ds (rotate offset ds)`, if `d == e`, yield `d`."*

It is exactly equivalent to:

```haskell
map fst (filter (\(d, e) -> d == e) (zip ds (rotate offset ds)))
```

…or to:

```haskell
do (d, e) <- zip ds (rotate offset ds)
   if d == e then [d] else []
```

The list-comprehension version reads most clearly for problems shaped *"pick the elements that satisfy a condition, then transform them."*

**Rust analogue**: list comprehensions don't exist. The closest reading is:

```rust
ds.iter().zip(rotate(offset, &ds).iter())
   .filter(|(d, e)| d == e)
   .map(|(d, _)| *d)
   .sum::<i32>()
```

The Haskell version is shorter and the binding `(d, e)` does double duty (pattern-match *and* introduce both names) where the Rust version needs a closure parameter.

### Why a `where` clause for `rotate`

`rotate` is only used inside `captchaSum`. Putting it at the top level would pollute the module's exports (or force a longer export list). `where` makes it private to its enclosing function — the Haskell idiom for helper-only-here.

```haskell
rotate :: Int -> [Int] -> [Int]
rotate k xs = drop k xs ++ take k xs
```

- `drop k xs` — the suffix of `xs` after dropping the first `k` elements.
- `take k xs` — the first `k` elements.
- `(++) :: [a] -> [a] -> [a]` — list concatenation.

`drop k xs ++ take k xs` is a left-rotation by `k`: `[1,2,3,4,5]` → `[3,4,5,1,2]` for `k = 2`.

**Rust analogue**: `rotate` is essentially `Vec::rotate_left(k)`, except it returns a fresh list rather than mutating in place — Haskell lists are immutable, so concatenation is the only option.

---

## `part1` and `part2`

```haskell
part1 :: Puzzle -> Int
part1 = captchaSum 1

part2 :: Puzzle -> Int
part2 ds = captchaSum (length ds `div` 2) ds
```

Both are one-liners now that `captchaSum` exists.

`part1` is **point-free**: `part1 = captchaSum 1` says "Part 1 *is* `captchaSum` partially applied with offset 1." Because `captchaSum` takes two arguments and we've supplied the first, `captchaSum 1 :: Puzzle -> Int` — exactly the type of `part1`. No need to write `part1 ds = captchaSum 1 ds`.

`part2` cannot be point-free as cleanly because the offset *depends on the input* (`length ds \`div\` 2`). So we name `ds`, compute the offset, and pass both. Backticks around `div` turn the function `div :: Int -> Int -> Int` into an infix operator — `length ds \`div\` 2` reads as `length ds / 2` in any other language.

**Rust analogue**: `part1 = captchaSum 1` is what Rust would write as a closure: `let part1 = |ds| captcha_sum(1, ds);`. Rust does not natively have partial application, so the closure is the closest expression.

---

## `solve` — the dispatcher entry point

```haskell
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
```

Three things to notice.

1. **`solve` parses once.** `let puzzle = parseInput contents` binds the parsed list once and feeds it to both `part1` and `part2`. Even though Haskell's lazy sharing means the result of `parseInput` would be reused regardless, being explicit with `let puzzle = ...` is the habit we want — when we move to bigger puzzles where parsing is slow, this pattern avoids accidental re-parsing.
2. **`solve :: String -> IO ()`** is the **shape every day must follow** in this project, because [app/Main.hs](../../app/Main.hs) stores them in a single dispatch table:
   ```haskell
   solvers :: [(Int, String -> IO ())]
   solvers = [ (0, Day00.solve), (1, Day01.solve), ... ]
   ```
   If any day deviated from this type, the table wouldn't typecheck. The signature is therefore a contract enforced by the dispatcher.
3. **`do` notation for `IO`** lines up sequential effects: `let` for pure bindings, `putStrLn` for the two prints. We touched this in tutorial Day 9; here it is the whole entry point.

Run it via:

```bash
cabal run aoc2018-solve -- 0
```

Output:
```
Day 00 (input: inputs/day00.txt)
  part 1: 1171
  part 2: 1024
```

The `-- 0` syntax is from Day 10: `--` separates cabal's own flags from arguments meant for the executable. The dispatcher reads the `0`, looks it up in the table, and calls `Day00.solve` on the contents of `inputs/day00.txt`.

---

## Tests

The full test file is [Day00Spec.hs](../../test/Day00Spec.hs). It covers four layers, in order:

1. **Parser shape** — three `parseInput` cases (clean digits, trailing newline, embedded whitespace) confirm the parser tolerates real-world input.
2. **Part 1 examples** — the four examples from the puzzle statement (`1122`, `1111`, `1234`, `91212129`).
3. **Part 2 examples** — the five examples (`1212`, `1221`, `123425`, `123123`, `12131415`).
4. **Actual input** — two `readFile`-based tests that lock in `part1 = 1171` and `part2 = 1024`.

The two `readFile` tests use `do` notation:

```haskell
it "part 1 = 1171" $ do
  raw <- readFile "inputs/day00.txt"
  part1 (parseInput raw) `shouldBe` 1171
```

`raw <- readFile ...` is the **monadic bind**: it runs the `IO String` action and gives the resulting `String` the name `raw`. Inside the `do` block, the next line is then a pure assertion. Compare to the `let` form on the same page (`let puzzle = parseInput contents`) — `<-` is for `IO` actions, `let` is for pure bindings. The distinction is the heart of "Haskell separates effectful from pure."

`cabal test` runs every spec file in `test/` automatically (the `hspec-discover` machinery from Day 10). You should see 14 Day 00 tests pass, plus the 50 still-pending stubs for Days 1–25.

---

## Benchmarks

The bench file [`bench/Main.hs`](../../bench/Main.hs) registers four criterion benches per day. For Day 0, on a Windows 11 / GHC 9.6.7 / `-O2` build:

| Bench               | Mean       | What it times                                                       |
|---------------------|-----------:|---------------------------------------------------------------------|
| `day00/parseInput`  |   17.5 µs  | Just the parser, on the raw 2074-byte `String`.                     |
| `day00/part1`       |   11.2 µs  | Just `part1`, on the **already-parsed** `[Int]` (`env`-cached).     |
| `day00/part2`       |   14.9 µs  | Just `part2`, same.                                                 |
| `day00/combined`    |   80.5 µs  | `\r -> let p = parseInput r in (part1 p, part2 p)` from raw text.   |

**The headline figure is Total = Parse + Part 1 + Part 2 = 43.6 µs** — the steady-state CPU cost of one solve. The summary table at [`summary_2018.md`](summary_2018.md) reports it that way, with **Parse**, **Part 1**, **Part 2**, and **Total** as separate columns so the bottleneck is visible at a glance.

**Why not just use `combined` as Total?** `combined` reports ~80 µs — almost twice the sum of the parts. The gap is **per-iteration garbage-collection and allocation overhead**, not real work. The cached `part1` / `part2` benches reuse the same parsed `[Int]` across iterations, so allocation is amortised across the whole criterion run. The `combined` bench builds a fresh 2074-element `[Int]` list every iteration, then walks it twice and discards it — that GC churn doubles the per-iteration cost in microbenchmark conditions. Real programs do not call `solve` 100,000 times in a tight loop; they call it once. So the sum-of-parts figure is the honest steady-state number; `combined` is kept around as a sanity check on `parseInput` (parse cost shows up in `combined - part1 - part2`) and as a reminder that allocation matters at scale.

**Why ~10× slower than the Rust baseline (4.26 µs)**: not a bad result. The Rust version stores digits in a `Vec<u32>`, which is one contiguous chunk of stack-allocated `u32` values; iteration and indexing are tight CPU loops with perfect cache behaviour. The Haskell version uses `[Int]`, a linked list of *boxed* `Int`s — every cons cell is a heap pointer, every `Int` is a heap pointer to a tag-and-payload, and traversal hops around memory. For ~2 000 digits the constant factor is small enough that 43.6 µs is fine; for 2 000 000 digits it would not be, and the fix would be `Data.Vector.Unboxed`. Day 0 is too small to bother — the result demonstrates "lists are slower than vectors but the gap is constant-factor, not algorithmic." Optimising here would teach the wrong lesson.

**Reproducing**:

```bash
cabal bench -- --match prefix day00     # just Day 0
cabal bench -- --output bench.html      # full HTML report
cabal bench -- --time-limit 10          # longer warm-up if numbers feel jittery
```

---

## Key patterns

Three takeaways that generalise beyond this puzzle.

1. **When you would index a list, rotate it instead.** `zip xs (rotate k xs)` is a pure-functional, O(n) substitute for `for i in 0..n: compare xs[i] with xs[(i+k) % n]`. The same pattern shows up in sliding-window problems (`zip xs (drop 1 xs)` for adjacent pairs) and is one of the most reused tricks in AoC Haskell.
2. **Factor the *parameter*, not the parts.** Part 2 was not a copy-paste of Part 1 with edits — it was Part 1's algorithm with a different argument. Spotting that early gives you `captchaSum offset` and reduces both parts to one-liners.
3. **Parse defensively at the boundary.** `filter isDigit` quietly drops trailing newlines and stray whitespace. The cost is one extra pass over the string; the benefit is that nothing downstream needs to think about line endings.

---

## Side-by-side with the Rust baseline

The Rust solution lives at [reference/rust_baseline_2017/src/solver/day01.rs](../../reference/rust_baseline_2017/src/solver/day01.rs). Lined up:

| Concept                       | Rust                                                                 | Haskell                                                              |
|-------------------------------|----------------------------------------------------------------------|----------------------------------------------------------------------|
| Strip non-digits              | `input.trim()`                                                       | `filter isDigit`                                                     |
| Char → digit                  | `c.to_digit(10).unwrap()`                                            | `digitToInt c`                                                       |
| Iterate with index            | `iter().enumerate()`                                                 | (avoided — we shift the whole list)                                  |
| Compare with offset partner   | `digits[(i + off) % len]`                                            | element of `rotate off ds` paired by `zip`                           |
| Filter then sum               | `.filter(...).map(...).sum()`                                        | `sum [ d | (d,e) <- ..., d == e ]` (list comprehension)              |
| Halve length                  | `digits.len() / 2`                                                   | `length ds \`div\` 2`                                                |
| Run both parts                | `pub fn solve -> (u32, u32)`                                         | `solve :: String -> IO ()` (prints both, dispatcher contract)        |
| Test framework                | `#[cfg(test)] mod tests { #[test] fn ... }`                          | `hspec`: `describe / it / shouldBe`                                  |

The shapes line up very closely. The two real differences:

- **No indexed access.** Haskell's `[a]` makes us think differently about "the element at position `i + offset`" — we shift the list once and iterate linearly. The result is arguably *more* idiomatic and reads as one expression.
- **Different `solve` signature.** The Rust baseline's `solve` returns `(u32, u32)` — the dispatcher prints. In this Haskell project the dispatcher is dumber: it hands every day raw `String` and expects each day's `solve` to print its own answers. That keeps `app/Main.hs` to one table; it does mean each day has to do its own `putStrLn`.

---

**Navigation**: [Problem statement](day00.md) | [Summary table](summary_2018.md) | [Day 1 →](day01_function_guide.md)
