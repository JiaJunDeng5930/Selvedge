From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Browser Require Import Document.
Import ListNotations.

(** Find the actual event target, including controls inside a labelled field wrapper. *)
Fixpoint target_events (key : string) (value : node) : option (list event_binding) :=
  let fix children_events children := match children with
    | [] => None
    | first :: rest => match target_events key first with
        | Some events => Some events | None => children_events rest end end in
  match value with
  | Element _ _ attrs _ events children _ =>
      if existsb (fun p => String.eqb (property_name p) "data-key" &&
                          String.eqb (property_value p) key) attrs
      then Some events else children_events children
  | PortalNode _ _ children => children_events children
  | _ => None end.
Definition native_control role := match role with
  | Button | Field | Select | Checkbox | Form => true | _ => false end.
Theorem disabled_controls_have_no_bindings : forall mode system_dark role key label value checked multiline action attrs source children,
  native_control role = true ->
  target_events key (render_scene mode system_dark (Scene role key label value true checked multiline action attrs source children)) = Some [].
Proof.
  intros; destruct role; try discriminate;
  cbn [native_control render_scene target_events];
  unfold role_properties; cbn;
  repeat rewrite String.eqb_refl; reflexivity.
Qed.

Theorem decoding_a_kind_is_exact : forall role,
  decode_kind (kind_name role) = Some role.
Proof. destruct role; reflexivity. Qed.

Theorem decoded_attributes_are_allowed : forall source attribute,
  In attribute (decode_properties source) -> allowed_attribute (property_name attribute) = true.
Proof.
  intros source attribute contained; destruct source; simpl in contained; try contradiction.
  apply in_flat_map in contained as [[name value] [present contained]].
  destruct (allowed_attribute name) eqn:allowed; [|contradiction].
  destruct value; simpl in contained; try contradiction.
  all: destruct contained as [same | impossible]; [subst attribute; exact allowed | contradiction].
Qed.

Theorem generic_attributes_cannot_install_event_handlers : forall source attribute,
  In attribute (decode_properties source) ->
  starts_with "on" (property_name attribute) = false.
Proof.
  intros source attribute contained.
  pose proof (decoded_attributes_are_allowed source attribute contained) as allowed.
  unfold allowed_attribute in allowed.
  apply existsb_exists in allowed as [name [member same]].
  apply String.eqb_eq in same.
  assert (safe : forallb (fun name => negb (starts_with "on" name)) allowed_attributes = true) by reflexivity.
  apply forallb_forall with (x := name) in safe; [|exact member].
  rewrite <- same in safe; now apply Bool.negb_true_iff in safe.
Qed.

Theorem image_sources_have_attachment_route_prefix : forall source property,
  In property (resource_properties Image source) ->
  property_name property = "src" ->
  starts_with "/api/board/attachments/" (property_value property) = true.
Proof.
  intros source property contained name; unfold resource_properties in contained.
  destruct (starts_with _ _) eqn:local; [|contradiction].
  simpl in contained; destruct contained as [same | [same | impossible]];
    [subst property; exact local | subst property; discriminate | contradiction].
Qed.
