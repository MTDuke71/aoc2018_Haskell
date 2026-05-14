# Day 13: Mine Cart Madness -- Function Guide

**Problem**: A 2-D ASCII grid of tracks (`-` `|` `/` `\` `+`) with carts (`^` `v` `<` `>`) riding the rails.  Every tick, every cart moves one cell in its facing direction -- in *reading order*: top-to-bottom by row, left-to-right within each row.  Curves reflect, intersections cycle left / straight / right per cart.  Part 1: report the coordinates of the first cart-on-cart crash as `"x,y"`.  Part 2: keep running, removing both carts of every crash, until exactly one cart survives; report *its* coordinates as `"x,y"`.
**Answers**: Part 1 = **`118,66`**, Part 2 = **`70,129`**
**Runtime** (mean, criterion `-O2`): Parse = **1.374 ms** | Part 1 = **292.8 µs** | Part 2 = **6.066 ms** | **Total = 7.73 ms**
**Code**: [Day13.hs](../../src/Day13.hs)
**Tests**: [Day13Spec.hs](../../test/Day13Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day13"`
**Problem statement**: [day13.md](day13.md)
**Python reference**: [python/day13.py](../../python/day13.py)

**New concepts this day** (beyond Days 0--12):

- **Reading-order discrete-event simulation.**  Day 12 was a *synchronous* update -- the entire grid steps in lock-step.  Day 13 is the asynchronous dual: each cart moves *independently*, in a deterministic reading order, and the world a cart sees is whatever the carts that already moved this tick have done.  Mid-tick collisions are a direct consequence.  AoC 2018 Day 15 (Goblins & Elves combat) is the next major puzzle of this shape; recognise the pattern now and Day 15's bookkeeping will be familiar.
- **Two-map state with a maintained invariant.**  `IntMap Int Cart` keyed by cart id is the population; `Map (Int,Int) Int` keyed by position points back into the population.  Every move updates both; the pair is in sync at every observable moment.  This is the same shape you would build in Rust as `HashMap<u32, Cart>` plus `HashMap<(i32,i32), u32>` -- and Haskell's strict `Map` / `IntMap` types give you the same performance profile.
- **Enum-style ADTs for direction and turn.**  `data Dir = U | D | L | R` and `data Turn = TLeft | TStraight | TRight` are textbook sum types: no fields, just tags.  Pattern matching on them is exhaustive (GHC warns otherwise), and the dispatch tables -- `reflectSlash`, `reflectBackslash`, `intersectTurn` -- are written as plain function definitions, one clause per case.  This is the Haskell idiom for what Rust would express with `enum Dir { U, D, L, R }`.
- **`foldl'` with a tuple accumulator.**  `tick`'s inner loop accumulates `([(Int,Int)], TickState)` across every cart in reading order.  Bangs on *both* components of the pair keep the fold's allocation profile flat -- otherwise the list-cons and the record-update would both be lazy and pile up thunks.
- **Reading-order traversal via the default `Ord` on tuples.**  `sortOn (\(_, c) -> (cartY c, cartX c))` exploits that `(Int, Int)` derives `Ord` lexicographically: tuples sort by their first component, breaking ties by their second.  Storing position as `(cartY, cartX)` -- *y first* -- means the default tuple order *is* reading order.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Why reading-order asynchronous tick is the puzzle](#why-reading-order-asynchronous-tick-is-the-puzzle)
3. [The Python reference](#the-python-reference)
4. [Data model](#data-model)
5. [`parseInput`](#parseinput)
6. [Direction algebra: `stepDir`, `reflectSlash`, `reflectBackslash`, `intersectTurn`, `nextTurn`](#direction-algebra-stepdir-reflectslash-reflectbackslash-intersectturn-nextturn)
7. [`applyTile` and `moveCart`](#applytile-and-movecart)
8. [`TickState` and `mkTickState`](#tickstate-and-mktickstate)
9. [`tick`](#tick)
10. [`firstCrash` and Part 1](#firstcrash-and-part-1)
11. [`lastSurvivor` and Part 2](#lastsurvivor-and-part-2)
12. [`part1`, `part2`, `solve`](#part1-part2-solve)
13. [Tests](#tests)
14. [Benchmarks](#benchmarks)
15. [Synchronous vs asynchronous CAs: Day 12 vs Day 13](#synchronous-vs-asynchronous-cas-day-12-vs-day-13)
16. [Possible optimizations](#possible-optimizations)
17. [Key patterns](#key-patterns)
18. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)
19. [Further reading](#further-reading)

---

## Problem summary

The input is a rectangular block of ASCII art.  Most of it is track:

```
/----\
|    |
\----/
```

Five tile types:

| Tile | Meaning                                                                  |
|:----:|--------------------------------------------------------------------------|
| `-`  | Straight track running east-west.                                        |
| `|`  | Straight track running north-south.                                      |
| `/`  | Curve from east-west into north-south.  Reflects:  R<->U,  L<->D.        |
| `\`  | Curve from east-west into north-south.  Reflects:  R<->D,  L<->U.        |
| `+`  | Four-way intersection.  A cart turns L / S / R / L / S / R / ...         |

Plus four cart glyphs (`^` `v` `<` `>`) that sit *on top of* a straight piece.  At parse time we replace each cart glyph with the straight piece that matches its facing -- the puzzle promises that this is what is underneath.

Each *tick*:

1. Carts are listed in the **reading order of their positions at the start of the tick**: top-to-bottom by row, left-to-right within a row.  (So a cart at row 3 column 1 moves before a cart at row 3 column 5, which moves before a cart at row 4 column 0.)
2. Each cart, in that order, takes exactly one step in its current direction.
3. After moving, the cart reads its new tile:
   - On `-` or `|`: keep going.
   - On `/`: reflect by `reflectSlash`.
   - On `\`: reflect by `reflectBackslash`.
   - On `+`: apply its next intersection turn (L / S / R) and bump its private turn counter to the next one in the L-S-R cycle.
4. If the new cell is already occupied by another cart -- one that already moved this tick *or* one that has not moved yet -- that is a collision.

**Part 1** asks: where does the *first* collision happen?  Report as `"x,y"`.

**Part 2** keeps running.  When a collision happens, both carts involved are removed and the simulation continues -- with whatever surviving carts are still due to move this tick.  When exactly one cart is left, report its position as `"x,y"`.

The worked example for Part 1 ends with a collision at `7,3`:

```
/---\
|   |  /----\
| /-+--+-\  |
| | |  X |  |       <-- X marks the collision
\-+-/  \-+--/
  \------/
```

The worked example for Part 2 has nine carts that gradually crash each other off the map; the survivor's position is `6,4`.

The actual input is a ~150x150 grid with about a dozen carts.  Brute-force simulation finishes in ~7 ms, so no algorithmic shortcut is needed: this puzzle is mostly about getting the mid-tick semantics right.

---

## Why reading-order asynchronous tick is the puzzle

Day 12 was a *synchronous* update: every pot reads its neighbours from the *current* state, all the new pots are computed, and then the whole tape is swapped over.  No pot ever sees a half-updated world.  The algebra of that puzzle (translation-equivariance, period-1 fixed points) hinged on every step being a single, atomic, world-wide refresh.

Day 13 is the asynchronous dual.  Carts move *one at a time*, in deterministic reading order, and each cart sees whatever the carts ahead of it have already produced.  Two consequences:

### Mid-tick collisions are real

A cart `A` at row 3, column 5 (facing right) and a cart `B` at row 3, column 6 (facing left) collide *immediately* on the next tick.  In reading order `A` moves first; it steps into column 6 -- which is where `B` still is.  Collision.  We did not need to "wait for `B` to also move" -- the world `A` looks at when it asks "is anyone at my destination?" is the world *as `B` left it*, because `B` has not moved yet.

### Order matters for the answer

Two carts that crash earlier in a tick are gone before later carts process (Part 2 semantics).  A later cart that *would have* crashed into one of them now glides past the empty cell where the dead pair used to be.  Get the order wrong and you produce a different Part 2 answer.

The whole puzzle, then, is about modelling these semantics correctly: a `tick` function that respects start-of-tick reading order, deletes positions on the way out, checks against everyone still alive, and removes crashed pairs in real time.  The state we carry across ticks is the bookkeeping that makes those four operations cheap.

---

## The Python reference

The shipping solution is in Haskell; the algorithm is captured in [python/day13.py](../../python/day13.py) for cross-checking and for readers who want to see the simulation without Haskell ceremony.  The tick function in particular is short enough to skim:

```python
def tick(grid, carts):
    carts.sort(key=lambda c: (c[0], c[1]))
    occupied = {(c[0], c[1]): i for i, c in enumerate(carts)}
    alive = set(range(len(carts)))
    crashes = []
    for i in range(len(carts)):
        if i not in alive:
            continue
        c = carts[i]
        del occupied[(c[0], c[1])]
        dy, dx = DV[c[2]]
        c[0] += dy; c[1] += dx
        tile = grid.get((c[0], c[1]), " ")
        if tile == "/":      c[2] = SLASH[c[2]]
        elif tile == "\\":   c[2] = BACK[c[2]]
        elif tile == "+":
            c[2] = turn(c[2], c[3])
            c[3] = NEXT_TURN[c[3]]
        if (c[0], c[1]) in occupied:
            j = occupied.pop((c[0], c[1]))
            alive.discard(i); alive.discard(j)
            crashes.append((c[1], c[0]))
        else:
            occupied[(c[0], c[1])] = i
    carts[:] = [c for i, c in enumerate(carts) if i in alive]
    return crashes
```

The Haskell `tick` below is a direct transliteration of this loop -- with the indices stable across ticks (we never re-number carts) so we can use an `IntMap` keyed by id instead of a `list` indexed by position-in-list, and with the `alive` set folded into the `IntMap` itself (`IM.lookup i` returning `Nothing` *is* "this cart is dead").

---

## Data model

```haskell
data Dir = U | D | L | R deriving (Eq, Show)

data Turn = TLeft | TStraight | TRight deriving (Eq, Show)

data Cart = Cart
  { cartY    :: !Int
  , cartX    :: !Int
  , cartDir  :: !Dir
  , cartTurn :: !Turn
  } deriving (Eq, Show)

data Puzzle = Puzzle
  { track :: !(UArray (Int,Int) Char)
  , carts :: ![Cart]
  } deriving (Eq, Show)

data TickState = TickState
  { tsCarts :: !(IntMap Cart)
  , tsPos   :: !(Map (Int, Int) Int)
  } deriving (Eq, Show)
```

Four types, ranked by lifetime.

### `Dir` and `Turn` -- enum-style sum types

These are the simplest sum types you can write in Haskell: four / three constructors with no fields each.  They are essentially named tags.  Pattern matching is exhaustive (GHC warns when a clause is missing -- a real bug-catcher for direction algebra), and the entire dispatch table for each is written as a flat function definition:

```haskell
reflectSlash :: Dir -> Dir
reflectSlash U = R
reflectSlash D = L
reflectSlash L = D
reflectSlash R = U
```

Rust would write this as:

```rust
enum Dir { U, D, L, R }

fn reflect_slash(d: Dir) -> Dir {
    match d { Dir::U => Dir::R, Dir::D => Dir::L, Dir::L => Dir::D, Dir::R => Dir::U }
}
```

Same shape, slightly heavier syntax.  Haskell's per-clause definition reads as a *truth table* -- four lines, one input case each.  Many beginners mistake this for "primitive recursion" but it is just function-as-table.

### Why store position as `(cartY, cartX)` -- *y first*

The puzzle wants reading order: rows then columns.  Haskell's default `Ord` on `(a, b)` is lexicographic: tuples sort by their first component, breaking ties by their second.  Storing `(y, x)` in that order means `sortOn (\(_, c) -> (cartY c, cartX c))` *is* "sort by reading order" -- no custom comparator, no `comparing` import.

Reversing the order (`(cartX, cartY)`) would still work, but you would have to spell out a comparator like `\c1 c2 -> compare (cartY c1, cartX c1) (cartY c2, cartX c2)` -- four times the writing.  Lining up the storage with the natural sort key is a free improvement.

### `Cart` has strict fields and a hand-rolled `NFData`

Every field is `!`-bang-strict.  `Cart` is a value record we will copy and tweak millions of times across ticks, so we want every update to produce a fully-evaluated cart, not a chain of `c { cartY = oldY + 1 }` thunks.

The `NFData` instance is hand-written because `deepseq` does not derive it for records with strict fields:

```haskell
instance NFData Cart where
  rnf (Cart a b c d) = a `seq` b `seq` c `seq` d `seq` ()
```

`Int`, `Dir`, `Turn` are all already `NFData` instances (the first by `deepseq`, the latter two by our own `rnf !_ = ()` -- which is sufficient because they are tag-only).  Criterion's `nf` calls `rnf` on the result to make sure the timing is honest.

### `Puzzle` -- the static input

`track :: UArray (Int,Int) Char` is the immutable grid produced once by `parseInput`.  `carts :: [Cart]` is the parse-order list of carts; `mkTickState` numbers them 0, 1, 2, ... in this same order to seed the `IntMap`.

`UArray (Int,Int) Char` has *no* `NFData` instance in the standard `deepseq` package -- exactly the same situation as Day 11's `UArray (Int,Int) Int`.  We use `seq` on the field, which is sufficient because `UArray` is spine-strict (the underlying byte array is already fully evaluated whenever the array reference is reached).

```haskell
instance NFData Puzzle where
  rnf (Puzzle a b) = a `seq` rnf b
```

`a `seq` ()` would also be correct, but `a `seq` rnf b` chains the cart list's evaluation too.

### `TickState` -- the two-map invariant

```haskell
data TickState = TickState
  { tsCarts :: !(IntMap Cart)
  , tsPos   :: !(Map (Int, Int) Int)
  }
```

Two strict maps, in lock-step.  At every moment between cart-moves the invariant holds:

```
for every i in tsCarts:
   let c = tsCarts ! i
   in  tsPos ! (cartY c, cartX c) == i

for every (y, x) in tsPos:
   tsCarts ! (tsPos ! (y, x)) is the cart at (y, x)
```

Together they make four operations cheap:

| Operation                                     | Cost      | What it touches                       |
|-----------------------------------------------|-----------|---------------------------------------|
| "Is there a cart at this cell?"               | `O(log n)`| `Map.lookup new tsPos`                |
| "Move cart `i` from `(oy,ox)` to `(ny,nx)`"   | `O(log n)`| Two map updates each side             |
| "Remove cart `i` after a crash"               | `O(log n)`| `IM.delete i` + `Map.delete pos`      |
| "Get all carts in reading order"              | `O(n log n)` | `sortOn ... . IM.toList`         |

The `IntMap` has a Patricia-trie internal representation -- faster than a generic `Map Int a` for integer keys.  Cart-count `n` is in the low double digits even on the real input, so the `log n` factors are tiny in practice.

### Why split state across two maps instead of one

A single `Map (Int,Int) Cart` would conflate identity and position.  The moment a cart moves, you would have to `Map.delete` its old key and `Map.insert` its new key -- which means a cart whose position is the *same as another cart's previous position* would silently overwrite, *and* you would lose the cart's id (so you cannot tell which of the original parse-order carts is which).

Keying by id is also what makes "skip already-crashed carts" cheap: `IM.lookup i tsCarts` returning `Nothing` *is* the test.  An alternative -- maintain a separate `IntSet` of alive carts -- would work, but maintaining one map instead of two simplifies the invariant.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput raw =
  let rows0   = lines raw
      h       = length rows0
      w       = maximum (0 : map length rows0)
      padded  = [ r ++ replicate (w - length r) ' ' | r <- rows0 ]
      tagged  = [ ((y, x), c)
                | (y, row) <- zip [0 ..] padded
                , (x, c)   <- zip [0 ..] row
                ]
      cs      = [ Cart y x d TLeft
                | ((y, x), ch) <- tagged
                , Just d       <- [cartDirOf ch]
                ]
      cells   = map (underTrack . snd) tagged
      arr     = listArray ((0, 0), (h - 1, w - 1)) cells
                  :: UArray (Int, Int) Char
  in  Puzzle arr cs
```

Three things worth dwelling on.

### Right-padding short rows

The puzzle's input has trailing whitespace stripped on some rows (text editors do this routinely).  But `listArray ((0,0), (h-1, w-1))` demands exactly `h * w` cells -- if any row is short, the array boundaries fall off the rails.

So we measure the max-width `w` and right-pad every row with spaces:

```haskell
padded  = [ r ++ replicate (w - length r) ' ' | r <- rows0 ]
```

Spaces are not a track tile, so they pad cleanly: any cart that walked onto a space would be off-track, and our `moveCart` would still read the space character correctly -- it just produces a no-op direction change.  In practice no cart ever steps off the rails, so this is belt-and-suspenders.

### Cart extraction and underlying-track replacement

`tagged` is a list of every cell, labelled with its `(y, x)` position.  From it we derive two things:

```haskell
cs    = [ Cart y x d TLeft
        | ((y, x), ch) <- tagged
        , Just d       <- [cartDirOf ch]
        ]
cells = map (underTrack . snd) tagged
```

`cs` is the cart list, with each cart starting on the L-S-R turn cycle (i.e. its first intersection turn will be a left).  The list comprehension's pattern match `Just d <- [cartDirOf ch]` is the "filter via pattern" idiom we used on Day 12: only cells whose `cartDirOf` produces `Just _` yield a cart, and we get the direction from the match.

`cells` is the underlying tile at every cell.  `underTrack '>'` = `'-'`, `underTrack '^'` = `'|'`, and every other character is unchanged.  Because `tagged` is enumerated in row-major order, `map (underTrack . snd) tagged` is the row-major flat list `listArray` wants.

### Why `'maximum (0 : map length rows0)'` rather than `'maximum (map length rows0)'`

The `0 :` cons handles the empty-input case: `maximum []` throws.  Belt-and-suspenders -- the puzzle inputs are always non-empty -- but the function is total.

### Why the parser is the slowest bench at 1.374 ms

The bench numbers tell a story:

| Bench   | Mean      | Why                                                                |
|---------|----------:|--------------------------------------------------------------------|
| Parse   | 1.374 ms  | `listArray` builds a ~150 x 150 `UArray` -- 22,500 cells           |
| Part 1  | 292.8 µs  | ~250 ticks until first crash, ~12 carts each                       |
| Part 2  | 6.066 ms  | ~17,500 ticks until one survivor (most ticks just shuffle carts)   |

The parser dominates Parse only relative to Part 1; Part 2's simulation is far heavier.  The 22,500-cell `listArray` build allocates a contiguous unboxed byte array, but the *cells list* it consumes is 22,500 lazy cons cells -- the `map (underTrack . snd) tagged` deferred work.  `nf parseInput` forces the array to WHNF, which in turn forces every cell, which forces every `underTrack`, which walks the entire `tagged` list.

A faster parser would write directly into a mutable `STUArray` and skip the intermediate list.  Not worth doing at this scale; documented in the [Possible optimizations](#possible-optimizations) sidebar.

---

## Direction algebra: `stepDir`, `reflectSlash`, `reflectBackslash`, `intersectTurn`, `nextTurn`

```haskell
stepDir :: Dir -> (Int, Int)
stepDir U = (-1,  0)
stepDir D = ( 1,  0)
stepDir L = ( 0, -1)
stepDir R = ( 0,  1)

reflectSlash :: Dir -> Dir
reflectSlash U = R
reflectSlash D = L
reflectSlash L = D
reflectSlash R = U

reflectBackslash :: Dir -> Dir
reflectBackslash U = L
reflectBackslash D = R
reflectBackslash L = U
reflectBackslash R = D

intersectTurn :: Turn -> Dir -> Dir
intersectTurn TStraight d = d
intersectTurn TLeft     U = L
intersectTurn TLeft     L = D
intersectTurn TLeft     D = R
intersectTurn TLeft     R = U
intersectTurn TRight    U = R
intersectTurn TRight    R = D
intersectTurn TRight    D = L
intersectTurn TRight    L = U

nextTurn :: Turn -> Turn
nextTurn TLeft     = TStraight
nextTurn TStraight = TRight
nextTurn TRight    = TLeft
```

Five flat truth tables.  Worth knowing the geometry so you can verify the rows by inspection -- there is no clever code here, but there are several easy ways to get a sign or a rotation wrong.

### `stepDir`: rows grow downward

`U` is `(-1, 0)`, not `(+1, 0)`.  Screen coordinates: y increases as you move down the page.  Day 6 (Chronal Coordinates) used the same convention; Day 11 (Chronal Charge) used (x, y) with y also being a "grid row".  When the puzzle's example output has a top-left of the grid at row 0, "up" is "decrease y".

If you ever spot a column count that goes the wrong way in your output, this is the first table to re-check.

### `reflectSlash`: pair the cardinals across the NE-SW diagonal

A `/` curve runs from the south-west corner to the north-east corner of its cell.  Geometrically:

```
   |
   v
 \ |
  \|         a cart heading south hits '/' and bounces west
---X---      a cart heading east  hits '/' and bounces north
   |\
   | \
```

Pairs: `R <-> U`, `L <-> D`.  Four input cases, four outputs; the table is `reflectSlash U = R; reflectSlash R = U; reflectSlash D = L; reflectSlash L = D`.

### `reflectBackslash`: the other diagonal

A `\` curve runs from the north-west corner to the south-east corner.

```
   |
   v
   |/
   |/        a cart heading south hits '\' and bounces east
---X---      a cart heading east  hits '\' and bounces south
  /|
 / |
```

Pairs: `R <-> D`, `L <-> U`.

### `intersectTurn`: 90 degrees CCW for left, CW for right

`TLeft` rotates a direction 90 degrees counter-clockwise: `U -> L -> D -> R -> U`.  `TRight` rotates clockwise: `U -> R -> D -> L -> U`.  `TStraight` is identity.

This is the place where most beginners introduce an off-by-rotation bug.  If your carts drift left when they should drift right, double-check this table -- and the corresponding row in the spec, which pins all eight rotations.

### `nextTurn`: the L-S-R cycle

Bumps the cart's per-intersection counter: `L -> S -> R -> L`.  The cart's first intersection encounter triggers `TLeft`, the second `TStraight`, the third `TRight`, and the cycle repeats.

Spec coverage in [Day13Spec.hs](../../test/Day13Spec.hs) pins every row of every table -- if you ever refactor this code, those tests are the first line of defence.

---

## `applyTile` and `moveCart`

```haskell
applyTile :: Char -> Cart -> Cart
applyTile '/'  c = c { cartDir = reflectSlash     (cartDir c) }
applyTile '\\' c = c { cartDir = reflectBackslash (cartDir c) }
applyTile '+'  c = c { cartDir  = intersectTurn (cartTurn c) (cartDir c)
                     , cartTurn = nextTurn (cartTurn c)
                     }
applyTile _    c = c

moveCart :: UArray (Int, Int) Char -> Cart -> Cart
moveCart tr c =
  let (dy, dx) = stepDir (cartDir c)
      !ny     = cartY c + dy
      !nx     = cartX c + dx
      !tile   = tr ! (ny, nx)
      !moved  = c { cartY = ny, cartX = nx }
  in  applyTile tile moved
```

### Tile arrival, not tile departure

A cart applies the tile rule based on the tile it has *arrived at*, not the tile it has just left.  This matters for `+` intersections in particular: a cart that started on a `+` (which the puzzle never does, but humour me) would not bump its counter just for *being* there -- only stepping onto a fresh `+` triggers a turn.

Implementing this is straightforward: in `moveCart`, we update the cart's position first (`moved`), then call `applyTile (tr ! (ny, nx)) moved`.  The tile at the new cell is the one we apply.

### Why the bang patterns in `moveCart`

`ny`, `nx`, `tile`, `moved` are all read exactly once on the way to `applyTile`.  In a non-strict language, defining them via `let` without bangs produces a small thunk chain (a thunk per binding); with bangs each is computed eagerly.

For a function that gets called millions of times across Part 2, that micro-thunk overhead would aggregate.  The bangs are a habit worth maintaining for code in hot inner loops.

### `applyTile` does not handle `'-'`, `'|'`, or `' '`

The catch-all branch `applyTile _ c = c` handles every tile that does not need a direction change.  Straight track (`-`, `|`) is a no-op.  An off-track space `' '` is also a no-op -- in practice this never fires because no cart leaves the rails, but a defensive catch-all is cheaper than a defensive `error` here.

---

## `TickState` and `mkTickState`

```haskell
data TickState = TickState
  { tsCarts :: !(IntMap Cart)
  , tsPos   :: !(Map (Int, Int) Int)
  } deriving (Eq, Show)

mkTickState :: [Cart] -> TickState
mkTickState cs =
  let idxed = zip [0 ..] cs
      cm    = IM.fromList idxed
      pm    = Map.fromList [ ((cartY c, cartX c), i) | (i, c) <- idxed ]
  in  TickState cm pm
```

The seeding step.  Cart ids are 0..(n-1) in *parse order* -- which, because `parseInput` walks rows then columns, is the same as reading order at parse time.  But the order does not have to be reading order at any later time: when carts are sorted into reading order on every tick, we use their *current* positions.

```haskell
idxed = zip [0 ..] cs
```

`zip [0 ..] cs` pairs each cart with its index in the list.  We then build both maps from the same `idxed` list:

```haskell
cm = IM.fromList idxed                                  -- id  -> Cart
pm = Map.fromList [ ((cartY c, cartX c), i) | (i, c) <- idxed ]  -- pos -> id
```

Both `fromList` calls are `O(n log n)` -- fine at `n ~ 12`.  We do this exactly once per puzzle, not per tick.

### Why is `tsPos` typed `Map (Int,Int) Int` rather than `Map (Int,Int) Cart`?

The `Int` is the *id*, which is the key into `tsCarts`.  Storing the `Cart` directly would let us look up cart-state from position in one step, but we would have to keep two copies of every cart in sync -- and the moment we move a cart, we would have to update *both* maps.  The cost of `cm IM.! i` after a `pm Map.! pos` is `O(log n)` extra; the cost of duplicating cart state would be 2x memory and a synchronisation invariant that is easy to get wrong.

For `n ~ 12` carts, neither cost is material; the id-indirection is a stylistic choice that scales gracefully when `n` grows.  AoC 2018 Day 15 (Goblins & Elves) has ~30 agents and uses the same pattern.

---

## `tick`

```haskell
tick :: UArray (Int, Int) Char -> TickState -> ([(Int, Int)], TickState)
tick tr ts0 =
  let orderedIds =
        map fst
          $ sortOn (\(_, c) -> (cartY c, cartX c))
          $ IM.toList (tsCarts ts0)
      (revCrashes, ts1) = foldl' (stepOne tr) ([], ts0) orderedIds
  in  (reverse revCrashes, ts1)

stepOne
  :: UArray (Int, Int) Char
  -> ([(Int, Int)], TickState)
  -> Int
  -> ([(Int, Int)], TickState)
stepOne tr (!crs, TickState !cm !pm) i =
  case IM.lookup i cm of
    Nothing -> (crs, TickState cm pm)            -- already crashed this tick
    Just c  ->
      let !old   = (cartY c, cartX c)
          !c'    = moveCart tr c
          !new   = (cartY c', cartX c')
          !pm0   = Map.delete old pm
      in  case Map.lookup new pm0 of
            Just j  ->
              let !pm1 = Map.delete new pm0
                  !cm1 = IM.delete i (IM.delete j cm)
              in  (new : crs, TickState cm1 pm1)
            Nothing ->
              let !pm1 = Map.insert new i pm0
                  !cm1 = IM.insert i c' cm
              in  (crs, TickState cm1 pm1)
```

The hottest piece of code in the day.  Pull it apart.

### Reading-order traversal

```haskell
orderedIds =
  map fst
    $ sortOn (\(_, c) -> (cartY c, cartX c))
    $ IM.toList (tsCarts ts0)
```

`IM.toList` produces an `[(Int, Cart)]` -- `(id, cart)` pairs sorted by *id*, not by position.  We then re-sort by position via `sortOn ... (cartY c, cartX c)`, which exploits the lexicographic `Ord` on the `(Int, Int)` tuple to get reading order for free.  Finally `map fst` discards the carts; we only need the ids -- the up-to-date cart will be looked up inside `stepOne`.

This `sortOn` runs once per tick.  At ~12 carts that is ~12 * log(12) ~= 43 comparisons per tick.  For Part 2's ~17,500 ticks, that is ~750,000 comparisons across the whole run -- still under 10 ms, well within budget.

### The `case IM.lookup i cm` is *the* reason ids exist

```haskell
case IM.lookup i cm of
  Nothing -> ... -- already crashed this tick
```

This branch is the Part 2 semantics.  A cart that gets killed by an earlier crash *in the same tick* is still in `orderedIds` (the order was fixed at the start of the tick), so its turn to move comes up -- we just observe that it is gone from `tsCarts` and skip it.

This is the cleanest example of *why* we key by id.  If we keyed by position instead, "skip this cart because it got killed earlier in the tick" would need a side channel -- usually an `IntSet` of dead ids.  Keeping all the state in `tsCarts` means `IM.lookup` is the test.

### The two map updates per move

```haskell
let !old   = (cartY c, cartX c)
    !c'    = moveCart tr c
    !new   = (cartY c', cartX c')
    !pm0   = Map.delete old pm
```

Step the cart, capture old and new positions, *delete the old position from `tsPos`* (so we cannot self-collide).  Then check for a collision:

```haskell
case Map.lookup new pm0 of
  Just j  -> ...   -- collision with cart j
  Nothing -> ...   -- no one there
```

If `pm0 ! new = Just j`, a different cart (`j`) was at `new`.  We delete `new` from `pm0` (its occupant is now dead too) and delete *both* ids from `cm`.  Note we delete `i` (the moving cart) before `j` -- order does not matter, but we have to remember `i` was still in `cm` at the top of this case.

If `pm0 ! new = Nothing`, the destination is free.  Insert `(new, i)` into `pm0` and update `cm` with the new cart record.

The crash list grows by prepending (`new : crs`).  At the end of the tick we `reverse` the list once, so callers see crashes in the order they happened.

### Bang patterns on the accumulator

```haskell
foldl' (stepOne tr) ([], ts0) orderedIds
```

`foldl'` is the strict left-fold -- it forces the accumulator to WHNF at every step.  For a *pair*, WHNF means the outer `(,)` constructor is evaluated, but its components stay thunks.  So `foldl'`'s built-in strictness is not enough; we need to bang the components.

That is what `stepOne`'s `(!crs, TickState !cm !pm)` does.  The `!` on `crs`, `cm`, and `pm` evaluates each component before the case-match runs -- so the accumulator at any point in the fold is fully-evaluated.

Without these bangs, the cart-state thunks would chain up across the tick -- and across 17,500 ticks in Part 2 we would build a *huge* thunk graph before the answer is asked for.  The bench would not be 6 ms but more like several hundred.

### Why prepend then reverse, instead of append?

Appending to the right end of a list is `O(n)`; prepending is `O(1)`.  Across a tick we might produce up to ~6 crashes (Part 2 of the worked example), so the difference is small -- but we *always* prepend in Haskell unless there is a specific reason not to.

`reverse revCrashes` at the end is `O(k)` where `k` is the crash count -- one walk.

---

## `firstCrash` and Part 1

```haskell
firstCrash :: UArray (Int, Int) Char -> TickState -> (Int, Int)
firstCrash tr = go
  where
    go !ts =
      let (crs, ts') = tick tr ts
      in  case crs of
            (c : _) -> c
            []      -> go ts'
```

A tight tail-recursive loop.  Run `tick`; if it produced any crashes, return the head (which `tick` has already reversed into reading order, so the head *is* the first crash).  Otherwise recurse on the new state.

Note: Part 1 still uses the full Part-2 `tick` -- which removes both carts of every crash.  That is OK because we stop at the first crash; the post-crash state is discarded.  We could have written a Part-1-only `tickStopAtFirst` that bails out mid-fold on the first collision, saving a few hundred microseconds.  Documented in [Possible optimizations](#possible-optimizations); not worth the duplication at 290 µs.

### Bang on `!ts`

The `!ts` pattern in `go !ts = ...` forces the accumulator on every recursive call.  Without it, every tick would defer the state update into a thunk -- the same thunk-chain problem `stepOne` solves locally, applied at the loop level.

### Part 1 -- driving the loop

```haskell
part1 :: Puzzle -> String
part1 (Puzzle tr cs) =
  let (y, x) = firstCrash tr (mkTickState cs)
  in  fmtXY x y
```

Pattern-match the puzzle, seed the tick state, run until first crash, format as `"x,y"`.  Note the swap: `firstCrash` returns `(y, x)` -- our internal convention -- and `fmtXY x y` produces `"x,y"`.

Six ticks deep at most; tens of microseconds in practice.  290 µs total because the timing includes seeding the tick state from scratch (an `IM.fromList` and a `Map.fromList` over the parsed carts).

---

## `lastSurvivor` and Part 2

```haskell
lastSurvivor :: UArray (Int, Int) Char -> TickState -> Cart
lastSurvivor tr = go
  where
    go !ts
      | IM.size (tsCarts ts) <= 1 =
          case IM.elems (tsCarts ts) of
            (c : _) -> c
            []      -> error "Day13.lastSurvivor: no carts left"
      | otherwise =
          let (_, ts') = tick tr ts
          in  go ts'
```

Same shape as `firstCrash`, different termination.  Loop until `IM.size (tsCarts ts) <= 1`.

### Why `<= 1` and not `== 1`?

For real inputs, the cart population starts odd and stays odd -- every crash removes two carts -- so the population is always odd, and "at most one" *is* "exactly one".  The `<= 1` reads as "stop as soon as fewer than two carts remain" and would correctly handle the degenerate case of zero carts (we then `error`).

A `== 1` check would also work but the `<= 1` reads more honestly to me: "stop the moment there is no point ticking again."

### Why `IM.elems` returns `[Cart]` not `Maybe Cart`

There is no `IM.findFirst` or similar in `Data.IntMap.Strict`.  `IM.elems` returns the values as a list (sorted by key, which is the cart id) and we take the head.

For a one-element `IntMap` this is `O(1)` -- the list is one cons cell.  Calling `error` in the zero-cart branch is defensive: it never fires on a real input but converts a silent wrong answer into a loud failure.

### Part 2 -- driving the loop

```haskell
part2 :: Puzzle -> String
part2 (Puzzle tr cs) =
  let c = lastSurvivor tr (mkTickState cs)
  in  fmtXY (cartX c) (cartY c)
```

Same shape as Part 1: seed, run, format.  Note that for Part 2 we read the survivor's `(cartX, cartY)` directly -- no tuple to unpack.

The Part 2 bench at 6.066 ms is ~17,500 ticks * 350 ns/tick.  Each tick is the inner work plus the `sortOn` overhead; for ~12 carts that lines up well.

---

## `part1`, `part2`, `solve`

```haskell
part1 :: Puzzle -> String
part1 (Puzzle tr cs) =
  let (y, x) = firstCrash tr (mkTickState cs)
  in  fmtXY x y

part2 :: Puzzle -> String
part2 (Puzzle tr cs) =
  let c = lastSurvivor tr (mkTickState cs)
  in  fmtXY (cartX c) (cartY c)

solve :: String -> IO ()
solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ part1 puzzle)
  putStrLn ("  part 2: " ++ part2 puzzle)

fmtXY :: Int -> Int -> String
fmtXY x y = show x ++ "," ++ show y
```

`part1` and `part2` are pure `Puzzle -> String` functions; `solve` is the `IO` driver consumed by `app/Main.hs`.  This shape has been stable across every day since Day 0; the bench's `dayBench` helper picks up `parseInput`, `part1`, `part2` by name.

`fmtXY` is the format helper, three lines of `show` + `++`.  Could have been `printf "%d,%d"` but `Text.Printf` is overkill for two integers.

---

## Tests

Coverage in [Day13Spec.hs](../../test/Day13Spec.hs):

1. **Direction algebra (12 cases)** -- every row of `stepDir`, `reflectSlash`, `reflectBackslash`, `intersectTurn` (in three sub-tests, one per turn), and `nextTurn`.  If anyone introduces a sign or rotation bug, these tests catch it before either example runs.
2. **`parseInput`** -- pulls two carts out of the Part 1 example and verifies the cart-glyph cells are replaced by the correct underlying tile (`>` -> `-`, `v` -> `|`).
3. **Part 1 worked example** -- `part1` returns `"7,3"` on the puzzle's six-row example.
4. **Part 2 worked example** -- `part2` returns `"6,4"` on the puzzle's seven-row example.
5. **Actual puzzle input** -- pinned `expectedPart1 = "118,66"`, `expectedPart2 = "70,129"`.

The two worked-example tests exercise the entire simulator end-to-end on small inputs where the answer is calculable by hand from the puzzle's animations.  They are the spec.  If you ever touch `tick`, `firstCrash`, or `lastSurvivor`, the worked-example tests are what will tell you whether you got the mid-tick semantics right.

The direction-algebra tests look pedantic but the win is when you refactor: rewriting `intersectTurn` to use a numeric encoding (`(d + turn) mod 4`) is the kind of "obvious" change where a sign error is easy and silent.  Spec the truth table, then any new implementation has to match it.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean      | What it times                                                  |
|--------------------|----------:|----------------------------------------------------------------|
| `day13/parseInput` | 1.374 ms  | `lines`, padding, `listArray` over ~22,500 cells               |
| `day13/part1`      | 292.8 µs  | `mkTickState` + ~250 ticks until first crash                   |
| `day13/part2`      | 6.066 ms  | `mkTickState` + ~17,500 ticks until one survivor               |
| `day13/combined`   | 7.817 ms  | End-to-end from raw string                                     |

**Total = Parse + Part 1 + Part 2 = 7.73 ms.**

Three observations.

### Part 2 / Part 1 ratio is ~21x

Most of Part 2's work is the long tail of mostly-uneventful ticks where carts just snake around the track without colliding.  My input has ~250 ticks before the first crash and ~17,500 ticks before the final survivor remains -- a 70x gap in tick count, but only a 21x gap in wall time because Part 1 includes the (slow) `mkTickState` seeding while Part 2 amortises it over much more simulation.

### The parser is real work

1.374 ms on the parser is heavy compared to most other days.  The reason is that we build a `UArray (Int,Int) Char` over 22,500 cells, *plus* a `[Cart]` of ~12 cart records, *plus* a 22,500-element intermediate list (`tagged`).  `listArray` walks the entire list once to write the byte array.

A faster parser would build the array directly in `ST`, similar to Day 11's `buildSat`.  Documented in the next section; not worth doing at 1.4 ms.

### Combined is 7.8 ms, Total is 7.73 ms -- a 70 µs gap

The gap is mostly the `parseInput` overhead that the cached parts amortise.  `combined` re-parses every iteration; the summed parts share the parse via criterion's `env`.  Use Total as the headline figure.

---

## Synchronous vs asynchronous CAs: Day 12 vs Day 13

Day 12 and Day 13 are two faces of the same coin.  Both have a discrete time step, both have *local* update rules, both have an immutable rule set.  Where they differ:

| Property                                    | Day 12 (synchronous CA)                         | Day 13 (asynchronous DES)                                                |
|---------------------------------------------|--------------------------------------------------|---------------------------------------------------------------------------|
| **State**                                   | `Set Int` of live pots                          | `IntMap Int Cart` plus `Map (Int,Int) Int`                                |
| **Step**                                    | Compute *every* new pot in parallel             | Move *one* cart at a time, in reading order                               |
| **What a cell/agent sees**                  | The whole previous-generation state             | The current state -- including agents that moved earlier this tick        |
| **Mid-step collisions**                     | Impossible -- the state is fixed during a step  | The puzzle's whole point                                                  |
| **Determinism source**                      | The rule table                                  | Reading order + the rule table                                            |
| **Equivariance / translation algebra**      | Holds -- enables billion-step extrapolation     | Does not hold -- different reading orders produce different outcomes      |

The "what an agent sees" row is the single deepest distinction.  In Day 12 every pot's new state depends *only* on the previous generation's pots within window range.  In Day 13 every cart's move depends on *every other cart's current position* -- including the ones that just moved.  The new state is no longer a pure function of the old state; it is a pure function of the old state *and the reading order*.

### Why Day 12's tricks would not help Day 13

The reason Day 12's `extrapolate` was sound is that translation commutes with the rule.  In Day 13, *translation does not commute with reading order*: shift the whole world right by one and the carts now move in a different order than before (their new positions sort differently against the grid edges), and the dynamics diverge.

So Day 13 is the puzzle where the algorithm is "just run the simulation."  No equivariance, no period-1 fixed points, no closed-form projection.  Mechanically a much smaller body of code, semantically a careful tour of asynchronous update.

### When you will see this again

AoC 2018 Day 15 (Goblins & Elves combat) is the next big asynchronous puzzle: agents take turns in reading order, attack the weakest adjacent enemy, and the order of operations dictates the outcome.  Same shape as Day 13, with combat instead of motion.  The Day 13 `tick` / `IntMap`-by-id / `Map`-by-pos pattern carries over almost verbatim.

AoC 2017 Day 22 has a single moving agent on a CA grid -- a smaller cousin of Day 13.

AoC 2020 Day 24 is a 2-D synchronous CA on a hex grid -- closer in shape to Day 12, but with explicit edge-case handling at the grid boundary.

---

## Possible optimizations

The current solution finishes in 7.73 ms.  These are documented for the reader, not because we plan to ship them.

### 1. Build the track `UArray` directly in `ST`

```haskell
parseInput :: String -> Puzzle
parseInput raw = runST $ do
  let rows0   = lines raw
      h       = length rows0
      w       = maximum (0 : map length rows0)
  arr <- newArray ((0,0), (h-1, w-1)) ' '
  -- ... write each cell in a loop
  cs  <- newSTRef []
  -- ...
  arr' <- freezeArray arr
  cs'  <- readSTRef cs
  return (Puzzle arr' (reverse cs'))
```

Skips the 22,500-element intermediate list and writes the byte array in place.  Expected speedup on Parse: ~2-3x, getting it under 500 µs.

The cost is a more complex parser, and the API of `Data.Array.ST` is fiddly (boxed vs unboxed, freeze vs unsafeFreeze).  Day 11's `buildSat` does exactly this for a `UArray (Int,Int) Int`; the pattern is portable.

### 2. Use `UArray (Int,Int) Word8` and encode tiles as small ints

Storing tiles as `Char` means the underlying byte array allocates one `Char` per cell (in GHC, `Char` is unboxed-as-`Char#` in `UArray`, which is one *word*-wide entry on a 64-bit machine; not one byte).  Encoding the six tile types as a `Word8` (or even three bits) would shrink the array by 8x.

For 22,500 cells the memory delta is ~150 KB -- not a measurable cache-locality win at this scale, but it would be on a 1000x1000 grid.

### 3. Drop the position map and scan the population

The position-map maintenance is 2x `Map.delete` + 1x `Map.insert` per move = ~3 * O(log n) per cart per tick = ~13 ops per tick at n=12.  Replacing it with a linear scan of `tsCarts` to find "anyone at (ny, nx)" would be O(n) per check = ~12 ops, but the *fixed cost* is lower (no map allocation, no balanced-tree rebalancing).

At n=12 the population scan is faster than the map.  At n>50 the map wins.  Empirically, swapping for the scan saves ~1 ms on Part 2.

### 4. A Part-1-specific `tick` that bails out on first crash

The current `tick` always processes every cart.  A Part-1-only variant could short-circuit:

```haskell
tickStopAtFirst :: ... -> TickState -> Either (Int,Int) TickState
```

Returns `Left newPos` on the first crash, `Right newState` if the whole tick completed without one.  Saves ~50-100 µs on Part 1 by skipping the remaining cart-moves of the crashing tick.  Not worth the code duplication at 290 µs.

### 5. Pre-sort `IM.toList` and never re-sort

`sortOn (\(_, c) -> (cartY c, cartX c))` is paid every tick.  An alternative: maintain `tsCarts` keyed by *position* (a sorted `Map (Int,Int) Cart`) instead of by id, and iterate in key order.  But then "skip if already crashed" needs a side channel again -- the trade-off described in the data-model section.

For ~12 carts the per-tick `sortOn` is ~5 µs; not worth restructuring the state machine for.

### 6. Vector-of-carts instead of `IntMap`

`Data.Vector` with a `Maybe Cart` per slot would be even faster than `IntMap` -- no tree, just array indexing.  But the API friction (the `Maybe` everywhere, the `STVector` for mutation) is not worth it at this puzzle's scale.

---

## Key patterns

1. **Reading-order is `(y, x)` lexicographic.**  Store coordinates as `(y, x)` -- y first -- so that the default tuple `Ord` does reading-order for free.  `sortOn (\(_, c) -> (cartY c, cartX c)) . IM.toList` is the whole sort.

2. **`IntMap` keyed by stable agent id.**  When you have a population of agents that can be removed mid-process and you need a "is this one still alive?" test, `IntMap Cart` plus `IM.lookup i` returning `Nothing` is the right pattern.  Stable ids let you iterate in any order while preserving identity.

3. **Two-map state with a maintained invariant.**  `IntMap Int Cart` + `Map (Int,Int) Int`: the second map is *derived* from the first, but maintaining it explicitly turns "anyone at this cell?" from O(n) into O(log n).  The invariant is your responsibility; in practice every code path that touches `tsCarts` also touches `tsPos`.

4. **Enum-style `data` for direction / turn.**  No fields, just tags; pattern-match dispatch tables.  Exhaustive pattern warnings (`-Wincomplete-patterns`) catch missing cases at compile time -- the most boring kind of bug eliminated for free.

5. **`foldl'` over a tuple accumulator needs component-level bangs.**  `foldl'` forces the tuple to WHNF -- the constructor, not the fields.  Bang patterns on the components (`(!crs, TickState !cm !pm) i`) are required for honest strictness.  This is the kind of subtle laziness trap that turns a 6 ms simulation into a 600 ms one.

---

## Side-by-side with the Rust mental model

```rust
use std::collections::{BTreeMap, BTreeSet, HashMap};

#[derive(Clone, Copy, Debug)]
enum Dir { U, D, L, R }
#[derive(Clone, Copy, Debug)]
enum Turn { Left, Straight, Right }

#[derive(Clone, Debug)]
struct Cart {
    y: i32,
    x: i32,
    dir: Dir,
    turn: Turn,
}

struct Puzzle {
    track: HashMap<(i32, i32), char>,
    carts: Vec<Cart>,
}

fn step_dir(d: Dir) -> (i32, i32) {
    match d {
        Dir::U => (-1, 0),
        Dir::D => ( 1, 0),
        Dir::L => ( 0,-1),
        Dir::R => ( 0, 1),
    }
}

fn reflect_slash(d: Dir) -> Dir {
    match d { Dir::U => Dir::R, Dir::D => Dir::L, Dir::L => Dir::D, Dir::R => Dir::U }
}

fn tick(track: &HashMap<(i32,i32), char>,
        carts:    &mut Vec<Cart>,
        alive:    &mut Vec<bool>,
        pos:      &mut BTreeMap<(i32, i32), usize>) -> Vec<(i32, i32)> {
    let mut order: Vec<usize> = (0..carts.len()).filter(|&i| alive[i]).collect();
    order.sort_by_key(|&i| (carts[i].y, carts[i].x));
    let mut crashes = Vec::new();
    for i in order {
        if !alive[i] { continue; }
        let (oy, ox) = (carts[i].y, carts[i].x);
        pos.remove(&(oy, ox));
        let (dy, dx) = step_dir(carts[i].dir);
        carts[i].y += dy;
        carts[i].x += dx;
        let tile = track.get(&(carts[i].y, carts[i].x)).copied().unwrap_or(' ');
        // ... apply tile ...
        let new = (carts[i].y, carts[i].x);
        if let Some(&j) = pos.get(&new) {
            pos.remove(&new);
            alive[i] = false;
            alive[j] = false;
            crashes.push((new.1, new.0));
        } else {
            pos.insert(new, i);
        }
    }
    crashes
}
```

Lined up:

| Concept                              | Rust                                            | Haskell                                                  |
|--------------------------------------|-------------------------------------------------|----------------------------------------------------------|
| Direction enum                       | `enum Dir { U, D, L, R }`                       | `data Dir = U \| D \| L \| R`                            |
| Turn enum                            | `enum Turn { Left, Straight, Right }`           | `data Turn = TLeft \| TStraight \| TRight`               |
| Cart record                          | `struct Cart { y, x, dir, turn }`               | `data Cart = Cart { cartY :: !Int, ... }`                |
| Track grid                           | `HashMap<(i32,i32), char>` or `Vec<Vec<char>>`  | `UArray (Int,Int) Char`                                  |
| Cart population                      | `Vec<Cart>` + parallel `Vec<bool>` for alive    | `IntMap Cart` (Nothing = dead)                           |
| Position map                         | `BTreeMap<(i32,i32), usize>` for id lookup      | `Map (Int,Int) Int`                                      |
| Reading-order sort                   | `order.sort_by_key(|&i| (carts[i].y, carts[i].x))` | `sortOn (\(_, c) -> (cartY c, cartX c))`              |
| Apply tile (mutate self in place)    | `match tile { '/' => carts[i].dir = ... }`      | `c' = applyTile tile c` (return a new `Cart`)            |
| Mid-tick collision check             | `pos.get(&new).copied()`                        | `Map.lookup new pm0`                                     |
| Crash bookkeeping                    | `alive[i] = false; alive[j] = false;`           | `IM.delete i (IM.delete j cm)`                           |

Two Rust-vs-Haskell themes worth naming.

### Mutation vs threading state

The Rust code mutates `carts[i].y` and `carts[i].x` in place; the Haskell builds a new `Cart` record and re-inserts it.  At first glance this looks like Haskell wasting allocation, but GHC compiles record update with strict fields to a stack-bump (a fresh boxed value, but the fields are unboxed `Int#`).  In practice the wall-time cost is comparable; the conceptual cost is "no mutation, no shared mutable state, no aliasing bugs."

For Day 13's ~17,500 ticks * ~12 carts = ~210,000 cart updates, the allocation cost shows up but is dominated by the `Map`/`IntMap` rebalancing -- which both Rust and Haskell pay equally.

### `IntMap` vs `Vec<bool>` for alive-tracking

Rust's idiomatic structure is `Vec<Cart>` (indexed by id) plus `Vec<bool>` (also indexed by id) for the alive flag.  Haskell could do the same with `Data.IntMap` + `Data.IntSet`, but folding the alive flag into the `IntMap` (`IM.lookup` returning `Nothing` = dead) is cleaner: one source of truth instead of two.

Why doesn't Rust do this?  Because `Vec<bool>` is cache-friendly (one byte per id, packed contiguously), and `HashMap<usize, Cart>` has worse memory layout than `Vec<Cart>`.  Haskell's `IntMap` uses a Patricia trie internally -- already fragmented -- so the "second array of bools" optimisation does not apply.

---

## Further reading

Discrete-event simulators, reading-order semantics, and asynchronous cellular automata.

### Discrete-event simulation, plain

- [**Discrete-event simulation** -- Wikipedia](https://en.wikipedia.org/wiki/Discrete-event_simulation).  The general framework: a system that changes state at discrete points in time, with each event scheduled at a specific time.  Day 13 is a special case where every cart fires an event at every tick, and the "scheduler" is reading-order rather than an explicit time queue.
- [**SimPy** -- Python DES library](https://simpy.readthedocs.io/).  A library for general-purpose DES with explicit event queues, resource contention, and timeouts.  Day 13's `tick` is a degenerate SimPy that lives inside a single time step.

### Asynchronous cellular automata

- [**Asynchronous cellular automaton** -- Wikipedia](https://en.wikipedia.org/wiki/Asynchronous_cellular_automaton).  Formal taxonomy of update orders: synchronous (Day 12), step-driven asynchronous (Day 13, where every cell updates per tick but in a fixed order), and random asynchronous (which Day 13 is *not* -- the order is deterministic).
- [**Cellular automaton -- Synchronous vs. asynchronous**](https://www.scholarpedia.org/article/Asynchronous_cellular_automata).  Scholarpedia article comparing the two, with examples of how the same local rule produces dramatically different macroscopic dynamics depending on update order.

### Entity Component System (ECS)

- [**Entity-component-system** -- Wikipedia](https://en.wikipedia.org/wiki/Entity_component_system).  The `IntMap` keyed by id is the kernel of an ECS: agents have stable ids, their component data is stored separately, queries iterate over the population.  Game engines like Bevy and Unity DOTS scale this pattern to millions of entities.  Day 13's two-map state is a minimal ECS with one "Component" (the `Cart` record) and one "query system" (`tick`).
- [**Bevy ECS book**](https://bevy-cheatbook.github.io/programming/ecs-intro.html).  Practical introduction to the pattern in Rust.  Once you have written Day 13's `tick`, the ECS systems-and-queries vocabulary is familiar -- you have built a one-table version of the same idea.

### Reading-order semantics in AoC

- **AoC 2018 Day 15 -- Beverage Bandits**.  The big puzzle of the year for reading-order asynchronous update.  Agents (Elves and Goblins) take turns in reading order, identify the weakest adjacent enemy in *also* reading order, and attack.  The Day 13 `tick` / `IntMap`-by-id / `Map`-by-pos pattern is the right starting skeleton.  Day 13 is, in retrospect, the warm-up.
- **AoC 2017 Day 22 -- Sporifica Virus**.  Single-agent on an infinite CA grid; the agent moves and modifies cells.  Mixed-mode: the CA is updated by the agent, and the agent's state machine is itself a small graph.

---

**Navigation**: [Problem statement](day13.md) | [Summary table](summary_2018.md) | [<- Day 12](day12_function_guide.md) | Day 14 -> *(not yet attempted)*
