# Day 04: Repose Record -- Function Guide

**Problem**: Guards write timestamped log entries whenever they begin a shift or fall asleep/wake up. The entries arrive unsorted. Part 1 finds the guard with the most total sleep and the minute they sleep most often; Part 2 finds the guard who is most consistently asleep at a single minute across all nights.
**Answers**: Part 1 = **85296**, Part 2 = **58559**
**Runtime** (mean, criterion `-O2`): Parse = **2.81 ms** | Part 1 = **45.5 µs** | Part 2 = **256 µs** | **Total = 3.11 ms**
**Code**: [Day04.hs](../../src/Day04.hs)
**Tests**: [Day04Spec.hs](../../test/Day04Spec.hs)
**Bench**: `cabal bench --benchmark-options="--match prefix day04"`
**Problem statement**: [day04.md](day04.md)

**New concepts this day** (beyond Days 0--3):

- **Sum types** (`data Event = BeginShift !Int | FallAsleep | WakeUp`) -- a type with multiple constructors, each carrying different data. Haskell's version of a Rust `enum` with payloads.
- **Lexicographic sort on strings** -- `sort` on ISO timestamp lines produces chronological order for free.
- **`maximumBy` / `comparing`** -- select the maximum element of a list by a projected key without a manual `map`-then-`sort` detour.
- **Tail-recursive `go` accumulator** -- the idiom for processing a sorted event stream when you need to thread multiple pieces of state (current guard, sleep-start minute, schedule so far). No `State` monad required.
- **`mapMaybe`** -- `Data.Maybe.mapMaybe f xs` applies `f` to every element, then drops every `Nothing`, keeping only the `Just` values. One function that combines `map` and `filter`.

---

## Table of contents

