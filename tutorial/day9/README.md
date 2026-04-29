# Day 9 — `IO`, `do` notation, and `readFile`

**Goal**: cross the line between pure code and the outside world. By the end you will know what `IO a` actually is, why `do` blocks exist, the difference between `<-` and `let`, and how to read a puzzle input file from disk and feed it into pure code. The shape of every AoC solution from here on is a thin IO shell wrapping a pile of pure functions — Day 9 builds that shell.

**Source files**:
- [src/IOBasics.hs](src/IOBasics.hs) — what `IO a` means, `do` blocks, `<-` vs `let`, `pure`/`return`, `mapM_`/`forM_`/`when`.
- [src/ReadInput.hs](src/ReadInput.hs) — `readFile`, `lines`, the IO/pure split that every AoC day will use.
- [sample.txt](sample.txt) — ten signed integers, one per line, used by `ReadInput`.

---

## 1. Pure vs effectful — the wall everything has been hiding behind

Every example up to Day 8 fit one shape:

```haskell
f :: SomeInputType -> SomeOutputType
```

You called `f`, you got a value. There was nothing to read, nothing to print, nothing on disk. That is what "pure" means: a function from input to output, no side effects, no surprises — and it is the reason Haskell can be so aggressive about laziness, sharing, and parallelism. Pure code is mathematics; you can substitute any expression by its definition without changing the meaning of the program.

But puzzles live on disk. Your AoC solver needs to:

- read `input.txt`,
- parse and solve it,
- print the answer.

Reading a file *is* a side effect. The file system can change between runs; the call returns different content depending on when you make it. That is exactly what purity disallows. So Haskell does not pretend `readFile` is pure — it gives `readFile` a special type that makes its effectfulness visible at compile time:

```haskell
readFile :: FilePath -> IO String
```

The `IO` in that type is the wall. Day 9 is about how to use it without falling over.

**Rust analogue**: this is closer to `async fn read_to_string(...) -> io::Result<String>` than you might expect. The `IO` wrapper marks a value as "this is a recipe for a real-world action," the way `async` marks a function as "this returns a future." In both cases the wrapper does not run anything by itself — something else (the Tokio runtime / the Haskell `main`) executes it.

---

## 2. What `IO a` actually is

A value of type `IO a` is a **recipe** that, when the runtime executes it, will produce a value of type `a` and may read or write the outside world along the way. Three things follow from that.

- **`IO a` is a value, not a statement.** You can store it in a variable, pass it to a function, put it in a list, build it from smaller pieces — nothing happens until something *runs* it.
- **The runtime runs exactly one `IO` value: `main`.** Every effect your program ever has must be reachable from `main :: IO ()`. Code defined elsewhere that has `IO ()` in its type but is never called from `main` will not execute, no matter what it claims to do.
- **The wrapper is sticky.** Once a function returns `IO a`, every caller that wants the `a` inside has to also live inside `IO`. Effectful code "infects" its callers. That sounds annoying — it is actually the feature: the compiler makes it impossible to accidentally do IO from somewhere you thought was pure.

A few `IO` values you will meet today:

| Value | Type | What its recipe does |
|---|---|---|
| `putStrLn s` | `IO ()` | Print `s` followed by a newline. No useful result. |
| `getLine` | `IO String` | Read a line from stdin, return it. |
| `readFile path` | `IO String` | Read the whole file at `path`, return its contents. |
| `pure x` | `IO a` | Do nothing; produce `x`. (Used to "lift" a pure value.) |

The `()` (pronounced "unit") is the type with exactly one value, also written `()`. It means "no useful result" — Haskell's version of `void`. `putStrLn` returns `IO ()` because the only thing it does is print; there is no value for the caller to use.

### Reading an `IO` type signature

```haskell
readFile :: FilePath -> IO String
--          ^^^^^^^^    ^^ ^^^^^^
--          input       |  the result you get out of running it
--                      this action is IO-flavoured
```

The pattern is always `IO X`, where `X` is the type of the result the action produces when run.

---

## 3. `do` notation — sequencing actions in order

Outside of `IO`, the order of evaluation rarely matters: pure expressions can be reduced in any order without changing the answer. Inside `IO`, order is everything: print *then* ask, not the other way around.

A `do` block lets you write a sequence of actions one per line, and the runtime executes them top-to-bottom:

