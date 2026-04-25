-- | Day 5 — 'Maybe' values and the helpers you actually use.
--
-- Every function below returns or consumes a 'Maybe' instead of
-- crashing on the bad case. Pattern matching from Day 4 is what makes
-- 'Maybe' pleasant to work with.

module Main where

import Data.Maybe (fromMaybe, mapMaybe)

-- --------------------------------------------------------------------
-- 1. Producing 'Maybe' values
-- --------------------------------------------------------------------

-- | A safe head: 'Nothing' for the empty list, 'Just' the first
-- element otherwise.
safeHead :: [a] -> Maybe a
safeHead []    = Nothing
safeHead (x:_) = Just x

-- | A safe division: 'Nothing' when the divisor is zero, 'Just' the
-- quotient otherwise. The 'Int' return type keeps it simple — for
-- 'Double' you would just produce an 'Infinity' or 'NaN' instead.
safeDiv :: Int -> Int -> Maybe Int
safeDiv _ 0 = Nothing
safeDiv n d = Just (n `div` d)

-- | A safe lookup by key in an association list. The Prelude already
-- ships 'lookup'; this is the pattern-match version of the same idea.
lookupKey :: Eq k => k -> [(k, v)] -> Maybe v
lookupKey _ []           = Nothing
lookupKey k ((k', v):xs)
  | k == k'   = Just v
  | otherwise = lookupKey k xs

-- --------------------------------------------------------------------
-- 2. Consuming 'Maybe' values
-- --------------------------------------------------------------------

-- | Pull a value out of a 'Maybe', supplying a default for 'Nothing'.
-- This is what 'Data.Maybe.fromMaybe' does; we hand-roll it here to
-- show the pattern.
withDefault :: a -> Maybe a -> a
withDefault def Nothing  = def
withDefault _   (Just x) = x

-- | Apply a function to the value inside a 'Just', leaving 'Nothing'
-- alone. This is 'fmap' for 'Maybe' — by Day 7 you will write it as
-- @fmap f m@ or @f \<$\> m@ — for today, the explicit pattern match
-- is the clearest version.
mapMaybeValue :: (a -> b) -> Maybe a -> Maybe b
mapMaybeValue _ Nothing  = Nothing
mapMaybeValue f (Just x) = Just (f x)

-- --------------------------------------------------------------------
-- 3. Real example — parsing
-- --------------------------------------------------------------------

-- | A toy "parse a digit character" — returns 'Just' the digit's value
-- as an 'Int' when the character is '0'..'9', 'Nothing' otherwise.
parseDigit :: Char -> Maybe Int
parseDigit c
  | c >= '0' && c <= '9' = Just (fromEnum c - fromEnum '0')
  | otherwise            = Nothing

-- | Try to parse every character in a string as a digit and sum them.
-- Non-digits are silently dropped — 'mapMaybe' from "Data.Maybe" does
-- exactly that: apply a 'Maybe'-valued function to a list and keep
-- only the 'Just's.
sumDigits :: String -> Int
sumDigits s = sum (mapMaybe parseDigit s)

-- --------------------------------------------------------------------
-- 4. Chaining: when the next step depends on the previous one
-- --------------------------------------------------------------------

-- | First valid quotient from a list of (numerator, denominator) pairs.
-- Walk the list, division by zero skips that pair, the first successful
-- division wins.
firstValidQuotient :: [(Int, Int)] -> Maybe Int
firstValidQuotient []         = Nothing
firstValidQuotient ((n,d):xs) =
  case safeDiv n d of
    Just q  -> Just q
    Nothing -> firstValidQuotient xs

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("safeHead []                   = " ++ show (safeHead ([] :: [Int])))
  putStrLn ("safeHead [1,2,3]              = " ++ show (safeHead [1, 2, 3 :: Int]))
  putStrLn ("safeDiv 10 0                  = " ++ show (safeDiv 10 0))
  putStrLn ("safeDiv 10 3                  = " ++ show (safeDiv 10 3))
  putStrLn ("lookupKey 'b' [('a',1),('b',2)] = "
           ++ show (lookupKey 'b' [('a', 1 :: Int), ('b', 2)]))
  putStrLn ("withDefault 0 Nothing         = " ++ show (withDefault (0 :: Int) Nothing))
  putStrLn ("withDefault 0 (Just 7)        = " ++ show (withDefault 0 (Just (7 :: Int))))
  putStrLn ("fromMaybe 0 (Just 9)          = " ++ show (fromMaybe (0 :: Int) (Just 9)))
  putStrLn ("mapMaybeValue (+1) (Just 4)   = " ++ show (mapMaybeValue (+ (1 :: Int)) (Just 4)))
  putStrLn ("mapMaybeValue (+1) Nothing    = " ++ show (mapMaybeValue (+ (1 :: Int)) Nothing))
  putStrLn ("parseDigit '7'                = " ++ show (parseDigit '7'))
  putStrLn ("parseDigit 'x'                = " ++ show (parseDigit 'x'))
  putStrLn ("sumDigits \"a1b2c3\"            = " ++ show (sumDigits "a1b2c3"))
  putStrLn ("firstValidQuotient [(1,0),(8,2)] = "
           ++ show (firstValidQuotient [(1, 0), (8, 2)]))
  putStrLn "Day 5 (Maybes) complete!!!"