1. [Problem summary](#problem-summary)
2. [Data model](#data-model)
3. [`parseEntry`](#parseentry)
4. [`buildSchedule` -- the tail-recursive accumulator pattern](#buildschedule)
5. [`parseInput`](#parseinput)
6. [`minuteFreqs` and `bestSlot`](#minutefreqs-and-bestslot)
7. [`part1`](#part1)
8. [`part2`](#part2)
9. [`solve`](#solve)
10. [Tests](#tests)
11. [Benchmarks](#benchmarks)
12. [Possible optimization -- share the schedule between parts](#possible-optimization)
13. [Key patterns](#key-patterns)
14. [Side-by-side with the Rust mental model](#side-by-side-with-the-rust-mental-model)

---

## Problem summary

The guards keep a log. Each line records a single event with an ISO timestamp followed by a description:

```
[1518-11-01 00:00] Guard #10 begins shift
[1518-11-01 00:05] falls asleep
[1518-11-01 00:25] wakes up
[1518-11-01 23:58] Guard #99 begins shift
[1518-11-02 00:40] falls asleep
[1518-11-02 00:50] wakes up
```

Important details: every sleep/wake event happens during the midnight hour (minutes 00--59), so only the minute field matters for those events. The puzzle says the log is scrambled; we must sort it before processing. The example above is already in order; the real input is not.

After sorting and parsing, we reconstruct, for each guard, the complete list of minutes during which they were asleep across all nights. The two strategies for choosing a target guard are:

- **Part 1 (Strategy 1)**: find the guard with the most *total* minutes asleep, then find the minute they sleep most frequently. Return `guard_id x minute`.
- **Part 2 (Strategy 2)**: for every guard, find the minute they sleep most frequently. Pick the guard/minute pair with the highest frequency. Return `guard_id x minute`.

For the example: Guard 10 sleeps 50 total minutes (Guard 99 sleeps 30), so Part 1 picks Guard 10; their most-slept minute is 24 (two nights). Answer: `10 * 24 = 240`. Guard 99 sleeps at minute 45 on all three of their nights (frequency 3 > Guard 10's frequency 2 at minute 24). Answer: `99 * 45 = 4455`.

---

## Data model

```haskell
data Event
  = BeginShift !Int  -- guard starts a new shift; carries the guard ID
  | FallAsleep       -- guard falls asleep
  | WakeUp           -- guard wakes up
  deriving (Eq, Show)

data LogEntry = LogEntry
  { entryMinute :: !Int
  , entryEvent  :: !Event
  } deriving (Eq, Show)

type SleepSchedule = Map.Map Int [Int]
```

### Sum types -- a type with multiple constructors

`data Event` is Day 4's headline new concept. Unlike `Claim` from Day 3, which had exactly one constructor (`Claim { ... }`), `Event` has *three* constructors joined by `|`. This is a *sum type* (or *algebraic data type*, ADT). In Rust the analogue is an `enum` with variants:

```rust
enum Event {
    BeginShift(u32),  // carries a guard ID
    FallAsleep,       // no payload
    WakeUp,           // no payload
}
```

In Haskell:

```haskell
data Event
  = BeginShift !Int  -- one constructor, carrying an Int payload
  | FallAsleep       -- constructor with no fields
  | WakeUp           -- constructor with no fields
```

Three key facts about sum types:

1. **Every value of type `Event` is exactly one of the three constructors.** You can't have an "unspecified" `Event` or a "mixture." The compiler enforces this.
2. **Pattern matching is exhaustive.** A `case` expression on an `Event` must handle all three constructors or the compiler warns you. This is the static safety you get instead of runtime `instanceof` checks.
3. **Payloads differ per constructor.** `BeginShift` carries an `Int`; `FallAsleep` and `WakeUp` carry nothing. The type system tracks this; you can't accidentally try to read a guard ID from a `FallAsleep` event.

### `LogEntry` -- a product type

`LogEntry` is a *product type*: exactly one constructor, with two named fields. Together, `Event` (sum) and `LogEntry` (product) cover the two flavors of ADTs. Most real data types are combinations of both.

### `SleepSchedule` -- why a `Map Int [Int]`

The schedule maps each guard ID to every minute they slept, across every night, as a flat concatenated list. Duplicate minutes are intentional: if guard 10 sleeps during minute 24 on two nights, the number `24` appears twice in their list. This makes frequency counting trivial: `map (\x -> (x, 1))` followed by `Map.fromListWith (+)` does it in one pass.

An alternative would be a `Map Int (Array Int Int)` (guard ID to a 60-element sleep-count array), but that introduces array indexing before we need it. A flat list is simpler and fast enough here.

---

## `parseEntry`

```haskell
parseEntry :: String -> LogEntry
parseEntry line =
  let ws     = words line
      minute = read (take 2 (drop 15 line)) :: Int
      ev     = case ws !! 2 of
                 "Guard" -> BeginShift (read (drop 1 (ws !! 3)))
                 "falls" -> FallAsleep
                 _       -> WakeUp
  in LogEntry minute ev
```

### Extracting the minute by position

Every log line has the same header: `[YYYY-MM-DD HH:MM]`. Counting from zero:

```
[ 1 5 1 8 - 1 1 - 0 1   0 0 : 0 5 ]  ...
0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17
```

Positions 15--16 are always the two minute digits. `take 2 (drop 15 line)` extracts them as a two-character string, then `read :: String -> Int` converts it. The `:: Int` type annotation fixes the overloaded return type of `read`; without it the compiler cannot infer which `Read` instance to use.

### Classifying the event with `words`

`words :: String -> [String]` splits a string on any whitespace, collapsing runs. For:

```
"[1518-11-01 00:00] Guard #10 begins shift"
```

`words` gives:

```
["[1518-11-01", "00:00]", "Guard", "#10", "begins", "shift"]
```

The third element (`ws !! 2`) is always the distinguishing word:
- `"Guard"` -- the guard ID follows as `ws !! 3 = "#10"`. `drop 1 "#10" = "10"`, then `read "10" = 10`.
- `"falls"` -- sleep event (the full word is "falls" from "falls asleep").
- Anything else -- wake event (the full word is "wakes" from "wakes up").

`!!` is the zero-indexed list access operator (`[a] -> Int -> a`). In Rust this would be `slice[i]`. It panics on out-of-bounds, just like Rust's `[]` -- acceptable for AoC.

### A note on `_` in case arms

```haskell
case ws !! 2 of
  "Guard" -> BeginShift (read (drop 1 (ws !! 3)))
  "falls" -> FallAsleep
  _       -> WakeUp
```

The wildcard `_` matches anything not caught by the earlier arms. We use it instead of `"wakes"` because the puzzle only has three event types -- if neither of the first two arms matched, it must be a wake. Using `_` instead of a literal string is slightly safer: a future input that spells the event differently would still work. Either choice is fine for AoC.

---

## `buildSchedule`

```haskell
buildSchedule :: [LogEntry] -> SleepSchedule
buildSchedule = go (-1) (-1) Map.empty
  where
    go :: Int -> Int -> SleepSchedule -> [LogEntry] -> SleepSchedule
    go _   _     sched []     = sched
    go gid sleep sched (e:es) = case entryEvent e of
      BeginShift g ->
        go g sleep sched es
      FallAsleep ->
        go gid (entryMinute e) sched es
      WakeUp ->
        let newMins = [sleep .. entryMinute e - 1]
            sched'  = Map.insertWith (++) gid newMins sched
        in  go gid sleep sched' es
```

### The tail-recursive accumulator pattern (`go`)

This is the first time in the project we need to *thread state* across a list traversal, where that state has multiple pieces that change at different events. The three pieces are:

| Accumulator | Initial value | Changes on |
|-------------|---------------|------------|
| `gid`       | `-1` (sentinel) | `BeginShift g` -- updates to `g` |
| `sleep`     | `-1` (sentinel) | `FallAsleep` -- updates to the event's minute |
| `sched`     | `Map.empty`     | `WakeUp` -- adds new sleep interval |

The `go` helper is a Haskell idiom for "I want a loop that carries named state." The name `go` is conventional -- you will see it in virtually every Haskell codebase. The function is *tail-recursive*: every branch ends with a call to `go` as the last action. GHC compiles this to a tight loop equivalent to a Rust `loop` with mutable variables.

Compare to the equivalent Rust:

```rust
let mut gid = -1i32;
let mut sleep = -1i32;
let mut sched: HashMap<i32, Vec<i32>> = HashMap::new();
for entry in entries {
    match entry.event {
        Event::BeginShift(g) => gid = g,
        Event::FallAsleep    => sleep = entry.minute,
        Event::WakeUp        => {
            let mins: Vec<i32> = (sleep..entry.minute).collect();
            sched.entry(gid).or_default().extend(mins);
        }
    }
}
```

The Haskell version passes those mutable variables as function arguments instead. Semantically identical; syntactically different.

### Why not `State` monad?

The `State` monad wraps this exact pattern in a type-class abstraction. It has real advantages for larger programs (composability, `do`-notation sugar). For a function this small, the named-accumulator `go` is more legible for a reader who has not yet learned monads. Introducing `State` here would teach the abstraction before the need is clear; that can wait until Day 9 or later.

### Pattern matching on a sum type

```haskell
case entryEvent e of
  BeginShift g -> ...
  FallAsleep   -> ...
  WakeUp       -> ...
```

The `case` expression *destructs* the `Event` value. For `BeginShift g`, `g` is bound to the integer payload. `FallAsleep` and `WakeUp` carry no payload, so no binding is needed. The compiler checks that all three constructors are covered -- leave one out and you get an `-Wall` warning.

### `Map.insertWith (++)`

When a `WakeUp` event fires, we add the interval `[sleep .. minute - 1]` to the guard's running list:

```haskell
Map.insertWith (++) gid newMins sched
```

`Map.insertWith f key newVal oldMap`:
- If `key` is absent: insert `key -> newVal`.
- If `key` is present with `oldVal`: replace with `f newVal oldVal`.

With `(++)` as the combining function, `f newVal oldVal = newVal ++ oldVal` -- prepend the new interval to the existing ones. The guard's accumulated list grows one sleep interval at a time.

---

## `parseInput`

```haskell
parseInput :: String -> SleepSchedule
parseInput = buildSchedule . map parseEntry . sort . lines
```

Three transformations, right-to-left:

1. `lines` -- split the raw input into individual log lines.
2. `sort` -- sort the lines lexicographically. Because ISO timestamps (`YYYY-MM-DD HH:MM`) sort alphabetically in the same order as chronologically, this is the entire "sort by timestamp" step. No `sortBy (comparing timestamp)`, no date parsing -- just `sort`.
3. `map parseEntry` -- parse each sorted line into a `LogEntry`.
4. `buildSchedule` -- convert the sorted entry stream into a `SleepSchedule`.

The ISO-timestamp-as-sort-key trick is worth remembering. It applies to any date format where larger fields come first and all fields have fixed width. AoC loves inputs with timestamps in this format.

---

## `minuteFreqs` and `bestSlot`

```haskell
minuteFreqs :: [Int] -> Map.Map Int Int
minuteFreqs = Map.fromListWith (+) . map (\x -> (x, 1))

bestSlot :: (Int, [Int]) -> Maybe (Int, Int)
bestSlot (_,   [])   = Nothing
bestSlot (gid, mins) =
  let (bestMin, freq) = maximumBy (comparing snd) (Map.toList (minuteFreqs mins))
  in  Just (gid * bestMin, freq)
```

### `minuteFreqs` -- reusing the Day 3 frequency idiom

Day 3 introduced `Map.fromListWith (+) [(key, 1) | ...]`. Here the same idiom counts minute occurrences:

```haskell
minuteFreqs [24, 30, 24, 5] =
  Map.fromListWith (+) [(24,1),(30,1),(24,1),(5,1)]
  = Map.fromList [(5,1),(24,2),(30,1)]
```

Minute 24 appeared twice, so its count is 2. One expression; no loop.

### `maximumBy` and `comparing`

```haskell
maximumBy :: (a -> a -> Ordering) -> [a] -> a
comparing :: Ord b => (a -> b) -> a -> a -> Ordering
```

`maximumBy` is `maximum` but with a custom comparison function. The comparison function must return `Ordering` (`LT`, `EQ`, or `GT`), which is what `compare :: Ord b => b -> b -> Ordering` produces.

`comparing f a b = compare (f a) (f b)` -- compare two elements by first projecting them through `f`. This is the Haskell idiom for "sort/max by key":

```haskell
maximumBy (comparing snd) [(24,2),(30,1),(5,1)]
-- compare fst-less, use snd as the key
-- compares 2, 1, 1 -- selects (24,2)
```

The Rust analogue: `iter.max_by_key(|&&(_,count)| count)`.

### `bestSlot` and `Maybe`

`bestSlot` returns `Nothing` for a guard with no sleep record (empty minute list) and `Just (product, frequency)` otherwise. This is the first time in the project we *return* `Maybe` from a helper function instead of receiving it from a library. The shape -- "produce a result that might be absent" -- is the canonical `Maybe` use case.

The `mapMaybe` call in `part2` silently drops any `Nothing` entries (guards with no sleep at all), keeping only `Just` values.

---

## `part1`

```haskell
part1 :: SleepSchedule -> Int
part1 sched =
  let (guardId, mins) = maximumBy (comparing (length . snd)) (Map.toList sched)
      (bestMin, _)    = maximumBy (comparing snd) (Map.toList (minuteFreqs mins))
  in  guardId * bestMin
```

Step by step:

1. `Map.toList sched` gives `[(guardId, [minutes])]` -- one pair per guard.
2. `maximumBy (comparing (length . snd))` finds the guard with the longest minute list -- i.e. the most total minutes asleep. `length . snd` extracts the list length from each `(id, [mins])` pair.
3. The winning guard's minute list `mins` goes into `minuteFreqs mins` to build a `Map Int Int` of `(minute -> count)`.
4. `maximumBy (comparing snd)` on `Map.toList freqMap` finds the `(minute, count)` pair with the highest count.
5. `guardId * bestMin` is the answer.

The `let` bindings name the intermediate results. This is important for performance: `minuteFreqs mins` is computed once and reused. Without a name, Haskell *could* recompute it -- naming guarantees sharing.

---

## `part2`

```haskell
part2 :: SleepSchedule -> Int
part2 sched =
  fst (maximumBy (comparing snd) (mapMaybe bestSlot (Map.toList sched)))
```

1. `Map.toList sched` gives one `(guardId, [minutes])` pair per guard.
2. `mapMaybe bestSlot` applies `bestSlot` to each pair, collects the `Just` results, and drops any `Nothing` (guards with no sleep). Each surviving element is `(guardId * minute, frequency)`.
3. `maximumBy (comparing snd)` finds the pair with the highest frequency.
4. `fst` extracts the product (`guardId * minute`).

### `mapMaybe` -- filter-map without the intermediate `[Maybe a]`

```haskell
mapMaybe :: (a -> Maybe b) -> [a] -> [b]
```

`mapMaybe f = catMaybes . map f`. It applies `f` to each element and keeps the unwrapped values from `Just` results:

```haskell
mapMaybe (\x -> if x > 0 then Just (x * 2) else Nothing) [-1, 2, -3, 4]
= [4, 8]
```

The Rust analogue is `iter().filter_map(f)` -- same semantics, different name.

---

## `solve`

```haskell
solve :: String -> IO ()
solve contents = do
  let sched = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 sched))
  putStrLn ("  part 2: " ++ show (part2 sched))
```

`parseInput` is called once; `sched` is shared by both parts. This is the "parse-once" rule from Day 1 in action -- both parts pay `buildSchedule` once (2.81 ms) instead of twice.

---

## Tests

Coverage in [Day04Spec.hs](../../test/Day04Spec.hs):

1. **`parseEntry`** -- four cases: a `BeginShift` line (minute 0, guard 10), a `FallAsleep` line, a `WakeUp` line, and a guard line with a 4-digit ID (`#2213`, minute 56 from 23:56).
2. **Part 1 on example** -- `10 * 24 = 240`.
3. **Part 2 on example** -- `99 * 45 = 4455`.
4. **Actual input** -- Part 1 = 85296, Part 2 = 58559.

The `parseEntry` test for a 4-digit guard ID (`#2213`) is worth calling out: the parsing extracts the ID by `drop 1 (ws !! 3)`, which works for any-length IDs because `words` splits on whitespace rather than fixed column widths.

---

## Benchmarks

Recorded on Windows 11 / GHC 9.6.7 / `-O2`.

| Bench              | Mean      | What it times |
|--------------------|----------:|---------------|
| `day04/parseInput` |  2.81 ms  | Sort ~550 lines + `parseEntry` per line + `buildSchedule`. |
| `day04/part1`      |  45.5 µs  | `Map.toList` + `maximumBy` + `minuteFreqs` + `maximumBy` again. |
| `day04/part2`      |  256 µs   | `mapMaybe bestSlot` over all guards + global `maximumBy`. |
| `day04/combined`   |  3.26 ms  | End-to-end from raw string. |

**Total = Parse + Part 1 + Part 2 = 3.11 ms.**

Parse dominates by 10x. The parse includes:
- `lines` splitting the 32 KB input into ~550 strings.
- `sort` on those strings (O(n log n) comparisons on 40-character strings).
- 550 `parseEntry` calls, each doing `words` + two `read` calls + a three-arm `case`.
- `buildSchedule` -- one pass through ~550 events, threading the accumulator.

Post-parse, both parts are fast because the `SleepSchedule` (a `Map` of ~20 guards with ~400 sleep minutes each) is tiny compared to the raw log.

---

## Possible optimization

The `sort` in `parseInput` is ~0.5 ms of the 2.81 ms total. If parsing were a bottleneck, we could sort by just the timestamp prefix (`take 17 line`) rather than the full line, saving string comparison work. For 2.8 ms there is no reason to bother.

Both `part1` and `part2` call `minuteFreqs` on individual guards' minute lists. If we pre-built per-guard frequency maps during `buildSchedule`, each part would skip that pass. The savings would be a few microseconds -- unmeasurable at 256 µs total for Part 2.

---

## Key patterns

1. **Sum types are the right tool when an event has multiple kinds with different payloads.** `Event = BeginShift !Int | FallAsleep | WakeUp` is cleaner than a `String` tag + optional `Int` field. Pattern matching on it is exhaustive -- the compiler tells you when you have forgotten to handle a case.
2. **The `go` accumulator pattern replaces mutable loop variables.** `go gid sleep sched entries` is a loop that passes its "variables" as arguments. Tail-recursive calls compile to a tight loop with no heap allocation for the call frames themselves.
3. **`sort` on ISO timestamps is chronological sort.** If the format is `YYYY-MM-DD HH:MM`, alphabetical order equals date order. No date parsing needed.
4. **`maximumBy (comparing f)` is the idiomatic max-by-key.** Know this idiom; you will reach for it at least once per AoC year.

---

## Side-by-side with the Rust mental model

```rust
#[derive(Debug)]
enum Event { BeginShift(u32), FallAsleep, WakeUp }

struct LogEntry { minute: u32, event: Event }

fn parse_entry(line: &str) -> LogEntry {
    let ws: Vec<&str> = line.split_whitespace().collect();
    let minute: u32 = line[15..17].parse().unwrap();
    let event = match ws[2] {
        "Guard" => Event::BeginShift(ws[3][1..].parse().unwrap()),
        "falls" => Event::FallAsleep,
        _       => Event::WakeUp,
    };
    LogEntry { minute, event }
}

fn build_schedule(mut entries: Vec<LogEntry>) -> HashMap<u32, Vec<u32>> {
    entries.sort_by_key(|e| e.minute); // oversimplification -- would sort by full timestamp
    let mut sched: HashMap<u32, Vec<u32>> = HashMap::new();
    let (mut gid, mut sleep) = (0u32, 0u32);
    for e in entries {
        match e.event {
            Event::BeginShift(g) => gid = g,
            Event::FallAsleep    => sleep = e.minute,
            Event::WakeUp        => {
                sched.entry(gid).or_default().extend(sleep..e.minute);
            }
        }
    }
    sched
}
```

Key correspondences:

| Concept | Rust | Haskell |
|---------|------|---------|
| Sum type / enum | `enum Event { BeginShift(u32), ... }` | `data Event = BeginShift !Int \| ...` |
| Exhaustive match | `match` (compiler checks completeness) | `case` (same, under `-Wall`) |
| Mutable loop state | `let mut gid = ...` | `go gid sleep sched` (explicit accumulator) |
| Append to entry in `HashMap` | `entry.or_default().extend(...)` | `Map.insertWith (++) gid newMins sched` |
| Max by key | `iter.max_by_key(\|&&(_, c)\| c)` | `maximumBy (comparing snd)` |
| Filter-map | `iter.filter_map(f)` | `mapMaybe f` |

The structural difference: Rust's `build_schedule` mutates `gid`, `sleep`, and `sched` inside a `for` loop; Haskell's `go` passes them as arguments to a tail-recursive call. Both compile to essentially the same machine code -- a loop with registers for the three variables -- but the Haskell version makes the data flow explicit as function arguments rather than implicit as mutation.

---

**Navigation**: [Problem statement](day04.md) | [Summary table](summary_2018.md) | [<- Day 3](day03_function_guide.md) | [Day 5 ->](day05_function_guide.md)
