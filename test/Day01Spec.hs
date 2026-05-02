-- | Tests for "Day01" — Chronal Calibration. Covers the parser, the
-- four Part 1 examples and the four Part 2 examples from the problem
-- statement, plus the actual puzzle answers loaded from
-- @inputs/day01.txt@. The actual answers are pinned here so that any
-- future refactor of "Day01" cannot silently change the result.

module Day01Spec (spec) where

import Test.Hspec
import Day01 (parseInput, part1, part2)

-- | The running example from the problem statement: @+1, -2, +3, +1@
-- with a trailing newline, exactly the shape 'parseInput' will see in
-- production.
puzzleExample :: String
puzzleExample = unlines ["+1", "-2", "+3", "+1"]

spec :: Spec
spec = describe "Day 01 (Chronal Calibration)" $ do

  describe "parseInput" $ do
    it "reads signed deltas, dropping the optional leading +" $
      parseInput puzzleExample `shouldBe` [1, -2, 3, 1]

    it "tolerates an input with no trailing newline" $
      parseInput "+5\n-3" `shouldBe` [5, -3]

  describe "part1 examples from the puzzle" $ do
    it "+1, -2, +3, +1 -> 3" $
      part1 (parseInput (unlines ["+1", "-2", "+3", "+1"])) `shouldBe` 3

    it "+1, +1, +1 -> 3" $
      part1 (parseInput (unlines ["+1", "+1", "+1"])) `shouldBe` 3

    it "+1, +1, -2 -> 0" $
      part1 (parseInput (unlines ["+1", "+1", "-2"])) `shouldBe` 0

    it "-1, -2, -3 -> -6" $
      part1 (parseInput (unlines ["-1", "-2", "-3"])) `shouldBe` (-6)

  describe "part2 examples from the puzzle" $ do
    it "+1, -2, +3, +1 first reaches 2 twice" $
      part2 (parseInput (unlines ["+1", "-2", "+3", "+1"])) `shouldBe` 2

    it "+1, -1 first reaches 0 twice" $
      part2 (parseInput (unlines ["+1", "-1"])) `shouldBe` 0

    it "+3, +3, +4, -2, -4 first reaches 10 twice" $
      part2 (parseInput (unlines ["+3", "+3", "+4", "-2", "-4"])) `shouldBe` 10

    it "-6, +3, +8, +5, -6 first reaches 5 twice" $
      part2 (parseInput (unlines ["-6", "+3", "+8", "+5", "-6"])) `shouldBe` 5

    it "+7, +7, -2, -7, -4 first reaches 14 twice" $
      part2 (parseInput (unlines ["+7", "+7", "-2", "-7", "-4"])) `shouldBe` 14

  describe "actual puzzle input (inputs/day01.txt)" $ do
    it "part 1 = 576" $ do
      raw <- readFile "inputs/day01.txt"
      part1 (parseInput raw) `shouldBe` 576

    it "part 2 = 77674" $ do
      raw <- readFile "inputs/day01.txt"
      part2 (parseInput raw) `shouldBe` 77674
