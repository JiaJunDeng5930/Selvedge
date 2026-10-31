From Stdlib Require Import List String Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Input Services.
From Selvedge.Interaction.Session Require State.
From Selvedge.Programming.Presentation Require Import Surface Model.
From Selvedge.Interaction.Presentation Require Import Navigation Pages Layers ServiceControls.
From Selvedge.Programming.Presentation Require Import Construction.
Import ListNotations.
Open Scope string_scope.

Definition pending_notices (state : State.state) : list (node Input.input) :=
 flat_map (fun pending => match State.outcome_unknown pending with
 |None => []
 |Some reason => [information "/workspace" ("request/" ++ show_natural(State.ticket pending))
   Information.Status ("Connection interrupted. Submission status is unknown. " ++ reason)] end)
 (State.awaiting(State.authoring_state state)).

Fixpoint find_presentation_node target (value:node Input.input):option(node Input.input):=
 let 'Node key semantic label role meaning children:=value in
 if String.eqb target key then Some value else
 fold_right(fun child rest=>match find_presentation_node target child with Some found=>Some found|None=>rest end)None children.
Definition find_presentation_nodes target nodes:=
 fold_right(fun child rest=>match find_presentation_node target child with Some found=>Some found|None=>rest end)None nodes.
Fixpoint without_presentation_node target (value:node Input.input):list(node Input.input):=
 let 'Node key semantic label role meaning children:=value in
 if String.eqb target key then []else
 [Node key semantic label role meaning(flat_map(without_presentation_node target)children)].
Definition occurrence_matches occurrence (value:node Input.input):=match layer_region(node_meaning value)with
 |Some behavior=>N.eqb occurrence(layer_occurrence behavior)|None=>false end.
Definition prepend_trigger occurrence trigger (value:node Input.input):=
 let 'Node key semantic label role meaning children:=value in
 if occurrence_matches occurrence value then Node key semantic label role meaning(trigger::children)else value.
(* A modal makes the page and its parent overlays inert. Move the existing
   toggle from either location into the active scope, preserving its authority. *)
Definition relocate_details_trigger state capacity base overlays:=
 match State.layers(State.navigation_state state)with
 |layer::_=>match State.layer_panel layer with
  |State.InformationPanel(State.TaskDetails task)=>
   match find_presentation_nodes(State.layer_trigger layer)(base++overlays)%list with
   |Some trigger=>match node_meaning trigger with
    |PanelToggle _ control=>match control_input control with
      |Input.OpenInformation(State.TaskDetails actual) _=>
       if N.eqb task actual&&modal_layer(Layers.behavior state capacity layer)&&
         existsb(occurrence_matches(State.layer_occurrence layer))overlays then
        (flat_map(without_presentation_node(node_key trigger))base,
         map(prepend_trigger(State.layer_occurrence layer)trigger)
          (flat_map(without_presentation_node(node_key trigger))overlays))
       else(base,overlays)
      |_ =>(base,overlays)end
    |_ =>(base,overlays)end
   |None=>(base,overlays)end
  |_ =>(base,overlays)end
 |[] =>(base,overlays)end.

Definition view (snapshot : json) (state : State.state) (capacity : Model.capacity) : Surface.surface Input.input :=
 let base:=List.app(Navigation.navigation_base snapshot state capacity)(Pages.main snapshot state::pending_notices state)in
 let overlays:=List.app(Navigation.navigation_layers snapshot state capacity)
   (List.app(map(Layers.layer_view snapshot state capacity)(rev(Layers.visible_layers(State.layers(State.navigation_state state)))))
     (ServiceControls.dialogs state))in
 let '(base,overlays):=relocate_details_trigger state capacity base overlays in
 Surface.Surface "/workspace" "/main"base overlays(Services.theme(State.service_state state)).
