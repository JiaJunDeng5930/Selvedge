From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Interaction.Session Require Draft.
From Selvedge.Features Require Domain.
From Selvedge.Interaction.Experience Require Model.

Inductive availability := Available | NeedsDirectoryObservation | Unavailable (reason : string) | Busy (reason : string).
Definition domain_availability(value:Selvedge.Interaction.Experience.Model.availability):availability:=match value with
|Selvedge.Interaction.Experience.Model.Available=>Available
|Selvedge.Interaction.Experience.Model.Unavailable reason=>Unavailable reason end.
Inductive prominence := Primary | Secondary | Destructive.

Record control (Action : Type) := Control {
  control_identity : string;
  control_label : string;
  control_prominence : prominence;
  control_input : Action;
  control_availability : availability
}.
Arguments Control {Action}.
Arguments control_identity {Action}.
Arguments control_label {Action}.
Arguments control_prominence {Action}.
Arguments control_input {Action}.
Arguments control_availability {Action}.

Definition available value := match value with Unavailable _ | Busy _ => false | _ => true end.

Definition map_control {A B} (f : A -> B) (value : control A) : control B :=
  Control (control_identity value) (control_label value) (control_prominence value)
    (f (control_input value)) (control_availability value).

Definition observe_control {A}(observe:A->availability)(value:control A):control A:=
 Control(control_identity value)(control_label value)(control_prominence value)(control_input value)
  (match control_availability value with Available=>observe(control_input value)|other=>other end).

Record edit_control (Action : Type) := EditControl {
  editing_entry : Fields.entry;
  editing_observation : Fields.observed;
  editing_buffer : option string;
  editing_choices : list Fields.choice_value;
  editing_selection : option Draft.selection;
  editing_availability : availability;
  editing_input : option (json -> option Action);
  editing_selection_input : option (json -> option Action);
  editing_key_input : option (json -> option Action)
}.
Arguments EditControl {Action}.
Arguments editing_entry {Action}.
Arguments editing_observation {Action}.
Arguments editing_buffer {Action}.
Arguments editing_choices {Action}.
Arguments editing_selection {Action}.
Arguments editing_availability {Action}.
Arguments editing_input {Action}.
Arguments editing_selection_input {Action}.
Arguments editing_key_input {Action}.

Definition map_edit_control {A B} (f : A -> B) (value : edit_control A) : edit_control B :=
  EditControl (editing_entry value) (editing_observation value) (editing_buffer value)
    (editing_choices value) (editing_selection value) (editing_availability value)
    (option_map (fun receive input => option_map f (receive input)) (editing_input value))
    (option_map (fun receive input => option_map f (receive input)) (editing_selection_input value))
    (option_map (fun receive input => option_map f (receive input)) (editing_key_input value)).

Record capacity := Capacity {
  navigation_beside_content : bool;
  details_beside_timeline : bool
}.

Inductive layer_kind := ModalDialog | AnchoredMenu | TrailingDetails.
Record layer_behavior (Action : Type) := LayerBehavior {
  layer_presentation : layer_kind;
  layer_beside : bool;
  layer_occurrence : N;
  layer_initial_attention : string;
  layer_return_attention : string;
  layer_fallback_attention : string;
  layer_anchor : string;
  layer_dismissal : Action;
  layer_outside : bool;
  layer_escape : bool
}.
Arguments LayerBehavior {Action}.
Arguments layer_presentation {Action}.
Arguments layer_beside {Action}.
Arguments layer_occurrence {Action}.
Arguments layer_initial_attention {Action}.
Arguments layer_return_attention {Action}.
Arguments layer_fallback_attention {Action}.
Arguments layer_anchor {Action}.
Arguments layer_dismissal {Action}.
Arguments layer_outside {Action}.
Arguments layer_escape {Action}.

Definition modal_layer {A} (value : layer_behavior A) :=
  match layer_presentation value with
  | TrailingDetails => negb (layer_beside value)
  | ModalDialog | AnchoredMenu => true
  end.

Definition map_layer_behavior {A B} (f : A -> B) (value : layer_behavior A) :=
  LayerBehavior (layer_presentation value) (layer_beside value) (layer_occurrence value)
    (layer_initial_attention value) (layer_return_attention value)
    (layer_fallback_attention value) (layer_anchor value) (f (layer_dismissal value))
    (layer_outside value) (layer_escape value).

Record card_face := CardFace {
  card_identity : N;
  card_reference : string;
  card_title : string;
  card_description : string;
  card_priority : Selvedge.Features.Domain.priority;
  card_pinned : bool;
  card_status : string;
  card_project : string;
  card_labels : list string;
  card_owner : string;
  card_updated : string
}.
