# Advent of Code 2018 — in Haskell

Solutions to [Advent of Code 2018](https://adventofcode.com/2018), written in Haskell, as a learning project.

Haskell is new to me; Rust, C, and AUTOSAR are not. Before starting the puzzles, this repo runs an 11-day Haskell ramp-up so the solutions are written from a real foundation rather than copy-pasted from Stack Overflow.

## Status

Tutorial in progress. Puzzle solutions have not started yet.

- [x] Day 1 of tutorial — install + Hello World
- [ ] Days 2–11 of tutorial — language fundamentals
- [ ] Puzzle solutions

## Repo layout

```
.
├── tutorial/              -- 11-day Haskell ramp-up (start here)
│   ├── README.md          -- plan overview
│   └── dayX/              -- one folder per day: README.md + src/
├── Problem_Statements/    -- puzzle text for all 25 days
│   └── days/dayNN.md
├── src/                   -- solution modules (to be added)
└── inputs/                -- personal puzzle inputs (gitignored per AoC policy)
```

## Getting started with the tutorial

1. Install [GHCup](https://www.haskell.org/ghcup/) and run `ghcup tui` to install `ghc`, `cabal`, and `ghci`.
2. Open [tutorial/README.md](tutorial/README.md) for the 11-day plan.
3. Start with [tutorial/day1/README.md](tutorial/day1/README.md).

Each tutorial day is self-contained: a `README.md` walkthrough plus a `src/` folder of runnable Haskell files.

## Toolchain

- **GHC 9.8+** — the Glasgow Haskell Compiler
- **cabal** — build tool and package manager (will be introduced on Day 10 of the tutorial)
- **GHCi** — the REPL; used constantly while learning

## Not in this repo

- `inputs/` — per AoC's [redistribution policy](https://adventofcode.com/about), personal puzzle inputs are kept local.
- `reference/` — a local Rust AoC 2017 solution set used as a style cross-reference while learning.

---

Puzzle content © [Eric Wastl](https://adventofcode.com/2018/about). Solutions and tutorial material in this repo are mine.
