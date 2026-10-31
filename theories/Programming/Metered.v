From Stdlib Require Import String Arith.
From Selvedge.Programming Require Import Outcome.

Definition metered(A:Type):Type:=nat->(outcome A*nat).
Definition met_return{A}(value:A):metered A:=fun budget=>(Good value,budget).
Definition met_lift{A}(value:outcome A):metered A:=fun budget=>(value,budget).
Definition met_fail{A}(reason:string):metered A:=met_lift(Error reason).
Definition met_bind{A B}(first:metered A)(next:A->metered B):metered B:=fun budget=>
 let '(result,remaining):=first budget in match result with Good value=>next value remaining|Error reason=>(Error reason,remaining)end.
Notation "x <-! a ;; b" := (met_bind a (fun x=>b)) (at level 100,a at next level,right associativity).
