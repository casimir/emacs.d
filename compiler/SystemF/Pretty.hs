{-# LANGUAGE FlexibleInstances #-}

{-# OPTIONS_GHC -fwarn-incomplete-patterns #-}

module SystemF.Pretty
    ( prettyPrint
    , prettyPrintPFExp
    , prettyPrintPFTyp
    ) where

import Data.Char        (chr, ord)
import Data.List        (intersperse)

import qualified Language.Java.Syntax as J

import Text.PrettyPrint

import ESF.Syntax
import SystemF.Syntax

prettyPrint :: Pretty a => a -> String
prettyPrint = show . pretty

prettyPrintPFTyp :: PFTyp Int -> String
prettyPrintPFTyp = prettyPrint

prettyPrintPFExp :: PFExp Int Int -> String
prettyPrintPFExp = prettyPrint


parenPrec :: Int -> Int -> Doc -> Doc
parenPrec inheritedPrec currentPrec t
    | inheritedPrec <= 0          = t
    | inheritedPrec < currentPrec = parens t
    | otherwise                   = t

class Pretty a where
    pretty :: a -> Doc
    pretty = prettyPrec 0 (0, 0)

    prettyPrec :: Int -> (Int, Int) -> a -> Doc
    prettyPrec _ _ = pretty

instance Pretty (PFTyp Int) where
    prettyPrec p l@(ltvar, lvar) t = case t of
        FTVar a     -> text (tvar a)
        FForall f   -> text ("forall " ++ tvar ltvar ++ ".") <+> prettyPrec p (ltvar+1,  lvar) (f ltvar)
        FFun t1 t2  -> parenPrec p 2 $ prettyPrec 1 l t1 <+> text "->" <+> prettyPrec p l t2
        FJClass c   -> text c
        FProduct ts -> parens $ hcat (intersperse (comma <> space) $ map (prettyPrec p l) ts)

instance Pretty (PFExp Int Int) where
    prettyPrec p l@(ltvar, lvar) e = case e of
        FVar _ x         -> text (var x)
        FLit lit         -> text $ show lit
        FTuple es        -> parens $ hcat (intersperse comma $ map (prettyPrec p l) es)

        FProj i e1       -> parenPrec p 1 $ prettyPrec 1 l e1 <> text ("._" ++ show i)

        FApp e1 e2       -> parenPrec p 2 $ prettyPrec 2 l e1 <+> prettyPrec 1 l e2
        FTApp e' t        -> parenPrec p 2 $ prettyPrec 2 l e'  <+> prettyPrec 1 l t

        FBLam f          -> parenPrec p 3 $
                                text ("/\\" ++ tvar ltvar ++ ".")
                                <+> prettyPrec 0 (ltvar+1, lvar) (f ltvar)
        FLam t f         -> parenPrec p 3 $
                                text ("\\(" ++ var lvar ++ " : " ++ show (prettyPrec p (ltvar, lvar+1) t) ++ ").")
                                <+> prettyPrec 0 (ltvar, lvar+1) (f lvar)
        FFix f t1 t2     -> parenPrec p 3 $
                                text ("fix " ++ var lvar ++ ".")
                                <+> text ("\\(" ++ (var (lvar+1) ++ " : " ++ show (prettyPrec p (ltvar, lvar+2) t1)) ++ ").")
                                <+> prettyPrec 0 (ltvar, lvar+2) (f lvar (lvar+1)) <+> colon <+> prettyPrec 0 (ltvar, lvar+2) t2

        FPrimOp e1 op e2 -> parenPrec p q $ prettyPrec q l e1 <+> text (show op) <+> prettyPrec (q-1) l e2
                                where q = opPrec op

        FIf e1 e2 e3    -> text "if" <+> prettyPrec p l e1 <+> text "then" <+> prettyPrec p l e2 <+> text "else" <+> prettyPrec p l e3

tvar :: Int -> String
tvar n
    | n < 0     = error "`var` called with n < 0"
    | n < 26    = [chr (ord 'A' + n)]
    | otherwise = "A" ++ show (n - 25)

var :: Int -> String
var n
    | n < 0     = error "`tvar` called with n < 0"
    | n < 26    = [chr (ord 'a' + n)]
    | otherwise = "a" ++ show (n - 25)

-- Precedence of operators based on the table in:
-- http://en.wikipedia.org/wiki/Order_of_operations#Programming_languages
opPrec :: Num a => Operator -> a
opPrec (Arith J.Mult)    = 3
opPrec (Arith J.Div)     = 3
opPrec (Arith J.Rem)     = 3
opPrec (Arith J.Add)     = 4
opPrec (Arith J.Sub)     = 4
opPrec (Compare J.LThan)   = 6
opPrec (Compare J.GThan)   = 6
opPrec (Compare J.LThanE)  = 6
opPrec (Compare J.GThanE)  = 6
opPrec (Compare J.Equal)   = 7
opPrec (Compare J.NotEq)   = 7
opPrec (Logic J.CAnd)    = 11
opPrec (Logic J.COr)     = 12
opPrec op = error $ "Something impossible happens! The operator '" ++ show op ++ "' is not part of the language."
