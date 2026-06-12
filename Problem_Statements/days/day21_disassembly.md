# Day 21 Disassembly Supplement: The Program Under the Microscope

This is a sibling reference to [day21_function_guide.md](day21_function_guide.md),
in the same spirit as [day16_disassembly.md](day16_disassembly.md).
The function guide explains the Haskell — the breakpoint runner,
`hashSpec`, the lifted hash. This supplement puts the *program
itself* under instrumentation and answers the questions the guide
asserts but doesn't prove:

> Where exactly do the instructions go when this thing runs? What
> does the probe stream look like as an object — how long is the
> tail, how long is the cycle? And what *are* the two numbers the
> puzzle text actually asks about — "fewest instructions" and "most
> instructions" — for this input?

**Short answers**: 98.3% of the first round (and 99.99% of a full
Part 2 run) is spent in an 8-instruction trial-multiplication loop
that exists only because the ISA has no shift or divide. The probe
stream is ρ-shaped: an 11,646-probe tail followed by a 1,222-probe
cycle. Halting soonest costs **1,848** instructions; halting latest
costs **2,976,386,661** — a ratio of 1.6 million between the two
answers to the same question.

> **Disclaimer on input-specificity.** The constants, the probe
> values, the tail/cycle lengths, and the instruction counts below
> are *this input's*. Every AoC solver gets the same program
> template with a different `SEED` (1765573 here), which changes
> every downstream number. The structural observations — the region
> layout, the jump idioms, the profile shape, the ρ structure —
> hold for every input.

All quoted numbers come from
[scripts/day21_disassemble.hs](../../scripts/day21_disassemble.hs),
whose frozen output is checked in at
[scripts/day21_disassembly.txt](../../scripts/day21_disassembly.txt).

---

## Table of contents

