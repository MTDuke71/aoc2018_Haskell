"""Day 16: Chronal Classification -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day16.hs; this file is here so the *algorithm* reads without
Haskell's types in the way.

Run from the repo root:

    python python/day16.py

Reads inputs/day16.txt and prints both parts.

Two ideas carry the day:

  1. An instruction set as one dispatch function.  `OPS[name](regs,
     a, b, c)` is exactly the `switch` in a bytecode VM's run loop.
     The `r`/`i` suffix is the operand mode (register vs immediate).

  2. Constraint propagation to recover the opcode numbering.  Each
     sample says "the op behind THIS number is one of {...}".
     Intersect those sets per number, then repeatedly assign any
     number whose set is a singleton and strike that op from every
     other set -- the Sudoku "naked single" / greedy bipartite
     matching rule.
"""
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day16.txt"

# The 16 ALU operations.  Each takes (regs, a, b, c) and returns the
# new register tuple.  `r`/`i` after the verb is operand A's / B's
# mode: r = "use the register numbered by this operand", i =
# "use this operand literally".  C is always a register to write.
def _w(regs, c, v):                       # write v into register c
    regs = list(regs)
    regs[c] = v
    return tuple(regs)

OPS = {
    "addr": lambda g, a, b, c: _w(g, c, g[a] + g[b]),
    "addi": lambda g, a, b, c: _w(g, c, g[a] + b),
    "mulr": lambda g, a, b, c: _w(g, c, g[a] * g[b]),
    "muli": lambda g, a, b, c: _w(g, c, g[a] * b),
    "banr": lambda g, a, b, c: _w(g, c, g[a] & g[b]),
    "bani": lambda g, a, b, c: _w(g, c, g[a] & b),
    "borr": lambda g, a, b, c: _w(g, c, g[a] | g[b]),
    "bori": lambda g, a, b, c: _w(g, c, g[a] | b),
    "setr": lambda g, a, b, c: _w(g, c, g[a]),
    "seti": lambda g, a, b, c: _w(g, c, a),
    "gtir": lambda g, a, b, c: _w(g, c, 1 if a > g[b] else 0),
    "gtri": lambda g, a, b, c: _w(g, c, 1 if g[a] > b else 0),
    "gtrr": lambda g, a, b, c: _w(g, c, 1 if g[a] > g[b] else 0),
    "eqir": lambda g, a, b, c: _w(g, c, 1 if a == g[b] else 0),
    "eqri": lambda g, a, b, c: _w(g, c, 1 if g[a] == b else 0),
    "eqrr": lambda g, a, b, c: _w(g, c, 1 if g[a] == g[b] else 0),
}


def nums(line):
    """Every run of digits on a line, as ints (ignores [], commas)."""
    out, cur = [], ""
    for ch in line:
        if ch.isdigit():
            cur += ch
        elif cur:
            out.append(int(cur))
            cur = ""
    if cur:
        out.append(int(cur))
    return out


def parse(text):
    """Return (samples, program).

    A sample is (before, instr, after); program is a list of instrs.
    Peel Before/instr/After triples off the front while the line
    starts with 'Before'; the rest is the test program.
    """
    lines = [ln for ln in text.splitlines() if ln.strip()]
    samples, i = [], 0
    while i < len(lines) and lines[i].startswith("Before"):
        before = tuple(nums(lines[i]))
        instr = tuple(nums(lines[i + 1]))
        after = tuple(nums(lines[i + 2]))
        samples.append((before, instr, after))
        i += 3
    program = [tuple(nums(ln)) for ln in lines[i:]]
    return samples, program


def matching(before, instr, after):
    """Names of the ops that turn `before` into `after` here."""
    _, a, b, c = instr
    return {name for name, fn in OPS.items() if fn(before, a, b, c) == after}


def part1(samples):
    return sum(1 for be, ins, af in samples if len(matching(be, ins, af)) >= 3)


def deduce(samples):
    """Numeric opcode -> op name, by constraint propagation."""
    cand = {}
    for be, ins, af in samples:
        code = ins[0]
        m = matching(be, ins, af)
        cand[code] = cand.get(code, set(OPS)) & m
    solved = {}
    while cand:
        code, ops = next((k, v) for k, v in cand.items() if len(v) == 1)
        op = next(iter(ops))
        solved[code] = op
        del cand[code]
        for k in cand:
            cand[k].discard(op)
    return solved


def part2(samples, program):
    codeof = deduce(samples)
    regs = (0, 0, 0, 0)
    for code, a, b, c in program:
        regs = OPS[codeof[code]](regs, a, b, c)
    return regs[0]


def main():
    samples, program = parse(INPUT.read_text())
    print(f"  part 1: {part1(samples)}")
    print(f"  part 2: {part2(samples, program)}")


if __name__ == "__main__":
    main()
