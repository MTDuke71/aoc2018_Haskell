# Day 6 — Folds: `foldr`, `foldl`, `foldl'`

**Goal**: replace hand-rolled "walk the list and accumulate something" recursion with one of the three standard folds. Understand why `foldl'` is the default for AoC, why `foldr` still earns its keep, and why plain `foldl` is almost always a bug waiting to happen.

**Source files**:
- [src/Folds.hs](src/Folds.hs) — the three folds, with the common functions reimplemented on top of them.
- [src/Strict.hs](src/Strict.hs) — a head-to-head demo: lazy `foldl` blows the stack, `foldl'` does not.

---

## 1. The pattern you keep writing

By Day 4 you had already written this shape three times in different disguises:

```haskell
sumIt :: [Int] -> Int
sumIt []     = 0
sumIt (x:xs) = x + sumIt xs

lengthIt :: [a] -> Int
lengthIt []     = 0
lengthIt (_:xs) = 1 + lengthIt xs

productIt :: [Int] -> Int
productIt []     = 1
productIt (x:xs) = x * productIt xs
```

Three functions, one shape: a base case for `[]` and a step that combines the head with the recursive call on the tail. Only two things change between them — the **starting value** (`0`, `0`, `1`) and the **combining function** (`+`, `\_ acc -> 1 + acc`, `*`).

A fold is exactly that pattern, factored out once. Pass in the starting value and the combining function; the fold does the recursion.

**Rust analogue**: this is the same observation that gives you `Iterator::fold` in Rust — `(0..=5).fold(0, |acc, x| acc + x)` is the same idea, with the same two arguments. The differences are about evaluation order and laziness, which is the rest of this day.

---

## 2. `foldr` — fold from the right

`foldr` is the cleanest definition. You can read it in two lines:

```haskell
foldr :: (a -> b -> b) -> b -> [a] -> b
foldr _ z []     = z
foldr f z (x:xs) = f x (foldr f z xs)
```

The mental model: `foldr f z` walks the list and **replaces every `(:)` with `f` and the final `[]` with `z`**. So:

```
foldr (+) 0 [1, 2, 3]
= foldr (+) 0 (1 : 2 : 3 : [])
= 1 + (2 + (3 + 0))
= 6
```

Every cons becomes a `+`, the empty list becomes `0`. That is the whole story.

In code:

```haskell
sumR :: [Int] -> Int
sumR = foldr (+) 0
```

One line replaces three. The combining function comes first, the starting value second, the list last.

### Reading the type signature

`foldr :: (a -> b -> b) -> b -> [a] -> b`

| Piece | What it is |
|-------|------------|
| `a` | The element type of the list. |
| `b` | The result type. |
| `(a -> b -> b)` | The combining function: take an element and the result-so-far, produce a new result. |
| `b` | The starting value (the result for the empty list). |
| `[a]` | The list to fold. |
| `b` | The final answer. |

Notice the function takes the **element first** and the **accumulator second**. That order is the giveaway that this is a *right* fold — the recursion has already happened on the tail by the time the function is called.

### `foldr` is the right tool for building a list

Because `(:)` itself is a "combine an element with a list" operation, `foldr` is the natural fold for producing list-shaped results. `map` and `filter` fall straight out of it:

```haskell
mapR :: (a -> b) -> [a] -> [b]
mapR f = foldr (\x acc -> f x : acc) []

filterR :: (a -> Bool) -> [a] -> [a]
filterR p = foldr (\x acc -> if p x then x : acc else acc) []
```

These are not just clever; they are the *definitions* the Prelude uses (modulo fusion magic). The lazy cons keeps them streaming — you can take the first element of `mapR f xs` without forcing the whole input.

---

## 3. `foldl` — fold from the left

`foldl` walks the list left to right, threading an accumulator:

```haskell
foldl :: (b -> a -> b) -> b -> [a] -> b
foldl _ z []     = z
foldl f z (x:xs) = foldl f (f z x) xs
```

Note the type difference: the combining function is `(b -> a -> b)` — accumulator **first**, element **second**. Mirror image of `foldr`.

If you imagine evaluating `foldl (+) 0 [1, 2, 3]` step by step:

```
foldl (+) 0       [1, 2, 3]
foldl (+) (0+1)   [2, 3]
foldl (+) ((0+1)+2)   [3]
foldl (+) (((0+1)+2)+3)   []
((0+1)+2)+3
6
```

The accumulator parenthesises to the **left** — that is what "left fold" means.

### The catch

Here is the problem. Haskell is lazy. Look at that third line: `foldl (+) ((0+1)+2) [3]`. The expression `((0+1)+2)` is **not** the number `3` yet — it is an **unevaluated thunk** representing "add 0 and 1, then add 2." On the next step it becomes a thunk wrapping a thunk, and so on.

