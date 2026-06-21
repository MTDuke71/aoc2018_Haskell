-- | Tests for "Day23" (Experimental Emergency Teleportation).
--
-- Two worked examples from the puzzle prose: the Part 1 swarm whose
-- strongest bot ranges 7 others, and the separate Part 2 swarm whose
-- best teleport point (12,12,12) sees 5 bots and sits 36 from the
-- origin.  Actual-input answers are pinned from the first clean run.

module Day23Spec (spec) where

import           Test.Hspec

import           Day23

-- | The Part 1 example swarm.  The strongest bot is the first one
-- (radius 4 at the origin); 7 bots fall within its range.
part1Example :: String
part1Example = unlines
  [ "pos=<0,0,0>, r=4"
  , "pos=<1,0,0>, r=1"
  , "pos=<4,0,0>, r=3"
  , "pos=<0,2,0>, r=1"
  , "pos=<0,5,0>, r=3"
  , "pos=<0,0,3>, r=1"
  , "pos=<1,1,1>, r=1"
  , "pos=<1,1,2>, r=1"
  , "pos=<1,3,1>, r=1"
  ]

-- | The Part 2 example swarm.  The point (12,12,12) is in range of 5
-- bots -- the most -- and is 36 (Manhattan) from the origin.
part2Example :: String
part2Example = unlines
  [ "pos=<10,12,12>, r=2"
  , "pos=<12,14,12>, r=2"
  , "pos=<16,12,12>, r=4"
  , "pos=<14,14,14>, r=6"
  , "pos=<50,50,50>, r=200"
  , "pos=<10,10,10>, r=5"
  ]

spec :: Spec
spec = describe "Day 23" $ do

  describe "parseInput" $ do
    it "reads positions and radii (negatives included)" $
      parseInput "pos=<-1,2,-3>, r=4\n"
        `shouldBe` [Nanobot (-1, 2, -3) 4]
    it "parses every line of the Part 1 example" $
      length (parseInput part1Example) `shouldBe` 9

  describe "manhattan" $
    it "sums absolute coordinate differences" $
      manhattan (1, 1, 2) (0, 0, 0) `shouldBe` 4

  describe "part1" $
    it "counts 7 bots in range of the strongest" $
      part1 (parseInput part1Example) `shouldBe` 7

  describe "part2" $
    it "finds the best point 36 from the origin" $
      part2 (parseInput part2Example) `shouldBe` 36

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day23.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day23.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 433
actualPart2 = 107272899
