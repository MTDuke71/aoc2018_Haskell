-- | Day 2 supplement — replacing counters and for-loops with recursion.
--
-- Each example replaces a pattern that in Rust would use a mutable
-- variable or a 'for' loop with a pure recursive Haskell definition.

module Main where

-- | Sum of 1..n. The imperative version uses a mutable accumulator:
--
-- @
-- let mut s = 0;
-- for i in 1..=n { s += i; }
-- return s;
-- @
--
-- The Haskell version describes the answer directly: the sum up to 0
-- is 0, and the sum up to n (for n > 0) is n plus the sum up to n-1.
sumTo :: Int -> Int
sumTo n = if n <= 0 then 0 else n + sumTo (n - 1)

-- | Factorial. Same shape: a base case, then a smaller recursive call.
factorial :: Int -> Int
factorial n = if n <= 1 then 1 else n * factorial (n - 1)

-- | Accumulator pattern: carry the \"running total\" as an extra
-- parameter instead of mutating it. 'i' plays the role of the loop
-- counter, 'acc' plays the role of the mutable sum.
sumToAcc :: Int -> Int -> Int -> Int
sumToAcc n i acc = if i > n then acc else sumToAcc n (i + 1) (acc + i)

-- | Public entry to 'sumToAcc' — start i at 1, acc at 0.
sumToA :: Int -> Int
sumToA n = sumToAcc n 1 0

-- | Counting down and printing each number. Recursion in IO — the
-- Haskell equivalent of:
--
-- @
-- for i in (1..=n).rev() { println!(\"{}\", i); }
-- println!(\"Blast off!\");
-- @
countdown :: Int -> IO ()
countdown n =
  if n <= 0
    then putStrLn "Blast off!"
    else do
      putStrLn (show n)
      countdown (n - 1)

main :: IO ()
main = do
  putStrLn ("sumTo 10     = " ++ show (sumTo 10))
  putStrLn ("factorial 6  = " ++ show (factorial 6))
  putStrLn ("sumToA 10    = " ++ show (sumToA 10))
  putStrLn "countdown 5:"
  countdown 5
