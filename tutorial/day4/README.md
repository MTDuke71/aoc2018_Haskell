# Day 4 — Pattern Matching, Guards, `where`, and `let`

**Goal**: stop writing `if/else` chains. Use pattern matching to dispatch on the *shape* of a value, guards to dispatch on a *condition*, and `where`/`let` to name the helper values you compute along the way.

**Source file**: [src/Patterns.hs](src/Patterns.hs)

---

## 1. Why bother — the if/else problem

A function like "factorial" written with `if` looks fine:

```haskell
factorial :: Int -> Int
factorial n = if n == 0 then 1 else n * factorial (n - 1)
```

…until you have three or four cases. Then you get the `if … then … else if … then … else …` ladder, which Haskell can express but does not want to. The language gives you two better tools:

- **Pattern matching** when the case split follows the *structure* of the input (zero vs non-zero, empty list vs non-empty list, `Nothing` vs `Just x`).
- **Guards** when the case split follows a *boolean condition* (`n < 0`, `x == y`, `length xs > 10`).

Most real Haskell functions use one or both. After today, `if` is reserved for one-shot two-branch decisions inside a larger expression.

---

## 2. Pattern matching on values

A function can have **multiple equations**. The compiler tries them top to bottom and uses the first one whose left-hand side matches the call.

```haskell
factorial :: Int -> Int
factorial 0 = 1
factorial n = n * factorial (n - 1)
```

Read it as:

> "`factorial 0` is `1`. For any other `n`, `factorial n` is `n * factorial (n - 1)`."

Two equations, one function. The literal `0` on the left is a **pattern** — it only matches the value `0`. The lowercase `n` is also a pattern, but a *variable* pattern: it matches anything and binds the matched value to the name `n`.

Order matters. If you wrote them in the other order, `factorial n` would match `0` first and recurse forever. The compiler will warn you about overlapping patterns, but it will still let you ship them — read the warnings.

`fib` shows the same shape with three equations:

```haskell
fib :: Int -> Int
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)
```

**Rust analogue**: this is exactly `match n { 0 => 1, n => n * factorial(n - 1) }`, except in Haskell the `match` is the function's left-hand side itself. No keyword needed.

---

## 3. Pattern matching on tuples

Tuples have a fixed shape, and you can pull them apart by writing the shape on the left of `=`:

```haskell
fstOf :: (a, b) -> a
fstOf (x, _) = x

sumPair :: (Int, Int) -> Int
sumPair (a, b) = a + b
```

Two new pieces:

- **`_` is the wildcard pattern.** It matches anything and does *not* bind a name. Use it when you do not care about that part of the value.
- **The pattern on the left is a real `(a, b)` tuple**, not a parameter list. The single argument *is* a pair, and we are destructuring it on the way in.

You will use this constantly: AoC input that comes as `(x, y)` coordinates, intermediate values that you produce as a pair, etc.

---

## 4. Pattern matching on lists

This is the one to internalise. Every list is one of two things:

- `[]` — the empty list.
- `x : xs` — a head `x` glued onto a tail `xs`. The `:` is the list **cons** operator.

So every list-consuming function has the same skeleton:

```haskell
myLength :: [a] -> Int
myLength []     = 0
myLength (_:xs) = 1 + myLength xs
```

> "The length of the empty list is 0. The length of a list with *some* head and a tail `xs` is one plus the length of `xs`."

The parentheses around `(_:xs)` are required — without them the compiler would parse it as two separate patterns `_` and `:xs`. The wildcard `_` says "we do not need the head; only the tail."

Same shape, summing:

```haskell
mySum :: [Int] -> Int
mySum []     = 0
mySum (x:xs) = x + mySum xs
```

You can combine the cons pattern with literal patterns to peek deeper:

```haskell
describeList :: [Int] -> String
describeList []      = "empty"
describeList [_]     = "singleton"
describeList (_:_:_) = "two or more"
```

`[_]` matches a list with exactly one element. `(_:_:_)` matches a list with at least two elements. You will see all three forms in real code.

**Rust analogue**: there is no built-in head/tail pattern for `Vec` in Rust. The closest is `slice::split_first()` returning `Option<(&T, &[T])>`. Haskell lists are linked lists, which is why `(x:xs)` is a natural pattern — it costs nothing.

---

## 5. Wildcard `_` and what it really means

`_` is special: it is the only pattern that matches anything *without* binding a name. You use it when:

- You need to enforce the *shape* of a value but do not care about a particular component (`(x, _)` to take only the first of a pair).
- You need a catch-all pattern but will not use the value (`(_:xs)` because the head is irrelevant).
- You want GHC to warn you that you would otherwise leave a variable unused.

A common newcomer mistake: writing `factorial _ = 1` thinking it is a "default case." It is — it is just a default that ignores its argument and always returns `1`. If it appears before `factorial n = …`, every call returns `1`. Order matters.

