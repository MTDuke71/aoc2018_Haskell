# Day 10 — modules, `cabal` projects, and `hspec` tests

**Goal**: graduate from single-file scripts to a real project. By the end you will know what a `.cabal` file is, how to split code across modules with hierarchical names, the difference between a library / executable / test-suite stanza, the four `cabal` commands you will actually use, and how to write and auto-discover `hspec` tests. The Day 9 example is rebuilt as a tiny project — same logic, split into modules with a real test suite around it.

**Source files**:
- [tutorial-day10.cabal](tutorial-day10.cabal) — the package description.
- [src/AoC/Parsing.hs](src/AoC/Parsing.hs) — pure parsing, exposed module 1.
- [src/AoC/Solver.hs](src/AoC/Solver.hs) — pure solver, exposed module 2.
- [app/Main.hs](app/Main.hs) — the executable: thin IO shell over the library.
- [test/Spec.hs](test/Spec.hs) — `hspec-discover` driver.
- [test/AoC/ParsingSpec.hs](test/AoC/ParsingSpec.hs), [test/AoC/SolverSpec.hs](test/AoC/SolverSpec.hs) — the actual tests.
- [sample.txt](sample.txt) — the same input we used on Day 9.
- [CHANGELOG.md](CHANGELOG.md) — required by the cabal file via `extra-doc-files`.

---

## 1. Why scaffold a project at all?

Days 1–9 fit one shape: write `Foo.hs`, run `runghc Foo.hs`. That works right up until you want any of these:

- Two files that share code (`module Util` used from both `Day01.hs` and `Day02.hs`).
- A library you can test from a separate file without copy-pasting code.
- A dependency on a package not in `base` — Day 8's `containers`, eventually `text`, `vector`, `parsec`, `attoparsec`, etc.
- One command that builds, runs, and tests the whole thing.

That is what `cabal` gives you. A project lives in one folder, has one `*.cabal` file describing what it contains and what it depends on, and supports a small set of commands to build / run / test / poke at it. Everything in this repo from Day 11 onward will live inside one such project.

**Rust analogue**: cabal is to Haskell what cargo is to Rust. A `.cabal` file is the rough equivalent of `Cargo.toml`; `cabal build` is `cargo build`; `cabal test` is `cargo test`; `cabal run` is `cargo run`. The shape will feel familiar — only the field names differ.

---

## 2. The Day 10 project at a glance

```
tutorial/day10/
├── tutorial-day10.cabal     -- the package file (one per project)
├── CHANGELOG.md             -- required by the cabal file
├── sample.txt               -- input data (read at runtime by the executable)
├── src/                     -- library code
│   └── AoC/
│       ├── Parsing.hs       -- module AoC.Parsing
│       └── Solver.hs        -- module AoC.Solver
├── app/                     -- executable entry point
│   └── Main.hs              -- module Main
└── test/                    -- test suite
    ├── Spec.hs              -- hspec-discover driver
    └── AoC/
        ├── ParsingSpec.hs   -- module AoC.ParsingSpec
        └── SolverSpec.hs    -- module AoC.SolverSpec
```

Three things to notice up front:

1. **The folder structure mirrors the module names.** `src/AoC/Parsing.hs` defines `module AoC.Parsing`. The compiler insists they match — get it wrong and you get *"file name does not match module name"* at build time.
2. **There is a `src/` for library code, an `app/` for the executable, and a `test/` for tests.** Those folder names are not magic — they are what the `.cabal` file tells cabal to look at via `hs-source-dirs:`. You could rename them; the convention is so universal that you should not.
3. **The library (`src/`) and the executable (`app/`) are separate things.** The executable depends on the library and just calls into it. That separation is what makes the library testable: the test suite imports the same modules the executable does, exercises them, and never has to spin up `Main`.

---

## 3. Anatomy of the `.cabal` file

Open [tutorial-day10.cabal](tutorial-day10.cabal). The file is plain text, indentation-sensitive (like YAML or Python), and grouped into **stanzas** — top-level blocks that describe one component of the package.

