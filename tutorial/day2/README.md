# Day 2 — Values, Types, and Functions

**Goal**: know Haskell's basic types by name, write pure functions with explicit type signatures, and understand what a multi-argument type signature actually means.

**Source file**: [src/Values.hs](src/Values.hs)

---

## 1. The basic types

Haskell's Prelude (the always-imported standard library) gives you these primitive types. Learn them by name — you will read them in every signature from now on.

| Type       | What it is                                           | Literal example      | Rust analogue          |
|------------|------------------------------------------------------|----------------------|------------------------|
| `Int`      | Machine-word signed integer (64-bit on modern hardware). Overflows silently. | `42`                | `i64`                  |
| `Integer`  | Arbitrary-precision integer. Never overflows.        | `2 ^ 100`            | `num_bigint::BigInt`   |
| `Double`   | 64-bit IEEE 754 floating point.                      | `3.14`               | `f64`                  |
| `Bool`     | `True` or `False`. Capitalised.                      | `True`               | `bool`                 |
| `Char`     | One Unicode codepoint. Single quotes.                | `'A'`                | `char`                 |
| `String`   | A list of `Char`, i.e. `[Char]`. Double quotes.      | `"hello"`            | `String` / `&str`      |

A few things worth internalising up front:

- **`Int` vs `Integer`**: if you do not have a reason to pick `Int`, pick `Int` anyway — it is what AoC puzzles almost always want. Reach for `Integer` when you know you will overflow, e.g. factorials, huge powers.
- **Capitalisation matters**: type names start with an uppercase letter (`Int`, `Bool`, `Char`). Constructor names like `True` / `False` are also uppercase. Ordinary value and function names start lowercase (`answer`, `square`). This is enforced by the compiler.
- **`String` is a list of `Char`**: so `++` (list concatenation) works on strings, and everything list-related from Day 3 will also work on strings.

---

## 2. Declaring a value

A top-level **binding** looks like this:

```haskell
answer :: Int
answer = 42
```

Two lines: the type signature, then the definition. In Haskell these are two pieces of one declaration — the signature on the first line, the body on the second.

Read it as:

> "`answer` has type `Int`. `answer` is defined to be `42`."

Things that are *not* happening here that you might expect:

- **No `let`, no `var`, no `const`**. Top-level bindings do not need a keyword.
- **No semicolons**. Haskell uses indentation and newlines.
- **No mutation**. `answer` is now permanently `42`. You cannot reassign it. There is no `answer = 43` later in the file. (Rust analogue: all top-level bindings are `const` / `static`.) *How do you write counters or `for` loops then? See the supplementary note [NO-MUTATION.md](NO-MUTATION.md) — runnable examples in [src/Counters.hs](src/Counters.hs).*

You can bind values of any type the same way:

```haskell
ready    :: Bool
ready    = True

letterA  :: Char
letterA  = 'A'

motto    :: String
motto    = "Types first, code second."
```

### Numeric literals are polymorphic

A subtle thing: `42` on its own does not have type `Int`. In GHCi:

```
ghci> :t 42
42 :: Num a => a
```

Read that as "`42` has type `a` for any `a` in the `Num` class" — i.e. any numeric type. The signature `answer :: Int` is what pins it down to `Int`. Without the signature, GHC would pick a default (usually `Integer`) and you might be surprised. **This is another reason to write signatures**: they resolve ambiguity, not just document.

You will see the same pattern for `3.14`: that is `Fractional a => a`, which is why `piApprox :: Double` in the source file needs the signature.

---

## 3. Defining a function

A function is a binding whose definition has parameters on the left-hand side of `=`:

```haskell
square :: Int -> Int
square x = x * x
```

Read it:

> "`square` has type `Int -> Int` — it takes an `Int` and returns an `Int`. Given a parameter called `x`, `square` is `x * x`."

No parentheses around the parameter, no `return` keyword, no braces. The whole body is a single expression.

Functions compose by juxtaposition — you call a function by writing it next to its argument, separated by a space:

```haskell
cube :: Int -> Int
cube x = x * square x
```

