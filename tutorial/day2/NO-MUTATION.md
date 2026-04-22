# No Mutation — How You Replace Counters and For-Loops

**Source file**: [src/Counters.hs](src/Counters.hs)

Day 2 claimed that top-level bindings are immutable: `answer = 42` means `answer` is `42` forever, and there is no `answer = 43` later in the file. So: how do you write a counter, or a `for` loop that accumulates a result?

**Short answer**: you don't mutate. You describe the result in terms of itself at a smaller input. GHC turns that into an efficient loop for you.

There are three patterns, in roughly this order of what-you-reach-for:

1. **Direct recursion** — a function calls itself on a smaller input, with a base case.
2. **Accumulator parameter** — a helper function carries the "running total" as an extra argument.
3. **Higher-order functions** — `map`, `filter`, `sum`, `foldl'` replace almost all hand-written recursion once you have them. These are Days 3 and 6.

Today we can do (1) and (2). The payoff is that once you have them, (3) is just shorter syntax for the same idea.

---

## Before we start: reading a name is not mutation

Look at Day 2's `cube`:

```haskell
cube :: Int -> Int
cube x = x * square x
```

Reading this and thinking *"isn't `square x` changing `x`?"* is a reasonable reaction coming from an imperative language. It is not. Walk through `cube 3`:

1. `cube` is called with `3`. The name `x` is bound to `3` for this one call.
2. `x * square x` is evaluated. Both `x` references are the same binding — both are `3`.
3. `square x` means *"apply `square` to the value of `x`."* That is a separate function call. Inside `square`, its own parameter (confusingly also named `x`, but a different binding in a different scope) is `3`; the body `x * x` evaluates to `9`; `square` **returns** `9` as a new value. It does not write back to `cube`'s `x`.
4. Back in `cube`, the expression is now `3 * 9`. That evaluates to `27`. `cube 3` returns `27`.

`x` was read twice and passed as an argument once. It was never changed, because there is no way to change it. In Haskell, **`=` is definition, not assignment** — `cube x = x * square x` is one permanent equation that defines what `cube x` means, not a sequence of statements that runs top to bottom.

The same mental model applies to `square`'s body `x * x`: the two `x`s are the same binding, read twice. Nothing is mutated.

**Rust analogue**: `fn cube(x: i64) -> i64 { x * square(x) }`. `x` is read twice and never written. Haskell is the same — it just enforces the "never written" part at the language level so you cannot accidentally break it.

---

## 1. Direct recursion

The imperative `for i in 1..=n { s += i; }` becomes:

```haskell
sumTo :: Int -> Int
sumTo n = if n <= 0 then 0 else n + sumTo (n - 1)
```

Read it out loud: *"the sum up to 0 is 0; the sum up to `n` is `n` plus the sum up to `n-1`."* There is no counter variable — the recursive call is the counter.

`if … then … else …` is an ordinary expression in Haskell, not a statement. Both branches must have the same type, and the whole `if` has that type. (Day 4 will replace `if` chains with pattern matching and guards; for now, `if` is fine.)

Same shape, factorial:

```haskell
factorial :: Int -> Int
factorial n = if n <= 1 then 1 else n * factorial (n - 1)
```

**Rust analogue**: this is what `fn sum_to(n: i64) -> i64 { if n <= 0 { 0 } else { n + sum_to(n - 1) } }` looks like. Rust can write it; Haskell *prefers* it.

---

## 2. Accumulator parameter

Sometimes the shape you need is closer to a real loop — a counter that walks up, a running total that builds. You express it with a helper that carries the state as parameters. Nothing mutates; each recursive call gets new values.

```haskell
sumToAcc :: Int -> Int -> Int -> Int
sumToAcc n i acc = if i > n then acc else sumToAcc n (i + 1) (acc + i)

sumToA :: Int -> Int
sumToA n = sumToAcc n 1 0
```

Read the helper line by line:

- `i` is the loop counter. It starts at `1` and goes up by `1` each call.
- `acc` is the "mutable sum." It starts at `0` and gains `i` each call.
- The base case `i > n` says *stop and return the accumulator*.

