# Day 7 — Your own `data` types and records

**Goal**: stop bundling problem state into anonymous tuples. Define your own types with `data`, name fields with record syntax, and let `deriving` write the boring instances. By the end you will know when to reach for `data`, when for `newtype`, and when a `type` synonym is enough.

**Source files**:
- [src/Records.hs](src/Records.hs) — sum types, product types, records, `deriving`, record update.
- [src/Newtype.hs](src/Newtype.hs) — `newtype` as a zero-cost type-safe wrapper.

---

## 1. Why your own types

Everything so far has used types Haskell ships with: `Int`, `Bool`, `[a]`, `Maybe a`, `Either e a`, and the occasional tuple. That carries you a long way, but tuples have two failure modes that AoC will hit immediately:

- **They lose meaning.** `(Int, Int, Int)` could be `(x, y, z)`, or `(red, green, blue)`, or `(id, x, y)`. Three months from now you will not remember which.
- **They do not scale.** Past three or four fields, every position becomes a guessing game. There are no field names to look up.

`data` lets you give the type a name and the fields a name. The compiler then keeps you honest: if you treat a `Player` as a `Score`, the build fails; if you forget a constructor in a pattern match, `-Wall` warns you.

**Rust analogue**: `data` is `enum` and `struct` at the same time. Sum types are Rust enums, product types are Rust structs, and tagged unions (constructors with fields) are Rust enum-with-data. Record syntax is the Haskell version of named struct fields.

---

## 2. Sum types — "one of these"

The simplest `data` declaration lists alternatives separated by `|`:

```haskell
data Direction = North | East | South | West
  deriving (Show, Eq)
```

Three things just happened in two lines:

1. A new type `Direction` was introduced.
2. Four nullary constructors (`North`, `East`, `South`, `West`) were introduced — each one is a value of type `Direction`.
3. `deriving (Show, Eq)` asked the compiler to write `show` and `==` for free.

Pattern match on a sum type the same way you matched on `Maybe` and `Either` in Day 5:

```haskell
opposite :: Direction -> Direction
opposite North = South
opposite South = North
opposite East  = West
opposite West  = East
```

If you forget a constructor and compile with `-Wall`, GHC tells you exactly which case you missed. That single warning catches more bugs than any test you would have written by hand.

**Rust analogue**: identical to `enum Direction { North, East, South, West }`. Pattern matching is exhaustive in both languages.

---

## 3. Product types — "these and these"

A constructor that takes arguments builds a *product*: a value carrying several pieces at once. The simplest form is positional:

```haskell
data Vec2 = Vec2 Int Int
  deriving (Show, Eq)
```

The constructor `Vec2` is now a function — `Vec2 :: Int -> Int -> Vec2`. Apply it like any other function:

```haskell
ghci> Vec2 3 4
Vec2 3 4
```

To take a `Vec2` apart, pattern match with the same shape you used to build it:

```haskell
addVec :: Vec2 -> Vec2 -> Vec2
addVec (Vec2 ax ay) (Vec2 bx by) = Vec2 (ax + bx) (ay + by)
```

This is fine for two fields. With more fields, or with several `Int`s in a row, you start guessing again. That is what record syntax fixes.

---

## 4. Records — names on the fields

Record syntax uses braces and explicit field names. Each field gets a type signature on the right:

```haskell
data Player = Player
  { playerName   :: String
  , playerHealth :: Int
  , playerScore  :: Int
  } deriving (Show, Eq)
```

You get **three** things from that one declaration:

| What you get | Type |
|---|---|
| The type | `Player` |
| The constructor | `Player :: String -> Int -> Int -> Player` |
| One accessor per field | `playerName :: Player -> String`, `playerHealth :: Player -> Int`, `playerScore :: Player -> Int` |

The accessors are ordinary functions. `playerName alice` reads the name; `map playerHealth players` extracts the health from a list of players.

Build a value with field names spelled out — order does not matter and there is no positional ambiguity:

```haskell
alice :: Player
alice = Player
  { playerName   = "Alice"
  , playerHealth = 100
  , playerScore  = 0
  }
```

You can still build it positionally — `Player "Alice" 100 0` works — but the named form is what you will write when the type has more than two fields.

### Reading a record declaration

```
data Player = Player                         -- type name = constructor name (same convention)
  { playerName   :: String                   -- field 1: name + type
  , playerHealth :: Int                      -- field 2 (commas at the front, Haskell style)
  , playerScore  :: Int                      -- field 3
  } deriving (Show, Eq)                      -- ask the compiler for free instances
```

The leading-comma layout is a Haskell convention worth adopting. It keeps every field aligned, makes diffs cleaner when you add a field, and avoids the "extra trailing comma" debate altogether.

---

## 5. Record update — immutable "modification"

Haskell records are immutable. "Updating" a record means producing a *new* record with some fields changed. The syntax is `r { field = newValue }`:

```haskell
heal :: Int -> Player -> Player
heal n p = p { playerHealth = playerHealth p + n }
```