### 3a. The package header

```cabal
cabal-version:      3.0
name:               tutorial-day10
version:            0.1.0.0
synopsis:           Day 10 of the Haskell pre-AoC tutorial — cabal layout + hspec.
license:            BSD-3-Clause
author:             Matt LaDuke
maintainer:         matt.laduke@gmail.com
build-type:         Simple
extra-doc-files:    CHANGELOG.md
```

- **`cabal-version`** declares the format version of the file itself. `3.0` is the modern minimum; it unlocks `common` stanzas and a few quality-of-life features. Pin it; do not omit it.
- **`name`** must match the file name (`tutorial-day10.cabal`). It is also the name other packages would use to depend on this one.
- **`version`** is `MAJOR.MINOR.PATCH.BUILD` by convention. Bump it when you publish; for local-only projects it does not matter.
- **`synopsis`** is the one-line description. `description:` exists for longer text.
- **`license`** is an SPDX identifier. `BSD-3-Clause` is the most common in the Haskell ecosystem.
- **`build-type: Simple`** means "no custom Setup.hs" — cabal does the build itself. You will almost never want anything else.
- **`extra-doc-files`** lists files that ship in the package tarball but are not source. cabal will warn if any of them are missing, which is why this project has a [CHANGELOG.md](CHANGELOG.md) — the file exists only to satisfy that listing.

### 3b. The `common` stanza — shared options

```cabal
common warnings
    ghc-options: -Wall
```

A `common` stanza is a named block of settings other stanzas can pull in via `import:`. Here we declare *"every component should compile with `-Wall`"* once, then reuse it. Without `common` you would copy the same options into the library, the executable, and the test suite. This is the Haskell answer to "DRY" for cabal files.

### 3c. The `library` stanza

```cabal
library
    import:           warnings
    exposed-modules:  AoC.Parsing
                    , AoC.Solver
    build-depends:    base       >= 4.18 && < 5
                    , containers >= 0.6  && < 0.8
    hs-source-dirs:   src
    default-language: Haskell2010
```

- **`import: warnings`** pulls in the `common warnings` block above, so this stanza inherits `-Wall`.
- **`exposed-modules`** is the list of modules other packages (and the executable, and the tests) can `import`. A module not listed here is not visible outside the library — even if its `.hs` file exists.
- **`build-depends`** is the dependency list, with **PVP version bounds**. `base >= 4.18 && < 5` says "any base with major version 4 ≥ 18, but stop before 5." Bounds protect you from upstream breakage; cabal will refuse to build if there is no version in range.
- **`hs-source-dirs: src`** tells cabal where to look for `.hs` files. Combined with the module names, `AoC.Parsing` resolves to `src/AoC/Parsing.hs`.
- **`default-language: Haskell2010`** picks the language standard. `GHC2021` is the modern alternative; `Haskell2010` is the conservative default and what we will use until something forces us to switch.

### 3d. The `executable` stanza

```cabal
executable day10-solve
    import:           warnings
    main-is:          Main.hs
    build-depends:    base
                    , tutorial-day10
    hs-source-dirs:   app
    default-language: Haskell2010
```

- **`executable day10-solve`** declares an executable named `day10-solve`. That name is what `cabal run day10-solve` looks up; it is also the name of the binary cabal produces.
- **`main-is: Main.hs`** is the file containing `main`. Inside it, the module **must** be named `Main`.
- **`build-depends: ... tutorial-day10`** — the executable depends on its own library by name. That is how `app/Main.hs` can `import AoC.Parsing` and `AoC.Solver`. The version bound on `base` is omitted here (bare `base`), which inherits the bound from the library; that is fine for components in the same package.

### 3e. The `test-suite` stanza

```cabal
test-suite day10-test
    import:             warnings
    type:               exitcode-stdio-1.0
    main-is:            Spec.hs
    hs-source-dirs:     test
    other-modules:      AoC.ParsingSpec
                      , AoC.SolverSpec
    build-depends:      base
                      , tutorial-day10
                      , hspec    >= 2.10 && < 2.12
    build-tool-depends: hspec-discover:hspec-discover >= 2.10 && < 2.12
    default-language:   Haskell2010
```

