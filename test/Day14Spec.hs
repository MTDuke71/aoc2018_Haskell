-- | Tests for Day 14 -- Chocolate Charts.

module Day14Spec (spec) where

import           Data.Word        (Word8)
import           Test.Hspec
import           Day14

spec :: Spec
spec = describe "Day 14 (Chocolate Charts)" $ do

  describe "parseInput" $ do
    it "parses the integer target" $
      target (parseInput "236021\n") `shouldBe` 236021
    it "parses the digit needle" $
      needle (parseInput "236021\n") `shouldBe` ([2, 3, 6, 0, 2, 1] :: [Word8])
    it "tolerates extra whitespace / trailing newline" $
      target (parseInput "  9\n") `shouldBe` 9

  describe "Part 1 worked examples (puzzle statement)" $ do
    it "after 9 recipes -> 5158916779" $
      simulateAfter 9    `shouldBe` "5158916779"
    it "after 5 recipes -> 0124515891" $
      simulateAfter 5    `shouldBe` "0124515891"
    it "after 18 recipes -> 9251071085" $
      simulateAfter 18   `shouldBe` "9251071085"
    it "after 2018 recipes -> 5941429882" $
      simulateAfter 2018 `shouldBe` "5941429882"

  describe "Part 2 worked examples (puzzle statement)" $ do
    it "51589 first appears after 9 recipes" $
      simulateUntil [5,1,5,8,9] `shouldBe` 9
    it "01245 first appears after 5 recipes" $
      simulateUntil [0,1,2,4,5] `shouldBe` 5
    it "92510 first appears after 18 recipes" $
      simulateUntil [9,2,5,1,0] `shouldBe` 18
    it "59414 first appears after 2018 recipes" $
      simulateUntil [5,9,4,1,4] `shouldBe` 2018

  describe "actual puzzle input (inputs/day14.txt)" $ do
    it "Part 1 matches the pinned answer" $ do
      raw <- readFile "inputs/day14.txt"
      part1 (parseInput raw) `shouldBe` expectedPart1
    it "Part 2 matches the pinned answer" $ do
      raw <- readFile "inputs/day14.txt"
      part2 (parseInput raw) `shouldBe` expectedPart2

-- | Pinned regression values.
expectedPart1 :: String
expectedPart1 = "6297310862"

expectedPart2 :: Int
expectedPart2 = 20221334
