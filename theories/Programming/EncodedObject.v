From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json TextJson.

(** Encoded argument objects retain the member AST returned by the text parser.
    The only constructor consumes the declared nesting budget; clients cannot
    manufacture an object that bypasses this boundary. *)
Module Type Object.
 Parameter t : nat -> Set.
 Parameter parse : forall nesting, string -> option (t nesting).
 Parameter members : forall {nesting}, t nesting -> list (string * json).
 Parameter parsed_members : forall nesting source value,
   parse nesting source = Some value ->
   TextJson.parse_json_members_at nesting source = Some (JObject (members value)).
 Parameter construct_members : forall nesting source fields,
   TextJson.parse_json_members_at nesting source = Some (JObject fields) ->
   exists value, parse nesting source = Some value /\ members value = fields.
End Object.
Module Admitted : Object.
 Definition t (_ : nat) := list (string * json).
 Definition parse nesting source : option (t nesting) :=
   match TextJson.parse_json_members_at nesting source with
   | Some (JObject fields) => Some fields | _ => None end.
 Definition members {nesting} (value : t nesting) := value.
 Theorem parsed_members : forall nesting source value,
   parse nesting source = Some value ->
   TextJson.parse_json_members_at nesting source = Some (JObject (members value)).
 Proof.
   intros nesting source value; unfold parse.
   destruct (TextJson.parse_json_members_at nesting source) as [parsed|] eqn:Parsed;
     [destruct parsed|]; intros Chosen; try discriminate; inversion Chosen; subst; reflexivity.
 Qed.
 Theorem construct_members : forall nesting source fields,
   TextJson.parse_json_members_at nesting source = Some (JObject fields) ->
   exists value, parse nesting source = Some value /\ members value = fields.
 Proof. intros nesting source fields Parsed; exists fields; unfold parse; rewrite Parsed; split; reflexivity. Qed.
End Admitted.
Definition value {nesting} (object : Admitted.t nesting) := JObject (Admitted.members object).
Definition spelling {nesting} (object : Admitted.t nesting) := TextJson.render_json (value object).
