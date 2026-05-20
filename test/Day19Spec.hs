-- | Tests for "Day19" (Go With The Flow).

module Day19Spec (spec) where

import           Data.Array.Unboxed (elems, listArray)
import           Test.Hspec

import           Day19

-- The seven-instruction example from the puzzle text.  Register 0
-- is bound to the instruction pointer; running from all-zero
-- registers should leave the file at @[6,5,6,0,0,9]@.
exampleProg :: String
exampleProg = unlines
  [ "#ip 0"
  , "seti 5 0 1"
  , "seti 6 0 2"
  , "addi 0 1 0"
  , "addr 1 2 3"
  , "setr 1 0 0"
  , "seti 8 0 4"
  , "seti 9 0 5"
  ]

spec :: Spec
spec = describe "Day 19" $ do

  describe "parseInput" $ do
    it "reads the ip directive and instruction count" $ do
      let p = parseInput exampleProg
      ipReg p `shouldBe` 0

  describe "runProgram (example)" $
    it "leaves [6, 5, 6, 0, 0, 9] in the register file" $
      let p    = parseInput exampleProg
          regs = runProgram p (listArray (0, 5) [0, 0, 0, 0, 0, 0])
      in  elems regs `shouldBe` [6, 5, 6, 0, 0, 9]

  describe "part1 (example)" $
    it "register 0 = 6 when the example program halts" $
      part1 (parseInput exampleProg) `shouldBe` 6

  describe "sumOfDivisors" $ do
    it "1 has divisor sum 1" $
      sumOfDivisors 1 `shouldBe` 1
    it "6 (perfect) has divisor sum 12" $
      sumOfDivisors 6 `shouldBe` 12
    it "12 has divisor sum 28" $
      sumOfDivisors 12 `shouldBe` 28
    it "28 (perfect) has divisor sum 56" $
      sumOfDivisors 28 `shouldBe` 56
    it "986 has divisor sum 1620 (= 1+2+17+29+34+58+493+986)" $
      sumOfDivisors 986 `shouldBe` 1620

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day19.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day19.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

-- Filled in from the first clean run on the real input.  Part 1
-- is the sum of divisors of 986 = 1 + 2 + 17 + 29 + 34 + 58 + 493 + 986.
-- Part 2 is the sum of divisors of 10551386 = 2 * p (p prime), so
-- (1+2) * (1+p) = 3 * 5275694 = 15827082.
actualPart1, actualPart2 :: Int
actualPart1 = 1620
actualPart2 = 15827082