---

## 6. Guards — dispatching on a condition

Guards are the right tool when the case split is *not* about the shape of the input but about a boolean condition over it.

```haskell
classify :: Int -> String
classify n
  | n < 0     = "negative"
  | n == 0    = "zero"
  | n < 10    = "small"
  | n < 100   = "medium"
  | otherwise = "large"
```

Read each `|` as "such that." `classify n`, such that `n < 0`, is `"negative"`; otherwise such that `n == 0`, is `"zero"`; …. The guards are tried top to bottom; the first one whose condition is `True` wins.

Two notes:

- **`otherwise` is just `True`.** Look it up in the Prelude and you will see `otherwise = True`. It is conventionally used as the final catch-all because it reads better than a bare `True`.
- **Guards and patterns combine.** You can guard a single equation, and you can have several equations each with their own guards. The first matching pattern is chosen, then its guards are evaluated in order; if none match, GHC falls through to the next equation.

```haskell
describeList :: [Int] -> String
describeList []  = "empty"
describeList [_] = "singleton"
describeList xs
  | sum xs > 0 = "non-empty, positive sum"
  | otherwise  = "non-empty, non-positive sum"
```

**Rust analogue**: guards are Rust's `match` arm guards: `n if n < 0 => "negative"`. Same idea, slightly tidier syntax.

---

## 7. `where` — local definitions, body first

When the body of a function uses one or two helper expressions, name them. The Haskell-idiomatic place to put them is a **`where` clause**, after the body:

```haskell
rms :: [Double] -> Double
rms xs = sqrt (sumOfSquares / n)
  where
    sumOfSquares = sum squared
    squared      = map (\x -> x * x) xs
    n            = fromIntegral (length xs)
```

Three things to notice:

- **The body comes first.** You read `rms` top-down: square root of the sum of squares divided by the count. Then if you care, you read the helpers below.
- **The helpers can refer to each other and to the function's parameters.** `squared` uses `xs`. `sumOfSquares` uses `squared`. Order in the `where` block does not matter — they are mutually visible.
- **Indentation defines the block.** Everything indented under `where` is part of the same `where` clause. This is the same indentation rule as the body of a `do` block.

`where` clauses are the cleanest place to compute a value once and reuse it across every guard of an equation:

```haskell
bmi :: Double -> Double -> String
bmi weightKg heightM
  | b < 18.5  = "underweight"
  | b < 25.0  = "normal"
  | b < 30.0  = "overweight"
  | otherwise = "obese"
  where
    b = weightKg / (heightM * heightM)
```

`b` is computed once and visible in every guard. Without `where` you would either compute it four times or pull the function apart with `let`.

**Rust analogue**: the closest thing is a `let` at the top of a function body. Haskell's `where` is unusual in that the helpers come *after* the use site — once you get used to it, top-down reading feels nicer because you see the high-level shape first and zoom in only if you need to.

---

## 8. `let … in …` — local definitions, helper first

`let` is the other way to introduce local names. It is an **expression**, not a statement:

```haskell
cylinderVolume :: Double -> Double -> Double
cylinderVolume r h =
  let area = pi * r * r
   in area * h
```

Read it as: "let `area` be `pi * r * r` in `area * h`." The whole `let … in …` is itself a value (here a `Double`), so it can appear anywhere a value can.

Practical rule of thumb:

- **`where`** for helpers shared across multiple guards or across the whole function body, when you want top-down reading.
- **`let`** for helpers used in a single expression, especially inside another expression. Also the only choice inside a `do` block (where it is written without `in`):

```haskell
main :: IO ()
main = do
  let greeting = "Hello, " ++ name
  putStrLn greeting
  where
    name = "Matt"
```

Both `let` and `where` exist because Haskellers wanted both reading orders, and the language designers refused to pick one. Use whichever makes the body read better.

---

## 9. `case … of` — pattern matching as an expression

The function-equations form is the most common place you pattern-match, but sometimes you want to match on a sub-expression without giving it a name. `case … of` is pattern matching as an inline expression:

```haskell
firstOrDefault :: a -> [a] -> a
firstOrDefault def xs =
  case xs of
    []    -> def
    (x:_) -> x
```

This is the same pattern matching you have already seen, just written as an expression. Each branch is `pattern -> expression`. The branches are tried top to bottom; the whole `case` evaluates to the matching branch's right-hand side.

`case` is the right tool when:

- You want to match on a value built up earlier in the body (e.g. the result of `lookup k m`).
- You want to match deep inside a `do` block.
- The function only matches in one place and adding a separate equation would feel like overkill.

When you can use either, prefer multiple equations on the function — it usually reads better.

---

## 10. Walkthrough of `Patterns.hs`

