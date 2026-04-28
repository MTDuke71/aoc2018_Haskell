-- | Day 8 — 'Data.Map.Strict', the workhorse keyed container.
--
-- A 'Map k v' is an ordered, immutable dictionary: keys of type 'k'
-- carrying values of type 'v', kept balanced under the hood so that
-- lookup, insert, and delete are O(log n). Compared with the only
-- thing you have so far for keyed data — a list of pairs — every
-- operation is asymptotically faster, and many become one named
-- function instead of three lines of recursion.
--
-- The strict variant ('Data.Map.Strict') forces values to weak head
-- normal form on insert. That single difference is why it is the
-- right default — see 'frequencies' below for a thunk leak that is
-- impossible to hit with the strict module.

module Main where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

-- The qualified import is the convention for 'Data.Map.Strict' (and
-- 'Data.Set'). Reasons:
--   1. Names like 'lookup', 'filter', 'map', 'null' clash with the
--      Prelude. Qualifying them as 'Map.lookup' etc. removes the
--      ambiguity at the call site.
--   2. The reader sees instantly which container a function belongs
--      to. 'Map.insert' and 'Set.insert' read differently — useful.
-- The unqualified 'import Data.Map.Strict (Map)' line above is the
-- standard companion: it brings the type name into scope without the
-- 'Map.' prefix, so you can write 'Map Int String' in signatures.

-- --------------------------------------------------------------------
-- 1. Building maps
-- --------------------------------------------------------------------
--
-- Three common starting points: empty, singleton, and from a list of
-- pairs. 'fromList' is the bulk loader you will reach for nine times
-- out of ten.

emptyMap :: Map String Int
emptyMap = Map.empty

oneEntry :: Map String Int
oneEntry = Map.singleton "alice" 30

ages :: Map String Int
ages = Map.fromList
  [ ("alice", 30)
  , ("bob",   25)
  , ("carol", 41)
  ]

-- 'fromList' ignores duplicate keys — the /last/ pair wins. If you
-- need different conflict resolution (sum, max, append), use
-- 'fromListWith' instead.

agesPickFirst :: Map String Int
agesPickFirst = Map.fromListWith (\_new old -> old)
  [ ("alice", 30)
  , ("alice", 99)   -- ignored: 30 stays
  ]

-- --------------------------------------------------------------------
-- 2. Lookup, membership, size
-- --------------------------------------------------------------------
--
-- 'Map.lookup :: Ord k => k -> Map k v -> Maybe v' returns 'Nothing'
-- when the key is absent. The 'Maybe' is the same one you met on
-- Day 5 — you destructure it with pattern matching or 'fromMaybe'.

aliceAge :: Maybe Int
aliceAge = Map.lookup "alice" ages       -- Just 30

daveAge :: Maybe Int
daveAge = Map.lookup "dave" ages          -- Nothing

hasBob :: Bool
hasBob = Map.member "bob" ages            -- True

ageCount :: Int
ageCount = Map.size ages                  -- 3

-- 'Map.findWithDefault' is the one-shot "lookup, otherwise this":
defaultedAge :: Int
defaultedAge = Map.findWithDefault 0 "dave" ages   -- 0

-- --------------------------------------------------------------------
-- 3. Insert, delete, update
-- --------------------------------------------------------------------
--
-- All these return a /new/ map. The original is unchanged — the same
-- immutability rule you saw with records on Day 7. The new map shares
-- most of its internal structure with the old one, so the cost is
-- O(log n), not a full copy.

withDave :: Map String Int
withDave = Map.insert "dave" 22 ages           -- adds a key

bumpAlice :: Map String Int
bumpAlice = Map.insert "alice" 31 ages         -- overwrites alice

withoutBob :: Map String Int
withoutBob = Map.delete "bob" ages

-- 'adjust' applies a function to the existing value at a key, if the
-- key is present. If the key is absent it is a no-op.
incrementAlice :: Map String Int
incrementAlice = Map.adjust (+1) "alice" ages

-- --------------------------------------------------------------------
-- 4. The workhorse: 'insertWith' for counting and aggregating
-- --------------------------------------------------------------------
--
-- 'insertWith :: Ord k => (v -> v -> v) -> k -> v -> Map k v -> Map k v'
--
-- If the key is absent, behaves like 'insert' with the supplied value.
-- If the key is present, combines the /new/ value (first arg of the
-- function) with the /old/ value (second arg) and stores the result.
--
-- For counting: insert 1 each time, combine with (+) on conflict.

-- | Build a frequency map: how many times does each element appear?
-- This pattern shows up in roughly half of all AoC puzzles, often as
-- the very first step of the solution.
frequencies :: Ord a => [a] -> Map a Int
frequencies = foldl' bump Map.empty
  where
    bump :: Ord a => Map a Int -> a -> Map a Int
    bump m x = Map.insertWith (+) x 1 m

