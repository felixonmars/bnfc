{-# LANGUAGE CPP #-}
#if __GLASGOW_HASKELL__ <= 708
{-# LANGUAGE OverlappingInstances #-}
#endif
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}

-- | Pretty-printer for PrintBNF.
--   Generated by the BNF converter.

module PrintBNF where

import qualified AbsBNF
import Data.Char

-- | The top-level printing method.

printTree :: Print a => a -> String
printTree = render . prt 0

type Doc = [ShowS] -> [ShowS]

doc :: ShowS -> Doc
doc = (:)

render :: Doc -> String
render d = rend 0 (map ($ "") $ d []) "" where
  rend i ss = case ss of
    "["      :ts -> showChar '[' . rend i ts
    "("      :ts -> showChar '(' . rend i ts
    "{"      :ts -> showChar '{' . new (i+1) . rend (i+1) ts
    "}" : ";":ts -> new (i-1) . space "}" . showChar ';' . new (i-1) . rend (i-1) ts
    "}"      :ts -> new (i-1) . showChar '}' . new (i-1) . rend (i-1) ts
    [";"]        -> showChar ';'
    ";"      :ts -> showChar ';' . new i . rend i ts
    t  : ts@(p:_) | closingOrPunctuation p -> showString t . rend i ts
    t        :ts -> space t . rend i ts
    _            -> id
  new i     = showChar '\n' . replicateS (2*i) (showChar ' ') . dropWhile isSpace
  space t s =
    case (all isSpace t', null spc, null rest) of
      (True , _   , True ) -> []              -- remove trailing space
      (False, _   , True ) -> t'              -- remove trailing space
      (False, True, False) -> t' ++ ' ' : s   -- add space if none
      _                    -> t' ++ s
    where
      t'          = showString t []
      (spc, rest) = span isSpace s

  closingOrPunctuation :: String -> Bool
  closingOrPunctuation [c] = c `elem` closerOrPunct
  closingOrPunctuation _   = False

  closerOrPunct :: String
  closerOrPunct = ")],;"

parenth :: Doc -> Doc
parenth ss = doc (showChar '(') . ss . doc (showChar ')')

concatS :: [ShowS] -> ShowS
concatS = foldr (.) id

concatD :: [Doc] -> Doc
concatD = foldr (.) id

replicateS :: Int -> ShowS -> ShowS
replicateS n f = concatS (replicate n f)

-- | The printer class does the job.

class Print a where
  prt :: Int -> a -> Doc
  prtList :: Int -> [a] -> Doc
  prtList i = concatD . map (prt i)

instance {-# OVERLAPPABLE #-} Print a => Print [a] where
  prt = prtList

instance Print Char where
  prt _ s = doc (showChar '\'' . mkEsc '\'' s . showChar '\'')
  prtList _ s = doc (showChar '"' . concatS (map (mkEsc '"') s) . showChar '"')

mkEsc :: Char -> Char -> ShowS
mkEsc q s = case s of
  _ | s == q -> showChar '\\' . showChar s
  '\\'-> showString "\\\\"
  '\n' -> showString "\\n"
  '\t' -> showString "\\t"
  _ -> showChar s

prPrec :: Int -> Int -> Doc -> Doc
prPrec i j = if j < i then parenth else id

instance Print Integer where
  prt _ x = doc (shows x)
  prtList _ [] = concatD []
  prtList _ [x] = concatD [prt 0 x]
  prtList _ (x:xs) = concatD [prt 0 x, doc (showString ","), prt 0 xs]

instance Print Double where
  prt _ x = doc (shows x)

instance Print AbsBNF.Identifier where
  prt _ (AbsBNF.Identifier (_,i)) = doc $ showString $ i
  prtList _ [x] = concatD [prt 0 x]
  prtList _ (x:xs) = concatD [prt 0 x, doc (showString ","), prt 0 xs]

instance Print AbsBNF.LGrammar where
  prt i e = case e of
    AbsBNF.LGr ldefs -> prPrec i 0 (concatD [prt 0 ldefs])

instance Print AbsBNF.LDef where
  prt i e = case e of
    AbsBNF.DefAll def -> prPrec i 0 (concatD [prt 0 def])
    AbsBNF.DefSome identifiers def -> prPrec i 0 (concatD [prt 0 identifiers, doc (showString ":"), prt 0 def])
    AbsBNF.LDefView identifiers -> prPrec i 0 (concatD [doc (showString "views"), prt 0 identifiers])
  prtList _ [] = concatD []
  prtList _ [x] = concatD [prt 0 x]

  prtList _ (x:xs) = concatD [prt 0 x, doc (showString ";"), prt 0 xs]

instance Print [AbsBNF.LDef] where
  prt = prtList

instance Print [AbsBNF.Identifier] where
  prt = prtList

instance Print AbsBNF.Grammar where
  prt i e = case e of
    AbsBNF.Grammar defs -> prPrec i 0 (concatD [prt 0 defs])

instance Print [AbsBNF.Def] where
  prt = prtList

instance Print AbsBNF.Def where
  prt i e = case e of
    AbsBNF.Rule label cat items -> prPrec i 0 (concatD [prt 0 label, doc (showString "."), prt 0 cat, doc (showString "::="), prt 0 items])
    AbsBNF.Comment str -> prPrec i 0 (concatD [doc (showString "comment"), prt 0 str])
    AbsBNF.Comments str1 str2 -> prPrec i 0 (concatD [doc (showString "comment"), prt 0 str1, prt 0 str2])
    AbsBNF.Internal label cat items -> prPrec i 0 (concatD [doc (showString "internal"), prt 0 label, doc (showString "."), prt 0 cat, doc (showString "::="), prt 0 items])
    AbsBNF.Token identifier reg -> prPrec i 0 (concatD [doc (showString "token"), prt 0 identifier, prt 0 reg])
    AbsBNF.PosToken identifier reg -> prPrec i 0 (concatD [doc (showString "position"), doc (showString "token"), prt 0 identifier, prt 0 reg])
    AbsBNF.Entryp identifiers -> prPrec i 0 (concatD [doc (showString "entrypoints"), prt 0 identifiers])
    AbsBNF.Separator minimumsize cat str -> prPrec i 0 (concatD [doc (showString "separator"), prt 0 minimumsize, prt 0 cat, prt 0 str])
    AbsBNF.Terminator minimumsize cat str -> prPrec i 0 (concatD [doc (showString "terminator"), prt 0 minimumsize, prt 0 cat, prt 0 str])
    AbsBNF.Delimiters cat str1 str2 separation minimumsize -> prPrec i 0 (concatD [doc (showString "delimiters"), prt 0 cat, prt 0 str1, prt 0 str2, prt 0 separation, prt 0 minimumsize])
    AbsBNF.Coercions identifier n -> prPrec i 0 (concatD [doc (showString "coercions"), prt 0 identifier, prt 0 n])
    AbsBNF.Rules identifier rhss -> prPrec i 0 (concatD [doc (showString "rules"), prt 0 identifier, doc (showString "::="), prt 0 rhss])
    AbsBNF.Function identifier args exp -> prPrec i 0 (concatD [doc (showString "define"), prt 0 identifier, prt 0 args, doc (showString "="), prt 0 exp])
    AbsBNF.Layout strs -> prPrec i 0 (concatD [doc (showString "layout"), prt 0 strs])
    AbsBNF.LayoutStop strs -> prPrec i 0 (concatD [doc (showString "layout"), doc (showString "stop"), prt 0 strs])
    AbsBNF.LayoutTop -> prPrec i 0 (concatD [doc (showString "layout"), doc (showString "toplevel")])
  prtList _ [] = concatD []
  prtList _ [x] = concatD [prt 0 x]

  prtList _ (x:xs) = concatD [prt 0 x, doc (showString ";"), prt 0 xs]

instance Print AbsBNF.Item where
  prt i e = case e of
    AbsBNF.Terminal str -> prPrec i 0 (concatD [prt 0 str])
    AbsBNF.NTerminal cat -> prPrec i 0 (concatD [prt 0 cat])
  prtList _ [] = concatD []
  prtList _ (x:xs) = concatD [prt 0 x, prt 0 xs]

instance Print [AbsBNF.Item] where
  prt = prtList

instance Print AbsBNF.Cat where
  prt i e = case e of
    AbsBNF.ListCat cat -> prPrec i 0 (concatD [doc (showString "["), prt 0 cat, doc (showString "]")])
    AbsBNF.IdCat identifier -> prPrec i 0 (concatD [prt 0 identifier])

instance Print AbsBNF.Label where
  prt i e = case e of
    AbsBNF.LabNoP labelid -> prPrec i 0 (concatD [prt 0 labelid])
    AbsBNF.LabP labelid profitems -> prPrec i 0 (concatD [prt 0 labelid, prt 0 profitems])
    AbsBNF.LabPF labelid1 labelid2 profitems -> prPrec i 0 (concatD [prt 0 labelid1, prt 0 labelid2, prt 0 profitems])
    AbsBNF.LabF labelid1 labelid2 -> prPrec i 0 (concatD [prt 0 labelid1, prt 0 labelid2])

instance Print AbsBNF.LabelId where
  prt i e = case e of
    AbsBNF.Id identifier -> prPrec i 0 (concatD [prt 0 identifier])
    AbsBNF.Wild -> prPrec i 0 (concatD [doc (showString "_")])
    AbsBNF.ListE -> prPrec i 0 (concatD [doc (showString "["), doc (showString "]")])
    AbsBNF.ListCons -> prPrec i 0 (concatD [doc (showString "("), doc (showString ":"), doc (showString ")")])
    AbsBNF.ListOne -> prPrec i 0 (concatD [doc (showString "("), doc (showString ":"), doc (showString "["), doc (showString "]"), doc (showString ")")])

instance Print AbsBNF.ProfItem where
  prt i e = case e of
    AbsBNF.ProfIt intlists ns -> prPrec i 0 (concatD [doc (showString "("), doc (showString "["), prt 0 intlists, doc (showString "]"), doc (showString ","), doc (showString "["), prt 0 ns, doc (showString "]"), doc (showString ")")])
  prtList _ [x] = concatD [prt 0 x]
  prtList _ (x:xs) = concatD [prt 0 x, prt 0 xs]

instance Print AbsBNF.IntList where
  prt i e = case e of
    AbsBNF.Ints ns -> prPrec i 0 (concatD [doc (showString "["), prt 0 ns, doc (showString "]")])
  prtList _ [] = concatD []
  prtList _ [x] = concatD [prt 0 x]
  prtList _ (x:xs) = concatD [prt 0 x, doc (showString ","), prt 0 xs]

instance Print [Integer] where
  prt = prtList

instance Print [AbsBNF.IntList] where
  prt = prtList

instance Print [AbsBNF.ProfItem] where
  prt = prtList

instance Print AbsBNF.Arg where
  prt i e = case e of
    AbsBNF.Arg identifier -> prPrec i 0 (concatD [prt 0 identifier])
  prtList _ [] = concatD []
  prtList _ (x:xs) = concatD [prt 0 x, prt 0 xs]

instance Print [AbsBNF.Arg] where
  prt = prtList

instance Print AbsBNF.Separation where
  prt i e = case e of
    AbsBNF.SepNone -> prPrec i 0 (concatD [])
    AbsBNF.SepTerm str -> prPrec i 0 (concatD [doc (showString "terminator"), prt 0 str])
    AbsBNF.SepSepar str -> prPrec i 0 (concatD [doc (showString "separator"), prt 0 str])

instance Print [String] where
  prt = prtList

instance Print AbsBNF.Exp where
  prt i e = case e of
    AbsBNF.Cons exp1 exp2 -> prPrec i 0 (concatD [prt 1 exp1, doc (showString ":"), prt 0 exp2])
    AbsBNF.App identifier exps -> prPrec i 1 (concatD [prt 0 identifier, prt 2 exps])
    AbsBNF.Var identifier -> prPrec i 2 (concatD [prt 0 identifier])
    AbsBNF.LitInt n -> prPrec i 2 (concatD [prt 0 n])
    AbsBNF.LitChar c -> prPrec i 2 (concatD [prt 0 c])
    AbsBNF.LitString str -> prPrec i 2 (concatD [prt 0 str])
    AbsBNF.LitDouble d -> prPrec i 2 (concatD [prt 0 d])
    AbsBNF.List exps -> prPrec i 2 (concatD [doc (showString "["), prt 0 exps, doc (showString "]")])
  prtList 2 [x] = concatD [prt 2 x]
  prtList 2 (x:xs) = concatD [prt 2 x, prt 2 xs]
  prtList _ [] = concatD []
  prtList _ [x] = concatD [prt 0 x]
  prtList _ (x:xs) = concatD [prt 0 x, doc (showString ","), prt 0 xs]

instance Print [AbsBNF.Exp] where
  prt = prtList

instance Print AbsBNF.RHS where
  prt i e = case e of
    AbsBNF.RHS items -> prPrec i 0 (concatD [prt 0 items])
  prtList _ [x] = concatD [prt 0 x]
  prtList _ (x:xs) = concatD [prt 0 x, doc (showString "|"), prt 0 xs]

instance Print [AbsBNF.RHS] where
  prt = prtList

instance Print AbsBNF.MinimumSize where
  prt i e = case e of
    AbsBNF.MNonempty -> prPrec i 0 (concatD [doc (showString "nonempty")])
    AbsBNF.MEmpty -> prPrec i 0 (concatD [])

instance Print AbsBNF.Reg where
  prt i e = case e of
    AbsBNF.RAlt reg1 reg2 -> prPrec i 0 (concatD [prt 0 reg1, doc (showString "|"), prt 1 reg2])
    AbsBNF.RMinus reg1 reg2 -> prPrec i 1 (concatD [prt 1 reg1, doc (showString "-"), prt 2 reg2])
    AbsBNF.RSeq reg1 reg2 -> prPrec i 2 (concatD [prt 2 reg1, prt 3 reg2])
    AbsBNF.RStar reg -> prPrec i 3 (concatD [prt 3 reg, doc (showString "*")])
    AbsBNF.RPlus reg -> prPrec i 3 (concatD [prt 3 reg, doc (showString "+")])
    AbsBNF.ROpt reg -> prPrec i 3 (concatD [prt 3 reg, doc (showString "?")])
    AbsBNF.REps -> prPrec i 3 (concatD [doc (showString "eps")])
    AbsBNF.RChar c -> prPrec i 3 (concatD [prt 0 c])
    AbsBNF.RAlts str -> prPrec i 3 (concatD [doc (showString "["), prt 0 str, doc (showString "]")])
    AbsBNF.RSeqs str -> prPrec i 3 (concatD [doc (showString "{"), prt 0 str, doc (showString "}")])
    AbsBNF.RDigit -> prPrec i 3 (concatD [doc (showString "digit")])
    AbsBNF.RLetter -> prPrec i 3 (concatD [doc (showString "letter")])
    AbsBNF.RUpper -> prPrec i 3 (concatD [doc (showString "upper")])
    AbsBNF.RLower -> prPrec i 3 (concatD [doc (showString "lower")])
    AbsBNF.RAny -> prPrec i 3 (concatD [doc (showString "char")])