Read this as: "take `p`, and return a copy where `playerHealth` is the old health plus `n`." All other fields stay the same. You can update several fields at once:

```haskell
resetPlayer :: Player -> Player
resetPlayer p = p { playerHealth = 100, playerScore = 0 }
```

Sharing makes this cheap. The new record reuses the unchanged fields by reference; only the changed fields are written. So you can update a record in a tight loop without worrying about copy cost.

**Rust analogue**: this is Rust's `..` struct-update shorthand — `Player { health: 100, ..p }` — flipped around. In Haskell you spell out the changes; in Rust you spell out the carry-overs.

---

## 6. `deriving` — free instances for common type classes

`deriving (Show, Eq, Ord)` is the compiler's offer to write the mechanical instances for you. The three you will use the most:

| Class | What it gives you |
|---|---|
| `Show` | A printable representation. Used by `show` and by GHCi's auto-print. |
| `Eq` | The `==` and `/=` operators. |
| `Ord` | `<`, `<=`, `compare`, plus things that need ordering — `sort`, `Data.Set`, `Data.Map`. |

Two rules to keep in mind:

- **`deriving (Eq)` does the obvious thing.** Two values are equal iff they have the same constructor and equal fields, recursively.
- **`deriving (Ord)` is *lexicographic on field order*.** `Score "Alice" 99` compares less than `Score "Bob" 0` because `"Alice" < "Bob"`. The points field is only consulted when the names tie.

That second rule matters. From `Records.hs`:

```haskell
data Score = Score
  { scorePlayer :: String
  , scorePoints :: Int
  } deriving (Show, Eq, Ord)
```

If you call `maximum` on a leaderboard of `Score`s, you get the alphabetically-last player, not the highest scorer. The fix is not to redefine `Ord` — it is to do the comparison you actually want, with a fold:

```haskell
topScore :: [Score] -> Maybe Score
topScore []     = Nothing
topScore (x:xs) = Just (foldl' best x xs)
  where
    best :: Score -> Score -> Score
    best b s
      | scorePoints s > scorePoints b = s
      | otherwise                     = b
```

This is yesterday's `foldl'` (Day 6) carrying a `Score` accumulator instead of an `Int`. Same shape, richer state.

**Aside on type classes**: a "type class" is Haskell's name for an interface that types can implement. `Show`, `Eq`, `Ord` are the three you will see most. `deriving` is the compiler saying "I will write the instance for you, since the structure is mechanical." A full tour of type classes comes later — for now, treat `deriving` as the magic that makes `print`, `==`, and `compare` work for your own types.

---

## 7. Sum + product together — tagged unions

The two ideas combine. Each constructor of a sum type can carry its own bundle of fields:

```haskell
data Shape
  = Circle Double                  -- radius
  | Rectangle Double Double        -- width, height
  | Triangle Double Double Double  -- side a, b, c
  deriving (Show, Eq)
```

Pattern match on the constructor and the fields fall out:

```haskell
area :: Shape -> Double
area (Circle r)       = pi * r * r
area (Rectangle w h)  = w * h
area (Triangle a b c) =
  let s = (a + b + c) / 2
   in sqrt (s * (s - a) * (s - b) * (s - c))
```

This shape — *one of several alternatives, each carrying its own data* — is the workhorse of Haskell modelling. AoC problems that branch on input format ("opcode 1 takes two registers, opcode 2 takes a register and an immediate, …") map straight onto a tagged union.

**Rust analogue**: identical to `enum Shape { Circle(f64), Rectangle(f64, f64), Triangle(f64, f64, f64) }`. The two languages have the same feature with different syntax.

---

## 8. `type` vs `newtype` vs `data`

Three flavours, three different cost/benefit tradeoffs:

| Keyword | What it is | Runtime cost | Use when |
|---|---|---|---|
| `type` | A pure synonym | None — `Name` *is* `String` | Documenting what a `String` (or other) means in a type signature. No safety. |
| `newtype` | A new type, one constructor, one field | None — same representation as the wrapped type | You want a fresh type for safety/documentation but cannot afford a runtime wrapper. |
| `data` | A full algebraic type — sums, products, records | A heap object per value | Anything richer than one field, or any sum type. |

`type` is just a synonym:

```haskell
type Name = String

greet :: Name -> String
greet n = "Hello, " ++ n
```

`Name` and `String` are interchangeable — the compiler does not separate them. Pass a literal `String` to `greet` and it works. This is cheap documentation, nothing more.

`newtype` is what you reach for when you want **distinct types at compile time and zero overhead at runtime**. Two `Double`s called `Meters` and `Seconds` are a great example — see `Newtype.hs`:

```haskell
newtype Meters  = Meters  Double deriving (Show, Eq, Ord)
newtype Seconds = Seconds Double deriving (Show, Eq, Ord)