- [The jump idioms: reading IP-bound code fluently](#the-jump-idioms-reading-ip-bound-code-fluently)
- [The program, region by region](#the-program-region-by-region)
- [Watching the hash work: the first 45 steps](#watching-the-hash-work-the-first-45-steps)
- [The execution profile: where 1,846 steps go](#the-execution-profile-where-1846-steps-go)
- [The probe stream is ρ-shaped](#the-probe-stream-is-ρ-shaped)
- [The two numbers the puzzle asks about](#the-two-numbers-the-puzzle-asks-about)
- [Where this lands in the 16 / 19 / 21 trilogy](#where-this-lands-in-the-16--19--21-trilogy)
- [Reproducing this analysis](#reproducing-this-analysis)

---

## The jump idioms: reading IP-bound code fluently

Day 19 introduced the mechanism (the IP is written into r2 before
each instruction and read back after); Day 21 is where reading it
becomes fluent. There are exactly three idioms in this program, and
the disassembler renders each as what it *is* rather than what it
arithmetically says:

| Raw instruction | Renders as | Why |
|---|---|---|
| `seti K _ 2` | `goto K+1` | r2 becomes K, post-step +1 lands at K+1. An absolute jump. |
| `addi 2 1 2` | `goto ip+2` | r2 = ip + 1, +1 again — skips exactly one instruction. An unconditional skip. |
| `addr F 2 2` | `if rF == 1: skip next` | r2 = ip + rF where rF is a 0/1 comparison flag. The *conditional* skip. |

The third one is the load-bearing idiom. Every branch in this
program is a three-instruction sandwich:

```
<comparison writing a 0/1 flag into rF>
addr F 2 2          ; if flag: skip next
<unconditional goto — the "else" arm>
```

That's a compiler's `if/else` lowered onto an ISA whose only
"branch" is *add a register to the program counter*. Once you see
the sandwich, the 31-instruction listing collapses into about ten
lines of structured code.

---

## The program, region by region

Full disassembly from the frozen output, grouped into its five
regions (ip bound to **r2**; comments are the disassembler's):

```
--- Region 1: the bani self-test (ips 0-4) -- runs once, 4 steps ---
 0: seti      123        0 4   ; r4 = 123
 1: bani        4      456 4   ; r4 = r4 & 456
 2: eqri        4       72 4   ; r4 = (r4 == 72) ? 1 : 0
 3: addr        4        2 2   ; ip += r4 -> if r4 == 1: skip next
 4: seti        0        0 2   ; goto 1

--- Region 2: power-on (ip 5) -- runs once ---
 5: seti        0        5 4   ; r4 = 0          (the first "previous probe")

--- Region 3: round header (ips 6-7) -- 2 steps per round ---
 6: bori        4    65536 5   ; r5 = r4 | 65536      WIDEN
 7: seti  1765573        9 4   ; r4 = 1765573         SEED

--- Region 4a: hash one byte (ips 8-16) -- 8 steps per byte ---
 8: bani        5      255 1   ; r1 = r5 & 255        BYTE_MASK
 9: addr        4        1 4   ; r4 = r4 + r1
10: bani        4 16777215 4   ; r4 = r4 & 16777215   HASH_MASK
11: muli        4    65899 4   ; r4 = r4 * 65899      MULT
12: bani        4 16777215 4   ; r4 = r4 & 16777215
13: gtir      256        5 1   ; r1 = (256 > r5) ? 1 : 0
14: addr        1        2 2   ; ip += r1 -> if r1 == 1: skip next
15: addi        2        1 2   ; goto 17              (more bytes to eat)
16: seti       27        0 2   ; goto 28              (that was the last byte)

--- Region 4b: r5 //= 256, the hard way (ips 17-27) ---
17: seti        0        8 1   ; r1 = 0
18: addi        1        1 3   ; r3 = r1 + 1     <┐ trial loop: find the
19: muli        3      256 3   ; r3 = r3 * 256    │ largest r1 with
20: gtrr        3        5 3   ; r3 = (r3 > r5)   │ r1 * 256 <= r5,
21: addr        3        2 2   ; if r3: goto 23   │ i.e. r1 = r5 div 256.
22: addi        2        1 2   ; goto 24          │ 7 instructions per
23: seti       25        1 2   ; goto 26          │ candidate quotient.
24: addi        1        1 1   ; r1 = r1 + 1      │
25: seti       17        7 2   ; goto 18         <┘
26: setr        1        4 5   ; r5 = r1          (one byte consumed)
27: seti        7        6 2   ; goto 8

--- Region 5: the halt check (ips 28-30) -- the ONLY use of r0 ---
28: eqrr        4        0 1   ; r1 = (r4 == r0) ? 1 : 0
29: addr        1        2 2   ; if r1 == 1: ip = 31 -> off the end -> HALT
30: seti        5        2 2   ; goto 6           (next round)
```

Two details that only jump out at this resolution:

- **The self-test costs 4 steps, not 5.** When the `bani` check
  passes, the conditional skip at ip 3 jumps *over* ip 4, so the
  `goto 1` retry instruction never executes at all. It exists purely
  as the punishment arm for a string-flavoured `&`. (This off-by-one
  shows up again in the instruction-count model below.)
- **ips 15 and 16 are a two-way dispatch, not a branch-and-fall-
  through.** The flag at ip 14 picks between *two gotos*: ip 15
  (`goto 17`, keep eating bytes) and ip 16 (`goto 28`, go compare
  with r0). Either way exactly one of them runs — which is why a
  byte-feed costs a flat 8 steps regardless of which way it goes.

---

## Watching the hash work: the first 45 steps

From the frozen trace (registers shown *after* each step,
`[r0,r1,r2,r3,r4,r5]`; r2 mirrors the IP):

```
step  ip  instruction                regs after
   5   5  seti        0        5 4   [0,0,5,0,0,0]
   6   6  bori        4    65536 5   [0,0,6,0,0,65536]          <- v = 0 | 0x10000
   7   7  seti  1765573        9 4   [0,0,7,0,1765573,65536]    <- acc = SEED
   8   8  bani        5      255 1   [0,0,8,0,1765573,65536]    <- byte = 0
   9   9  addr        4        1 4   [0,0,9,0,1765573,65536]
  10  10  bani        4 16777215 4   [0,0,10,0,1765573,65536]
  11  11  muli        4    65899 4   [0,0,11,0,116349495127,65536]   <- !!
  12  12  bani        4 16777215 4   [0,0,12,0,16279383,65536]
```

Step 11 is worth staring at: `1765573 × 65899 = 116,349,495,127` —
a 37-bit value sitting in the register, far outside the hash's
24-bit world, until the very next instruction masks it back down to
16,279,383. The device evidently has wide registers and the
*program* imposes 24-bit arithmetic with explicit masks — exactly
the relationship between Haskell's 64-bit `Int` and the `.&. mask`
in `nextProbe`. The Haskell isn't simulating a 24-bit machine; it's
reproducing a 64-bit machine's deliberate 24-bit discipline.

Then the trial-divide loop starts, and the trace turns into
wallpaper:

```
  17  18  addi        1        1 3   [0,0,18,1,16279383,65536]    r3 = 1*256 = 256   > 65536?  no
  24  18  addi        1        1 3   [0,1,18,2,16279383,65536]    r3 = 2*256 = 512   > 65536?  no
  31  18  addi        1        1 3   [0,2,18,3,16279383,65536]    r3 = 3*256 = 768   > 65536?  no
  38  18  addi        1        1 3   [0,3,18,4,16279383,65536]    ...
  45  18  addi        1        1 3   [0,4,18,5,16279383,65536]    ... 252 more of these
```

Seven instructions per candidate quotient, 257 candidates to
establish `65536 div 256 = 256`. The trace's first 45 steps already
contain four of them; the remaining ~1,790 steps to the first check
are almost entirely this.

---

## The execution profile: where 1,846 steps go

Per-region totals from the per-IP counts (full table in the frozen
output), over the run from power-on to the first arrival at the
check:

| Region | IPs | Steps | Share |
|---|---|---:|---:|
| Self-test | 0–4 | 4 | 0.2% |
| Power-on | 5 | 1 | 0.1% |
| Round header | 6–7 | 2 | 0.1% |
| Byte-feed (hash + dispatch) | 8–16 | 24 | 1.3% |
| **Trial-divide (`r5 //= 256`)** | **17–27** | **1,815** | **98.3%** |
| Halt check | 28–30 | 0 | — |
| | | **1,846** | |

The eight hash instructions that give the puzzle its character —
the add, the masks, the multiply — execute **24 times** before the
first probe is ready. The bookkeeping loop that shifts `v` right by
eight bits executes **1,815 times**. And the first round is the
*cheap* case: `v = 0 | 0x10000` is the smallest widened value
possible. In later rounds `v` is a full 24-bit probe, the first
quotient is ~47,000 instead of 256, and the divide loop's share
climbs to **99.99%** of the whole Part 2 run.

This is the quantitative version of the function guide's claim that
the ISA predicts the profile: no shift instruction ⇒ a one-cycle
operation becomes `7 × (v ÷ 256)` instructions ⇒ essentially the
entire program is one missing opcode, amplified three times per
round for twelve thousand rounds. The lifted Haskell `div` deletes
the 98.3%-and-up column entirely; that's the whole optimisation.

---

## The probe stream is ρ-shaped

From the frozen output:

```
distinct probes before the first repeat: 12868
last new probe (Part 2's answer): #12868 = 5310683
first repeat: probe #12869 = 15949699, same as probe #11647
```

The function guide's pigeonhole argument said the stream *must*
eventually cycle. The instrumentation shows the actual shape: the
first repeated value doesn't loop back to the beginning — it loops
back to probe **#11,647**. So the orbit of `nextProbe` from 0 is:

```
0 → p1 → p2 → ... → p11646 ──→ p11647 → ... → p12868 ──┐
   (tail: 11,646 probes)      ↑   (cycle: 1,222 probes) │
                              └─────────────────────────┘
```

This tail-plus-loop picture is called **ρ ("rho") structure** —
the Greek letter is literally the diagram — and it is the same
object that powers Pollard's ρ factoring algorithm and the
Floyd/Brent cycle-detection algorithms. Every iterated function on
a finite set produces one; the tail length (11,646) and cycle
length (1,222) are just properties of this particular `SEED`.

Two consequences worth spelling out:

- **Part 2's answer is the last probe of the first lap.** Probes
  #11,647 .. #12,868 form the cycle; #12,868 is the final cycle
  element visited before the stream starts its second lap. The
  10 probes #1 .. #10 in the frozen output (starting with Part 1's
  12,213,578) are all tail — values the program visits exactly once
  and never again.
- **Our `IntSet` walk is the right tool here, not Floyd/Brent.**
  The classic constant-memory cycle detectors find the cycle but
  *not* the set of values in the tail — and Part 2's answer needs
  every value seen, because "last new value" is a property of the
  whole prefix. With only 12,868 probes, the set costs nothing;
  Floyd would actually make the problem harder. (Day 18 made the
  same choice for the same reason: its `Map` of seen states *was*
  the answer machinery, not just a detector.)

---

## The two numbers the puzzle asks about

The puzzle text is oddly specific: Part 1 asks for the r0 that
halts after the *fewest instructions executed*, Part 2 after the
*most*. We never needed to count instructions to answer (first
probe / last new probe), but the disassembler counts them anyway —
it's the only way to appreciate what the two questions actually
span.

The per-round cost model, read straight off the region layout
(`q = v div 256`, the trial loop's quotient):

| Piece | Cost |
|---|---|
| Self-test (once) | 4 |
| Power-on `r4 = 0` (once) | 1 |
| Round header | 2 |
| Non-final byte | 8 hash + 1 + 7q + 5 trial-divide + 2 = **16 + 7q** |
| Final byte | 8 |
| Check, not halting | 3 |
| Check, halting | 2 (the `eqrr`, then the `addr` that jumps off the end) |

The model is cross-checked against the real VM at the first two
check arrivals — both say `[1846, 338955]` — and then summed over
the whole stream:

| Question | Halts at | Instructions executed |
|---|---|---:|
| Part 1 (fewest) | check #1, r0 = 12213578 | **1,848** |
| Part 2 (most) | check #12,868, r0 = 5310683 | **2,976,386,661** |

Note the second check arrives at step 338,955 — round 2 alone costs
~337,000 instructions, 183× round 1, because its `v` is a 24-bit
probe rather than `0x10000`. That ratio is the divide loop's `7q`
term doing exactly what the profile said it would.

So the same program, asked the same question with two different
seeds for r0, runs for either 1.8 thousand or 2.98 *billion*
instructions — a factor of 1.6 million, all of it spent
re-deriving `div` by trial multiplication. For calibration, the
billions-scale run is what our Part 2 *avoids* simulating: the
lifted hash replays those 2.98 × 10⁹ instructions as ~38,600 native
arithmetic operations in 2.3 ms.

---

## Where this lands in the 16 / 19 / 21 trilogy

The forward reference in the [Day 16 supplement](day16_disassembly.md)
can now be resolved:

| Day | Test program is... | Reverse-engineering task |
|----:|---|---|
| 16 | Anti-content: 868 straight-line instructions producing one constant. | Identify all 16 opcodes. |
| 19 | A real algorithm hidden in brute force: σ(N). | Read the assembly; compute σ(N) in O(√N). |
| 21 | A real *generator* run against your input: an FNV-style hash emitting a probe stream. | Find the one instruction that reads r0; characterise the stream it sees. |

The escalation is in *what kind of object you recover*. Day 16
recovers a **mapping** (code → op). Day 19 recovers a **function**
(the program = σ(N), so compute it directly). Day 21 recovers a
**sequence** — the program is a generator, its output is an
eventually-periodic stream, and both answers are order statistics
of that stream (first element; last element of the first lap). The
Day 16 supplement predicted Part 2 would be "something close to
'what is the longest non-repeating input'" — close: it's the last
value *of* the non-repeating prefix.

And the running theme of the trilogy, stated once more with data:
in all three puzzles the simulator is *correct* and the puzzle is
calibrated so correctness isn't enough. Day 16's program runs fine
(868 steps). Day 19 Part 2 doesn't (10¹⁴ steps). Day 21 sits
exactly in between — 2.98 × 10⁹ steps is *almost* simulable, maybe
an hour of immutable-array VM — which is the puzzle's way of
letting you *feel* the trial-divide loop before you read it.

---

## Reproducing this analysis

The disassembly, trace, profile, stream statistics, and instruction
counts were all produced by
[scripts/day21_disassemble.hs](../../scripts/day21_disassemble.hs),
which imports Day 21's exposed `parseInput` / `checkInfo` /
`hashSpec` / `probes` plus Day 16's `applyOp`, and instruments the
same VM loop the solution uses.

Run from the repo root:

```
runghc -isrc scripts/day21_disassemble.hs > scripts/day21_disassembly.txt
```

The 159-line output is checked in at
[scripts/day21_disassembly.txt](../../scripts/day21_disassembly.txt)
as a frozen reference for this supplement. Re-running it on a
different `inputs/day21.txt` produces a different seed, different
probes, different tail/cycle lengths, and different instruction
counts — but the same regions, the same idioms, and the same
98%-and-up profile shape.

---

**Navigation**: [← Day 21 function guide](day21_function_guide.md) | [All Days](summary_2018.md) | [Day 16 supplement (phase 1 of this arc)](day16_disassembly.md)
