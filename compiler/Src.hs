{- References for syntax:
   http://www.haskell.org/onlinereport/exps.html
   http://caml.inria.fr/pub/docs/manual-ocaml/expr.html -}

{-# LANGUAGE DeriveDataTypeable, RecordWildCards #-}

module Src
  ( Type(..)
  , Expr(..), Bind(..), RecFlag(..), Lit(..), Operator(..)
  , TypeContext, ValueContext
  , Name, TcId
  -- , RdrExpr
  -- , TcBinds
  -- , TcExpr
  , alphaEqTy
  , subtype
  , freeTyVars
  , substFreeTyVars
  , wrap
  , opPrec
  , unwrapOp
  , opReturnType
  ) where

import JavaUtils
import Panic

import qualified Language.Java.Syntax as J (Op(..))
-- import qualified Language.Java.Pretty as P
import Text.PrettyPrint.Leijen

import Data.Data
import qualified Data.Map as Map
import qualified Data.Set as Set

type Name = String
type TcId = (Name, Type)

data Type
  = TyVar Name
  | JClass ClassName
  | Fun Type Type
  | Forall Name Type
  | Product [Type]
  | ListOf Type
  | And Type Type
  -- Warning: If you ever add a case to this, you MUST also define the binary
  -- relations on your new case. Namely, add cases for your data constructor in
  -- `alphaEqTy` and `subtype` below.
  deriving (Eq, Show, Data, Typeable)

data Lit
    = Integer Integer
    | String String
    | Boolean Bool
    | Char Char
    deriving (Eq, Show)

data Operator = Arith J.Op | Compare J.Op | Logic J.Op
    deriving (Eq, Show)

data Expr id
  = Var id                              -- Variable
  | Lit Lit                             -- Literals
  | Lam (Name, Type) (Expr id)          -- Lambda
  | App  (Expr id) (Expr id)            -- Application
  | BLam Name (Expr id)                 -- Big lambda
  | TApp (Expr id) Type                 -- Type application
  | Tuple [Expr id]                     -- Tuples
  | Proj (Expr id) Int                  -- Tuple projection
  | PrimOp (Expr id) Operator (Expr id) -- Primitive operation
  | If (Expr id) (Expr id) (Expr id)    -- If expression
  | Let RecFlag [Bind id] (Expr id)     -- Let (rec) ... (and) ... in ...
  | LetOut RecFlag [(Name, Type, Expr TcId)] (Expr TcId) -- Post typecheck only
  | JNewObj ClassName [Expr id]
  | JMethod (Either ClassName (Expr id)) MethodName [Expr id] ClassName
  | JField  (Either ClassName (Expr id)) FieldName            ClassName
  | Seq [Expr id]
  | Merge (Expr id) (Expr id)
  | PrimList [Expr id]           -- New List
  deriving (Eq, Show)

-- type RdrExpr = Expr Name
-- type TcExpr  = Expr TcId
-- type TcBinds = [(Name, Type, Expr TcId)] -- f1 : t1 = e1 and ... and fn : tn = en

data Bind id = Bind
  { bindId       :: id             -- Identifier
  , bindTargs    :: [Name]         -- Type arguments
  , bindArgs     :: [(Name, Type)] -- Arguments, each annotated with a type
  , bindRhs      :: Expr id        -- RHS to the "="
  , bindRhsAnnot :: Maybe Type     -- Type of the RHS
  } deriving (Eq, Show)

data RecFlag = Rec | NonRec deriving (Eq, Show)

type TypeContext  = Set.Set Name
type ValueContext = Map.Map Name Type

alphaEqTy :: Type -> Type -> Bool
alphaEqTy (TyVar a)      (TyVar b)      = a == b
alphaEqTy (JClass c)     (JClass d)     = c == d
alphaEqTy (Fun t1 t2)    (Fun t3 t4)    = t1 `alphaEqTy` t3 && t2 `alphaEqTy` t4
alphaEqTy (Forall a1 t1) (Forall a2 t2) = substFreeTyVars (a2, TyVar a1) t2 `alphaEqTy` t1
alphaEqTy (Product ts1)  (Product ts2)  = length ts1 == length ts2 && uncurry alphaEqTy `all` zip ts1 ts2
alphaEqTy (ListOf t1)    (ListOf t2)    = t1 `alphaEqTy` t2
alphaEqTy (And t1 t2)    (And t3 t4)    = t1 `alphaEqTy` t3 && t2 `alphaEqTy` t4
alphaEqTy t1 t2
  | toConstr t1 == toConstr t2          = panic "Src.alphaEqTy"
                                          -- Panic if the names of the constructors are the same
  | otherwise                           = False

subtype :: Type -> Type -> Bool
subtype (TyVar a) (TyVar b)           = a == b
subtype (JClass c) (JClass d)         = c == d
  -- TODO: Should the subtype here be aware of the subtyping relations in the
  -- Java world?
subtype (Fun t1 t2) (Fun t3 t4)       = t3 `subtype` t1 && t2 `subtype` t4
subtype (Forall a1 t1) (Forall a2 t2) = substFreeTyVars (a1, TyVar a2) t1 `subtype` t2
subtype (Product ts1) (Product ts2)   = length ts1 == length ts2 && uncurry subtype `all` zip ts1 ts2
subtype (ListOf t1) (ListOf t2)       = t1 `subtype` t2  -- List :: * -> * is covariant
subtype (And t1 t2) t3                = t1 `subtype` t3 || t2 `subtype` t3
subtype t1 (And t2 t3)                = t1 `subtype` t2 && t1 `subtype` t3
subtype t1 t2
  | toConstr t1 == toConstr t2        = panic "Src.subtype"
                                        -- Panic if the names of the constructors are the same
  | otherwise                         = False

substFreeTyVars :: (Name, Type) -> Type -> Type
substFreeTyVars (x, r) = go
  where
    go (TyVar a)
      | a == x      = r
      | otherwise   = TyVar a
    go (JClass c )  = JClass c
    go (Fun t1 t2)  = Fun (go t1) (go t2)
    go (Product ts) = Product (map go ts)
    go (Forall a t)
      | a == x                      = Forall a t
      | a `Set.member` freeTyVars r = Forall a t -- The freshness condition, crucial!
      | otherwise                   = Forall a (go t)
    go (ListOf a)   = ListOf (go a)

freeTyVars :: Type -> Set.Set Name
freeTyVars (TyVar x)    = Set.singleton x
freeTyVars (JClass _)   = Set.empty
freeTyVars (Forall a t) = Set.delete a (freeTyVars t)
freeTyVars (Fun t1 t2)  = freeTyVars t1 `Set.union` freeTyVars t2
freeTyVars (Product ts) = Set.unions (map freeTyVars ts)
freeTyVars (ListOf a)   = Set.empty

instance Pretty Type where
  pretty (TyVar a)    = text a
  pretty (Fun t1 t2)  = parens $ pretty t1 <+> text "->" <+> pretty t2
  pretty (Forall a t) = parens $ text "forall" <+> text a <> dot <+> pretty t
  pretty (Product ts) = tupled (map pretty ts)
  pretty (JClass c)   = text c
  pretty (ListOf a)   = brackets $ pretty a
  pretty (And t1 t2)  = parens (pretty t1 <+> text "&" <+> pretty t2)

instance Pretty id => Pretty (Expr id) where
  pretty (Var x) = pretty x
  pretty (Lit (Integer n)) = integer n
  pretty (Lit (String n)) = string n
  pretty (Lit (Boolean n)) = bool n
  pretty (Lit (Char n)) = char n
  pretty (BLam a e) = parens $ text "/\\" <> text a <> dot <+> pretty e
  pretty (Lam (x,t) e) =
    parens $
      backslash <> parens (pretty x <+> colon <+> pretty t) <> dot <+>
      pretty e
  pretty (TApp e t) = parens $ pretty e <+> pretty t
  pretty (App e1 e2) = parens $ pretty e1 <+> pretty e2
  pretty (Tuple es) = tupled (map pretty es)
  pretty (Proj e i) = parens (pretty e) <> text "._" <> int i
  pretty (PrimOp e1 op e2) = parens $
                               parens (pretty e1) <+>
                               text (show op) <+>
                               -- text (P.prettyPrint op) <+>
                               parens (pretty e2)
  pretty (If e1 e2 e3) = parens $
                            text "if" <+> pretty e1 <+>
                            text "then" <+> pretty e2 <+>
                            text "else" <+> pretty e3
  pretty (Let recFlag bs e) =
    text "let" <+> pretty recFlag <+>
    encloseSep empty empty (softline <> text "and" <> space) (map pretty bs) <+>
    text "in" <+>
    pretty e
  pretty (LetOut recFlag bs e) =
    text "let" <+> pretty recFlag <+>
    encloseSep empty empty (softline <> text "and" <> space)
      (map (\(f1,t1,e1) -> text f1 <+> colon <+> pretty t1 <+> equals <+> pretty e1) bs) <+>
    text "in" <+>
    pretty e
  pretty (JNewObj c args)  = text "new" <+> text c <> tupled (map pretty args)
  pretty (JMethod e m args _) = case e of (Left e')  -> pretty e' <> dot <> text m <> tupled (map pretty args)
                                          (Right e') -> pretty e' <> dot <> text m <> tupled (map pretty args)
  pretty (PrimList l)         = brackets $ tupled (map pretty l)
  pretty (Merge e1 e2)  = parens (pretty e1 <+> text ",," <+> pretty e2)

instance Pretty id => Pretty (Bind id) where
  pretty Bind{..} =
    pretty bindId <+>
    hsep (map pretty bindTargs) <+>
    hsep (map (\(x,t) -> parens (pretty x <+> colon <+> pretty t)) bindArgs) <+>
    case bindRhsAnnot of { Nothing -> empty; Just t -> colon <+> pretty t } <+>
    equals <+>
    pretty bindRhs

instance Pretty RecFlag where
  pretty Rec    = text "rec"
  pretty NonRec = empty

wrap :: (b -> a -> a) -> [b] -> a -> a
wrap cons xs t = foldr cons t xs

-- Precedence of operators based on the table in:
-- http://en.wikipedia.org/wiki/Order_of_operations#Programming_languages
opPrec :: Num a => Operator -> a
opPrec (Arith J.Mult)     = 3
opPrec (Arith J.Div)      = 3
opPrec (Arith J.Rem)      = 3
opPrec (Arith J.Add)      = 4
opPrec (Arith J.Sub)      = 4
opPrec (Compare J.LThan)  = 6
opPrec (Compare J.GThan)  = 6
opPrec (Compare J.LThanE) = 6
opPrec (Compare J.GThanE) = 6
opPrec (Compare J.Equal)  = 7
opPrec (Compare J.NotEq)  = 7
opPrec (Logic J.CAnd)     = 11
opPrec (Logic J.COr)      = 12
opPrec op = panic $ "Src.Syntax.opPrec: " ++ show op

unwrapOp :: Operator -> J.Op
unwrapOp (Arith op)   = op
unwrapOp (Compare op) = op
unwrapOp (Logic op)   = op

opReturnType :: Operator -> Type
opReturnType (Arith _)   = JClass "java.lang.Integer"
opReturnType (Compare _) = JClass "java.lang.Boolean"
opReturnType (Logic _)   = JClass "java.lang.Boolean"