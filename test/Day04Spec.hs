-- | Tests for Day 04 — Repose Record.

module Day04Spec (spec) where

import Test.Hspec
import Day04

-- | The worked example from the puzzle description.  Given in chronological
--   order so that 'sort . lines' is a no-op; the parser handles unsorted
--   real input just as well.
exampleRaw :: String
exampleRaw = unlines
  [ "[1518-11-01 00:00] Guard #10 begins shift"
  , "[1518-11-01 00:05] falls asleep"
  , "[1518-11-01 00:25] wakes up"
  , "[1518-11-01 00:30] falls asleep"
  , "[1518-11-01 00:55] wakes up"
  , "[1518-11-01 23:58] Guard #99 begins shift"
  , "[1518-11-02 00:40] falls asleep"
  , "[1518-11-02 00:50] wakes up"
  , "[1518-11-03 00:05] Guard #10 begins shift"
  , "[1518-11-03 00:24] falls asleep"
  , "[1518-11-03 00:29] wakes up"
  , "[1518-11-04 00:02] Guard #99 begins shift"
  , "[1518-11-04 00:36] falls asleep"
  , "[1518-11-04 00:46] wakes up"
  , "[1518-11-05 00:03] Guard #99 begins shift"
  , "[1518-11-05 00:45] falls asleep"
  , "[1518-11-05 00:55] wakes up"
  ]

spec :: Spec
spec = describe "Day 04 (Repose Record)" $ do

  describe "parseEntry" $ do
    it "parses a Guard-begins line (minute = 0, guard ID = 10)" $
      parseEntry "[1518-11-01 00:00] Guard #10 begins shift"
        `shouldBe` LogEntry { entryMinute = 0,  entryEvent = BeginShift 10 }
    it "parses a falls-asleep line (minute = 5)" $
      parseEntry "[1518-11-01 00:05] falls asleep"
        `shouldBe` LogEntry { entryMinute = 5,  entryEvent = FallAsleep }
    it "parses a wakes-up line (minute = 25)" $
      parseEntry "[1518-11-01 00:25] wakes up"
        `shouldBe` LogEntry { entryMinute = 25, entryEvent = WakeUp }
    it "parses a guard line with a 4-digit ID (guard #2213, minute = 0)" $
      parseEntry "[1518-04-15 23:56] Guard #2213 begins shift"
        `shouldBe` LogEntry { entryMinute = 56, entryEvent = BeginShift 2213 }

  describe "part1 (puzzle example)" $
    it "guard #10 (most total minutes) x minute 24 (most-slept minute) = 240" $
      part1 (parseInput exampleRaw) `shouldBe` 240

  describe "part2 (puzzle example)" $
    it "guard #99 x minute 45 (slept there 3 nights) = 4455" $
      part2 (parseInput exampleRaw) `shouldBe` 4455

  describe "actual puzzle input (inputs/day04.txt)" $ do
    it "part 1 = 85296" $ do
      raw <- readFile "inputs/day04.txt"
      part1 (parseInput raw) `shouldBe` 85296
    it "part 2 = 58559" $ do
      raw <- readFile "inputs/day04.txt"
      part2 (parseInput raw) `shouldBe` 58559
