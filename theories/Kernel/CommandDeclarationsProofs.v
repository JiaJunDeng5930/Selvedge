From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Arguments.
From Selvedge.Foundation Require ArgumentDeclaration.
From Selvedge.Kernel Require Import Commands CommandDeclarations NativeTools Inputs InputDecoder Packet.
From Selvedge.Generated Require Commands.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.
Module D := ArgumentDeclaration.

Theorem public_admission_keeps_the_original_command : forall source admitted,
 admit_public source = Some admitted -> public_raw_source admitted = source /\ valid false source = true.
Proof.
 intros source admitted Accepted; unfold admit_public in Accepted.
 destruct (Bool.bool_dec (valid false source) true) as [Admitted | Refused]; [|discriminate].
 inversion Accepted; subst; split; [reflexivity | exact Admitted].
Qed.
Theorem observed_admission_keeps_the_original_command : forall source admitted,
 admit_observed source = Some admitted -> observed_source admitted = source /\ valid true source = true.
Proof.
 intros source admitted Accepted; unfold admit_observed in Accepted.
 destruct (Bool.bool_dec (valid true source) true) as [Admitted | Refused]; [|discriminate].
 inversion Accepted; subst; split; [reflexivity | exact Admitted].
Qed.
Theorem actual_command_decoder_requires_its_raw_declaration : forall source command,
 G.decode source = Some command -> valid true source = true.
Proof.
 intros source command Accepted; rewrite G.decode_observed_declaration in Accepted.
 destruct (valid true source) eqn:Admitted; [reflexivity | discriminate].
Qed.
Theorem omitted_fields_do_not_accept_explicit_invalid_values : forall name description value,
 decode_field (OmittableField name description) None = Some None /\
 (decode_value description value = None ->
  decode_field (OmittableField name description) (Some value) = None).
Proof. intros; split; [reflexivity | intro Invalid; cbn; rewrite Invalid; reflexivity]. Qed.

Theorem title_prompt_uses_the_owning_domain_rule : forall prompt,
 Titles.valid_instructions prompt = D.check title_prompt_declaration (JString prompt).
Proof. reflexivity. Qed.
Theorem controller_identity_uses_the_owning_domain_rule : forall identity,
 RemoteIdentity.controller_valid identity = D.check controller_id_declaration (JString identity).
Proof. reflexivity. Qed.

Theorem native_title_arguments_use_the_owning_domain_rule : forall argument prompt,
 argument_name argument = "task_prompt" ->
 Arguments.type_valid (argument_type_of (refine_argument false "configure_title_settings" argument)) (JString prompt) =
 Titles.valid_instructions prompt.
Proof.
 intros [name description required documentation bounds] prompt Name.
 cbn in Name; subst name; reflexivity.
Qed.
Theorem native_controller_arguments_use_the_owning_domain_rule : forall argument identity,
 argument_name argument = "controller_id" ->
 Arguments.type_valid (argument_type_of (refine_argument false "remote_grant" argument)) (JString identity) =
 RemoteIdentity.controller_valid identity.
Proof.
 intros [name description required documentation bounds] identity Name.
 cbn in Name; subst name; reflexivity.
Qed.
Definition executable_legacy_shape source :=
 match D.parse source with Some D.Reject | None => false | Some _ => true end.
Theorem legacy_content_images_and_chatgpt_shapes_compile :
 executable_legacy_shape (JObject ContentDeclarations.content_schema) = true /\
 executable_legacy_shape (JObject ContentDeclarations.images_schema) = true /\
 executable_legacy_shape ChatgptArguments.args_schema = true.
Proof. vm_compute; repeat split; reflexivity. Qed.

Definition interpretable_schema source :=
 match D.parse source with Some _ => true | None => false end.
(** This is the complete production declaration table, not a second hand-written
    inventory or an assumption that its generated schemas happen to parse. *)
Theorem all_public_command_schemas_are_interpretable :
 forallb (fun specification => interpretable_schema (command_schema specification)) Selvedge.Kernel.Commands.command_specs = true.
Proof. vm_compute. reflexivity. Qed.

Definition command_input source := JObject [("kind",JString "command");("command",source)].
Theorem malformed_commands_are_not_durable : forall source before,
 G.decode source = None ->
 let '(durable,_,_,_) := Packet.transition (command_input source) before in durable = false.
Proof.
 intros source before Rejected.
 assert (Decoded : InputDecoder.decode (command_input source) = None).
 { change (option_map UserCommand (G.decode source) = None). rewrite Rejected; reflexivity. }
 unfold Packet.transition; rewrite Decoded.
 reflexivity.
Qed.