`square x` calls `square` on `x`. No parentheses. If you want to pass a more complicated expression, you need parentheses to group it:

```haskell
cube (x + 1)     -- call cube on (x + 1)
cube x + 1       -- NOT the same: this is (cube x) + 1
```

**Rust analogue**: function application has higher precedence than any operator, same as in Rust (`f(x) + 1` vs `f(x + 1)`). The only difference is that Haskell writes it `f x` instead of `f(x)`.

---

## 4. Multi-argument functions and currying

Here is the one piece of syntax that trips up every newcomer. Look at this signature:

```haskell
hypot :: Double -> Double -> Double
hypot a b = sqrt (a * a + b * b)
```

You read it as "takes two `Double`s and returns a `Double`." That reading is fine as a mental model. But the precise story is:

> `Double -> Double -> Double` is `Double -> (Double -> Double)`. The `->` associates to the right. `hypot` takes **one** `Double` and returns a **function** that takes a `Double` and returns a `Double`.

This is called **currying**, and it has one very practical consequence: you can **partially apply** any function. Call it with fewer arguments than its signature lists, and you get back a new function waiting for the rest.

```
ghci> :t hypot
hypot :: Double -> Double -> Double

ghci> :t hypot 3
hypot 3 :: Double -> Double        -- partial application, waiting for the second argument

ghci> (hypot 3) 4
5.0

ghci> hypot 3 4                    -- same thing. Application is left-associative.
5.0
```

So `hypot 3 4` is parsed as `(hypot 3) 4`. The `->` on the right, the application on the left. It sounds like a party trick now; by Day 6 it will be how you write half your code.

**Rust analogue**: Rust does not curry by default. The nearest equivalent is a closure that captures the first argument: `|b| hypot(3.0, b)`. You use that pattern constantly in Rust (`.map(|x| ...)`, `.filter(|x| ...)`). In Haskell you get it for free — just omit the arguments you want to fill in later.

---

## 5. Operators, infix, and backticks

Most operators in Haskell are ordinary functions with symbolic names. `+`, `-`, `*`, `/`, `==`, `&&`, `||`, `++` are all just functions.

You can ask for their types like anything else:

```
ghci> :t (+)
(+) :: Num a => a -> a -> a

ghci> :t (==)
(==) :: Eq a => a -> a -> Bool

ghci> :t (++)
(++) :: [a] -> [a] -> [a]
```

A few working rules:

- **Use parentheses to refer to an operator as a value**: `(+)` is the `+` function; `+` on its own is syntax.
- **Any two-argument function can be used infix with backticks**: `mod` is a function `Int -> Int -> Int`, and we can write either `mod 10 3` (prefix) or ``10 `mod` 3`` (infix). The two are identical.
- **Comparisons return `Bool`**: `n == 0`, `x < y`, `a /= b` (`/=` is "not equal", the Haskell spelling of `!=`).
- **`&&` and `||`** are boolean and/or, same as in C/Rust. `not` is prefix negation.

Example from the source file:

```haskell
isEven :: Int -> Bool
isEven n = n `mod` 2 == 0
```

Read it left-to-right: take `n`, take its remainder mod 2, compare to 0. Because `mod` is in backticks it is infix; because `==` has lower precedence than ``` `mod` ```, the whole expression parses as `(n `mod` 2) == 0`.

---

## 6. Reading a type signature, revisited

You now have enough vocabulary to read every signature we have used. Try these out loud:

```haskell
square    :: Int -> Int
--           takes an Int, returns an Int.

hypot     :: Double -> Double -> Double
--           takes a Double, then another Double, returns a Double.
--           (Or: takes a Double and returns a (Double -> Double).)

isEven    :: Int -> Bool
--           takes an Int, returns a Bool.

shout     :: String -> String
--           takes a String, returns a String.

show      :: Show a => a -> String
--           for any type 'a' that can be shown, takes an 'a' and returns
--           a String. The 'Show a =>' part is a type-class constraint —
--           we will see these properly on Day 7. For now read it as
--           "works for any printable type."

putStrLn  :: String -> IO ()
--           takes a String, returns an I/O action that prints it.
```

