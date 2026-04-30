# Day 11 — Putting it together: a real AoC puzzle, end-to-end

**Goal**: solve a small Advent of Code puzzle inside the cabal layout from Day 10. By the end you will have parsed a real input file, written Part 1 and Part 2 as type-signed functions, run them through the project's `solve` dispatcher, and have a passing `hspec` suite around the lot. This is the dry-run for AoC 2018 itself — every 2018 day will follow the same pattern.

**The puzzle**: AoC 2017 Day 1, *"Inverse Captcha"*. A circular list of digits; sum the digits that match a partner at a fixed offset. Part 1 uses offset 1 (the next digit); Part 2 uses offset `n / 2` (the digit halfway around). Small enough to solve in one sitting, real enough to have two parts and a non-trivial input file. The full problem statement and answers are at [Problem_Statements/days/day00.md](../../Problem_Statements/days/day00.md).

**Why this lives in the AoC 2018 cabal project**: rather than scaffolding a `tutorial-day11/` mini-project, Day 11 *is* the AoC 2018 project's `Day00` slot — the warm-up before December 1st. That gives you the real layout you will use for the next 25 days, and the same `cabal run aoc2018-solve -- 0` you will use for every subsequent day. **The artefacts for this tutorial day live in the repository root**, not in this folder:

- Source: [`src/Day00.hs`](../../src/Day00.hs)
- Tests: [`test/Day00Spec.hs`](../../test/Day00Spec.hs)
- Input: [`inputs/day00.txt`](../../inputs/day00.txt)
- Cabal file: [`aoc2018.cabal`](../../aoc2018.cabal)
- Dispatcher: [`app/Main.hs`](../../app/Main.hs)

This README is the teaching companion. The annotated walk-through of the solution itself — function by function, line by line — is at [`Problem_Statements/days/day00_function_guide.md`](../../Problem_Statements/days/day00_function_guide.md). Read this first, then read that.

---

## 1. The shape of every day in this project

The AoC 2018 cabal project carries 26 day-modules, `Day00` through `Day25`, all behind a single dispatcher in [`app/Main.hs`](../../app/Main.hs). Each module is the same shape:

```haskell
module DayNN
  ( Puzzle
  , parseInput
  , part1
  , part2
  , solve
  ) where

type Puzzle = ...

parseInput :: String -> Puzzle
part1      :: Puzzle -> Int
part2      :: Puzzle -> Int
solve      :: String -> IO ()
```

Five names, every day. The dispatcher only uses `solve`; `parseInput`, `part1`, and `part2` are exported so the test suite can exercise them without going through `IO`. `Puzzle` is exported for the same reason.

**Why this shape**:

- **`parseInput :: String -> Puzzle`** keeps parsing pure. No `IO`, no file paths, no surprises — given the same string, you get the same parsed value. The test suite can call it directly with a `String` literal.
- **`part1`, `part2 :: Puzzle -> Int`** keep the algorithms pure too. Each takes already-parsed input. That means the test suite can write `part1 (parseInput "1122") \`shouldBe\` 3` without touching disk.
- **`solve :: String -> IO ()`** is the *one* place in each day where `IO` happens. It calls `parseInput`, then `part1` and `part2`, then `putStrLn`s the answers. The dispatcher hands it the file contents; everything downstream is pure.
- **`type Puzzle = ...`** documents the shape parsing produces. For Day 0 it is `[Int]`. Later days will use records, maps, or grids — but the contract `parseInput :: String -> Puzzle` stays the same.

**Rust analogue**: the AoC 2017 Rust baseline does the same thing in a slightly tighter package — `pub fn solve(input: &str) -> (u32, u32)` is one function returning both answers. In Haskell we split that across `part1`/`part2` so the tests can exercise them independently without computing both.

---

## 2. The dispatcher — `app/Main.hs`

The executable is a 26-entry table that maps a day number to that day's `solve`:

