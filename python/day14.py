"""Day 14: Chocolate Charts -- AoC 2018.

Algorithm reference in Python.  The shipping solution is Haskell in
src/Day14.hs; this file shows the same simulation without the ST monad
ceremony.

Run from the repo root:

    python python/day14.py

Reads inputs/day14.txt and prints both parts.

Two elves on a scoreboard of digits.  Each round, append the digits of
the sum of their current scores, then each elf advances by 1 + their
own score (with wraparound modulo the new length).

Part 1: simulate until len >= N + 10, return digits N..N+9 as a string.
Part 2: simulate until the trailing edge matches the puzzle's digit
        pattern, return the index at which the pattern starts.
"""
from pathlib import Path

INPUT = Path(__file__).parent.parent / "inputs" / "day14.txt"


def simulate_after(n: int) -> str:
    """Part 1: ten digits after position n."""
    board = [3, 7]
    i, j = 0, 1
    while len(board) < n + 10:
        a, b = board[i], board[j]
        s = a + b
        if s >= 10:
            board.append(s // 10)
            board.append(s % 10)
        else:
            board.append(s)
        i = (i + 1 + a) % len(board)
        j = (j + 1 + b) % len(board)
    return "".join(str(d) for d in board[n:n + 10])


def simulate_until(pat: list[int]) -> int:
    """Part 2: index at which the digit pattern first appears."""
    board = [3, 7]
    i, j = 0, 1
    plen = len(pat)
    last = pat[-1]
    # Check the seed in case the pattern matches "3" or "37" itself.
    if board[-plen:] == pat:
        return 0
    while True:
        a, b = board[i], board[j]
        s = a + b
        # Append one digit at a time so we can check between the two.
        if s >= 10:
            board.append(s // 10)
            if board[-1] == last and board[-plen:] == pat:
                return len(board) - plen
            board.append(s % 10)
            if board[-1] == last and board[-plen:] == pat:
                return len(board) - plen
        else:
            board.append(s)
            if board[-1] == last and board[-plen:] == pat:
                return len(board) - plen
        i = (i + 1 + a) % len(board)
        j = (j + 1 + b) % len(board)


def main() -> None:
    raw = INPUT.read_text().strip()
    n = int(raw)
    pat = [int(c) for c in raw]
    print(f"  part 1: {simulate_after(n)}")
    print(f"  part 2: {simulate_until(pat)}")


if __name__ == "__main__":
    main()
