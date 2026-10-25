From Selvedge.Kernel Require Import ModelResultDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import Dispatch.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
Import ListNotations.
Open Scope string_scope.
Definition running_json (entry : running) := JObject [("generation",number (handle entry));
  ("key",JString (key entry));("task",match task entry with Some owner => number owner | None => JNull end);
  ("cancellable",JBool (cancellable entry));("provider",JBool (provider entry));("reduced",JBool (reduced entry))].
Definition state_json (s : state) := JObject [("retired",JBool (retired s));
  ("next",number (next_handle s));("active",JArray (map running_json (active s)))].
Definition running_of (entry : json) := Running (num entry "generation") (str entry "key")
  (natural (get entry "task")) (boolean_field entry "cancellable") (boolean_field entry "provider") (boolean_field entry "reduced").
Definition state_of (source : json) := State (boolean_field source "retired") (num source "next")
  (map running_of (items (get source "active"))).
Definition effect_key (effect : json) :=
  let kind := str effect "kind" in
  if starts kind "worktree_" then kind ++ ":" ++ Common.decimal (num effect "task_id")
  else if String.eqb kind "chatgpt_exec" || String.eqb kind "chatgpt_cancel" then "chatgpt:" ++ Common.decimal (num effect "operation_id")
  else if String.eqb kind "board_text" then "board:" ++ Common.decimal (num effect "card_id") ++ ":" ++ Common.decimal (num effect "ticket")
  else Common.decimal (num effect "task_id") ++ ":" ++ Common.decimal (num effect "ticket").
Definition outcome_of (name : string) :=
  if String.eqb name "accepted" then Some Accepted
  else if String.eqb name "input_limit" then Some InputLimit
  else if String.eqb name "output_limit" then Some OutputLimit
  else if String.eqb name "rejected" then Some Rejected
  else if String.eqb name "uncertain" then Some Uncertain else None.
Definition observation_of (source : json) :=
  let kind := str source "kind" in let effect := get source "effect" in
  if String.eqb kind "launch" then Some (Launch (effect_key effect) (natural (get effect "task_id"))
    (negb (starts (str effect "kind") "worktree_"))
    (String.eqb (str effect "kind") "model" || String.eqb (str effect "kind") "approval"))
  else if String.eqb kind "complete" then Some (Complete (num source "generation"))
  else if String.eqb kind "cancel_task" then Some (CancelTask (num effect "task_id"))
  else if String.eqb kind "cancel_key" then Some (CancelKey (effect_key effect))
  else if String.eqb kind "settlement" then
    match outcome_of (str source "outcome") with Some outcome => Some (Settlement (num source "generation") outcome) | None => None end
  else if String.eqb kind "shutdown" then Some Shutdown else None.
Definition primitive_json (p : primitive) := match p with
| Start generation => ModelDeclarations.encode ModelResultDeclarations.dispatch_start (Schema.FCons (field:=Schema.Field "generation" Schema.KNatural) generation Schema.FNil)
| Cancel generation provider => ModelDeclarations.encode ModelResultDeclarations.dispatch_cancel (Schema.FCons (field:=Schema.Field "generation" Schema.KNatural) generation (Schema.FCons (field:=Schema.Field "provider" Schema.KBool) provider Schema.FNil))
| RetryFailure => ModelDeclarations.encode ModelResultDeclarations.dispatch_retry_failure Schema.FNil
| Settled => ModelDeclarations.encode ModelResultDeclarations.dispatch_settled Schema.FNil
| Retire => ModelDeclarations.encode ModelResultDeclarations.dispatch_retire Schema.FNil end.

Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "control.dispatch.initial" then success (state_json initial)
  else if String.eqb operation "control.dispatch.step" then
    match observation_of (get source "observation") with
    | Some observation => let '(next, effects) := step (state_of (get source "state")) observation in
        success (JObject [("state",state_json next);("effects",JArray (map primitive_json effects))])
    | None => type_error "Invalid effect dispatch observation" end
  else type_error "Unknown effect dispatch operation".
