# Day 24: Immune System Simulator 20XX -- Function Guide

**Problem**: Two armies (Immune System, Infection), each a set of
*groups* of identical *units*. Each group has hit points, an attack
(damage + type), an initiative, and optional weaknesses/immunities.
Combat is a sequence of *fights*; each fight runs a *target selection*
phase then an *attacking* phase, both with fiddly ordering rules.
Part 1: total units in the winning army. Part 2: the smallest attack
*boost* added to every Immune System group that lets it win — report
its surviving units.

**Answers**: Part 1 = **15165**, Part 2 = **4037**
**Code**: [Day24.hs](../../src/Day24.hs) · **Python reference**: [day24.py](../../python/day24.py)
**Runtime**: Parse 156.6 µs · Part 1 3.99 ms · Part 2 200.9 ms · Total ≈ 205 ms

**New concepts this day**:

- **Tuple `Ord` + `Down` *is* the tie-break specification.** Both combat
  phases sort groups by several keys in mixed directions. We never write
  a comparator — we `sortOn` a tuple whose lexicographic `Ord` encodes
  the rule, wrapping descending keys in `Down`.
- **`IntMap` as a population of living entities keyed by id.** Groups
  take damage, shrink, and die mid-fight. Keying them by a stable id
  lets an attacker look up its (possibly already-weakened or dead)
  target by reference rather than by position in a list.
- **Stalemate / fixed-point detection.** A fight that kills zero units
  leaves combat in exactly the same state forever. Detecting it turns a
  non-terminating loop into a decidable `Stalemate` — the same trick as
  the cycle detection on Days 12 and 18.
- **Linear threshold search.** Part 2 is "smallest boost that flips the
  outcome." A list comprehension over `[1..]` with a pattern guard
  finds it in one line.
- **Keyword-anchored parsing.** No parser combinator: locate each field
  by the fixed word next to it (`units`, `does`, `initiative`) and lift
  the optional `(...)` clause out separately.

---

## Table of contents

