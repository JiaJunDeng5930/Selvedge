From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State TaskScope TaskChange ModelRequest
 Dispatch Scheduler Delivery DeferredCommit.
From Selvedge.Features Require Runtime.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition capture (result : decision) :=
 let '(value,effects) := Dispatch.prepare (decision_world result) (decision_effects result) in
 Decision value (decision_reply result) effects.
(* This is the same finalization used by Packet. In particular, compaction's
   selected scope and reserve are attached before the actual wire is measured. *)
Definition finish := Selvedge.Features.Runtime.finish.
Definition continuing (result : decision) :=
 Decision (decision_world result) (decision_reply result)
   (decision_effects result ++ [ContinueScheduling]).

Definition inference_coordinate (request : effect) : option (N * N) :=
 match request with
 | RequestModel request => Some (ModelRequest.owner request,ModelRequest.ticket request)
 | RequestReasoning owner ticket _ => Some (owner,ticket)
 | _ => None end.
Definition inference_fits (value : world) (request : effect) :=
 Delivery.fits true (accept JNull value [request;ContinueScheduling]).
Definition oversized_inference (value : world) (request : effect) :=
 match inference_coordinate request with
 | Some _ => negb (inference_fits value request)
 | None => false end.
Definition failure_message :=
 "The inference request exceeds the native transport budget; no request was sent and full task history was retained".
Definition refusal_changes :=
 [TaskChange.AppendHistory [FailureMessage failure_message];TaskChange.ChangePhase Idle].
Definition owns_inference (request : effect) (current : task) :=
 match request,task_activity current with
 | RequestModel request,AskingModel expected _ _ => N.eqb (ModelRequest.ticket request) expected
 | RequestReasoning _ ticket _,EvaluatingReasoning expected _ => N.eqb ticket expected
 | _,_ => false end.
Definition same_inference (first second : effect) :=
 match inference_coordinate first,inference_coordinate second with
 | Some (owner,ticket),Some (actual,expected) => N.eqb owner actual && N.eqb ticket expected
 | _,_ => false end.
Definition refuse (request : effect) (result : decision) :=
 match inference_coordinate request with
 | None => result
 | Some (owner,_) => match TaskScope.select owner (decision_world result) with
   | None => result
   | Some target =>
     (* DEFENSE: An accumulated legal history can exceed the transport frame.
        Only the receiver of this never-sent request is retired; queued input,
        operation results and the complete history remain available. *)
     if owns_inference request (TaskScope.selected target) then
       Decision (TaskChange.interpret (TaskChange.Plan (decision_world result) target refusal_changes))
         (decision_reply result)
         (filter (fun effect => negb (same_inference request effect)) (decision_effects result))
     else result end
 end.
Definition normalize (result : decision) :=
 let result := capture result in
 let encoded := Selvedge.Features.Runtime.finish result in
 fold_left (fun result request => refuse request result)
   (filter (oversized_inference (decision_world encoded)) (decision_effects encoded)) result.

(* The accepted accumulator remains an unfinalized scheduler value. Previewing
   Runtime.finish never commits a feature fold or allocates a second receiver.
   Both possible terminal envelopes are checked, including the continuation
   needed when the next independent step belongs in another transaction. *)
Definition advance (reply : json) : Scheduler.advancement := fun value effects =>
 (* Reconciliation can append a side's parent observation after the packet's
    feature delta was processed. Refresh that maintenance state before the
    runnable gate; a frozen inference already owns its measured input. *)
 let result := if existsb Scheduler.frozen_inference effects then Decision value reply effects
   else Selvedge.Features.Compaction.synchronize_all (Decision value reply effects) in
 let result := normalize result in
 let result := Decision (decision_world result) reply (decision_effects result) in
 if Delivery.fits true (finish result) && Delivery.fits true (finish (continuing result))
 then Some (decision_world result,decision_effects result) else None.

Definition run (execute : Scheduler.executor) (permitted : N -> world -> bool) (result : decision) :=
 let result := normalize result in
 match advance (decision_reply result) (decision_world result) (decision_effects result) with
 | Some (value,effects) =>
   finish (Scheduler.run_with (advance (decision_reply result)) execute permitted
     (Decision value (decision_reply result) effects))
 | None => finish (DeferredCommit.continue result)
 end.

(* A physical completion and its feature consequences are durable before
   unrelated scheduling. The caller supplies the complete after_transition
   result, retaining its before/after delta for graph handoffs and maintenance. *)
Definition defer (result : decision) := finish (DeferredCommit.continue (normalize result)).
