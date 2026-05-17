-- | Tests for "Day17" (Reservoir Research).

module Day17Spec (spec) where

import Test.Hspec
import Day17

-- The worked example from the puzzle text.  Reachable tiles (| and
-- ~) within the clay y-window = 57; water at rest (~) = 29.
exampleScan :: String
exampleScan = unlines
  [ "x=495, y=2..7"
  , "y=7, x=495..501"
  , "x=501, y=3..7"
  , "x=498, y=2..4"
  , "x=506, y=1..2"
  , "x=498, y=10..13"
  , "x=504, y=10..13"
  , "y=13, x=498..504"
  ]

spec :: Spec
spec = describe "Day 17" $ do
  describe "parseInput" $
    it "reads the clay y-window of the example as 1..13" $ do
      let p = parseInput exampleScan
      (pMinY p, pMaxY p) `shouldBe` (1, 13)

  describe "simulate (example)" $ do
    it "reaches 57 tiles" $
      fst (simulate (parseInput exampleScan)) `shouldBe` 57
    it "settles 29 tiles" $
      snd (simulate (parseInput exampleScan)) `shouldBe` 29

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day17.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day17.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 26910
actualPart2 = 22182
