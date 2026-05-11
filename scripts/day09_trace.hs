{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | One-off diagnostic: run a 9-player, 25-marble game (matches the
-- worked example in the puzzle text) and print the contents of the
-- @nxt@, @prv@, and @scores@ arrays at the moments just after marbles
-- 22, 23, 24, and 25 have been placed.
--
-- Run from the repo root:
--
--     runghc scripts/day09_trace.hs

module Main where

import           Control.Monad      (forM_, when)
import           Control.Monad.ST   (ST, runST)
import           Data.Array.ST      (STUArray, newArray, readArray,
                                     writeArray)
import           Data.STRef         (modifySTRef', newSTRef, readSTRef)

main :: IO ()
main = do
  let dumps = runST (playWithDumps 9 25 [22, 23, 24, 25])
  forM_ dumps $ \(m, current, nxtList, prvList, scoresList, circle) -> do
    putStrLn ("=== After marble " ++ show m ++ " placed ===")
    putStrLn ("  current marble : " ++ show current)
    putStrLn ("  circle (cw from 0): " ++ show circle)
    printRow "  index" [0..25]
    printRow "  nxt  " nxtList
    printRow "  prv  " prvList
    putStrLn ("  scores (player 0..8): " ++ show scoresList)
    putStrLn ""

printRow :: String -> [Int] -> IO ()
printRow label xs =
  putStrLn (label ++ " :" ++ concatMap (\n -> pad 3 (show n)) xs)
  where pad k s = replicate (k - length s) ' ' ++ s

-- | Walk @nxt@ clockwise from marble 0 until we wrap back to 0.
walkCircle :: STUArray s Int Int -> ST s [Int]
walkCircle nxt = go 0 [0]
  where
    go !i acc = do
      j <- readArray nxt i
      if j == 0 then return (reverse acc) else go j (j : acc)

-- | Snapshot a range of an array as a plain list.
snapshotArr :: STUArray s Int Int -> Int -> Int -> ST s [Int]
snapshotArr arr lo hi = mapM (readArray arr) [lo .. hi]

-- | Same simulation as 'Day09.playST', plus per-marble snapshot capture.
playWithDumps
  :: forall s. Int -> Int -> [Int]
  -> ST s [(Int, Int, [Int], [Int], [Int], [Int])]
playWithDumps players lastM marblesToSnap = do
  nxt    <- newArray (0, lastM)       0 :: ST s (STUArray s Int Int)
  prv    <- newArray (0, lastM)       0 :: ST s (STUArray s Int Int)
  scores <- newArray (0, players - 1) 0 :: ST s (STUArray s Int Int)
  dumpsRef <- newSTRef []

  let stepBack !i 0  = return i
      stepBack !i !k = do
        p <- readArray prv i
        stepBack p (k - 1)

      maybeSnap !marble !current =
        when (marble `elem` marblesToSnap) $ do
          nxtList    <- snapshotArr nxt    0 lastM
          prvList    <- snapshotArr prv    0 lastM
          scoresList <- snapshotArr scores 0 (players - 1)
          circle     <- walkCircle nxt
          modifySTRef' dumpsRef
            ((marble, current, nxtList, prvList, scoresList, circle) :)

      go !current !marble
        | marble > lastM = return ()
        | marble `mod` 23 == 0 = do
            target <- stepBack current 7
            tprev  <- readArray prv target
            tnext  <- readArray nxt target
            writeArray nxt tprev tnext
            writeArray prv tnext tprev
            let player = (marble - 1) `mod` players
            cur <- readArray scores player
            writeArray scores player (cur + marble + target)
            maybeSnap marble tnext
            go tnext (marble + 1)
        | otherwise = do
            one <- readArray nxt current
            two <- readArray nxt one
            writeArray nxt one    marble
            writeArray prv marble one
            writeArray nxt marble two
            writeArray prv two    marble
            maybeSnap marble marble
            go marble (marble + 1)

  when (lastM >= 1) (go 0 1)
  reverse <$> readSTRef dumpsRef
