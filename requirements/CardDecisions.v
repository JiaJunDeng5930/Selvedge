From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Programming Require Schema.
From Selvedge.Kernel Require Commands.
From Selvedge.Generated Require Commands.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require CardDecisions.
From Selvedge.Browser.Session Require Input ObjectActions ObjectActionsProof.
From Selvedge.Browser.Session Require Authoring Navigation Runtime State.

Module K := Selvedge.Kernel.Commands.
Module G := Selvedge.Generated.Commands.
Import ListNotations.
Open Scope string_scope.

(** The shared card decision model supplies the choices, the observed card
    revision and the proposal. The browser decides which choices to present
    and requests assessment for the same proposal it can submit. A drag uses
    the shared move command construction. The service still checks the current
    world when the command is submitted. *)
Theorem browser_card_choice_uses_published_opportunity snapshot state card decision key action :
  ObjectActions.active_decision state (CardActions card) = Some decision ->
  ObjectActions.resolve snapshot state (CardActions card) key = Some action ->
  exists opportunity now selected accepted,
    CardDecisions.observe snapshot card = Some opportunity /\
    State.now state = Some now /\
    In selected (CardDecisions.choices decision opportunity) /\
    key = ObjectActions.choice_key selected /\
    ObjectActions.action_key action = key /\
    ObjectActions.action_operation action = ObjectActions.NativeCommand accepted /\
    ObjectActions.action_confirmation action = None /\
    ObjectActions.action_status action =
      ObjectActions.availability snapshot state (CardActions card) action /\
    Schema.decode_command K.command_specs
      (G.encode (CardDecisions.proposal opportunity now selected)) = Some accepted.
Proof.
  intros Active. unfold ObjectActions.resolve. rewrite Active.
  destruct (String.eqb key ObjectActions.add_to_board_key || String.eqb key ObjectActions.open_board_card_key);
    [discriminate|].
  unfold ObjectActions.find_choice.
  destruct (CardDecisions.observe snapshot card) as [opportunity|] eqn:Observed;
    [|discriminate].
  destruct (State.now state) as [now|] eqn:Clock; [|discriminate].
  cbn [bind].
  destruct (find (fun candidate => String.eqb key (ObjectActions.choice_key candidate))
    (CardDecisions.choices decision opportunity)) as [selected|] eqn:Found; [|discriminate].
  apply find_some in Found as [Selected Key]. apply String.eqb_eq in Key.
  cbn [bind].
  unfold ObjectActions.choice_declaration, ObjectActions.native.
  destruct (Schema.decode_command K.command_specs
    (G.encode (CardDecisions.proposal opportunity now selected))) as [accepted|] eqn:Decoded;
    [|discriminate].
  intros Result. inversion Result; subst action.
  exists opportunity, now, selected, accepted.
  repeat split; try assumption; try reflexivity.
  cbn [ObjectActions.observe ObjectActions.action_key]. symmetry. exact Key.
Qed.

Theorem browser_selector_dispatch_uses_current_choice namespace snapshot lagged state card decision key action layer rest :
  State.layers (State.navigation_state state) = layer :: rest ->
  State.layer_panel layer = State.CardDecisionPanel card decision ->
  ObjectActions.resolve snapshot state (CardActions card) key = Some action ->
  exists accepted,
    ObjectActions.command action = Some accepted /\
    ObjectActions.action_status action =
      ObjectActions.availability snapshot state (CardActions card) action /\
    Authoring.refresh_input snapshot (Input.MenuAction (CardActions card) key (State.layer_occurrence layer)) state =
      Authoring.ensure_request snapshot (ObjectActions.action_owner (CardActions card) action)
        (State.layer_occurrence layer) accepted state /\
    let result := Runtime.core namespace snapshot lagged
      (Input.MenuAction (CardActions card) key (State.layer_occurrence layer)) state in
    match ObjectActions.action_status action with
    | ObjectActions.Available =>
      let occurrence := State.layer_occurrence layer in
      result = Authoring.issue accepted (State.MenuSubmission occurrence)
        (Navigation.result_state (Navigation.modify_top occurrence
          (fun current => Some (set State.layer_feedback (fun _ => None) current)) state))
    | _ => Authoring.result_effects result = []
    end.
Proof.
  intros Layers Panel Resolved.
  assert (Active : ObjectActions.active_decision state (CardActions card) = Some decision).
  { unfold ObjectActions.active_decision. now rewrite Layers, Panel, N.eqb_refl. }
  destruct (browser_card_choice_uses_published_opportunity _ _ _ _ _ _ Active Resolved)
    as [opportunity [now [selected [accepted [_ [_ [_ [_ [_ [Operation [Confirmation [Availability _]]]]]]]]]]]].
  assert (Command : ObjectActions.command action = Some accepted).
  { unfold ObjectActions.command. now rewrite Operation. }
  exists accepted. repeat split; try assumption.
  - cbn [Authoring.refresh_input]. rewrite Resolved, Command.
    unfold ObjectActions.action_revision. now rewrite Layers, Panel, N.eqb_refl.
  - cbn [Runtime.core]. unfold Runtime.menu_action. rewrite Layers, Panel.
    unfold Runtime.owns_action_panel. repeat rewrite N.eqb_refl.
    simpl. rewrite Resolved, Operation, Confirmation.
    now destruct (ObjectActions.action_status action).
Qed.

Export ObjectActionsProof (available_native_has_current_admission).

Theorem browser_drop_uses_shared_move_proposal snapshot state card revision now stage target :
  Authoring.input_command snapshot state (Input.CardPlaced card revision now stage target) =
    Schema.decode_command K.command_specs
      (G.encode (CardDecisions.move_proposal card revision now stage target)).
Proof. reflexivity. Qed.