The source file demonstrates each construct above with one tiny example. The pieces worth calling out:

```haskell
factorial 0 = 1
factorial n = n * factorial (n - 1)
```

Two equations, no `if`. The literal pattern `0` is a real pattern, not a comparison.

```haskell
safeHead :: [a] -> Maybe a
safeHead []    = Nothing
safeHead (x:_) = Just x
```

A function that cannot crash: empty list returns `Nothing`, non-empty returns `Just` the head. We will use `Maybe` properly on Day 5; for now read it as "either nothing, or one value."

```haskell
classify n
  | n < 0     = "negative"
  | otherwise = "large"
```

The guard form. `otherwise` is the conventional final catch-all.

```haskell
rms xs = sqrt (sumOfSquares / n)
  where
    sumOfSquares = sum squared
    squared      = map (\x -> x * x) xs
    n            = fromIntegral (length xs)
```

The `where` form. `\x -> x * x` is a **lambda**: an anonymous function that takes `x` and returns `x * x`. You will see lambdas constantly with `map` and `filter`. `fromIntegral` converts an integral type (`Int`) into any other numeric type — here, into `Double` so the division works.

```haskell
average []  = Nothing
average xs  = Just (total / count)
  where
    total = sum xs
    count = fromIntegral (length xs)
```

Pattern matching for the empty case, `where` for the helpers in the non-empty case. This is the canonical "safe average" you will write for AoC inputs that might be empty.

Run it:

```bash
cd tutorial/day4
runghc src/Patterns.hs
```

Expected output (truncated):

```
factorial 6           = 720
fib 10                = 55
fstOf (1, 'x')        = 1
sumPair (3, 4)        = 7
myLength [1..5]       = 5
mySum [1..10]         = 55
safeHead []           = Nothing
safeHead [42]         = Just 42
classify (-3)         = negative
classify 0            = zero
classify 7            = small
classify 250          = large
describeList []       = empty
describeList [1,2,3]  = non-empty, positive sum
describeList [1,-5]   = non-empty, non-positive sum
rms [1,2,3,4,5]       = 3.3166247903554
bmi 70 1.75           = normal
cylinderVolume 2 5    = 62.83185307179586
firstOrDefault 0 []   = 0
firstOrDefault 0 [9]  = 9
average []            = Nothing
average [1,2,3,4]     = Just 2.5
Day 4 complete!!!
```

Or load it in GHCi and poke at individual functions:

```bash
ghci src/Patterns.hs
```

```
ghci> factorial 10
3628800
ghci> safeHead [1,2,3]
Just 1
ghci> classify 42
"medium"
ghci> :t average
average :: [Double] -> Maybe Double
```

---

## 11. Try it

Small exercises. Do them in GHCi with `src/Patterns.hs` loaded.

1. Rewrite `factorial` using a guard instead of pattern matching. Reload with `:r`. Convince yourself it behaves identically.
2. Define `myProduct :: [Int] -> Int` that multiplies every element of a list. Empty list returns `1`. Use the same shape as `mySum`.
3. Define `lastSafe :: [a] -> Maybe a` that returns the last element of a list as a `Maybe`. Three patterns: `[]`, `[x]`, and `(_:xs)`.
4. Rewrite `bmi` to use `let … in` instead of `where`. Which version do you prefer?
5. Define `signum' :: Int -> Int` that returns `-1` for negatives, `0` for zero, and `1` for positives. Use guards. (`signum` already exists in the Prelude — call yours `signum'` to avoid the clash.)
6. Define `describeTriangle :: Int -> Int -> Int -> String` that takes three side lengths and returns `"equilateral"`, `"isosceles"`, `"scalene"`, or `"not a triangle"`. Use guards plus a `where` clause for the triangle-inequality check.

---

## 12. What you should remember

- **Multiple equations per function** — the compiler tries them top to bottom and the first matching pattern wins.
- **Patterns describe shape**: literals (`0`, `'A'`), variables (`n`, `x`), wildcards (`_`), tuples (`(a, b)`), and lists (`[]`, `(x:xs)`, `[x]`).
- **`(x:xs)` is the bread and butter of list functions.** Empty list base case, cons recursive case. You will write it a hundred times.
- **Guards (`|`) dispatch on a boolean condition.** `otherwise` is just a friendly name for `True`.
- **`where` clauses** put helpers after the body — top-down reading. Visible across all guards of one equation.
- **`let … in …`** introduces helpers before the body — useful inside a single expression or inside a `do` block.
- **`case … of`** is pattern matching as an expression, useful when you want to match on a sub-expression without giving it a name.
- **`if` is now reserved** for one-shot, two-branch decisions inside a larger expression. Everything else is patterns + guards.

---

**Next**: Day 5 — tuples (already used here), `Maybe`, and `Either`. Returning "maybe a value" and "a value or an error" without exceptions.