-- Why 'Data.Map.Strict' specifically? Because every call to
-- 'insertWith (+) x 1 m' would otherwise build a thunk like
-- '((1 + 1) + 1) + 1' inside the value slot. With the strict variant,
-- the new value is forced before insertion — no thunk tower, O(1)
-- space per entry. Day 6's lesson on 'foldl'' applies one level up.

letterCounts :: Map Char Int
letterCounts = frequencies "mississippi"
-- => fromList [('i',4),('m',1),('p',2),('s',4)]

-- 'fromListWith' is 'fromList' + 'insertWith' in one call. Same shape,
-- handy when you already have a list of pairs:
totalsByCategory :: Map String Int
totalsByCategory = Map.fromListWith (+)
  [ ("food",   12)
  , ("rent",  800)
  , ("food",   18)
  , ("food",    7)
  ]
-- => fromList [("food",37),("rent",800)]

-- --------------------------------------------------------------------
-- 5. Walking a map: keys, elems, toList, fold
-- --------------------------------------------------------------------
--
-- These all walk in /key order/, ascending. That ordering guarantee is
-- the bonus 'Data.Map' gives you over a 'Data.HashMap' — pay a small
-- constant factor in exchange for predictable iteration.

allKeys :: [String]
allKeys = Map.keys ages              -- ["alice", "bob", "carol"]

allValues :: [Int]
allValues = Map.elems ages           -- [30, 25, 41]

asPairs :: [(String, Int)]
asPairs = Map.toList ages            -- [("alice",30),("bob",25),("carol",41)]

-- 'Map.foldr' / 'Map.foldl'' fold over /values/ in key order. To fold
-- over keys and values together use 'Map.foldrWithKey' /
-- 'Map.foldlWithKey''.

ageSum :: Int
ageSum = Map.foldl' (+) 0 ages       -- 96

-- | Most common element, returning 'Nothing' on the empty list.
-- Reuses 'frequencies' from above and the strict left fold from Day 6.
mostCommon :: Ord a => [a] -> Maybe (a, Int)
mostCommon []  = Nothing
mostCommon xs  =
  case Map.toList (frequencies xs) of
    []     -> Nothing
    (p:ps) -> Just (foldl' best p ps)
  where
    best :: (a, Int) -> (a, Int) -> (a, Int)
    best (k1, c1) (k2, c2)
      | c2 > c1   = (k2, c2)
      | otherwise = (k1, c1)

-- --------------------------------------------------------------------
-- 6. Combining maps: 'union' and 'unionWith'
-- --------------------------------------------------------------------
--
-- 'Map.union' is left-biased: on key conflict the left map's value
-- wins. 'unionWith' lets you say what to do on conflict.

scoresWeek1 :: Map String Int
scoresWeek1 = Map.fromList [("alice", 10), ("bob", 7)]

scoresWeek2 :: Map String Int
scoresWeek2 = Map.fromList [("alice", 5),  ("carol", 9)]

-- Left-biased — alice keeps her week-1 score:
mergedLeftBiased :: Map String Int
mergedLeftBiased = Map.union scoresWeek1 scoresWeek2
-- => fromList [("alice",10),("bob",7),("carol",9)]

-- Sum the two — alice gets 15:
mergedSum :: Map String Int
mergedSum = Map.unionWith (+) scoresWeek1 scoresWeek2
-- => fromList [("alice",15),("bob",7),("carol",9)]

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("ages                    = " ++ show ages)
  putStrLn ("Map.lookup \"alice\"      = " ++ show aliceAge)
  putStrLn ("Map.lookup \"dave\"       = " ++ show daveAge)
  putStrLn ("Map.member \"bob\"        = " ++ show hasBob)
  putStrLn ("Map.size ages           = " ++ show ageCount)
  putStrLn ("findWithDefault 0 dave  = " ++ show defaultedAge)
  putStrLn ""
  putStrLn ("insert dave 22          = " ++ show withDave)
  putStrLn ("insert alice 31         = " ++ show bumpAlice)
  putStrLn ("delete bob              = " ++ show withoutBob)
  putStrLn ("adjust (+1) alice       = " ++ show incrementAlice)
  putStrLn ""
  putStrLn ("frequencies \"mississippi\" = " ++ show letterCounts)
  putStrLn ("totalsByCategory          = " ++ show totalsByCategory)
  putStrLn ""
  putStrLn ("Map.keys ages           = " ++ show allKeys)
  putStrLn ("Map.elems ages          = " ++ show allValues)
  putStrLn ("Map.toList ages         = " ++ show asPairs)
  putStrLn ("Map.foldl' (+) 0 ages   = " ++ show ageSum)
  putStrLn ("mostCommon \"mississippi\" = " ++ show (mostCommon "mississippi"))
  putStrLn ""
  putStrLn ("union week1 week2       = " ++ show mergedLeftBiased)
  putStrLn ("unionWith (+) w1 w2     = " ++ show mergedSum)
  putStrLn ""
  putStrLn "Day 8 (MapBasics) complete!!!"
