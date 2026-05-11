# Day 09: Marble Mania -- Function Guide

**Problem**: `N` Elves play a marble game.  Marbles numbered `1..M` are placed in turn around a circle that starts as just marble `0`.  For most marbles, the next one is inserted between the marbles `1` and `2` clockwise of the current marble and becomes the new current.  When the marble being placed is a multiple of `23`, the placing player keeps it AND removes the marble `7` counter-clockwise of current; both numbers go into the player's score, and the marble immediately clockwise of the removed one becomes the new current.  Part 1 asks for the highest single-player score.  Part 2 asks the same with the last marble multiplied by 100.
**Answers**: Part 1 = **380705**, Part 2 = **3171801582**
**Runtime** (mean, criterion `-O2`): Parse = **1.41 µs** | Part 1 = **407.2 µs** | Part 2 = **45.54 ms** | **Total = 45.95 ms**
**Code**: [Day09.hs](../../src/Day09.hs)
**Tests**: [Day09Spec.hs](../../test/Day09Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day09"`
**Problem statement**: [day09.md](day09.md)

**New concepts this day** (beyond Days 0--8):

- **The `ST` monad and `runST`**.  `ST` is Haskell's "scoped mutation" monad: inside an `ST s` action you can read and write mutable cells, but the wrapper `runST :: (forall s. ST s a) -> a` makes the whole computation pure from the outside -- the mutation can never escape the `s` scope.  Same mental model as a Rust function that takes `&mut [i64]` internally but returns an owned `i64`.
- **`STUArray` from `Data.Array.ST`**.  The unboxed flavour of mutable arrays: stores raw machine `Int`s contiguously, no thunks, no pointer indirection.  We allocate two of them as the index arrays of a doubly-linked list.
- **`forall` + `ScopedTypeVariables`**.  The `forall s.` in `playST :: forall s. Int -> Int -> ST s Int` plus the `ScopedTypeVariables` extension lets us bring `s` into scope inside the body, so we can pin the array element type with `:: ST s (STUArray s Int Int)`.
- **`BangPatterns` on tail-recursive accumulators**.  Bangs on `!current`, `!marble`, `!best` force strictness on the loop variable so the compiled inner loop allocates no thunks per iteration -- critical at 7 million iterations for Part 2.
- **`Generic`-derived `NFData` for a parsed product type**.  `data Game = Game ... deriving (..., Generic) ; instance NFData Game`.  Same one-line technique as Day 8's `Tree`, applied to a flat record.

The doubly-linked list itself is not a new concept -- it is the same data structure you would build in C, just spelled with two parallel `Int` arrays instead of two pointers per node.  What is new is doing it inside Haskell while keeping the public API pure.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Why a list / `Seq` is too slow for Part 2](#why-a-list--seq-is-too-slow-for-part-2)
3. [Data model](#data-model)
4. [`parseInput`](#parseinput)
5. [The `play` API](#the-play-api)
6. [`playST` -- the stateful core, line by line](#playst-the-stateful-core-line-by-line)
7. [`stepBack` -- counter-clockwise walk](#stepback)
8. [The `go` loop -- insertion vs the multiple-of-23 case](#the-go-loop)
9. [`maxLoop`](#maxloop)
10. [`part1`, `part2`, `solve`](#part1-part2-solve)
11. [Tests](#tests)
12. [Benchmarks](#benchmarks)
13. [Why `ST` is not `IO`, and what that buys you](#why-st-is-not-io)
14. [What is a monad, generally?](#what-is-a-monad-generally)
15. [Possible optimizations](#possible-optimizations)
16. [Key patterns](#key-patterns)
17. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The marble game is a stateful simulation:

- The circle starts as `[0]` -- a single marble that is its own clockwise and counter-clockwise neighbour.
- For each successive integer `m = 1, 2, 3, ...`, *some Elf* places marble `m` somewhere in the circle.  The Elves take turns in player order (marble 1 to player 1, marble 2 to player 2, ..., wrapping at `numPlayers`).
- The placement rule: insert `m` between marble `1cw` and marble `2cw` of the current marble; the new marble becomes current.
- The exception, every 23rd marble: the placing player *keeps* marble `m` (adds it to their score), then *removes* the marble `7ccw` of current (also added to their score), and the marble immediately clockwise of the removed one becomes the new current.

After all `M` marbles have been placed, we report the highest single-player score.

For the actual input `464 players; last marble is worth 71730 points`:

- Part 1 simulates 71,730 placements.
- Part 2 simulates 71,730 × 100 = **7,173,000** placements.

That two-orders-of-magnitude jump is the whole point of Day 9.  It is engineered to crush a naive "use a list" solution.

---

## Why a list / `Seq` is too slow for Part 2

There are several natural Haskell representations for the circle.  Three of them, and what they cost on Part 2:

| Representation                              | Per-step cost                       | Part 2 total |
|--------------------------------------------|-------------------------------------|-------------:|
| `[Int]` with `splitAt` to insert           | `O(n)` for both `splitAt` and the cons after it | hours        |
| `Data.Sequence.Seq Int` (finger tree)      | `O(log n)` for `splitAt`, `O(1)` for `<\|` / `\|>` | ~5--15 s     |
| Two-list zipper `(left, current, right)`   | `O(1)` amortised for one rotation, `O(k)` for `k` rotations | ~1--2 s      |
| `STUArray` doubly-linked list (this file)  | `O(1)` per insert / remove          | **45 ms**    |

The `Data.Sequence` approach is the most *idiomatic* Haskell -- finger trees are a beautiful fit for a sliding-window problem -- and would be the first thing to reach for if Part 2 needed only ~100 K marbles.  At 7 M marbles the `O(log n)` overhead, plus finger-tree node allocations and GC pressure, push the runtime out of the project's "under 1 second" target.

The two-list zipper is a viable middle ground.  Once you reach for `STUArray`, though, the per-step work is a handful of machine-word reads and writes -- the same code your C compiler would emit -- and you can stop worrying about constants.

We pick `STUArray` because:

1. It is genuinely the fastest pure-Haskell option without giving up `runST`'s purity guarantee.
2. It introduces the `ST` monad, which is a major Haskell concept worth knowing.
3. The doubly-linked-list shape itself is universally familiar and barely any code.

---

## Data model

```haskell
data Game = Game
  { numPlayers :: !Int
  , lastMarble :: !Int
  } deriving (Eq, Show, Generic)

instance NFData Game
```

Two `Int` fields with strict `!` annotations.  `Generic` plus an empty `instance NFData Game` gives criterion a deep-evaluation walker for the parsed input -- exactly the same idiom we used for `Tree` on Day 8.  The fields are strict because there is no meaningful "lazy half-built `Game`" we would ever want to construct.

---

## `parseInput`

```haskell
parseInput :: String -> Game
parseInput s = case words s of
  (n : _ : _ : _ : _ : _ : m : _) -> Game (read n) (read m)
  _ -> error ("Day09.parseInput: unexpected line " ++ show s)
```

The input is a single line of nine words:

```
464 players; last marble is worth 71730 points
 0     1     2    3     4    5     6      7
```

(Word index 5 is the literal `"worth"`; word index 6 is the integer we want.  Word index 7 is the trailing `"points"`.)

Pattern matching on the result of `words`:

- `(n : _ : _ : _ : _ : _ : m : _)` -- bind word 0 as `n`, skip words 1--5 with five `_`, bind word 6 as `m`, then a final `_` matches whatever remains (in this case the single word `"points"`).
- The catch-all `_ -> error ...` arm fires only on a malformed input.  We accept the panic because the puzzle input is trusted.

`read` does the heavy lifting on the two integer tokens; we have used it on every prior day.

---

## The `play` API

```haskell
play :: Int -> Int -> Int
play players lastM = runST (playST players lastM)
```

`play` is the *pure* face of the simulation: given the player count and last-marble value, it returns the winning score as an ordinary `Int`.  Underneath, all the work happens inside an `ST` action that allocates and mutates the linked-list arrays; `runST` traps that mutation in a closed scope and returns the result.

This separation -- `play` pure, `playST` effectful -- is the standard Haskell pattern for "I need mutation to compute this fast, but I do not want it to leak."  Compare the IO-monad equivalent: if we had used `IO`, the result would have type `IO Int` and the rest of the program would have to thread it through `do`-notation forever.  `runST` is exactly the escape hatch that prevents that contagion.

---

## `playST` -- the stateful core, line by line

```haskell
playST :: forall s. Int -> Int -> ST s Int
playST players lastM = do
  nxt    <- newArray (0, lastM)        0 :: ST s (STUArray s Int Int)
  prv    <- newArray (0, lastM)        0 :: ST s (STUArray s Int Int)
  scores <- newArray (0, players - 1)  0 :: ST s (STUArray s Int Int)
```

### The `forall s.` and what `ScopedTypeVariables` does

`playST` is polymorphic in `s`, the **region tag** of the `ST` monad.  Every time we call `runST`, GHC picks a fresh `s` that nothing else can name -- that is what guarantees the mutable state cannot leak.

By default, the `s` in the function's signature is *not* in scope inside the body.  `ScopedTypeVariables` (the language pragma at the top of the file) changes that: now we can write `:: ST s (STUArray s Int Int)` in a local annotation and have it refer to the *same* `s` from the outer signature.  Without the pragma, GHC would treat that `s` as a fresh existential and the type error would be incomprehensible.

### Why annotate the array types?

`newArray :: (MArray a e m, Ix i) => (i, i) -> e -> m (a i e)` is *very* polymorphic.  It can return either:

- `STArray s i e` -- a boxed array (each cell stores a thunk pointer).
- `STUArray s i Int` -- an unboxed array (each cell is a raw machine word).

Both implement the `MArray` class.  Without an explicit annotation, GHC will pick one of them more or less arbitrarily (often the boxed default), and the boxed version is ~3x slower because every read goes through a thunk and every write allocates.  Pinning `STUArray s Int Int` forces the unboxed representation.

### Three arrays, what they hold

| Array        | Bounds              | What it stores                                         |
|--------------|---------------------|--------------------------------------------------------|
| `nxt`        | `(0, lastM)`        | `nxt[m]` = marble immediately clockwise of marble `m`. |
| `prv`        | `(0, lastM)`        | `prv[m]` = marble immediately counter-clockwise.       |
| `scores`     | `(0, players - 1)`  | Per-player running score (0-based player index).       |

Marble values are *exactly* the indices we use, since marble `m` is unique and bounded by `lastM`.  No `Map Int Int` needed.

### Why the initial state is correct

`newArray` zeroes every cell.  Marble 0 starts as the only member of the circle, and a singleton circle has the property "0 is its own clockwise neighbour" -- which is exactly `nxt[0] = 0`.  Same for `prv[0] = 0`.  We do not need any explicit "set up the initial circle" step because the zero-fill matches what we want.

---

## `stepBack`

```haskell
stepBack :: Int -> Int -> ST s Int
stepBack !i 0  = return i
stepBack !i !k = do
  p <- readArray prv i
  stepBack p (k - 1)
```

Walks `k` steps counter-clockwise from marble `i` by chasing `prv[]` pointers.  Recursive, tail-call-shaped, and bang-pattern strict on both arguments so the compiled loop has no thunk allocation.

The `return i` in the base case is `ST`-flavoured -- it lifts the pure `Int` into the `ST` monad so the recursive call's `do`-block can bind it.

For the multiple-of-23 case we always call `stepBack current 7`, so `k` is bounded by 7 forever.  Total time across the whole game is `7 * (lastM `div` 23)` array reads -- about 2.2 million for Part 2, which is a few percent of total cost.

---

## The `go` loop

```haskell
go :: Int -> Int -> ST s ()
go !current !marble
  | marble > lastM = return ()
  | marble `mod` 23 == 0 = do
      target <- stepBack current 7
      tprev  <- readArray prv target
      tnext  <- readArray nxt target
      writeArray nxt tprev tnext
      writeArray prv tnext tprev
      let player = (marble - 1) `mod` players
      cur <- readArray scores player
      writeArray scores player (cur + marble + target)
      go tnext (marble + 1)
  | otherwise = do
      one <- readArray nxt current
      two <- readArray nxt one
      writeArray nxt one    marble
      writeArray prv marble one
      writeArray nxt marble two
      writeArray prv two    marble
      go marble (marble + 1)
```

Three guards, mirroring the puzzle's three rules.

### Termination: `marble > lastM`

When we have placed every marble from `1` to `lastM`, the loop returns `()` and the action ends.  After this, `playST` falls through to `maxLoop` to read the winner out of the `scores` array.

### The standard insertion case (`otherwise`)

Insert `marble` between `nxt[current]` (let's call it `one`) and `nxt[one]` (call it `two`).  The before-and-after diagram:

```
  before:     ... <- current -> one -> two -> ...
  after :     ... <- current -> one -> marble -> two -> ...
```

Four pointer writes are enough:

| Write              | Meaning                                            |
|--------------------|----------------------------------------------------|
| `nxt[one] = marble`| marble's left neighbour links forward to marble.   |
| `prv[marble] = one`| marble links backward to its left neighbour.       |
| `nxt[marble] = two`| marble links forward to its right neighbour.       |
| `prv[two] = marble`| marble's right neighbour links backward to marble. |

#### Token by token through the insertion case

The two `<-` lines look the most unfamiliar.  They are *not* range, slice, or directional operators.  Each is a **single-cell** array read whose result is given a local name for the rest of the `do`-block:

- `<-` reads as **"name the result on the right."**  It is the monadic-bind arrow of `do`-notation; the same step in pure style is `readArray nxt current >>= \one -> ...`.  See [What is a monad, generally?](#what-is-a-monad-generally) for the full story.
- `readArray :: STUArray s i e -> i -> ST s e` returns *one* element at the given index.  Same shape as Rust's `nxt[current]`.
- `writeArray :: STUArray s i e -> i -> e -> ST s ()` writes a single element and yields `()`.

| Token / phrase                  | Meaning |
|---------------------------------|---------|
| `one <- readArray nxt current`  | Read cell `current` of array `nxt`; name the `Int` we find there `one`.  After this line, `one` is the marble immediately clockwise of `current`. |
| `two <- readArray nxt one`      | Read cell `one` of `nxt`; name the result `two`.  `two` is the marble two steps clockwise of `current`. |
| `writeArray nxt one    marble`  | Set `nxt[one] = marble`.  `one`'s new clockwise neighbour is the marble we are inserting. |
| `writeArray prv marble one`     | Set `prv[marble] = one`.  `marble`'s counter-clockwise neighbour is `one`. |
| `writeArray nxt marble two`     | Set `nxt[marble] = two`.  `marble`'s clockwise neighbour is `two`. |
| `writeArray prv two    marble`  | Set `prv[two] = marble`.  `two`'s new counter-clockwise neighbour is `marble`. |

Crucially, `one` and `two` are each a single `Int` -- a *marble number* -- not an array slice and not a range from `current` to `nxt`.  The names just give us readable labels for the two marbles we are about to splice the new one between.

#### Concrete trace through marble 2

Right after marble 1 is placed the state is:

```
nxt:  nxt[0]=1, nxt[1]=0
prv:  prv[0]=1, prv[1]=0
current = 1
```

On the next loop iteration `marble = 2` and we fall through to the `otherwise` branch:

| Line                            | Reads / writes      | Local names after |
|---------------------------------|---------------------|-------------------|
| `one <- readArray nxt current`  | reads `nxt[1] = 0`  | `one = 0`         |
| `two <- readArray nxt one`      | reads `nxt[0] = 1`  | `two = 1`         |
| `writeArray nxt one    marble`  | `nxt[0] = 2`        | -                 |
| `writeArray prv marble one`     | `prv[2] = 0`        | -                 |
| `writeArray nxt marble two`     | `nxt[2] = 1`        | -                 |
| `writeArray prv two    marble`  | `prv[1] = 2`        | -                 |

The linked list now reads `nxt[0]=2, nxt[2]=1, nxt[1]=0` and `prv[1]=2, prv[2]=0, prv[0]=1`.  Following `nxt` clockwise from the new current (`marble = 2`): `2 -> 1 -> 0 -> 2`.  Three marbles, current is 2, which matches the puzzle's `0 (2) 1` rendering exactly.

`current` itself does not move within the array (its slot is unchanged); the recursive call passes `marble` as the new `current` because the puzzle says "the marble that was just placed becomes the current marble."

### The multiple-of-23 case

`marble \`mod\` 23 == 0` is the single most expensive line of the file by criterion: it fires `lastM \`div\` 23` times -- about 311,800 times in Part 2.  Each firing does:

1. **Locate the marble to remove**: `target <- stepBack current 7`.  Walks 7 steps counter-clockwise via `prv[]`.
2. **Read its neighbours**: `tprev <- readArray prv target` (1 ccw of target) and `tnext <- readArray nxt target` (1 cw of target).
3. **Splice it out**: two pointer writes, `nxt[tprev] = tnext` and `prv[tnext] = tprev`.  We do not bother clearing `nxt[target]` / `prv[target]` -- the marble's slot is just abandoned, never touched again, and the next iteration's `go` is never given `target` as the current marble (we recurse on `tnext`).
4. **Update the player's score**: `(marble - 1) \`mod\` players` is the placer's index (marble 1 → player 1 → array index 0; marble 2 → player 2 → index 1; ...).  Their score gains `marble + target`.
5. **Recurse with the new current**: `go tnext (marble + 1)`.  `tnext` -- the marble that was immediately clockwise of the removed one -- becomes the new current, exactly per the puzzle.

There is no bounds check on `stepBack 7`.  By the time we hit marble 23, the circle has 23 marbles in it; by marble 46 it has 23 + 22 = 45.  In general before any multiple-of-23 step the circle has at least 22 elements, so walking 7 steps backwards never wraps to a not-yet-placed slot.  The puzzle is constructed so that this is always safe.

### Why the loop is one big function instead of three

The cleaner separation -- "insertion function" and "removal function" -- would split the logic across two `ST s ()` actions and pass the new current back via the return value.  That works, and would compile to roughly the same code, but the inner-loop boilerplate doubles.  Keeping the whole step inside one `go` lets the compiler see all the array reads/writes together and inline the recursion as a tight loop.  This is the Haskell equivalent of "I would not refactor a hot inner loop for stylistic reasons" in any other language.

### Why bang patterns on `current` and `marble`

Without `BangPatterns`, every recursive call would build a thunk shaped like `current = [previous current modified by one branch's worth of code]`.  Across 7 M iterations that would tower up enough closures to crash with a stack overflow before completing.  The `!current` and `!marble` annotations force evaluation at the call site, so each iteration starts with two raw `Int`s on the stack, no allocations.

---

## `maxLoop`

```haskell
let maxLoop :: Int -> Int -> ST s Int
    maxLoop !i !best
      | i >= players = return best
      | otherwise = do
          v <- readArray scores i
          maxLoop (i + 1) (max best v)
maxLoop 0 0
```

Linear scan of the `scores` array tracking the running maximum.  Bang patterns on both arguments for the same reason as above.  Returns the largest score encountered.

We could equivalently write `maximum <$> mapM (readArray scores) [0 .. players - 1]`, which is shorter but allocates an intermediate list of 464 `Int`s.  At 464 elements the difference is invisible; the explicit fold pattern is shown here to keep the style consistent across the whole file.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Game -> Int
part1 g = play (numPlayers g) (lastMarble g)

part2 :: Game -> Int
part2 g = play (numPlayers g) (lastMarble g * 100)

solve :: String -> IO ()
solve contents = do
  let g = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 g))
  putStrLn ("  part 2: " ++ show (part2 g))
```

`part1` and `part2` differ only in the `* 100` factor.  Both feed a fresh game into `play`; there is no shared work to amortise (the simulation has to start over for the longer Part 2 game).  `solve` parses once and prints both answers.

---

## Tests

Coverage in [Day09Spec.hs](../../test/Day09Spec.hs):

1. **`parseInput`** -- one round-trip on the actual-input line.
2. **The six examples in the puzzle text** -- `9 players / 25 marbles → 32`, plus the five additional games stated in the problem.  These are tiny (under 8000 marbles each) but they cover:
   - The minimal game where Part 1 hits at marble 23 only once.
   - Games long enough that hundreds of multiple-of-23 events fire.
   - Player counts that hit every congruence class for `(marble - 1) \`mod\` players`.
3. **Pinned actual-input answers** -- `380705` for Part 1 and `3171801582` for Part 2.

Note that the Part 2 test takes ~45 ms and is the slowest single test in the whole project.  Worth keeping in the suite as a regression guard against accidentally re-introducing a thunk-based slowdown.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean       | What it times |
|--------------------|-----------:|---------------|
| `day09/parseInput` | 1.41 µs    | One short line: `words` + two `read`s. |
| `day09/part1`      | 407.2 µs   | 71,730 marble placements + ~3,100 multiple-of-23 events. |
| `day09/part2`      | 45.54 ms   | 7,173,000 placements + ~311,800 multiple-of-23 events. |
| `day09/combined`   | 46.4 ms    | End-to-end from raw string. |

**Total = Parse + Part 1 + Part 2 = 45.95 ms.**

Part 2 is **~112x** more marbles than Part 1 and runs in ~112x the time -- the simulation is genuinely linear in marble count.  That linear scaling is the load-bearing claim of this whole file: if the array writes were not `O(1)`, that ratio would be much worse.

The parser is in the noise.  Day 8's parser dominated total runtime because it had 6500 tokens; here we have two.

---

## Why `ST` is not `IO`, and what that buys you

This is the conceptual lesson of Day 9.

`IO` and `ST` look almost identical at the operational level: both let you allocate mutable state (`IORef` / `STRef`, `IOArray` / `STArray`), read it, write it, and sequence the resulting actions with `do`-notation.  The difference is in their *types*:

```haskell
runST :: (forall s. ST s a) -> a       -- pure result, scoped state
runIO :: IO a -> IO a                  -- (no equivalent: IO can never escape)
```

The `forall s.` in `runST` is the magic.  It says: "the action I am being given must work for *any* `s` -- it cannot have committed to a specific one."  Any `STRef` or `STUArray` you allocate has type `STRef s ...` for the *one specific `s`* of the outer action; if you tried to return such a reference, the type would no longer be polymorphic in `s`, and `runST` would refuse to compile.

The practical consequence: `ST` actions are *referentially transparent*.  `play 9 25 == 32` always, in any context.  No `IO`, no need to thread the world through.  The mutation is real (the bytes really do get rewritten in `nxt`, `prv`, `scores`), but the *abstraction* is pure.

That is the gift `ST` gives you: in-place mutation when you need the speed, with the same compositional reasoning as any other pure function.  Rust's `&mut T`-bounded scope is the closest analogue -- a function that takes `&mut Vec<i64>` can mutate the vector freely, but the moment it returns, the borrow ends and the caller cannot tell the difference between "we mutated in place" and "we returned a fresh `Vec`."  `ST` is the same trick, dressed up as a monad.

Three concrete consequences in this file:

1. **`play 9 25` is just an `Int`.**  No `IO`, no leak.
2. **Tests can call `play` directly** with `shouldBe`, no special harness for effectful code.
3. **Composition is normal**: `part1 = play (numPlayers g) (lastMarble g)` would not type-check in `IO` without lifting; in `ST`-via-`runST` it's just function application.

---

## What is a monad, generally?

Day 9 is the first day where the code is written *inside* a monad (the `ST s` monad) using `do`-notation.  The pattern is worth pausing on, because the same shape shows up in `Maybe`, `Either e`, `[]`, `IO`, `State s`, parser combinators, async code, and dozens of other places.  Once you see it, the rest of Haskell stops looking like a separate sub-language.

### The type-class definition

A **monad** is any type constructor `m :: Type -> Type` (something that takes a type and produces a type, like `Maybe`, `IO`, `ST s`, `[]`) for which you can implement two operations:

```haskell
class Applicative m => Monad m where
  return :: a -> m a
  (>>=)  :: m a -> (a -> m b) -> m b
```

- `return :: a -> m a` -- "embed this pure value into the monad."  For `Maybe`, `return x = Just x`.  For `IO`, it produces an action that does nothing and yields `x`.  For `ST s`, it produces a stateful action that does not touch any reference and yields `x`.
- `(>>=) :: m a -> (a -> m b) -> m b` -- pronounced **"bind"**.  Given a computation `m a` producing an `a`, and a function from `a` to a *new* computation `m b`, run them in sequence and produce the combined `m b`.

That is the entire abstract shape.  Every monad just picks a different meaning for "in sequence."

### `do`-notation is sugar for `>>=`

The `do`-block from `playST` in this file:

```haskell
do
  one <- readArray nxt current
  two <- readArray nxt one
  writeArray nxt one    marble
  writeArray prv marble one
```

is exactly the same code as:

```haskell
readArray nxt current     >>= \one ->
readArray nxt one         >>= \two ->
writeArray nxt one marble >>  (
writeArray prv marble one)
```

Each `<-` arrow is GHC inserting a `>>=` and binding the result to a name.  Lines without `<-` use `>>` (which is `>>= \_ ->` -- "do this, ignore the result, continue").  This is the *only* thing `do`-notation does -- pretty syntax for chains of `>>=`.

### The intuition: a programmable semicolon

In an imperative language, `;` between two statements means "do the first, then the second."  That is it -- the language defines what "then" means, and you cannot change it.

Monads let you choose what "then" means:

| Monad        | What "then" means in `>>=`                                                       |
|--------------|-----------------------------------------------------------------------------------|
| `Maybe`      | If the previous step was `Nothing`, short-circuit; otherwise unwrap and continue. |
| `Either e`   | Same as `Maybe`, but with a payload describing why we failed.                     |
| `[]`         | For each result of the previous step, run the next; collect every result.         |
| `IO`         | Perform the side effect, observe its result, then perform the next.               |
| `ST s`       | Perform the scoped mutation, observe its result, then perform the next.           |
| `State s`    | Thread a logical state value through; each step can read or modify it.            |
| Parser monad | Consume some input, name what was parsed, continue parsing.                       |

The `do`-block looks the same regardless of which "then" is in effect.  That uniformity is the lever -- code written for one monad can sometimes be reused unchanged for another, and library authors take heavy advantage of it (`mapM`, `forM_`, `replicateM`, `when`, `unless` from `Control.Monad` all work for *any* monad).

### The monad laws

For an implementation to deserve the name `Monad`, three identities must hold:

```
return x >>= f    ==  f x                          -- left identity
m >>= return      ==  m                            -- right identity
(m >>= f) >>= g   ==  m >>= (\x -> f x >>= g)      -- associativity
```

In words: `return` does nothing on either side of a bind, and chains of binds can be re-bracketed without changing their meaning.  Equational reasoning over `do`-blocks works because of these laws -- you can refactor a long `do`-block into a chain of helper functions, hoist common prefixes, swap explicit recursion for `mapM`, and the meaning is preserved.  GHC does not check the laws -- the implementer of each monad has to respect them -- but every monad in `base` and the standard libraries does.

### Day 9's `ST s` viewed through this lens

`ST s` is a monad: `ST s a` is a stateful computation that yields an `a`.  Sequencing `ST s` actions with `>>=` threads the (implicit, type-tagged) state through them.  The four lines of the standard insertion case

```haskell
one <- readArray nxt current
two <- readArray nxt one
writeArray nxt one    marble
writeArray prv marble one
```

are four `ST s` actions composed by `>>=`.  The first reads `nxt[current]`, names the result `one`, hands it to the second action which reads `nxt[one]`, names that `two`, hands both to the third action which writes `marble` into `nxt[one]`, and so on.  Pure functional code with mutation underneath, type-checked end-to-end.

### Familiar Rust analogues

There is no single "monad" feature in Rust, but several Rust idioms are exactly the bind operator for a specific monad.  Once you see them, the connection clicks.

- **`?` on `Result` / `Option`** is `>>=` for the `Either` / `Maybe` monad.  `let n = s.parse::<i32>()?;` is "if `parse` returned `Err`, short-circuit; otherwise unwrap and continue."  In Haskell that is `s >>= parseInt >>= \n -> ...` or, with `do`, `n <- parseInt s`.  The `?` syntax even resembles `<-` in a `do`-block.
- **`async`/`await`** is `>>=` for the future-producing monad.  Every `.await` is "the previous future has resolved; here is its value, now keep going."
- **`Iterator::flat_map`** is `>>=` for the list monad.  `xs.flat_map(f).flat_map(g)` produces the cartesian product, which is exactly `xs >>= f >>= g` in Haskell.
- **`for x in xs { ... }`** is `>>=` for the list monad combined with `>>` -- iterate, perform side effects, discard the per-iteration value.

Rust gave each of these its own bespoke syntax (`?`, `await`, `for`, `flat_map`).  Haskell uses `do`-notation for *all* of them, parameterised on which monad is in scope.  That is why Haskell code can look monolithic at first glance -- one syntax for many things.  It is also why, once you internalise it, you can read code in an unfamiliar monad and follow it without learning a new control structure.

### Why bother with the abstraction?

Two reasons that show up in every project, including ours:

1. **Code reuse across effects.**  A function with type `Monad m => Int -> m Int` works in `Maybe`, `IO`, `ST s`, `[]`, parser monads, and any monad you might define.  We do not write that polymorphism much in AoC code, but we *use* it constantly: `mapM_`, `forM_`, `when`, `unless` are all `Monad m =>`-polymorphic and we have already seen `mapM_` printing the rendered grid in Day 10's `solve`.
2. **Equational reasoning.**  Knowing `return` is identity-ish and `>>=` is associative means you can refactor `do`-blocks the same way you refactor pure expressions: factor common prefixes into helpers, swap a long chain for a fold over a list of actions, inline a one-line action.  Same composability you have in pure code, with effects threaded through.

### What this section deliberately did not cover

- **Functor and Applicative.**  Every monad is also a `Functor` (`fmap :: (a -> b) -> m a -> m b`) and an `Applicative` (`(<*>) :: m (a -> b) -> m a -> m b`).  These are weaker abstractions than `Monad` and worth a separate section once we hit a day where they help.  The class hierarchy `Functor => Applicative => Monad` shows up in error messages occasionally; for now, just notice it and keep going.
- **Monad transformers.**  When you want "stateful AND failure-aware" code, you stack monads via `StateT`, `ExceptT`, `ReaderT`.  We will meet these only if a puzzle genuinely demands them.
- **`return` vs `pure`.**  `pure` is the `Applicative` version of `return` -- they coincide for every monad, and modern code prefers `pure`.  In our code we write `return` for symmetry with the textbook definition; either spelling works.

The 200-word version: **a monad is a type with `return` and `>>=`, where `return` injects a pure value and `>>=` chains an effectful step into a continuation.  `do`-notation is sugar for chains of `>>=`.  Each monad picks what "chains" means -- failure short-circuit, mutation threading, list flattening, IO sequencing.  `ST s` is the monad we used today; the same shape underlies everything from `Maybe` to `Megaparsec`.**

---

## Possible optimizations

### `ByteString` parsing

The parser is already in the microsecond range and will never matter to the total runtime.  Skipping.

### Skip the `mod 23` test by special-casing the schedule

Every 23rd marble we do the expensive branch.  A fused loop that maintains a separate "marbles until next 23-event" counter would skip the modulus on every other iteration -- each `mod` is a few cycles, but with 6.86 M iterations going down the cheap branch, the savings are real.  Estimate: 5--15% speedup.  Worth measuring if Part 2 ever needs to be in the millisecond range.

### Use machine-word `Int` rather than 64-bit-everywhere

Already done -- `STUArray s Int Int` picks the platform `Int`, which is 64 bits on the target machine and 32 bits on no machine we still target.  No gains available here.

### Two-list zipper (the pure approach)

```haskell
-- conceptual sketch, not benchmarked
data Zipper = Zipper { zL :: ![Int], zC :: !Int, zR :: ![Int] }

rotateCw :: Int -> Zipper -> Zipper
rotateCw 0 z = z
rotateCw n (Zipper l c (r:rs)) = rotateCw (n-1) (Zipper (c:l) r rs)
rotateCw n (Zipper l c [])     = rotateCw n     (Zipper [] c (reverse l))
```

A two-list zipper amortises one rotation to `O(1)` and reaches Part 2 in roughly 1--2 seconds.  Significantly slower than `STUArray` but requires no monad, no extension, and reads as ordinary recursive code.  Worth implementing once for comparison, but not as the primary solution.

### Why we did not use `Data.Sequence.Seq Int`

Finger trees give `O(log n)` `splitAt` and `O(1)` `<\|` / `\|>`, which would handle Part 2 in ~5--10 seconds.  Beautiful code, but ~150x slower than `STUArray`.  The teaching value of `Seq` is high (it generalises to many problems where you need both ends of a list and middle-splits), but Day 9 happens to be the puzzle where the constant factor matters more than the abstraction.

---

## Key patterns

1. **`runST` for in-place computation with a pure result**.  Whenever you have a fast mutable algorithm but the public API should be a pure function, the recipe is: write the mutation inside `ST s a`, wrap the entry point in `runST`.  The compiler will refuse to let mutable state escape, so the abstraction is enforced for free.
2. **Doubly-linked list as two index arrays**.  When elements have a natural numeric ID (here, the marble's value), parallel `prv[id]` / `nxt[id]` arrays beat any pointer-based representation in a GC'd language.  No allocations per insert, no thunk towers, just four word writes.
3. **Bang patterns on tail-recursive accumulators**.  Any time a recursive function builds a numeric value through repeated addition / max / etc., bangs on the accumulator parameters are mandatory.  Without them, the loop accumulates thunks; with them, it compiles to a counted machine loop.
4. **`forall` in a function signature + `ScopedTypeVariables`** for naming type variables in the body's local annotations.  This is the standard recipe for `ST`-monad code that needs to pin array types.
5. **Inline the inner loop**.  When performance matters, do not factor the body into clean helper actions; one big `go` with explicit guards lets the compiler see and inline everything.

---

## Side-by-side with the Rust mental model

```rust
fn play(players: usize, last_m: usize) -> u64 {
    let mut nxt    = vec![0usize; last_m + 1];
    let mut prv    = vec![0usize; last_m + 1];
    let mut scores = vec![0u64;   players];

    let mut current: usize = 0;
    for marble in 1..=last_m {
        if marble % 23 == 0 {
            let mut target = current;
            for _ in 0..7 {
                target = prv[target];
            }
            let tprev = prv[target];
            let tnext = nxt[target];
            nxt[tprev] = tnext;
            prv[tnext] = tprev;
            scores[(marble - 1) % players] += marble as u64 + target as u64;
            current = tnext;
        } else {
            let one = nxt[current];
            let two = nxt[one];
            nxt[one]    = marble;
            prv[marble] = one;
            nxt[marble] = two;
            prv[two]    = marble;
            current = marble;
        }
    }

    *scores.iter().max().unwrap()
}
```

Lined up:

| Concept                               | Rust                                                | Haskell                                                  |
|---------------------------------------|-----------------------------------------------------|----------------------------------------------------------|
| Mutable index arrays                  | `Vec<usize>` (allocated once, then mutated in place)| `STUArray s Int Int` allocated with `newArray`           |
| Scoped mutation, pure outside         | function returns `u64`, caller never sees the `Vec`s| `runST :: (forall s. ST s a) -> a` with `s` traps `STUArray` |
| Element read / write                  | `nxt[current]` / `nxt[one] = marble`                | `readArray nxt current` / `writeArray nxt one marble`    |
| Counter-clockwise walk by 7           | `for _ in 0..7 { target = prv[target]; }`           | `stepBack` recursive helper                              |
| Per-iteration loop variable           | `let mut current: usize`                            | `go !current !marble` parameter, bang-patterned          |
| "Find max" over a small array         | `*scores.iter().max().unwrap()`                     | `maxLoop` over `[0 .. players - 1]`                      |
| Avoiding allocation in the inner loop | `Vec` already gives raw `usize` storage             | `STUArray` gives raw `Int` storage; bang patterns kill thunks |

Two real differences:

1. **The `forall s.` is the price of admission.**  Rust does not need it -- every borrow has a lifetime that the compiler tracks per-callsite.  Haskell's escape mechanism is rank-2 polymorphism instead.  The user-visible payoff is identical: scoped mutation that cannot leak.
2. **The Rust `for marble in 1..=last_m` is a counted loop**; the Haskell `go` is tail recursion.  GHC compiles tail recursion into a counted loop with `-O2`, so the generated code is essentially the same.  The difference is purely syntactic.

---

**Navigation**: [Problem statement](day09.md) | [Summary table](summary_2018.md) | [<- Day 8](day08_function_guide.md) | [Day 10 ->](day10_function_guide.md)