For a 30-million-element list, lazy `foldl` builds a 30-million-deep nested addition before the Prelude's `print` finally forces it. Forcing that nested expression is what overflows the stack.

You almost never want this. The Prelude `foldl` is there for compatibility and for the rare cases where laziness in the accumulator is actually what you want (it is rare). For numeric reductions, sums, counts, max/min, anything where the accumulator is a `Bang`-able value — use `foldl'` instead.

---

## 4. `foldl'` — strict fold from the left, the one you actually use

`foldl'` lives in `Data.List`, so you import it:

```haskell
import Data.List (foldl')
```

The definition adds one extra step: force the new accumulator before recursing.

```haskell
foldl' :: (b -> a -> b) -> b -> [a] -> b
foldl' _ z []     = z
foldl' f z (x:xs) = let z' = f z x in z' `seq` foldl' f z' xs
```

`seq a b` is the Prelude primitive that says "evaluate `a` to weak head normal form, then return `b`." So `z' \`seq\` foldl' f z' xs` means "actually compute the new accumulator, then recurse." The chain of thunks never builds; the run uses constant stack.

The apostrophe is part of the name, by convention — Haskell uses a trailing prime to mean "strict variant of the function next door." You will see this elsewhere too (e.g. `Data.Map.Strict.insert'`).

In code, swapping `foldr` for `foldl'` for a numeric sum is mechanical:

```haskell
sumL :: [Int] -> Int
sumL = foldl' (+) 0
```

Same call shape, same answer, but it runs in constant stack and constant memory regardless of list length.

**Rust analogue**: Rust's `Iterator::fold` is *eager* by default — it forces every intermediate value. So `foldl'` is the closest analogue to what Rust's `fold` already gives you for free. Coming from Rust you can think of `foldl'` as "the normal fold" and `foldl` as "the lazy variant you don't want."

---

## 5. Reimplementing what you already know

Almost every list-consumer in the Prelude is a fold underneath. Once that clicks, a lot of code stops looking mysterious. From [src/Folds.hs](src/Folds.hs):

```haskell
sumL :: [Int] -> Int
sumL = foldl' (+) 0

productL :: [Int] -> Int
productL = foldl' (*) 1

maximumL :: [Int] -> Int
maximumL []     = error "maximumL: empty list"
maximumL (x:xs) = foldl' max x xs

reverseL :: [a] -> [a]
reverseL = foldl' (\acc x -> x : acc) []

countL :: (a -> Bool) -> [a] -> Int
countL p = foldl' (\acc x -> if p x then acc + 1 else acc) 0
```

Two patterns to notice:

- **The starting value is the identity for the operation.** `0` for sums (because `0 + x = x`), `1` for products, `[]` for list-building. When you write a fold, picking the identity is the first thing to think about.
- **`maximumL` cannot start from a free identity** because there is no `Int` smaller than every other `Int`. So we seed the accumulator with the head of the list and fold over the tail. This is why the Prelude's `maximum` is partial on the empty list — there is genuinely no good answer.

### A two-value accumulator

The accumulator does not have to be a single number. From the same file:

```haskell
runningSums :: [Int] -> [Int]
runningSums xs = reverseL (snd (foldl' step (0, []) xs))
  where
    step :: (Int, [Int]) -> Int -> (Int, [Int])
    step (total, acc) x =
      let total' = total + x
       in (total', total' : acc)
```

The accumulator is a tuple `(running_total, accumulated_list)` (Day 5). At each step the running total advances, and we cons it onto the result list. We `reverseL` at the end because we built the list backwards (cheaper than appending). This is the AoC pattern in miniature: when one number is not enough, fold over a richer accumulator.

---

## 6. Picking between them: the short rule

After all the explanation, the working rule fits in three lines:

| Fold | Use when | Why |
|------|----------|-----|
| `foldl'` | You are reducing to a strict value (sum, product, count, max, the final state of a record). | Constant stack, no thunk leak. Default for AoC. |
| `foldr` | You are producing a list (or any lazy structure), or your combining function can short-circuit (`&&`, `||`). | The lazy cons lets the result stream and lets `&&` / `||` skip the rest of the list. |
| `foldl` | Almost never. | Lazy in the accumulator with no laziness benefit on the result side. Real working Haskell uses `foldl'` instead. |

If you are unsure, start with `foldl'`. If your function builds a list and you want it to stream, switch to `foldr`. If you find yourself reaching for plain `foldl`, double-check that you actually want the laziness — most of the time you wrote the wrong import.

---

## 7. Walkthrough of the source files

`Folds.hs` is laid out in four parts that mirror this README:

