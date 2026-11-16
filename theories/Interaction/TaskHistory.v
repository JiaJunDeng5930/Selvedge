From Stdlib Require Import String List Bool Arith FMapAVL OrderedTypeEx.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require Import JsonObjects.
From Selvedge.Kernel Require Conversation Domain Codec.
Module KCodec := Selvedge.Kernel.Codec.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require Audit.
Import ListNotations.
Open Scope string_scope.

Definition entry := (nat * json)%type.

Record invocation := Invocation {
 invocation_entry : entry;
 invocation_id : string;
 invocation_running : bool;
 invocation_result : option entry;
 invocation_receipt : option entry;
 invocation_operation : option json
}.

Inductive step :=
 | Commentary (message : entry)
 | Tools (first : invocation) (rest : list invocation)
 | Supporting (first : entry) (rest : list entry).
Inductive section :=
 | Speech (message : entry)
 | Process (identity : nat) (steps : list step) (ended : bool).

Definition invocation_identity message :=
 bind (field "content" message) (string_field "id").

Inductive result_kind := ProviderResult | PublishedResult | ExecutionReceipt.
Definition result_identity message : option (string * result_kind) :=
 match text "role" message with
 | "function_output" => option_map (fun id => (id,ProviderResult)) (string_field "call_id" message)
 | "operation_result" => option_map (fun id => (id,PublishedResult)) (string_field "call_id" message)
 | "tool_receipt" => option_map (fun id => (id,ExecutionReceipt))
   (bind (field "call" message) (string_field "id"))
 | _ => None end.

Module Calls := FMapAVL.Make OrderedTypeEx.String_as_OT.

Record evidence := Evidence {
 invocation_position : option nat;
 current_operation : option json;
 provider_result : option entry;
 published_result : option entry;
 execution_receipt : option entry
}.
Definition empty_evidence := Evidence None None None None None.
Definition evidence_for id (calls : Calls.t evidence) := value_or empty_evidence (Calls.find id calls).
Definition update id edit calls := Calls.add id (edit (evidence_for id calls)) calls.

Definition index_operation calls operation :=
 match string_field "call_id" operation with
 | Some id => update id (fun before => Evidence (invocation_position before) (Some operation)
   (provider_result before) (published_result before) (execution_receipt before)) calls
 | None => calls end.

Definition record_result kind result before :=
 let '(provider, published, receipt) := match kind with
  | ProviderResult => (Some result, published_result before, execution_receipt before)
  | PublishedResult => (provider_result before, Some result, execution_receipt before)
  | ExecutionReceipt => (provider_result before, published_result before, Some result)
  end in Evidence (invocation_position before) (current_operation before) provider published receipt.

Definition index_entry calls (item : entry) :=
 let '(position, message) := item in
 match text "role" message with
 | "function_call" => match invocation_identity message with
   | Some id => update id (fun before => Evidence (Some position) (current_operation before)
     (provider_result before) (published_result before) (execution_receipt before)) calls
   | None => calls end
 | _ => match result_identity message with
   | Some (id,kind) =>
     let before := evidence_for id calls in
     match invocation_position before with
     | Some _ => Calls.add id (record_result kind item before) calls
     | None => calls end
   | None => calls end
 end.

Fixpoint indexed (index : nat) (messages : list json) : list entry :=
 match messages with
 | [] => []
 | message :: rest => (index,message) :: indexed (S index) rest
 end.

Definition result_for kind before := match kind with
 | ProviderResult => provider_result before
 | PublishedResult => published_result before
 | ExecutionReceipt => execution_receipt before end.

(** Once an operation is announced, the provider response only acknowledges
    its publication. The current operation or its eventual result has the
    actual state the reader needs. *)
Definition settled_result before :=
 match published_result before with
 | Some result => Some result
 | None => if value_or false (option_map (flag "announced") (current_operation before))
           then None else provider_result before
 end.

Definition same_outcome (left right : entry) :=
 let left := snd left in let right := snd right in
 Bool.eqb (flag "is_error" left) (flag "is_error" right) &&
 JsonObjects.equivalent (value_or JNull (field "content" left)) (value_or JNull (field "content" right)).

Definition operation_running (operation : option json) :=
 match operation with Some value => String.eqb (text "status" value) "running" | None => false end.

Definition present_call item id before :=
 let result := settled_result before in
 let receipt := execution_receipt before in
 let '(primary, original) := match result, receipt with
  | Some result, Some receipt => (Some result, if same_outcome result receipt then None else Some receipt)
  | Some result, None => (Some result, None)
  | None, _ => (receipt, None) end in
 let operation := current_operation before in
 Invocation item id (operation_running operation) primary original operation.

Definition belongs_to_call calls kind id position :=
 match result_for kind (evidence_for id calls) with
 | Some result => Nat.eqb position (fst result)
 | None => false end.

Inductive activity := Explain (message : entry) | Invoke (call : invocation) | Support (message : entry).
Definition activity_entry item := match item with
 | Explain entry | Support entry => entry
 | Invoke call => invocation_entry call end.

Definition visible calls (item : entry) : option (entry + activity) :=
 let '(position,message) := item in
 match Conversation.json_message_role message with
 | Some "user" => Some (inl item)
 | Some "assistant" => match KCodec.assistant_phase_from_json message with
   | Some Domain.Commentary => Some (inr (Explain item))
   | _ => Some (inl item) end
 | _ => if Audit.hidden message || negb (Audit.readable_activity message) then None else
   match text "role" message with
   | "function_call" => match invocation_identity message with
     | Some id => Some (inr (Invoke (present_call item id (evidence_for id calls))))
     | None => Some (inr (Support item)) end
   | _ => match result_identity message with
     | Some (id,kind) => if belongs_to_call calls kind id position then None else Some (inr (Support item))
     | None => Some (inr (Support item)) end
   end
 end.

Definition prepend_step item tail :=
 match item, tail with
 | Explain message, _ => Commentary message :: tail
 | Invoke call, Tools first rest :: next => Tools call (first :: rest) :: next
 | Invoke call, _ => Tools call [] :: tail
 | Support message, Supporting first rest :: next => Supporting message (first :: rest) :: next
 | Support message, _ => Supporting message [] :: tail end.

Definition prepend_section item tail :=
 match item with
 | None => tail
 | Some (inl message) => Speech message :: tail
 | Some (inr activity) =>
   let position := fst (activity_entry activity) in
   match tail with
   | Process _ steps ended :: rest => Process position (prepend_step activity steps) ended :: rest
   | Speech _ :: _ => Process position (prepend_step activity []) true :: tail
   | [] => [Process position (prepend_step activity []) false]
   end
 end.

Definition project (history operations : list json) : list section :=
 let history := indexed 0 history in
 let calls := fold_left index_entry history (fold_left index_operation operations (Calls.empty evidence)) in
 fold_right (fun item tail => prepend_section (visible calls item) tail) [] history.
