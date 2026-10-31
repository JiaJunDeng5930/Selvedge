From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State TaskScope TaskChange ModelRequest
 Dispatch Scheduler Delivery DeferredCommit HookCallbacks RequestReceiver.
From Selvedge.Features Require Runtime.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition capture_requests : DecisionComposition.transformation := fun _ => Dispatch.prepare.
Definition capture := DecisionComposition.transform capture_requests.
(* This is the same finalization used by Packet. In particular, compaction's
   selected scope and reserve are attached before the actual wire is measured. *)
Definition finish := Selvedge.Features.Runtime.finish.
Definition continuing := DecisionComposition.transform (DecisionComposition.append [ContinueScheduling]).

Definition inference_coordinate (request : effect) : option (N * N) :=
 match request with
 | RequestModel request => Some (ModelRequest.owner request,ModelRequest.ticket request)
 | RequestReasoning owner ticket _ => Some (owner,ticket)
 | _ => None end.
Definition request_fits (value : world) (request : effect) :=
 Delivery.fits true (accept JNull value [request;ContinueScheduling]).
Definition oversized_inference (value : world) (request : effect) :=
 match inference_coordinate request with
 | Some _ => negb (request_fits value request)
 | None => false end.
Definition failure_message :=
 "The inference request exceeds the native transport budget; no request was sent and full task history was retained".
Definition refusal_changes :=
 [TaskChange.AppendHistory [FailureMessage failure_message];TaskChange.ChangePhase Idle].
Definition owns_inference (request : effect) (current : task) :=
 match request with
 | RequestModel request => match RequestReceiver.pending_phase RequestReceiver.ModelReceiver
     (ModelRequest.ticket request) current with Some _ => true | None => false end
 | RequestReasoning _ ticket _ => match RequestReceiver.pending_phase RequestReceiver.ReasoningReceiver
     ticket current with Some _ => true | None => false end
 | _ => false end.
Definition same_inference (first second : effect) :=
 match inference_coordinate first,inference_coordinate second with
 | Some (owner,ticket),Some (actual,expected) => N.eqb owner actual && N.eqb ticket expected
 | _,_ => false end.
Definition refusal (request : effect) : DecisionComposition.transformation := fun _ value effects =>
 match inference_coordinate request with
 | None => (value,effects)
 | Some (owner,_) => match TaskScope.select owner value with
   | None => (value,effects)
   | Some target =>
     (* DEFENSE: An accumulated legal history can exceed the transport frame.
        Only the receiver of this never-sent request is retired; queued input,
        operation results and the complete history remain available. *)
     if owns_inference request (TaskScope.selected target) then
       (TaskChange.interpret (TaskChange.Plan value target refusal_changes),
         filter (fun effect => negb (same_inference request effect)) effects)
     else (value,effects) end
 end.
Definition refuse request := DecisionComposition.transform (refusal request).
Definition after_failure_message :=
 "The result-processing request exceeds the native transport budget; this hook was not sent and the original tool result remains available in task history".
Definition oversized_after (value : world) (request : effect) :=
 match request with
 | CheckResult _ _ _ _ _ _ _ => negb (request_fits value request)
 | _ => false end.
Definition same_after (first second : effect) :=
 match first,second with
 | CheckResult owner ticket operation _ _ _ _, CheckResult actual expected pending _ _ _ _ =>
   N.eqb owner actual && N.eqb ticket expected && N.eqb operation pending
 | _,_ => false end.
Definition after_refusal (request : effect) : DecisionComposition.transformation := fun _ value effects =>
 match request with
 | CheckResult owner ticket operation _ _ _ _ =>
   (* DEFENSE: A legal call and a legal tool result can exceed one frame when
      combined for an after hook. Its never-sent receiver must settle, rather
      than retry the same oversized request in every durable continuation.
      The ordinary callback owns the operation, receipt, result and wake rules. *)
   let settled := HookCallbacks.after_completed owner operation ticket
     (Inputs.AfterFailure after_failure_message) value in
   (decision_world settled,filter (fun effect => negb (same_after request effect)) effects)
 | _ => (value,effects) end.
Definition refuse_after request := DecisionComposition.transform (after_refusal request).
Definition normalization : DecisionComposition.transformation := fun reply value effects =>
 let '(value,effects) := capture_requests reply value effects in
 let '(encoded,emitted) := Selvedge.Features.Runtime.finalization reply value effects in
 DecisionComposition.compose
   (DecisionComposition.fold (filter (oversized_inference encoded) emitted) refusal)
   (DecisionComposition.fold (filter (oversized_after encoded) emitted) after_refusal) reply value effects.
Definition normalize := DecisionComposition.transform normalization.

(* The accepted accumulator remains an unfinalized scheduler value. Previewing
   Runtime.finish never commits a feature fold or allocates a second receiver.
   Both possible terminal envelopes are checked, including the continuation
   needed when the next independent step belongs in another transaction. *)
Definition advance (reply : json) : Scheduler.advancement := fun value effects =>
 (* Reconciliation can append a side's parent observation after the packet's
    feature delta was processed. Refresh that maintenance state before the
    runnable gate; a frozen inference already owns its measured input. *)
 let '(value,effects) := if existsb Scheduler.frozen_inference effects then (value,effects)
   else DecisionComposition.maintain Selvedge.Features.Compaction.synchronize_all reply value effects in
 let '(value,effects) := normalization reply value effects in
 let result := Decision value reply effects in
 if Delivery.fits true (finish result) && Delivery.fits true (finish (continuing result))
 then Some (decision_world result,decision_effects result) else None.

Definition scheduling (execute : Scheduler.executor) (permitted : N -> world -> bool)
 : DecisionComposition.transformation := fun reply value effects =>
 let '(value,effects) := normalization reply value effects in
 let '(value,effects) := match advance reply value effects with
 | Some (next,emitted) => Scheduler.scheduling_with (advance reply) execute permitted reply next emitted
 | None => DeferredCommit.continuation reply value effects end in
 Selvedge.Features.Runtime.finalization reply value effects.
Definition run execute permitted := DecisionComposition.transform (scheduling execute permitted).

(* A physical completion and its feature consequences are durable before
   unrelated scheduling. The caller supplies the complete after_transition
   result, retaining its before/after delta for graph handoffs and maintenance. *)
Definition deferral := DecisionComposition.compose normalization
 (DecisionComposition.compose DeferredCommit.continuation Selvedge.Features.Runtime.finalization).
Definition defer := DecisionComposition.transform deferral.
