"""Visualize AoC 2018 Day 10's converging starfield.

Generates two figures.

**Figure 1: `scripts/day10_visualization.png`** -- the main story.

1. **Bounding-box area vs t** (log y-axis, full t-range from 0 to ~22000).
   The curve dips sharply to a unique minimum at t = 10595 -- this is
   the empirical justification for the "step until area would grow"
   search in Day10.hs.  Dashed grey lines mark the snapshot times so
   you can see where each one sits on the area curve.

2. **Eight point-cloud snapshots** laid out as a 2x4 grid.  Top row
   is the approach (t = 0, t_min/4, t_min/2, t_min - 200); bottom
   row is the message itself plus the symmetric departure
   (t_min, t_min + 200, t_min + t_min/2, 2*t_min).  Each subplot is
   zoomed to its own bounding box so the cluster shape stays visible
   even as the bbox area shrinks by a factor of ~10^7 between t=0
   and the message frame.

**Figure 2: `scripts/day10_reflection_diff.png`** -- red/blue overlay.

Overlay of t = 0 (red) and t = 2*t_min (blue) clusters at their
actual positions, with the three missing (vx, vy) buckets annotated
in both clusters and connected through the message centre by dashed
lines.  Inspired by the "red and blue transparency overlay" trick
used for PCB-layout diffs: anywhere one color appears without the
other is a real difference.  Here the only such "diff" features are
the six gaps from the three unsampled velocity pairs.

Y-axis is inverted in all spatial plots to match the puzzle's
coordinate convention (positive y points down, rows of the rendered
grid).

Run from the project root:

    python scripts/plot_day10.py

Outputs:
    scripts/day10_visualization.png
    scripts/day10_reflection_diff.png
"""

import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


POINT_RE = re.compile(
    r'position=<\s*(-?\d+),\s*(-?\d+)>\s*velocity=<\s*(-?\d+),\s*(-?\d+)>'
)


def load_points(path: Path) -> np.ndarray:
    """Returns an Nx4 int64 array of (px, py, vx, vy) rows."""
    rows: list[list[int]] = []
    for line in path.read_text().splitlines():
        m = POINT_RE.match(line.strip())
        if m:
            rows.append([int(g) for g in m.groups()])
    return np.array(rows, dtype=np.int64)


def missing_velocity_pairs(points: np.ndarray) -> list[tuple[int, int]]:
    """Return every (vx, vy) in the full 10x10 grid that has 0 points.

    The full grid is {-5,...,-1,1,...,5}^2.  The puzzle's input never
    has vx = 0 or vy = 0, so we restrict to that 100-cell grid.
    """
    vs = (-5, -4, -3, -2, -1, 1, 2, 3, 4, 5)
    present = {(int(vx), int(vy)) for vx, vy in points[:, 2:4]}
    return [(vx, vy) for vx in vs for vy in vs if (vx, vy) not in present]