- [Problem summary](#problem-summary)
- [The algorithm in Python](#the-algorithm-in-python)
- [Data model](#data-model)
- [Parsing](#parsing)
- [Combat](#combat)
- [`part1`](#part1)
- [`part2` — the boost search](#part2--the-boost-search)
- [Key patterns](#key-patterns)
- [If I were writing this in Rust](#if-i-were-writing-this-in-rust)

---

## Problem summary

This is the calendar's most *rule-dense* puzzle. There is no clever
algorithm — the entire difficulty is implementing the combat rules
*exactly*, because a single mis-ordered tie-break passes the example and
fails the real input (or vice versa). The rules, precisely:

A **group** is `N` units, each with `hp` hit points, dealing `attack`
damage of one `type`, with an `initiative`, optionally `weak to` some
types (take **double** damage) and/or `immune to` others (take **zero**).
A group's **effective power** is `units × attack`.

A **fight** has two phases:

1. **Target selection.** In decreasing effective power (ties: higher
   initiative), each group picks the enemy group it would deal the
   *most* damage to. Damage here ignores the defender's unit count — it
   is just `effective_power × (0 | 1 | 2)` depending on immunity/weakness.
   Ties on damage break toward the defender with the largest effective
   power, then highest initiative. A group that can deal no damage to
   anyone picks nothing, and **each defender can be chosen by only one
   attacker**.

2. **Attacking.** In decreasing initiative (across *both* armies
   interleaved), each group that has a target deals damage. The defender
   loses `floor(damage / hp)` whole units (capped at its size). A group
   reduced to zero units is removed.

Fights repeat until one army has no groups left. **Part 1** asks for the
total units in the winner.

**Part 2** introduces a *boost*: a fixed number added to the per-unit
attack damage of *every* Immune System group. Find the smallest boost
that makes the Immune System win, and report how many units it has left.
The wrinkle: some boosts produce a **stalemate** — a fight in which
*no* unit dies, because every remaining attacker is immune to or too
weak against every target it can reach. Combat would loop forever; we
must detect "a fight killed nobody" and call it a draw (not an Immune
win).

---

## The algorithm in Python

The full reference is [day24.py](../../python/day24.py). The combat
rules read most clearly in straight-line imperative code. One fight:

```python
def fight(groups):
    # --- target selection ---
    chosen, targeted = {}, set()
    order = sorted(groups, key=lambda g: (-g.power, -g.initiative))
    for atk in order:
        enemies = [d for d in groups
                   if d.army != atk.army and id(d) not in targeted
                   and atk.damage_to(d) > 0]
        if not enemies:
            continue
        best = max(enemies, key=lambda d: (atk.damage_to(d), d.power, d.initiative))
        chosen[id(atk)] = best
        targeted.add(id(best))

    # --- attacking ---
    killed = 0
    for atk in sorted(groups, key=lambda g: -g.initiative):
        if atk.units <= 0 or id(atk) not in chosen:
            continue
        d = chosen[id(atk)]
        dead = min(d.units, atk.damage_to(d) // d.hp)
        d.units -= dead
        killed += dead

    groups[:] = [g for g in groups if g.units > 0]
    return killed
```

Note every ordering is a `sorted(..., key=lambda g: (-a, -b))` — a tuple
with negated keys for "descending." The Haskell version is the same idea
with `Down` instead of negation (you can't negate `initiative` when the
key might be a string, and `Down` works for any `Ord`). The combat loop
and the boost search:

```python
def run_combat(groups):
    groups = deepcopy(groups)
    while True:
        armies = {g.army for g in groups}
        if len(armies) <= 1:
            return (armies.pop() if armies else None, sum(g.units for g in groups))
        if fight(groups) == 0:
            return None, 0                          # stalemate

def part2(groups):
    boost = 1
    while True:
        boosted = deepcopy(groups)
        for g in boosted:
            if g.army == "immune":
                g.attack += boost
        army, units = run_combat(boosted)
        if army == "immune":
            return units
        boost += 1
```

The Haskell mirrors this structurally, with an `IntMap Group` standing
in for the mutable list and a list comprehension standing in for the
`while boost` loop.

---

## Data model

```haskell
data Army = Immune | Infection deriving (Eq, Show)

data Group = Group
  { gId         :: !Int       -- stable identity (unique across both armies)
  , gArmy       :: !Army
  , gUnits      :: !Int
  , gHp         :: !Int
  , gWeak       :: [String]   -- attack types this group takes double from
  , gImmune     :: [String]   -- attack types this group takes zero from
  , gAttack     :: !Int       -- damage per unit
  , gAttackType :: !String
  , gInit       :: !Int       -- higher attacks first, wins ties
  } deriving (Eq, Show)

type Puzzle = [Group]

data Outcome = Win Army Int | Stalemate deriving (Eq, Show)
```

**Why these choices**:

- `Group` is a nine-field **record**. Tuples stopped scaling around
  Day 6; with nine heterogeneous fields a record with named accessors
  (`gUnits`, `gHp`, …) is the only readable option. The `g` prefix is
  the Haskell convention for dodging the fact that record field names
  share the module namespace — without it, a field called `units` would
  collide with anything else named `units`.
- **Every field is strict (`!`)** except the two lists. Each is a small
  `Int`/`String` read once, and the simulation reads `gUnits`/`gAttack`/
  `gHp` in tight loops; there is no value in deferring them. (The lists
  are left lazy only because there's no strict-list annotation in plain
  record syntax; they're forced in practice by `elem`.)
- **`gId` is the load-bearing field.** A group's unit count changes
  every fight, so we cannot identify a group by its value. The id is a
  fixed handle: target selection records "attacker 7 hits defender 12,"
  and the attack phase looks up 12's *current* state by that id. We
  assign ids `1..` across both armies so a single `IntMap` holds
  everyone.
- `Outcome` is a small sum type so Part 2 can distinguish "Immune won"
  from "Infection won" from "nobody won (stalemate)" — three cases a
  bare `Int` couldn't carry.

The internal live-state type is `IntMap Group` keyed by `gId`. `IntMap`
(from `Data.IntMap.Strict`) is a map specialised to `Int` keys — a
big-endian Patricia tree, faster than a general `Map Int` and exactly
the right fit when your keys are small integers (it's the Day 21 / Day 9
"int-keyed collection" again).

---

## Parsing

The line format is fixed except for an optional parenthetical:

```
18 units each with 729 hit points (weak to fire; immune to cold, slashing) with an attack that does 8 radiation damage at initiative 10
```

Rather than reach for a parser combinator (this codebase has not pulled
in `megaparsec`), we exploit that every field sits next to a fixed
**keyword**, and the only variable structure — the `(...)` clause — can
be sliced out first.

```haskell
parseInput :: String -> Puzzle
parseInput input = immune ++ infection
 where
  ls          = lines input
  immuneLines = takeBlock "Immune System:" ls
  infectLines = takeBlock "Infection:"     ls
  immune      = zipWith (parseGroup Immune)    [1 ..]                 immuneLines
  infection   = zipWith (parseGroup Infection) [length immune + 1 ..] infectLines

takeBlock :: String -> [String] -> [String]
takeBlock header =
  takeWhile (not . null) . drop 1 . dropWhile (/= header)
```

- `takeBlock` is a three-stage pipeline read right to left:
  `dropWhile (/= header)` discards lines until the header,
  `drop 1` drops the header itself, and `takeWhile (not . null)` keeps
  the group lines until the blank separator. New functions:
  `dropWhile :: (a -> Bool) -> [a] -> [a]` drops the leading run
  satisfying the predicate; `takeWhile` keeps it. `null :: [a] -> Bool`
  is the empty-list test.
- `zipWith :: (a -> b -> c) -> [a] -> [b] -> [c]` pairs two lists
  element-wise through a function. `zipWith (parseGroup Immune) [1..]
  immuneLines` feeds each line *and* a fresh id from the infinite list
  `[1..]` into `parseGroup`. `zipWith` stops at the shorter list, so the
  infinite `[1..]` is safely truncated to the number of group lines —
  laziness again. The infection ids start at `length immune + 1` so no
  two groups collide.

```haskell
parseGroup :: Army -> Int -> String -> Group
parseGroup army gid line = Group
  { gId = gid, gArmy = army
  , gUnits      = numBefore "units"
  , gHp         = numBefore "hit"
  , gWeak       = weak
  , gImmune     = immune
  , gAttack     = numAfter "does"
  , gAttackType = ws !! (idxOf "damage" - 1)
  , gInit       = numAfter "initiative"
  }
 where
  (weak, immune) = parseMods line
  ws             = words (stripParens line)
  idxOf kw       = case elemIndex kw ws of
                     Just i  -> i
                     Nothing -> error ("Day24.parseGroup: no " ++ show kw ++ " in " ++ show line)
  numBefore kw   = read (ws !! (idxOf kw - 1))
  numAfter  kw   = read (ws !! (idxOf kw + 1))
```

- `stripParens` (below) deletes the `(...)` clause, so `ws` is the
  fixed skeleton: `["18","units","each","with","729","hit","points",
  "with","an","attack","that","does","8","radiation","damage","at",
  "initiative","10"]`.
- `elemIndex :: Eq a => a -> [a] -> Maybe Int` (from `Data.List`) finds
  the position of the first matching element, or `Nothing`. `idxOf`
  unwraps it, exploding loudly on a malformed line.
- `numBefore`/`numAfter` read the integer one slot before/after a
  keyword. `gHp = numBefore "hit"` grabs the number left of `"hit"`;
  `gAttack = numAfter "does"`; `gInit = numAfter "initiative"`. The
  attack *type* is the word just before `"damage"`. This keyword anchoring
  is robust to the stripped parenthetical leaving a double space —
  `words` collapses runs of whitespace.
- `(!!) :: [a] -> Int -> a` is list indexing (`O(n)`). Fine here: each
  line is ~18 short words, parsed once.

```haskell
stripParens :: String -> String
stripParens s = case break (== '(') s of
  (before, '(' : r) -> before ++ drop 1 (dropWhile (/= ')') r)
  (before, _)       -> before

parseMods :: String -> ([String], [String])
parseMods line = case break (== '(') line of
  (_, '(' : r) -> foldl' addClause ([], []) (splitOn ';' (takeWhile (/= ')') r))
  _            -> ([], [])
 where
  addClause (w, i) clause =
    case words (map commaToSpace clause) of
      ("weak"   : "to" : ts) -> (w ++ ts, i)
      ("immune" : "to" : ts) -> (w, i ++ ts)
      _                      -> (w, i)
  commaToSpace c = if c == ',' then ' ' else c
```

- `break :: (a -> Bool) -> [a] -> ([a], [a])` splits a list at the first
  element satisfying the predicate, *keeping* that element at the head
  of the second part. `break (== '(') s` gives everything before the
  paren and everything from the paren on. The pattern `(before, '(':r)`
  matches *only when a `(` was found* (the second part starts with it);
  the fallthrough `(before, _)` covers the no-parenthetical lines.
- `stripParens` rebuilds the line without the clause:
  `before ++ drop 1 (dropWhile (/= ')') r)` keeps the prefix and the
  suffix after `)`.
- `parseMods` instead keeps the clause's *interior*
  (`takeWhile (/= ')') r`), splits it on `;` into "weak to …" / "immune
  to …" parts, and folds each into a `(weak, immune)` pair. Turning
  commas into spaces lets `words` split the type list; the pattern
  `("weak":"to":ts)` peels the leading two words and binds the rest as
  the type list. `parseMods` returns `([],[])` for groups with no clause.

```haskell
splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, [])       -> [a]
  (a, _ : rest) -> a : splitOn c rest
```

A tiny hand-rolled splitter (the codebase has no `Data.List.Split`).
`break` finds the next separator; if there is none we return the final
chunk, otherwise we cons the chunk and recurse on the tail past the
separator.

---

## Combat

Two pure geometry-free helpers first:

```haskell
effectivePower :: Group -> Int
effectivePower g = gUnits g * gAttack g

damageTo :: Group -> Group -> Int
damageTo atk def
  | gAttackType atk `elem` gImmune def = 0
  | gAttackType atk `elem` gWeak   def = 2 * effectivePower atk
  | otherwise                          = effectivePower atk
```

`damageTo` is the rules' core: immune → 0, weak → double, else full
power. `elem :: Eq a => a -> [a] -> Bool` is list membership; the
weakness/immunity lists are tiny so a linear scan is free.

### Target selection

```haskell
selectTargets :: IntMap Group -> IntMap Int
selectTargets groups = go Set.empty IntMap.empty pickingOrder
 where
  pickingOrder =
    sortOn (\g -> (Down (effectivePower g), Down (gInit g))) (IntMap.elems groups)

  go _ acc [] = acc
  go taken acc (a : rest) =
    case candidates of
      [] -> go taken acc rest
      _  -> let d = maximumBy (comparing rank) candidates
            in  go (Set.insert (gId d) taken) (IntMap.insert (gId a) (gId d) acc) rest
   where
    candidates = [ d | d <- IntMap.elems groups
                     , gArmy d /= gArmy a
                     , not (gId d `Set.member` taken)
                     , damageTo a d > 0 ]
    rank d = (damageTo a d, effectivePower d, gInit d)
```

This is where the **tuple-`Ord`-as-tie-break** idea earns its keep.

- `sortOn :: Ord b => (a -> b) -> [a] -> [a]` sorts by a projection
  (computing it once per element — the Schwartzian transform). The
  projection here is `(Down (effectivePower g), Down (gInit g))`.
- `Down :: a -> Down a` (from `Data.Ord`) is a newtype that **flips an
  `Ord`**: `Down x <= Down y` iff `y <= x`. Wrapping both keys in `Down`
  makes `sortOn` order by effective power *descending*, then initiative
  *descending* — exactly "strongest picks first, ties to higher
  initiative." No comparator, no `sortBy`, just a tuple. The lexicographic
  `Ord` derived for tuples does the rest: compare the first components,
  and only on a tie look at the second.
- `go` walks the attackers in that order, threading two accumulators: a
  `Set` of defender ids already `taken`, and the `IntMap` of chosen
  `attacker → defender` assignments. `Set.member`/`Set.insert` enforce
  "each defender chosen once."
- For each attacker, `candidates` are live enemies not yet taken that it
  can actually damage. `maximumBy (comparing rank)` then picks the best,
  where `rank d = (damageTo a d, effectivePower d, gInit d)` — most
  damage, then most effective power, then highest initiative. Here we
  want the *maximum*, so plain ascending tuple `Ord` with `maximumBy` is
  right (no `Down` needed). `comparing :: Ord b => (a -> b) -> a -> a ->
  Ordering` builds the comparison from the projection;
  `maximumBy :: (a -> a -> Ordering) -> [a] -> a` returns the greatest.
  Because every initiative is unique, `rank` is a strict total order —
  there are never exact ties, so the choice is unambiguous.

### Attacking

```haskell
fight :: IntMap Group -> (IntMap Group, Int)
fight groups = foldl' attackStep (groups, 0) attackOrder
 where
  targets     = selectTargets groups
  attackOrder = map gId
              . sortOn (Down . gInit)
              . filter ((`IntMap.member` targets) . gId)
              $ IntMap.elems groups

  attackStep (gs, killed) aid =
    case IntMap.lookup aid gs of
      Nothing  -> (gs, killed)            -- attacker died earlier this fight
      Just atk ->
        case IntMap.lookup (targets IntMap.! aid) gs of
          Nothing  -> (gs, killed)
          Just def ->
            let dead = min (gUnits def) (damageTo atk def `div` gHp def)
                def' = def { gUnits = gUnits def - dead }
                gs'  | gUnits def' <= 0 = IntMap.delete (gId def) gs
                     | otherwise        = IntMap.insert (gId def) def' gs
            in  (gs', killed + dead)
```

- `attackOrder` is the ids of every group that selected a target, sorted
  by initiative **descending** (`Down . gInit`). Initiative order spans
  both armies — there is no per-army interleaving, which is why a single
  `IntMap` holding everyone is the natural structure.
- `foldl' attackStep (groups, 0) attackOrder` threads the evolving group
  map and a running kill count through the attacks. `foldl'` (strict
  left fold) keeps the `(IntMap, Int)` pair forced as it goes.
- Each `attackStep` re-looks-up the attacker **by id in the current
  map**, because a higher-initiative enemy may already have killed it
  this fight — `IntMap.lookup aid gs = Nothing` means "skip, it's dead."
  Likewise the defender is looked up fresh, and its damage is computed
  from the attacker's *current* unit count (its effective power may have
  shrunk earlier this fight). This is the whole reason for the
  id-keyed map: identity that survives mutation.
- `dead = min (gUnits def) (damageTo atk def \`div\` gHp def)` — integer
  division floors the kill count, capped at the defender's size.
  A defender at zero units is `IntMap.delete`d (so the map only ever
  holds live groups); otherwise it is re-`insert`ed with fewer units.

### The combat loop

```haskell
runCombat :: [Group] -> Outcome
runCombat gs0 = go (IntMap.fromList [ (gId g, g) | g <- gs0 ])
 where
  go gs
    | not immuneLeft || not infectLeft =
        Win (if immuneLeft then Immune else Infection) (sum (map gUnits elems))
    | otherwise =
        let (gs', killed) = fight gs
        in  if killed == 0 then Stalemate else go gs'
   where
    elems      = IntMap.elems gs
    immuneLeft = any ((== Immune)    . gArmy) elems
    infectLeft = any ((== Infection) . gArmy) elems
```

- The map starts as `IntMap.fromList [(gId g, g) | g <- gs0]` — a list
  comprehension building `(key, value)` pairs.
- `any :: (a -> Bool) -> [a] -> Bool` tests whether any element matches;
  `any ((== Immune) . gArmy) elems` is "is any group still on the Immune
  side?" When one side is empty, the other has won, and we sum the
  survivors' units.
- **Stalemate detection** is the one line `if killed == 0 then
  Stalemate`. A fight that kills nobody cannot change the state, so the
  next fight would be identical forever. Returning `Stalemate` makes
  `runCombat` total — it always terminates, because every non-stalemate
  fight strictly reduces the total unit count, which is bounded below by
  zero. This is the Day 12 / Day 18 cycle-detection instinct applied to
  a degenerate period-1 cycle.

---

## `part1`

```haskell
part1 :: Puzzle -> Int
part1 gs = case runCombat gs of
  Win _ n   -> n
  Stalemate -> error "Day24.part1: unexpected stalemate"
```

Just run combat and read off the winner's units. The unboosted real
input has a decisive winner, so the `Stalemate` branch is a guard
against a mis-parse rather than an expected case.

---

## `part2` — the boost search

```haskell
boostImmune :: Int -> [Group] -> [Group]
boostImmune b = map bump
 where
  bump g
    | gArmy g == Immune = g { gAttack = gAttack g + b }
    | otherwise         = g

part2 :: Puzzle -> Int
part2 gs = head [ n | b <- [1 ..], Win Immune n <- [runCombat (boostImmune b gs)] ]
```

- `boostImmune b` adds `b` to every Immune group's per-unit attack via a
  record update `g { gAttack = gAttack g + b }`, leaving Infection
  groups untouched.
- `part2` is a one-line **linear threshold search**. Read the list
  comprehension as: for each boost `b` from 1 upward, run combat, and —
  this is the clever bit — bind `Win Immune n` against the *singleton
  list* `[runCombat …]`. A pattern in a comprehension generator acts as
  a filter: if `runCombat` returns `Win Infection _` or `Stalemate`, the
  pattern `Win Immune n` fails to match and that `b` is silently
  dropped. So the comprehension yields `n` only for boosts where the
  Immune System wins, and `head` takes the first (smallest) one.

Why linear and not binary search? The outcome is *almost* monotone in
the boost — more attack never hurts the Immune System — but integer
unit-kill rounding and the discrete tie-breaks mean it is not
*guaranteed* monotone, so a binary search can land in a false trough and
return a non-minimal boost. Linear search is provably correct and, at
~200 ms for this input (the smallest winning boost is small), fast
enough. Each boost runs a full combat from scratch; the search is the
entire Part 2 cost.

### Possible optimization

1. **Binary-search the boost with a re-scan.** In practice the outcome
   *is* monotone on AoC inputs, so a binary search over a generous range
   then a short linear back-scan to confirm minimality would cut Part 2
   from ~50 combats to ~10. Not done because linear is unconditionally
   correct and already inside budget.

2. **Memoise nothing, but prune the inner loop.** Each fight re-sorts
   all ~20 groups twice. With so few groups that is noise; at larger
   scales you'd keep groups in a structure sorted by initiative and only
   re-sort the selection order.

---

## Key patterns

- **A tuple's lexicographic `Ord` is a tie-break spec; `Down` flips a
  key.** Whenever a sort or an argmax has the shape "by A, then by B,
  then by C" with mixed directions, build the key as a tuple and wrap
  the descending components in `Down`. `sortOn`/`maximumBy (comparing
  …)` then need no hand-written comparator. This scales to any number of
  keys and is far less error-prone than a multi-way `compare`.

- **Key mutable entities by a stable id, not by value or position.**
  When the things in your collection change identity-preservingly over
  time (units die, values update), an `IntMap`/`Map` keyed by an id lets
  references survive the mutation. Looking a target up *by id at use
  time* gives you its current state for free — the alternative, carrying
  indices into a list that is being filtered, is a bug factory.

- **Detect period-1 cycles to make a simulation total.** A step that
  changes nothing will repeat forever. A cheap "did anything change?"
  check (here: "were any units killed?") converts a potentially infinite
  loop into a decidable outcome. Generalises to the full cycle detection
  of Days 12 and 18.

- **A pattern in a list-comprehension generator is a filter.** `[ n |
  b <- [1..], Win Immune n <- [f b] ]` keeps only the `b`s whose result
  matches `Win Immune n`, binding `n` along the way. Combined with `[1..]`
  and `head`, it expresses "smallest input satisfying a predicate"
  without an explicit loop or `Maybe` plumbing.

- **Keyword-anchored parsing beats a combinator for fixed skeletons.**
  When a line is mostly boilerplate with values wedged between known
  words, slicing on those words (`elemIndex`, `break`) is shorter than a
  grammar and trivially robust to whitespace.

---

## If I were writing this in Rust

The shape is almost identical. `Group` is a `struct` with the same nine
fields; the live population is a `HashMap<u32, Group>` (or a `Vec<Group>`
with a parallel "alive" filter, but the id-keyed map matches the Haskell
and avoids index invalidation). Both sorts become
`groups.sort_by_key(|g| (Reverse(g.power()), Reverse(g.initiative)))` —
Rust's `std::cmp::Reverse` is the exact analogue of `Down`, and the
tuple-key sort is the same trick. `damage_to` is a method with a
`match`/`if` on weakness/immunity. The combat loop is a `loop { … }` with
a `killed == 0` break for the stalemate. Part 2 is `(1..).find_map(|b|
match run_combat(&boost(b)) { Outcome::Win(Immune, n) => Some(n), _ =>
None })` — Rust's `find_map` over the open range `(1..)` is line-for-line
the Haskell list comprehension with `head`. The only real difference is
that Rust forces you to think about ownership when a group both attacks
and is mutated in the same loop; the `HashMap` + id indirection sidesteps
it exactly as the `IntMap` does here. Runtime would be a few milliseconds
— Haskell's ~200 ms is the boxed-`IntMap` churn across ~50 full combats,
which a `HashMap<u32, Group>` with in-place unit decrements would avoid.

---

**Navigation**: [← Day 23](day23_function_guide.md) | [All Days](summary_2018.md) | [Day 25 →](day25_function_guide.md)
