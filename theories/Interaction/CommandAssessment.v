From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs Numbers.
From Selvedge.Programming Require Import Schema Resource.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Features Require BoardFacts.
From Selvedge.Interaction Require Import Codec Identity.
Import ListNotations.
Open Scope string_scope.

Definition same_owner (left right : option N) :=
 if editor_eq_dec (Card left) (Card right) then true else false.
Definition encode_owner owner := JObject [("kind", JString "draft"); ("editor", encode_editor (Card owner))].
Definition decode_owner source :=
 match string_field "kind" source, bind (field "editor" source) decode_editor with
 | Some "draft", Some (Card owner) => Some owner
 | _, _ => None end.

Record request := Request {
  request_owner : option N;
  request_revision : N;
  request_facts : json;
  request_command : command_value command_specs
}.
Inductive admission := Admitted | Refused (code message : string).
Record observation := Observation {
  observed_owner : option N;
  observed_revision : N;
  observed_sequence : N;
  observed_facts : json;
  observed_admission : admission;
  observed_card_save_consequence : option BoardFacts.save_consequence
}.
Definition owned_assessment owner (r : resource request observation) :=
  match resource_request r with Some request => same_owner owner (request_owner request) | None => false end.
Definition request_fields value := [
  ("editor", encode_owner (request_owner value));
  ("revision", number (request_revision value));
  ("command", encode_command (request_command value))].
Definition encode_request value := JObject (("card_save_facts", request_facts value) :: request_fields value).
Definition encode_http_request sequence value := JObject (("sequence", number sequence) :: request_fields value).
Definition decode_request source :=
  e <- bind (field "editor" source) decode_owner ;;
  revision <- natural_field "revision" source ;;
  facts <- field "card_save_facts" source ;;
  command <- bind (field "command" source) (decode_command command_specs) ;;
  Some (Request e revision facts command).
Definition encode_observation value := JObject [
  ("editor", encode_owner (observed_owner value));
  ("revision", number (observed_revision value));
  ("sequence", number (observed_sequence value));
  ("card_save_facts", observed_facts value);
  ("admitted", JBool (match observed_admission value with Admitted => true | _ => false end));
  ("refusal", match observed_admission value with Admitted => JNull
    | Refused code message => JObject [("code", JString code); ("message", JString message)] end);
  ("card_save_consequence",match observed_card_save_consequence value with
   |Some consequence=>JString(BoardFacts.save_consequence_name consequence)|None=>JNull end)].
Definition decode_observation source :=
  e <- bind (field "editor" source) decode_owner ;;
  revision <- natural_field "revision" source ;;
  sequence <- natural_field "sequence" source ;;
  facts <- field "card_save_facts" source ;;
  admitted <- bool_field "admitted" source ;;
  refusal <- field "refusal" source ;;
  result <- (if admitted then match refusal with JNull => Some Admitted | _ => None end
    else code <- string_field "code" refusal ;; message <- string_field "message" refusal ;;
      Some (Refused code message)) ;;
  consequence <- field "card_save_consequence" source ;;
  consequence <- (match consequence with JNull=>Some None
    |JString name=>option_map (@Some BoardFacts.save_consequence)(BoardFacts.save_consequence_of_name name)
    |_=>None end) ;;
  Some (Observation e revision sequence facts result consequence).
Definition correlated request observation :=
  same_owner (request_owner request) (observed_owner observation) &&
  N.eqb (request_revision request) (observed_revision observation).
Definition current owner revision facts observation :=
  same_owner owner (observed_owner observation) &&
  N.eqb revision (observed_revision observation) &&
  Json.equal facts (observed_facts observation).
Definition semantic_command (command : command_value command_specs) :=
  JObject (remove_field "observed_at" (object_fields (encode_command command))).
Definition same_command left right := Json.equal (semantic_command left) (semantic_command right).
Definition matches owner revision command request :=
  same_owner owner (request_owner request) && N.eqb revision (request_revision request) &&
  same_command command (request_command request).

Definition already_observed owner revision sequence facts command (r : resource request observation) :=
 match r with
 | Loaded _ request observation =>
   matches owner revision command request &&
   (current owner revision facts observation ||
    (* A reply can run ahead of the browser's commit stream. Let that stream
       catch up before retrying the request against the same displayed facts. *)
    (N.ltb sequence (observed_sequence observation) && Json.equal facts (request_facts request)))
 | Loading _ request | Failed _ request _ =>
   matches owner revision command request && Json.equal facts (request_facts request)
 | Dormant => false end.

Theorem current_observation_retains_action_and_facts owner revision facts observation :
  current owner revision facts observation = true ->
  observed_owner observation = owner /\ observed_revision observation = revision /\
  observed_facts observation = facts.
Proof.
  unfold current,same_owner. repeat rewrite Bool.andb_true_iff.
  destruct (editor_eq_dec (Card owner) (Card (observed_owner observation))) as [Same|Different].
  - intros [[_ Revision] Facts]. injection Same as Same.
    apply N.eqb_eq in Revision. apply JsonProofs.equal_reflects_equality in Facts. auto.
  - intros [[Impossible _] _]. discriminate.
Qed.

Theorem a_current_card_observation_needs_no_repeat owner revision sequence facts command ticket request result :
  matches owner revision command request = true ->
  current owner revision facts result = true ->
  already_observed owner revision sequence facts command (Loaded ticket request result) = true.
Proof. intros Matches Current. cbn [already_observed]. now rewrite Matches, Current. Qed.