def render_reflection_figure(points: np.ndarray, t_min: int,
                              out_path: Path) -> None:
    """Plot t=0 (red) and t=2*t_min (blue) clusters on the same axes.

    The two clusters are point-reflections of each other through the
    message centre (X_final, Y_final).  If the puzzle had sampled all
    100 (vx, vy) pairs, this overlay would be a perfect mirror -- every
    red dot would have a blue dot in the diagonally opposite position.

    For the actual input, three (vx, vy) pairs are unsampled, which
    breaks the mirror at six specific cells: three red gaps at t = 0
    and three blue gaps at t = 2*t_min, point-reflected through the
    centre.  We annotate each missing cell with a hollow circle in
    the colour of the cluster it belongs to, and connect each red-blue
    partner pair with a dashed line through the message centre.
    """
    # Cluster positions.
    pos_0_x  = points[:, 0]                              # t = 0
    pos_0_y  = points[:, 1]
    pos_2t_x = points[:, 0] + 2 * t_min * points[:, 2]   # t = 2 * t_min
    pos_2t_y = points[:, 1] + 2 * t_min * points[:, 3]

    # Message centre: mean position at t_min.  Used as the reflection
    # axis; also drawn as a black + marker.
    pos_min_x = points[:, 0] + t_min * points[:, 2]
    pos_min_y = points[:, 1] + t_min * points[:, 3]
    cx = float(pos_min_x.mean())
    cy = float(pos_min_y.mean())

    missing = missing_velocity_pairs(points)

    fig, ax = plt.subplots(figsize=(11, 11))

    ax.scatter(pos_0_x, pos_0_y, s=28, color='#d62728', alpha=0.45,
               edgecolor='none', label='t = 0 (red)')
    ax.scatter(pos_2t_x, pos_2t_y, s=28, color='#1f77b4', alpha=0.45,
               edgecolor='none', label=f't = 2*t_min = {2 * t_min:,} (blue)')

    # Hollow circles at the missing cells.  rx,ry is where the red dot
    # would have been at t=0; bx,by is its point-reflected partner at
    # t = 2*t_min.
    for vx, vy in missing:
        rx = cx - t_min * vx
        ry = cy - t_min * vy
        bx = cx + t_min * vx
        by = cy + t_min * vy
        ax.scatter([rx], [ry], marker='o', s=260, facecolor='none',
                   edgecolor='#d62728', linewidth=2.2, zorder=6)
        ax.scatter([bx], [by], marker='o', s=260, facecolor='none',
                   edgecolor='#1f77b4', linewidth=2.2, zorder=6)
        ax.plot([rx, bx], [ry, by], color='#555555', linewidth=0.7,
                linestyle='--', alpha=0.55, zorder=4)
        ax.annotate(f'(vx={vx}, vy={vy})', xy=(rx, ry),
                    xytext=(10, -14), textcoords='offset points',
                    fontsize=9, color='#d62728')

    # Message centre marker.
    ax.scatter([cx], [cy], marker='+', s=320, color='black',
               linewidth=2.2, zorder=10)
    ax.annotate(f'message centre\n({cx:.0f}, {cy:.0f})',
                xy=(cx, cy), xytext=(14, -8),
                textcoords='offset points', fontsize=10)

    ax.set_aspect('equal')
    ax.invert_yaxis()
    ax.grid(True, alpha=0.3)
    ax.set_xlabel('x')
    ax.set_ylabel('y')
    ax.set_title(
        'Red (t = 0) vs blue (t = 2*t_min): the two clusters are\n'
        f'point-symmetric through the message centre.  '
        f'{len(missing)} unsampled (vx, vy) pairs leave 3 red gaps + '
        f'3 mirror blue gaps;\nthe dashed lines connect each missing '
        'red-blue partner pair through the centre.'
    )
    ax.legend(loc='upper right', fontsize=9)

    fig.tight_layout()
    fig.savefig(out_path, dpi=140, bbox_inches='tight')
    print(f'wrote {out_path}')


