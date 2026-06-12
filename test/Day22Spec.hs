-- | Tests for "Day22" (Mode Maze).
--
-- The puzzle prose works through the example cave (depth 510,
-- target 10,10) cell by cell; those worked values pin the
-- knot-tied erosion grid before anything is summed or searched.
-- The pad-independence test guards the one approximation in the
-- solution: Part 2 computes erosion on a finite padded rectangle,
-- and the answer must not change when the pad grows.

module Day22Spec (spec) where

import           Test.Hspec

import           Day22

-- | The example scan from the puzzle prose.
exampleScan :: Puzzle
exampleScan = Puzzle { depth = 510, target = (10, 10) }

spec :: Spec
spec = describe "Day 22" $ do

  describe "parseInput" $
    it "reads depth and target" $
      parseInput "depth: 7740\ntarget: 12,763\n"
        `shouldBe` Puzzle { depth = 7740, target = (12, 763) }

  describe "erosionGrid (worked cells from the prose)" $ do
    let grid = erosionGrid exampleScan (target exampleScan)
    it "(0,0) is rocky" $
      grid `regionAt` (0, 0) `shouldBe` 0
    it "(1,0) is wet" $
      grid `regionAt` (1, 0) `shouldBe` 1
    it "(0,1) is rocky" $
      grid `regionAt` (0, 1) `shouldBe` 0
    it "(1,1) is narrow" $
      grid `regionAt` (1, 1) `shouldBe` 2
    it "(10,10) (the target) is rocky" $
      grid `regionAt` (10, 10) `shouldBe` 0

  describe "part1" $
    it "example risk level is 114" $
      part1 exampleScan `shouldBe` 114

  describe "part2" $ do
    it "example rescue takes 45 minutes" $
      part2 exampleScan `shouldBe` 45
    it "example answer is pad-independent" $
      part2Padded 30 exampleScan `shouldBe` part2Padded 120 exampleScan

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day22.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day22.txt"
      part2 (parseInput raw) `shouldBe` actualPart2
    it "Part 2 is pad-independent on the real cave" $ do
      raw <- readFile "inputs/day22.txt"
      part2Padded 200 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 9899
actualPart2 = 1051
