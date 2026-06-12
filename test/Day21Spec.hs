-- | Tests for "Day21" (Chronal Conversion).
--
-- There is no puzzle example this day -- the whole point is
-- reverse-engineering your own input -- so the example-level tests
-- run against a tiny hand-written program plus structural checks
-- on the real input's extracted constants.

module Day21Spec (spec) where

import           Test.Hspec

import           Day21

-- A four-instruction program with the same halt idiom as the real
-- input: put 42 in register 3, then loop on @eqrr 3 0 1@ forever
-- unless r0 == 42.  'runToFirstCheck' must stop at ip 1 and report
-- 42 without ever executing the comparison.
miniProg :: String
miniProg = unlines
  [ "#ip 5"
  , "seti 42 0 3"
  , "eqrr 3 0 1"
  , "addr 1 5 5"
  , "seti 0 0 5"
  ]

spec :: Spec
spec = describe "Day 21" $ do

  describe "checkInfo (mini program)" $
    it "finds the eqrr-vs-r0 at ip 1 probing register 3" $
      checkInfo (parseInput miniProg) `shouldBe` (1, 3)

  describe "runToFirstCheck (mini program)" $
    it "breaks at the check with the probed register = 42" $
      runToFirstCheck (parseInput miniProg) `shouldBe` 42

  describe "actual input" $ do
    it "extracts the hash constants from the program text" $ do
      raw <- readFile "inputs/day21.txt"
      hashSpec (parseInput raw) `shouldBe`
        HashSpec { hashSeed = 1765573
                 , hashMult = 65899
                 , hashMask = 16777215
                 , byteMask = 255
                 , widenBit = 65536
                 }

    it "native hash round 1 agrees with the simulated VM" $ do
      raw <- readFile "inputs/day21.txt"
      let prog = parseInput raw
      nextProbe (hashSpec prog) 0 `shouldBe` runToFirstCheck prog

    it "probe values always fit in the 24-bit mask" $ do
      raw <- readFile "inputs/day21.txt"
      let prog = parseInput raw
      all (<= hashMask (hashSpec prog)) (take 1000 (probes prog))
        `shouldBe` True

    it "solves Part 1" $ do
      raw <- readFile "inputs/day21.txt"
      part1 (parseInput raw) `shouldBe` actualPart1

    it "solves Part 2" $ do
      raw <- readFile "inputs/day21.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input (and
-- cross-checked against python/day21.py, which solves Part 1 with
-- the full VM rather than the lifted hash).
actualPart1, actualPart2 :: Int
actualPart1 = 12213578
actualPart2 = 5310683
