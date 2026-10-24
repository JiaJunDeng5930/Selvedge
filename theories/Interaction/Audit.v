From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Kernel Require Import Conversation.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition speech message := existsb(String.eqb(value_or ""(Conversation.json_message_role message)))["user";"assistant"].
Definition hidden message := String.eqb(text "role" message)"speech_delegation_receipt".
Definition failed message :=
 let decision:=text "decision"(value_or JNull(field "content" message))in
 flag "is_error" message || String.eqb(text "role" message)"error" ||
 (existsb(String.eqb(text "role" message))["approval_record";"hook_record";"after_record"] &&
  existsb(String.eqb decision)["deny";"failed"]).
Inductive group := Spoken(entry:nat*json) | Activity(first:nat*json)(rest:list(nat*json)).
Definition entries g := match g with Spoken entry=>[entry]|Activity first rest=>first::rest end.
Definition prepend index message tail :=
 if hidden message then tail else if speech message then Spoken(index,message)::tail else
 match tail with Activity first rest::tail=>Activity(index,message)(first::rest)::tail
 |tail=>Activity(index,message)[]::tail end.
Fixpoint groups index messages := match messages with []=>[]|message::rest=>prepend index message(groups(S index)rest)end.
Fixpoint latest_failure (entries:list(nat*json)) : option nat := match entries with []=>None|(index,message)::rest=>
 match latest_failure rest with Some index=>Some index|None=>if failed message then Some index else None end end.
Definition attention entries := match latest_failure entries with None=>0%N|Some index=>N.of_nat(S index)end.
Definition operation_count (entries:list(nat*json)) := List.length(filter(fun entry=>String.eqb(text "role"(snd entry))"function_call")entries).
Fixpoint retained index messages := match messages with []=>[]|message::rest=>
 if hidden message then retained(S index)rest else (index,message)::retained(S index)rest end.

(** Grouping changes disclosure boundaries, never event order or payloads. *)
Theorem grouping_preserves_events : forall messages index,
 flat_map entries(groups index messages)=retained index messages.
Proof.
 induction messages as [|message rest IH];intros index;simpl;auto.
 unfold prepend. destruct(hidden message);auto.
 destruct(speech message);simpl;rewrite ?IH;auto.
 destruct(groups(S index)rest)as [|g tail]eqn:Tail;simpl in *.
 - now rewrite <-IH,Tail.
 - destruct g;simpl in *;now rewrite <-IH,Tail.
Qed.

Open Scope string_scope.

(** Audit faces retain the admitted event. Approval records include the reviewer
    frozen when the decision ran, rather than a later profile lookup. *)
Inductive kind := ToolInvocation | ToolResult | Reasoning | ContextChange
 | PermissionDecision | Diagnostic | TaskRelation.
Definition kind_of message := match text "role" message with
 |"function_call"=>ToolInvocation
 |"function_output"|"operation_result"|"tool_receipt"|"after_record"=>ToolResult
 |"reasoning_record"=>Reasoning|"approval_record"|"hook_record"=>PermissionDecision
 |"error"=>Diagnostic|"fork_result"=>TaskRelation|_=>ContextChange end.
Definition call_name message := text "name" (value_or JNull (field "content" message)).
Definition title message := match text "role" message with
 |"function_call"=>call_name message|"function_output"=>"Tool output"
 |"operation_result"=>text "tool" message
 |"tool_receipt"=>text "name" (value_or JNull (field "call" message))
 |"error"=>match field "content" message with Some (JString value)=>value|_=>"Error" end
 |"reasoning_record"=>"Reasoning: "++text "effort" (value_or JNull (field "content" message))
 |"hook_record"=>"Tool permission check"
 |"approval_record"=>"Approval: "++text "decision" (value_or JNull (field "content" message))
 |"after_record"=>"Tool result processing"|"fork_result"=>"Task fork"
 |"context_replacement"=>"Context compacted"|"model_context"=>"Model activity"
 |"task_context"=>if String.eqb (text "type" message) "reasoning_configuration"
    then "Reasoning changed to "++text "effort" message else "Conversation event"
 |_=>"Conversation event" end.
Record face := Face { face_occurrence:N; face_kind:kind; face_title:string; face_source:json }.
Definition native_fork_invocation receipt message :=
 String.eqb (text "role" message) "function_call" &&
 match string_field "call_id" receipt,
   string_field "id" (value_or JNull (field "content" message)),
   string_field "name" (value_or JNull (field "content" message)) with
 |Some receipt_id,Some invocation_id,Some name=>
   String.eqb receipt_id invocation_id && String.eqb name "fork_task"
 |_,_,_=>false end.
Definition fork_result_source history message :=
 if String.eqb (text "role" message) "function_output" &&
    String.eqb (text "receipt_kind" message) "fork_result" &&
    existsb (native_fork_invocation message) history
 then Codec.replace "role" (JString "fork_result") message else message.
Definition faces history values := map (fun entry=>
 let source:=fork_result_source history (snd entry) in
 Face (N.of_nat (fst entry)) (kind_of source) (title source) source) values.
Definition result_detail message := (if flag "is_error" message then "Error" else "Result")++"
"++
 render_json (value_or JNull (field "content" message)).
Definition detail message := match text "role" message with
 |"function_call"=>call_name message++"
"++
   render_json (value_or JNull (field "arguments" (value_or JNull (field "content" message))))
 |"function_output"=>result_detail message
 |"fork_result"=>"Task fork · call "++text "call_id" message++"\n"++
   render_json (value_or JNull (field "content" message))
 |"operation_result"=>text "tool" message++"
"++result_detail message
 |"tool_receipt"=>text "name" (value_or JNull (field "call" message))++"
"++result_detail message
 |"approval_record"=>render_json message
 |"hook_record"|"after_record"|"model_context"=>render_json (value_or JNull (field "content" message))
 |"error"=>match field "content" message with Some (JString value)=>value|_=>title message end
 |"context_replacement"=>"Context compacted; original conversation retained."
 |_=>title message end.
Definition summary history values :=
 match latest_failure values with
 |Some occurrence=>match find (fun entry=>Nat.eqb occurrence (fst entry)) values with
   |Some entry=>"Failure: "++title (fork_result_source history (snd entry))++" · "++Numbers.show_nat (List.length values)++" events"
   |None=>"Activity" end
 |None=>match rev values with
   |[]=>"Activity"|entry::_=>title (fork_result_source history (snd entry))++" · "++Numbers.show_nat (operation_count values)++" operations" end
 end.
Definition disclosed (group:N) (values:list(N*N*bool)) (attention:N) :=
 match find (fun entry=>let '(id,_,_):=entry in N.eqb group id) values with
 |Some (_,_,expanded)=>expanded|None=>negb (N.eqb attention 0) end.
