-- | Day 6 — Folds: 'foldr', 'foldl', and 'foldl''.
--
-- A fold reduces a list to a single value by combining the elements
-- with a function and an initial accumulator. Almost every "walk a
-- list and accumulate something" function in the Prelude is a fold
-- in disguise — once you see the pattern, you stop hand-rolling
-- recursion for the easy cases.

module Main where

import Data.List (foldl')

-- --------------------------------------------------------------------
-- 1. The hand-rolled version, so the fold is not a black box
-- --------------------------------------------------------------------

-- | Sum a list with explicit recursion, the way you wrote it before
-- you knew about folds. Compare its shape to 'foldr' below.
sumExplicit :: [Int] -> Int
sumExplicit []     = 0
sumExplicit (x:xs) = x + sumExplicit xs

-- | Length, same shape: a base case for the empty list and a step
-- that combines the head with the recursive call on the tail.
lengthExplicit :: [a] -> Int
lengthExplicit []     = 0
lengthExplicit (_:xs) = 1 + lengthExplicit xs

-- --------------------------------------------------------------------
-- 2. 'foldr' — fold from the right
-- --------------------------------------------------------------------
--
-- foldr :: (a -> b -> b) -> b -> [a] -> b
-- foldr _ z []     = z
-- foldr f z (x:xs) = f x (foldr f z xs)
--
-- Read 'foldr (+) 0 [1, 2, 3]' as: replace every (:) with (+) and
-- every [] with 0. So [1, 2, 3] = 1 : 2 : 3 : [] becomes
-- 1 + 2 + 3 + 0 = 6.

-- | Sum, written as a right fold. Identical answer to 'sumExplicit',
-- one line instead of two.
sumR :: [Int] -> Int
sumR = foldr (+) 0

-- | Length as a right fold. The combining function ignores the
-- element (we only care that there /is/ one) and adds 1.
lengthR :: [a] -> Int
lengthR = foldr (\_ acc -> 1 + acc) 0

-- | 'foldr' is the right fold for building a list result, because
-- list construction is lazy and the result can be consumed before
-- the whole input is walked. 'mapR' is exactly the Prelude 'map'.
mapR :: (a -> b) -> [a] -> [b]
mapR f = foldr (\x acc -> f x : acc) []

-- | 'filterR' is exactly the Prelude 'filter'. The combining function
-- decides whether to keep the head; the lazy cons keeps the result
-- streamy.
filterR :: (a -> Bool) -> [a] -> [a]
filterR p = foldr (\x acc -> if p x then x : acc else acc) []

-- --------------------------------------------------------------------
-- 3. 'foldl'' — strict fold from the left, the one you actually use
-- --------------------------------------------------------------------
--
-- foldl' :: (b -> a -> b) -> b -> [a] -> b
-- foldl' _ z []     = z
-- foldl' f z (x:xs) = let z' = f z x in z' `seq` foldl' f z' xs
--
-- 'foldl'' walks the list left to right, threading an accumulator,
-- and forces the accumulator at every step. For numeric reductions
-- on long lists this is what you want — see Strict.hs for why the
-- non-strict 'foldl' is almost always the wrong choice.

-- | Sum as a strict left fold. Same answer as 'sumR', but it runs in
-- constant stack space — important when the list is long.
sumL :: [Int] -> Int
sumL = foldl' (+) 0

-- | Product as a strict left fold. Note the initial value: 1, the
-- identity for multiplication. Picking the right identity is the
-- only thing you have to think about.
productL :: [Int] -> Int
productL = foldl' (*) 1

-- | Maximum of a non-empty list. We seed the accumulator with the
-- first element and fold over the rest. 'max' is in the Prelude.
maximumL :: [Int] -> Int
maximumL []     = error "maximumL: empty list"
maximumL (x:xs) = foldl' max x xs

-- | Reverse, written as a strict left fold. Build the result by
-- consing each element onto the front of the accumulator — the
-- accumulator ends up holding the reversed prefix.
reverseL :: [a] -> [a]
reverseL = foldl' (\acc x -> x : acc) []

-- | Count the elements that satisfy a predicate. Classic AoC shape:
-- "how many entries pass this test?"
countL :: (a -> Bool) -> [a] -> Int
countL p = foldl' (\acc x -> if p x then acc + 1 else acc) 0

-- --------------------------------------------------------------------
-- 4. A small AoC-flavoured example
-- --------------------------------------------------------------------

-- | Running totals: turn [1, 2, 3, 4] into [1, 3, 6, 10]. This is
-- 'scanl1 (+)' in the Prelude, but we hand-roll it with 'foldl'' and
-- a tuple accumulator '(running_total, accumulated_list)' so you can
-- see how the pattern generalises beyond a single number.
runningSums :: [Int] -> [Int]
runningSums xs = reverseL (snd (foldl' step (0, []) xs))
  where
    step :: (Int, [Int]) -> Int -> (Int, [Int])
    step (total, acc) x =
      let total' = total + x
       in (total', total' : acc)

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("sumExplicit    [1..5]  = " ++ show (sumExplicit [1 .. 5]))
  putStrLn ("lengthExplicit [1..5]  = " ++ show (lengthExplicit [1 .. 5 :: Int]))
  putStrLn ""
  putStrLn ("sumR           [1..5]  = " ++ show (sumR [1 .. 5]))
  putStrLn ("lengthR        [1..5]  = " ++ show (lengthR [1 .. 5 :: Int]))
  putStrLn ("mapR (*2)      [1..5]  = " ++ show (mapR (* 2) [1 .. 5 :: Int]))
  putStrLn ("filterR even   [1..10] = " ++ show (filterR even [1 .. 10 :: Int]))
  putStrLn ""
  putStrLn ("sumL           [1..5]  = " ++ show (sumL [1 .. 5]))
  putStrLn ("productL       [1..5]  = " ++ show (productL [1 .. 5]))
  putStrLn ("maximumL       [3,1,4,1,5,9,2,6] = "
           ++ show (maximumL [3, 1, 4, 1, 5, 9, 2, 6]))
  putStrLn ("reverseL       [1..5]  = " ++ show (reverseL [1 .. 5 :: Int]))
  putStrLn ("countL even    [1..10] = " ++ show (countL even [1 .. 10 :: Int]))
  putStrLn ""
  putStrLn ("runningSums    [1..5]  = " ++ show (runningSums [1 .. 5]))
  putStrLn "Day 6 (Folds) complete!!!"
