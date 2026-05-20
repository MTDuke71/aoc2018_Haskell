"""Day 19: Go With The Flow -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day19.hs; this file is here so the *algorithm* reads without
Haskell's NFData/array plumbing in the way.

The device is the same six-letter ALU as Day 16, except now the
instruction pointer is bound to a register:

    1. Write the current IP into the bound register.
    2. Execute the instruction at that IP.
    3. Read the bound register back as the new IP.
    4. Add one.  Halt if the IP is now outside the program.

Part 1 just runs the simulator to halt with all-zero registers.

Part 2 sets register 0 to 1 and runs from there.  The naive
simulator does NOT finish -- the program is a brute-force divisor
sum on a number around 10^7, i.e. roughly 10^14 inner-loop
iterations.  So we read the assembly:

    r2 = N      # the setup computes some N around 10^7
    r0 = 0
    for r5 in 1..N:
        for r3 in 1..N:
            if r5 * r3 == N:
                r0 += r5
    halt

That is just sum_of_divisors(N).  We simulate only the setup phase
to recover N, then compute the answer in O(sqrt N) instead of O(N^2).

The setup phase ends when control returns to the main loop.  The
first instruction is invariably `addi <ipR> K <ipR>`, meaning "jump
K+1 ahead": the main loop occupies IPs 1..K, the setup is at K+1
onwards.  When the IP drops back below K+1 after having visited K+1,
setup is done and the registers hold N (the maximum, in fact).

Run from the repo root:

    python python/day19.py

Reads inputs/day19.txt and prints both parts.
"""
from math import isqrt
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day19.txt"


# ---------------------------------------------------------------------------
# The ALU -- exactly Day 16
# ---------------------------------------------------------------------------

def apply_op(op, a, b, c, regs):
    """Return a new register file after running 'op a b c' on regs."""
    out = list(regs)
    r = regs.__getitem__
    if   op == "addr": out[c] = r(a) + r(b)
    elif op == "addi": out[c] = r(a) + b
    elif op == "mulr": out[c] = r(a) * r(b)
    elif op == "muli": out[c] = r(a) * b
    elif op == "banr": out[c] = r(a) & r(b)
    elif op == "bani": out[c] = r(a) & b
    elif op == "borr": out[c] = r(a) | r(b)
    elif op == "bori": out[c] = r(a) | b
    elif op == "setr": out[c] = r(a)
    elif op == "seti": out[c] = a
    elif op == "gtir": out[c] = 1 if a   >  r(b) else 0
    elif op == "gtri": out[c] = 1 if r(a) >  b   else 0
    elif op == "gtrr": out[c] = 1 if r(a) >  r(b) else 0
    elif op == "eqir": out[c] = 1 if a   == r(b) else 0
    elif op == "eqri": out[c] = 1 if r(a) == b   else 0
    elif op == "eqrr": out[c] = 1 if r(a) == r(b) else 0
    else: raise ValueError(f"unknown op: {op}")
    return out


# ---------------------------------------------------------------------------
# Parse + run
# ---------------------------------------------------------------------------

def parse(text):
    """(ip_reg, [(op, a, b, c)])."""
    lines = [l for l in text.splitlines() if l]
    assert lines[0].startswith("#ip ")
    ip_reg = int(lines[0].split()[1])
    program = []
    for line in lines[1:]:
        parts = line.split()
        program.append((parts[0], int(parts[1]), int(parts[2]), int(parts[3])))
    return ip_reg, program


def run(ip_reg, program, regs):
    """Run to halt.  Returns the final register file."""
    ip = 0
    n = len(program)
    while 0 <= ip < n:
        op, a, b, c = program[ip]
        regs = apply_op(op, a, b, c, list(regs[:ip_reg]) + [ip] + list(regs[ip_reg+1:]))
        ip = regs[ip_reg] + 1
    return regs


def part1(ip_reg, program):
    regs = run(ip_reg, program, [0] * 6)
    return regs[0]


# ---------------------------------------------------------------------------
# Part 2: simulate setup only, then closed-form sum of divisors
# ---------------------------------------------------------------------------

def first_setup_ip(program):
    """First IP belonging to the setup region.

    Every Day 19 input opens with `addi <ipR> K <ipR>`, which adds K
    to the IP-bound register; the post-step increment then puts the
    IP at K+1 (the setup entry).  So the main loop is at IPs 1..K
    and the setup begins at K+1.
    """
    op, _a, k, _c = program[0]
    assert op == "addi", f"expected 'addi' at ip=0, got {op}"
    return k + 1


def run_until_setup_complete(ip_reg, program, regs):
    """Step the VM until control returns to the main loop after visiting setup."""
    setup_start = first_setup_ip(program)
    ip = 0
    n = len(program)
    visited_setup = False
    while 0 <= ip < n:
        if ip < setup_start and visited_setup:
            return regs
        op, a, b, c = program[ip]
        regs = apply_op(op, a, b, c, list(regs[:ip_reg]) + [ip] + list(regs[ip_reg+1:]))
        ip = regs[ip_reg] + 1
        if ip >= setup_start:
            visited_setup = True
    return regs


def sum_of_divisors(n):
    """O(sqrt n) divisor sum.  Pair each d <= sqrt(n) with n // d."""
    if n <= 0:
        return 0
    total = 0
    for d in range(1, isqrt(n) + 1):
        if n % d == 0:
            total += d
            if d * d != n:
                total += n // d
    return total


def part2(ip_reg, program):
    regs = run_until_setup_complete(ip_reg, program, [1, 0, 0, 0, 0, 0])
    n = max(regs)
    return sum_of_divisors(n)


# ---------------------------------------------------------------------------

def main():
    ip_reg, program = parse(INPUT.read_text())
    print(f"  part 1: {part1(ip_reg, program)}")
    print(f"  part 2: {part2(ip_reg, program)}")


if __name__ == "__main__":
    main()
