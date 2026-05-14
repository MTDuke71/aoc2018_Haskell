-- | Tests for Day 13 -- Mine Cart Madness.

module Day13Spec (spec) where

import           Data.Array.Unboxed ((!))
import           Test.Hspec
import           Day13

spec :: Spec
spec = describe "Day 13 (Mine Cart Madness)" $ do

  describe "stepDir / direction algebra" $ do
    it "U moves rows up (negative dy)" $
      stepDir U `shouldBe` (-1, 0)
    it "D moves rows down (positive dy)" $
      stepDir D `shouldBe` ( 1, 0)
    it "L moves columns left (negative dx)" $
      stepDir L `shouldBe` ( 0,-1)
    it "R moves columns right (positive dx)" $
      stepDir R `shouldBe` ( 0, 1)

    it "reflectSlash sends R -> U (east into '/' goes north)" $
      reflectSlash R `shouldBe` U
    it "reflectSlash sends U -> R (north into '/' goes east)" $
      reflectSlash U `shouldBe` R
    it "reflectBackslash sends R -> D (east into '\\' goes south)" $
      reflectBackslash R `shouldBe` D
    it "reflectBackslash sends U -> L (north into '\\' goes west)" $
      reflectBackslash U `shouldBe` L

    it "intersectTurn TStraight is identity" $ do
      intersectTurn TStraight U `shouldBe` U
      intersectTurn TStraight L `shouldBe` L
    it "intersectTurn TLeft is 90 deg counter-clockwise" $ do
      intersectTurn TLeft U `shouldBe` L
      intersectTurn TLeft L `shouldBe` D
      intersectTurn TLeft D `shouldBe` R
      intersectTurn TLeft R `shouldBe` U
    it "intersectTurn TRight is 90 deg clockwise" $ do
      intersectTurn TRight U `shouldBe` R
      intersectTurn TRight R `shouldBe` D
      intersectTurn TRight D `shouldBe` L
      intersectTurn TRight L `shouldBe` U

    it "nextTurn cycles L -> S -> R -> L" $ do
      nextTurn TLeft     `shouldBe` TStraight
      nextTurn TStraight `shouldBe` TRight
      nextTurn TRight    `shouldBe` TLeft

  describe "parseInput" $ do
    it "extracts the two carts from the part-1 worked example" $ do
      let p = parseInput examplePart1
      length (carts p) `shouldBe` 2
    it "replaces cart glyphs with the underlying straight track" $ do
      let p = parseInput examplePart1
          a = track p
      -- The first cart in the example is '>' at column 2 of row 0:
      -- "/->-\\".  After parsing the cell should be '-'.
      (a ! (0, 2)) `shouldBe` '-'
      -- And the cart at (3, 9) was 'v', so the underlying tile is '|'.
      (a ! (3, 9)) `shouldBe` '|'

  describe "Part 1 worked example (crash at 7,3)" $
    it "part1 returns \"7,3\"" $
      part1 (parseInput examplePart1) `shouldBe` "7,3"

  describe "Part 2 worked example (survivor at 6,4)" $
    it "part2 returns \"6,4\"" $
      part2 (parseInput examplePart2) `shouldBe` "6,4"

  describe "actual puzzle input (inputs/day13.txt)" $ do
    it "Part 1 matches the pinned answer" $ do
      raw <- readFile "inputs/day13.txt"
      part1 (parseInput raw) `shouldBe` expectedPart1
    it "Part 2 matches the pinned answer" $ do
      raw <- readFile "inputs/day13.txt"
      part2 (parseInput raw) `shouldBe` expectedPart2

-- | Part 1 worked example, verbatim from the puzzle.  Trailing
-- whitespace is preserved (the curves on the right need it).
examplePart1 :: String
examplePart1 = unlines
  [ "/->-\\        "
  , "|   |  /----\\"
  , "| /-+--+-\\  |"
  , "| | |  | v  |"
  , "\\-+-/  \\-+--/"
  , "  \\------/   "
  ]

-- | Part 2 worked example, verbatim from the puzzle.
examplePart2 :: String
examplePart2 = unlines
  [ "/>-<\\  "
  , "|   |  "
  , "| /<+-\\"
  , "| | | v"
  , "\\>+</ |"
  , "  |   ^"
  , "  \\<->/"
  ]

-- | Pinned regression value for Part 1.
expectedPart1 :: String
expectedPart1 = "118,66"

-- | Pinned regression value for Part 2.
expectedPart2 :: String
expectedPart2 = "70,129"
