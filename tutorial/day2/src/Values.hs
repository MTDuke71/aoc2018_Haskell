-- | Day 2 — Values, types, and functions.
--
-- Every top-level binding has an explicit type signature. This is the
-- habit we are building: write the type first, then the body.

module Main where

-- --------------------------------------------------------------------
-- Values of each of the basic types
-- --------------------------------------------------------------------

-- | A machine-word-sized signed integer. Same idea as Rust's 'i64' on
-- most platforms. Will overflow silently if you multiply enough big
-- numbers together.
answer :: Int
answer = 42

-- | An arbitrary-precision integer. No overflow, ever — it just grows.
-- Slower than 'Int' but the right default when you are not sure.
bignum :: Integer
bignum = 2 ^ (100 :: Int)

-- | Double-precision floating point. IEEE 754, 64-bit. Same as Rust's 'f64'.
piApprox :: Double
piApprox = 3.141592653589793

-- | A boolean. Only two inhabitants: 'True' and 'False'. Note the capitals.
ready :: Bool
ready = True

-- | A single Unicode character. Written in single quotes.
letterA :: Char
letterA = 'A'

-- | A string. In Haskell, 'String' is literally '[Char]' — a list of
-- characters. Written in double quotes.
motto :: String
motto = "Types first, code second."

-- --------------------------------------------------------------------
-- Functions
-- --------------------------------------------------------------------

-- | Square an 'Int'. One-argument pure function.
square :: Int -> Int
square x = x * x

-- | Cube an 'Int'. Notice we reuse 'square' — functions compose freely.
cube :: Int -> Int
cube x = x * square x

-- | Euclidean distance between the origin and (a, b). Two arguments, both
-- 'Double'. Uses 'sqrt' from the standard Prelude.
hypot :: Double -> Double -> Double
hypot a b = sqrt (a * a + b * b)

-- | Is the number even? Returns a 'Bool'. Uses the prefix function 'mod'
-- as an infix operator by wrapping it in backticks: @n \`mod\` 2@.
isEven :: Int -> Bool
isEven n = n `mod` 2 == 0

-- | Build a loud version of a string.
shout :: String -> String
shout s = s ++ "!!!"

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

-- | Show off each value and function. 'show' turns any value whose type
-- has a 'Show' instance into a 'String' we can print.
main :: IO ()
main = do
  putStrLn ("answer     = " ++ show answer)
  putStrLn ("bignum     = " ++ show bignum)
  putStrLn ("piApprox   = " ++ show piApprox)
  putStrLn ("ready      = " ++ show ready)
  putStrLn ("letterA    = " ++ show letterA)
  putStrLn ("motto      = " ++ motto)
  putStrLn ("square 7   = " ++ show (square 7))
  putStrLn ("cube 3     = " ++ show (cube 3))
  putStrLn ("hypot 3 4  = " ++ show (hypot 3 4))
  putStrLn ("isEven 10  = " ++ show (isEven 10))
  putStrLn (shout "Day 2 complete")
