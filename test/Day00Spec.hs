-- | Tests for "Day00" — the AoC 2017 Day 1 \"Inverse Captcha\"
-- warm-up. Covers the four Part-1 and five Part-2 examples from the
-- problem statement, plus the parser and the actual puzzle answers
-- (Part 1 = 1171, Part 2 = 1024).

module Day00Spec (spec) where

import Test.Hspec
import Day00 (parseInput, part1, part2)

spec :: Spec
spec = describe "Day 00 (AoC 2017 Day 1 - Inverse Captcha)" $ do

  describe "parseInput" $ do
    it "turns a digit string into a list of Ints" $
      parseInput "1122" `shouldBe` [1, 1, 2, 2]

    it "ignores a trailing newline" $
      parseInput "91212129\n" `shouldBe` [9, 1, 2, 1, 2, 1, 2, 9]

    it "ignores embedded whitespace" $
      parseInput "  12 34\n" `shouldBe` [1, 2, 3, 4]

  describe "part1 examples from the puzzle" $ do
    it "1122 -> 3" $ part1 (parseInput "1122") `shouldBe` 3
    it "1111 -> 4" $ part1 (parseInput "1111") `shouldBe` 4
    it "1234 -> 0" $ part1 (parseInput "1234") `shouldBe` 0
    it "91212129 -> 9" $ part1 (parseInput "91212129") `shouldBe` 9

  describe "part2 examples from the puzzle" $ do
    it "1212 -> 6" $ part2 (parseInput "1212") `shouldBe` 6
    it "1221 -> 0" $ part2 (parseInput "1221") `shouldBe` 0
    it "123425 -> 4" $ part2 (parseInput "123425") `shouldBe` 4
    it "123123 -> 12" $ part2 (parseInput "123123") `shouldBe` 12
    it "12131415 -> 4" $ part2 (parseInput "12131415") `shouldBe` 4

  describe "actual puzzle input (inputs/day00.txt)" $ do
    it "part 1 = 1171" $ do
      raw <- readFile "inputs/day00.txt"
      part1 (parseInput raw) `shouldBe` 1171

    it "part 2 = 1024" $ do
      raw <- readFile "inputs/day00.txt"
      part2 (parseInput raw) `shouldBe` 1024
