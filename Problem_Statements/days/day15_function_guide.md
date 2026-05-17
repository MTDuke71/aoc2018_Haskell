# Day 15: Beverage Bandits -- Function Guide

**Problem**: Goblins and Elves fight on a grid. Each unit, in reading
order, moves toward and attacks the nearest enemy. Every tie is broken
by reading order. Part 1: the outcome (`rounds * remaining HP`) of the
fight at attack power 3. Part 2: the lowest Elf attack power at which
*no Elf dies*, and that fight's outcome.

**Answers**: Part 1 = **248235**, Part 2 = **46784**
**Code**: [Day15.hs](../../src/Day15.hs) · **Python reference**: [day15.py](../../python/day15.py)
**Runtime**: Parse 37.3 µs · Part 1 231.6 ms · Part 2 2.212 s · Total ≈ 2.44 s

**New concepts this day**:

- **Breadth-first search returning a distance map** (`Map Pos Int`),
  not just a yes/no reachability answer. The distance map is the data
  structure every tie-break reads from.
- **Reading order as `Ord` on `(y, x)`**. Storing positions row-first
  makes "first in reading order" literally `minimum`. No comparator,
  no `Ordering` plumbing -- the type does the work.
- **The two-BFS shortest-step technique**: one BFS to pick *where* to
  go, a second from that square to pick *which first step* lies on a
  shortest path to it.
- **A pure simulation parameterised by a knob and an early-abort
  predicate**. Part 2 is a linear search over Elf attack power; the
  abort makes every losing attempt cheap.

---

## Table of contents

