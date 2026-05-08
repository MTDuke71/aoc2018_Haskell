-- | Tests for Day 07 -- The Sum of Its Parts.

module Day07Spec (spec) where

import           Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import           Day07

exampleInput :: String
exampleInput = unlines
  [ "Step C must be finished before step A can begin."
  , "Step C must be finished before step F can begin."
  , "Step A must be finished before step B can begin."
  , "Step A must be finished before step D can begin."
  , "Step B must be finished before step E can begin."
  , "Step D must be finished before step E can begin."
  , "Step F must be finished before step E can begin."
  ]

spec :: Spec
spec = describe "Day 07 (The Sum of Its Parts)" $ do

  describe "parseInput" $ do
    it "parses seven edges from the example" $
      parseInput exampleInput `shouldBe`
        [('C','A'), ('C','F'), ('A','B'), ('A','D'),
         ('B','E'), ('D','E'), ('F','E')]

  describe "prereqs (example)" $ do
    let pre = prereqs (parseInput exampleInput)
    it "covers exactly the six step letters A..F" $
      Map.keys pre `shouldBe` "ABCDEF"
    it "C has no prereqs"            $ Map.lookup 'C' pre `shouldBe` Just Set.empty
    it "A has prereq {C}"            $ Map.lookup 'A' pre `shouldBe` Just (Set.fromList "C")
    it "F has prereq {C}"            $ Map.lookup 'F' pre `shouldBe` Just (Set.fromList "C")
    it "B has prereq {A}"            $ Map.lookup 'B' pre `shouldBe` Just (Set.fromList "A")
    it "D has prereq {A}"            $ Map.lookup 'D' pre `shouldBe` Just (Set.fromList "A")
    it "E has prereqs {B, D, F}"     $ Map.lookup 'E' pre `shouldBe` Just (Set.fromList "BDF")

  describe "stepDuration" $ do
    it "A with base 60 takes 61 s"   $ stepDuration 60 'A' `shouldBe` 61
    it "Z with base 60 takes 86 s"   $ stepDuration 60 'Z' `shouldBe` 86
    it "A with base 0 takes 1 s"     $ stepDuration 0  'A' `shouldBe` 1
    it "F with base 0 takes 6 s"     $ stepDuration 0  'F' `shouldBe` 6

  describe "puzzle example" $ do
    it "Part 1 order is CABDFE" $
      part1 (parseInput exampleInput) `shouldBe` "CABDFE"
    it "Part 2 with 2 workers and base 0 finishes at second 15" $
      finishTime 2 0 (parseInput exampleInput) `shouldBe` 15

  describe "actual puzzle input (inputs/day07.txt)" $ do
    it "part 1 = GDHOSUXACIMRTPWNYJLEQFVZBK" $ do
      raw <- readFile "inputs/day07.txt"
      part1 (parseInput raw) `shouldBe` "GDHOSUXACIMRTPWNYJLEQFVZBK"
    it "part 2 = 1024 (5 workers, base 60)" $ do
      raw <- readFile "inputs/day07.txt"
      part2 (parseInput raw) `shouldBe` 1024
