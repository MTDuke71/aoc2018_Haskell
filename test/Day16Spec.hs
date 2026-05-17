-- | Tests for "Day16" (Chronal Classification).

module Day16Spec (spec) where

import           Data.List  (sort)
import           Test.Hspec
import           Day16

-- The single sample worked through in the puzzle text: it behaves
-- like exactly three opcodes -- mulr, addi and seti.
sample :: Sample
sample = Sample [3, 2, 1, 1] [9, 2, 1, 2] [3, 2, 2, 1]

spec :: Spec
spec = describe "Day 16" $ do
  describe "matchingOps" $
    it "the puzzle sample behaves like exactly mulr, addi, seti" $
      sort (matchingOps sample) `shouldBe` sort [Mulr, Addi, Seti]

  describe "parseInput" $
    it "splits samples from the test program" $ do
      raw <- readFile "inputs/day16.txt"
      let Puzzle ss prog = parseInput raw
      not (null ss)   `shouldBe` True
      not (null prog) `shouldBe` True
      -- every parsed instruction is exactly [code, a, b, c]
      all ((== 4) . length . sInstr) ss `shouldBe` True
      all ((== 4) . length) prog        `shouldBe` True

  describe "part1 (samples behaving like >= 3 opcodes)" $
    it "solves the actual input" $ do
      raw <- readFile "inputs/day16.txt"
      part1 (parseInput raw) `shouldBe` actualPart1

  describe "part2 (run the test program)" $
    it "solves the actual input" $ do
      raw <- readFile "inputs/day16.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 640
actualPart2 = 472
