# Day 1 — Install + Hello, World!

**Goal**: verify the install, run your first Haskell program three different ways, and read your first type signatures.

**Source file**: [src/Hello.hs](src/Hello.hs)

---

## 1. The install

You already installed GHC via [GHCup](https://www.haskell.org/ghcup/). Verify it:

```bash
ghc --version      # The compiler
ghci --version     # The REPL (interactive shell)
cabal --version    # The build tool + package manager
ghcup --version    # The installer itself
```

If all four print a version, you are ready.

**What each one does**:

| Tool | Role | Rust analogue |
|------|------|---------------|
| `ghc` | Compiler. Turns `.hs` files into executables. | `rustc` |
| `ghci` | REPL. Load code, call functions, inspect types interactively. | (no direct equivalent — closest is `rustc --edition=... -` playground use) |
| `cabal` | Build tool + package manager. Projects, dependencies, test runners. | `cargo` |
| `ghcup` | Installer and version switcher for GHC/cabal. | `rustup` |

You will mostly use `ghci` and `cabal`. `ghc` is usually called *by* `cabal` rather than directly.

---

## 2. The program

Open [src/Hello.hs](src/Hello.hs):

```haskell
module Main where

main :: IO ()
main = do
  putStrLn "Hello, World!"
  putStrLn (greeting "Matt")

greeting :: String -> String
greeting name = "Welcome to Haskell, " ++ name ++ "."
```

Eight lines, and already enough to talk about for the rest of this page.

---

## 3. Three ways to run it

### 3a. `runghc` — quickest, no build artifacts

```bash
cd tutorial/day1
runghc src/Hello.hs
```

Expected output:

```
Hello, World!
Welcome to Haskell, Matt.
```

`runghc` compiles the file to a temporary executable, runs it, and throws the executable away. Good for one-off scripts.

### 3b. `ghc` — compile to a native executable

```bash
cd tutorial/day1
ghc src/Hello.hs -o hello
./hello                 # or: .\hello.exe on Windows cmd/PowerShell; ./hello.exe under bash
```

This produces a real, standalone executable (`hello.exe` on Windows) you can ship. You will also see `.hi` (interface) and `.o` (object) files appear next to `Hello.hs` — those are compiler artifacts, safe to ignore or delete.

### 3c. `ghci` — the REPL

This is the one you will actually live in while learning.

```bash
cd tutorial/day1
ghci src/Hello.hs
```

You get a prompt:

```
ghci> main
Hello, World!
Welcome to Haskell, Matt.
ghci> greeting "Haskell"
"Welcome to Haskell, Haskell."
ghci> :t greeting
greeting :: String -> String
ghci> :t putStrLn
putStrLn :: String -> IO ()
ghci> :q
Leaving GHCi.
```

Three commands you will use constantly:

- `:t expr` — **print the type** of an expression. This is GHCi's single biggest superpower.
- `:r` — **reload** the current file after you edit it. No need to restart.
- `:q` — **quit**.

> **Pro tip**: when you are confused about a Haskell expression, the first thing to try is `:t` on it. The type almost always explains what it does.

---

## 4. Reading a type signature

The line `greeting :: String -> String` is a **type signature**. It is read:

> "`greeting` is a function that takes a `String` and returns a `String`."

The `::` is read "has type." The `->` is "takes … and returns …."

A few more examples, with their plain-English reading:

```haskell
putStrLn :: String       -> IO ()
--          |               |
--          takes a String  returns an I/O action that yields nothing useful

length   :: [a]          -> Int
--          |               |
--          takes a list    returns an Int
--          of anything

(+)      :: Int -> Int   -> Int
--          |     |         |
--          takes takes     returns
--          an    another   their
--          Int   Int       sum
```

A few things worth noticing:

- `[a]` means "a list of elements of some type `a`." The lowercase `a` is a **type variable** — the function works for any element type. (Rust analogue: generics. `[a]` ≈ `&[T]` or `Vec<T>`.)
- `IO ()` means "an action in the `IO` world that returns `()`." The `IO` wrapping is how Haskell marks "this touches the outside world" — printing, reading files, etc. Pure functions do *not* have `IO` in their type.
- Functions with multiple arguments are written `a -> b -> c`. You will learn why (partial application / currying) on Day 2; for now, just read it as "takes an `a`, takes a `b`, returns a `c`."

**Why we write type signatures on every top-level binding**: Haskell can usually infer them, but writing them yourself:

1. documents the function to a reader (including future-you);
2. pins the function's contract so a later change that breaks it is caught immediately;
3. gives you a check against your own mental model before you write the body.

This is the one Haskell habit that pays back the most. We will do it everywhere.

---

## 5. What each piece of the program does

```haskell
module Main where
```

Every `.hs` file is a **module**. A module named `Main` that defines a function named `main` is what `ghc` looks for to build an executable. Other modules have names like `AOC.Day01` and export named functions to be used elsewhere.

**Rust analogue**: roughly `mod`, but one module per file is the norm.

```haskell
main :: IO ()
main = do
  putStrLn "Hello, World!"
  putStrLn (greeting "Matt")
```

- `main :: IO ()` — `main` is an I/O action that returns nothing useful.
- `do` — start a block where we sequence several I/O actions, one per line. You will see `do` blocks a lot; for now read it as "do this, then this."
- `putStrLn :: String -> IO ()` — print a string followed by a newline.
- `putStrLn (greeting "Matt")` — call `greeting` with the argument `"Matt"`, then print the result. The parentheses group the function call, the same as in most languages.

```haskell
greeting :: String -> String
greeting name = "Welcome to Haskell, " ++ name ++ "."
```

- `greeting :: String -> String` — takes a `String`, returns a `String`.
- `greeting name = …` — the parameter is named `name`. Haskell does not use parentheses around parameters on the left side of `=`.
- `"..." ++ name ++ "..."` — `++` is list concatenation. A `String` in Haskell is literally `[Char]` (a list of characters), so `++` concatenates strings the same way it concatenates lists.

**Pure vs. impure**: `greeting` has no `IO` in its type, so it has no side effects. It cannot print, read files, or get the current time. Given `"Matt"` it will always return `"Welcome to Haskell, Matt."`, forever. This separation — effects in the type system — is the biggest single idea in Haskell, and we will come back to it on Day 9.

---

## 6. Try it

Small exercises. Do them in `ghci` with `src/Hello.hs` loaded.

1. Call `greeting` with your own name.
2. Ask GHCi for the types of `main`, `greeting`, `putStrLn`, `++`, and `length` using `:t`. Read each one out loud.
3. Edit `Hello.hs` so the program also prints `greeting "the world"` on a third line. Save, then in GHCi run `:r` and then `main`.
4. In GHCi, evaluate `greeting "A" ++ " And " ++ greeting "B"`. What is the type? What is the value?

If any of these feel weird — especially the `IO ()` part — that is normal. We will see it from several more angles over the next ten days.

---

## 7. What you should remember

- **Run Haskell three ways**: `runghc` for quick scripts, `ghc` to build an executable, `ghci` for interactive exploration.
- **`:t`, `:r`, `:q`** are the three GHCi commands you will use every day.
- **Every top-level binding gets an explicit type signature.** No exceptions in this tutorial.
- **`::` reads "has type"; `->` reads "takes … and returns …."**
- **`IO` in a type means the function touches the outside world.** No `IO` means it is pure — same input, same output, always, no exceptions.

---

**Next**: Day 2 — values, types, and writing your own pure functions.
