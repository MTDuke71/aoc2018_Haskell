"""Plot the AoC 2018 Day 1 Part 2 trajectory.

Walks the cycled list of frequency deltas, tracking the running cumulative
frequency, and stops as soon as a frequency is reached twice. Plots the full
trajectory and marks the two collision points plus Part 1's end-of-first-cycle
answer.

Run from the project root:

    python scripts/plot_day01.py

Output: scripts/day01_part2_trajectory.png
"""

from itertools import cycle as itertools_cycle
from pathlib import Path

import matplotlib.pyplot as plt


def load_deltas(path: Path) -> list[int]:
    return [int(line.lstrip('+')) for line in path.read_text().splitlines() if line]


def walk_until_repeat(deltas: list[int]) -> tuple[list[int], int, int]:
    """Walk the cycled deltas; return (trajectory, repeat_value, repeat_step).

    The trajectory starts at 0 (step 0) and ends at the *second* occurrence of
    the repeated value, inclusive. step indexes match `range(len(trajectory))`.
    """
    seen: dict[int, int] = {0: 0}
    trajectory = [0]
    freq = 0
    for step, d in enumerate(itertools_cycle(deltas), start=1):
        freq += d
        trajectory.append(freq)
        if freq in seen:
            return trajectory, freq, step
        seen[freq] = step


def main() -> None:
    project_root = Path(__file__).resolve().parent.parent
    deltas = load_deltas(project_root / 'inputs' / 'day01.txt')

    trajectory, repeat_val, repeat_step = walk_until_repeat(deltas)
    first_step = trajectory.index(repeat_val)  # earlier occurrence
    cycle_len = len(deltas)
    part1 = trajectory[cycle_len]

    big_idx = sorted(range(len(deltas)), key=lambda i: abs(deltas[i]), reverse=True)[:2]
    big_idx.sort()

    fig, (ax_top, ax_bot) = plt.subplots(2, 1, figsize=(11, 9),
                                          gridspec_kw={'height_ratios': [1.4, 1]})

    ax_top.plot(range(len(trajectory)), trajectory, linewidth=0.6, color='#1f77b4',
                label='cumulative frequency')
    ax_top.axhline(repeat_val, color='#d62728', linewidth=0.7, linestyle='--', alpha=0.6,
                   label=f'first repeat = {repeat_val}')
    ax_top.scatter([first_step, repeat_step], [repeat_val, repeat_val],
                   color='#d62728', s=40, zorder=5,
                   label=f'collision: step {first_step:,} & step {repeat_step:,}')
    ax_top.axvline(cycle_len, color='#7f7f7f', linewidth=0.7, linestyle=':', alpha=0.7)
    ax_top.scatter([cycle_len], [part1], color='#2ca02c', s=40, zorder=5,
                   label=f'Part 1 = {part1} (end of cycle 1, step {cycle_len})')
    ax_top.set_xlabel(f'step (1 cycle = {cycle_len} deltas)')
    ax_top.set_ylabel('cumulative frequency')
    ax_top.set_title(f'Full trajectory until first repeat '
                     f'({repeat_step:,} steps, ≈ {repeat_step / cycle_len:.1f} cycles)')
    ax_top.grid(True, alpha=0.3)
    ax_top.legend(loc='lower right', fontsize=9)

    one_cycle = trajectory[:cycle_len + 1]
    ax_bot.plot(range(len(one_cycle)), one_cycle, linewidth=0.9, color='#1f77b4')

    for i in big_idx:
        step_after = i + 1
        y_after = trajectory[step_after]
        sign = '+' if deltas[i] > 0 else ''
        ax_bot.scatter([step_after], [y_after], color='#ff7f0e', s=45, zorder=5)
        ax_bot.annotate(f'line {i + 1}: {sign}{deltas[i]:,}',
                        xy=(step_after, y_after),
                        xytext=(8, 12 if deltas[i] > 0 else -18),
                        textcoords='offset points', fontsize=9,
                        color='#ff7f0e')

    ax_bot.scatter([first_step], [trajectory[first_step]],
                   color='#d62728', s=40, zorder=5,
                   label=f'first hit of {repeat_val} (step {first_step})')
    ax_bot.axhline(repeat_val, color='#d62728', linewidth=0.7, linestyle='--', alpha=0.5)
    ax_bot.scatter([cycle_len], [part1], color='#2ca02c', s=40, zorder=5,
                   label=f'end of cycle 1 = {part1}')
    ax_bot.set_xlabel('step within cycle 1')
    ax_bot.set_ylabel('cumulative frequency')
    ax_bot.set_title(f'Cycle 1 alone — two outlier deltas at lines '
                     f'{big_idx[0] + 1} and {big_idx[1] + 1} dominate the shape; '
                     f'everything else is small noise')
    ax_bot.grid(True, alpha=0.3)
    ax_bot.legend(loc='lower left', fontsize=9)

    fig.tight_layout()
    out_path = project_root / 'scripts' / 'day01_part2_trajectory.png'
    fig.savefig(out_path, dpi=140)
    print(f'wrote {out_path}')
    print(f'  trajectory length: {len(trajectory):,} steps '
          f'({repeat_step / cycle_len:.2f} full cycles)')
    print(f'  Part 1 (end of cycle 1, step {cycle_len:,}): {part1}')
    print(f'  Part 2 (first repeated frequency): {repeat_val}')
    print(f'  first reached at step {first_step:,}, repeated at step {repeat_step:,}')


if __name__ == '__main__':
    main()
