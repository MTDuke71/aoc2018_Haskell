-- | Tests for "Day25" (Four-Dimensional Adventure).
--
-- The puzzle gives four worked examples with constellation counts
-- 2, 4, 3, and 8; pinning all four exercises the union-find merging
-- (the first example deliberately includes a chain join and a separate
-- pair).  Day 25 has no Part 2.

module Day25Spec (spec) where

import           Test.Hspec

import           Day25

ex2, ex4, ex3, ex8 :: String
ex2 = unlines
  [ "0,0,0,0", "3,0,0,0", "0,3,0,0", "0,0,3,0"
  , "0,0,0,3", "0,0,0,6", "9,0,0,0", "12,0,0,0"
  ]
ex4 = unlines
  [ "-1,2,2,0", "0,0,2,-2", "0,0,0,-2", "-1,2,0,0", "-2,-2,-2,2"
  , "3,0,2,-1", "-1,3,2,2", "-1,0,-1,0", "0,2,1,-2", "3,0,0,0"
  ]
ex3 = unlines
  [ "1,-1,0,1", "2,0,-1,0", "3,2,-1,0", "0,0,3,1", "0,0,-1,-1"
  , "2,3,-2,0", "-2,2,0,0", "2,-2,0,-1", "1,-1,0,-1", "3,2,0,2"
  ]
ex8 = unlines
  [ "1,-1,-1,-2", "-2,-2,0,1", "0,2,1,3", "-2,3,-2,1", "0,2,3,-2"
  , "-1,-1,1,-2", "0,-2,-1,0", "-2,2,3,-1", "1,2,2,0", "-1,-2,0,-2"
  ]

spec :: Spec
spec = describe "Day 25" $ do

  describe "parseInput" $
    it "reads four-coordinate points (negatives included)" $
      parseInput "8,6,7,-5\n" `shouldBe` [(8, 6, 7, -5)]

  describe "manhattan" $
    it "sums absolute coordinate differences" $
      manhattan (0, 0, 0, 0) (0, 0, 0, 6) `shouldBe` 6

  describe "part1 (worked examples)" $ do
    it "example A has 2 constellations" $
      part1 (parseInput ex2) `shouldBe` 2
    it "example B has 4 constellations" $
      part1 (parseInput ex4) `shouldBe` 4
    it "example C has 3 constellations" $
      part1 (parseInput ex3) `shouldBe` 3
    it "example D has 8 constellations" $
      part1 (parseInput ex8) `shouldBe` 8

  describe "actual input" $
    it "solves Part 1" $ do
      raw <- readFile "inputs/day25.txt"
      part1 (parseInput raw) `shouldBe` actualPart1

-- Filled in from the first clean run on the real input.
actualPart1 :: Int
actualPart1 = 420
