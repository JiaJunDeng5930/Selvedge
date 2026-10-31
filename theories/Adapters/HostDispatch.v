From Selvedge.Kernel Require Import ModelResultDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import Dispatch.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
Import ListNotations.
Open Scope string_scope.
Definition provider_json value := JString (match value with NoProvider=>"none" | TaskProvider=>"task" | IndependentProvider=>"independent" end).
Definition provider_of value := if String.eqb (text value) "task" then TaskProvider
  else if String.eqb (text value) "independent" then IndependentProvider else NoProvider.
Definition effect_provider effect := if String.eqb (str effect "kind") "model" then TaskProvider
  else if String.eqb (str effect "kind") "approval" then IndependentProvider else NoProvider.
Definition running_json (entry : running) := JObject [("generation",number (handle entry));
  ("key",JString (key entry));("task",match task entry with Some owner => number owner | None => JNull end);
  ("cancellable",JBool (cancellable entry));("provider",provider_json (provider entry));("reduced",JBool (reduced entry));("settled",JBool (settled entry))].
Definition state_json (s : state) := JObject [("retired",JBool (retired s));
  ("next",number (next_handle s));("active",JArray (map running_json (active s)))].
Definition running_of (entry : json) := Running (num entry "generation") (str entry "key")
  (natural (get entry "task")) (boolean_field entry "cancellable") (provider_of (get entry "provider")) (boolean_field entry "reduced") (boolean_field entry "settled").
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
Definition workspace_running_of (source : json) :=
  let resource := get source "resource" in
  WorkspaceRunning (num source "generation") (natural (get source "task"))
    (natural (get resource "task_id")) (String.eqb (str resource "backend") "local") (boolean_field source "local_overlap").
Definition observation_of (source : json) :=
  let kind := str source "kind" in let effect := get source "effect" in
  if String.eqb kind "workspace_limit" then
    Some (WorkspaceLimit (String.eqb (str effect "kind") "worktree_create")
      (String.eqb (str effect "backend") "local") (boolean_field (get source "completion") "ok"))
  else if String.eqb kind "workspace_barrier" then
    Some (AwaitWorkspace (num effect "task_id") (String.eqb (str effect "backend") "local")
      (map workspace_running_of (items (get source "running"))))
  else if String.eqb kind "launch" then Some (Launch (effect_key effect) (natural (get effect "task_id"))
    (negb (starts (str effect "kind") "worktree_"))
    (effect_provider effect))
  else if String.eqb kind "complete" then match natural (get source "generation") with Some (N.pos generation) => Some (Complete (N.pos generation)) | _ => None end
  else if String.eqb kind "cancel_task" then Some (CancelTask (num effect "task_id"))
  else if String.eqb kind "cancel_key" then Some (CancelKey (effect_key effect))
  else if String.eqb kind "settlement" then
    match natural (get source "generation"), outcome_of (str source "outcome") with Some (N.pos generation), Some outcome => Some (Settlement (N.pos generation) outcome) | _, _ => None end
  else if String.eqb kind "shutdown" then Some Shutdown else None.
Definition primitive_packet (p : primitive) := match p with
| Start generation => ModelDeclarations.pack ModelResultDeclarations.dispatch_start [!generation!]
| RollbackWorkspace => ModelDeclarations.pack ModelResultDeclarations.dispatch_rollback_workspace [!!]
| RetainWorkspace => ModelDeclarations.pack ModelResultDeclarations.dispatch_retain_workspace [!!]
| Await generation => ModelDeclarations.pack ModelResultDeclarations.dispatch_await [!generation!]
| Cancel generation provider => ModelDeclarations.pack ModelResultDeclarations.dispatch_cancel [!generation;provider!]
| RetryFailure => ModelDeclarations.pack ModelResultDeclarations.dispatch_retry_failure [!!]
| Settled => ModelDeclarations.pack ModelResultDeclarations.dispatch_settled [!!]
| Retire => ModelDeclarations.pack ModelResultDeclarations.dispatch_retire [!!] end.
Definition primitive_json p := ModelDeclarations.encode_packet (primitive_packet p).

Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "control.dispatch.initial" then success (state_json initial)
  else if String.eqb operation "control.dispatch.step" then
    match observation_of (get source "observation") with
    | Some observation => let '(next, effects) := step (state_of (get source "state")) observation in
        success (JObject [("state",state_json next);("effects",JArray (map primitive_json effects))])
    | None => type_error "Invalid effect dispatch observation" end
  else type_error "Unknown effect dispatch operation".
