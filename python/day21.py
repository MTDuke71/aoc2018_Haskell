"""Day 21: Chronal Conversion -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day21.hs; this file is here so the *algorithm* reads without
Haskell's array plumbing in the way.

Same device as Days 16/19.  This time the program never halts on
its own: the only exit is an `eqrr X 0 _` instruction -- "compare
register X with register 0, and fall off the end of the program if
they are equal".  Register 0 is otherwise never read or written, so
it is a pure *spectator*: the sequence of values register X holds
at that comparison is fixed, and our only move is to pick r0 to
match one of them.

    Part 1: the FIRST value X takes at the check (halts soonest).
    Part 2: the LAST NEW value before the sequence starts repeating
            (halts latest while still halting at all).

What the program between checks actually computes is a byte-at-a-
time hash, FNV-style (add a byte, multiply by a prime, mask to 24
bits).  Each round feeds the previous check value (widened with
bit 16) through the hash a byte at a time:

    v = prev | 0x10000          # 17 bits -> three byte-feed steps
    acc = SEED
    while True:
        acc = (((acc + (v & 0xFF)) & 0xFFFFFF) * MULT) & 0xFFFFFF
        if v < 256: break
        v //= 256               # the assembly does this with a
                                # painfully slow trial-add loop
    # acc is the next check value

The VM spends 99.99% of its time in that `v //= 256` trial loop
(the device has no shift or divide instruction!), so Part 2 is
done by lifting the hash into native code: ~10k rounds of pure
arithmetic instead of ~3 billion simulated instructions.

All the constants (SEED, MULT, the masks) are extracted from the
program text, not hard-coded -- every AoC input is this same
template with different numbers.

Run from the repo root:

    python python/day21.py

Reads inputs/day21.txt and prints both parts.
"""
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day21.txt"


# ---------------------------------------------------------------------------
# Parse (same format as Day 19)
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


# ---------------------------------------------------------------------------
# Locate the halt check
# ---------------------------------------------------------------------------

def check_info(program):
    """(ip, reg) of the unique `eqrr reg 0 _` halt comparison."""
    hits = []
    for ip, (op, a, b, _c) in enumerate(program):
        if op == "eqrr" and b == 0:
            hits.append((ip, a))
        elif op == "eqrr" and a == 0:
            hits.append((ip, b))
    assert len(hits) == 1, f"expected one eqrr-vs-r0, found {hits}"
    return hits[0]


# ---------------------------------------------------------------------------
# Part 1: run the VM until it first reaches the check
# ---------------------------------------------------------------------------

def apply_op(op, a, b, c, regs):
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


def part1(ip_reg, program):
    """First value compared against r0 -- a few thousand VM steps."""
    check_ip, check_reg = check_info(program)
    regs = [0] * 6
    ip = 0
    while True:
        if ip == check_ip:
            return regs[check_reg]
        op, a, b, c = program[ip]
        regs[ip_reg] = ip
        regs = apply_op(op, a, b, c, regs)
        ip = regs[ip_reg] + 1


# ---------------------------------------------------------------------------
# Part 2: lift the hash into native code
# ---------------------------------------------------------------------------

def hash_spec(program):
    """(seed, mult, hash_mask, byte_mask, widen) from the program text.

    Every input shares this six-instruction template (the `bori` is
    unique in the program, so it anchors the match):

        bori f  WIDEN     v      # v = prev | 0x10000
        seti SEED  _      acc    # acc = seed
        bani v  BYTE_MASK t      # t = v & 0xFF
        addr acc t        acc    # acc += t
        bani acc HASH_MASK acc   # acc &= 0xFFFFFF
        muli acc MULT     acc    # acc *= 65899  (then masked again)
    """
    boris = [ip for ip, (op, *_rest) in enumerate(program) if op == "bori"]
    assert len(boris) == 1, f"expected one bori, found {boris}"
    b = boris[0]
    (_,  _, widen,     _) = program[b]
    (op, seed, _,      _) = program[b + 1];  assert op == "seti"
    (op, _, byte_mask, _) = program[b + 2];  assert op == "bani"
    (op, _, hash_mask, _) = program[b + 4];  assert op == "bani"
    (op, _, mult,      _) = program[b + 5];  assert op == "muli"
    return seed, mult, hash_mask, byte_mask, widen


def next_probe(spec, prev):
    """One full round: previous check value -> next check value."""
    seed, mult, hash_mask, byte_mask, widen = spec
    v = prev | widen
    acc = seed
    while True:
        acc = (((acc + (v & byte_mask)) & hash_mask) * mult) & hash_mask
        if v <= byte_mask:
            return acc
        v //= byte_mask + 1


def part2(ip_reg, program):
    """Last new probe value before the sequence cycles."""
    spec = hash_spec(program)
    seen = set()
    prev = 0
    probe = next_probe(spec, 0)
    while probe not in seen:
        seen.add(probe)
        prev = probe
        probe = next_probe(spec, probe)
    return prev


# ---------------------------------------------------------------------------

def main():
    ip_reg, program = parse(INPUT.read_text())
    spec = hash_spec(program)
    p1 = part1(ip_reg, program)
    assert p1 == next_probe(spec, 0), "VM and native hash disagree on round 1"
    print(f"  part 1: {p1}")
    print(f"  part 2: {part2(ip_reg, program)}")


if __name__ == "__main__":
    main()
