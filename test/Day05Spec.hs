-- | Tests for Day 05 -- Alchemical Reduction.

module Day05Spec (spec) where

import Test.Hspec
import Day05

spec :: Spec
spec = describe "Day 05 (Alchemical Reduction)" $ do

  describe "reacts" $ do
    it "same letter, opposite case gives True"  $ reacts 'a' 'A' `shouldBe` True
    it "same letter, same case gives False"     $ reacts 'a' 'a' `shouldBe` False
    it "same letter, same case upper gives False" $ reacts 'A' 'A' `shouldBe` False
    it "different letter gives False"           $ reacts 'a' 'B' `shouldBe` False
    it "reaction is symmetric (A,a)"            $ reacts 'A' 'a' `shouldBe` True

  describe "react (unit examples from the puzzle)" $ do
    it "\"aA\"     fully annihilates (0 units)"    $ length (react "aA")     `shouldBe` 0
    it "\"abBA\"   fully annihilates (0 units)"    $ length (react "abBA")   `shouldBe` 0
    it "\"abAB\"   leaves 4 units"                 $ length (react "abAB")   `shouldBe` 4
    it "\"aabAAB\" leaves 6 units"                 $ length (react "aabAAB") `shouldBe` 6

  describe "puzzle example (dabAcCaCBAcCcaDA)" $ do
    it "part1 leaves 10 units" $
      part1 (parseInput "dabAcCaCBAcCcaDA") `shouldBe` 10
    it "part2 shortest is 4 units (removing c/C)" $
      part2 (parseInput "dabAcCaCBAcCcaDA") `shouldBe` 4

  describe "actual puzzle input (inputs/day05.txt)" $ do
    it "part 1 = 11264" $ do
      raw <- readFile "inputs/day05.txt"
      part1 (parseInput raw) `shouldBe` 11264
    it "part 2 = 4552" $ do
      raw <- readFile "inputs/day05.txt"
      part2 (parseInput raw) `shouldBe` 4552
