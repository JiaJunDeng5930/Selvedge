From Stdlib Require Import List String.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Input Services.
From Selvedge.Interaction.Session Require State.
From Selvedge.Interaction.Presentation Require Import Surface Model Navigation Pages Layers ServiceControls.
Import ListNotations.
Open Scope string_scope.

Definition view (snapshot : json) (state : State.state) (capacity : Model.capacity) : Surface.surface Input.input :=
 Surface.Surface "/workspace" "/main"
  (List.app (Navigation.navigation_base snapshot state capacity) [Pages.main snapshot state])
  (List.app (Navigation.navigation_layers snapshot state capacity)
   (List.app (map (Layers.layer_view snapshot state capacity) (rev (Layers.visible_layers(State.layers (State.navigation_state state)))))
     (ServiceControls.dialogs state)))
  (Services.theme(State.service_state state)).
