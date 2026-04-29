-- | Tests for "AoC.Parsing".
--
-- The module name (@AoC.ParsingSpec@) and file path
-- (@test/AoC/ParsingSpec.hs@) must match. hspec-discover finds this
-- file because it ends in @Spec.hs@.

module AoC.ParsingSpec (spec) where

import Test.Hspec
import AoC.Parsing (parseChange, parseInput)

spec :: Spec
spec = do
  describe "parseChange" $ do
    it "strips a leading + and reads the rest" $
      parseChange "+7" `shouldBe` 7

    it "passes a leading - through unchanged" $
      parseChange "-3" `shouldBe` (-3)

    it "reads a bare integer with no sign" $
      parseChange "42" `shouldBe` 42

  describe "parseInput" $ do
    it "splits on newlines and parses each line" $
      parseInput "+1\n-2\n+3\n" `shouldBe` [1, -2, 3]

    it "is empty for an empty string" $
      parseInput "" `shouldBe` []

    it "tolerates a missing trailing newline" $
      parseInput "+1\n-2\n+3" `shouldBe` [1, -2, 3]
