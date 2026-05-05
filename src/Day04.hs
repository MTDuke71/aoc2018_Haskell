-- |
-- Module      : Day04
-- Description : Day 04 — Repose Record
--
-- Guards keep log entries noting when they begin their shifts and when they
-- fall asleep or wake up.  All sleep events occur within the midnight hour
-- (00:00–00:59).  The log entries arrive unsorted; sort them to recover
-- chronological order.
--
-- Part 1: find the guard with the most total minutes asleep; find the
--         minute that guard is most often asleep.  Answer = guard ID × minute.
-- Part 2: find the guard most consistently asleep at a single minute
--         (highest frequency at any one minute across all nights).
--         Answer = guard ID × that minute.
--
-- Concepts introduced this day:
--   * Sum types  — @data Event = BeginShift !Int | FallAsleep | WakeUp@
--   * Lexicographic sort on strings — ISO timestamp format makes
--     alphabetical order identical to chronological order.
--   * 'maximumBy' / 'comparing' — select the maximum element by a
--     projected key, avoiding a manual 'map-then-sort' detour.
--   * Tail-recursive 'go' accumulator — building state from a sorted
--     event stream without touching the State monad.
--   * 'mapMaybe' — filter-and-map that silently drops 'Nothing' values.

module Day04
  ( Event (..)
  , LogEntry (..)
  , SleepSchedule
  , parseEntry
  , buildSchedule
  , parseInput
  , part1
  , part2
  , solve
  ) where

import Data.List             (sort, maximumBy)
import Data.Ord              (comparing)
import Data.Maybe            (mapMaybe)
import qualified Data.Map.Strict as Map

-- ---------------------------------------------------------------------------
-- Data types
-- ---------------------------------------------------------------------------

-- | One event recorded in the guard log.
--
--   This is a /sum type/ (also called an algebraic data type or ADT): a
--   single type with three distinct constructors.  Haskell's analogue of a
--   Rust @enum@.
--
--   The bang (!) on the 'BeginShift' field is a strict annotation: the
--   guard ID is evaluated to a real @Int@ as soon as the constructor is
--   applied, rather than being deferred as a thunk.
data Event
  = BeginShift !Int  -- ^ guard starts a new shift; carries the guard ID
  | FallAsleep       -- ^ guard falls asleep
  | WakeUp           -- ^ guard wakes up
  deriving (Eq, Show)

-- | One parsed log line: the minute within the midnight hour when the event
--   occurred (0–59), together with the event itself.
data LogEntry = LogEntry
  { entryMinute :: !Int   -- ^ minute extracted from the timestamp
  , entryEvent  :: !Event -- ^ what happened
  } deriving (Eq, Show)

-- | Per-guard sleep record.  Maps each guard ID to the complete list of
--   minutes (0–59) during which that guard was asleep, concatenated across
--   every night.  Duplicate minutes are intentional: a minute appearing N
--   times means the guard was asleep at that minute on N different nights.
type SleepSchedule = Map.Map Int [Int]

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Parse one raw log line into a 'LogEntry'.
--
--   Line format: @[YYYY-MM-DD HH:MM] text@
--
--   The minute is always at character positions 15–16 (0-indexed).
--   The event type is determined by the third whitespace-separated token:
--   @\"Guard\"@ → shift start (guard ID follows as @#NNN@);
--   @\"falls\"@ → sleep;
--   anything else → wake.
parseEntry :: String -> LogEntry
parseEntry line =
  let ws     = words line
      minute = read (take 2 (drop 15 line)) :: Int
      ev     = case ws !! 2 of
                 "Guard" -> BeginShift (read (drop 1 (ws !! 3)))
                 "falls" -> FallAsleep
                 _       -> WakeUp
  in LogEntry minute ev

-- | Convert a chronologically-sorted list of log entries into a
--   'SleepSchedule'.
--
--   Uses a tail-recursive helper @go@ with three accumulator parameters:
--   the ID of the current guard on duty, the minute the guard last fell
--   asleep, and the schedule built so far.  No 'State' monad is needed —
--   a named helper with explicit accumulators is the idiomatic Haskell
--   approach for processing a sorted stream.
buildSchedule :: [LogEntry] -> SleepSchedule
buildSchedule = go (-1) (-1) Map.empty
  where
    go :: Int -> Int -> SleepSchedule -> [LogEntry] -> SleepSchedule
    go _   _     sched []     = sched
    go gid sleep sched (e:es) = case entryEvent e of
      BeginShift g ->
        go g sleep sched es
      FallAsleep ->
        go gid (entryMinute e) sched es
      WakeUp ->
        let newMins = [sleep .. entryMinute e - 1]
            sched'  = Map.insertWith (++) gid newMins sched
        in  go gid sleep sched' es

-- | Sort log lines lexicographically (ISO timestamp format makes this
--   identical to chronological order), parse each, then build the schedule.
parseInput :: String -> SleepSchedule
parseInput = buildSchedule . map parseEntry . sort . lines

-- ---------------------------------------------------------------------------
-- Helpers shared by both parts
-- ---------------------------------------------------------------------------

-- | Count how often each minute appears in a guard's sleep list.
--   Reuses the 'Map.fromListWith' idiom from Day 3.
minuteFreqs :: [Int] -> Map.Map Int Int
minuteFreqs = Map.fromListWith (+) . map (\x -> (x, 1))

-- | For one guard (given as a @(guardId, sleepMinutes)@ pair), find the
--   product @guardId × mostSleptMinute@ together with the frequency of
--   that minute.  Returns 'Nothing' for a guard with no sleep record.
bestSlot :: (Int, [Int]) -> Maybe (Int, Int)
bestSlot (_,   [])   = Nothing
bestSlot (gid, mins) =
  let (bestMin, freq) = maximumBy (comparing snd) (Map.toList (minuteFreqs mins))
  in  Just (gid * bestMin, freq)

-- ---------------------------------------------------------------------------
-- Solutions
-- ---------------------------------------------------------------------------

-- | Part 1: find the guard with the most total minutes asleep.  Among all
--   minutes, find which one that guard is most often asleep at.
--   Return @guardId × minute@.
part1 :: SleepSchedule -> Int
part1 sched =
  let (guardId, mins) = maximumBy (comparing (length . snd)) (Map.toList sched)
      (bestMin, _)    = maximumBy (comparing snd) (Map.toList (minuteFreqs mins))
  in  guardId * bestMin

-- | Part 2: across all guards, find the guard most consistently asleep at
--   a single minute (highest frequency at any one minute).
--   Return @guardId × that minute@.
part2 :: SleepSchedule -> Int
part2 sched =
  fst (maximumBy (comparing snd) (mapMaybe bestSlot (Map.toList sched)))

-- | Print both answers.
solve :: String -> IO ()
solve contents = do
  let sched = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 sched))
  putStrLn ("  part 2: " ++ show (part2 sched))
