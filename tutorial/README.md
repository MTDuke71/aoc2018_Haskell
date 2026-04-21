# Haskell Tutorial — 11-Day Pre-AoC Ramp

An 11-day ramp from *"I just installed GHC"* to *"I can read and write the kind of Haskell that AoC needs."* Each day is one folder: a `README.md` that teaches, and `src/` files you can run.

## Plan

| Day | Topic | What you can do by the end |
|----:|-------|----------------------------|
| 1 | Install + Hello World | Run Haskell three different ways (GHCi, `runghc`, compiled). Read your first type signature. |
| 2 | Values, types, functions | Write pure functions with explicit type signatures. Understand `Int`, `Integer`, `Double`, `Bool`, `Char`, `String`. |
| 3 | Lists and the list toolkit | `map`, `filter`, `sum`, `length`, `lines`, `words`, list ranges, list comprehensions. |
| 4 | Pattern matching, guards, `where` and `let` | Write functions that dispatch on structure instead of `if/else` chains. |
| 5 | Tuples, `Maybe`, and `Either` | Return "maybe a value" and "a value or an error" without exceptions. The Haskell version of Rust's `Option` and `Result`. |
| 6 | Folds: `foldr`, `foldl`, `foldl'` | Reduce a list to a value. Understand why `foldl'` is the default and why `foldl` is almost always a bug. |
| 7 | `data` types and records | Model problem state with your own types. Field accessors, `deriving (Show, Eq, Ord)`. |
| 8 | `Data.Map.Strict` and `Data.Set` | Keyed lookup and set membership. The workhorse containers for AoC. |
| 9 | `IO`, `do` notation, `readFile` | Read puzzle input from disk and print the answer. The line between pure and effectful code. |
| 10 | Modules, `cabal` project layout, tests with `hspec` | Organise code into modules, build a project, run tests. |
| 11 | Putting it together — a mini AoC-style puzzle | Solve a small puzzle end-to-end: parse input, solve Part 1 and Part 2, test against the example. |

Each day stays in its own folder so you can come back to it later without hunting. Everything is reference material — it's meant to live here permanently.

## How to use this tutorial

- Read the day's `README.md` top-to-bottom first.
- Open the files in `src/` in your editor and run them as the README instructs.
- Use `ghci` to poke at individual functions — it is the single fastest way to learn Haskell.
- Each day ends with a short "Try it" section. Do them. They are small on purpose.

## Rust analogues

Where a Haskell concept has a close Rust equivalent, the README calls it out as **Rust analogue:** …. These are anchors for your existing mental model, not promises that the languages behave identically.