1. **Hand-rolled** `sumExplicit` and `lengthExplicit` so you can compare the fold-based versions to the recursion they replace.
2. **`foldr`** versions — `sumR`, `lengthR`, `mapR`, `filterR`. Note how `mapR` and `filterR` cons onto the recursive result; that is the shape `foldr` was designed for.
3. **`foldl'`** versions — `sumL`, `productL`, `maximumL`, `reverseL`, `countL`. All of them use `foldl'` from `Data.List`.
4. A **two-value accumulator** example, `runningSums`, showing that the accumulator can be any type — here a tuple — when one number is not enough.

`Strict.hs` is a focused head-to-head. `sumStrict` uses `foldl'`; `sumLazy` uses plain `foldl`. The `main` action runs both on a tiny list (they agree) and then on `[1 .. 30,000,000]` (the strict one finishes, the lazy one stack-overflows). Run it and read the output:

```bash
cd tutorial/day6
runghc src/Strict.hs
```

You should see the strict run finish with a 16-digit answer, and then the lazy run print "About to call sumLazy big" and immediately die with `stack overflow`. That is the entire teaching point in a single run.

Run `Folds.hs` the same way:

```bash
runghc src/Folds.hs
```

Or load either in GHCi:

```bash
ghci src/Folds.hs
```

```
ghci> foldr (+) 0 [1, 2, 3]
6
ghci> foldl' (+) 0 [1 .. 100]
5050
ghci> foldr (\x acc -> if x > 0 then x : acc else acc) [] [-1, 2, -3, 4]
[2,4]
ghci> :t foldl'
foldl' :: Foldable t => (b -> a -> b) -> b -> t a -> b
```

(`Foldable t` in the GHCi response generalises `foldl'` from lists to any container that knows how to be folded — Day 7 introduces the type-class machinery that makes that work. For today, read it as `[a]`.)

---

## 8. Try it

Small exercises. Do them in GHCi with `Folds.hs` loaded.

1. Reimplement `sum` using `foldr` and again using `foldl'`. Confirm both give the same answer on `[1 .. 100]`.
2. Write `andAll :: [Bool] -> Bool` two ways: once with `foldr (&&) True` and once with `foldl' (&&) True`. Try each on `[True, True, False, undefined]`. Which one short-circuits, and which one diverges? (`undefined` is the Prelude's "evaluating me crashes" placeholder — perfect for showing whether evaluation reached a particular spot.)
3. Write `concatL :: [[a]] -> [a]` as a single fold. Pick `foldr` or `foldl'` and explain to yourself why.
4. Write `minMax :: [Int] -> (Int, Int)` that returns the smallest and largest element of a non-empty list, in a single pass. Use `foldl'` with a tuple accumulator like `runningSums`.
5. Time the difference for yourself. In a fresh GHCi session, run `:set +s` (turns on timing), then evaluate `foldl' (+) 0 [1 .. 1000000 :: Int]` and `sum [1 .. 1000000 :: Int]`. They should be similar — `sum` is `foldl' (+) 0` underneath.
6. Try to break it. Evaluate `foldl (+) 0 [1 .. 30000000 :: Int]` in GHCi. You should see a stack overflow. Now evaluate `foldl' (+) 0 [1 .. 30000000 :: Int]` — same answer, no crash.

---

## 9. What you should remember

- **A fold is "walk a list, combine elements with a function, starting from a seed value."** Two of the three Day-6 functions are folds: only the seed and the combiner change.
- **`foldr f z (x:xs) = f x (foldr f z xs)`** — replace every `(:)` with `f`, replace `[]` with `z`. The right tool when you are producing a list, or when the combiner can short-circuit.
- **`foldl' f z (x:xs)` evaluates `f z x` strictly** before recursing. Constant stack, no thunk chain. The default for AoC and any numeric reduction.
- **Plain `foldl` is almost always a bug.** It builds an unevaluated chain of operations and crashes the stack on long inputs. Reach for `foldl'` from `Data.List` instead.
- **The seed for a fold is usually the identity of the operation** — `0` for `+`, `1` for `*`, `[]` for cons. When there is no identity (max, min), seed with the head of the list and fold the tail.
- **The accumulator can be any type** — a tuple, a record, a `Map`. When one number is not enough, make the accumulator richer.
- **Rust analogue**: Rust's `Iterator::fold` is strict, like `foldl'`. Rust has no equivalent of `foldr` because Rust iterators are eager.

---

**Next**: Day 7 — your own `data` types and records. Stop bundling things into tuples and start naming your fields. Field accessors, `deriving (Show, Eq, Ord)`, and how custom types replace `Maybe`-of-tuples for problem state.
