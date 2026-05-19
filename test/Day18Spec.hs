-- | Tests for "Day18" (Settlers of the North Pole).

module Day18Spec (spec) where

import Test.Hspec
import Day18

-- The 10x10 worked example from the puzzle text.  After 10 minutes
-- it holds 37 wooded acres and 31 lumberyards, so the resource value
-- is 37 * 31 = 1147.
exampleGrid :: String
exampleGrid = unlines
  [ ".#.#...|#."
  , ".....#|##|"
  , ".|..|...#."
  , "..|#.....#"
  , "#.#|||#|#|"
  , "...#.||..."
  , ".|....|..."
  , "||...#|.#|"
  , "|.||||..|."
  , "...#.|..|."
  ]

-- The state after 1 minute, from the puzzle text -- pins the step
-- rule independently of the 10-minute aggregate.
afterOne :: String
afterOne = unlines
  [ ".......##."
  , "......|###"
  , ".|..|...#."
  , "..|#||...#"
  , "..##||.|#|"
  , "...#||||.."
  , "||...|||.."
  , "|||||.||.|"
  , "||||||||||"
  , "....||..|."
  ]

spec :: Spec
spec = describe "Day 18" $ do
  describe "parseInput" $
    it "reads the example (27 trees, 17 lumberyards)" $
      resourceValue (parseInput exampleGrid) `shouldBe` 27 * 17

  describe "step" $
    it "matches the published state after one minute" $
      step (parseInput exampleGrid) `shouldBe` parseInput afterOne

  describe "part1 (exampleGrid)" $
    it "resource value after 10 minutes is 1147" $
      part1 (parseInput exampleGrid) `shouldBe` 1147

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day18.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day18.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 745008
actualPart2 = 219425