```haskell
greetWorld :: IO ()
greetWorld = do
  putStrLn "Hello,"
  putStrLn "World!"
  putStrLn "(three lines, in this exact order)"
```

Two rules govern a `do` block:

1. **All actions in a block share the same monad.** Here that monad is `IO`. You cannot mix `IO` and `Maybe` actions in one block — the compiler does not know what "do them in order" means across types. You will see `Maybe`-flavoured `do` blocks much later; they exist, but each block is one monad.
2. **The block's type is the type of its last action.** `greetWorld` ends in `putStrLn "..."`, whose type is `IO ()`; therefore `greetWorld :: IO ()`. If the last line were `pure 42 :: IO Int`, the block would have type `IO Int`.

**Rust analogue**: a `do` block is the IO equivalent of a Rust `async {}` block — you write the steps in order, and the runtime walks them. The `<-` you are about to meet is the rough cousin of `.await`.

---

## 4. The `<-` arrow vs `=` and `let`

`getLine :: IO String` is an action whose *result* is a `String`. To use that `String` in the rest of the block, you need to bind it to a name:

```haskell
askName :: IO ()
askName = do
  putStrLn "What is your name?"
  name <- getLine
  putStrLn ("Hello, " ++ name ++ "!")
```

Read `name <- getLine` as: "run the action `getLine`, and call the resulting `String` `name`." From here on `name` is a plain pure `String`; the `IO` wrapper has been peeled off **inside** this block.

There are three different binding shapes and they are easy to confuse:

| Binding | Where | Means | Example |
|---|---|---|---|
| `name <- action` | inside `do` | run the action, name its result | `name <- getLine` |
| `let name = expr` | inside `do` | name a pure expression (no `in`) | `let n = read s :: Int` |
| `name = expr` | top level | define a top-level value | `pi = 3.14159` |

`<-` is **only** legal inside a `do` block. `let` inside `do` does not have an `in` clause — the rest of the block is its body. And the top-level `=` you have used since Day 1 has nothing to do with either; it just defines a name.

A common confusion to head off:

```haskell
name <- getLine          -- 'name' is the String inside the IO action
let copy = name          -- pure binding: 'copy' is also a String

let copy = getLine       -- WRONG mental model: 'copy' here is the
                         -- *recipe* getLine itself, not the String
                         -- it would produce when run.
```

`let copy = getLine` is perfectly legal Haskell — but `copy` has type `IO String`, not `String`. The recipe got named, not its result.

---

## 5. `pure` / `return` — promote a pure value into IO

Sometimes the last line of a `do` block needs to be a value, not an action. Use `pure` to wrap it:

```haskell
doubleEcho :: IO Int
doubleEcho = do
  putStrLn "Type a number:"
  s <- getLine
  let n = read s :: Int
  putStrLn ("doubled: " ++ show (2 * n))
  pure (2 * n)
```

The block's type is the type of its last action: `pure (2 * n) :: IO Int`, so `doubleEcho :: IO Int`.

Two important warnings about `return` in Haskell.

- **`return` is NOT the C/Rust `return`.** It does not jump out of a function. `return x` in Haskell is identical to `pure x` for `IO`: it just lifts `x` into the monad.
- **Modern style prefers `pure`.** If you read older Haskell and see `return`, mentally substitute `pure`. They are interchangeable for `IO`, and `pure` makes the intent obvious.

---

## 6. Reading a file: `readFile` and the AoC pattern

Here is the heart of Day 9. Almost every AoC solution in this repo will look like this:

```haskell
main :: IO ()
main = do
  contents <- readFile "input.txt"      -- IO   — get the bytes
  let answer = solve (parse contents)   -- pure — do the work
  print answer                          -- IO   — show the result
```

Three lines of IO; everything else is pure. The pure layer is testable in GHCi with a hand-written `String` — no fixtures, no temp files, no mocking. The IO layer is so short there is nothing to test.

A concrete example from `ReadInput.hs`:

```haskell
parseChange :: String -> Int
parseChange ('+' : rest) = read rest
parseChange s            = read s

parseInput :: String -> [Int]
parseInput = map parseChange . lines

part1 :: [Int] -> Int
part1 = foldl' (+) 0

main :: IO ()
main = do
  contents <- readFile "tutorial/day9/sample.txt"
  let changes = parseInput contents
  putStrLn ("part 1 sum = " ++ show (part1 changes))
```

