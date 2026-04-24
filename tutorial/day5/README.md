# Day 5 — Tuples, `Maybe`, and `Either`

**Goal**: stop reaching for exceptions or sentinel values when a function might not have an answer. Use `Maybe` for "optional", `Either` for "value or error", and pattern matching from Day 4 to take them apart.

**Source files**:
- [src/Maybes.hs](src/Maybes.hs) — `Maybe` and the helpers you actually use.
- [src/Eithers.hs](src/Eithers.hs) — `Either` for failure with a message.

---

## 1. The problem

A function like "head of a list" or "parse this string as an integer" cannot succeed on every input. In an imperative language you have three usual options, all bad in their own way:

- **Crash** — `head []` throws an exception. Now every caller has to know.
- **Sentinel value** — return `-1` for "not found." Now every caller has to remember the sentinel and never accidentally use it as a real value.
- **Out-parameter** — `bool TryParse(string, out int)`. Two return values pretending to be one.

Haskell does the obvious thing: make the "might be missing" or "might fail" part *part of the return type*. The caller cannot ignore it, the compiler tracks it, and there are no special values to remember.

Two types do almost all the work:

- **`Maybe a`** for "an `a`, or nothing." Two constructors: `Nothing` and `Just a`.
- **`Either e a`** for "an `a`, or an error of type `e`." Two constructors: `Left e` and `Right a`.

**Rust analogue**: `Maybe a` is `Option<T>`. `Either e a` is `Result<T, E>` (with the order swapped — Rust puts the success type first; Haskell puts the *error* type first because of how type-class instances work, more on that on Day 7).

---

## 2. Tuples, briefly

You already saw tuples on Day 4 (`(x, _)`, `(a, b)`). They are the simplest "more than one value" container, and they are everywhere in AoC: coordinates `(x, y)`, key-value pairs `(k, v)`, results that bundle two answers `(part1, part2)`.

Three things to know:

- **Tuples have a fixed length and per-position types.** `(Int, String)` is a different type from `(String, Int)` and from `(Int, String, Bool)`.
- **The Prelude gives you `fst` and `snd` for pairs.** `fst (1, "x") = 1`, `snd (1, "x") = "x"`. For triples or larger, pattern-match.
- **Pattern-match instead of indexing.** There is no `t.0` or `t[0]` for tuples — you destructure them with a pattern: `let (x, y) = pt in …`.

```
ghci> :t (1, "x")
(1, "x") :: (Num a) => (a, String)

ghci> fst (1, "x")
1

ghci> let (x, y) = (3, 4) in x * y
12
```

Tuples are good for small, ad-hoc bundles. For anything with more structure or a real meaning, you will want a `data` type — that is Day 7.

---

## 3. `Maybe` — "an `a`, or nothing"

`Maybe` is defined in the Prelude (you do not need to import it):

```haskell
data Maybe a = Nothing | Just a
```

That one line says: a `Maybe a` is either the constructor `Nothing` (no value) or the constructor `Just` applied to a value of type `a`. The vertical bar reads "or."

You build `Maybe` values with the constructors:

```haskell
safeHead :: [a] -> Maybe a
safeHead []    = Nothing
safeHead (x:_) = Just x
```

You take them apart with pattern matching, exactly the same way you took apart lists on Day 4:

```haskell
withDefault :: a -> Maybe a -> a
withDefault def Nothing  = def
withDefault _   (Just x) = x
```

Read this as "given a default, if the `Maybe` is `Nothing` return the default; if it is `Just x`, return `x`." The compiler checks both cases — if you forget one, it warns you.

**Rust analogue**: `Option<T>` is `enum Option<T> { None, Some(T) }`. The Haskell `Just` is Rust's `Some`; `Nothing` is Rust's `None`. `match` on Rust's `Option` is the same shape as pattern matching on `Maybe`.

### The helpers you will actually use

`Data.Maybe` ships these three helpers. You will use them constantly; learn them now and you can stop hand-rolling pattern matches for the easy cases.

```haskell
fromMaybe :: a -> Maybe a -> a
-- fromMaybe 0 (Just 7) = 7
-- fromMaybe 0 Nothing  = 0
```

