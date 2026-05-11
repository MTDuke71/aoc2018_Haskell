-- | Tests for Day 09 -- Marble Mania.

module Day09Spec (spec) where

import           Test.Hspec
import           Day09

spec :: Spec
spec = describe "Day 09 (Marble Mania)" $ do

  describe "parseInput" $ do
    it "parses '464 players; last marble is worth 71730 points'" $
      parseInput "464 players; last marble is worth 71730 points"
        `shouldBe` Game 464 71730

  describe "play -- the six examples in the puzzle text" $ do
    -- The puzzle text walks through a 9-player, 25-marble game and
    -- shows the winner's score is 32; the rest are stated outright.
    it "9 players, last marble 25  -> 32"     $ play 9  25   `shouldBe` 32
    it "10 players, last marble 1618  -> 8317"  $ play 10 1618 `shouldBe` 8317
    it "13 players, last marble 7999  -> 146373" $ play 13 7999 `shouldBe` 146373
    it "17 players, last marble 1104  -> 2764"   $ play 17 1104 `shouldBe` 2764
    it "21 players, last marble 6111  -> 54718"  $ play 21 6111 `shouldBe` 54718
    it "30 players, last marble 5807  -> 37305"  $ play 30 5807 `shouldBe` 37305

  describe "actual puzzle input (inputs/day09.txt)" $ do
    it "Part 1 matches the pinned answer" $ do
      raw <- readFile "inputs/day09.txt"
      part1 (parseInput raw) `shouldBe` expectedPart1Answer
    it "Part 2 matches the pinned answer" $ do
      raw <- readFile "inputs/day09.txt"
      part2 (parseInput raw) `shouldBe` expectedPart2Answer

-- | Pinned regression values for the actual puzzle input.
expectedPart1Answer, expectedPart2Answer :: Int
expectedPart1Answer = 380705
expectedPart2Answer = 3171801582