- [Problem summary](#problem-summary)
- [Why reading order *is* the puzzle](#why-reading-order-is-the-puzzle)
- [The algorithm in Python](#the-algorithm-in-python)
- [Data model](#data-model)
- [`parseInput`](#parseinput)
- [`neighbors` -- reading order for free](#neighbors----reading-order-for-free)
- [`bfs` -- a distance map, not a boolean](#bfs----a-distance-map-not-a-boolean)
- [`unitTurn` -- one combatant's turn](#unitturn----one-combatants-turn)
- [`playRound` -- the round loop and the off-by-one](#playround----the-round-loop-and-the-off-by-one)
- [`runCombat` -- the knob and the abort](#runcombat----the-knob-and-the-abort)
- [`part1`, `part2`, `solve`](#part1-part2-solve)
- [Tests](#tests)
- [Benchmarks](#benchmarks)
- [Possible optimization: array BFS](#possible-optimization-array-bfs)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

A cave is a grid of walls (`#`) and open floor (`.`). On the floor
stand Goblins (`G`) and Elves (`E`). Every unit starts with **200 hit
points** and **3 attack power**.

Combat runs in **rounds**. At the start of a round you fix the turn
order: every living unit, sorted by the **reading order** of its
position *right now* (top row first, then left column first). Then
each unit, in that fixed order, takes a turn:

1. **Find targets.** Targets are all units of the other faction. *If
   there are none, combat ends instantly* -- and the round it ended in
   does **not** count.
2. **Already adjacent?** If an enemy is orthogonally adjacent, do not
   move; go straight to the attack.
3. **Otherwise move.** Consider every open square that is adjacent to
   *some* enemy ("in range"). Of the ones the unit can actually reach,
   take the **nearest**; break ties by the reading order of the
   square. Then take **one step** toward it along a shortest path;
   if several first steps are all on *some* shortest path, take the
   one first in reading order.
4. **Attack.** If now adjacent to an enemy, hit the adjacent enemy
   with the **fewest HP** (reading order breaks ties) for `attack
   power` damage. At `HP <= 0` the target dies and its square becomes
   open immediately.

The **outcome** is `(fully completed rounds) * (sum of HP of all
survivors)`.

Part 2: Goblins stay at attack power 3. Find the smallest Elf attack
power such that the Elves win **without losing a single Elf**, and
report that battle's outcome.

---

## Why reading order *is* the puzzle

There is no clever algorithm hiding here. The graph search is plain
breadth-first search on a ~32×32 grid -- first year CS. What makes
Day 15 the puzzle people re-attempt five times is that **four
different decisions are each a tie-break, and they are not the same
tie-break**:

| Decision | Tie broken by |
|----------|---------------|
| Which square to walk to | reading order of the **destination square** |
| Which first step to take | reading order of the **step square** |
| Which adjacent enemy to hit | fewest HP, then reading order of **that enemy** |
| Whose turn is next | reading order of unit positions **at round start** |

Get the wrong tie-break on any one and you pass *some* examples and
fail others -- which is exactly why the test file pins eleven
examples, not one.

The single design decision that makes all of this fall out cleanly:
**store every position as `(y, x)` and never write a comparator.**
Haskell derives `Ord` for tuples lexicographically -- compare the
first component, then the second. For `(row, col)` that is *exactly*
reading order. So:

- "the square first in reading order" → `minimum` of `(dist, pos)`.
- "the enemy first in reading order" → `minimum` of `(hp, pos)`.
- "turn order" → `sortOn pos`.

Every tie-break in the spec collapses to `minimum`/`sortOn` on a tuple
whose last component is the position. The hard part of Day 15 becomes
a non-event the moment the type is right.

### The two-BFS subtlety

Step 3 has a trap. Knowing the nearest reachable in-range square is
**not enough** to know which way to step, because there can be several
shortest paths to it and you must take the reading-order-first *first
step*, not the reading-order-first square at distance 1.

The clean fix is two searches:

1. BFS from the **unit** → distance to every reachable cell. Pick the
   destination = in-range square minimising `(distance, y, x)`.
2. BFS from the **destination** → distance from it to every cell. The
   unit steps onto the neighbour of itself minimising `(distance, y,
   x)`. That neighbour is provably on a shortest path (its distance to
   the goal is one less than the unit's), and the `(.., y, x)` tuple
   picks the reading-order-first such neighbour.

One BFS finds *where*; the second finds *which way*.

---

## The algorithm in Python

The shipping solution is [Day15.hs](../../src/Day15.hs). Because this
day is all algorithm and no Haskell mechanic, the reference
implementation lives at [python/day15.py](../../python/day15.py) and is
worth reading first -- it is the same algorithm with the types
removed. Run it from the repo root:

```
$ python python/day15.py
  part 1: 248235
  part 2: 46784
```

The two functions that carry the puzzle are `bfs` and `turn`:

```python
def bfs(walls, occupied, start):
    dist = {start: 0}
    q = deque([start])
    while q:
        cy, cx = q.popleft()
        for ny, nx in adj(cy, cx):                 # adj() is reading order
            if (ny, nx) in dist: continue
            if (ny, nx) in walls or (ny, nx) in occupied: continue
            dist[(ny, nx)] = dist[(cy, cx)] + 1
            q.append((ny, nx))
    return dist
```

```python
# pick destination, then pick the step toward it
_, chosen = min(reachable)                         # (dist, pos) tuple
dist_from_goal = bfs(walls, occupied, chosen)
step = min((dist_from_goal[p], p)
           for p in adj(me[0], me[1])
           if p not in walls and p not in occupied
              and p in dist_from_goal)[1]
```

Every `min(...)` is over a tuple ending in a position, so every
`min(...)` *is* the reading-order tie-break. The Haskell below is a
near-transliteration; the differences are all about types and purity,
not algorithm.

---

## Data model

```haskell
type Pos = (Int, Int)                 -- (row, col) == (y, x)

data Kind = Goblin | Elf
  deriving (Eq, Show)

data Unit = Unit
  { upos  :: !Pos
  , ukind :: !Kind
  , uhp   :: !Int
  } deriving (Eq, Show)

data Puzzle = Puzzle
  { grid   :: !(UArray Pos Bool)      -- True = open floor, False = wall
  , units0 :: ![Unit]                 -- reading order = parse order
  } deriving (Eq, Show)
```

**Why `(y, x)` and not `(x, y)`** -- this is the whole-day decision,
spelled out above. Row-first tuples sort in reading order under the
*derived* `Ord`, so every tie-break is `minimum`/`sortOn` with no
custom comparator. Day 13 made the same choice for the same reason;
Day 15 leans on it four times instead of one.

**Why a `Bool` array for terrain** -- the terrain never changes during
combat. Only *occupancy* changes (units move and die). Separating the
two means the static part is an immutable `UArray Pos Bool` (cache
friendly, O(1) lookup) and the dynamic part is a small `Map Pos Int`
rebuilt per turn. `True` means "a unit could stand here, wall-wise";
the BFS additionally rejects currently occupied cells.

**Why `Kind` is a bare enum** -- the constructors carry no data; they
are tags, exactly like Day 13's `Dir`/`Turn`. `ukind u /= myKind` is
the entire "is this an enemy?" test.

**Why all `Unit` fields are strict (`!`)** -- HP is decremented on
every hit and position is rewritten on every move. Over the ~thousands
of turns a real battle runs, a lazy field would stack a thunk tower
(`200 - 3 - 3 - 12 - ...`) that is never forced until the end. `!`
forces each update immediately: O(1) space per unit. This is the same
space-leak guard as `foldl'` vs `foldl`, applied to record fields.

**Why `IntMap Unit` for the live population** (built in `mkPopulation`)
-- units are referenced by a stable integer id assigned at parse time
in reading order. An id never changes and is never reused; a dead unit
is simply `IM.delete`d. "Is unit `k` still alive?" is `IM.member k um`.
This is the same id-keyed-population pattern as Day 13's carts, and
the reason is the same: agents that can be removed mid-round need a
stable handle that survives other agents dying.

---

## `parseInput`

```haskell
parseInput :: String -> Puzzle
parseInput raw =
  let rows0  = filter (not . null) (lines raw)
      h      = length rows0
      w      = maximum (1 : map length rows0)
      padded = [ r ++ replicate (w - length r) '#' | r <- rows0 ]
      tagged = [ ((y, x), c)
               | (y, row) <- zip [0 ..] padded
               , (x, c)   <- zip [0 ..] row
               ]
      us     = mapMaybe (\(p, c) -> (\k -> Unit p k 200) <$> kindOf c) tagged
      cells  = [ c /= '#' | (_, c) <- tagged ]
      arr    = listArray ((0, 0), (h - 1, w - 1)) cells :: UArray Pos Bool
  in  Puzzle arr us
```

Functions used here, first appearances flagged:

- `lines :: String -> [String]` -- split on `\n` (seen since Day 1).
- `filter (not . null)` -- drop blank lines so a trailing newline does
  not create a zero-width row. `not . null` is "is non-empty".
- `replicate :: Int -> a -> [a]` -- `replicate 3 '#' == "###"`. Pads
  short rows with wall so the grid is a true rectangle. AoC inputs
  already have a solid `#` border, but padding makes `listArray`'s
  bounds total no matter what.
- `zip [0..] xs` -- the idiomatic Haskell `enumerate`: pair each
  element with its index. Used twice, for `y` over rows and `x` over
  characters. (Seen on Day 13.)
- **`mapMaybe :: (a -> Maybe b) -> [a] -> [b]`** -- map, then keep only
  the `Just`s and strip the `Just`. Here it turns "every tagged cell"
  into "just the cells that are units". `kindOf c` is `Just Goblin`,
  `Just Elf`, or `Nothing`; `(\k -> Unit p k 200) <$> kindOf c` lifts
  the `Unit` constructor over the `Maybe`, and `mapMaybe` discards the
  `Nothing`s. (First explicit use this year; compare Day 8's
  `mapMaybe`.)
- `<$>` -- `fmap`. `f <$> Just x == Just (f x)`, `f <$> Nothing ==
  Nothing`. Read it as "apply `f` inside the `Maybe`".
- `listArray (lo, hi) xs :: UArray Pos Bool` -- build an unboxed
  immutable array filling cells in row-major order from the list. The
  `cells` list is `[ c /= '#' | ... ]` over the *same* `tagged` list
  that drives the units, so terrain and unit positions are guaranteed
  to agree by construction.

`units0` comes out of `mapMaybe` in `tagged` order, and `tagged`
iterates rows then columns -- so it is already in reading order, which
is exactly the id order `mkPopulation` wants.

---

## `neighbors` -- reading order for free

```haskell
neighbors :: Pos -> [Pos]
neighbors (y, x) = [ (y - 1, x), (y, x - 1), (y, x + 1), (y + 1, x) ]
```

Up, left, right, down -- and that list *is already sorted in reading
order* (`(y-1,x) < (y,x-1) < (y,x+1) < (y+1,x)` under the derived tuple
`Ord`). Returning the neighbours pre-sorted is a small thing that pays
off twice: the BFS frontier expands in a deterministic order, and the
"pick the reading-order-first step" in `unitTurn` can use `minimum`
without re-sorting.

---

## `bfs` -- a distance map, not a boolean

```haskell
bfs :: UArray Pos Bool -> Set.Set Pos -> Pos -> Map Pos Int
bfs g blocked start = go (Map.singleton start 0) [start] 1
  where
    ((y0, x0), (y1, x1)) = bounds g
    inBounds (y, x) = y >= y0 && y <= y1 && x >= x0 && x <= x1
    go dist []       _ = dist
    go dist frontier d =
      let ring = Set.toList $ Set.fromList
                   [ p
                   | f <- frontier, p <- neighbors f
                   , inBounds p, g ! p
                   , not (Set.member p blocked)
                   , not (Map.member p dist)
                   ]
          dist' = foldl' (\m p -> Map.insert p d m) dist ring
      in  go dist' ring (d + 1)
```

This is **level-synchronous BFS**: instead of a queue of single
cells, `frontier` is the *entire* current ring of cells at distance
`d - 1`, and one `go` step computes the whole next ring at distance
`d`. Why this shape instead of a `Data.Sequence` queue:

- It needs only `containers` (already a dependency); no new package.
- The distance is implicit in the recursion (`d`), not stored per
  queue element.
- It is obviously correct: BFS visits cells in non-decreasing distance
  order, so the first time a cell is reached is its shortest distance.
  `Map.member p dist` is the visited-set test *and* the
  shortest-distance guarantee in one.

Key details:

- **`dist` doubles as the visited set.** A cell already in `dist` was
  reached on an equal-or-earlier ring, so we never overwrite it. That
  is what makes the distances shortest.
- **`Set.toList . Set.fromList`** dedupes the ring. Two frontier cells
  can both border the same new cell; without the dedupe we would push
  it twice and do redundant work. (`Set.fromList` then `toList` is the
  standard "unique, sorted" idiom -- here we only need unique.)
- **`start` is seeded at 0 and exempt from `blocked`.** The moving
  unit stands on `start`; its own cell must not stop its own search.
  Every *other* unit-occupied cell *is* in `blocked` and so is
  impassable -- units block each other, exactly as the spec says
  ("Units cannot move into walls or other units").
- **`g ! p` is safe** because `inBounds` is checked first and the grid
  has a wall border; we still check `inBounds` defensively so a
  malformed input cannot index out of the array.

The return type is the whole point. A reachability *boolean* would
force a separate search per candidate square. One `bfs` call yields
the distance to *every* reachable cell, so "nearest in-range square"
is one pass plus a `minimum`.

---

## `unitTurn` -- one combatant's turn

This is the heart of the day. It returns a small sum type so the
caller can tell "combat ended" apart from "unit acted":

```haskell
data TurnResult
  = NoTargets                   -- combat is over
  | Acted !(IntMap Unit) !Bool  -- new population; True iff an Elf died
```

The function, in phases.

**Targets.** No enemies anywhere → `NoTargets`, which propagates all
the way up and ends combat:

```haskell
enemies = [ (j, u) | (j, u) <- IM.toList um0, ukind u /= myKind ]
in if null enemies then NoTargets else ...
```

**Occupancy.** `occMap` rebuilds `Map Pos Int` (position → id) from the
`IntMap` once per turn:

```haskell
occMap :: IntMap Unit -> Map Pos Int
occMap um = Map.fromList [ (upos u, i) | (i, u) <- IM.toList um ]
```

Day 13 maintained its `pos → id` map as an invariant across every
move. Day 15 deliberately does **not**: with only a few dozen units,
`Map.fromList` per turn is cheaper than the bookkeeping, and -- more
importantly for a puzzle this tie-break-sensitive -- it removes an
entire class of "the two maps disagreed after a kill" bugs. Clarity
beats the micro-optimisation here; the BFS dominates the runtime
anyway.

**Already in range?** An enemy adjacent → skip the move entirely:

```haskell
adjEnemy p posId um =
  [ j | nb <- neighbors p
      , Just j <- [Map.lookup nb posId]
      , ukind (um IM.! j) /= myKind ]
alreadyInRange = not (null (adjEnemy (upos me) posId0 um0))
```

The `Just j <- [Map.lookup nb posId]` is a **pattern-match guard in a
list comprehension**: `Map.lookup` returns `Maybe Int`; wrapping it in
a singleton list and matching `Just j` keeps only the neighbours that
*are* occupied, binding `j` to the occupant's id. A `Nothing` produces
no element. This is the idiomatic Haskell "filter-and-bind in one".

**Move phase.** Only if not already in range:

```haskell
inRange = Set.fromList
  [ nb | (_, u) <- enemies, nb <- neighbors (upos u)
       , g ! nb, not (Set.member nb occ0) ]
distU = bfs g occ0 (upos me)
reach = [ (d, p) | p <- Set.toList inRange
                  , Just d <- [Map.lookup p distU] ]
```

`reach` is the list of `(distance, square)` for every in-range square
the unit can actually get to. If it is empty the unit cannot make
progress and the turn ends. Otherwise:

```haskell
chosen = snd (minimum reach)          -- nearest; ties by reading order
distC  = bfs g occ0 chosen            -- second BFS, from the goal
steps  = [ (d, p) | p <- neighbors (upos me)
                   , g ! p, not (Set.member p occ0)
                   , Just d <- [Map.lookup p distC] ]
step   = snd (minimum steps)          -- first step on a shortest path
me'    = me { upos = step }
```

`minimum reach` picks the smallest `(d, p)`: smallest distance first,
and `p = (y, x)` breaks the distance tie in reading order -- because
the tuple `Ord` *is* reading order. The second BFS from `chosen` gives
distance-from-the-goal to every cell; among the unit's own neighbours,
`minimum steps` is the one closest to the goal, ties again by reading
order of the step square. That neighbour is necessarily on a shortest
path (its goal-distance is one less than the unit's), so the unit is
guaranteed to make progress. `me { upos = step }` is **record update
syntax**: a new `Unit` identical to `me` but with `upos` replaced.

**Attack phase.** From wherever the unit now stands:

```haskell
target = snd $ minimum
           [ ((uhp (um1 IM.! j), upos (um1 IM.! j)), j) | j <- foes ]
power  = if myKind == Elf then eap else 3
hp'    = uhp tgt - power
in if hp' <= 0
     then Acted (IM.delete target um1) (ukind tgt == Elf)
     else Acted (IM.insert target tgt { uhp = hp' } um1) False
```

The selection key is `(uhp, upos)`: fewest HP first, reading order of
the enemy's position breaking the HP tie. One `minimum` again. Goblins
always hit for 3; Elves hit for `eap`, the knob Part 2 turns. A lethal
hit `IM.delete`s the victim and the `Bool` in `Acted` records *whether
that victim was an Elf* -- the single fact Part 2's abort needs.

---

## `playRound` -- the round loop and the off-by-one

```haskell
playRound g eap umStart =
  let order = map fst $ sortOn (\(_, u) -> upos u) (IM.toList umStart)
      go []       um elf = (False, um, elf)
      go (k : ks) um elf
        | not (IM.member k um) = go ks um elf       -- died this round
        | otherwise =
            case unitTurn g eap k um of
              NoTargets        -> (True, um, elf)
              Acted um' elfHit -> go ks um' (elf || elfHit)
  in  go order umStart False
```

`order` is computed **once**, from `umStart` -- positions *at the
start of the round*. The spec is explicit that turn order is fixed at
round start even though units move during the round, and that is
exactly what "snapshot `umStart`, never re-sort" encodes. A unit
killed earlier in the same round is skipped via `IM.member k um` (its
id is gone from the live map) -- the same id-as-liveness trick as
Day 13.

The return is `(combatEnded, population, anElfDied)`. The off-by-one
that trips everyone: when a unit's `unitTurn` returns `NoTargets`,
`go` returns `(True, um, elf)` **without finishing the rest of
`order`**. Combat ended *during* this round, so this round must not
count. `runCombat` only increments its round counter when a round
returns `combatEnded = False`, i.e. every unit completed its turn.

---

## `runCombat` -- the knob and the abort

```haskell
runCombat g eap abortOnElfDeath = loop 0
  where
    loop !rounds um =
      case playRound g eap um of
        (_, _, True) | abortOnElfDeath -> Nothing
        (True,  um', _)  -> Just (rounds, sumHp um')
        (False, um', _)  -> loop (rounds + 1) um'
    sumHp = IM.foldl' (\acc u -> acc + uhp u) 0
```

Two parameters carry both parts:

- **`eap`** -- Elf attack power. Part 1 passes 3 (everyone equal).
  Part 2 sweeps it upward.
- **`abortOnElfDeath`** -- if set, the *instant* any round reports an
  Elf death, bail with `Nothing`. This is what makes the Part 2 search
  affordable: a doomed attack power is abandoned the moment the first
  Elf falls, not after simulating the whole losing battle.

`!rounds` is a bang pattern so the round counter is forced each
iteration rather than building `0 + 1 + 1 + ...` thunks across
(potentially) thousands of rounds -- the same discipline as a strict
`foldl'` accumulator. `sumHp` uses `IM.foldl'` (strict left fold over
the map's values) for the same reason.

```haskell
outcomeAt g um =
  case runCombat g 3 False um of
    Just (r, hp) -> r * hp
    Nothing      -> error "Day15.outcomeAt: unreachable"

lowestNoDeathOutcome g um = go 4
  where
    go !ap = case runCombat g ap True um of
      Just (r, hp) -> r * hp        -- Elves finished intact => they won
      Nothing      -> go (ap + 1)
```

Part 1 never aborts, so the `Nothing` branch of `outcomeAt` is
genuinely unreachable -- `error` documents that invariant rather than
inventing a wrong number. Part 2 searches `ap = 4, 5, 6, ...` (3 is
the Part 1 baseline; the Elves need *more* than that). A `Just` from
the aborting `runCombat` can only mean *no Elf ever died* -- and a
battle that ends with Elves alive is a battle the Elves won, because
combat only ends when one faction is wiped out. So the first `Just`
is the answer; no separate "did the Elves win?" check is needed.

---

## `part1`, `part2`, `solve`

```haskell
mkPopulation us = IM.fromList (zip [0 ..] us)   -- id = reading-order index

part1 (Puzzle g us) = outcomeAt           g (mkPopulation us)
part2 (Puzzle g us) = lowestNoDeathOutcome g (mkPopulation us)

solve contents = do
  let puzzle = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 puzzle))
  putStrLn ("  part 2: " ++ show (part2 puzzle))
```

`mkPopulation` assigns id `0` to the first unit in `units0` (which is
reading order), id `1` to the next, and so on -- the ids `playRound`'s
`order` and the `IM.member` liveness test rely on. Both parts parse
through the shared `puzzle` binding, so the terrain array is built
once.

---

## Tests

[test/Day15Spec.hs](../../test/Day15Spec.hs) pins **fourteen** cases,
deliberately more than usual: the narrated 27730 battle, all five
"summarized combats" from the puzzle text for Part 1, four Part 2
attack-power searches, a structural parse check, and both real-input
answers. The reason for the over-coverage is in
[Why reading order *is* the puzzle](#why-reading-order-is-the-puzzle):
a wrong tie-break passes the simplest example and fails a harder one,
so one example proves nothing. The summarized combats (`exA`..`exE`)
are specifically the ones AoC chose to exercise different tie-break
corners.

```haskell
it "narrated example -> 27730" $ p1 ex0 `shouldBe` 27730
it "summarized E -> 18740"     $ p1 exE `shouldBe` 18740
it "summarized E -> 1140"      $ p2 exE `shouldBe` 1140
```

`shouldBe` reads like `assert_eq!(actual, expected)`. The real-input
expected values are factored into `actualPart1`/`actualPart2` so the
two `readFile` tests stay one line each.

---

## Benchmarks

| Bench | Mean |
|-------|------|
| `parseInput` | 37.3 µs |
| `part1` | 231.6 ms |
| `part2` | 2.212 s |
| `combined` | 2.446 s |
| **Total (Parse+P1+P2)** | **≈ 2.44 s** |

- **Part 1 is one full battle**: ~80 rounds × a few dozen units × two
  BFS per moving unit over a ~700-open-cell grid. 232 ms is dominated
  entirely by the `Map`-based BFS allocating a fresh `Map Pos Int`
  every search.
- **Part 2 ≈ 9–10× Part 1**: the attack-power search runs roughly ten
  full battles before it finds the no-Elf-death threshold. The abort
  helps the *early* low-power attempts (they end fast, with a dead
  Elf) but the winning high-power run is a complete battle, so the
  multiplier stays near "number of attack powers tried".
- This is the slowest day of the year so far (Day 14 was 211 ms;
  Day 15 is 2.44 s total). It is well under the 10 s "something is
  wrong" line, but over the 1 s "look for an algorithmic improvement"
  line -- the improvement is real and is the BFS representation, not
  micro-optimisation. See the next section.

---

## Possible optimization: array BFS

*Untested pseudo-Haskell -- the shipping `Day15.hs` keeps the
idiomatic `Map`-based BFS for readability; this is the documented
faster path.*

The BFS is ~95 % of the runtime, and its cost is almost all
`Data.Map` allocation: every search builds a brand-new `Map Pos Int`
of up to ~700 entries, and a moving unit triggers two searches per
turn. The grid is small and dense -- a textbook case for an **unboxed
array distance buffer** instead of a balanced tree:

```haskell
-- One reusable STUArray Pos Int, sentinel -1 = unvisited, refilled
-- per search instead of allocated fresh:
bfsArr :: UArray Pos Bool -> UArray Pos Bool -> Pos -> ST s (STUArray s Pos Int)
bfsArr terrain occ start = do
  d <- newArray (bounds terrain) (-1)
  writeArray d start 0
  let loop [] = pure ()
      loop frontier = do
        nxt <- concat <$> mapM expand frontier   -- expand: neighbours
        loop nxt                                  -- with O(1) array
      ...                                         -- visited/distance
  loop [start]
  pure d
```

Replacing `Map Pos Int` lookups/inserts (O(log n), pointer-chasing,
GC pressure) with `UArray Pos Int` reads/writes (O(1), contiguous, no
per-search allocation) is the same Day 9 / Day 11 / Day 14 move:
*when the index space is small and dense, an unboxed array beats a
tree.* Expected effect on this puzzle: roughly an order of magnitude,
bringing Part 2 from ~2.2 s into the low-hundreds-of-ms range. The
algorithm is unchanged -- only the distance container is.

A second, smaller win: Part 2 could **binary-search** the attack
power instead of scanning `4, 5, 6, ...`. "Elves win with no deaths"
is monotone in attack power (more power never *causes* an Elf death),
so a bisection over a sane upper bound (say 200) is ~log₂ instead of
linear in the threshold. In practice the threshold is small (single
digits to low teens) so the linear scan is already close to optimal;
the array BFS is where the order-of-magnitude lives.

---

## Key patterns

1. **Make the type do the tie-break.** Storing positions `(y, x)` and
   reusing the derived tuple `Ord` turned four different "first in
   reading order" rules into four `minimum`s. The alternative -- a
   hand-written `compareReadingOrder` threaded through every decision
   -- is where Day 15 implementations usually get a tie-break subtly
   wrong. Pick the representation that makes the invariant free.

2. **Return the richest cheap thing.** `bfs` returns a *distance map*,
   not a boolean or a single distance. One search then answers
   "nearest in-range square", "is `p` reachable", and "distance to
   `p`" with no extra work. Computing the general object once beats
   computing the specific answer many times.

3. **Two searches to resolve a path tie-break.** When you must pick
   the first step of a shortest path (not just the endpoint), BFS from
   the *goal* and read off the neighbour with the smallest
   goal-distance. This "search backward from the target" trick recurs
   across grid puzzles.

4. **Parameter + abort = a cheap search.** A pure simulation that
   takes a knob (`eap`) and a fail-fast predicate
   (`abortOnElfDeath`) turns "find the smallest input with property
   P" into a short linear scan, because the failing attempts die early
   instead of running to completion.

---

## If I were writing this in Rust

The shape is identical; the differences are all ownership and the
absence of derived tuple `Ord` doing reading order for free (Rust
*does* derive lexicographic `Ord` on tuples too -- so `(y, x)` works
the same way; this is one of the rare days where the two languages
line up almost exactly).

- `IntMap Unit` → `HashMap<u32, Unit>` or a `Vec<Option<Unit>>`
  indexed by id (dead = `None`). The `Vec<Option<_>>` is what most
  fast Rust solutions use; `IM.member` becomes `v[id].is_some()`.
- `bfs` returning `Map Pos Int` → a `HashMap<(i32,i32), u32>`, or --
  the fast version -- a flat `vec![u32::MAX; w*h]` distance buffer
  reused across searches with a `VecDeque` frontier. That flat buffer
  *is* the [array BFS](#possible-optimization-array-bfs) optimisation;
  Rust solutions reach for it by default, which is why a Rust Day 15
  is typically ~20 ms where this Haskell is ~2.4 s. The gap is the
  container, not the language.
- `minimum reach` → `reach.into_iter().min().unwrap()`. Rust's
  `Ord` on `(u32, (i32, i32))` is the same lexicographic order, so
  the tie-break is identical -- `min()` is reading order, same as
  here.
- `me { upos = step }` (record update) → `me.pos = step;` -- Rust
  mutates in place; Haskell returns a new record and threads it
  through `IM.insert`. Same effect, different default.
- `runCombat`'s `abortOnElfDeath -> Nothing` → returning
  `Option<(u32,u32)>` or a `Result` and `?`-propagating the
  early-out. The Haskell `Maybe` and Rust `Option` are the same idea.

The honest takeaway: Day 15's algorithm is language-neutral and
short; the 100× runtime gap to Rust is entirely "fresh `Data.Map` per
BFS" vs "one reused flat array", and is closed by the optimisation
sidebar, not by rewriting in Rust.

---

**Navigation**: [← Day 14](day14_function_guide.md) | [All Days](summary_2018.md) | [Day 16 →](day16_function_guide.md)
