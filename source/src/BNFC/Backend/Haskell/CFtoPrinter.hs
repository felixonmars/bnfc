{-
    BNF Converter: Pretty-printer generator
    Copyright (C) 2004  Author:  Aarne Ranta

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module BNFC.Backend.Haskell.CFtoPrinter (cf2Printer, compareRules) where

import Prelude hiding ((<>))

import BNFC.Backend.Haskell.Utils
import BNFC.CF
import BNFC.Options (TokenText(..))
import BNFC.Utils

import Data.Char     (toLower)
import Data.Either   (lefts)
import Data.Function (on)
import Data.List     (sortBy, intersperse)

-- import Debug.Trace (trace)
import Text.PrettyPrint

-- AR 15/2/2002

type AbsMod = String

-- | Derive pretty-printer from a BNF grammar.
cf2Printer
  :: TokenText  -- ^ Are identifiers @ByteString@s or @Text@ rather than @String@s?  (Option @--bytestrings@ and @--text@)
  -> Bool    -- ^ Option @--functor@?
  -> Bool    -- ^ @--haskell-gadt@?
  -> String  -- ^ Name of created Haskell module.
  -> AbsMod  -- ^ Name of Haskell module for abstract syntax.
  -> CF      -- ^ Grammar.
  -> String
cf2Printer tokenText functor useGadt name absMod cf = unlines $ concat $
  -- Each of the following list entries is itself a list of lines
  [ prologue tokenText useGadt name absMod
  , integerRule absMod cf
  , doubleRule absMod cf
  , if hasIdent cf then identRule absMod tokenText cf else []
  ] ++ [ ownPrintRule absMod tokenText cf own | (own,_) <- tokenPragmas cf ] ++
  [ rules absMod functor cf
  ]


prologue :: TokenText -> Bool -> String -> AbsMod -> [String]
prologue tokenText useGadt name absMod = concat
  [ [ "{-# LANGUAGE CPP #-}"
    , "#if __GLASGOW_HASKELL__ <= 708"
    , "{-# LANGUAGE OverlappingInstances #-}"
    , "#endif"
    ]
  , [ "{-# LANGUAGE GADTs, TypeSynonymInstances #-}" | useGadt ]
  , [ "{-# LANGUAGE FlexibleInstances #-}"
    , "{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}"
    , ""
    , "-- | Pretty-printer for " ++ takeWhile ('.' /=) name ++ "."
    , "--   Generated by the BNF converter."
    , ""
    , "module " ++ name +++ "where"
    , ""
    , "import qualified " ++ absMod
    , "import Data.Char"
    ]
  , tokenTextImport tokenText
  , [ ""
    , "-- | The top-level printing method."
    , ""
    , "printTree :: Print a => a -> String"
    , "printTree = render . prt 0"
    , ""
    , "type Doc = [ShowS] -> [ShowS]"
    , ""
    , "doc :: ShowS -> Doc"
    , "doc = (:)"
    , ""
    , "render :: Doc -> String"
    , "render d = rend 0 (map ($ \"\") $ d []) \"\" where"
    , "  rend i ss = case ss of"
    , "    \"[\"      :ts -> showChar '[' . rend i ts"
    , "    \"(\"      :ts -> showChar '(' . rend i ts"
    , "    \"{\"      :ts -> showChar '{' . new (i+1) . rend (i+1) ts"
    , "    \"}\" : \";\":ts -> new (i-1) . space \"}\" . showChar ';' . new (i-1) . rend (i-1) ts"
    , "    \"}\"      :ts -> new (i-1) . showChar '}' . new (i-1) . rend (i-1) ts"
    , "    [\";\"]        -> showChar ';'"
    , "    \";\"      :ts -> showChar ';' . new i . rend i ts"
    , "    t  : ts@(p:_) | closingOrPunctuation p -> showString t . rend i ts"
    , "    t        :ts -> space t . rend i ts"
    , "    _            -> id"
    , "  new i     = showChar '\\n' . replicateS (2*i) (showChar ' ') . dropWhile isSpace"
    , "  space t s ="
    , "    case (all isSpace t', null spc, null rest) of"
    , "      (True , _   , True ) -> []              -- remove trailing space"
    , "      (False, _   , True ) -> t'              -- remove trailing space"
    , "      (False, True, False) -> t' ++ ' ' : s   -- add space if none"
    , "      _                    -> t' ++ s"
    , "    where"
    , "      t'          = showString t []"
    , "      (spc, rest) = span isSpace s"
    , ""
    , "  closingOrPunctuation :: String -> Bool"
    , "  closingOrPunctuation [c] = c `elem` closerOrPunct"
    , "  closingOrPunctuation _   = False"
    , ""
    , "  closerOrPunct :: String"
    , "  closerOrPunct = \")],;\""
    , ""
    , "parenth :: Doc -> Doc"
    , "parenth ss = doc (showChar '(') . ss . doc (showChar ')')"
    , ""
    , "concatS :: [ShowS] -> ShowS"
    , "concatS = foldr (.) id"
    , ""
    , "concatD :: [Doc] -> Doc"
    , "concatD = foldr (.) id"
    , ""
    , "replicateS :: Int -> ShowS -> ShowS"
    , "replicateS n f = concatS (replicate n f)"
    , ""
    , "-- | The printer class does the job."
    , ""
    , "class Print a where"
    , "  prt :: Int -> a -> Doc"
    , "  prtList :: Int -> [a] -> Doc"
    , "  prtList i = concatD . map (prt i)"
    , ""
    , "instance {-# OVERLAPPABLE #-} Print a => Print [a] where"
    , "  prt = prtList"
    , ""
    , "instance Print Char where"
    , "  prt _ s = doc (showChar '\\'' . mkEsc '\\'' s . showChar '\\'')"
    , "  prtList _ s = doc (showChar '\"' . concatS (map (mkEsc '\"') s) . showChar '\"')"
    , ""
    , "mkEsc :: Char -> Char -> ShowS"
    , "mkEsc q s = case s of"
    , "  _ | s == q -> showChar '\\\\' . showChar s"
    , "  '\\\\'-> showString \"\\\\\\\\\""
    , "  '\\n' -> showString \"\\\\n\""
    , "  '\\t' -> showString \"\\\\t\""
    , "  _ -> showChar s"
    , ""
    , "prPrec :: Int -> Int -> Doc -> Doc"
    , "prPrec i j = if j < i then parenth else id"
    , ""
    ]
  ]

-- | Printing instance for @Integer@, and possibly @[Integer]@.
integerRule :: AbsMod -> CF -> [String]
integerRule absMod cf = showsPrintRule absMod cf $ TokenCat catInteger

-- | Printing instance for @Double@, and possibly @[Double]@.
doubleRule :: AbsMod -> CF -> [String]
doubleRule absMod cf = showsPrintRule absMod cf $ TokenCat catDouble

showsPrintRule :: AbsMod -> CF -> Cat -> [String]
showsPrintRule absMod cf t =
  [ unwords [ "instance Print" , qualifiedCat absMod t , "where" ]
  , "  prt _ x = doc (shows x)"
  ] ++ ifList cf t ++
  [ ""
  ]

-- | Print category (data type name) qualified if user-defined.
--
qualifiedCat :: AbsMod -> Cat -> String
qualifiedCat absMod t = case t of
  TokenCat s
    | s `elem` baseTokenCatNames -> unqualified
    | otherwise                  -> qualified
  Cat{}       -> qualified
  ListCat c   -> concat [ "[", qualifiedCat absMod c, "]" ]
  CoercCat{}  -> impossible
  where
  unqualified = catToStr t
  qualified   = qualify absMod unqualified
  impossible  = error $ "impossible in Backend.Haskell.CFtoPrinter.qualifiedCat: " ++ show t

qualify :: AbsMod -> String -> String
qualify absMod s = concat [ absMod, "." , s ]

-- | Printing instance for @Ident@, and possibly @[Ident]@.
identRule :: AbsMod -> TokenText -> CF -> [String]
identRule absMod tokenText cf = ownPrintRule absMod tokenText cf catIdent

-- | Printing identifiers and terminals.
ownPrintRule :: AbsMod -> TokenText -> CF -> TokenCat -> [String]
ownPrintRule absMod tokenText cf own = concat
  [ [ "instance Print " ++ q ++ " where"
    , "  prt _ (" ++ q ++ posn ++ ") = doc $ showString $ " ++ tokenTextUnpack tokenText "i"
    ]
  , ifList cf (TokenCat own)
  , [ ""
    ]
  ]
 where
   q    = qualifiedCat absMod $ TokenCat own
   posn = if isPositionCat cf own then " (_,i)" else " i"

-- | Printing rules for the AST nodes.
rules :: AbsMod -> Bool -> CF -> [String]
rules absMod functor cf = do
    (cat, xs :: [(Fun, [Cat])]) <- cf2dataLists cf
    [ render (case_fun absMod functor cat (map (toArgs cat) xs)) ] ++ ifList cf cat ++ [ "" ]
  where
    toArgs :: Cat -> (Fun, [Cat]) -> Rule
    toArgs cat (cons, _) =
      case filter (\ (Rule f c _rhs _internal) -> cons == funName f && cat == normCat (wpThing c)) (cfgRules cf)
      of
        (r : _) -> r
        -- 2018-01-14:  Currently, there can be overlapping rules like
        --   Foo. Bar ::= "foo" ;
        --   Foo. Bar ::= "bar" ;
        -- Of course, this will generate an arbitary printer for @Foo@.
        [] -> error $ "CFToPrinter.rules: no rhs found for: " ++ cons ++ ". " ++ show cat ++ " ::= ?"

-- |
-- >>> case_fun "Abs" False (Cat "A") [ (npRule "AA" (Cat "AB") [Right "xxx"]) Parsable ]
-- instance Print Abs.A where
--   prt i e = case e of
--     Abs.AA -> prPrec i 0 (concatD [doc (showString "xxx")])
case_fun :: AbsMod -> Bool -> Cat -> [Rule] -> Doc
case_fun absMod functor cat xs =
  -- trace ("case_fun: cat = " ++ show cat) $
  -- trace ("case_fun: xs  = " ++ show xs ) $
  vcat
    [ "instance Print" <+> type_ <+> "where"
    , nest 2 $ if isList cat then "prt = prtList" else vcat
        [ "prt i e = case e of"
        , nest 2 $ vcat (map (mkPrintCase absMod functor) xs)
        ]
    ]
  where
    type_
     | functor   = case cat of
         ListCat{}  -> type' cat
         _ -> parens $ type' cat
     | otherwise = text (qualifiedCat absMod cat)
    type' = \case
      ListCat c    -> "[" <> type' c <> "]"
      c@TokenCat{} -> text (qualifiedCat absMod c)
      c            -> text (qualifiedCat absMod c) <+> "a"

-- | When writing the Print instance for a category (in case_fun), we have
-- a different case for each constructor for this category.
--
-- >>> mkPrintCase "Abs" False (npRule "AA" (Cat "A") [Right "xxx"] Parsable)
-- Abs.AA -> prPrec i 0 (concatD [doc (showString "xxx")])
--
-- Coercion levels are passed to @prPrec@.
--
-- >>> mkPrintCase "Abs" False (npRule "EInt" (CoercCat "Expr" 2) [Left (TokenCat "Integer")] Parsable)
-- Abs.EInt n -> prPrec i 2 (concatD [prt 0 n])
--
-- >>> mkPrintCase "Abs" False (npRule "EPlus" (CoercCat "Expr" 1) [Left (Cat "Expr"), Right "+", Left (Cat "Expr")] Parsable)
-- Abs.EPlus expr1 expr2 -> prPrec i 1 (concatD [prt 0 expr1, doc (showString "+"), prt 0 expr2])
--
-- If the AST is a functor, ignore first argument.
--
-- >>> mkPrintCase "Abs" True (npRule "EInt" (CoercCat "Expr" 2) [Left (TokenCat "Integer")] Parsable)
-- Abs.EInt _ n -> prPrec i 2 (concatD [prt 0 n])
--
-- Skip internal categories.
--
-- >>> mkPrintCase "Abs" True $ npRule "EInternal" (Cat "Expr") [Left (Cat "Expr")] Internal
-- Abs.EInternal _ expr -> prPrec i 0 (concatD [prt 0 expr])
--
mkPrintCase :: AbsMod -> Bool -> Rule -> Doc
mkPrintCase absMod functor (Rule f cat rhs _internal) =
    pattern <+> "->"
    <+> "prPrec i" <+> integer (precCat $ wpThing cat) <+> parens (mkRhs (map render variables) rhs)
  where
    pattern :: Doc
    pattern
      | isOneFun  f = text "[" <+> head variables <+> "]"
      | isConsFun f = hsep $ intersperse (text ":") variables
      | otherwise   = text (qualify absMod $ funName f) <+> (if functor then "_" else empty) <+> hsep variables
    -- Creating variables names used in pattern matching. In addition to
    -- haskell's reserved words, `e` and `i` are used in the printing function
    -- and should be avoided
    names = map var (lefts rhs)
    variables :: [Doc]
    variables = map text $ mkNames ("e" : "i" : hsReservedWords) LowerCase names
    var (ListCat c)  = var c ++ "s"
    var (TokenCat "Ident")   = "id"
    var (TokenCat "Integer") = "n"
    var (TokenCat "String")  = "str"
    var (TokenCat "Char")    = "c"
    var (TokenCat "Double")  = "d"
    var xs = map toLower $ show xs

ifList :: CF -> Cat -> [String]
ifList cf cat =
    -- trace ("ifList cf    = " ++ show cf   ) $
    -- trace ("ifList cat   = " ++ show cat  ) $
    -- trace ("ifList rules = " ++ show rules) $
    -- trace ("ifList rulesForCat' cf (ListCat cat) = " ++ show (rulesForCat' cf (ListCat cat))) $
    -- trace "" $
    map (render . nest 2) cases
  where
    rules = sortBy compareRules $ rulesForNormalizedCat cf (ListCat cat)
    cases = [ mkPrtListCase r | r <- rules ]

-- | Pattern match on the list constructor and the coercion level
--
-- >>> mkPrtListCase (npRule "[]" (ListCat (Cat "Foo")) [] Parsable)
-- prtList _ [] = concatD []
--
-- >>> mkPrtListCase (npRule "(:[])" (ListCat (Cat "Foo")) [Left (Cat "FOO")] Parsable)
-- prtList _ [x] = concatD [prt 0 x]
--
-- >>> mkPrtListCase (npRule "(:)" (ListCat (Cat "Foo")) [Left (Cat "Foo"), Left (ListCat (Cat "Foo"))] Parsable)
-- prtList _ (x:xs) = concatD [prt 0 x, prt 0 xs]
--
-- >>> mkPrtListCase (npRule "[]" (ListCat (CoercCat "Foo" 2)) [] Parsable)
-- prtList 2 [] = concatD []
--
-- >>> mkPrtListCase (npRule "(:[])" (ListCat (CoercCat "Foo" 2)) [Left (CoercCat "Foo" 2)] Parsable)
-- prtList 2 [x] = concatD [prt 2 x]
--
-- >>> mkPrtListCase (npRule "(:)" (ListCat (CoercCat "Foo" 2)) [Left (CoercCat "Foo" 2), Left (ListCat (CoercCat "Foo" 2))] Parsable)
-- prtList 2 (x:xs) = concatD [prt 2 x, prt 2 xs]
--
mkPrtListCase :: Rule -> Doc
mkPrtListCase (Rule f (WithPosition _ (ListCat c)) rhs _internal)
  | isNilFun f = "prtList" <+> precPattern <+> "[]" <+> "=" <+> body
  | isOneFun f = "prtList" <+> precPattern <+> "[x]" <+> "=" <+> body
  | isConsFun f = "prtList" <+> precPattern <+> "(x:xs)" <+> "=" <+> body
  | otherwise = empty -- (++) constructor
  where
    precPattern = case precCat c of 0 -> "_" ; p -> integer p
    body = mkRhs ["x", "xs"] rhs
mkPrtListCase _ = error "mkPrtListCase undefined for non-list categories"


-- | Define an ordering on lists' rules with the following properties:
--
-- - rules with a higher coercion level should come first, i.e. the rules for
--   [Foo3] are before rules for [Foo1] and they are both lower than rules for
--   [Foo].
--
-- - [] < [_] < _:_
--
-- This is desiged to correctly order the rules in the prtList function so that
-- the pattern matching works as expectd.
--
-- >>> compareRules (npRule "[]" (ListCat (CoercCat "Foo" 3)) [] Parsable) (npRule "[]" (ListCat (CoercCat "Foo" 1)) [] Parsable)
-- LT
--
-- >>> compareRules (npRule "[]" (ListCat (CoercCat "Foo" 3)) [] Parsable) (npRule "[]" (ListCat (Cat "Foo")) [] Parsable)
-- LT
--
-- >>> compareRules (npRule "[]" (ListCat (Cat "Foo")) [] Parsable) (npRule "(:[])" (ListCat (Cat "Foo")) [] Parsable)
-- LT
--
-- >>> compareRules (npRule "(:[])" (ListCat (Cat "Foo")) [] Parsable) (npRule "(:)" (ListCat (Cat "Foo")) [] Parsable)
-- LT
--
compareRules :: IsFun f => Rul f -> Rul f -> Ordering
compareRules r1 r2
  | precRule r1 > precRule r2 = LT
  | precRule r1 < precRule r2 = GT
  | otherwise = (compareFunNames `on` (funName . funRule)) r1 r2

compareFunNames :: String -> String -> Ordering
compareFunNames = curry $ \case
  ("[]"    , "[]"   ) -> EQ
  ("[]"    , _      ) -> LT
  ("(:[])" , "[]"   ) -> GT
  ("(:[])" , "(:[])") -> EQ
  ("(:[])" , "(:)"  ) -> LT
  ("(:)"   , "(:)"  ) -> EQ
  ("(:)"   , _      ) -> GT
  (_       , _      ) -> EQ


-- |
--
-- >>> mkRhs ["expr1", "n", "expr2"] [Left (Cat "Expr"), Right "-", Left (TokenCat "Integer"), Left (Cat "Expr")]
-- concatD [prt 0 expr1, doc (showString "-"), prt 0 n, prt 0 expr2]
--
-- Coercions on the right hand side should be passed to prt:
--
-- >>> mkRhs ["expr1"] [Left (CoercCat "Expr" 2)]
-- concatD [prt 2 expr1]
--
-- >>> mkRhs ["expr2s"] [Left (ListCat (CoercCat "Expr" 2))]
-- concatD [prt 2 expr2s]
--
mkRhs :: [String] -> [Either Cat String] -> Doc
mkRhs args its =
  "concatD" <+> brackets (hsep (punctuate "," (mk args its)))
  where
  mk (arg:args) (Left c  : items)    = (prt c <+> text arg) : mk args items
  mk args       (Right s : items)    = ("doc (showString" <+> text (show s) <> ")") : mk args items
  mk _          _                    = []
  prt c = "prt" <+> integer (precCat c)