Compare to the Rust equivalent:

```rust
fn sum_to_a(n: i64) -> i64 {
    let mut i = 1;
    let mut acc = 0;
    while i <= n {
        acc += i;
        i += 1;
    }
    acc
}
```

Same shape. Haskell just makes the state explicit as parameters instead of hiding it in mutable variables. Every Haskell programmer writes this pattern at least once — on Day 4 you will learn `where` clauses, which let you hide the helper inside `sumToA` so it is not visible at the top level. For today, a top-level helper is fine and honest.

**Note on performance**: GHC is aggressive about turning tail-recursive accumulator functions into tight loops. `sumToAcc` above compiles down to the same machine code as the `while` loop. You are not paying for the "recursion."

---

## 3. Looping with side effects (IO)

If the body of your "loop" prints things or reads things — i.e. it is in `IO` — you still recurse. `countdown` in the source file is the closest thing to a classic `for` loop you will see today:

```haskell
countdown :: Int -> IO ()
countdown n =
  if n <= 0
    then putStrLn "Blast off!"
    else do
      putStrLn (show n)
      countdown (n - 1)
```

The `do` block sequences two actions: print the current `n`, then recurse with `n - 1`. The recursive call *is* the "next iteration."

Run it:

```
ghci> countdown 5
5
4
3
2
1
Blast off!
```

On Day 9 you will meet `mapM_`, which lets you write the same thing as `mapM_ (putStrLn . show) [5, 4 .. 1]` — one line, no recursion. That is the higher-order-function version.

---

## 4. Previewing Day 3 and Day 6

Once you have lists and folds, most of these explicit recursions disappear:

```haskell
-- Day 3: list range + sum from the Prelude
sumTo :: Int -> Int
sumTo n = sum [1 .. n]

-- Day 6: the same with foldl'
sumTo :: Int -> Int
sumTo n = foldl' (+) 0 [1 .. n]
```

These are the same function. The recursion has not vanished — `sum` and `foldl'` *are* recursive definitions, written once in the standard library and reused forever. You will spend Day 3 getting fluent with lists and Day 6 understanding what `foldl'` actually does.

The point for today is: the recursion-plus-accumulator pattern is what every list function is built out of. Learn it now and the higher-order versions will feel like shorthand, not magic.

---

## 5. "But I really do need mutation"

You will not need it for AoC 2018. You will especially not need it in the first ten days. But for the record:

- **`IORef`** (from `Data.IORef`) gives you a real mutable reference that lives in `IO`. Looks like `newIORef`, `readIORef`, `writeIORef`, `modifyIORef'`. It is the Haskell spelling of a `RefCell<T>` or `Mutex<T>`.
- **The `State` monad** (from `Control.Monad.State`) lets you thread a value through a pure computation as if it were mutable, without any real mutation. It is what you reach for before `IORef`.
- **Mutable arrays** (`Data.Array.ST`, `Data.Vector.Mutable`) exist for algorithms where you genuinely need O(1) mutable writes — e.g. a union-find. These run inside the `ST` monad, which gives you controlled mutation that is invisible from the outside.

All three are advanced. For every AoC puzzle in 2018, the answer is either a recursion, a fold, or a `Map.Map`. You will not touch `IORef` this month, and that is the right call.

---

## What you should remember

- **`=` is definition, not assignment.** Reading a name twice in an expression (like `x * square x`) is not mutation — there is no statement that runs, just an equation that gets reduced.
- **Recursion replaces `for` loops.** Describe the result in terms of a smaller input, plus a base case.
- **An accumulator parameter replaces a mutable counter.** Each recursive call takes new values.
- **`if … then … else …` is an expression**, not a statement. Both branches must have the same type.
- **Tail-recursive accumulators compile to loops.** You are not paying for the recursion at runtime.
- **Higher-order functions (`map`, `sum`, `foldl'`) replace almost all hand-written recursion** once you meet them on Days 3 and 6.
- **Real mutation exists (`IORef`, `ST`, `State`) but you will not need it** for AoC 2018.