`fromMaybe` is the function we hand-rolled as `withDefault`. Use it any time you want to fall back to a default.

```haskell
maybe :: b -> (a -> b) -> Maybe a -> b
-- maybe "no" show (Just 42) = "42"
-- maybe "no" show Nothing   = "no"
```

`maybe` is `fromMaybe` plus a function: it transforms the `Just` case and supplies a default for `Nothing`, in one call. Read it as "if `Nothing`, this default; if `Just x`, this function applied to `x`."

```haskell
mapMaybe :: (a -> Maybe b) -> [a] -> [b]
-- mapMaybe parseDigit "a1b2c3" = [1, 2, 3]
```

`mapMaybe` walks a list, applies a `Maybe`-returning function to each element, and keeps only the `Just`s. Whenever you find yourself writing "try to parse each item, drop the failures" — that is `mapMaybe`.

### When the next step depends on the previous one

Sometimes you have several `Maybe`-returning steps where each one only makes sense if the previous one succeeded. The hand-rolled version is a chain of pattern matches:

```haskell
firstValidQuotient :: [(Int, Int)] -> Maybe Int
firstValidQuotient []         = Nothing
firstValidQuotient ((n,d):xs) =
  case safeDiv n d of
    Just q  -> Just q
    Nothing -> firstValidQuotient xs
```

This works, but if you stack three or four of these the indentation grows. On Day 7/8 you will see `>>=` ("bind") and `do` notation for `Maybe`, which collapse the chain. For today, the explicit `case` is the honest version.

---

## 4. `Either` — "an `a`, or an error"

`Either` is the same idea as `Maybe` with one extra piece: when something fails, you carry information about *why*.

```haskell
data Either e a = Left e | Right a
```

By convention:

- `Right` is the success case, holding the answer.
- `Left` is the failure case, holding the error.

There is a memory trick: "right" sounds like "correct." That is the actual reason the convention is this way around.

```haskell
safeDivE :: Int -> Int -> Either String Int
safeDivE _ 0 = Left "division by zero"
safeDivE n d = Right (n `div` d)
```

You take it apart the same way:

```haskell
describe :: Either String Int -> String
describe (Left err) = "error: " ++ err
describe (Right n)  = "ok: "    ++ show n
```

**Rust analogue**: `Result<T, E>` is `enum Result<T, E> { Ok(T), Err(E) }`. The Haskell `Right` is Rust's `Ok`; `Left` is `Err`. The type-parameter order is swapped — Rust writes `Result<T, E>` (success first), Haskell writes `Either e a` (error first). Same idea, same uses; just remember the order flips.

### Why the error type comes first in Haskell

You can `fmap` over an `Either e` to transform the success value, and the type-class machinery wants the "varying" type parameter to be the last one. So `Either e a` lets you say "a thing that maps over its `a`," with the error type pinned. You will see this on Day 7 when type classes show up properly. For now: just remember the convention.

### Pipelining

Same problem as `Maybe`: chained `Either`-returning steps stack their pattern matches. The hand-rolled version is:

```haskell
divideStrings :: String -> String -> Either String Int
divideStrings a b =
  case parseInt a of
    Left err -> Left err
    Right n  ->
      case parseInt b of
        Left err -> Left err
        Right d  -> safeDivE n d
```

The `Left err -> Left err` lines are the "first failure wins" pattern. Day 7's `do` notation makes this disappear. For today, you can see why people wanted it.

---

## 5. `Maybe` vs `Either` — when to use which

The decision is straightforward:

- **Use `Maybe`** when there is exactly one failure mode and the caller does not need a message. "Is this key in the map?" "What is the head of this list?"
- **Use `Either`** when failure can happen for several reasons and the caller (or the human running the program) wants to know which. "Did this parse succeed, and if not, which character was bad?" "Did this rule fire, and if not, which precondition was violated?"

For AoC 2018 specifically: `Maybe` covers almost everything, because failure usually means "this branch of the search did not pan out." `Either` shows up when you write input parsers that need to surface errors during development.