speed :: Meters -> Seconds -> Double
speed (Meters m) (Seconds s) = m / s
```

The compiler now refuses `speed (Seconds 9.58) (Meters 100)` — the arguments are swapped. With raw `Double` everywhere, that bug compiles and runs and gives you nonsense. The cost is one constructor wrap at the boundary; after compilation, `Meters` and `Double` are represented identically. AoC use: wrap a row index and a column index as separate newtypes so grid code cannot transpose them by accident.

`newtype` has two hard rules: **exactly one constructor** and **exactly one field**. As soon as you need more than one field, you upgrade to `data`.

---

## 9. Walkthrough of the source files

`Records.hs` is laid out in seven parts that mirror this README:

1. **Sum type** — `Direction` and `opposite`, the enum case.
2. **Product type** — `Vec2` and `addVec`, the positional constructor.
3. **Records** — `Player` and `alice`, named fields and free accessors.
4. **Record update** — `heal`, `scorePoint`, `resetPlayer` showing `r { field = ... }` syntax.
5. **`deriving`** — `Score` and the `topScore` fold that ignores the derived (lexicographic) `Ord` and uses a custom comparison.
6. **Tagged union** — `Shape` and `area`, sum-of-products with pattern matching.
7. **Type aliases** — `Name = String` and `greet`, the no-cost synonym.

`Newtype.hs` is the focused mini-demo. It introduces `Meters`, `Seconds`, and `Celsius`, and uses them in `speed` and `toFahrenheit` to show two things:

- **The wrap is invisible at runtime.** `speed (Meters 100) (Seconds 9.58)` runs as fast as the raw `Double` version.
- **The wrap is visible at compile time.** Swap the arguments and the build fails.

Run them the same way as previous days:

```bash
cd tutorial/day7
runghc src/Records.hs
runghc src/Newtype.hs
```

Or load either in GHCi:

```bash
ghci src/Records.hs
```

```
ghci> :t Player
Player :: String -> Int -> Int -> Player
ghci> :t playerHealth
playerHealth :: Player -> Int
ghci> alice { playerScore = 5 }
Player {playerName = "Alice", playerHealth = 100, playerScore = 5}
ghci> compare (Score "Alice" 99) (Score "Bob" 0)
LT
```

That last one is the lexicographic `Ord` in action: `"Alice" < "Bob"`, so the score field never gets compared.

---

## 10. Try it

Small exercises. Do them in GHCi with `Records.hs` loaded.

1. Add a `damage :: Int -> Player -> Player` function that subtracts from `playerHealth`. Confirm it agrees with `heal (-n)`. Pattern: record update.
2. Define `data Coin = Penny | Nickel | Dime | Quarter deriving (Show, Eq, Ord)` and a function `cents :: Coin -> Int`. Use `map cents [Penny, Dime, Quarter]` to confirm.
3. Extend `Shape` with a `Square Double` constructor. Add the case to `area`. Compile with `-Wall` *before* you add the case and read the warning — that is the safety net you get for free.
4. Define `data Tree a = Leaf | Node (Tree a) a (Tree a) deriving (Show, Eq)` — a binary tree. Write `insert :: Ord a => a -> Tree a -> Tree a` that places a value in the right spot. (Use `Ord a =>` exactly as written; it says "for any `a` that has an `Ord` instance" — Day 8 will go deeper.)
5. Sort the leaderboard two ways. First, `Data.List.sort leaderboard` — observe it sorts alphabetically because of the derived `Ord`. Then write `sortByPoints :: [Score] -> [Score]` using `Data.List.sortBy` and `compare` on `scorePoints`. Confirm it gives the order you actually want.
6. Switch `Newtype.hs` to call `speed (Seconds 9.58) (Meters 100)` and recompile. Read the type error message — you have just been saved from a unit bug.

---

## 11. What you should remember

- **`data` introduces a new type with a list of constructors**, separated by `|`. No-argument constructors are an enum; constructors with arguments are a product; mix them and you get a tagged union.
- **Record syntax names the fields**, and the compiler auto-generates one accessor function per field. `playerHealth :: Player -> Int` is just an ordinary function.
- **Records are immutable.** `r { field = newValue }` produces a new record with the named fields updated; everything else is shared. Cheap, no mutation involved.
- **`deriving (Show, Eq, Ord)` writes the boring instances for you.** Derived `Ord` is lexicographic on field order — if that is not the order you want, fold with a custom comparison instead of redefining the instance.
- **`type` is a free synonym, `newtype` is a zero-cost wrapper, `data` is a real algebraic type.** `newtype` is the right tool when you want compile-time safety (`Meters` vs `Seconds`) without runtime overhead.
- **Pattern matching scales naturally.** Every type you define here can be taken apart by the same pattern syntax you used for `Maybe` and `Either` on Day 5.
- **Rust analogue summary**: `data` sum types are Rust enums; `data` records are Rust structs with named fields; tagged unions are Rust enums-with-data; `newtype` is Rust's tuple-struct wrapper; `deriving` is the Haskell counterpart to `#[derive(Debug, PartialEq, Eq, Ord)]`.

---

**Next**: Day 8 — `Data.Map.Strict` and `Data.Set`. The two workhorse containers for AoC: keyed lookup with `Map`, set membership with `Set`. Strict variants by default, just like `foldl'` was the default fold.
