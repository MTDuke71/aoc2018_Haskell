# GHC Compile Pipeline and Runtime Notes

A growing reference for how GHC turns Haskell source into a running program, and how that program manages memory while it runs.  Notes land here as the relevant runtime/compile behaviours come up in the AoC code; the full sit-down deep-dive session will draw from this file once it has enough material.

**Status**: collected piecewise.  Not yet a coherent walkthrough -- expect topical entries, ordered roughly as they were encountered, with cross-references when they intersect.

---

## Table of contents

1. [The GHC nursery (garbage collector's youngest generation)](#the-ghc-nursery)

## Wishlist (topics to add as they come up)

The eventual deep-dive should hit most of these, ideally in order of "shortest distance from `.hs` source" to "the running binary":

### Compile-time
- The full GHC pipeline: parsing -> renaming -> type checking -> desugaring to Core -> Core-to-Core opt passes -> STG -> Cmm -> assembly / native code.
- Core-to-Core optimisation passes: inlining, specialisation, strictness analysis, common subexpression elimination, rewrite rules, list/stream fusion.
- The Core language itself -- what `-ddump-simpl` shows you, and how to read it.
- STG and the spineless-tagless G-machine: what a thunk actually looks like in memory, how function application is compiled.
- Cmm: GHC's portable assembly-like intermediate representation.
- Strictness analysis and how `BangPatterns` / `!` annotations affect the generated code.
- How `runST` is implemented (the `forall s.` rank-2 trick, the `ST` representation, and why mutation cannot escape).

### Runtime
- [x] **The GHC nursery** (see below).
- The two-generation copying collector: nursery -> generation 1 -> optional further generations; promotion thresholds.
- Pinned vs unpinned heap objects (the latter can be moved by GC, the former cannot -- relevant for FFI and `STUArray`).
- The RTS options (`+RTS -A ... -K ... -RTS`) and what tuning each one accomplishes in practice.
- Concurrency runtime: lightweight threads, the scheduler, MVars, STM.
- Profiling: cost-centre profiles, ticky-ticky profiling, eventlog + Threadscope, heap-profile breakdowns.

---

## The GHC nursery

(First encountered in Day 10's per-tick `[Point]` allocation.)

GHC's runtime uses a **generational copying garbage collector**, and the **nursery** is the youngest generation -- a small region (~1 MB per OS thread by default, sized to fit in L2 cache) where every new allocation lands first.

### Lifecycle of a heap object

1. **Allocate**: writing a new value into the heap is a *single instruction* -- bump the nursery's allocation pointer by the size of the object.  No `malloc`, no free-list search, no per-object header bookkeeping.  Just `hp += size`.
2. **Use**: the program references the object until it falls out of scope (or out of any data structure that pointed to it).
3. **Minor GC** (triggered when the nursery fills): scan from the live roots, **copy survivors out** to the older generation, then **reset the nursery pointer to zero**.  Everything not copied is freed for free -- no per-object cleanup work.

```
                  bump pointer
                       v
nursery: [obj1][obj2][obj3]................     (most allocs land here)
                       ^                  ^
                       next alloc           nursery end

after minor GC (survivors copied to gen 1):
nursery: ..........................            (entire nursery empty again)
gen 1:   [obj1 (lived)][obj7 (lived)]...
```

### Why this matters for hot allocation loops

Take Day 10's `step` function in [src/Day10.hs](../src/Day10.hs).  Each call allocates 313 fresh `Point` records -- about 5 KB per tick.  Over 10,500 ticks that is ~50 MB of total allocation, far larger than the nursery.  But the **live set at any moment** is just the current list of 313 `Point`s, which fits in the nursery with room to spare.

What happens at each minor GC:

- Survivors: the current `[Point]` (~5 KB).
- Garbage: every previous tick's `[Point]` that we replaced -- gigabytes of cumulative allocation across the run, all of which is "free" because GC never touches it; it just gets overwritten next time the bump pointer wraps around.

The bench numbers confirm: 45 ms total for 10,500 ticks ~ **4 us per tick**.  If each `Point` allocation cost a `malloc`/`free` pair (say 50 ns each), 313 points x 10,500 ticks x 100 ns ~ 330 ms -- almost 10x slower.  The nursery is what makes the difference.

### Comparison table

| Allocator                | Cost per alloc | Cost per free                 | Cache behaviour            |
|--------------------------|---------------:|-------------------------------|----------------------------|
| `malloc` / `free` (C)    | ~30-100 ns     | ~30-100 ns                    | Fragments over time        |
| Rust stack frame         | ~1 ns          | ~0 ns (frame pop)             | Hot in L1/L2               |
| Rust `Box` (heap)        | ~30-100 ns     | ~30-100 ns                    | Like malloc                |
| **GHC nursery alloc**    | **~1 ns**      | **~0 ns** (bulk-freed at GC)  | Always hot in L1/L2        |
| GHC old-gen survivor     | ~1 ns + ~10 ns copy at promotion | proportional to survivor count | Cooler              |

The trade-off: GHC pays for the **copy** when something *does* survive.  If a value lives long enough to be promoted out of the nursery, its bytes get written twice (once into the nursery, once into gen 1).  For short-lived garbage like Day 10's per-tick `Point` list, that copy never happens.  For long-lived state like Day 9's marble linked list, we sidestepped GC entirely by using pinned mutable `STUArray` (see [src/Day09.hs](../src/Day09.hs)) -- different escape hatch.

### Tuning via RTS flags

The default nursery is sized for general workloads; tune it via the runtime-system flags compiled into the program:

```
program +RTS -A4M -RTS args...    # 4 MB nursery instead of default ~1 MB
```

A larger `-A` means more headroom before minor GC fires -- fewer pauses, but each pause processes more garbage.  For allocation-heavy workloads with a small live set, bumping `-A` often gives a noticeable speedup.  Day 10 does not need it; Day 9 does not allocate.

Other knobs worth eventually documenting here:

- `-H<size>` -- suggested heap size; sets minimum heap before first major GC.
- `-M<size>` -- maximum heap size; program dies if exceeded.
- `-G<n>` -- number of generations (default 2).
- `-s` / `-S` -- print GC stats to stderr after the run.
- `-T` -- enable runtime stats accessible via `GHC.Stats`.

### The hardware-roots analogy

The nursery is **a circular bump-allocator scratchpad in fast memory** -- mentally similar to a small SRAM region in a microcontroller you would use for DMA-staged packets.  Write into it, the consumer drains it, reset the pointer for the next batch.  The "GC" step is the periodic drain.

The difference from a pure ring buffer: the consumer (the survivor copier) does not drain in order -- it scans for live data via root-pointer chasing.  But the *region semantics* are the same: bulk-allocate, bulk-reclaim, no per-object bookkeeping.

### Cross-references

- The escape hatch for long-lived state: see Day 9's `STUArray`-based linked list in [`src/Day09.hs`](../src/Day09.hs) and the [Day 9 function guide](../Problem_Statements/days/day09_function_guide.md).
- The allocation pattern that benefits from this: see Day 10's `step` and `bboxArea` in [`src/Day10.hs`](../src/Day10.hs).
