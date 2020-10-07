{-# LANGUAGE OverloadedStrings #-}

{-
    BNF Converter: ocamllex Generator
    Copyright (C) 2005  Author:  Kristofer Johannisson

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


-- based on BNFC Haskell backend

module BNFC.Backend.OCaml.CFtoOCamlLex (cf2ocamllex) where

import Prelude hiding ((<>))

import qualified Data.List as List
import Text.PrettyPrint hiding (render)
import qualified Text.PrettyPrint as PP

import AbsBNF
import BNFC.CF
import BNFC.Backend.OCaml.CFtoOCamlYacc (terminal)
import BNFC.Backend.OCaml.OCamlUtil (mkEsc, ocamlTokenName)
import BNFC.Lexing (mkRegMultilineComment)
import BNFC.Utils (cstring, unless)

cf2ocamllex :: String -> String -> CF -> String
cf2ocamllex _ parserMod cf =
  unlines $ List.intercalate [""] [
    header parserMod cf,
    definitions cf,
    [PP.render (rules cf)]
   ]

header :: String -> CF -> [String]
header parserMod cf = [
  "(* This ocamllex file was machine-generated by the BNF converter *)",
  "{",
  "open " ++ parserMod,
  "open Lexing",
  "",
  hashtables cf,
  "",
  "let unescapeInitTail (s:string) : string =",
  "  let rec unesc s = match s with",
  "      '\\\\'::c::cs when List.mem c ['\\\"'; '\\\\'; '\\\''] -> c :: unesc cs",
  "    | '\\\\'::'n'::cs  -> '\\n' :: unesc cs",
  "    | '\\\\'::'t'::cs  -> '\\t' :: unesc cs",
  "    | '\\\\'::'r'::cs  -> '\\r' :: unesc cs",
  -- "    | '\\\\'::'f'::cs  -> '\\f' :: unesc cs",  -- \f not supported by ocaml
  "    | '\\\"'::[]    -> []",
  "    | c::cs      -> c :: unesc cs",
  "    | _         -> []",
  "  (* explode/implode from caml FAQ *)",
  "  in let explode (s : string) : char list =",
  "      let rec exp i l =",
  "        if i < 0 then l else exp (i - 1) (s.[i] :: l) in",
  "      exp (String.length s - 1) []",
  "  in let implode (l : char list) : string =",
  "      let res = Buffer.create (List.length l) in",
  "      List.iter (Buffer.add_char res) l;",
  "      Buffer.contents res",
  "  in implode (unesc (List.tl (explode s)))",
  "",
  "let incr_lineno (lexbuf:Lexing.lexbuf) : unit =",
  "    let pos = lexbuf.lex_curr_p in",
  "        lexbuf.lex_curr_p <- { pos with",
  "            pos_lnum = pos.pos_lnum + 1;",
  "            pos_bol = pos.pos_cnum;",
  "        }",
  "}"
  ]

-- | set up hashtables for reserved symbols and words
hashtables :: CF -> String
hashtables cf = unlines . concat $
  [ ht "symbol_table"  $ cfgSymbols cf
  , ht "resword_table" $ reservedWords cf
  ]
  where
  ht table syms = unless (null syms) $
    [ unwords [ "let", table, "= Hashtbl.create", show (length syms)                  ]
    , unwords [ "let _ = List.iter (fun (kwd, tok) -> Hashtbl.add", table, "kwd tok)" ]
    , concat  [ "                  [", concat (List.intersperse ";" keyvals), "]"     ]
    ]
    where
    keyvals = map (\ s -> concat [ "(", mkEsc s, ", ", terminal cf s, ")" ]) syms


definitions :: CF -> [String]
definitions cf = concat $
  [ cMacros
  , rMacros cf
  , uMacros cf
  ]

cMacros :: [String]
cMacros = [
  "let l = ['a'-'z' 'A'-'Z' '\\192' - '\\255'] # ['\\215' '\\247']    (*  isolatin1 letter FIXME *)",
  "let c = ['A'-'Z' '\\192'-'\\221'] # ['\\215']    (*  capital isolatin1 letter FIXME *)",
  "let s = ['a'-'z' '\\222'-'\\255'] # ['\\247']    (*  small isolatin1 letter FIXME *)",
  "let d = ['0'-'9']                             (*  digit *)",
  "let i = l | d | ['_' '\\'']                    (*  identifier character *)",
  "let u = _                                     (* universal: any character *)"
  ]

rMacros :: CF -> [String]
rMacros cf
  | null symbs = []
  | otherwise  =
      [ "let rsyms =    (* reserved words consisting of special symbols *)"
      , "            " ++ unwords (List.intersperse "|" (map mkEsc symbs))
      ]
  where symbs = cfgSymbols cf

-- user macros, derived from the user-defined tokens
uMacros :: CF -> [String]
uMacros cf = ["let " ++ name ++ " = " ++ rep | (name, rep, _, _) <- userTokens cf]

-- | Returns the tuple of @(reg_name, reg_representation, token_name, is_position_token)@.

userTokens :: CF -> [(String, String, String, Bool)]
userTokens cf =
  [ (ocamlTokenName name, printRegOCaml reg, name, pos)
  | TokenReg n pos reg <- cfgPragmas cf
  , let name = wpThing n
  ]

-- | Make OCamlLex rule
-- >>> mkRule "token" [("REGEX1","ACTION1"),("REGEX2","ACTION2"),("...","...")]
-- rule token =
--   parse REGEX1 {ACTION1}
--       | REGEX2 {ACTION2}
--       | ... {...}
--
-- If no regex are given, we dont create a lexer rule:
-- >>> mkRule "empty" []
-- <BLANKLINE>
mkRule :: Doc -> [(Doc,Doc)] -> Doc
mkRule _ [] = empty
mkRule entrypoint (r1:rn) = vcat
    [ "rule" <+> entrypoint <+> "="
    , nest 2 $ hang "parse" 4 $ vcat
        (nest 2 (mkOne r1):map (("|" <+>) . mkOne) rn) ]
  where
    mkOne (regex, action) = regex <+> braces action

-- | Create regex for single line comments
-- >>> mkRegexSingleLineComment "--"
-- "--" (_ # '\n')*
-- >>> mkRegexSingleLineComment "\""
-- "\"" (_ # '\n')*
mkRegexSingleLineComment :: String -> Doc
mkRegexSingleLineComment s = cstring s <+> "(_ # '\\n')*"

-- | Create regex for multiline comments.
-- >>> mkRegexMultilineComment "<!--" "-->"
-- "<!--" (u # '-')* '-' ((u # '-')+ '-')* '-' ((u # ['-''>']) (u # '-')* '-' ((u # '-')+ '-')* '-' | '-')* '>'
--
-- >>> mkRegexMultilineComment "\"'" "'\""
-- "\"'" (u # '\'')* '\'' ((u # ['"''\'']) (u # '\'')* '\'' | '\'')* '"'
mkRegexMultilineComment :: String -> String -> Doc
mkRegexMultilineComment b e = text $ printRegOCaml $ mkRegMultilineComment b e

-- | Uses the function from above to make a lexer rule from the CF grammar
rules :: CF -> Doc
rules cf = mkRule "token" $
    -- comments
    [ (mkRegexSingleLineComment s, "token lexbuf") | s <- singleLineC ]
    ++
    [ (mkRegexMultilineComment b e, "token lexbuf") | (b,e) <- multilineC]
    ++
    -- reserved keywords
    [ ( "rsyms"
      , "let id = lexeme lexbuf in try Hashtbl.find symbol_table id with Not_found -> failwith (\"internal lexer error: reserved symbol \" ^ id ^ \" not found in hashtable\")" )
      | not (null (cfgSymbols cf))]
    ++
    -- user tokens
    [ (text n , tokenAction pos (text t)) | (n,_,t,pos) <- userTokens cf]
    ++
    -- predefined tokens
    [ ( "l i*", tokenAction False "Ident" ) ]
    ++
    -- integers
    [ ( "d+", "let i = lexeme lexbuf in TOK_Integer (int_of_string i)" )
    -- doubles
    , ( "d+ '.' d+ ('e' ('-')? d+)?"
      , "let f = lexeme lexbuf in TOK_Double (float_of_string f)" )
    -- strings
    , ( "'\\\"' ((u # ['\\\"' '\\\\' '\\n']) | ('\\\\' ('\\\"' | '\\\\' | '\\\'' | 'n' | 't' | 'r')))* '\\\"'"
      , "let s = lexeme lexbuf in TOK_String (unescapeInitTail s)" )
    -- chars
    , ( "'\\'' ((u # ['\\\'' '\\\\']) | ('\\\\' ('\\\\' | '\\\'' | 'n' | 't' | 'r'))) '\\\''"
      , "let s = lexeme lexbuf in TOK_Char s.[1]")
    -- spaces
    , ( "[' ' '\\t']", "token lexbuf")
    -- new lines
    , ( "'\\n'", "incr_lineno lexbuf; token lexbuf" )
    -- end of file
    , ( "eof", "TOK_EOF" )
    ]
  where
    (multilineC, singleLineC) = comments cf
    tokenAction pos t = case reservedWords cf of
        [] -> "let l = lexeme lexbuf in TOK_" <> t <+> arg
        _  -> "let l = lexeme lexbuf in try Hashtbl.find resword_table l with Not_found -> TOK_" <> t <+> arg
      where
      arg | pos       = "((lexeme_start lexbuf, lexeme_end lexbuf), l)"
          | otherwise = "l"

-------------------------------------------------------------------
-- Modified from the inlined version of @RegToAlex@.
-------------------------------------------------------------------

-- modified from pretty-printer generated by the BNF converter

-- the top-level printing method
printRegOCaml :: Reg -> String
printRegOCaml = render . prt 0

-- you may want to change render and parenth

render :: [String] -> String
render = rend 0
    where rend :: Int -> [String] -> String
          rend i ss = case ss of
                        "["      :ts -> cons "["  $ rend i ts
                        "("      :ts -> cons "("  $ rend i ts
                        t  : "," :ts -> cons t    $ space "," $ rend i ts
                        t  : ")" :ts -> cons t    $ cons ")"  $ rend i ts
                        t  : "]" :ts -> cons t    $ cons "]"  $ rend i ts
                        t        :ts -> space t   $ rend i ts
                        _            -> ""

          cons s t  = s ++ t
          space t s = if null s then t else t ++ " " ++ s

parenth :: [String] -> [String]
parenth ss = ["("] ++ ss ++ [")"]

-- the printer class does the job
class Print a where
  prt :: Int -> a -> [String]
  prtList :: [a] -> [String]
  prtList = concat . map (prt 0)

instance Print a => Print [a] where
  prt _ = prtList

instance Print Char where
  prt _ c = [show c]   -- if isAlphaNum c then [[c]] else ['\\':[c]]
  prtList s = [show s] -- map (concat . prt 0) s

prPrec :: Int -> Int -> [String] -> [String]
prPrec i j = if j<i then parenth else id

instance Print Identifier where
  prt _ (Identifier (_, i)) = [i]

instance Print Reg where
  prt i e = case e of
   RSeq reg0 reg   -> prPrec i 2 (concat [prt 2 reg0 , prt 3 reg])
   RAlt reg0 reg   -> prPrec i 1 (concat [prt 1 reg0 , ["|"] , prt 2 reg])
   RMinus reg0 reg -> prPrec i 1 (concat [prt 2 reg0 , ["#"] , prt 2 reg])
   RStar reg       -> prPrec i 3 (concat [prt 3 reg , ["*"]])
   RPlus reg       -> prPrec i 3 (concat [prt 3 reg , ["+"]])
   ROpt reg        -> prPrec i 3 (concat [prt 3 reg , ["?"]])
   REps            -> prPrec i 3 (["\"\""])  -- special construct for eps in ocamllex?
   RChar c         -> prPrec i 3 (concat [prt 0 c])
   RAlts str       -> prPrec i 3 (concat [["["], [concatMap show str], ["]"]])
   RSeqs str       -> [ show str ]
   -- RSeqs str       -> prPrec i 2 (concat (map (prt 0) str))
   RDigit          -> prPrec i 3 (concat [["d"]])
   RLetter         -> prPrec i 3 (concat [["l"]])
   RUpper          -> prPrec i 3 (concat [["c"]])
   RLower          -> prPrec i 3 (concat [["s"]])
   RAny            -> prPrec i 3 (concat [["u"]])
