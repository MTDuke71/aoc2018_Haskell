-- | Tests for "Day20" (A Regular Map).
--
-- The puzzle text gives five small worked examples, each with the
-- expected /furthest-room/ distance.  Those pin both the regex
-- walker ('buildDoors') and the BFS ('distances') against the same
-- shapes the prose describes.  The actual-input rows are filled in
-- after the first clean run.

module Day20Spec (spec) where

import qualified Data.Map.Strict as Map
import           Test.Hspec

import           Day20

-- | All five examples from the puzzle, with their published
-- furthest-room distances.
examples :: [(String, Int)]
examples =
  [ ( "^WNE$",                                                              3 )
  , ( "^ENWWW(NEEE|SSE(EE|N))$",                                           10 )
  , ( "^ENNWSWW(NEWS|)SSSEEN(WNSE|)EE(SWEN|)NNN$",                         18 )
  , ( "^ESSWWN(E|NNENN(EESS(WNSE|)SSS|WWWSSSSE(SW|NNNE)))$",               23 )
  , ( "^WSSEESWWWNW(S|NENNEEEENN(ESSSSW(NWSW|SSEN)|WSWWN(E|WWS(E|SS))))$", 31 )
  ]

spec :: Spec
spec = describe "Day 20" $ do

  describe "buildDoors / origin" $
    it "always knows about the starting room" $
      let p = parseInput "^N$"
      in  Map.lookup (0, 0) (doors p) `shouldBe` Just [(0, -1)]

  describe "part1 (examples)" $
    mapM_ pinExample examples

  describe "part2 (detour case)" $
    it "third example has only 0 rooms >= 1000 doors away" $
      part2 (parseInput "^ENNWSWW(NEWS|)SSSEEN(WNSE|)EE(SWEN|)NNN$") `shouldBe` 0

  describe "actual input" $ do
    it "solves Part 1" $ do
      raw <- readFile "inputs/day20.txt"
      part1 (parseInput raw) `shouldBe` actualPart1
    it "solves Part 2" $ do
      raw <- readFile "inputs/day20.txt"
      part2 (parseInput raw) `shouldBe` actualPart2

pinExample :: (String, Int) -> Spec
pinExample (regex, expected) =
  it (regex ++ " has furthest room " ++ show expected) $
    part1 (parseInput regex) `shouldBe` expected

-- Filled in from the first clean run on the real input.
actualPart1, actualPart2 :: Int
actualPart1 = 3835
actualPart2 = 8520
