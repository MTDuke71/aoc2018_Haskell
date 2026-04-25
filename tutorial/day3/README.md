# Day 3 — Lists and the List Toolkit

**Goal**: read and write list types, build lists with literals / ranges / `:` / `++`, and use the core Prelude list functions — `map`, `filter`, `sum`, `length`, `lines`, `words` — plus list comprehensions.

**Source file**: [src/Lists.hs](src/Lists.hs)

---

## 1. What a list is

A list in Haskell is a **singly-linked, immutable, homogeneous** sequence. "Homogeneous" means every element has the same type.

The type is written with square brackets around the element type:

| Haskell type | Meaning                        | Rust analogue           |
|--------------|--------------------------------|-------------------------|
| `[Int]`      | list of `Int`                  | `Vec<i64>` / `&[i64]`   |
| `[String]`   | list of `String`               | `Vec<String>`           |
| `[[Int]]`    | list of lists of `Int`         | `Vec<Vec<i64>>`         |
| `String`     | alias for `[Char]`             | `String` / `&str`       |

Three things that make Haskell lists feel different from Rust `Vec`:

- **Immutable**. There is no "mutate in place." Every "update" returns a new list.
- **Linked list under the hood**, not a contiguous buffer. `length xs` is *O(n)*, `xs !! i` (indexing) is *O(i)*. Don't use them as random-access arrays — we will graduate to `Data.Vector` around Day 7 when it matters.
- **Can be infinite**. Because Haskell is lazy, you can build `[1..]` and take the first few elements — nothing actually computes the rest. More on laziness around Day 6.

For everything on Day 3 you can pretend a list is just a Rust iterator that also remembers its elements.

---

## 2. Building lists: literals, cons, append

Three ways to make a list:

```haskell
primes    = [2, 3, 5, 7, 11, 13]     -- literal
withZero  = 0 : primes                -- cons: prepend one element
allDigits = [0..4] ++ [5..9]          -- append two lists
```

The two operators to memorise:

| Operator | Type                  | What it does                              |
|----------|-----------------------|-------------------------------------------|
| `(:)`    | `a -> [a] -> [a]`     | "cons" — prepend **one element** to a list |
| `(++)`   | `[a] -> [a] -> [a]`   | append **two lists**                       |

Notice the asymmetry: `:` has an **element** on the left, `++` has a **list** on the left. Writing `1 : 2 : 3 : []` builds `[1, 2, 3]` one element at a time, from the right. In fact every list literal `[1, 2, 3]` is just sugar for exactly that expression.

**Rust analogue**:
- `(:)` ≈ `std::iter::once(x).chain(xs)` — conceptually, "one element followed by the rest."
- `(++)` ≈ `[xs, ys].concat()` for `Vec`, or `xs.chain(ys)` for iterators.

`++` walks the whole left list to glue the right one on the end. That makes `xs ++ ys` *O(length xs)*. If you catch yourself repeatedly appending to a growing list — `acc ++ [x]` — you are writing *O(n²)* code. The idiomatic fix is to cons onto the front and reverse at the end, or use a fold (Day 6).

---

## 3. Ranges

Haskell has a very readable sugar for arithmetic progressions:

```haskell
[1 .. 10]       -- [1,2,3,4,5,6,7,8,9,10]
[2, 4 .. 20]    -- [2,4,6,8,10,12,14,16,18,20]   step = 4 - 2 = 2
[10, 9 .. 1]    -- [10,9,8,7,6,5,4,3,2,1]        step = -1
['a' .. 'z']    -- "abcdefghijklmnopqrstuvwxyz"  ranges work on Char too
```

- `[low .. high]` — inclusive on both ends. Empty if `low > high`.
- `[first, second .. last]` — the compiler infers the step from the first two elements.
- Works on any type in the `Enum` class: `Int`, `Integer`, `Char`, and more.

**Gotcha**: `[1.0, 1.1 .. 2.0]` works but floating-point rounding makes the last element unreliable. Stick to `Int` / `Integer` / `Char` ranges.

