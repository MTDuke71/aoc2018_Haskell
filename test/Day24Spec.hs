-- | Tests for "Day24" (Immune System Simulator 20XX).
--
-- The puzzle's worked example (two groups per army) pins both the
-- no-boost outcome (Infection wins with 5216 units) and the boost
-- search (the smallest boost is 1570, after which the Immune System
-- wins with 51 units).  Each group is one line -- the wrapping in the
-- puzzle prose is just typesetting.

module Day24Spec (spec) where

import           Test.Hspec

import           Day24

-- | The example armies from the puzzle statement, one group per line.
exampleInput :: String
exampleInput = unlines
  [ "Immune System:"
  , "17 units each with 5390 hit points (weak to radiation, bludgeoning) with an attack that does 4507 fire damage at initiative 2"
  , "989 units each with 1274 hit points (immune to fire; weak to bludgeoning, slashing) with an attack that does 25 slashing damage at initiative 3"
  , ""
  , "Infection:"
  , "801 units each with 4706 hit points (weak to radiation) with an attack that does 116 bludgeoning damage at initiative 1"
  , "4485 units each with 2961 hit points (immune to radiation; weak to fire, cold) with an attack that does 12 slashing damage at initiative 4"
  ]

spec :: Spec
spec = describe "Day 24" $ do

  describe "parseInput" $ do
    it "reads four groups (two per army)" $
      length (parseInput exampleInput) `shouldBe` 4

    it "parses weaknesses and immunities" $ do
      let immune2 = parseInput exampleInput !! 1   -- second Immune System group
      gWeak   immune2 `shouldBe` ["bludgeoning", "slashing"]
      gImmune immune2 `shouldBe` ["fire"]

    it "computes effective power (units * attack)" $
      effectivePower (head (parseInput exampleInput)) `shouldBe` 17 * 4507

  describe "damageTo" $ do
    let bots   = parseInput exampleInput
        inf1   = bots !! 2                    -- Infection group 1 (bludgeoning)
        imm1   = head bots                    -- weak to bludgeoning
    it "doubles damage against a weakness" $
      damageTo inf1 imm1 `shouldBe` 2 * effectivePower inf1

  describe "part1" $
    it "the Infection wins the example with 5216 units" $
      part1 (parseInput exampleInput) `shouldBe` 5216

  describe "part2" $
    it "boost 1570 leaves the Immune System with 51 units" $
      part2 (parseInput exampleInput) `shouldBe` 51

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day24.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day24.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 15165
actualPart2 = 4037
