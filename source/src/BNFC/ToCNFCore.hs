{-# LANGUAGE TypeSynonymInstances, FlexibleInstances, CPP #-}
{-# LANGUAGE RecordWildCards #-}
{-
    Copyright (C) 2012  Authors:
    Jean-Philippe Bernardy.

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

{-# LANGUAGE OverloadedStrings #-}

module BNFC.ToCNFCore (toCNF, isCat, group', catTag, punctuate', onRules, isUnitRule, splitOptim, second, lookupMulti,
                       Set, CatDescriptions, UnitRel, RHSEl, Exp(..), prettyExp, appMany, app',after)  where

{-

Construction of CYK tables. The algorithm follows:

Lange, Martin; Leiß, Hans (2009), "To CNF or not to CNF? An Efficient
Yet Presentable Version of the CYK Algorithm", Informatica Didactica

-}

import BNFC.CF hiding (App,Exp)
import Control.Monad.RWS
#if __GLASGOW_HASKELL__ < 710
import Control.Applicative hiding (Const)
#endif

import Data.Bifunctor (second)
import Data.Char      (isAlphaNum, ord)
import Data.Function  (on)
import Data.Functor   (($>))
import Data.List      (nub, sortBy, sort)
import Data.Map       (Map)
import qualified Data.Map as Map
import Data.Pair

import Text.PrettyPrint.HughesPJ hiding (first, (<>))

onRules ::([Rul f] -> [Rul g]) -> CFG f -> CFG g
onRules f cfg@CFG{..} = cfg { cfgRules = f cfgRules }

toCNF :: IsFun a => CFG a
      -> (CFG Exp, CFG Exp, UnitRel Cat, CatDescriptions,
          [(Either Cat String, [Either Cat String])])
toCNF cf0 = (cf1,cf2,units,descriptions,neighbors)
  where cf01 = funToExp . onRules (filter isParsable) $ cf0
        (rules',descriptions) = toBin (cfgRules cf01)
        cf1 = cf01 { cfgRules = rules' }
        cf2 = delNull cf1
        units = unitSet cf2
        neighbors = neighborSet cf2

funToExp :: IsFun a => CFG a -> CFG Exp
funToExp = fmap toExp

toExp :: IsFun a => a -> Exp
toExp f | isCoercion f = Id
        | otherwise = Con $ funName f

isCat (Right _) = False
isCat (Left _) = True


group0 :: Eq a => [(a,[b])] -> [(a,[b])]
group0 [] = []
group0 ((a,bs):xs) = (a,bs ++ concatMap snd ys) : group0 zs
  where (ys,zs) = span (\x -> fst x == a) xs

group' :: Ord a => [(a,[b])] -> [(a,[b])]
group' = group0 . sortBy (compare `on` fst)

catTag :: Either Cat String -> Doc
catTag (Left c) = "CAT_" <> text (concatMap escape (show c))
catTag (Right t) = "TOK_" <> text (concatMap escapeToken t)

escape c | isAlphaNum c || c == '_' = [c]
escape '[' = ""
escape ']' = "_List"
escape '{' = "OPEN_"
escape '}' = "CLOS_"
escape '@' = "BIN_"
escape c   = show (ord c) ++ "_"

escapeToken c | isAlphaNum c || c == '_' = [c]
escapeToken '(' = "LPAREN_"
escapeToken ')' = "RPAREN_"
escapeToken '[' = "LBRACKET_"
escapeToken ']' = "RBRACKET_"
escapeToken '{' = "LBRACE_"
escapeToken '}' = "RBRACE_"
escapeToken '~' = "TILDE_"
escapeToken '^' = "CARET_"
escapeToken '*' = "STAR_"
escapeToken '+' = "PLUS_"
escapeToken '-' = "DASH_"
escapeToken '/' = "SLASH_"
escapeToken '.' = "DOT_"
escapeToken ',' = "COMMA_"
escapeToken ';' = "SEMI_"
escapeToken ':' = "COLON_"
escapeToken '=' = "EQ_"
escapeToken '<' = "LT_"
escapeToken '>' = "GT_"
escapeToken '&' = "AMP_"
escapeToken '|' = "BAR_"
escapeToken '%' = "PERCENT_"
escapeToken '?' = "QUESTION_"
escapeToken '!' = "BANG_"
-- add more if you have fun
-- or fall back to ASCII code:
escapeToken c = show (ord c) ++ "_"

punctuate' p = cat . punctuate p
--------------------------------------------------------------
-- BIN: make sure no rule has more than 2 symbols on the rhs

allocateCatName = do
  n <- get
  put (1+n)
  return $ show n

toBin :: [Rul Exp] -> ([Rul Exp], CatDescriptions)
toBin cf = (a,w)
  where (a,_,w) = runRWS (concat <$> forM cf toBinRul) () 0

type CatDescriptions = Map Cat Doc

-- | Convert a rule into a number of equivalent rules with at most 2
-- symbols on the rhs.
-- Also writes an explanation of what new categories are.
toBinRul :: Rul Exp -> RWS () CatDescriptions Int [Rul Exp]
toBinRul (Rule f cat rhs internal) | length rhs > 2 = do
  cat' <- liftM Cat allocateCatName
  r' <- toBinRul $ Rule f (cat $> cat') p internal
  tell $ Map.singleton cat' (int (length p) <> "-prefix of " <> prettyExp f <> " " <> parens (prettyRHS p))
  return $ Rule (Con "($)") cat [Left cat',l] internal
         : r'
  where l = last rhs
        p = init rhs
toBinRul r = return [r]

prettyRHS = hcat . punctuate " " . map (either (text . show) (quotes . text))

---------------------------
-- Fixpoint utilities

x ∪ y = sort $ nub (x ++ y)

lookupMulti cat nullset = maybe [] id (Map.lookup cat nullset)

type Set k x = Map k [x]

fixpointOnGrammar :: (Show k, Show x,Ord k, Ord x) => String -> (Set k x -> Rul f -> Set k x) -> CFG f -> Set k x
fixpointOnGrammar name f cf = case fixn 100 step Map.empty of
  Left x -> error $ "Could not find fixpoint of " ++ name ++". Last iteration:\n" ++ show x
  Right x -> x
  where step curSet = Map.unionsWith (∪) (map (f curSet) (cfgRules cf))

fixn :: Eq a => Int -> (a -> a) -> a -> Either a a
fixn 0 _ x = Left x
fixn n f x = if x' == x then Right x else fixn (n-1) f x'
  where x' = f x

-------------------------------------------------------
-- DEL : make sure no rule has 0 symbol on the rhs

type Nullable = Set Cat Exp

cross :: [[a]] -> [[a]]
cross [] = [[]]
cross (x:xs) = [y:ys | y <- x,  ys <- cross xs]

nullRule :: Nullable -> Rul Exp -> (Cat,[Exp])
nullRule nullset (Rule f c rhs _) = (wpThing c, map (appMany f) (cross (map nulls rhs)))
    where nulls (Right _) = []
          nulls (Left cat) = lookupMulti cat nullset

nullSet :: CFG Exp -> Nullable
nullSet = fixpointOnGrammar "nullable" (\s r -> uncurry Map.singleton (nullRule s r))

-- | Replace nullable occurences by nothing, and adapt the function consequently.
delNullable :: Nullable -> Rul Exp -> [Rul Exp]
delNullable nullset r@(Rule f cat rhs internal) = case rhs of
  [] -> []
  [_] -> [r]
  [r1,r2] -> [r] ++ [Rule (app'  f x) cat [r2] internal | x <- lk' r1]
                 ++ [Rule (app2 (isCat r1) f x) cat [r1] internal | x <- lk' r2]
  _ -> error $ "Panic:" ++ show r ++ "should have at most two elements."
  where lk' (Right _) = []
        lk' (Left cat) = lookupMulti cat nullset

delNull :: CFG Exp -> CFG Exp
delNull cf = onRules (concatMap (delNullable (nullSet cf))) cf


---------------
-- UNIT

type UnitRel cat = Set (Either cat String) (Exp,cat)

-- (c,(f,c')) ∈ unitSet   ⇒  f : c → c'

unitSet :: CFG Exp -> UnitRel Cat
unitSet = fixpointOnGrammar "unit set" unitRule

unitRule unitSet (Rule f (WithPosition _ c) [r] _internal) = Map.singleton r $
  (f,c) : [(g `appl` f,c') | (g,c') <- lookupMulti (Left c) unitSet]
         where appl = case r of
                 Left _ -> after
                 Right _ -> app'
unitRule _ _ = Map.empty

isUnitRule (Rule _ _ [_] _) = True
isUnitRule _ = False


------------------------
-- Left/Right occurences
type RHSEl = Either Cat String

isOnLeft, isOnRight :: RHSEl -> Rul f -> Bool
isOnLeft c (Rule _ _ [c',_] _) = c == c'
isOnLeft _ _ = False

isOnRight c (Rule _ _ [_,c'] _) = c == c'
isOnRight _ _ = False

isEntryPoint cf el = either (`elem` allEntryPoints cf) (const False) el

occurs :: (RHSEl -> Rul f -> Bool) -> RHSEl -> CFG f -> Bool
occurs where_ el cf = any (where_ el) (cfgRules cf)

splitLROn :: (a -> RHSEl) -> CFG f -> [a] -> Pair [a]
splitLROn f cf xs = filt <*> pure xs
  where filt = filter (\c -> occurs isOnLeft  (f c) cf || isEntryPoint cf (f c)) :/:
               filter (\c -> occurs isOnRight (f c) cf)

isSpecial (Left (Cat ('@':'@':_))) = True
isSpecial _ = False

optim :: (a -> RHSEl) -> Pair [a] -> Pair [(a,Doc -> Doc)]
optim f (x:/:y) = map modif x :/: map modif' y
  where modif  a | isSpecial (f a) = (a,\x -> "(if not p then (" <> x <> ":) else id)")
                 | otherwise = (a,rob)
        modif' a | isSpecial (f a) = (a,\x -> "(if     p then (" <> x <> ":) else id)")
                 | otherwise = (a,rob)
        rob x = "("<> x <> ":)"


splitOptim f cf xs = optim f $ splitLROn f cf $ xs


---------------------------
-- Error reporting

-- leftOf C = ⋃ { {X} ∪ leftOf X | C ::= X B ∈ Grammar or C ::= X ∈ Grammar }
leftRight pos s (Rule _ c rhs _) = Map.singleton (show c) (lkCat x s)
  where x = pos rhs

lkCat (Right t) _ = [Right t]
lkCat (Left c) s = Left c:lookupMulti (show c) s

-- neighbors A B = ∃ A' B'.  P ::= A' B'  &  A ∈ rightOf A'  &  B ∈ leftOf B
neighborSet cf = map (second (nub . sort)) $ group' [(x',lkCat y leftSet) | Rule _ _ [x,y] _ <- cfgRules cf, x' <- lkCat x rightSet]
  where leftSet  = fixpointOnGrammar "left set"  (leftRight head) cf
        rightSet = fixpointOnGrammar "right set" (leftRight last) cf

data Exp = Id -- identity function
          | Con String -- constructor or variable
          | App Exp Exp
          | Exp `After` Exp
          | App2 Exp Exp
            deriving (Eq,Ord)

prettyExp Id = "id"
prettyExp (Con x) = text x
prettyExp (App f x) = prettyExp f <+> (parens $ prettyExp x)
prettyExp (App2 f x) = "flip" <+> parens (prettyExp f) <+> parens (prettyExp x)
prettyExp (f `After` g) = parens (prettyExp f) <> "." <> parens (prettyExp g)

instance Show Exp where show = render . prettyExp

-- | Apply in 2nd position if the flag is true, otherwise apply normally.
app2 True f x =  App2 f x
app2 False f x = app' f x

infixl `app'`
app' :: Exp -> Exp -> Exp
app' (f `After` g) x = app' f (app' g x)
app' Id x = x
app' (App2 f y) x = (f `app'` x) `app'` y
app' (Con "($)") f = f
-- app' (Con "const") f = f
app' f x = App f x

after :: Exp -> Exp -> Exp
after Id f = f
after f Id = f
after f g = f `After` g

appMany f args = foldl app' f args
