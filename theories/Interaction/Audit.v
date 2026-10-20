From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
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
