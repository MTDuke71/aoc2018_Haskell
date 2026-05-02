"""Plot AoC 2018 Day 1 cycle 1, split into its two segments with offset y-axes.

Cycle 1 of the trajectory has two structurally distinct halves, separated by
the +76,538 cliff at line 576:

    Region A: steps   0..575    "low walk"     freq in [-1379, +126]
    Region B: steps 576..985    "high plateau" freq in [76,664, 77,674]

This script draws each segment on its own panel, offsetting Region B's
y-axis by the up-cliff delta (76,538) so that both regions can be read on a
shared y-scale. The point of the offset is to compare the *wiggle amplitudes*
of the two segments without the 76,538-unit cliff dominating the picture.

Run from the project root:

    python scripts/plot_day01_plateaus.py

Output: scripts/day01_plateaus.png
"""

from itertools import accumulate
from pathlib import Path

import matplotlib.pyplot as plt


def load_deltas(path: Path) -> list[int]:
    return [int(s.lstrip('+')) for s in path.read_text().split() if s]


def main() -> None:
    project_root = Path(__file__).resolve().parent.parent
    deltas = load_deltas(project_root / 'inputs' / 'day01.txt')

    cliff_up_line = 1 + max(range(len(deltas)), key=lambda i: deltas[i])
    cliff_up_delta = max(deltas)
    cliff_down_line = 1 + min(range(len(deltas)), key=lambda i: deltas[i])

    traj = [0] + list(accumulate(deltas))   # traj[k] = freq after step k

    region_a = traj[: cliff_up_line]                          # steps 0 .. cliff_up_line - 1
    region_b = traj[cliff_up_line : cliff_down_line]          # steps cliff_up_line .. cliff_down_line - 1

    a_steps = list(range(len(region_a)))
    b_steps = list(range(cliff_up_line, cliff_up_line + len(region_b)))

    a_min, a_max = min(region_a), max(region_a)
    a_argmin = a_steps[region_a.index(a_min)]
    a_argmax = a_steps[region_a.index(a_max)]

    b_min, b_max = min(region_b), max(region_b)
    b_argmin = b_steps[region_b.index(b_min)]
    b_argmax = b_steps[region_b.index(b_max)]   # = step 841 = first hit of 77674

    region_b_offset = [y - cliff_up_delta for y in region_b]

    y_lo = min(a_min, b_min - cliff_up_delta) - 150
    y_hi = max(a_max, b_max - cliff_up_delta) + 150

    fig, (ax_a, ax_b) = plt.subplots(2, 1, figsize=(11, 8.5))

    ax_a.plot(a_steps, region_a, linewidth=0.8, color='#1f77b4')
    ax_a.scatter([a_argmin], [a_min], color='#d62728', s=45, zorder=5,
                 label=f'min = {a_min:,} at step {a_argmin}')
    ax_a.scatter([a_argmax], [a_max], color='#2ca02c', s=45, zorder=5,
                 label=f'max = {a_max:+,} at step {a_argmax}')
    ax_a.axhline(0, color='#7f7f7f', linewidth=0.5, alpha=0.4)
    ax_a.set_ylim(y_lo, y_hi)
    ax_a.set_xlabel(f'step within cycle 1 (region A: 0 .. {cliff_up_line - 1})')
    ax_a.set_ylabel('cumulative frequency')
    ax_a.set_title(f'Region A — low walk (steps 0–{cliff_up_line - 1}, '
                   f'before the +{cliff_up_delta:,} cliff at line {cliff_up_line})')
    ax_a.grid(True, alpha=0.3)
    ax_a.legend(loc='lower left', fontsize=9)

    ax_b.plot(b_steps, region_b_offset, linewidth=0.8, color='#1f77b4')
    ax_b.scatter([b_argmin], [b_min - cliff_up_delta], color='#d62728', s=45, zorder=5,
                 label=f'min = {b_min:,} (raw) -> {b_min - cliff_up_delta:+,} (offset) at step {b_argmin}')
    ax_b.scatter([b_argmax], [b_max - cliff_up_delta], color='#2ca02c', s=45, zorder=5,
                 label=f'max = {b_max:,} (raw) -> {b_max - cliff_up_delta:+,} (offset) at step {b_argmax}'
                       f'  -- first hit of {b_max:,}')
    ax_b.axhline(0, color='#7f7f7f', linewidth=0.5, alpha=0.4)
    ax_b.set_ylim(y_lo, y_hi)
    ax_b.set_xlabel(f'step within cycle 1 (region B: {cliff_up_line} .. {cliff_down_line - 1})')
    ax_b.set_ylabel(f'cumulative frequency − {cliff_up_delta:,}  (offset y-axis)')
    ax_b.set_title(f'Region B — high plateau (steps {cliff_up_line}–{cliff_down_line - 1}, '
                   f'between the two cliffs; y offset by −{cliff_up_delta:,})')
    ax_b.grid(True, alpha=0.3)
    ax_b.legend(loc='lower right', fontsize=9)

    fig.suptitle('Cycle 1 split into its two regions, drawn on a shared y-scale',
                 fontsize=12, y=0.995)
    fig.tight_layout()

    out_path = project_root / 'scripts' / 'day01_plateaus.png'
    fig.savefig(out_path, dpi=140)
    print(f'wrote {out_path}')
    print()
    print(f'Region A (steps 0..{cliff_up_line - 1}):')
    print(f'  min = {a_min:>+8,} at step {a_argmin}')
    print(f'  max = {a_max:>+8,} at step {a_argmax}')
    print(f'  range = {a_max - a_min:,}')
    print()
    print(f'Region B (steps {cliff_up_line}..{cliff_down_line - 1}, offset by -{cliff_up_delta:,}):')
    print(f'  min = {b_min:>+8,}  (offset {b_min - cliff_up_delta:>+8,}) at step {b_argmin}')
    print(f'  max = {b_max:>+8,}  (offset {b_max - cliff_up_delta:>+8,}) at step {b_argmax}'
          f'  <-- first hit of 77,674')
    print(f'  range = {b_max - b_min:,}')


if __name__ == '__main__':
    main()