def main() -> None:
    project_root = Path(__file__).resolve().parent.parent
    points = load_points(project_root / 'inputs' / 'day10.txt')
    n = len(points)

    # Vectorised: positions for every t in [0, T_MAX) at once.
    # T_MAX is chosen as ~2 x t_min so the area curve shows the full
    # symmetric rise after the message moment.
    T_MAX = 22000
    ts = np.arange(0, T_MAX)
    xs = points[:, 0:1] + ts * points[:, 2:3]      # n x T
    ys = points[:, 1:2] + ts * points[:, 3:4]      # n x T
    widths  = xs.max(axis=0) - xs.min(axis=0)      # T
    heights = ys.max(axis=0) - ys.min(axis=0)      # T
    areas   = widths * heights                     # T
    t_min   = int(areas.argmin())

    print(f'loaded {n} points')
    print(f't_min          = {t_min:,}')
    print(f'bbox at t_min  = {widths[t_min]:,} x {heights[t_min]:,}')
    print(f'area at t_min  = {areas[t_min]:,}')
    print(f'area at t=0    = {areas[0]:,}')
    print(f'shrinkage      = ~{areas[0] / areas[t_min]:,.0f}x')

    missing = missing_velocity_pairs(points)
    print(f'missing (vx,vy) pairs: {missing}')

    # Row 1: approach.  Row 2: the message moment, then the mirrored
    # departure.  The far-right of row 2 (t = 2*t_min) mirrors the
    # far-left of row 1 (t = 0).
    snapshot_times = [0,              t_min // 4,    t_min // 2,    t_min - 200,
                      t_min,          t_min + 200,   t_min + t_min // 2, 2 * t_min]

    fig = plt.figure(figsize=(18, 11))
    gs = fig.add_gridspec(3, 4, height_ratios=[0.9, 1.2, 1.2],
                          hspace=0.45, wspace=0.30)

    # Top row spans all 3 columns: bbox area vs t.
    ax_area = fig.add_subplot(gs[0, :])
    ax_area.semilogy(ts, areas, linewidth=1.2, color='#1f77b4',
                     label='bbox area')
    ax_area.axvline(t_min, color='#d62728', linewidth=1, linestyle='--',
                    alpha=0.7, label=f't_min = {t_min:,}')
    ax_area.scatter([t_min], [areas[t_min]], color='#d62728',
                    s=50, zorder=5)
    for t in snapshot_times:
        if t == t_min:
            continue
        ax_area.axvline(t, color='#7f7f7f', linewidth=0.5,
                        linestyle=':', alpha=0.5)
    ax_area.set_xlabel('t (seconds)')
    ax_area.set_ylabel('bounding-box area (log scale)')
    ax_area.set_title(
        f'Bounding-box area is quasi-convex: shrinks '
        f'~{areas[0] / areas[t_min]:,.0f}x then grows again. '
        f'Minimum (area = {areas[t_min]:,}) at t = {t_min:,}. '
        f'Dotted greys mark the snapshot frames below.'
    )
    ax_area.grid(True, which='both', alpha=0.3)
    ax_area.legend(loc='upper right')

    # Bottom 2 rows: 8 snapshots in a 2x4 grid.
    for i, t in enumerate(snapshot_times):
        row = 1 + i // 4
        col = i % 4
        ax = fig.add_subplot(gs[row, col])

        pos_x = points[:, 0] + t * points[:, 2]
        pos_y = points[:, 1] + t * points[:, 3]

        # Slightly bigger square markers for the message frame so the
        # discrete points visually fill in the letter strokes.
        is_msg = (t == t_min)
        marker_size = 22 if is_msg else 6
        marker_shape = 's' if is_msg else 'o'
        colour = '#000000' if is_msg else '#1f77b4'

        ax.scatter(pos_x, pos_y, s=marker_size, marker=marker_shape,
                   color=colour)

        x0, x1 = int(pos_x.min()), int(pos_x.max())
        y0, y1 = int(pos_y.min()), int(pos_y.max())
        w, h   = x1 - x0, y1 - y0
        pad    = max(w, h, 1) * 0.06
        ax.set_xlim(x0 - pad, x1 + pad)
        ax.set_ylim(y1 + pad, y0 - pad)        # invert y -- puzzle convention

        marker_text = '   *** MESSAGE: JLPZFJRH ***' if is_msg else ''
        ax.set_title(f't = {t:,} | bbox {w:,} x {h:,}{marker_text}',
                     fontsize=10)
        ax.set_aspect('equal')
        ax.grid(True, alpha=0.2)
        ax.tick_params(labelsize=8)

    fig.suptitle(
        'AoC 2018 Day 10 - starfield converging to spell "JLPZFJRH" at t = 10595',
        fontsize=13, y=0.995
    )
    out_path = project_root / 'scripts' / 'day10_visualization.png'
    fig.savefig(out_path, dpi=140, bbox_inches='tight')
    print(f'wrote {out_path}')

    # Second figure: red/blue overlay showing the three missing pairs.
    reflection_path = project_root / 'scripts' / 'day10_reflection_diff.png'
    render_reflection_figure(points, t_min, reflection_path)


if __name__ == '__main__':
    main()