The `show` one is the first signature you have seen with a **constraint** (the `=>` part). Do not sweat it yet — it just means "this works for many types, not all types." You will meet constraints properly when you write your own types on Day 7.

---

## 7. Walkthrough of `Values.hs`

The source file defines six values and five functions, plus `main`. The pieces worth calling out:

```haskell
bignum :: Integer
bignum = 2 ^ (100 :: Int)
```

Two things happening here. `^` is integer exponentiation. Its type is `(^) :: (Num a, Integral b) => a -> b -> a` — the **base** can be any `Num`, the **exponent** must be an integral type. The `(100 :: Int)` is a **type annotation on an expression**: we are telling the compiler "treat this literal as an `Int`." Without it GHC would pick a default and might warn. You will see this pattern occasionally to disambiguate.

```haskell
cube x = x * square x
```

One function calling another. `square x` evaluates first (function application is tighter than `*`), then `x *` multiplies the result.

```haskell
isEven n = n `mod` 2 == 0
```

Discussed above — prefix function used infix with backticks.

```haskell
shout s = s ++ "!!!"
```

`++` is list concatenation. Because `String = [Char]`, this is just appending three exclamation marks to the list.

```haskell
main = do
  putStrLn ("answer     = " ++ show answer)
  ...
```

`do` sequences I/O actions, same as Day 1. The new piece is `show`: it converts a value to its `String` representation, which we then concatenate with the label and hand to `putStrLn`. `show 42` is `"42"`, `show True` is `"True"`, `show 'A'` is `"'A'"` (note the quotes are part of the shown form).

Run it:

```bash
cd tutorial/day2
runghc src/Values.hs
```

Expected output:

```
answer     = 42
bignum     = 1267650600228229401496703205376
piApprox   = 3.141592653589793
ready      = True
letterA    = 'A'
motto      = Types first, code second.
square 7   = 49
cube 3     = 27
hypot 3 4  = 5.0
isEven 10  = True
Day 2 complete!!!
```

Or load it in GHCi and poke at individual bindings:

```bash
ghci src/Values.hs
```

```
ghci> square 12
144
ghci> hypot 5 12
13.0
ghci> isEven 7
False
ghci> :t cube
cube :: Int -> Int
```

---

## 8. Try it

Small exercises. Do them in GHCi with `src/Values.hs` loaded.

1. Evaluate `2 ^ 62 :: Int` and then `2 ^ 63 :: Int`. What does the second one do? Now evaluate `2 ^ 63 :: Integer`. (This is the `Int` vs `Integer` lesson the hard way.)
2. Ask GHCi for the types of `(+)`, `(==)`, `mod`, `sqrt`, and `show` using `:t`. For each one, read the signature out loud.
3. Without changing the file, in GHCi evaluate `hypot 3`. What *is* that, and what is its type? Now evaluate `(hypot 3) 4`. Confirm it equals `hypot 3 4`.
4. Add a function `average :: Double -> Double -> Double` that returns the arithmetic mean of two `Double`s. Reload with `:r` and test it.
5. Add a function `isOdd :: Int -> Bool`. Try to define it **without** repeating the `mod` trick — use `not` and `isEven`.

---

## 9. What you should remember

- **Six basic types**: `Int`, `Integer`, `Double`, `Bool`, `Char`, `String`. Capitalised. Default to `Int` for AoC.
- **Numeric literals are polymorphic**: `42 :: Num a => a`. Type signatures pin them down.
- **Top-level bindings are immutable**. Two lines: the signature, then the definition.
- **Function application is by juxtaposition**: `f x`, not `f(x)`. Tighter than any operator.
- **`a -> b -> c` is curried**: it means `a -> (b -> c)`, so you can partially apply any function.
- **Backticks make any function infix**: ``n `mod` 2`` is the same as `mod n 2`.
- **`show :: Show a => a -> String`** converts a value to a printable string.

---

**Next**: Day 3 — lists, the list toolkit, and list comprehensions.
