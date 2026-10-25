From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.

Inductive action := Resume | Reclaim.
Definition plan (entry receipt : json) :=
 let creating := existsb (String.eqb (str entry "status")) ["creating";"creating_archived"] in
 let action := if creating && negb (String.eqb (str entry "status") "creating_archived") &&
   String.eqb (str receipt "status") "ready" then Resume else Reclaim in
 JObject [("effect",set entry "kind" (JString (if creating then "worktree_create" else "worktree_archive")));
   ("action",JString (match action with Resume=>"resume" | Reclaim=>"reclaim" end))].