- **`type: exitcode-stdio-1.0`** is the only test-suite type you will care about. It means "a normal executable that prints results and exits with 0 on success, non-zero on failure." That's it.
- **`other-modules`** is the test-suite version of `exposed-modules`: every module in `test/` other than the `main-is` file must be listed here. Forget one and you will get *"could not find module"* at link time.
- **`build-tool-depends`** is for *executables* the build needs (not libraries). `hspec-discover:hspec-discover` says "we need the binary called `hspec-discover` from the package called `hspec-discover`." The colon syntax is `package:executable`. Cabal will fetch and build it, then run it as a preprocessor when it sees the pragma in [test/Spec.hs](test/Spec.hs).

That is the entire `.cabal` file. The shape — header + library + executable + test-suite — is exactly what every project in this repo will use from here on.

### Reading a build-depends line

```cabal
build-depends:    base       >= 4.18 && < 5
--                ^^^^       ^^^^^^^^^^^^^^^
--                package    version range (PVP bounds)
                , containers >= 0.6  && < 0.8
                , tutorial-day10
--                ^^^^^^^^^^^^^^
--                bare name, version inferred from same-package context
```

The `>= X && < Y` shape is the Haskell convention (PVP — *Package Versioning Policy*). The lower bound says "I tested with at least this." The upper bound says "I have not tested anything beyond this; refuse to build if a future release breaks me." `< 5` rather than `< 4.99` because base is `4.18.X.Y` and the next major would be `5.x` — the rule is "next major version that could break me."

---

## 4. Modules — splitting code and importing it back

A **module** is one `.hs` file. The first non-comment line is its header:

```haskell
module AoC.Parsing
  ( parseChange
  , parseInput
  ) where
```

Three things happen here.

1. **The module name `AoC.Parsing` must match the path `src/AoC/Parsing.hs`.** Dotted name → folder hierarchy.
2. **The export list `( parseChange, parseInput )`** declares which top-level names are visible to importers. Anything you define but do not list is private. Omit the export list entirely (`module AoC.Parsing where`) and *everything* is exported — fine for tiny modules, sloppy for big ones.
3. **`where`** introduces the body of the module. Everything after it is the module contents.

### Plain, qualified, and selective imports

In [src/AoC/Solver.hs](src/AoC/Solver.hs):

```haskell
import           Data.List (foldl', scanl')
import qualified Data.Set  as Set
import           Data.Set  (Set)
```

| Form | What it does | Use it for |
|---|---|---|
| `import M` | Bring everything `M` exports into scope under its bare name | Small modules with non-conflicting names (rare) |
| `import M (a, b)` | Bring only `a` and `b` from `M` into scope | What `Data.List` is doing here — only `foldl'` and `scanl'` are pulled in |
| `import qualified M` | Bring everything in, but every reference must be `M.name` | Big modules whose names collide with each other (`Data.Set`, `Data.Map`, `Data.Vector`) |
| `import qualified M as N` | Same, but use `N.name` instead | `import qualified Data.Set as Set` so we can write `Set.insert` |
| `import M (T)` after a qualified import of the same `M` | Bring just the *type name* in unqualified | The third line above — `Set` (the type) is unqualified; everything else is `Set.something` |

The combination on the third line is a Haskell idiom worth memorising: qualify the *operations* (so `Set.member`, `Set.insert` read like method calls) but unqualify the *type* (so signatures stay clean: `Set Int` instead of `Set.Set Int`).

In the test files:

```haskell
import Test.Hspec
import AoC.Parsing (parseChange, parseInput)
```

`Test.Hspec` is brought in unqualified because its DSL (`describe`, `it`, `shouldBe`) is the whole point. Your library's exports are listed selectively because being explicit is cheaper than chasing down where a name came from later.