**Rust analogue**:
- `[1 .. 10]` ≈ `1..=10` (note: Haskell ranges are *inclusive* on the high end, same as Rust's `..=`).
- `[2, 4 .. 20]` ≈ `(2..=20).step_by(2)`.

---

## 4. Simple queries

These all take a list and return a summary:

| Function  | Type                 | Notes                                                |
|-----------|----------------------|------------------------------------------------------|
| `length`  | `[a] -> Int`         | *O(n)*. Walks the list.                              |
| `null`    | `[a] -> Bool`        | *O(1)*. "Is the list empty?" Prefer over `length xs == 0`. |
| `reverse` | `[a] -> [a]`         | *O(n)*. Returns a new list.                          |
| `head`    | `[a] -> a`           | First element. **Crashes on `[]`.**                  |
| `last`    | `[a] -> a`           | Last element. *O(n)* **and** crashes on `[]`.        |

`head` and `last` are **partial** — they throw a runtime error on the empty list. For AoC early on, we will use them freely and accept the risk. On Day 5 we will meet `Maybe` and see the total alternatives (`listToMaybe`, pattern matching).

**Rust analogue**: `xs.len()`, `xs.is_empty()`, `xs.iter().rev().collect()`, `xs[0]` (panics same as `head`), `xs.last().unwrap()`.

> Heads-up on signatures: ask GHCi `:t length` and you will see `length :: Foldable t => t a -> Int`, not `[a] -> Int`. That is because the Prelude generalised these functions to work on any *foldable* container, not just lists. For now, read `Foldable t => t a` as "a list or something list-like"; we will meet `Foldable` properly later.

---

## 5. Numeric reductions

Collapse a list to a single value:

| Function   | Type                  | Notes                          |
|------------|-----------------------|--------------------------------|
| `sum`      | `Num a => [a] -> a`   | Zero for the empty list.       |
| `product`  | `Num a => [a] -> a`   | One for the empty list.        |
| `minimum`  | `Ord a => [a] -> a`   | Crashes on `[]`.               |
| `maximum`  | `Ord a => [a] -> a`   | Crashes on `[]`.               |

The `Num a =>` and `Ord a =>` parts are *type-class constraints*: "for any type `a` in the `Num` class" — i.e. any numeric type. You already saw `Show a =>` on Day 2; this is the same idea. Day 7 covers type classes properly.

**Rust analogue**: `xs.iter().sum()`, `xs.iter().product()`, `xs.iter().min().unwrap()`, `xs.iter().max().unwrap()`.

---

## 6. `map` — transform every element

```haskell
map :: (a -> b) -> [a] -> [b]
```

`map f xs` returns a new list with `f` applied to every element. Same length as the input.

From the source file:

```haskell
doubled = map (* 2) primes          -- [4, 6, 10, 14, 22, 26]
squared = map square primes         -- where  square x = x * x
shoutedDigits = map show allDigits  -- ["0","1","2","3",...]
```

### Operator sections

`(* 2)` is a brand-new piece of syntax. When you put one argument of a binary operator inside the parentheses alongside the operator, you get back a function with the *other* argument still to be filled in. These are called **sections**:

```haskell
(* 2)    ==  \x -> x * 2
(10 -)   ==  \x -> 10 - x
(> 5)    ==  \x -> x > 5
(5 >)    ==  \x -> 5 > x
```

**Gotcha**: `(- 5)` is *not* a section — it is the negative number `-5`. To get the function `\x -> x - 5`, use `subtract 5` (a named Prelude function that exists precisely to dodge this corner).

**Rust analogue**: there is no direct equivalent. You write the closure by hand: `.map(|x| x * 2)`. Sections are a Haskell-only convenience — worth getting comfortable with, because you will read them in every piece of Haskell you meet.

---

## 7. `filter` — keep the matches

```haskell
filter :: (a -> Bool) -> [a] -> [a]
```

`filter p xs` returns the sub-list of elements for which `p x` is `True`. The predicate is any function returning `Bool`:

```haskell
evenPrimes = filter even primes     -- [2]
bigPrimes  = filter (> 5) primes    -- [7, 11, 13]
```

`even`, `odd`, `(> 0)`, `(< n)` — predicates are the most common use of sections.

**Rust analogue**: `xs.iter().filter(|&x| x > 5).collect()`.

---

## 8. Strings are lists: `lines` and `words`

Since `String = [Char]`, every list function on this page works on strings. The Prelude also has two string-splitters that come up constantly when parsing puzzle input:

```haskell
lines :: String -> [String]   -- split on '\n'
words :: String -> [String]   -- split on any run of whitespace
```

From the source file:

```haskell
sampleText :: String
sampleText = "one two three\nfour five\nsix"

textLines      = lines sampleText             -- ["one two three", "four five", "six"]
firstLineWords = words (head textLines)       -- ["one", "two", "three"]
```

Their inverses also exist: `unlines :: [String] -> String` adds a `\n` after each, `unwords :: [String] -> String` joins with a single space. You will reach for `lines` in nearly every AoC puzzle — "split input on newlines" is the universal first parsing step.

**Rust analogue**: `s.lines().collect::<Vec<_>>()` and `s.split_whitespace().collect::<Vec<_>>()`.

---

## 9. List comprehensions

A list comprehension is a compact notation for "build a list by drawing values from other lists and filtering them." The shape is

```haskell
[ expression | generator, guard, generator, guard, ... ]
```

Read it as set-builder notation: *"the list of `expression` such that `generator` and `guard` and …"*.

```haskell
squaresTo10 = [ x * x | x <- [1 .. 10] ]
              -- [1, 4, 9, 16, 25, 36, 49, 64, 81, 100]

evenSquares = [ x * x | x <- [1 .. 10], even x ]
              -- [4, 16, 36, 64, 100]

pairs       = [ (x, y) | x <- [1 .. 3], y <- [1 .. 3] ]
              -- [(1,1),(1,2),(1,3),(2,1),(2,2),(2,3),(3,1),(3,2),(3,3)]
```

The parts:

- `x <- [1 .. 10]` is a **generator** — "for each `x` drawn from `[1..10]`." The arrow is a left arrow (`<-`), not the function-type arrow.
- `even x` (no arrow) is a **guard** — a `Bool` expression; only rows where it holds are kept.
- Multiple generators compose like nested loops: the rightmost varies fastest.

A comprehension is equivalent to a combination of `map` and `filter` and nesting. This one is all three:

```haskell
evenSquares == map (\x -> x * x) (filter even [1 .. 10])
```

Use whichever is clearer for the case at hand. `filter even [1..10]` reads cleanly for one step; once you have two or three generators and a guard, the comprehension wins.

The bigger example in the source is Pythagorean triples:

```haskell
pythag =
  [ (a, b, c)
  | c <- [1 .. 20]
  , b <- [1 .. c]
  , a <- [1 .. b]
  , a * a + b * b == c * c
  ]
```

Three nested generators plus one guard — a thirteen-line triple-nested loop in C, five lines here.

**Rust analogue**: Rust has no list comprehensions; you chain iterator adaptors. `evenSquares` would be `(1..=10).filter(|&x| x % 2 == 0).map(|x| x * x).collect::<Vec<_>>()`. Pythagorean triples would be nested `flat_map`s.

---

## 10. Walkthrough of `Lists.hs`

The source file is organised into labelled sections that mirror this README.

### Literals and empty lists

```haskell
primes :: [Int]
primes = [2, 3, 5, 7, 11, 13]

noInts :: [Int]
noInts = []
```

`[]` is polymorphic on its own — it could be a list of any type. The signature pins `noInts` to `[Int]`. If you drop the signature, GHC may complain that the type is ambiguous.

### Cons and append

```haskell
withZero  = 0 : primes                 -- 0 : [2,3,5,7,11,13]
allDigits = [0, 1, 2, 3, 4] ++ [5, 6, 7, 8, 9]
```

`0 : primes` does **not** modify `primes`. It returns a *new* list whose head is `0` and whose tail is the original `primes`. Because Haskell values are immutable, the original list can be shared — no copy is made of the tail.

### Ranges

```haskell
oneToTen  = [1 .. 10]
evensTo20 = [2, 4 .. 20]
alphabet  = ['a' .. 'z']
```

### Queries and reductions

```haskell
primeCount       = length primes
isEmpty          = null noInts
primesDescending = reverse primes
firstPrime       = head primes

sumPrimes     = sum primes
productPrimes = product primes
biggest       = maximum primes
smallest      = minimum primes
```

### `map`, with a `where`-defined helper

```haskell
squared = map square primes
  where
    square :: Int -> Int
    square x = x * x
```

`where` attaches a local definition to the binding above it. `square` is only visible inside `squared`. This is how you avoid polluting the top-level namespace with one-off helpers.

### `filter` and sections

```haskell
evenPrimes = filter even primes
bigPrimes  = filter (> 5) primes
```

Both arguments to `filter` are *functions*. `even` is a Prelude function (`Integral a => a -> Bool`). `(> 5)` is an on-the-fly section.

### `lines`, `words`, and `head`

```haskell
sampleText :: String
sampleText = "one two three\nfour five\nsix"

textLines      = lines sampleText
firstLineWords = words (head textLines)
```

`head textLines` takes `["one two three", "four five", "six"]` and returns `"one two three"`. `words` then splits that on whitespace.

### List comprehensions

The four increasingly-fancy comprehensions at the bottom of the file cover: a single generator, a generator + guard, multiple generators, and multiple generators + a guard. Read them in that order.

### Running it

```bash
cd tutorial/day3
runghc src/Lists.hs
```

Expected output (truncated):

```
primes            = [2,3,5,7,11,13]
greeting          = "hello"
withZero          = [0,2,3,5,7,11,13]
allDigits         = [0,1,2,3,4,5,6,7,8,9]
oneToTen          = [1,2,3,4,5,6,7,8,9,10]
evensTo20         = [2,4,6,8,10,12,14,16,18,20]
alphabet          = "abcdefghijklmnopqrstuvwxyz"
...
pythag            = [(3,4,5),(6,8,10),(5,12,13),(9,12,15),(8,15,17),(12,16,20)]
Day 3 complete!!!
```

Or load it into GHCi:

```bash
ghci tutorial/day3/src/Lists.hs
```

```
ghci> map (* 3) [1..5]
[3,6,9,12,15]
ghci> filter odd [1..10]
[1,3,5,7,9]
ghci> sum [1..100]
5050
ghci> words "the quick brown fox"
["the","quick","brown","fox"]
ghci> :t map
map :: (a -> b) -> [a] -> [b]
```

---

## 11. Try it

Do these in GHCi with `src/Lists.hs` loaded.

1. Compute the sum of the squares of `1..100` two different ways: once with `map` + `sum`, once with a list comprehension.
2. Build the string `"a,b,c,d,e,f"` from `['a'..'f']`. Hint: think `map` + `++`, and remember a `String` is a list of `Char` so you can cons a `Char` onto one.
3. Write `countEven :: [Int] -> Int` that counts how many elements are even. One-liner: `filter` then `length`.
4. Using a list comprehension, list every `(x, y)` with `x + y == 10`, `1 <= x <= y <= 9`.
5. `lines "abc\ndef\n"` gives `["abc", "def"]` (note: only two elements, because the trailing `\n` does not create a third empty line). Verify it in GHCi, then predict and check `unlines ["abc", "def"]`.

---

## 12. What you should remember

- **A list type is `[a]`**. `String` is exactly `[Char]`. Immutable, singly-linked, homogeneous.
- **Three ways to build**: literal `[1, 2, 3]`, cons `x : xs`, append `xs ++ ys`.
- **Ranges**: `[1..10]`, `[2, 4..20]`, `['a'..'z']`. Inclusive on both ends.
- **Queries**: `length`, `null`, `reverse`, `head`, `last`. `head` / `last` / `minimum` / `maximum` crash on `[]`.
- **Reductions**: `sum`, `product`, `minimum`, `maximum`.
- **`map :: (a -> b) -> [a] -> [b]`** transforms every element.
- **`filter :: (a -> Bool) -> [a] -> [a]`** keeps matching elements.
- **Operator sections**: `(* 2)`, `(> 5)`, `(10 -)`. Not `(- 5)` — that is a number.
- **`lines` / `words`** split a `String` on newlines / whitespace. Your everyday AoC parsing starting point.
- **List comprehensions** `[ e | gen, guard, ... ]` are sugar for nested `map` + `filter`. Great for multiple generators.

---

**Next**: Day 4 — pattern matching, guards, `where` and `let`.
