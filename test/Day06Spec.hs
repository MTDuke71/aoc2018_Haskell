-- | Tests for Day 06 -- Chronal Coordinates.

module Day06Spec (spec) where

import Test.Hspec
import Day06

exampleInput :: String
exampleInput = unlines
  [ "1, 1"
  , "1, 6"
  , "8, 3"
  , "3, 4"
  , "5, 5"
  , "8, 9"
  ]

spec :: Spec
spec = describe "Day 06 (Chronal Coordinates)" $ do

  describe "parseInput" $ do
    it "parses six coords from the example" $
      parseInput exampleInput `shouldBe`
        [(1,1), (1,6), (8,3), (3,4), (5,5), (8,9)]

  describe "manhattan" $ do
    it "is zero for equal points"      $ manhattan (3,4) (3,4) `shouldBe` 0
    it "is symmetric"                  $ manhattan (1,1) (4,5) `shouldBe`
                                          manhattan (4,5) (1,1)
    it "(1,1) -> (4,5) = 7"            $ manhattan (1,1) (4,5) `shouldBe` 7
    it "(0,0) -> (-3,4) = 7"           $ manhattan (0,0) (-3,4) `shouldBe` 7

  describe "bounds" $ do
    it "wraps the example coords (1..8, 1..9)" $
      bounds (parseInput exampleInput) `shouldBe` (1, 8, 1, 9)

  describe "closest (example)" $ do
    let cs = parseInput exampleInput
    it "(0,0) -> A (index 0)"                         $ closest cs (0,0) `shouldBe` Just 0
    it "(5,0) -> tie between A and C, no owner"       $ closest cs (5,0) `shouldBe` Nothing
    it "(3,4) -> D (index 3) -- on the coord itself"  $ closest cs (3,4) `shouldBe` Just 3
    it "(5,5) -> E (index 4) -- on the coord itself"  $ closest cs (5,5) `shouldBe` Just 4

  describe "puzzle example" $ do
    it "Part 1 largest finite area = 17 (region around E)" $
      part1 (parseInput exampleInput) `shouldBe` 17
    it "Part 2 with threshold 32 = 16" $
      safeRegionSize 32 (parseInput exampleInput) `shouldBe` 16

  describe "actual puzzle input (inputs/day06.txt)" $ do
    it "part 1 = 4233" $ do
      raw <- readFile "inputs/day06.txt"
      part1 (parseInput raw) `shouldBe` 4233
    it "part 2 = 45290" $ do
      raw <- readFile "inputs/day06.txt"
      part2 (parseInput raw) `shouldBe` 45290