**Rust analogue**: `import M` ≈ `use M::*` (rare, frowned upon); `import M (a, b)` ≈ `use M::{a, b}`; `import qualified M as N` ≈ `use M as N` followed by always writing `N::thing`. Haskell's "qualified" *forces* the prefix at every call site, which is stricter than Rust's `use ... as`.

---

## 5. The four `cabal` commands you will actually use

Run these from inside `tutorial/day10/`:

| Command | Effect | Run it when |
|---|---|---|
| `cabal build` | Compile the library + executable. Test suite is built only on demand. | After editing source. Catches type errors. |
| `cabal run day10-solve` | Build and execute the executable named `day10-solve`. | When you want to actually run the puzzle. |
| `cabal test` | Build and run the test suite, summarising pass/fail. | After every meaningful change. |
| `cabal repl tutorial-day10` | Start GHCi with the library loaded. | When you want to poke at `parseInput` etc. interactively. |

A few useful but lower-frequency ones:

- `cabal clean` — wipe the build directory (`dist-newstyle/`).
- `cabal build all` — build *everything*, including the test suite.
- `cabal run day10-solve -- arg1 arg2` — pass args to the binary; the `--` separates cabal's flags from the program's.
- `cabal repl day10-test` — start GHCi with the test suite loaded, so you can `import Test.Hspec` and play.

The first time you run `cabal test` here, cabal will fetch and build `hspec` and its dependencies. That is one-time; subsequent test runs are fast.

### Where the artefacts go

cabal puts everything under `dist-newstyle/`. The full path to the test executable looks scary:

```
dist-newstyle/build/x86_64-windows/ghc-9.6.7/tutorial-day10-0.1.0.0/t/day10-test/build/day10-test/day10-test.exe
```

You almost never need to know that. `cabal test` runs it; cabal-managed tooling looks it up by name. The whole tree is in `.gitignore` — never commit `dist-newstyle/`.

---

## 6. `hspec` — `describe`, `it`, `shouldBe`

A test in `hspec` is built from three combinators:

```haskell
spec :: Spec
spec = do
  describe "parseChange" $ do
    it "strips a leading + and reads the rest" $
      parseChange "+7" `shouldBe` 7
```

- **`describe "name" $ do ...`** groups related tests and names the group. Groups can nest.
- **`it "description" $ ...`** is one test case. The description reads like a sentence: *"`parseChange` strips a leading + and reads the rest"*.
- **`shouldBe`** is the assertion. `actual \`shouldBe\` expected` fails the test if they differ, with a readable diff.

A handful of other matchers worth knowing:

| Matcher | Meaning |
|---|---|
| `x \`shouldBe\` y` | `x == y` |
| `x \`shouldNotBe\` y` | `x /= y` |
| `xs \`shouldContain\` ys` | every element of `ys` appears in `xs` |
| `x \`shouldSatisfy\` p` | `p x == True` |
| `action \`shouldThrow\` predicate` | running `action` throws an exception matching the predicate |

You will rarely need more than `shouldBe` for AoC tests; the rest are there when you do.

### The shape of a `Spec` value

`Spec` is a monad — a `do`-block of test declarations. Each `describe` and `it` is one statement in the block. That is why every test file follows the same skeleton:

```haskell
module SomeModuleSpec (spec) where

import Test.Hspec
import SomeModule

spec :: Spec
spec = do
  describe "..." $ do
    it "..." $ ...
    it "..." $ ...
  describe "..." $ do
    ...
```

The export list is `(spec)` because that is the one name `hspec-discover` reaches in.

---

## 7. `hspec-discover` — auto-finding spec files

[test/Spec.hs](test/Spec.hs) is one line of code:

```haskell
{-# OPTIONS_GHC -F -pgmF hspec-discover #-}
```

That pragma is a **per-file compiler option**. `-F` says "preprocess this file"; `-pgmF hspec-discover` names the program to use. At build time cabal runs `hspec-discover` over `test/`; it scans for `*Spec.hs` files, generates a `main` that calls `Test.Hspec.hspec` on the union of every `spec`, and feeds the generated source to GHC in place of `Spec.hs`.

The upshot: **adding a new test module is a three-step ritual** —

