-- | Parsing for the Day 10 sample puzzle.
--
-- The input format is one signed integer per line, e.g.:
--
--     +1
--     -2
--     +3
--
-- 'parseChange' converts one such line to an 'Int', and 'parseInput'
-- turns the whole file (one big 'String' from 'readFile') into a list
-- of 'Int's. Both are pure — they take a 'String' and return a value,
-- with no side effects, so they are testable in isolation.

module AoC.Parsing
  ( parseChange
  , parseInput
  ) where

-- | Parse a single line of the sample input.
--
-- 'read :: String -> Int' rejects a leading @+@, so the @+@ branch
-- strips it explicitly. A negative sign is fine for 'read'.
parseChange :: String -> Int
parseChange ('+' : rest) = read rest
parseChange s            = read s

-- | Parse the full file contents into a list of changes.
--
-- 'lines' splits on @'\n'@ and drops a trailing empty line, so a file
-- ending in a newline (which it should) parses cleanly.
parseInput :: String -> [Int]
parseInput = map parseChange . lines