```haskell
solvers :: [(Int, String -> IO ())]
solvers =
  [ ( 0, Day00.solve), ( 1, Day01.solve), ( 2, Day02.solve), ...
  ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    [arg] -> case reads arg of
      [(n, "")] -> runDay n
      _         -> usage
    _ -> usage

runDay :: Int -> IO ()
runDay n = case lookup n solvers of
  Just solve -> do
    let path = "inputs/day" ++ pad n ++ ".txt"
    contents <- readFile path
    solve contents
  Nothing -> ...
```

Two things to call out.

**`lookup :: Eq k => k -> [(k, v)] -> Maybe v`** is the standard "find by key" function for association lists. It returns `Just solver` or `Nothing`. Pattern matching on the result is how we handle "valid day" vs "out-of-range day" without throwing exceptions.

**`reads :: Read a => String -> [(a, String)]`** is a more disciplined cousin of `read`. Instead of panicking on garbage input, it returns a list of possible parses with the leftover string. We only accept the case where the parse consumed everything (`[(n, "")]`); anything else falls through to `usage`. **Rust analogue**: `reads` is `str::parse::<i32>()` returning `Result<i32, _>`, except Haskell's version is shaped as a list to support ambiguous parses (a feature you'll never use in this project).

The single-table dispatcher is a small piece of code but it pays off: adding a new day's solver costs one line in this table and one line in [`aoc2018.cabal`](../../aoc2018.cabal)'s `exposed-modules:`. The day's `solve :: String -> IO ()` shape is the contract that lets that table typecheck.

---

## 3. Walking through the Day 0 solution

Open [`src/Day00.hs`](../../src/Day00.hs) and read it top-to-bottom alongside this section. The function guide at [Problem_Statements/days/day00_function_guide.md](../../Problem_Statements/days/day00_function_guide.md) is more thorough; this is the speed run.

**`parseInput`**: `map digitToInt . filter isDigit`. Drop non-digit characters (the trailing newline, in particular), then convert each remaining character to its `Int` value. A two-stage pipeline composed with `(.)`. Day 1's `'+' / '-'` parser was a hand-written function; this is what the same idea looks like at one operator's worth of complexity.

**`captchaSum offset ds`**: the algorithmic heart. Both parts share it; only the offset differs. The trick is that we cannot use `ds !! (i + offset)` style indexing — `(!!)` on a list is O(n), so doing it n times is O(n²). Instead, we **rotate** the list once and zip:

```haskell
captchaSum offset ds =
  sum [ d | (d, e) <- zip ds (rotate offset ds), d == e ]
  where
    rotate k xs = drop k xs ++ take k xs
```

`rotate offset ds` builds the partner list — at index `i`, it holds the element that was originally at index `(i + offset) mod n`. `zip ds that` pairs them. The list comprehension keeps the matches and `sum` adds them up. Whole thing is O(n).

**`part1` and `part2`**: one-liners that pick the right offset.

```haskell
part1 :: Puzzle -> Int
part1 = captchaSum 1

part2 :: Puzzle -> Int
part2 ds = captchaSum (length ds `div` 2) ds
```

`part1` is **point-free** — `captchaSum 1` is `captchaSum` partially applied with offset 1, which is already a `Puzzle -> Int`. Day 6's folds had the same flavour: when the function is just "this other function with one argument fixed," writing it in the form `f = g x` is the cleanest expression.

**`solve`**: parse once, print twice.

```haskell
solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
```

`do` notation with a single `let` binding for the parsed input, and two `putStrLn`s for the report. Nothing fancier than Day 9's IO. The `let puzzle = ...` line makes the parse-once pattern visible — even if Haskell's sharing means the parse would only run once anyway, being explicit models the habit.

---

## 4. The test file — `test/Day00Spec.hs`

Open [`test/Day00Spec.hs`](../../test/Day00Spec.hs). The structure mirrors the Day 10 `hspec` template you already know:

