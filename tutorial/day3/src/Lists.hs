-- | Day 3 — Lists and the list toolkit.
--
-- Everything in this file uses only the Prelude (no imports). We build
-- lists, take them apart, transform them, and reduce them.
--
-- Concepts introduced this day:
--   * The list type '[a]' and list literals
--   * Cons (:) and append (++)
--   * Ranges: [1..10], [2, 4..20], ['a'..'z']
--   * length, null, reverse, head, last
--   * sum, product, minimum, maximum
--   * map and filter, plus operator "sections" like (*2) and (> 5)
--   * lines and words on strings
--   * List comprehensions

module Main where

-- --------------------------------------------------------------------
-- List literals
-- --------------------------------------------------------------------

-- | A short list of 'Int'. Haskell writes list literals with square
-- brackets and commas. The type is @[Int]@ — "list of Int".
primes :: [Int]
primes = [2, 3, 5, 7, 11, 13]

-- | The empty list. '[]' is polymorphic on its own, so the signature is
-- what pins it down to @[Int]@.
noInts :: [Int]
noInts = []

-- | A 'String' is literally @[Char]@, so every list function works on
-- it too. Double-quoted string syntax is a shorthand for a list of
-- 'Char's: @"hi" == ['h', 'i']@.
greeting :: String
greeting = "hello"

-- --------------------------------------------------------------------
-- Building lists: cons (:) and append (++)
-- --------------------------------------------------------------------

-- | @(:)@ is "cons" — it prepends one element onto an existing list.
-- Its type is @a -> [a] -> [a]@. Reads "element, then rest."
withZero :: [Int]
withZero = 0 : primes

-- | @(++)@ concatenates two lists. Type: @[a] -> [a] -> [a]@.
allDigits :: [Int]
allDigits = [0, 1, 2, 3, 4] ++ [5, 6, 7, 8, 9]

-- --------------------------------------------------------------------
-- Ranges
-- --------------------------------------------------------------------

-- | @[low..high]@ is an inclusive range.
oneToTen :: [Int]
oneToTen = [1 .. 10]

-- | @[first, second..last]@ — range with a step. The step is inferred
-- from the difference between the first two elements.
evensTo20 :: [Int]
evensTo20 = [2, 4 .. 20]

-- | Ranges work on anything in the 'Enum' class, including 'Char'.
alphabet :: String
alphabet = ['a' .. 'z']

-- --------------------------------------------------------------------
-- Simple queries
-- --------------------------------------------------------------------

-- | How many elements? 'length' specialised to lists is @[a] -> Int@.
primeCount :: Int
primeCount = length primes

-- | Is the list empty? 'null' specialised to lists is @[a] -> Bool@.
isEmpty :: Bool
isEmpty = null noInts

-- | Reverse a list. @reverse :: [a] -> [a]@.
primesDescending :: [Int]
primesDescending = reverse primes

-- | First element. 'head' is /partial/ — it crashes on @[]@. We will
-- fix that properly with 'Maybe' on Day 5.
firstPrime :: Int
firstPrime = head primes

-- --------------------------------------------------------------------
-- Numeric reductions
-- --------------------------------------------------------------------

-- These all collapse a list to a single value.
--   sum     :: Num a => [a] -> a
--   product :: Num a => [a] -> a
--   minimum :: Ord a => [a] -> a   (crashes on [])
--   maximum :: Ord a => [a] -> a   (crashes on [])

sumPrimes :: Int
sumPrimes = sum primes

productPrimes :: Int
productPrimes = product primes

biggest :: Int
biggest = maximum primes

smallest :: Int
smallest = minimum primes

-- --------------------------------------------------------------------
-- map — apply a function to every element
-- --------------------------------------------------------------------

-- @map :: (a -> b) -> [a] -> [b]@

-- | Double every prime. '(* 2)' is an "operator section" — it is the
-- function @\\x -> x * 2@ with the left argument missing.
doubled :: [Int]
doubled = map (* 2) primes

-- | Square every prime, using a locally-defined helper introduced in a
-- 'where' clause (same trick as Day 2).
squared :: [Int]
squared = map square primes
  where
    square :: Int -> Int
    square x = x * x