A common newcomer mistake: using `Either String a` when `Maybe a` would do. If the only thing the caller does with the error is `fromMaybe`-style fallback, the message is wasted — use `Maybe`.

---

## 6. Walkthrough of the source files

`Maybes.hs` builds the patterns above. The pieces worth calling out:

```haskell
parseDigit :: Char -> Maybe Int
parseDigit c
  | c >= '0' && c <= '9' = Just (fromEnum c - fromEnum '0')
  | otherwise            = Nothing
```

Guards (Day 4) plus `Maybe` is the canonical "validate then return" shape. `fromEnum` turns a `Char` into its 'Int' codepoint; subtracting `fromEnum '0'` gives the digit's numeric value.

```haskell
sumDigits :: String -> Int
sumDigits s = sum (mapMaybe parseDigit s)
```

`mapMaybe parseDigit` walks the string, parsing each character and discarding the non-digits. `sum` adds the surviving values. This is the AoC pattern in miniature: filter and parse in one pass.

`Eithers.hs` is the same idea with messages:

```haskell
parseInt :: String -> Either String Int
parseInt ""                             = Left "empty input"
parseInt s
  | all (`elem` "0123456789") s = Right (read s)
  | otherwise                   = Left ("not a number: " ++ s)
```

Two failure modes (empty, non-digits), each with its own message. `read` is the Prelude's "parse this string into whatever type the context demands"; we have already validated the input, so it is safe here.

Run them:

```bash
cd tutorial/day5
runghc src/Maybes.hs
runghc src/Eithers.hs
```

Or load either in GHCi:

```bash
ghci src/Maybes.hs
```

```
ghci> safeDiv 10 3
Just 3
ghci> safeDiv 10 0
Nothing
ghci> mapMaybe parseDigit "a1b2c3"
[1,2,3]
ghci> :t fromMaybe
fromMaybe :: a -> Maybe a -> a
```

---

## 7. Try it

Small exercises. Do them in GHCi.

1. With `Maybes.hs` loaded, evaluate `safeHead []`, `safeHead [42]`, and `safeDiv 100 7`. Confirm the types and values match what you expect.
2. Define `safeLast :: [a] -> Maybe a` (the last element if the list is non-empty). Three patterns: `[]`, `[x]`, `(_:xs)`.
3. Define `safeIndex :: Int -> [a] -> Maybe a` that returns the `i`-th element of a list, or `Nothing` if `i` is out of range. Use guards and recursion.
4. Use `mapMaybe` to keep only the positive numbers from a `[Int]`. (Hint: write a tiny helper `keepPositive :: Int -> Maybe Int`.)
5. With `Eithers.hs` loaded, evaluate `divideStrings "10" "2"`, `divideStrings "10" "0"`, and `divideStrings "10" "abc"`. Note which error message wins in each case.
6. Add a function `safeSqrt :: Double -> Either String Double` that returns `Left "negative input"` for negative numbers and `Right` of the square root otherwise. (`sqrt` is in the Prelude.)

---

## 8. What you should remember

- **`Maybe a = Nothing | Just a`** — "an `a`, or nothing." Use when there is one failure mode and no message.
- **`Either e a = Left e | Right a`** — "an `a`, or an error of type `e`." `Right` is success; `Left` is failure. Use when the caller wants to know *why*.
- **You take both apart with pattern matching**, exactly the same way as lists.
- **`fromMaybe`, `maybe`, and `mapMaybe`** cover most of the day-to-day uses of `Maybe`. Learn them now and stop hand-rolling.
- **Chains of `Maybe` or `Either` operations** can be written with nested `case` today; on Day 7 you will see `do` notation collapse them into a flat sequence.
- **Tuples** (`(a, b)`) are the simplest "two things" container — use them for small, ad-hoc bundles. Anything with structure deserves a `data` type (Day 7).
- **Rust analogues**: `Maybe` is `Option`; `Either e a` is `Result<a, e>` (note the swapped parameter order).

---

**Next**: Day 6 — folds. `foldr`, `foldl`, `foldl'`. Reducing a list to a value, why `foldl'` is the default, and why `foldl` is almost always a bug.
