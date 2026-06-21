"""Day 24: Immune System Simulator 20XX -- AoC 2018.

Algorithm reference in Python.  The shipping solution lives in
src/Day24.hs; this file is here so the combat *rules* read without
Haskell's IntMap plumbing in the way.

Two armies (Immune System, Infection), each a set of groups.  A group
is a pile of identical units with hit points, an attack (damage +
type), an initiative, and optional weaknesses/immunities.  Combat is a
sequence of fights; each fight has two phases:

  * Target selection: in decreasing effective power (ties: higher
    initiative) each group picks the enemy it would damage most (ties:
    largest effective power, then highest initiative); a group that can
    deal no damage picks nothing, and each defender is claimed once.

  * Attacking: in decreasing initiative, each group hits its target.
    Damage = effective power, doubled if the defender is weak, zeroed if
    immune.  The defender loses floor(damage / hp) whole units.

Fights repeat until an army is wiped out.

  * Part 1: total units in the winning army.
  * Part 2: smallest attack boost added to every Immune System group
    that makes the Immune System win; report its surviving units.  Some
    boosts deadlock (a fight kills nobody) -- detect that or loop forever.

Run from the repo root:

    python python/day24.py

Reads inputs/day24.txt and prints both parts.
"""
import re
from copy import deepcopy
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day24.txt"


class Group:
    __slots__ = ("army", "units", "hp", "weak", "immune",
                 "attack", "atype", "initiative")

    def __init__(self, army, units, hp, weak, immune, attack, atype, initiative):
        self.army = army
        self.units = units
        self.hp = hp
        self.weak = weak
        self.immune = immune
        self.attack = attack
        self.atype = atype
        self.initiative = initiative

    @property
    def power(self):
        return self.units * self.attack

    def damage_to(self, other):
        if self.atype in other.immune:
            return 0
        if self.atype in other.weak:
            return 2 * self.power
        return self.power


LINE = re.compile(
    r"(\d+) units each with (\d+) hit points (?:\(([^)]*)\) )?"
    r"with an attack that does (\d+) (\w+) damage at initiative (\d+)"
)


def parse_mods(clause):
    """'(weak to a, b; immune to c)' inner text -> (weak set, immune set)."""
    weak, immune = set(), set()
    if not clause:
        return weak, immune
    for part in clause.split("; "):
        kind, _, rest = part.partition(" to ")
        types = set(rest.split(", "))
        (weak if kind == "weak" else immune).update(types)
    return weak, immune


def parse(text):
    groups = []
    army = None
    for line in text.strip().splitlines():
        if line.endswith(":"):
            army = "immune" if line.startswith("Immune") else "infection"
            continue
        if not line.strip():
            continue
        units, hp, mods, atk, atype, init = LINE.match(line).groups()
        weak, immune = parse_mods(mods)
        groups.append(Group(army, int(units), int(hp), weak, immune,
                            int(atk), atype, int(init)))
    return groups


def fight(groups):
    """Run one fight in place.  Return units killed (0 means stalemate)."""
    # --- target selection ---
    chosen = {}                                   # attacker id -> defender
    targeted = set()
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


def run_combat(groups):
    """Return (winning_army_or_None, total_units).  None army = stalemate."""
    groups = deepcopy(groups)
    while True:
        armies = {g.army for g in groups}
        if len(armies) <= 1:
            return (armies.pop() if armies else None,
                    sum(g.units for g in groups))
        if fight(groups) == 0:
            return None, 0                         # stalemate


def part1(groups):
    _, units = run_combat(groups)
    return units


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


def main():
    groups = parse(INPUT.read_text())
    print("part 1:", part1(groups))
    print("part 2:", part2(groups))


if __name__ == "__main__":
    main()
