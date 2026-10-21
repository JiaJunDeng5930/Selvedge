From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Interaction Require Import Codec Identity.
Import ListNotations.
Open Scope string_scope.

Inductive action_owner := DraftOwner (owner:editor) | MenuOwner (subject:menu_subject)(action_key:string).
Definition menu_subject_eq_dec : forall a b:menu_subject,{a=b}+{a<>b}.
Proof. decide equality;apply N.eq_dec. Defined.
Definition action_owner_eq_dec : forall a b:action_owner,{a=b}+{a<>b}.
Proof. decide equality;auto using editor_eq_dec,menu_subject_eq_dec,string_dec. Defined.
Definition same_owner a b := if action_owner_eq_dec a b then true else false.
Definition encode_owner value := match value with
|DraftOwner e=>JObject[("kind",JString "draft");("editor",encode_editor e)]
|MenuOwner subject key=>JObject[("kind",JString "menu");("subject",encode_menu_subject subject);("action",JString key)]end.
Definition decode_owner source := match string_field "kind" source with
|Some "draft"=>e<-bind(field "editor" source)decode_editor;;Some(DraftOwner e)
|Some "menu"=>subject<-bind(field "subject" source)decode_menu_subject;;key<-string_field "action" source;;Some(MenuOwner subject key)
|_=>None end.

Record request := Request {
  request_owner : action_owner;
  request_revision : N;
  request_sequence : N;
  request_command : command_value command_specs
}.
Inductive admission := Admitted | Refused (code message : string).
Record observation := Observation {
  observed_owner : action_owner;
  observed_revision : N;
  observed_sequence : N;
  observed_admission : admission
}.
Definition encode_request value := JObject [
  ("editor", encode_owner (request_owner value));
  ("revision", number (request_revision value));
  ("sequence", number (request_sequence value));
  ("command", encode_command (request_command value))].
Definition decode_request source :=
  e <- bind (field "editor" source) decode_owner ;;
  revision <- natural_field "revision" source ;;
  sequence <- natural_field "sequence" source ;;
  command <- bind (field "command" source) (decode_command command_specs) ;;
  Some (Request e revision sequence command).
Definition encode_observation value := JObject [
  ("editor", encode_owner (observed_owner value));
  ("revision", number (observed_revision value));
  ("sequence", number (observed_sequence value));
  ("admitted", JBool (match observed_admission value with Admitted => true | _ => false end));
  ("refusal", match observed_admission value with Admitted => JNull
    | Refused code message => JObject [("code", JString code); ("message", JString message)] end)].
Definition decode_observation source :=
  e <- bind (field "editor" source) decode_owner ;;
  revision <- natural_field "revision" source ;;
  sequence <- natural_field "sequence" source ;;
  admitted <- bool_field "admitted" source ;;
  refusal <- field "refusal" source ;;
  result <- (if admitted then match refusal with JNull => Some Admitted | _ => None end
    else code <- string_field "code" refusal ;; message <- string_field "message" refusal ;;
      Some (Refused code message)) ;;
  Some (Observation e revision sequence result).
Definition correlated request observation :=
  same_owner (request_owner request) (observed_owner observation) &&
  N.eqb (request_revision request) (observed_revision observation).
Definition current_owned owner revision sequence observation :=
  same_owner owner (observed_owner observation) &&
  N.eqb revision (observed_revision observation) &&
  N.eqb sequence (observed_sequence observation).
Definition current e := current_owned(DraftOwner e).
Definition same_command (left right:command_value command_specs) := Json.equal
  (JObject(remove_field "observed_at"(object_fields(encode_command left))))
  (JObject(remove_field "observed_at"(object_fields(encode_command right)))).
Definition matches owner revision sequence command request :=
  same_owner owner(request_owner request) && N.eqb revision(request_revision request) &&
  N.eqb sequence(request_sequence request) && same_command command(request_command request).

Theorem current_observation_retains_action_and_world owner revision sequence observation :
  current_owned owner revision sequence observation = true ->
  observed_owner observation = owner /\ observed_revision observation = revision /\
  observed_sequence observation = sequence.
Proof.
  unfold current_owned,same_owner. repeat rewrite Bool.andb_true_iff.
  destruct(action_owner_eq_dec owner(observed_owner observation));simpl;intros [Same Version].
  - destruct Same as [_ Revision]. apply N.eqb_eq in Revision,Version. auto.
  - destruct Same as [Impossible _]. discriminate.
Qed.
