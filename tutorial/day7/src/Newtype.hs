-- | Day 7 — 'newtype' for type-safe wrappers.
--
-- A function that expects metres and a function that returns seconds
-- both work on 'Double' under the hood. With raw 'Double' the type
-- checker will happily let you pass the wrong one. 'newtype' wraps
-- a single value in a fresh type so the compiler catches the mistake
-- — and it does it at compile time only, with no runtime overhead.

module Main where

-- A 'newtype' has exactly one constructor and exactly one field. The
-- compiler enforces both rules — try to add a second field and it
-- refuses. The benefit is that 'Meters' and 'Seconds' are different
-- types as far as the type checker is concerned, even though both
-- are represented by a 'Double' at runtime.

newtype Meters  = Meters  Double deriving (Show, Eq, Ord)
newtype Seconds = Seconds Double deriving (Show, Eq, Ord)

-- A function that wants metres /requires/ a 'Meters'. Passing a
-- 'Seconds' is a type error caught at compile time.

speed :: Meters -> Seconds -> Double
speed (Meters m) (Seconds s) = m / s   -- result in m/s

-- The unwrap pattern — pattern match on the constructor — is the
-- only way to get the underlying value back out. Records work for
-- newtypes too, and the field accessor doubles as the unwrap helper.

newtype Celsius = Celsius { fromCelsius :: Double } deriving (Show, Eq, Ord)

toFahrenheit :: Celsius -> Double
toFahrenheit c = fromCelsius c * 9 / 5 + 32

-- Why bother? Two reasons that pay off in real code:
--
--   1. /Documentation in the signature/. 'speed :: Meters -> Seconds
--      -> Double' tells you the units; 'speed :: Double -> Double ->
--      Double' tells you nothing.
--
--   2. /Compile-time prevention of unit mix-ups/. Pass a 'Seconds'
--      where 'Meters' was expected and the build fails with
--      "Couldn't match expected type 'Meters' with actual type
--      'Seconds'". The cost is one constructor wrap at the boundary;
--      after that the wrapper is invisible to the runtime.
--
-- AoC use: wrap a row index and a column index as separate newtypes
-- so the grid code cannot transpose them by accident.

main :: IO ()
main = do
  let d = Meters 100
      t = Seconds 9.58
  putStrLn ("speed 100m 9.58s            = "
           ++ show (speed d t) ++ " m/s")
  putStrLn ("toFahrenheit (Celsius 100)  = "
           ++ show (toFahrenheit (Celsius 100)))
  -- The line below, if uncommented, is a compile-time type error:
  --   speed t d
  -- "Couldn't match expected type 'Meters' with actual type 'Seconds'"
  putStrLn "Day 7 (Newtype) complete!!!"
