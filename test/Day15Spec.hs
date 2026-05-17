-- | Tests for "Day15" (Beverage Bandits).
--
-- The puzzle ships an unusually rich set of worked examples: one
-- fully narrated 27730 battle plus five "summarized" combats for
-- Part 1, and four attack-power searches for Part 2.  All of them are
-- pinned here -- this day's tie-breaking rules are subtle enough that
-- a single example is not enough confidence.

module Day15Spec (spec) where

import Test.Hspec
import Day15

-- The fully narrated example (outcome 27730).
ex0 :: String
ex0 = unlines
  [ "#######"
  , "#.G...#"
  , "#...EG#"
  , "#.#.#G#"
  , "#..G#E#"
  , "#.....#"
  , "#######"
  ]

-- The five "summarized combats" from the puzzle text.
exA, exB, exC, exD, exE :: String
exA = unlines
  [ "#######", "#G..#E#", "#E#E.E#", "#G.##.#", "#...#E#", "#...E.#", "#######" ]
exB = unlines
  [ "#######", "#E..EG#", "#.#G.E#", "#E.##E#", "#G..#.#", "#..E#.#", "#######" ]
exC = unlines
  [ "#######", "#E.G#.#", "#.#G..#", "#G.#.G#", "#G..#.#", "#...E.#", "#######" ]
exD = unlines
  [ "#######", "#.E...#", "#.#..G#", "#.###.#", "#E#G#G#", "#...#G#", "#######" ]
exE = unlines
  [ "#########"
  , "#G......#"
  , "#.E.#...#"
  , "#..##..G#"
  , "#...##..#"
  , "#...#...#"
  , "#.G...G.#"
  , "#.....G.#"
  , "#########"
  ]

p1 :: String -> Int
p1 = part1 . parseInput

p2 :: String -> Int
p2 = part2 . parseInput

spec :: Spec
spec = describe "Day 15" $ do
  describe "parseInput" $
    it "reads the units of the narrated example in reading order" $ do
      let Puzzle _ us = parseInput ex0
      map ukind us `shouldBe` [Goblin, Elf, Goblin, Goblin, Goblin, Elf]

  describe "part1 (attack power 3 both sides)" $ do
    it "narrated example -> 27730" $ p1 ex0 `shouldBe` 27730
    it "summarized A -> 36334"     $ p1 exA `shouldBe` 36334
    it "summarized B -> 39514"     $ p1 exB `shouldBe` 39514
    it "summarized C -> 27755"     $ p1 exC `shouldBe` 27755
    it "summarized D -> 28944"     $ p1 exD `shouldBe` 28944
    it "summarized E -> 18740"     $ p1 exE `shouldBe` 18740

  describe "part2 (lowest Elf attack power, no Elf dies)" $ do
    it "narrated example -> 4988"  $ p2 ex0 `shouldBe` 4988
    it "summarized B -> 31284"     $ p2 exB `shouldBe` 31284
    it "summarized C -> 3478"      $ p2 exC `shouldBe` 3478
    it "summarized D -> 6474"      $ p2 exD `shouldBe` 6474
    it "summarized E -> 1140"      $ p2 exE `shouldBe` 1140

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day15.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day15.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 248235
actualPart2 = 46784
