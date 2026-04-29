-- | The AoC 2018 dispatch executable.
--
-- Usage:
--
--     cabal run aoc2018-solve -- <day-number>
--     cabal run aoc2018-solve -- 0          -- the warm-up
--     cabal run aoc2018-solve -- 5          -- AoC 2018 Day 5
--
-- The day number is looked up in 'solvers' below; the matching
-- 'Day??.solve' is then run against the file @inputs/day??.txt@. The
-- relative path resolves against the package directory (the repo
-- root) when launched via @cabal run@.

module Main where

import           System.Environment (getArgs)
import           System.IO          (hPutStrLn, stderr)
import           System.Exit        (exitFailure)

import qualified Day00
import qualified Day01
import qualified Day02
import qualified Day03
import qualified Day04
import qualified Day05
import qualified Day06
import qualified Day07
import qualified Day08
import qualified Day09
import qualified Day10
import qualified Day11
import qualified Day12
import qualified Day13
import qualified Day14
import qualified Day15
import qualified Day16
import qualified Day17
import qualified Day18
import qualified Day19
import qualified Day20
import qualified Day21
import qualified Day22
import qualified Day23
import qualified Day24
import qualified Day25

-- | The 26-entry dispatch table. Each entry maps a day number to that
-- day's 'solve :: String -> IO ()'. Adding a 27th day would require
-- two edits: a new module, and a new line here.
solvers :: [(Int, String -> IO ())]
solvers =
  [ ( 0, Day00.solve), ( 1, Day01.solve), ( 2, Day02.solve), ( 3, Day03.solve)
  , ( 4, Day04.solve), ( 5, Day05.solve), ( 6, Day06.solve), ( 7, Day07.solve)
  , ( 8, Day08.solve), ( 9, Day09.solve), (10, Day10.solve), (11, Day11.solve)
  , (12, Day12.solve), (13, Day13.solve), (14, Day14.solve), (15, Day15.solve)
  , (16, Day16.solve), (17, Day17.solve), (18, Day18.solve), (19, Day19.solve)
  , (20, Day20.solve), (21, Day21.solve), (22, Day22.solve), (23, Day23.solve)
  , (24, Day24.solve), (25, Day25.solve)
  ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    [arg] -> case reads arg of
      [(n, "")] -> runDay n
      _         -> usage
    _ -> usage

runDay :: Int -> IO ()
runDay n = case lookup n solvers of
  Just solve -> do
    let path = "inputs/day" ++ pad n ++ ".txt"
    putStrLn ("Day " ++ pad n ++ " (input: " ++ path ++ ")")
    contents <- readFile path
    solve contents
  Nothing -> do
    hPutStrLn stderr ("no solver for day " ++ show n ++ " (valid range: 0..25)")
    exitFailure

pad :: Int -> String
pad n
  | n < 10 && n >= 0 = '0' : show n
  | otherwise        = show n

usage :: IO ()
usage = do
  hPutStrLn stderr "usage: aoc2018-solve <day-number>   (0..25)"
  exitFailure
