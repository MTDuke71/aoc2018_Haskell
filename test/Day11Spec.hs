-- | Tests for Day 11 -- Chronal Charge.

module Day11Spec (spec) where

import           Test.Hspec
import           Day11

spec :: Spec
spec = describe "Day 11 (Chronal Charge)" $ do

  describe "powerLevel" $ do
    it "(3, 5) with serial 8 is 4 (puzzle worked-example)" $
      powerLevel 8 3 5 `shouldBe` 4
    it "(122, 79) with serial 57 is -5" $
      powerLevel 57 122 79 `shouldBe` (-5)
    it "(217, 196) with serial 39 is 0" $
      powerLevel 39 217 196 `shouldBe` 0
    it "(101, 153) with serial 71 is 4" $
      powerLevel 71 101 153 `shouldBe` 4

  describe "buildSat / squareSum" $ do
    it "a single-cell sum equals powerLevel for serial 18" $ do
      let sat = buildSat 18
      squareSum sat 3 5 1 `shouldBe` powerLevel 18 3 5
    it "a single-cell sum equals powerLevel for serial 42" $ do
      let sat = buildSat 42
      squareSum sat 100 100 1 `shouldBe` powerLevel 42 100 100

  describe "bestSquare (Part 1)" $ do
    it "serial 18: best 3x3 is at (33, 45) with power 29" $ do
      let sat = buildSat 18
      let (x, y) = bestSquare sat 3
      (x, y) `shouldBe` (33, 45)
      squareSum sat x y 3 `shouldBe` 29
    it "serial 42: best 3x3 is at (21, 61) with power 30" $ do
      let sat = buildSat 42
      let (x, y) = bestSquare sat 3
      (x, y) `shouldBe` (21, 61)
      squareSum sat x y 3 `shouldBe` 30
    it "part1 returns \"33,45\" for serial 18" $
      part1 (parseInput "18") `shouldBe` "33,45"
    it "part1 returns \"21,61\" for serial 42" $
      part1 (parseInput "42") `shouldBe` "21,61"

  describe "bestAnySize (Part 2)" $ do
    it "serial 18: best any-size square is (90, 269, 16) with power 113" $ do
      let sat = buildSat 18
      let (x, y, s) = bestAnySize sat
      (x, y, s) `shouldBe` (90, 269, 16)
      squareSum sat x y s `shouldBe` 113
    it "serial 42: best any-size square is (232, 251, 12) with power 119" $ do
      let sat = buildSat 42
      let (x, y, s) = bestAnySize sat
      (x, y, s) `shouldBe` (232, 251, 12)
      squareSum sat x y s `shouldBe` 119
    it "part2 returns \"90,269,16\" for serial 18" $
      part2 (parseInput "18") `shouldBe` "90,269,16"
    it "part2 returns \"232,251,12\" for serial 42" $
      part2 (parseInput "42") `shouldBe` "232,251,12"

  describe "actual puzzle input (inputs/day11.txt)" $ do
    it "Part 1 matches the pinned answer" $ do
      raw <- readFile "inputs/day11.txt"
      part1 (parseInput raw) `shouldBe` expectedPart1
    it "Part 2 matches the pinned answer" $ do
      raw <- readFile "inputs/day11.txt"
      part2 (parseInput raw) `shouldBe` expectedPart2

-- | Pinned regression value for Part 1 on the actual input
-- (serial 9435).  The 3x3 square with the largest total power.
expectedPart1 :: String
expectedPart1 = "20,41"

-- | Pinned regression value for Part 2 on the actual input
-- (serial 9435).  An 11x11 square wins -- empirically a common
-- winning size for AoC 2018 Day 11.
expectedPart2 :: String
expectedPart2 = "236,270,11"
