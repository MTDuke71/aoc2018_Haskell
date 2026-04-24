-- | Day 4 — Pattern matching, guards, where, and let.
--
-- Every function below is written so the structure of the input drives
-- the structure of the code. No if/else chains where a pattern fits
-- better. Every top-level binding still has an explicit type signature.

module Main where

-- --------------------------------------------------------------------
-- 1. Pattern matching on values
-- --------------------------------------------------------------------

-- | Factorial, defined by two equations: one for the base case, one
-- for the recursive case. The compiler tries the equations top to
-- bottom and uses the first whose left-hand side matches.
--
-- This is the Haskell replacement for @if n == 0 then 1 else …@.
factorial :: Int -> Int
factorial 0 = 1
factorial n = n * factorial (n - 1)

-- | Fibonacci, three equations. The first two pin the base cases; the
-- third handles every other 'Int'. Order matters — if the @fib n@
-- equation came first it would match @0@ and @1@ as well.
fib :: Int -> Int
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)

-- --------------------------------------------------------------------
-- 2. Pattern matching on tuples
-- --------------------------------------------------------------------

-- | Take the first component of a pair. The pattern @(x, _)@ binds
-- the first component to @x@ and ignores the second with @_@.
fstOf :: (a, b) -> a
fstOf (x, _) = x

-- | Sum the components of an Int pair.
sumPair :: (Int, Int) -> Int
sumPair (a, b) = a + b

-- --------------------------------------------------------------------
-- 3. Pattern matching on lists
-- --------------------------------------------------------------------

-- | A list is built from @[]@ (the empty list) and @x:xs@ (a head @x@
-- prepended to a tail @xs@). Every list function in the Prelude is
-- some variant of these two cases.
--
-- Our own 'length' is the canonical example.
myLength :: [a] -> Int
myLength []     = 0
myLength (_:xs) = 1 + myLength xs

-- | Sum a list of 'Int's. Same shape: empty list is 0, non-empty list
-- is head plus the sum of the tail.
mySum :: [Int] -> Int
mySum []     = 0
mySum (x:xs) = x + mySum xs

-- | Safely take the first element of a list. The 'Maybe' result handles
-- the empty case without crashing — Day 5 will cover 'Maybe' properly.
safeHead :: [a] -> Maybe a
safeHead []    = Nothing
safeHead (x:_) = Just x

-- --------------------------------------------------------------------
-- 4. Guards
-- --------------------------------------------------------------------

-- | When the dispatch is on a /condition/ rather than a /shape/, use
-- guards. The vertical bar reads "such that", and the equations are
-- tried top to bottom until one's guard is 'True'.
--
-- 'otherwise' is just @True@ with a friendly name; it is the catch-all.
classify :: Int -> String
classify n
  | n < 0     = "negative"
  | n == 0    = "zero"
  | n < 10    = "small"
  | n < 100   = "medium"
  | otherwise = "large"

-- | Guards combine freely with patterns. Here we pattern-match the list,
-- then use a guard to decide what to do with a non-empty list.
describeList :: [Int] -> String
describeList []  = "empty"
describeList [_] = "singleton"
describeList xs
  | mySum xs > 0 = "non-empty, positive sum"
  | otherwise    = "non-empty, non-positive sum"

-- --------------------------------------------------------------------
-- 5. 'where' clauses
-- --------------------------------------------------------------------

-- | A 'where' clause introduces local bindings /after/ the body that
-- uses them. The names @sumOfSquares@ and @squared@ are visible in
-- the right-hand side of 'rms' and in each other.
--
-- Reading order: top-down for the result, bottom-up for the helpers.
rms :: [Double] -> Double
rms xs = sqrt (sumOfSquares / n)
  where
    sumOfSquares = sum squared
    squared      = map (\x -> x * x) xs
    n            = fromIntegral (length xs)

-- | 'where' bindings can use the function's parameters, and they can
-- be shared across all the guards of one equation. That makes them
-- the natural place to put a value you want to compute once.
bmi :: Double -> Double -> String
bmi weightKg heightM
  | b < 18.5  = "underweight"
  | b < 25.0  = "normal"
  | b < 30.0  = "overweight"
  | otherwise = "obese"
  where
    b = weightKg / (heightM * heightM)

-- --------------------------------------------------------------------
-- 6. 'let ... in ...'
-- --------------------------------------------------------------------

-- | A 'let' is an expression: it introduces local bindings /before/ the
-- body that uses them, and the whole thing is itself a value you can
-- substitute anywhere.
--
-- Use 'let' when you need a name inside one specific expression. Use
-- 'where' when you want the name visible across guards or when the
-- helper is just clutter at the top of the body.
cylinderVolume :: Double -> Double -> Double
cylinderVolume r h =
  let area = pi * r * r
   in area * h

-- --------------------------------------------------------------------
-- 7. 'case ... of'
-- --------------------------------------------------------------------

-- | 'case' is pattern matching as an expression — useful when you want
-- to match on the result of a sub-expression without giving it a name.
firstOrDefault :: a -> [a] -> a
firstOrDefault def xs =
  case xs of
    []    -> def
    (x:_) -> x

-- --------------------------------------------------------------------
-- 8. Putting the pieces together
-- --------------------------------------------------------------------

-- | Average a list of 'Double's, returning 'Nothing' for an empty list.
-- Pattern match to dispatch on shape, 'where' to name the helpers.
average :: [Double] -> Maybe Double
average [] = Nothing
average xs = Just (total / count)
  where
    total = sum xs
    count = fromIntegral (length xs)

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("factorial 6           = " ++ show (factorial 6))
  putStrLn ("fib 10                = " ++ show (fib 10))
  putStrLn ("fstOf (1, 'x')        = " ++ show (fstOf (1 :: Int, 'x')))
  putStrLn ("sumPair (3, 4)        = " ++ show (sumPair (3, 4)))
  putStrLn ("myLength [1..5]       = " ++ show (myLength [1 .. 5 :: Int]))
  putStrLn ("mySum [1..10]         = " ++ show (mySum [1 .. 10]))
  putStrLn ("safeHead []           = " ++ show (safeHead ([] :: [Int])))
  putStrLn ("safeHead [42]         = " ++ show (safeHead [42 :: Int]))
  putStrLn ("classify (-3)         = " ++ classify (-3))
  putStrLn ("classify 0            = " ++ classify 0)
  putStrLn ("classify 7            = " ++ classify 7)
  putStrLn ("classify 250          = " ++ classify 250)
  putStrLn ("describeList []       = " ++ describeList [])
  putStrLn ("describeList [1,2,3]  = " ++ describeList [1, 2, 3])
  putStrLn ("describeList [1,-5]   = " ++ describeList [1, -5])
  putStrLn ("rms [1,2,3,4,5]       = " ++ show (rms [1, 2, 3, 4, 5]))
  putStrLn ("bmi 70 1.75           = " ++ bmi 70 1.75)
  putStrLn ("cylinderVolume 2 5    = " ++ show (cylinderVolume 2 5))
  putStrLn ("firstOrDefault 0 []   = " ++ show (firstOrDefault (0 :: Int) []))
  putStrLn ("firstOrDefault 0 [9]  = " ++ show (firstOrDefault 0 [9 :: Int]))
  putStrLn ("average []            = " ++ show (average []))
  putStrLn ("average [1,2,3,4]     = " ++ show (average [1, 2, 3, 4]))
  putStrLn "Day 4 complete!!!"
