{-# LANGUAGE DeriveGeneric #-}

-- |
-- Module      : Day08
-- Description : Day 08 -- Memory Maneuver
--
-- The puzzle input is a single long line of space-separated integers
-- that encodes a tree.  Each node is laid out as
--
--     <numChildren> <numMetaEntries> <child_1> <child_2> ... <meta_1> <meta_2> ...
--
-- where every @<child_i>@ is itself a node in exactly the same shape,
-- recursively.  After all children are consumed, the next
-- @numMetaEntries@ integers are this node's metadata.
--
-- Part 1: sum every metadata entry across the whole tree.
-- Part 2: compute the root node's "value": leaves sum their metadata,
--         internal nodes treat metadata as 1-based indices into their
--         children and sum the referenced children's values (skipping
--         out-of-range / zero indices, double-counting duplicates).
--
-- Concepts introduced this day:
--   * Recursive algebraic data types: 'Tree' refers to itself in its
--     'children' field.  This is the first day where a 'data' declaration
--     describes a recursive structure rather than a flat record / sum.
--   * State-threading by return tuple: instead of mutating a cursor into
--     a list, each parser returns @(result, leftover)@ and the caller
--     feeds @leftover@ to the next parser.  This is the hand-rolled,
--     beginner-friendly version of the @State@ monad we will meet later.
--   * 'splitAt' :: 'Int' -> [a] -> ([a], [a]) -- split a list at an
--     index in one pass, returning both halves.
--   * 'zip' against an infinite list: 'zip [1..] xs' attaches a 1-based
--     index to every element of 'xs'.  Laziness makes this safe even
--     though @[1..]@ is infinite -- 'zip' stops at the shorter input.
--   * 'lookup' :: 'Eq' k => k -> [(k, v)] -> 'Maybe' v -- linear scan of
--     an association list, returning 'Nothing' if the key is missing.
--   * 'mapMaybe' :: (a -> 'Maybe' b) -> [a] -> [b] -- map then drop the
--     'Nothing's, unwrapping each 'Just'.  Cleaner than @catMaybes . map@.

module Day08
  ( Tree (..)
  , parseInput
  , parseTree
  , sumMetadata
  , nodeValue
  , part1
  , part2
  , solve
  ) where

import Control.DeepSeq (NFData)
import Data.Maybe     (mapMaybe)
import GHC.Generics   (Generic)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A node in the license-file tree.  The @children@ field is a list
--   of 'Tree' values, which makes 'Tree' a /recursive/ type: the
--   definition of 'Tree' refers to 'Tree' itself.
--
--   Strict fields (the @!@) avoid building thunks inside the tree as we
--   construct it during parsing.  For Part 1 the laziness wouldn't bite
--   us, but it's a cheap habit to form.
data Tree = Tree
  { children :: ![Tree]
  , metadata :: ![Int]
  } deriving (Eq, Show, Generic)

-- | The empty body uses GHC.Generics to derive a structural 'NFData'
--   instance: every field is recursively forced to normal form.  This
--   is what criterion's 'nf' needs to time the parser without leaving
--   thunks behind in the result.
instance NFData Tree

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- | Tokenise the raw input into a list of 'Int', then parse one tree.
--   'words' splits on any whitespace (including the trailing newline),
--   and 'read' converts each token to 'Int' (will panic on a malformed
--   token, which is fine for trusted AoC input).
--
--   We discard any leftover tokens after the root tree is built; the
--   real input has none, but defensively returning just the root keeps
--   the public API a plain 'Tree'.
parseInput :: String -> Tree
parseInput = fst . parseTree . map read . words

-- | The recursive workhorse.  Given a prefix-encoded token stream,
--   peel off one node and return it together with the unconsumed tail.
--
--   The shape of the recursion mirrors the shape of the data:
--   a node consists of two header ints, then exactly @nChildren@
--   sub-trees (each consumed by a recursive call), then exactly
--   @nMeta@ raw metadata ints (taken directly with 'splitAt').
--
--   Pattern @(nChildren : nMeta : rest0)@ binds the first two tokens
--   and names the rest @rest0@.  We thread that tail through the two
--   sub-parses, picking up new names @rest1@ and @rest2@ as each
--   stage consumes more of it.
parseTree :: [Int] -> (Tree, [Int])
parseTree (nChildren : nMeta : rest0) =
  let (cs,  rest1) = parseChildren nChildren rest0
      (mds, rest2) = splitAt        nMeta    rest1
  in  (Tree cs mds, rest2)
parseTree _ =
  error "Day08.parseTree: ran out of input before reading a node header"

-- | Parse exactly @n@ sibling trees in left-to-right order, threading
--   the leftover tokens between them.  Base case @n == 0@ returns the
--   empty list of children and gives the input back untouched.
parseChildren :: Int -> [Int] -> ([Tree], [Int])
parseChildren 0 xs = ([], xs)
parseChildren n xs =
  let (c,  xs')  = parseTree xs
      (cs, xs'') = parseChildren (n - 1) xs'
  in  (c : cs, xs'')

-- ---------------------------------------------------------------------------
-- Part 1
-- ---------------------------------------------------------------------------

-- | Sum of every metadata entry in the whole tree.
--
--   The function pattern-matches the 'Tree' constructor, sums this
--   node's own metadata, and recursively sums each child.  The two
--   contributions are added; 'sum (map sumMetadata cs)' is the classic
--   "sum of a thing applied to each child" idiom.
sumMetadata :: Tree -> Int
sumMetadata (Tree cs mds) = sum mds + sum (map sumMetadata cs)

part1 :: Tree -> Int
part1 = sumMetadata

-- ---------------------------------------------------------------------------
-- Part 2
-- ---------------------------------------------------------------------------

-- | Recursive node value:
--
--   * A leaf (@children == []@) is the sum of its own metadata.
--   * An internal node treats each metadata entry as a /1-based index/
--     into its child list.  We pair the children with @[1..]@ once,
--     evaluate each child's value once, and look up each metadata
--     index in that association list:
--
--         indexed = zip [1..] (map nodeValue cs)
--         lookup i indexed :: Maybe Int   -- Nothing for 0 or out-of-range
--
--     Mapping @lookup i indexed@ across @mds@ then collecting only the
--     'Just' answers gives exactly the rule "skip references to
--     non-existent children, double-count repeats".  'mapMaybe' does
--     the map-then-drop-Nothing in one pass.
--
--   Why pre-evaluate child values into @indexed@?  Because metadata may
--   reference the same child twice (the spec explicitly says so), and
--   re-recursing would do duplicate work.  Sharing through the @let@
--   binding evaluates each child once.
--
--   HLint will suggest replacing @\\i -> lookup i indexed@ with the
--   point-free @(`lookup` indexed)@ (backtick-infix + right-section).
--   We keep the lambda for teaching clarity and silence that one hint.
{-# ANN nodeValue ("HLint: ignore Avoid lambda using `infix`" :: String) #-}
nodeValue :: Tree -> Int
nodeValue (Tree []  mds) = sum mds
nodeValue (Tree cs  mds) =
  let indexed :: [(Int, Int)]
      indexed = zip [1..] (map nodeValue cs)
  in  sum (mapMaybe (\i -> lookup i indexed) mds)

part2 :: Tree -> Int
part2 = nodeValue

-- ---------------------------------------------------------------------------
-- IO entry point
-- ---------------------------------------------------------------------------

-- | Parse once, print both answers.
solve :: String -> IO ()
solve contents = do
  let tree = parseInput contents
  putStrLn ("  part 1: " ++ show (part1 tree))
  putStrLn ("  part 2: " ++ show (part2 tree))