```haskell
module Day00Spec (spec) where

import Test.Hspec
import Day00 (parseInput, part1, part2)

spec :: Spec
spec = describe "Day 00 (AoC 2017 Day 1 - Inverse Captcha)" $ do

  describe "parseInput" $ do
    it "turns a digit string into a list of Ints" $
      parseInput "1122" `shouldBe` [1, 1, 2, 2]
    ...

  describe "part1 examples from the puzzle" $ do
    it "1122 -> 3" $ part1 (parseInput "1122") `shouldBe` 3
    ...

  describe "actual puzzle input (inputs/day00.txt)" $ do
    it "part 1 = 1171" $ do
      raw <- readFile "inputs/day00.txt"
      part1 (parseInput raw) `shouldBe` 1171
    ...
```

The four layers, in order:

1. **Parser**: a few `parseInput` tests confirming we strip newlines and stray whitespace.
2. **Part 1 examples**: the four cases from the problem statement (`1122`→3, `1111`→4, `1234`→0, `91212129`→9).
3. **Part 2 examples**: the five cases (`1212`→6, `1221`→0, `123425`→4, `123123`→12, `12131415`→4).
4. **Actual input**: two `readFile`-based tests that pin `part1 = 1171` and `part2 = 1024`.

The shape *parser → part 1 examples → part 2 examples → actual answers* is the template every AoC day will use. Cover the small public examples first (they catch off-by-one bugs in the algorithm), then lock the real answer in (catches regressions when you refactor later).

The `readFile` tests are the only ones that go through `IO` — and notice the `do` notation:

```haskell
it "part 1 = 1171" $ do
  raw <- readFile "inputs/day00.txt"
  part1 (parseInput raw) `shouldBe` 1171
```

`raw <- readFile ...` is the **monadic bind**: run the `IO String` action, give the resulting `String` the name `raw`, then continue. Compare to `let puzzle = parseInput contents` in `solve` — `<-` is for actions, `let` is for pure bindings. The two often appear in the same `do` block.

---

## 5. The four cabal commands, in this project

Same four as Day 10, just with the project's actual names:

```bash
cabal build                            # compile the library + dispatcher
cabal run aoc2018-solve -- 0           # run Day 0 (reads inputs/day00.txt)
cabal test                             # run the entire hspec suite
cabal repl aoc2018                     # GHCi with the library loaded
```

Things worth knowing:

- **`cabal run aoc2018-solve -- 0`**: the `--` separates cabal flags from the dispatcher's arguments. Without it, cabal would try to parse `0` as one of *its* flags. The `0` is then `args !! 0` inside `main`.
- **`cabal test` runs the entire suite, not just Day 0**. You will see the 14 Day 0 tests pass plus 50 pending stubs for Days 1–25. The pending stubs (`pendingWith ...`) are placeholders so the test suite has every day's hooks already wired up — replace them as you solve each day.
- **`cabal repl aoc2018`** is where to go when something doesn't typecheck and you want to poke at it. `:t parseInput`, `:t part1`, `parseInput "1234"` — all work with the library already loaded.

---

## 6. Walking through the workflow you'll use for AoC 2018

The pattern this Day 11 establishes is the one to repeat for every actual 2018 puzzle. For AoC 2018 Day 1:

1. **Read the puzzle** at [Problem_Statements/days/day01.md](../../Problem_Statements/days/day01.md) (links to all 25 days are in [Problem_Statements/days/](../../Problem_Statements/days/)).
2. **Drop your input** into `inputs/day01.txt`.
3. **Open `src/Day01.hs`** — it currently has the placeholder skeleton. Replace `parseInput`, `part1`, `part2`, and the `Puzzle` type with the real solution. The `solve` function usually does not need to change.
4. **Open `test/Day01Spec.hs`** — replace the two `pendingWith` stubs with real `it ... shouldBe ...` tests for the puzzle examples plus the actual answers.
5. **`cabal test`** — confirm the new tests pass and nothing else broke.
6. **`cabal run aoc2018-solve -- 1`** — confirm the dispatcher prints the right answers.
7. **Add a function guide** at `Problem_Statements/days/day01_function_guide.md` (use [`day00_function_guide.md`](../../Problem_Statements/days/day00_function_guide.md) as the template).
8. **Update [`Problem_Statements/days/summary_2018.md`](../../Problem_Statements/days/summary_2018.md)** with the answers and the new concepts introduced.
9. **Commit**. One commit per day is a good habit; the repo can grow tidily and `git log` becomes a reading list.

