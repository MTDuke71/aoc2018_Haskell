-- | Tests for "Day02" — Inventory Management System. Covers the
-- parser, the worked Part 1 example from the puzzle (the seven IDs
-- that produce checksum @4 * 3 = 12@), the worked Part 2 example
-- (seven IDs whose unique near-pair shares @"fgij"@), several focused
-- unit tests for the helper predicates, and the actual answers
-- pinned against @inputs/day02.txt@.

module Day02Spec (spec) where

import Test.Hspec
import Day02
  ( parseInput
  , part1
  , part2
  , charCounts
  , differByOne
  , commonLetters
  )

import qualified Data.Map.Strict as Map

-- | The seven-ID Part 1 example, each on its own line. The puzzle
-- says: four contain a doubled letter, three contain a tripled
-- letter, checksum = 12.
puzzleExamplePart1 :: String
puzzleExamplePart1 = unlines
  [ "abcdef"
  , "bababc"
  , "abbcde"
  , "abcccd"
  , "aabcdd"
  , "abcdee"
  , "ababab"
  ]

-- | The seven-ID Part 2 example. The unique near-pair is
-- @fghij@ / @fguij@, sharing @fgij@.
puzzleExamplePart2 :: String
puzzleExamplePart2 = unlines
  [ "abcde"
  , "fghij"
  , "klmno"
  , "pqrst"
  , "fguij"
  , "axcye"
  , "wvxyz"
  ]

spec :: Spec
spec = describe "Day 02 (Inventory Management System)" $ do

  describe "parseInput" $ do
    it "splits the input on newlines" $
      parseInput puzzleExamplePart1
        `shouldBe` ["abcdef","bababc","abbcde","abcccd","aabcdd","abcdee","ababab"]

    it "tolerates an input with no trailing newline" $
      parseInput "abcde\nfghij" `shouldBe` ["abcde", "fghij"]

  describe "charCounts" $ do
    it "counts each letter exactly once" $
      charCounts "bababc" `shouldBe` Map.fromList [('a',2),('b',3),('c',1)]

    it "is empty for an empty string" $
      charCounts "" `shouldBe` Map.empty

  describe "differByOne" $ do
    it "is True for the canonical near-pair" $
      differByOne "fghij" "fguij" `shouldBe` True

    it "is False for two characters of difference" $
      differByOne "abcde" "axcye" `shouldBe` False

    it "is False for identical strings" $
      differByOne "abcde" "abcde" `shouldBe` False

  describe "commonLetters" $ do
    it "drops the one differing position" $
      commonLetters "fghij" "fguij" `shouldBe` "fgij"

    it "returns the whole string for identical inputs" $
      commonLetters "abcde" "abcde" `shouldBe` "abcde"

  describe "part1 example from the puzzle" $
    it "checksum = 4 * 3 = 12" $
      part1 (parseInput puzzleExamplePart1) `shouldBe` 12

  describe "part2 example from the puzzle" $
    it "common letters between fghij and fguij = fgij" $
      part2 (parseInput puzzleExamplePart2) `shouldBe` "fgij"

  describe "actual puzzle input (inputs/day02.txt)" $ do
    it "part 1 = 5880" $ do
      raw <- readFile "inputs/day02.txt"
      part1 (parseInput raw) `shouldBe` 5880

    it "part 2 = tiwcdpbseqhxryfmgkvjujvza" $ do
      raw <- readFile "inputs/day02.txt"
      part2 (parseInput raw) `shouldBe` "tiwcdpbseqhxryfmgkvjujvza"
