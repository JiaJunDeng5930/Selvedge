From Stdlib Require Import String Bool NArith.
From Selvedge.Foundation Require ArgumentDeclaration.
Open Scope string_scope.

Definition constraints := ArgumentDeclaration.TextConstraints 1 ArgumentDeclaration.maximum_natural
 4096 true false false None.
Definition declaration := ArgumentDeclaration.Text constraints.
Fixpoint contains (needle text : string) :=
 if String.prefix needle text then true else match text with EmptyString => false | String _ rest => contains needle rest end.
Definition canonical (path : string) :=
 String.prefix "/" path &&
 negb (contains "/../" (String.append path "/")) && negb (contains "/./" (String.append path "/")) &&
 (String.eqb path "/" || negb (contains "//" (String.append path "/"))).
