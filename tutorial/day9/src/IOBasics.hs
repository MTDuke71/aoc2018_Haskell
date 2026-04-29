-- | Day 9 — 'IO', 'do' notation, and the line between pure and effectful.
--
-- Up to Day 8 every example was pure: a function from input to output
-- with no side effects. This file is the first one that /does things/
-- in the world — prints to the terminal, reads a line of input, and
-- sequences those actions in order. The mechanism that makes that
-- possible without breaking purity is the 'IO' type and the 'do'
-- block. Both are introduced step by step below.

module Main where

-- We import a couple of helpers from 'Control.Monad' for the section
-- on 'mapM_' / 'forM_' / 'when'. They are part of the standard
-- libraries shipped with GHC; no extra package needed.
import Control.Monad (when, forM_, replicateM_)

-- --------------------------------------------------------------------
-- 1. What 'IO a' means
-- --------------------------------------------------------------------
--
-- Every value in Haskell so far has been pure: 'Int', 'String',
-- 'Map String Int', and so on. Pure values can be inspected, copied,
-- and substituted by their definition without changing the meaning of
-- a program.
--
-- 'IO a' is different. A value of type 'IO a' is a /recipe/ that, when
-- the runtime executes it, will produce a value of type 'a' /and/ may
-- read or write the outside world along the way. The recipe itself is
-- a perfectly ordinary first-class value — you can store it, pass it
-- around, build it from smaller recipes — but it does nothing until
-- 'main' is run.
--
-- Examples of 'IO' values:
--
--   putStrLn :: String -> IO ()      -- print a line, return nothing useful
--   getLine  :: IO String            -- read a line from stdin
--   readFile :: FilePath -> IO String
--   pure     :: a -> IO a            -- "lift" a pure value into IO
--
-- The unit type '()' shows up a lot: it is the "I have nothing
-- meaningful to give you" type, with exactly one value, also written
-- '()'. 'putStrLn' returns 'IO ()' because the only thing it does is
-- print — there is no result for the caller to use.

-- --------------------------------------------------------------------
-- 2. 'do' notation — sequencing actions in order
-- --------------------------------------------------------------------
--
-- A 'do' block lets you write a sequence of 'IO' actions one per line.
-- Each line is an action; the runtime executes them top-to-bottom.

greetWorld :: IO ()
greetWorld = do
  putStrLn "Hello,"
  putStrLn "World!"
  putStrLn "(three lines, in this exact order)"

-- The two key rules of a 'do' block:
--
--   1. /All actions in a 'do' block must share the same monad./ Here
--      that monad is 'IO'. You cannot mix 'IO' and 'Maybe' actions in
--      one block — you would not even know what "do them in order"
--      means across types.
--   2. /The block's type is the type of its last action./ 'greetWorld'
--      ends in 'putStrLn "..."', whose type is 'IO ()'; therefore
--      'greetWorld :: IO ()'.

-- --------------------------------------------------------------------
-- 3. The '<-' arrow: bind a result inside a 'do' block
-- --------------------------------------------------------------------
--
-- 'getLine :: IO String' is an action whose /result/ is a 'String'.
-- To use that 'String' in the rest of the block, write
--
--     name <- getLine
--
-- Read it as: "run the action 'getLine', and call the resulting
-- 'String' 'name'." From here on 'name' is a plain pure 'String';
-- the 'IO' wrapper has been peeled off /inside/ the block.

askName :: IO ()
askName = do
  putStrLn "What is your name?"
  name <- getLine          -- the <- is binding, not assignment
  putStrLn ("Hello, " ++ name ++ "!")

-- Crucial distinction:
--
--   name <- getLine        -- run the action, bind its result to 'name'
--   let greeting = "Hi"    -- pure binding: no action, just a name
--
-- Use '<-' for IO actions whose result you want to name.
-- Use 'let' for pure expressions you want to name. (Inside a 'do'
-- block, 'let' has no 'in' — the rest of the block is its body.)

greetTwice :: IO ()
greetTwice = do
  let shout = "HEY"          -- pure
  putStrLn shout
  putStrLn shout
  -- 'shout' could just as well have been a top-level definition; the
  -- 'let' inside 'do' is for things you need only locally.

-- --------------------------------------------------------------------
-- 4. 'pure' / 'return' — promote a pure value into IO
-- --------------------------------------------------------------------
--
-- Sometimes the last line of a 'do' block needs to be a value, not an
-- action. Wrap it with 'pure' (older code uses 'return' — same thing
-- for 'IO').

doubleEcho :: IO Int
doubleEcho = do
  putStrLn "Type a number:"
  s <- getLine
  let n = read s :: Int      -- pure: parse the line
  putStrLn ("doubled: " ++ show (2 * n))
  pure (2 * n)               -- IO Int — this is the block's result

