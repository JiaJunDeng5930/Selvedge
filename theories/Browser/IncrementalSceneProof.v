From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Browser Require Application Layout Document.
From Selvedge.Browser.Presentation Require LiveUpdate View Layers.
From Selvedge.Browser.Scene Require Surface.
From Selvedge.Browser.Session Require State Authoring.
Import ListNotations.
Module A:=Application.
Module S:=Surface.
Module V:=View.
Module SS:=Selvedge.Browser.Session.State.

Theorem retained_live_preview_has_no_action before after view key gesture input :
 LiveUpdate.retains_preview before after=true ->
 S.node_actions (Selvedge.Browser.AuditReading.in_view view before)=[] /\
 S.node_actions (Selvedge.Browser.AuditReading.in_view view after)=[] /\
 S.resolve_node key gesture input (Selvedge.Browser.AuditReading.in_view view before)=None /\
 S.resolve_node key gesture input (Selvedge.Browser.AuditReading.in_view view after)=None.
Proof.
 unfold LiveUpdate.retains_preview. intros Retains.
 apply Bool.andb_true_iff in Retains as [_ Passive].
 destruct before as [first semantic label role meaning children].
 destruct after as [second semantic' label' role' meaning' children'].
 destruct children; [|discriminate]. destruct children';[|discriminate].
 destruct meaning; try discriminate; destruct meaning'; try discriminate;
 cbn [Selvedge.Browser.AuditReading.in_view Selvedge.Browser.AuditReading.scope_meaning S.node_actions
   S.meaning_actions S.resolve_node S.resolve_meaning];
 repeat match goal with |- context [String.eqb ?x ?y] => destruct (String.eqb x y) end;
 destruct gesture; repeat split.
Qed.

Theorem projected_picker_overlays_are_the_scene_overlays context overlays :
 A.projected_picker_overlays context=Some overlays ->
 exists scene, A.scene (A.prepared_world context)(A.prepared_state context)(A.prepared_environment context)=Some scene /\
 S.overlays scene=overlays.
Proof.
 unfold A.projected_picker_overlays, A.projected_overlays_with, A.scene.
 destruct (A.prepared_environment context) as [env|] eqn:Env; cbn [bind]; [|discriminate].
 destruct (Json.equal (A.prepared_world context) JNull).
 { intro E. injection E as E; subst overlays. eexists. split; reflexivity. }
 unfold A.surface.
 destruct (A.capacity env) as [size|] eqn:Capacity; [|discriminate].
 cbn [bind option_map].
 unfold A.underlying_layers, A.top_picker.
 destruct (SS.layers(SS.navigation_state(A.prepared_state context))) as [|layer layers] eqn:Layers.
 - intro H. injection H as H; subst overlays. eexists. split; [reflexivity|].
   unfold V.view, V.relocate_details_trigger. now rewrite Layers.
 - cbn [hd_error bind]. destruct (Authoring.model_picker_layer layer) eqn:Picker;
   cbn [bind tl forallb].
   + destruct (forallb A.picker_underlay layers); [|discriminate].
     intro H. injection H as H; subst overlays. eexists. split; [reflexivity|].
     unfold V.view, V.relocate_details_trigger. rewrite Layers.
     unfold Authoring.model_picker_layer in Picker.
     destruct (SS.layer_panel layer); try discriminate; reflexivity.
   + destruct (A.picker_underlay layer && forallb A.picker_underlay layers) eqn:Underlay; [|discriminate].
     intro H. injection H as H; subst overlays. eexists. split; [reflexivity|].
     unfold V.view, V.relocate_details_trigger. rewrite Layers.
     apply Bool.andb_true_iff in Underlay as [Side _].
     unfold A.picker_underlay in Side. destruct (SS.layer_panel layer); try discriminate; reflexivity.
Qed.

Definition same_overlay_scope (first second:S.node Selvedge.Browser.Session.Input.input) :=
 S.node_key first=S.node_key second /\
 S.node_meaning first=S.node_meaning second /\
 A.as_picker first=A.as_picker second.

Lemma same_scope_refl node : same_overlay_scope node node.
Proof. repeat split. Qed.

Lemma projected_layer_keeps_scope snapshot state size compact layer :
 same_overlay_scope
  (Layers.layer_view snapshot state size compact layer)
  (Layers.layer_scope_view snapshot state size compact layer).
Proof.
 unfold same_overlay_scope, Layers.layer_view, Layers.layer_scope_view, Layers.layer_view_with_side.
 destruct (SS.layer_panel layer); repeat split.
Qed.

Lemma projected_overlay_order snapshot state size compact :
 Forall2 same_overlay_scope (V.view_overlays snapshot state size compact)
                            (V.view_overlay_scopes snapshot state size compact).
Proof.
 assert (All: forall nodes, Forall2 same_overlay_scope nodes nodes).
 { induction nodes; constructor; auto using same_scope_refl. }
 assert (Layers: forall layers, Forall2 same_overlay_scope
   (map (Layers.layer_view snapshot state size compact) layers)
   (map (Layers.layer_scope_view snapshot state size compact) layers)).
 { induction layers; simpl; constructor; auto using projected_layer_keeps_scope. }
 unfold V.view_overlays, V.view_overlay_scopes, V.view_overlays_with.
 destruct partition. repeat apply Forall2_app; auto.
Qed.

Lemma projected_modal_order full projected :
 Forall2 same_overlay_scope full projected ->
 Forall2 same_overlay_scope (filter S.is_modal_node full)(filter S.is_modal_node projected).
Proof.
 induction 1 as [|x y l r Scope More IH]; simpl; [constructor|].
 assert (Modal:S.is_modal_node x=S.is_modal_node y).
 { unfold S.is_modal_node. destruct Scope as [_ [Meaning _]]. now rewrite Meaning. }
 rewrite Modal. destruct (S.is_modal_node y); auto using Forall2_cons.
Qed.

Lemma reverse_overlay_order full projected :
 Forall2 same_overlay_scope full projected ->
 Forall2 same_overlay_scope (rev full)(rev projected).
Proof.
 induction 1; simpl; [constructor|].
 apply Forall2_app; auto.
Qed.

Lemma projected_active_picker full projected :
 Forall2 same_overlay_scope full projected ->
 bind (A.modal_from_overlays full) A.as_picker =
 bind (A.modal_from_overlays projected) A.as_picker.
Proof.
 intro Eq. unfold A.modal_from_overlays.
 pose proof (reverse_overlay_order _ _ (projected_modal_order _ _ Eq)) as Ordered.
 inversion Ordered as [|x y xs ys Scope]; cbn; [reflexivity|].
 exact (proj2 (proj2 Scope)).
Qed.

Lemma projected_focus_scopes full projected :
 Forall2 same_overlay_scope full projected ->
 Document.surface_scopes(filter S.is_modal_node full) =
 Document.surface_scopes(filter S.is_modal_node projected).
Proof.
 intro Eq. apply projected_modal_order in Eq. unfold Document.surface_scopes.
 f_equal. induction Eq as [|x y xs ys Scope More IH]; simpl; [reflexivity|].
 destruct Scope as [Key [Meaning _]]. now rewrite Key, Meaning, IH.
Qed.

Theorem scope_only_projection_retains_picker_and_focus context scopes :
 A.projected_picker_scopes context=Some scopes ->
 exists full, A.projected_picker_overlays context=Some full /\
 bind(A.modal_from_overlays full)A.as_picker=bind(A.modal_from_overlays scopes)A.as_picker /\
 Document.surface_scopes(filter S.is_modal_node full)=
 Document.surface_scopes(filter S.is_modal_node scopes).
Proof.
 unfold A.projected_picker_scopes, A.projected_picker_overlays, A.projected_overlays_with.
 destruct (A.prepared_environment context) as [env|]; cbn [bind]; [|discriminate].
 destruct (Json.equal (A.prepared_world context) JNull).
 { intro E. injection E as E; subst scopes. exists []. repeat split. }
 destruct (A.capacity env) as [size|]; cbn [bind]; [|discriminate].
 destruct (forallb A.picker_underlay (A.underlying_layers context)); [|discriminate].
 intro E; injection E as E; subst scopes.
 eexists. split; [reflexivity|]. split;
 auto using projected_active_picker, projected_focus_scopes, projected_overlay_order.
Qed.
