-- | Day 5 supplement — 'Either' for "value or error."
--
-- 'Maybe' tells you /that/ something failed. 'Either' tells you /why/.
-- Use it when the failure carries information the caller will want.

module Main where

-- --------------------------------------------------------------------
-- 1. Producing 'Either' values
-- --------------------------------------------------------------------

-- | Safe division that explains the failure with a 'String' error.
safeDivE :: Int -> Int -> Either String Int
safeDivE _ 0 = Left "division by zero"
safeDivE n d = Right (n `div` d)

-- | Parse a non-empty string of digits into an 'Int', returning a
-- helpful error message on the bad cases.
parseInt :: String -> Either String Int
parseInt ""                             = Left "empty input"
parseInt s
  | all (`elem` "0123456789") s = Right (read s)
  | otherwise                   = Left ("not a number: " ++ s)

-- --------------------------------------------------------------------
-- 2. Consuming 'Either' values
-- --------------------------------------------------------------------

-- | Pattern match on 'Left' / 'Right' just like 'Nothing' / 'Just'.
describe :: Either String Int -> String
describe (Left err) = "error: " ++ err
describe (Right n)  = "ok: "    ++ show n

-- | Apply a function to the value inside 'Right', leaving 'Left' alone.
-- 'Either' is "biased" toward 'Right' for exactly this reason: 'Right'
-- is the success case, 'Left' carries the error and is preserved as-is.
mapRight :: (a -> b) -> Either e a -> Either e b
mapRight _ (Left e)  = Left e
mapRight f (Right x) = Right (f x)

-- --------------------------------------------------------------------
-- 3. A small pipeline
-- --------------------------------------------------------------------

-- | Parse two strings into 'Int's and divide them. The first failure
-- short-circuits; the success case threads the values through.
divideStrings :: String -> String -> Either String Int
divideStrings a b =
  case parseInt a of
    Left err -> Left err
    Right n  ->
      case parseInt b of
        Left err -> Left err
        Right d  -> safeDivE n d

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("safeDivE 10 0           = " ++ show (safeDivE 10 0))
  putStrLn ("safeDivE 10 3           = " ++ show (safeDivE 10 3))
  putStrLn ("parseInt \"\"             = " ++ show (parseInt ""))
  putStrLn ("parseInt \"42\"           = " ++ show (parseInt "42"))
  putStrLn ("parseInt \"4x\"           = " ++ show (parseInt "4x"))
  putStrLn ("describe (Right 7)      = " ++ describe (Right 7))
  putStrLn ("describe (Left \"oops\")  = " ++ describe (Left "oops"))
  putStrLn ("mapRight (+1) (Right 4) = "
           ++ show (mapRight (+ (1 :: Int)) (Right 4 :: Either String Int)))
  putStrLn ("mapRight (+1) (Left e)  = "
           ++ show (mapRight (+ (1 :: Int)) (Left "e" :: Either String Int)))
  putStrLn ("divideStrings \"10\" \"2\"  = " ++ show (divideStrings "10" "2"))
  putStrLn ("divideStrings \"10\" \"0\"  = " ++ show (divideStrings "10" "0"))
  putStrLn ("divideStrings \"10\" \"x\"  = " ++ show (divideStrings "10" "x"))
  putStrLn "Day 5 (Eithers) complete!!!"