-- 'return' in Haskell is /not/ the C / Rust 'return'. It does NOT
-- jump out of a function; it just lifts a pure value into a monad.
-- These two definitions of 'doubleEcho' would behave identically:
--
--     pure (2 * n)
--     return (2 * n)
--
-- Modern style prefers 'pure' for clarity. If you read older Haskell
-- and see 'return', mentally rewrite it as 'pure'.

-- --------------------------------------------------------------------
-- 5. Pure vs effectful — the 60/40 rule
-- --------------------------------------------------------------------
--
-- A useful AoC habit: keep IO at the edges, keep the meat pure.
--
--   main :: IO ()                               -- effectful shell
--   main = do
--     contents <- readFile "input.txt"          -- effect
--     let answer = solve (parse contents)       -- pure
--     print answer                              -- effect
--
-- That split makes pure code easy to test (no IO setup, no fixtures)
-- and makes the IO layer obvious to read (a handful of lines that
-- are clearly "talk to the world").
--
-- The functions below illustrate the split — the pure 'isShout'
-- decides what to do; the effectful 'reactToInput' just glues
-- 'getLine', the pure decision, and 'putStrLn' together.

isShout :: String -> Bool
isShout s = not (null s) && all (`elem` ['A'..'Z']) (filter (/= ' ') s)

reactToInput :: IO ()
reactToInput = do
  putStrLn "Say something:"
  s <- getLine
  if isShout s
     then putStrLn "WHY ARE YOU YELLING"
     else putStrLn ("ok, you said: " ++ s)

-- 'isShout' has type 'String -> Bool'. It can be tested in GHCi
-- without ever invoking IO. 'reactToInput' is the IO wrapper around
-- it. That separation is the single most important habit Day 9
-- introduces.

-- --------------------------------------------------------------------
-- 6. Effectful list helpers: 'mapM_', 'forM_', 'replicateM_'
-- --------------------------------------------------------------------
--
-- 'mapM_ :: (a -> IO ()) -> [a] -> IO ()'
--   "map this IO action over each element of the list, throwing the
--    results away."
--
-- 'forM_' is 'mapM_' with the arguments flipped — handy when the
-- list comes first and the action is a multi-line lambda or 'do'
-- block.
--
-- 'replicateM_ :: Int -> IO a -> IO ()'
--   "do this action n times, throw the results away."

printAll :: [String] -> IO ()
printAll xs = mapM_ putStrLn xs

countDown :: IO ()
countDown = forM_ [3, 2, 1 :: Int] $ \n -> do
  putStrLn ("T-minus " ++ show n)

knockKnock :: IO ()
knockKnock = replicateM_ 3 (putStrLn "knock")

-- The trailing underscore on 'mapM_' / 'forM_' / 'replicateM_' is the
-- convention for "discards the results." Without the underscore you
-- get back '[a]' or 'IO [a]', which you almost never want for pure
-- printing.

-- --------------------------------------------------------------------
-- 7. Conditional effects: 'when' and 'unless'
-- --------------------------------------------------------------------
--
-- 'when :: Bool -> IO () -> IO ()'  runs the action if the condition
-- is 'True'. 'unless' is the negation. They are the natural
-- replacement for 'if cond then action else pure ()'.

shoutBack :: String -> IO ()
shoutBack s = do
  when (isShout s) $
    putStrLn "(you are still yelling)"
  putStrLn ("you said: " ++ s)

-- Without 'when', you would write
--
--     if isShout s
--        then putStrLn "(you are still yelling)"
--        else pure ()
--
-- which is correct but noisier. 'when' is the named pattern.

-- --------------------------------------------------------------------
-- Entry point — the only IO action that actually runs
-- --------------------------------------------------------------------
--
-- 'main :: IO ()' is the program's entry point. The runtime takes the
-- 'IO ()' recipe stored in 'main' and executes it. Anything not
-- reachable from 'main' simply never runs, no matter how many
-- 'putStrLn's it contains.
--
-- For Day 9 the 'main' below stays non-interactive — it does not call
-- 'getLine' — so 'runghc' will run end-to-end without waiting on you.
-- The interactive examples ('askName', 'reactToInput', 'shoutBack')
-- are demonstrated in GHCi instead; see the README's "Try it" section.

main :: IO ()
main = do
  greetWorld
  putStrLn ""
  printAll ["one", "two", "three"]
  putStrLn ""
  countDown
  putStrLn ""
  knockKnock
  putStrLn ""
  putStrLn ("isShout \"HELLO WORLD\" = " ++ show (isShout "HELLO WORLD"))
  putStrLn ("isShout \"hello\"       = " ++ show (isShout "hello"))
  putStrLn ""
  putStrLn "Day 9 (IOBasics) complete!!!"
