-- | Tests for Day 12 -- Subterranean Sustainability.

module Day12Spec (spec) where

import qualified Data.Set      as Set
import           Test.Hspec
import           Day12

spec :: Spec
spec = describe "Day 12 (Subterranean Sustainability)" $ do

  describe "parseInput" $ do
    it "extracts the initial live pots from the example header" $ do
      let p = parseInput exampleInput
      initial p `shouldBe` Set.fromList [0, 3, 5, 8, 9, 16, 17, 18, 22, 23, 24]
    it "keeps only rules whose RHS is '#'" $ do
      let p = parseInput exampleInput
      Set.size (rules p) `shouldBe` 14  -- the 14 productive rules in the worked example
    it "drops rules whose RHS is '.'" $ do
      -- Add a no-op rule and make sure it isn't recorded.
      let extra = exampleInput ++ "..... => .\n"
          p    = parseInput extra
      ("....." `Set.member` rules p) `shouldBe` False

  describe "window" $ do
    it "is five characters wide" $
      length (window (Set.fromList [0]) 0) `shouldBe` 5
    it "centres on i, reading -2..+2" $
      window (Set.fromList [-1, 0, 2]) 0 `shouldBe` ".##.#"
    it "is all dots when no live pot is within 2" $
      window (Set.fromList [10]) 0 `shouldBe` "....."

  describe "step (one generation of the example)" $ do
    let p     = parseInput exampleInput
        gen1  = step (rules p) (initial p)
    it "produces the gen-1 live set from the puzzle's worked example" $
      -- Row 1 of the puzzle's printed run: "...#...#....#.....#..#..#..#"
      -- Pot positions of those '#'s, starting at -3 in the printout:
      -- index 0 (was offset 3), 4, 9, 15, 18, 21, 24.
      gen1 `shouldBe` Set.fromList [0, 4, 9, 15, 18, 21, 24]

  describe "runFor / part1" $ do
    it "the worked example sums to 325 after 20 generations" $ do
      let p = parseInput exampleInput
      sumPots (runFor (rules p) 20 (initial p)) `shouldBe` 325
    it "part1 on the worked example is 325" $
      part1 (parseInput exampleInput) `shouldBe` 325

  describe "extrapolate" $ do
    it "agrees with runFor on small horizons (target = 20)" $ do
      let p = parseInput exampleInput
      extrapolate (rules p) 20 (initial p)
        `shouldBe` sumPots (runFor (rules p) 20 (initial p))
    it "agrees with runFor on small horizons (target = 50)" $ do
      let p = parseInput exampleInput
      extrapolate (rules p) 50 (initial p)
        `shouldBe` sumPots (runFor (rules p) 50 (initial p))
    it "target = 0 returns the initial sum" $ do
      let p = parseInput exampleInput
      extrapolate (rules p) 0 (initial p) `shouldBe` sumPots (initial p)

  describe "normalize" $ do
    it "translates the leftmost live pot to 0" $
      normalize (Set.fromList [3, 7, 10])
        `shouldBe` Set.fromList [0, 4, 7]
    it "is identity on a set that already starts at 0" $
      normalize (Set.fromList [0, 4, 7])
        `shouldBe` Set.fromList [0, 4, 7]
    it "handles the empty set" $
      normalize Set.empty `shouldBe` Set.empty

  describe "actual puzzle input (inputs/day12.txt)" $ do
    it "Part 1 matches the pinned answer" $ do
      raw <- readFile "inputs/day12.txt"
      part1 (parseInput raw) `shouldBe` expectedPart1
    it "Part 2 matches the pinned answer" $ do
      raw <- readFile "inputs/day12.txt"
      part2 (parseInput raw) `shouldBe` expectedPart2

-- | The puzzle's worked example, verbatim.
exampleInput :: String
exampleInput = unlines
  [ "initial state: #..#.#..##......###...###"
  , ""
  , "...## => #"
  , "..#.. => #"
  , ".#... => #"
  , ".#.#. => #"
  , ".#.## => #"
  , ".##.. => #"
  , ".#### => #"
  , "#.#.# => #"
  , "#.### => #"
  , "##.#. => #"
  , "##.## => #"
  , "###.. => #"
  , "###.# => #"
  , "####. => #"
  ]

-- | Pinned regression value for Part 1 on the actual input.
--   Sum of plant-pot indices after 20 generations.
expectedPart1 :: Int
expectedPart1 = 3230

-- | Pinned regression value for Part 2 on the actual input.
--   Sum of plant-pot indices after 50,000,000,000 generations,
--   computed by detecting the period-1 translating fixed point
--   (which on this input emerges in well under 200 generations).
expectedPart2 :: Int
expectedPart2 = 4400000000304
