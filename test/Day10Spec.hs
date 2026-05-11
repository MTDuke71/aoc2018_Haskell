-- | Tests for Day 10 -- The Stars Align.

module Day10Spec (spec) where

import           Test.Hspec
import           Day10

-- | The 31-point exampleInput from the puzzle text.  After 3 seconds the
-- bounding box reaches its minimum and the points spell @HI@.
exampleInput :: String
exampleInput = unlines
  [ "position=< 9,  1> velocity=< 0,  2>"
  , "position=< 7,  0> velocity=<-1,  0>"
  , "position=< 3, -2> velocity=<-1,  1>"
  , "position=< 6, 10> velocity=<-2, -1>"
  , "position=< 2, -4> velocity=< 2,  2>"
  , "position=<-6, 10> velocity=< 2, -2>"
  , "position=< 1,  8> velocity=< 1, -1>"
  , "position=< 1,  7> velocity=< 1,  0>"
  , "position=<-3, 11> velocity=< 1, -2>"
  , "position=< 7,  6> velocity=<-1, -1>"
  , "position=<-2,  3> velocity=< 1,  0>"
  , "position=<-4,  3> velocity=< 2,  0>"
  , "position=<10, -3> velocity=<-1,  1>"
  , "position=< 5, 11> velocity=< 1, -2>"
  , "position=< 4,  7> velocity=< 0, -1>"
  , "position=< 8, -2> velocity=< 0,  1>"
  , "position=<15,  0> velocity=<-2,  0>"
  , "position=< 1,  6> velocity=< 1,  0>"
  , "position=< 8,  9> velocity=< 0, -1>"
  , "position=< 3,  3> velocity=<-1,  1>"
  , "position=< 0,  5> velocity=< 0, -1>"
  , "position=<-2,  2> velocity=< 2,  0>"
  , "position=< 5, -2> velocity=< 1,  2>"
  , "position=< 1,  4> velocity=< 2,  1>"
  , "position=<-2,  7> velocity=< 2, -2>"
  , "position=< 3,  6> velocity=<-1, -1>"
  , "position=< 5,  0> velocity=< 1,  0>"
  , "position=<-6,  0> velocity=< 2,  0>"
  , "position=< 5,  9> velocity=< 1, -2>"
  , "position=<14,  7> velocity=<-2,  0>"
  , "position=<-3,  6> velocity=< 2, -1>"
  ]

-- | The expected rendered "HI" from the puzzle text, cropped to
-- bounding box.  An @H@ five wide, two dot columns of gap, then an
-- @I@ three wide -- ten columns total, eight rows tall.
expectedExampleMessage :: String
expectedExampleMessage = unlines
  [ "#...#..###"
  , "#...#...#."
  , "#...#...#."
  , "#####...#."
  , "#...#...#."
  , "#...#...#."
  , "#...#...#."
  , "#...#..###"
  ]

spec :: Spec
spec = describe "Day 10 (The Stars Align)" $ do

  describe "parseLine" $ do
    it "parses a positive-only line" $
      parseLine "position=< 9,  1> velocity=< 0,  2>"
        `shouldBe` Point 9 1 0 2
    it "parses a line with negatives" $
      parseLine "position=<-52775,  31912> velocity=< 5, -3>"
        `shouldBe` Point (-52775) 31912 5 (-3)

  describe "parseInput" $
    it "parses every line of the exampleInput" $
      length (parseInput exampleInput) `shouldBe` 31

  describe "step / bboxArea" $ do
    let pts0 = parseInput exampleInput
    it "advances one second" $ do
      let pts1 = step pts0
      -- the first point is < 9, 1>  velocity < 0, 2>, so after 1s it
      -- should be at (9, 3) with velocity unchanged.
      head pts1 `shouldBe` Point 9 3 0 2
    it "bounding-box area shrinks then grows on the exampleInput" $ do
      let areas = take 6 [ bboxArea ps | ps <- iterate step pts0 ]
      -- areas decrease through t=3 then start increasing.
      head     areas `shouldSatisfy` (>  areas !! 1)
      areas !! 1     `shouldSatisfy` (>  areas !! 2)
      areas !! 2     `shouldSatisfy` (>  areas !! 3)
      areas !! 3     `shouldSatisfy` (<= areas !! 4)

  describe "puzzle exampleInput" $ do
    let (t, pts) = findMessage (parseInput exampleInput)
    it "reaches the minimum-area frame at t = 3" $
      t `shouldBe` 3
    it "renders 'HI' at the minimum-area frame" $
      render pts `shouldBe` expectedExampleMessage
    it "part2 returns 3 on the exampleInput" $
      part2 (parseInput exampleInput) `shouldBe` 3
    it "part1 returns the 'HI' rendering on the exampleInput" $
      part1 (parseInput exampleInput) `shouldBe` expectedExampleMessage

  describe "findMessageTernary (optimisation alternative)" $ do
    it "agrees with findMessage on the puzzle example (t = 3)" $ do
      let pts = parseInput exampleInput
      fst (findMessageTernary pts) `shouldBe` fst (findMessage pts)
    it "renders the same 'HI' frame on the example" $ do
      let pts = parseInput exampleInput
      render (snd (findMessageTernary pts)) `shouldBe` expectedExampleMessage
    it "agrees with findMessage on the actual input" $ do
      raw <- readFile "inputs/day10.txt"
      let pts = parseInput raw
      fst (findMessageTernary pts) `shouldBe` fst (findMessage pts)

  describe "actual puzzle input (inputs/day10.txt)" $ do
    it "Part 2 (seconds elapsed) matches the pinned answer" $ do
      raw <- readFile "inputs/day10.txt"
      part2 (parseInput raw) `shouldBe` expectedPart2Answer
    it "Part 1 (rendered message) matches the pinned ASCII art" $ do
      raw <- readFile "inputs/day10.txt"
      part1 (parseInput raw) `shouldBe` expectedPart1Render

-- | The eight-letter message reads @JLPZFJRH@ in the rendered ASCII.
expectedPart1Render :: String
expectedPart1Render = unlines
  [ "...###..#.......#####...######..######.....###..#####...#....#"
  , "....#...#.......#....#.......#..#...........#...#....#..#....#"
  , "....#...#.......#....#.......#..#...........#...#....#..#....#"
  , "....#...#.......#....#......#...#...........#...#....#..#....#"
  , "....#...#.......#####......#....#####.......#...#####...######"
  , "....#...#.......#.........#.....#...........#...#..#....#....#"
  , "....#...#.......#........#......#...........#...#...#...#....#"
  , "#...#...#.......#.......#.......#.......#...#...#...#...#....#"
  , "#...#...#.......#.......#.......#.......#...#...#....#..#....#"
  , ".###....######..#.......######..#........###....#....#..#....#"
  ]

-- | Pinned regression value for the seconds-elapsed answer.
expectedPart2Answer :: Int
expectedPart2Answer = 10595