`parseChange`, `parseInput`, `part1` are all pure. None of them touch `IO`. You can call them at the GHCi prompt:

```
ghci> parseInput "+1\n-2\n+3"
[1,-2,3]
ghci> part1 [1, -2, 3, 1, -5, 8, 4, -3, 7, -2]
14
```

That is the testability win — you do not need a file to exercise the logic.

### `lines` and `words`, briefly

Two Prelude functions you will use every single day:

```haskell
lines :: String -> [String]    -- split on '\n', drop a trailing newline
words :: String -> [String]    -- split on any whitespace
```

`lines "+1\n-2\n+3\n"` is `["+1", "-2", "+3"]`. `words "  hello  world "` is `["hello", "world"]`. Either is enough to chop a typical AoC input into pieces; the parsing happens after.

### Relative paths bite

`readFile "tutorial/day9/sample.txt"` resolves the path against the *current working directory*, not the directory of the source file. Run from the repository root:

```bash
runghc tutorial/day9/src/ReadInput.hs
```

If you `cd tutorial/day9` first, the literal path no longer matches; either change it to `"sample.txt"` or always run from the same directory. This is the one Day 9 gotcha worth memorising — relative paths catch every newcomer once.

### A note on laziness in `readFile`

The `base` library's `readFile` is *lazy*: the file handle is closed only when the returned string is fully consumed. For AoC inputs (a few KB to a few MB) this is harmless. For larger files prefer `Data.Text.IO.readFile` from the `text` package, which is strict and uses bytes-not-chars. We will reach for that in Day 10 once a project is set up; for now `String` is fine.

---

## 7. `mapM_`, `forM_`, `when` — the effectful list helpers

A pure `map` returns `[b]`. The IO equivalent is `mapM_`:

```haskell
mapM_ :: (a -> IO ()) -> [a] -> IO ()
forM_ :: [a] -> (a -> IO ()) -> IO ()
```

Both walk a list, run an `IO ()` action for each element, and discard the results. They differ only in argument order. Reach for `mapM_` when the list is the more interesting argument; reach for `forM_` when the action is a multi-line `do` block:

```haskell
printAll :: [String] -> IO ()
printAll xs = mapM_ putStrLn xs

countDown :: IO ()
countDown = forM_ [3, 2, 1 :: Int] $ \n -> do
  putStrLn ("T-minus " ++ show n)
```

`replicateM_ :: Int -> IO a -> IO ()` is the count-based variant: "do this action `n` times":

```haskell
knockKnock :: IO ()
knockKnock = replicateM_ 3 (putStrLn "knock")
```

The trailing underscore on `mapM_`, `forM_`, `replicateM_` is the convention for "discards the results." Without the underscore you get `mapM :: (a -> IO b) -> [a] -> IO [b]`, which is the right shape if you actually want to collect each action's result — say, reading `n` lines into a `[String]`.

For conditional effects use `when` and `unless`:

```haskell
when   :: Bool -> IO () -> IO ()
unless :: Bool -> IO () -> IO ()
```

These are the named replacement for `if cond then action else pure ()`:

```haskell
shoutBack :: String -> IO ()
shoutBack s = do
  when (isShout s) $
    putStrLn "(you are still yelling)"
  putStrLn ("you said: " ++ s)
```

Without `when`, that block reads as `if isShout s then putStrLn "..." else pure ()` — correct, but noisier.

---

## 8. Walkthrough of the source files

`IOBasics.hs` is laid out as seven numbered sections that mirror this README:

1. What `IO a` means — types of `putStrLn`, `getLine`, `readFile`, `pure`.
2. `do` notation — `greetWorld` as the simplest sequenced block.
3. The `<-` arrow — `askName` reads a line, `greetTwice` shows `let` inside `do`.
4. `pure` / `return` — `doubleEcho` lifts a pure `Int` into `IO Int`.
5. Pure vs effectful — `isShout` is pure, `reactToInput` is the IO wrapper.
6. Effectful list helpers — `printAll`, `countDown`, `knockKnock`.
7. `when` / `unless` — `shoutBack`.

`ReadInput.hs` follows the same shape but oriented around a single AoC-style end-to-end:

