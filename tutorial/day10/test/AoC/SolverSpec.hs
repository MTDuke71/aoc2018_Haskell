-- | Tests for "AoC.Solver".

module AoC.SolverSpec (spec) where

import Test.Hspec
import AoC.Solver (firstRepeated, part1, part2)

spec :: Spec
spec = do
  describe "part1" $ do
    it "is 0 for an empty list" $
      part1 [] `shouldBe` 0

    it "sums the sample input to 12" $
      -- The sample.txt file used by the executable.
      part1 [1, -2, 3, 1, -5, 8, 4, -3, 7, -2] `shouldBe` 12

    it "handles a single element" $
      part1 [5] `shouldBe` 5

  describe "firstRepeated" $ do
    it "returns Nothing when every element is unique" $
      firstRepeated [1, 2, 3 :: Int] `shouldBe` Nothing

    it "returns the first element that recurs" $
      firstRepeated [1, 2, 3, 2, 1 :: Int] `shouldBe` Just 2

    it "treats Strings the same way" $
      firstRepeated ["a", "b", "a", "c"] `shouldBe` Just "a"

  describe "part2" $ do
    it "is Nothing when running totals never repeat" $
      -- 0, 1, 3, 6 — strictly increasing, no repeat.
      part2 [1, 2, 3] `shouldBe` Nothing

    it "catches the running total that revisits 0" $
      -- Running totals: 0, 1, -1, 0  --> first repeat is 0.
      part2 [1, -2, 1] `shouldBe` Just 0