-- | 'show' turns any showable value into a 'String'; 'map show' turns a
-- list of showables into a list of strings.
shoutedDigits :: [String]
shoutedDigits = map show allDigits

-- --------------------------------------------------------------------
-- filter — keep the elements that satisfy a predicate
-- --------------------------------------------------------------------

-- @filter :: (a -> Bool) -> [a] -> [a]@

-- | Only the even primes (there is exactly one, of course).
-- 'even' comes from the Prelude: @even :: Integral a => a -> Bool@.
evenPrimes :: [Int]
evenPrimes = filter even primes

-- | Primes greater than 5. '(> 5)' is another operator section —
-- the function @\\x -> x > 5@.
bigPrimes :: [Int]
bigPrimes = filter (> 5) primes

-- --------------------------------------------------------------------
-- Strings are lists: lines and words
-- --------------------------------------------------------------------

-- | A multi-line blob. '\n' is a single character — a newline.
sampleText :: String
sampleText = "one two three\nfour five\nsix"

-- | 'lines' splits a 'String' at every @\\n@.
--   @lines :: String -> [String]@
textLines :: [String]
textLines = lines sampleText

-- | 'words' splits a 'String' on any run of whitespace.
--   @words :: String -> [String]@
firstLineWords :: [String]
firstLineWords = words (head textLines)

-- --------------------------------------------------------------------
-- List comprehensions
-- --------------------------------------------------------------------

-- The general shape is
--   [ expression | generator, guard, generator, guard, ... ]
-- Read it as "the list of @expression@ such that ..." — set-builder
-- notation from maths class.

-- | Squares of 1..10.
squaresTo10 :: [Int]
squaresTo10 = [ x * x | x <- [1 .. 10] ]

-- | Squares of the /even/ numbers in 1..10.
evenSquares :: [Int]
evenSquares = [ x * x | x <- [1 .. 10], even x ]

-- | Every @(x, y)@ with @x, y@ drawn from 1..3. The cartesian product.
pairs :: [(Int, Int)]
pairs = [ (x, y) | x <- [1 .. 3], y <- [1 .. 3] ]

-- | Pythagorean triples with @c <= 20@ and @a <= b <= c@.
pythag :: [(Int, Int, Int)]
pythag =
  [ (a, b, c)
  | c <- [1 .. 20]
  , b <- [1 .. c]
  , a <- [1 .. b]
  , a * a + b * b == c * c
  ]

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("primes            = " ++ show primes)
  putStrLn ("greeting          = " ++ show greeting)
  putStrLn ("withZero          = " ++ show withZero)
  putStrLn ("allDigits         = " ++ show allDigits)
  putStrLn ("oneToTen          = " ++ show oneToTen)
  putStrLn ("evensTo20         = " ++ show evensTo20)
  putStrLn ("alphabet          = " ++ show alphabet)
  putStrLn ("primeCount        = " ++ show primeCount)
  putStrLn ("isEmpty           = " ++ show isEmpty)
  putStrLn ("primesDescending  = " ++ show primesDescending)
  putStrLn ("firstPrime        = " ++ show firstPrime)
  putStrLn ("sumPrimes         = " ++ show sumPrimes)
  putStrLn ("productPrimes     = " ++ show productPrimes)
  putStrLn ("biggest           = " ++ show biggest)
  putStrLn ("smallest          = " ++ show smallest)
  putStrLn ("doubled           = " ++ show doubled)
  putStrLn ("squared           = " ++ show squared)
  putStrLn ("shoutedDigits     = " ++ show shoutedDigits)
  putStrLn ("evenPrimes        = " ++ show evenPrimes)
  putStrLn ("bigPrimes         = " ++ show bigPrimes)
  putStrLn ("textLines         = " ++ show textLines)
  putStrLn ("firstLineWords    = " ++ show firstLineWords)
  putStrLn ("squaresTo10       = " ++ show squaresTo10)
  putStrLn ("evenSquares       = " ++ show evenSquares)
  putStrLn ("pairs             = " ++ show pairs)
  putStrLn ("pythag            = " ++ show pythag)
  putStrLn "Day 3 complete!!!"
