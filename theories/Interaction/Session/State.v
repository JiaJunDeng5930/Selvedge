From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands Streams.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction.Interactive Require Types State.
From Selvedge.Interaction Require Import Codec Identity Services Speech SkillMention Resource DocumentState.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Interaction.Experience Require Import Model Activity.
From Selvedge.Interaction.Session Require Import Draft.
Import ListNotations.
Open Scope string_scope.
Definition public_command := command_value command_specs.

Inductive information_panel := TaskDetails (task : N) | CardDetails (card : N)
| TaskContext (task : N) | PropertySource (owner : editor) (request : activity_request).
Inductive board_panel := BoardSettings | BoardFilters | ArchivedCards.
Inductive panel := PropertyPanel (owner : editor) (request : activity_request)
| EditorPanel (owner : editor)
| BoardSettingsPanel | BoardFiltersPanel | ArchivedCardsPanel
| SideConversationPanel(task:N)
| NavigationPanel (kind : navigation_panel)
| ObjectActionsPanel (subject : menu_subject)
| InformationPanel (kind : information_panel)
| Confirmation (command : public_command) (caption : string) (destination : route).
Record layer := Layer {
  layer_panel : panel;
  layer_trigger : string;
  layer_initial_attention : string;
  layer_query : string;
  layer_occurrence : N;
  layer_source_expanded : bool;
  layer_decision_field : option Fields.field;
  layer_parameter_buffer : option string;
  layer_feedback : option json;
  layer_pending : bool
}.
Inductive navigation_visibility := AutomaticNavigation | OpenNavigation | ClosedNavigation.
Record navigation := Navigation {
  location : route;
  active_work : option N;
  visits : list (option N * route);
  navigation_intent : navigation_visibility;
  desktop_task_list_visible : bool;
  generation : N;
  layers : list layer
}.
Definition side_task n:=fold_right(fun layer rest=>match layer_panel layer with
|SideConversationPanel task=>Some task|_=>rest end)None(layers n).
Inductive pending_purpose := DraftSubmission (snapshot : draft) (navigation_generation layer_generation : N) (trigger : string)
| ConfirmationSubmission (navigation_generation occurrence : N)
| LiveConfiguration (snapshot : draft) (view_occurrence : option N) (remember_model:bool)
| ProjectPreference (snapshot : draft) (prepared : public_command) (navigation_generation layer_generation : N) (trigger : string)
| DirectSubmission
| WorkCreation (navigation_generation layer_generation:N)
| SideCreation (parent navigation_generation layer_generation:N)(trigger:string)
| SearchSubmission(query:string)(project work:option N)(search_ticket:N)
| LanguageAdmission (task revision : N) (text : string) (owner : Selvedge.Interaction.Interactive.Types.owner) (path : string) (ticket : N)
| LanguageSubmission (editor : Identity.editor) (owner : Selvedge.Interaction.Interactive.Types.owner) (path : string) (ticket : N).
Record pending := Pending { ticket : N; accepted_command : public_command; purpose : pending_purpose;
  outcome_unknown : option string }.
Definition unknown_outcome requested reason current :=
 if N.eqb requested (ticket current) then
  Pending (ticket current) (accepted_command current) (purpose current) (Some reason)
 else current.
Record search := Search {
  keyword : string;
  project_filter : option N;
  work_filter : option N;
  search_result : option json;
  search_latest : option N
}.
Record skill_request := SkillRequest { skill_editor : editor; skill_workspace : Selvedge.Kernel.Domain.workspace }.
Record authoring := Authoring {
  drafts : list draft;
  next : N;
  awaiting : list pending;
  history_search : search;
  skill_catalogs : list (resource skill_request (list SkillMention.skill));
  mentions : list (editor * SkillMention.mention_state);
  draft_model_manual : bool
}.
Inductive reading_intent := FollowingLatest | ReadingHistory.
Record reader := Reader { reading_task : N; reader_generation : N;
 reader_position : reading_intent; disclosures : list (N * N * bool) }.
Record state := State {
  navigation_state : navigation;
  authoring_state : authoring;
  service_state : Services.services;
  speech_state : Speech.speech;
  stream_state : Streams.state;
  readers : list reader;
  interactive_state : Selvedge.Interaction.Interactive.State.state;
  board_selection : BoardFilter.filter;
  document_retention : DocumentState.retention;
  collapsed_projects : list N;
  now : option N;
  next_layer : N
}.
Definition pending_editor owner state:=existsb(fun pending=>match purpose pending with
|DraftSubmission value _ _ _|LiveConfiguration value _ _|ProjectPreference value _ _ _ _=>same_editor owner(Draft.owner value)
|LanguageAdmission task _ _ _ _ _=>same_editor owner(Identity.Message task)
|LanguageSubmission editor _ _ _=>same_editor owner editor
|_=>false end)(awaiting(authoring_state state)).
Definition pending_command command state:=existsb(fun pending=>CommandAssessment.same_command command(accepted_command pending))(awaiting(authoring_state state)).
Definition pending_placement card state:=existsb(fun pending=>
 let raw:=Schema.encode_command(accepted_command pending)in
 String.eqb (Codec.text "op" raw) "move_card" &&
 match Codec.natural_field "card_id" raw with Some current=>N.eqb card current|None=>false end)
 (awaiting(authoring_state state)).
Definition initial := State
  (Navigation Start None [] AutomaticNavigation true 0 [])
  (Authoring [] 0 [] (Search "" None None None None) [] [] false)
  Services.initial Speech.initial [] [] Selvedge.Interaction.Interactive.State.initial
  BoardFilter.empty DocumentState.initial_retention [] None 0.
Definition with_navigation value := set navigation_state (fun _=>value).
Definition with_authoring value := set authoring_state (fun _=>value).
Definition with_services value := set service_state (fun _=>value).
Definition with_speech value := set speech_state (fun _=>value).
Definition with_streams value := set stream_state (fun _=>value).
Definition with_readers value := set readers (fun _=>value).
Definition with_retention value := set document_retention (fun _=>value).
Definition with_interactive_state value := set interactive_state (fun _=>value).
Definition with_board value := set board_selection (fun _=>value).
Definition with_collapsed value := set collapsed_projects (fun _=>value).
Definition with_now value := set now (fun _=>value).
Definition with_next_layer value := set next_layer (fun _=>value).
Definition save_draft value state := with_authoring
 (set drafts (Draft.store_draft value) (authoring_state state))state.
Definition current_draft s e := match find_draft e (drafts (authoring_state s)) with
| Some draft => draft | None => new_draft e end.
