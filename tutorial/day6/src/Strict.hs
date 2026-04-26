-- | Day 6 supplement — why 'foldl'' beats 'foldl'.
--
-- Both functions walk a list left to right and thread an accumulator.
-- The difference is when the accumulator is /evaluated/.
--
-- 'foldl' is lazy: it builds up an unevaluated chain of additions
-- ('thunks') and only collapses them at the end. For long lists this
-- chain blows the stack.
--
-- 'foldl'' (note the apostrophe — it is part of the name) forces the
-- accumulator at every step. The chain never builds up, the run uses
-- constant stack, and the program completes.
--
-- Run this file with: runghc src/Strict.hs
-- The first part proves both folds give the same answer on a small
-- list. The second part feeds them a long list — the strict version
-- finishes (slowly under the interpreter; near-instant when compiled
-- with -O), the lazy version blows the stack.

module Main where

import Data.List (foldl')

-- | Strict left fold sum — the version you want.
sumStrict :: [Int] -> Int
sumStrict = foldl' (+) 0

-- | Lazy left fold sum — the version that explodes on long input.
-- (HLint will suggest 'sum' here — that is the right answer in real
-- code, but the whole demo is to show what raw 'foldl' does, so we
-- suppress the hint just for this binding.)
{-# ANN sumLazy ("HLint: ignore Use sum" :: String) #-}
sumLazy :: [Int] -> Int
sumLazy = foldl (+) 0

-- --------------------------------------------------------------------
-- Two demonstration lists.
-- --------------------------------------------------------------------

-- | A short list, both folds handle this fine.
small :: [Int]
small = [1 .. 10]

-- | A list long enough to exhaust the default stack with lazy 'foldl'
-- under the runghc interpreter on this machine. The exact threshold
-- depends on stack size and GHC version; 30 million is comfortably
-- past it.
big :: [Int]
big = [1 .. 30000000]

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "Both folds agree on a short list:"
  putStrLn ("  sumStrict small = " ++ show (sumStrict small))
  putStrLn ("  sumLazy   small = " ++ show (sumLazy   small))
  putStrLn ""
  putStrLn "Strict fold (foldl') over [1 .. 30,000,000]:"
  putStrLn "  This may take a few seconds under runghc; with 'ghc -O2' it is near-instant."
  putStrLn ("  sumStrict big = " ++ show (sumStrict big))
  putStrLn ""
  putStrLn "Lazy fold (foldl) over [1 .. 30,000,000]:"
  putStrLn "  About to call sumLazy big - expect a stack overflow."
  putStrLn ("  sumLazy big   = " ++ show (sumLazy big))
  putStrLn "(If you ever see this line, the lazy fold somehow did not blow up.)"