That is the entire loop. Day 11 is where it crystallises into a process; the next 25 days are repetition with new puzzles.

---

## 7. Try it

Small exercises to make this material stick. Run them in the repo root.

1. **Run the suite.** `cabal test`. Confirm 14 passing tests for Day 0 and 50 pending stubs for Days 1–25. Then `cabal run aoc2018-solve -- 0` and confirm `part 1: 1171`, `part 2: 1024`.
2. **Poke at it in `cabal repl aoc2018`.**
   - `:t parseInput`, `:t part1`, `:t captchaSum`, `:t (.)` — read the types out loud.
   - `parseInput "91212129"` — what type is the result?
   - `captchaSum 1 [1,2,1,2]` — predict, then check.
   - `:t map digitToInt . filter isDigit` — confirm the composed type matches `parseInput`'s.
3. **Break the dispatcher in a controlled way.** In `app/Main.hs`, comment out the `Day00.solve` line in `solvers`. `cabal build` — read the error. Put it back. The error tells you exactly where the table breaks.
4. **Try a third entry point.** Add a function `solveBoth :: String -> (Int, Int)` to `Day00`. Export it. In `cabal repl`, evaluate `solveBoth =<< readFile "inputs/day00.txt"` — predict what that types as, then check. (Hint: `readFile :: FilePath -> IO String`, `solveBoth :: String -> (Int, Int)`, `(=<<) :: Monad m => (a -> m b) -> m a -> m b`. The result is `IO (Int, Int)`.)
5. **Stress-test the parser.** Run `parseInput ""`, `parseInput "abc"`, `parseInput "12 34 56"` in `cabal repl`. What does each return? Why did `filter isDigit` make the first two safe?
6. **Refactor without changing behaviour.** Replace the list comprehension in `captchaSum` with the equivalent `map fst (filter (\(d,e) -> d == e) (zip ds (rotate offset ds)))`. Run `cabal test`. Confirm everything still passes. Decide which version reads more clearly.

---

## 8. What you should remember

- **Every day is `parseInput / part1 / part2 / solve`**, with a `Puzzle` type alias. The dispatcher in `app/Main.hs` only knows about `solve`; the test suite exercises the other three.
- **`solve` parses once, then prints both parts.** The dispatcher hands it raw `String`; everything downstream is pure.
- **`parseInput :: String -> Puzzle` is pure.** No `IO`, no file paths. That keeps it testable from a `String` literal.
- **Test layers in order: parser, Part 1 examples, Part 2 examples, actual input.** Examples catch algorithm bugs; `readFile`-backed tests pin the real answers.
- **Adding a day costs three edits**: replace the placeholder in `src/DayNN.hs`, replace the `pendingWith` stubs in `test/DayNNSpec.hs`, fill in the row in [summary_2018.md](../../Problem_Statements/days/summary_2018.md). The cabal file and dispatcher already list every day.
- **Use `cabal repl aoc2018` aggressively while solving.** GHCi is the shortest path from a typed expression to a known result; never debug by `putStrLn` when `:t` and `:i` will do.
- **The `zip ds (rotate k ds)` trick** is the Haskell substitute for indexed comparisons — keep it in mind whenever a problem asks "compare element `i` to element `i + k`" in a circular list. Sliding-window problems use the same shape with `zip xs (drop 1 xs)`.

---

**You finished the tutorial.** From here on, every "day" is the AoC 2018 puzzle of the same number. The Day 0 warm-up sat in the same project alongside Days 1–25 because it *is* one of them — the day you build muscle memory before the calendar starts.

**Next**: open [Problem_Statements/days/day01.md](../../Problem_Statements/days/day01.md) when you are ready to start AoC 2018 proper.

---

**Navigation**: [← Day 10](../day10/README.md) | [Tutorial index](../README.md) | [AoC 2018 summary →](../../Problem_Statements/days/summary_2018.md)
