-- | Tests for "Day03" — No Matter How You Slice It. Covers the
-- per-line parser, the worked three-claim example from the puzzle
-- description (4 overlapping squares; non-overlapping claim ID = 3),
-- a focused test for 'squares', and the actual answers pinned against
-- @inputs/day03.txt@.

module Day03Spec (spec) where

import Test.Hspec
import Day03
  ( Claim (..)
  , parseInput
  , parseClaim
  , squares
  , countMap
  , part1
  , part2
  )

import qualified Data.Map.Strict as Map

-- | The three-claim example from the puzzle description.
puzzleExample :: String
puzzleExample = unlines
  [ "#1 @ 1,3: 4x4"
  , "#2 @ 3,1: 4x4"
  , "#3 @ 5,5: 2x2"
  ]

spec :: Spec
spec = describe "Day 03 (No Matter How You Slice It)" $ do

  describe "parseClaim" $ do
    it "parses a line with multi-digit fields" $
      parseClaim "#123 @ 3,2: 5x4"
        `shouldBe` Claim { claimId = 123, left = 3, top = 2, width = 5, height = 4 }

    it "parses the first line of the puzzle example" $
      parseClaim "#1 @ 1,3: 4x4"
        `shouldBe` Claim { claimId = 1, left = 1, top = 3, width = 4, height = 4 }

  describe "parseInput" $
    it "splits the example into three claims" $
      length (parseInput puzzleExample) `shouldBe` 3

  describe "squares" $ do
    it "enumerates every square of a 2x2 claim" $
      squares Claim { claimId = 3, left = 5, top = 5, width = 2, height = 2 }
        `shouldBe` [(5,5),(5,6),(6,5),(6,6)]

    it "is empty for a zero-area claim" $
      squares Claim { claimId = 0, left = 0, top = 0, width = 0, height = 0 }
        `shouldBe` []

  describe "countMap" $
    it "marks the four overlap squares as count 2 in the example" $ do
      let m  = countMap (parseInput puzzleExample)
          xs = [(3,3),(3,4),(4,3),(4,4)]
      map (\sq -> Map.findWithDefault 0 sq m) xs `shouldBe` [2,2,2,2]

  describe "part1 example from the puzzle" $
    it "4 squares are covered by 2+ claims" $
      part1 (parseInput puzzleExample) `shouldBe` 4

  describe "part2 example from the puzzle" $
    it "claim #3 is the non-overlapping one" $
      part2 (parseInput puzzleExample) `shouldBe` 3

  describe "actual puzzle input (inputs/day03.txt)" $ do
    it "part 1 = 111485" $ do
      raw <- readFile "inputs/day03.txt"
      part1 (parseInput raw) `shouldBe` 111485

    it "part 2 = 113" $ do
      raw <- readFile "inputs/day03.txt"
      part2 (parseInput raw) `shouldBe` 113