1. Create `test/AoC/SomethingSpec.hs` with `module AoC.SomethingSpec (spec) where`.
2. Add `AoC.SomethingSpec` to `other-modules:` in the `.cabal` file.
3. `cabal test`.

No editing of `Spec.hs`, no central registry of tests. The convention "module name ends in `Spec`, exports `spec :: Spec`" is the only thing you have to remember.

---

## 8. Walkthrough of every file

### 8a. `src/AoC/Parsing.hs`

```haskell
module AoC.Parsing
  ( parseChange
  , parseInput
  ) where

parseChange :: String -> Int
parseChange ('+' : rest) = read rest
parseChange s            = read s

parseInput :: String -> [Int]
parseInput = map parseChange . lines
```

Identical logic to Day 9, just packaged as a module. `parseChange` and `parseInput` are exported; nothing else is defined here, so the export list is exhaustive. No imports beyond `Prelude` (`map`, `lines`, `read` are all there by default) — that is why no `import` line appears.

### 8b. `src/AoC/Solver.hs`

```haskell
module AoC.Solver
  ( part1
  , part2
  , firstRepeated
  ) where

import           Data.List (foldl', scanl')
import qualified Data.Set  as Set
import           Data.Set  (Set)
```

Three imports, in the canonical Haskell style:

1. Selective import from `Data.List` — only the strict folds, nothing else.
2. Qualified import of `Data.Set` for the operations.
3. Unqualified import of just the type `Set` from the same module.

The body is the Day 9 solver verbatim. The point of this module is that `firstRepeated`, `part1`, and `part2` can be tested without ever touching `IO` or a file — see [test/AoC/SolverSpec.hs](test/AoC/SolverSpec.hs).

### 8c. `app/Main.hs`

```haskell
module Main where

import AoC.Parsing (parseInput)
import AoC.Solver  (part1, part2)

main :: IO ()
main = do
  contents <- readFile "sample.txt"
  let changes = parseInput contents
  putStrLn ("read "       ++ show (length changes) ++ " changes")
  putStrLn ("part 1 sum = " ++ show (part1 changes))
  putStrLn ("part 2 (first repeated running total) = "
            ++ show (part2 changes))
```

Eight lines, and most of it is `putStrLn`. The IO shell:

- `module Main` — required for any executable's main file.
- Imports the library by module name; *no* path-based imports. Cabal handles the wiring.
- `readFile "sample.txt"` — the path is **relative to the package directory** when run via `cabal run`. That removes the working-directory gotcha from Day 9.
- `let changes = parseInput contents` — pure binding, just like Day 9.
- Three `putStrLn`s for the report.

Run it:

```bash
cabal run day10-solve
```

Output:

```
read 10 changes
part 1 sum = 12
part 2 (first repeated running total) = Nothing
```

`Nothing` for part 2 because the sample is short enough that no running total repeats; the full AoC puzzle cycles the input until one does.

### 8d. `test/Spec.hs`

```haskell
{-# OPTIONS_GHC -F -pgmF hspec-discover #-}
```

That is the entire file — see §7.

### 8e. `test/AoC/ParsingSpec.hs` and `test/AoC/SolverSpec.hs`

Each file:

- has a module name matching its path (`test/AoC/ParsingSpec.hs` → `AoC.ParsingSpec`);
- exports `spec :: Spec`;
- imports `Test.Hspec` for the DSL and the module under test for the functions.

The tests themselves are short. `parseChange` covers the `+`, `-`, and bare-integer cases; `parseInput` covers a normal multi-line string, the empty string (`[]`), and a string without a trailing newline. `part1` is sanity-checked on `[]`, the sample, and a one-element list. `firstRepeated` covers the no-repeat, mid-list-repeat, and `String`-instead-of-`Int` cases. `part2` covers the no-repeat case and the simplest possible "running total revisits 0" case.

That is exactly the level of coverage AoC needs: enough to catch dumb mistakes in the small, not so much that the test suite becomes a project of its own.

---

## 9. Try it

