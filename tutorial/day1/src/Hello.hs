-- | Day 1 — Hello, World!
--
-- The smallest possible Haskell program that does something visible.
-- Every top-level binding has an explicit type signature: this is the
-- style the rest of the tutorial (and the AoC solutions) will follow.

module Main where

-- | Program entry point.
--
-- 'IO ()' is the type of "an action that performs some input/output
-- and returns nothing useful" (the '()' is Haskell's unit type — the
-- same idea as Rust's '()' or C's 'void').
main :: IO ()
main = do
  putStrLn "Hello, World!"
  putStrLn (greeting "Matt")

-- | Build a greeting string for the given name.
--
-- Pure function: given the same input, always returns the same output,
-- and has no side effects. Contrast with 'main', which lives in 'IO'.
greeting :: String -> String
greeting name = "Welcome to Haskell, " ++ name ++ "."
