From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Schema.
From Selvedge.Kernel Require Commands.
From Selvedge.Generated Require Commands.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require CardDecisions.
From Selvedge.Browser.Session Require Input ObjectActions ObjectActionsProof.
From Selvedge.Browser.Session Require Authoring Runtime State.

Module K := Selvedge.Kernel.Commands.
Module G := Selvedge.Generated.Commands.
Import ListNotations.
Open Scope string_scope.

(** Moving and linking a card are decisions about a card at an observed
    revision. Terminals can inspect the alternatives before choosing a command.
    The browser can open a selector or offer a drop target. Both must retain
    the source revision and submit the proposal selected from the observation.
    The service still assesses and executes the command against its own world,
    which may change before submission. *)
Theorem browser_card_choice_uses_published_opportunity snapshot state card decision key action :
  ObjectActions.active_decision state (CardActions card) = Some decision ->
  ObjectActions.resolve snapshot state (CardActions card) key = Some action ->
  exists opportunity now selected accepted,
    CardDecisions.observe snapshot card = Some opportunity /\
    State.now state = Some now /\
    In selected (CardDecisions.choices decision opportunity) /\
    ObjectActions.action_key action = ObjectActions.choice_key selected /\
    ObjectActions.action_operation action = ObjectActions.NativeCommand accepted /\
    ObjectActions.action_confirmation action = None /\
    ObjectActions.action_status action =
      ObjectActions.availability snapshot state (CardActions card) action /\
    Schema.decode_command K.command_specs
      (G.encode (CardDecisions.proposal opportunity now selected)) = Some accepted.
Proof.
  intros Active. unfold ObjectActions.resolve. rewrite Active.
  unfold ObjectActions.find_choice.
  destruct (CardDecisions.observe snapshot card) as [opportunity|] eqn:Observed;
    [|discriminate].
  destruct (State.now state) as [now|] eqn:Clock; [|discriminate].
  cbn [bind].
  destruct (find (fun candidate => String.eqb key (ObjectActions.choice_key candidate))
    (CardDecisions.choices decision opportunity)) as [selected|] eqn:Found; [|discriminate].
  apply find_some in Found as [Selected Key].
  cbn [bind].
  unfold ObjectActions.choice_declaration, ObjectActions.native.
  destruct (Schema.decode_command K.command_specs
    (G.encode (CardDecisions.proposal opportunity now selected))) as [accepted|] eqn:Decoded;
    [|discriminate].
  intros Result. inversion Result; subst action.
  exists opportunity, now, selected, accepted.
  repeat split; try assumption; reflexivity.
Qed.

Theorem browser_selector_dispatch_uses_current_choice snapshot state card decision key action layer rest :
  State.layers (State.navigation_state state) = layer :: rest ->
  State.layer_panel layer = State.CardDecisionPanel card decision ->
  ObjectActions.resolve snapshot state (CardActions card) key = Some action ->
  exists accepted,
    ObjectActions.command action = Some accepted /\
    ObjectActions.action_revision state (CardActions card) = State.layer_occurrence layer /\
    ObjectActions.action_status action =
      ObjectActions.availability snapshot state (CardActions card) action /\
    Runtime.menu_action snapshot (CardActions card) key (State.layer_occurrence layer) state =
      match ObjectActions.action_status action with
      | ObjectActions.Available => Authoring.issue accepted State.DirectSubmission state
      | _ => Authoring.fail state "This action has not been admitted against the current state."
      end.
Proof.
  intros Layers Panel Resolved.
  assert (Active : ObjectActions.active_decision state (CardActions card) = Some decision).
  { unfold ObjectActions.active_decision. now rewrite Layers, Panel, N.eqb_refl. }
  destruct (browser_card_choice_uses_published_opportunity _ _ _ _ _ _ Active Resolved)
    as [opportunity [now [selected [accepted [_ [_ [_ [_ [Operation [Confirmation [Availability _]]]]]]]]]]].
  exists accepted. repeat split.
  - unfold ObjectActions.command. now rewrite Operation.
  - unfold ObjectActions.action_revision. now rewrite Layers, Panel, N.eqb_refl.
  - exact Availability.
  - unfold Runtime.menu_action. rewrite Layers, Panel.
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