1. `readFile` and `writeFile` types and the laziness note.
2. `parseChange` — pure, one line at a time.
3. `parseInput` — pure, the whole file.
4. `part1` — pure, the running sum.
5. `part2` — pure, first repeated running total (set-based, from Day 8).
6. `main` — the thin IO shell.

Run them like every previous day. `IOBasics.hs` is non-interactive in `main`, so `runghc` will execute end-to-end:

```bash
cd c:/Users/m_lad/Repos/aoc2018_Haskell
runghc tutorial/day9/src/IOBasics.hs
```

```bash
runghc tutorial/day9/src/ReadInput.hs
```

The interactive examples (`askName`, `reactToInput`, `shoutBack`) are best driven from GHCi:

```bash
ghci tutorial/day9/src/IOBasics.hs
```

```
ghci> askName
What is your name?
Matt
Hello, Matt!
ghci> reactToInput
Say something:
HEY THERE
WHY ARE YOU YELLING
ghci> :t getLine
getLine :: IO String
```

---

## 9. Try it

Small exercises. Do them in GHCi with the relevant file loaded.

1. In GHCi, evaluate `:t putStrLn`, `:t getLine`, `:t readFile`, `:t pure`. Read each one out loud as "an action that takes …, runs effects, and returns …". This costs nothing and pays off every time you stare at a confusing IO type.
2. Write `echoTwice :: IO ()` that reads one line with `getLine` and prints it back twice. Use `<-` to bind the result.
3. Modify `askName` so it loops three times, asking for three different names. Use `replicateM_ 3` or `forM_ [1..3]`.
4. In `ReadInput.hs`, change the relative path in `main` to `"does-not-exist.txt"` and run it. Read the runtime error carefully — that is what every relative-path bug looks like.
5. Add a `part1Compare` action to `ReadInput.hs`'s `main` that reads the file, computes `part1`, and uses `when (answer < 0)` to print a warning if the running sum is negative. Wire it into `main`.
6. In GHCi, evaluate `parseInput "+1\n-2\n+3\n"` and confirm you get `[1, -2, 3]`. Then evaluate `parseInput ""` — what does an empty string parse to, and why?
7. Write `countLines :: FilePath -> IO Int` that reads a file and returns the number of lines in it. Use `readFile`, `lines`, `length`, and `pure` to wrap the final `Int`.

---

## 10. What you should remember

- **`IO a` is a recipe.** A first-class value that, *when executed by the runtime*, performs effects and produces an `a`. The wrapper makes effectfulness visible in the type.
- **The runtime runs exactly one `IO` value: `main :: IO ()`.** Anything not reachable from `main` is dead code.
- **A `do` block sequences actions of the same monad.** Top-to-bottom execution; the block's type is the type of its last action.
- **`<-` binds the *result* of an action; `let` binds a *pure expression*.** Both only inside `do`. Top-level `=` is unrelated to either.
- **`pure x` (or `return x` in older code) lifts a pure value into IO.** It does *not* return-as-in-C — Haskell's `return` is just monadic injection.
- **`readFile path` returns `IO String`.** Always pair it with `lines` (or `words`) to chop into pieces, then a pure parser to type them.
- **AoC pattern: thin IO at the edges, big pure middle.** Read the file, run pure functions, print the answer. Pure code is testable; the IO shell is short enough that it does not need testing.
- **Relative paths in `readFile` resolve against the working directory, not the source file.** Run from the repository root.
- **`mapM_`, `forM_`, `replicateM_` are the IO-flavoured `map` / `for_` / `repeat`.** Trailing underscore = discard the results.
- **`when` and `unless` are the named replacement for `if … then act else pure ()`.** Reach for them whenever an action should fire only on a condition.
- **Rust analogue summary**: `IO a` ↔ a `Future<Output = A>` you have not awaited yet (a recipe, not a result); `do { x <- act; ... }` ↔ `let x = act.await; ...`; `pure x` ↔ `async { x }`; `readFile path` ↔ `tokio::fs::read_to_string(path).await`. The shapes are not identical but the mental model carries over.

---

**Next**: Day 10 — modules, `cabal` project layout, and tests with `hspec`. Until now everything has been a single file run with `runghc`. Day 10 introduces the project structure that lets you split code across modules, manage dependencies in a `.cabal` file, and run a real test suite — the scaffolding the AoC solutions themselves will live in.
