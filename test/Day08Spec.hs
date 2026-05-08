-- | Tests for Day 08 -- Memory Maneuver.

module Day08Spec (spec) where

import           Test.Hspec
import           Day08

-- The example tree from the puzzle description: a root A with two
-- children B and C, where C has one child D.
exampleInput :: String
exampleInput = "2 3 0 3 10 11 12 1 1 0 1 99 2 1 1 2"

spec :: Spec
spec = describe "Day 08 (Memory Maneuver)" $ do

  describe "parseTree" $ do
    let toks = map read (words exampleInput) :: [Int]
        (tree, leftover) = parseTree toks

    it "consumes the entire example token stream" $
      leftover `shouldBe` []

    it "root has 2 children and 3 metadata entries" $ do
      length (children tree) `shouldBe` 2
      metadata tree          `shouldBe` [1, 1, 2]

    it "first child (B) is a leaf with metadata [10, 11, 12]" $ do
      let b = head (children tree)
      children b `shouldBe` []
      metadata b `shouldBe` [10, 11, 12]

    it "second child (C) has one child (D) and metadata [2]" $ do
      let c = children tree !! 1
          d = head (children c)
      length (children c) `shouldBe` 1
      metadata c          `shouldBe` [2]
      children d          `shouldBe` []
      metadata d          `shouldBe` [99]

  describe "puzzle example" $ do
    it "Part 1 metadata sum is 138" $
      part1 (parseInput exampleInput) `shouldBe` 138
    it "Part 2 root value is 66" $
      part2 (parseInput exampleInput) `shouldBe` 66

  describe "nodeValue cases from the puzzle text" $ do
    let tree = parseInput exampleInput
        b    = head (children tree)
        c    = children tree !! 1
        d    = head (children c)
    it "B is a leaf, value 33"             $ nodeValue b    `shouldBe` 33
    it "D is a leaf, value 99"             $ nodeValue d    `shouldBe` 99
    it "C has only one child, value 0"     $ nodeValue c    `shouldBe` 0
    it "A is the root, value 66"           $ nodeValue tree `shouldBe` 66

  describe "actual puzzle input (inputs/day08.txt)" $ do
    it "Part 1 metadata sum matches expected" $ do
      raw <- readFile "inputs/day08.txt"
      part1 (parseInput raw) `shouldBe` expectedPart1Answer
    it "Part 2 root value matches expected" $ do
      raw <- readFile "inputs/day08.txt"
      part2 (parseInput raw) `shouldBe` expectedPart2Answer

-- | Pinned regression values for the actual puzzle input.
expectedPart1Answer, expectedPart2Answer :: Int
expectedPart1Answer = 41521
expectedPart2Answer = 19990