Small exercises. Run them inside `tutorial/day10/`.

1. Run `cabal build`, then `cabal run day10-solve`, then `cabal test`. Confirm you get the same output shown above and 14 passing tests.
2. In `cabal repl tutorial-day10`, evaluate `parseInput "+1\n-2\n"`, `part1 [1,2,3]`, and `firstRepeated [1,2,3,2]`. Then `:t firstRepeated` and read the type out loud.
3. Add a new `it` to `AoC.ParsingSpec`: `parseInput " " \`shouldBe\` [???]`. Decide what answer you expect *before* you run it; then run `cabal test` and see whether `parseChange " "` even succeeds. (Spoiler: `read " "` does not parse.) Either change the test to assert what really happens, or change `parseChange` to handle whitespace — both are valid lessons.
4. Add a third module: `AoC.IO` exposing `readChanges :: FilePath -> IO [Int]`. List it in `exposed-modules:` in the cabal file. Use it from `app/Main.hs` to shrink `main` by one line.
5. Create `test/AoC/IOSpec.hs` (module `AoC.IOSpec`) that uses `shouldThrow` to verify reading a missing file raises an `IOError`. Remember to add `AoC.IOSpec` to `other-modules:`. Run `cabal test`.
6. Open `tutorial-day10.cabal` and *delete* `containers` from `build-depends`. Run `cabal build`. Read the error. Put it back. The error message is the canonical "you forgot to declare a dependency" response — recognise it now and you will save yourself ten minutes later.
7. Run `cabal run day10-solve` from the *repository root* (i.e. `cabal --project-dir tutorial/day10 run day10-solve` or just `cd tutorial/day10` first). Confirm both work; confirm what fails.

---

## 10. What you should remember

- **A cabal project is one folder with one `*.cabal` file.** That file lists the components (library, executable, test suite) and the dependencies. Everything else is convention.
- **`src/`, `app/`, `test/` are conventions, not rules.** They are pointed to by `hs-source-dirs:` in the `.cabal` file. Stick to them.
- **Module names mirror the file path.** `src/AoC/Parsing.hs` ↔ `module AoC.Parsing`. The compiler enforces it.
- **`exposed-modules:` controls public API.** Anything not listed there is private to the library. `other-modules:` is the same idea for the test suite.
- **`build-depends:` carries PVP bounds: `>= X && < Y`.** Lower = "I tested with this." Upper = "I have not tested past this."
- **Stanzas you will see in every cabal file: `library`, `executable`, `test-suite`.** A `common` stanza factors shared options out of them.
- **The four cabal commands you will actually use: `build`, `run`, `test`, `repl`.** Everything else is a nice-to-have.
- **`cabal run <name>` resolves relative paths against the package directory.** That is why `readFile "sample.txt"` works without a `cd`.
- **`hspec` is `describe` + `it` + `shouldBe`.** Each test file exports `spec :: Spec`; `hspec-discover` finds them.
- **`{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`** is the one-line `Spec.hs` driver. Drop new `*Spec.hs` files into `test/`, add them to `other-modules:`, and they run automatically.
- **Imports come in three flavours: open (`import M`), selective (`import M (a, b)`), and qualified (`import qualified M as N`).** The Haskell idiom is qualified-operations + unqualified-type, on consecutive lines.
- **Rust analogue summary**: cabal ↔ cargo; `.cabal` ↔ `Cargo.toml`; `library` / `executable` / `test-suite` ↔ `[lib]` / `[[bin]]` / `[[test]]`; `cabal build|run|test|repl` ↔ `cargo build|run|test`/REPL-via-`evcxr`. The shapes line up almost one-for-one; the field names differ, and Haskell's `qualified` is stricter than Rust's `use as`.

---

**Next**: Day 11 — putting it together. We use this exact project layout to port AoC 2017 Day 1 into Haskell as a side-by-side with the Rust baseline in `reference/`. Day 11 is the first time you parse a real puzzle input, solve Part 1 and Part 2, and have a passing hspec suite around them — the dry-run for AoC 2018 itself.
