-- | Day 8 — 'Data.Set', the workhorse membership container.
--
-- A 'Set a' is a 'Map a ()' with the unit value optimised away: an
-- ordered, immutable collection of unique elements with O(log n)
-- membership tests, insertions, and deletions. Use it any time the
-- question is "have I seen this before?" or "is this in the
-- allow-list?". Lists answer those questions in O(n); sets answer
-- them in O(log n) and remove duplicates for free.

module Main where

import qualified Data.Set as Set
import Data.Set (Set)

-- 'Data.Set' is single-flavoured — there is no separate 'Strict'
-- module like there is for 'Map', because a 'Set' has no values to be
-- lazy about, only keys. Keys are always evaluated when the tree is
-- rebalanced, so strictness is not a knob you need to turn here.

-- --------------------------------------------------------------------
-- 1. Building sets
-- --------------------------------------------------------------------
--
-- Same trio you saw with 'Map': empty, singleton, fromList. 'fromList'
-- silently dedups the input, which is half the reason you reach for
-- it.

emptySet :: Set Int
emptySet = Set.empty

oneItem :: Set Int
oneItem = Set.singleton 7

primes :: Set Int
primes = Set.fromList [2, 3, 5, 7, 11, 13]

-- 'Set.fromList' on input with duplicates is a one-liner dedup that
-- also throws in an ordering for free:
unique :: Ord a => [a] -> [a]
unique = Set.toAscList . Set.fromList
-- 'unique [3, 1, 4, 1, 5, 9, 2, 6, 5, 3]' returns [1,2,3,4,5,6,9].

-- --------------------------------------------------------------------
-- 2. Membership and basic queries
-- --------------------------------------------------------------------

isPrime7 :: Bool
isPrime7 = Set.member 7 primes        -- True

isPrime9 :: Bool
isPrime9 = Set.member 9 primes        -- False

primeCount :: Int
primeCount = Set.size primes          -- 6

-- 'Set.null' tells you "is the set empty?"; do not confuse it with
-- the Prelude 'null' for lists. Qualified imports keep the two
-- distinguishable at the call site.
noPrimes :: Bool
noPrimes = Set.null emptySet          -- True

-- --------------------------------------------------------------------
-- 3. Insert and delete return new sets
-- --------------------------------------------------------------------
--
-- Same immutability rule as 'Map': the original 'primes' is unchanged,
-- and the returned set shares most of its tree structure with it.

withFifteen :: Set Int
withFifteen = Set.insert 15 primes

withoutTwo :: Set Int
withoutTwo = Set.delete 2 primes

-- Inserting an element that is already a member returns the same set
-- — no error, no duplicate. (Internally Haskell may not even allocate
-- a new tree node when nothing changed.)
stillPrimes :: Set Int
stillPrimes = Set.insert 7 primes

-- --------------------------------------------------------------------
-- 4. Set algebra: union, intersection, difference
-- --------------------------------------------------------------------
--
-- These are the three classical set operations. Each returns a new
-- set; none mutates the inputs. Pay O(m + n) in the worst case, often
-- much less when one set is small.

evens :: Set Int
evens = Set.fromList [2, 4, 6, 8, 10, 12]

odds :: Set Int
odds = Set.fromList [1, 3, 5, 7, 9, 11]

allSmall :: Set Int
allSmall = Set.union evens odds       -- 1..12

evenPrimes :: Set Int
evenPrimes = Set.intersection evens primes        -- {2}

oddPrimes :: Set Int
oddPrimes = Set.difference primes evens           -- {3,5,7,11,13}

-- --------------------------------------------------------------------
-- 5. The classic set-membership pattern: 'firstDuplicate'
-- --------------------------------------------------------------------
--
-- Walk a list; the first time you see an element you have already
-- seen, return it. With a list, "have I seen this?" is O(n) and the
-- whole pass becomes O(n^2). With a 'Set' the "seen" test is O(log n)
-- and the pass is O(n log n). This pattern shows up directly in
-- AoC 2018 Day 1 Part 2 (first repeated running frequency) and in
-- many cycle-detection puzzles.

firstDuplicate :: Ord a => [a] -> Maybe a
firstDuplicate = go Set.empty
  where
    go :: Ord a => Set a -> [a] -> Maybe a
    go _    []       = Nothing
    go seen (x : xs)
      | Set.member x seen = Just x
      | otherwise         = go (Set.insert x seen) xs

-- Notice the recursion carries 'seen' as an explicit accumulator —
-- the same shape as a fold, written by hand because we want to /stop/
-- early when we find a duplicate. A right fold could short-circuit
-- here too, but the explicit version is clearer.

dupExample :: Maybe Int
dupExample = firstDuplicate [3, 1, 4, 1, 5, 9, 2, 6]   -- Just 1

noDupExample :: Maybe Int
noDupExample = firstDuplicate [1, 2, 3, 4, 5]           -- Nothing

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("primes                       = " ++ show primes)
  putStrLn ("Set.member 7 primes          = " ++ show isPrime7)
  putStrLn ("Set.member 9 primes          = " ++ show isPrime9)
  putStrLn ("Set.size primes              = " ++ show primeCount)
  putStrLn ("Set.null Set.empty           = " ++ show noPrimes)
  putStrLn ""
  putStrLn ("insert 15 primes             = " ++ show withFifteen)
  putStrLn ("delete 2  primes             = " ++ show withoutTwo)
  putStrLn ("insert 7  primes (no-op)     = " ++ show stillPrimes)
  putStrLn ""
  putStrLn ("union evens odds             = " ++ show allSmall)
  putStrLn ("intersection evens primes    = " ++ show evenPrimes)
  putStrLn ("difference primes evens      = " ++ show oddPrimes)
  putStrLn ""
  putStrLn ("unique [3,1,4,1,5,9,2,6,5,3] = "
           ++ show (unique [3, 1, 4, 1, 5, 9, 2, 6, 5, 3 :: Int]))
  putStrLn ("firstDuplicate [3,1,4,1,..]  = " ++ show dupExample)
  putStrLn ("firstDuplicate [1..5]        = " ++ show noDupExample)
  putStrLn ""
  putStrLn "Day 8 (SetBasics) complete!!!"
