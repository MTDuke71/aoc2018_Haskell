-- | Day 7 — Your own data types and records.
--
-- Tuples carry you for a while, but the moment you have more than two
-- or three values, or the moment two of them have the same type, the
-- meaning leaks out: '(Int, Int, Int)' tells you nothing about what
-- those numbers /are/. 'data' types let you give shape and name to
-- problem state. Records put names on the fields too, so
-- 'playerHealth p' beats 'snd (snd p)' every time.

module Main where

import Data.List (foldl')

-- --------------------------------------------------------------------
-- 1. A sum type — one of these, exactly
-- --------------------------------------------------------------------
--
-- 'data' followed by a name introduces a new type. The right-hand
-- side lists the /constructors/ separated by '|'. Each constructor is
-- a value of the new type. With no fields, it is the Haskell version
-- of a C-style enum.

data Direction = North | East | South | West
  deriving (Show, Eq)

-- Pattern matching on a sum type is exhaustive — the compiler warns
-- you if you forget a case. (Compile with -Wall to see the warning
-- when a constructor is missed.)

opposite :: Direction -> Direction
opposite North = South
opposite South = North
opposite East  = West
opposite West  = East

-- --------------------------------------------------------------------
-- 2. A product type — these /and/ these /and/ these
-- --------------------------------------------------------------------
--
-- A constructor with arguments builds a "product" — a value that
-- carries several pieces at once. The simplest form is positional.

data Vec2 = Vec2 Int Int
  deriving (Show, Eq)

-- Build values by applying the constructor as if it were a function:
-- 'Vec2 3 4' has type 'Vec2'. Take them apart by pattern matching
-- with the same shape.

addVec :: Vec2 -> Vec2 -> Vec2
addVec (Vec2 ax ay) (Vec2 bx by) = Vec2 (ax + bx) (ay + by)

-- --------------------------------------------------------------------
-- 3. Records — product types with named fields
-- --------------------------------------------------------------------
--
-- Once you have more than two fields, positional constructors become
-- a chore: which Int is health, which is score? Record syntax names
-- each field and gives you accessor functions for free.

data Player = Player
  { playerName   :: String
  , playerHealth :: Int
  , playerScore  :: Int
  } deriving (Show, Eq)

-- Record syntax gives you three things in one declaration:
--   1. The type 'Player'.
--   2. The constructor 'Player' (you can still write
--      'Player "Alice" 100 0' positionally if you want).
--   3. One accessor function per field:
--        playerName   :: Player -> String
--        playerHealth :: Player -> Int
--        playerScore  :: Player -> Int
--
-- Build a player using record syntax. Reads top-to-bottom, no
-- positional ambiguity.

alice :: Player
alice = Player
  { playerName   = "Alice"
  , playerHealth = 100
  , playerScore  = 0
  }

-- --------------------------------------------------------------------
-- 4. Record update syntax
-- --------------------------------------------------------------------
--
-- Haskell records are immutable. "Updating" means producing a /new/
-- value with some fields changed. The syntax is 'r { field = value }'.

heal :: Int -> Player -> Player
heal n p = p { playerHealth = playerHealth p + n }

scorePoint :: Player -> Player
scorePoint p = p { playerScore = playerScore p + 1 }

-- You can update several fields at once:
resetPlayer :: Player -> Player
resetPlayer p = p { playerHealth = 100, playerScore = 0 }

-- --------------------------------------------------------------------
-- 5. 'deriving' — free instances for common type classes
-- --------------------------------------------------------------------
--
-- 'deriving (Show, Eq, Ord)' tells the compiler to write the
-- mechanical instances for you:
--   * Show -> printable representation, used by 'print' and 'show'.
--   * Eq   -> the '==' and '/=' operators.
--   * Ord  -> '<', '<=', 'compare', and friends.
-- The derived ordering for product types is /lexicographic/: compare
-- the first field, break ties on the second, and so on. The order in
-- the 'data' declaration matters.

data Score = Score
  { scorePlayer :: String
  , scorePoints :: Int
  } deriving (Show, Eq, Ord)

leaderboard :: [Score]
leaderboard =
  [ Score "Alice" 12
  , Score "Bob"   18
  , Score "Carol" 7
  ]

-- The derived 'Ord' compares names first, points second — rarely what
-- you want for a leaderboard. Easy to fix without changing the type:
-- fold to find the max-by-points yourself. (This reuses the strict
-- left fold from Day 6.)

topScore :: [Score] -> Maybe Score
topScore []     = Nothing
topScore (x:xs) = Just (foldl' best x xs)
  where
    best :: Score -> Score -> Score
    best b s
      | scorePoints s > scorePoints b = s
      | otherwise                     = b

-- --------------------------------------------------------------------
-- 6. Sum + product together — a tagged union
-- --------------------------------------------------------------------
--
-- You can mix the two. Each constructor of a sum type can carry its
-- own bundle of fields. This is exactly Rust's enum-with-data, and it
-- is the idiomatic way to model "one of several shapes" in Haskell.

data Shape
  = Circle Double                 -- radius
  | Rectangle Double Double       -- width, height
  | Triangle Double Double Double -- side a, b, c
  deriving (Show, Eq)

area :: Shape -> Double
area (Circle r)       = pi * r * r
area (Rectangle w h)  = w * h
area (Triangle a b c) =
  let s = (a + b + c) / 2
   in sqrt (s * (s - a) * (s - b) * (s - c))

-- --------------------------------------------------------------------
-- 7. Type aliases vs newtypes vs data
-- --------------------------------------------------------------------
--
-- Three flavours of "I want to talk about a type":
--
--   type    Name = String
--          A pure synonym. 'Name' and 'String' are interchangeable —
--          the compiler does not separate them. Use for documentation
--          inside type signatures.
--
--   newtype Username = Username String
--          A genuinely distinct type at compile time, but with zero
--          runtime cost (compiles to the same representation as the
--          wrapped type). Exactly one constructor, exactly one field.
--          See Newtype.hs for why you reach for this.
--
--   data    User = User { userName :: String, userAge :: Int }
--          A full algebraic type. Multiple fields and/or multiple
--          constructors are allowed. Pays the cost of a real heap
--          object, but unlocks records, sum types, and everything
--          else this file demonstrates.

type Name = String

greet :: Name -> String
greet n = "Hello, " ++ n

-- 'Name' and 'String' are the same type. 'greet "Alice"' is fine. We
-- use the synonym only for readability inside signatures.

-- --------------------------------------------------------------------
-- Entry point
-- --------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn ("opposite North         = " ++ show (opposite North))
  putStrLn ("Vec2 1 2 + Vec2 3 4    = " ++ show (addVec (Vec2 1 2) (Vec2 3 4)))
  putStrLn ""
  putStrLn ("alice                  = " ++ show alice)
  putStrLn ("playerName alice       = " ++ show (playerName alice))
  putStrLn ("playerHealth alice     = " ++ show (playerHealth alice))
  putStrLn ""
  putStrLn ("heal 10 alice          = " ++ show (heal 10 alice))
  putStrLn ("scorePoint alice       = " ++ show (scorePoint alice))
  putStrLn ("resetPlayer wounded    = "
           ++ show (resetPlayer (alice { playerHealth = 5, playerScore = 99 })))
  putStrLn ""
  putStrLn ("leaderboard            = " ++ show leaderboard)
  putStrLn ("topScore leaderboard   = " ++ show (topScore leaderboard))
  putStrLn ""
  putStrLn ("area (Circle 1)        = " ++ show (area (Circle 1)))
  putStrLn ("area (Rectangle 3 4)   = " ++ show (area (Rectangle 3 4)))
  putStrLn ("area (Triangle 3 4 5)  = " ++ show (area (Triangle 3 4 5)))
  putStrLn ""
  putStrLn (greet "Alice")
  putStrLn "Day 7 (Records) complete!!!"
