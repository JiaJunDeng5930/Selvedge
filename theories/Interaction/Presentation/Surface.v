From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require Import Identity Appearance Graphics CodeSource CodeBlock DocumentPublication Audit.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Interaction.Interactive Require Presentation.
From Selvedge.Interaction.Presentation Require Roles Information Composition Gesture.
From Selvedge.Interaction.Presentation Require Import Model.
Import ListNotations.
Open Scope string_scope.

Module UX := Selvedge.Interaction.Experience.Model.
Module Activities := Selvedge.Interaction.Experience.Activity.
Module Components := Selvedge.Interaction.Interactive.Presentation.

Inductive activity_row_role :=
| ChoiceRow | DependencyRow | InspectionRow | SupportingRow
| MemberRow | TerminalRow | ObjectHeading | NavigationRow.
Inductive board_grouping := ViewChoices | SearchArea | WorkStatus | SecondaryActions | PrimaryAction.
Inductive choice_kind := SingleChoice | MultipleChoice.


Record placement (Action : Type) := Placement {
  placement_target : string;
  placement_control : control Action
}.
Arguments Placement {Action}.
Arguments placement_target {Action}.
Arguments placement_control {Action}.

Inductive meaning (Action : Type) :=
| SettingEntry (owner : editor) (property : UX.property owner) (action : control Action)
| ActivityContent (expanded : bool) (audit : list Audit.face)
| ActivityRow (row : activity_row_role)
| ActivityGroup (owner : editor) (activity : Activities.activity owner) (view : Activities.view owner) (behavior : layer_behavior Action)
| DecisionGroup (owner : editor) (decision : UX.decision owner)
| WorkspaceCollection (owner : editor) (collection : UX.collection owner)
| WorkspaceMember (owner : editor) (collection : UX.collection owner) (path : string)
| ActionUnit (owner : editor) (action : UX.action_unit owner)
| ActionFeedback (owner : editor) (identity : UX.action_identity owner) (message : string)
| ActionExplanation (owner : editor) (assessment : UX.assessment owner)
| ActionCommit (owner : editor) (assessment : UX.assessment owner) (action : control Action)
| ObjectGroup (object : UX.object)
| SupportingControl (owner : editor) (support : UX.support owner) (property : UX.property owner) (action : control Action)
| InformationText (role : Information.text_role)
| LayerRegion (behavior : layer_behavior Action)
| NavigationRegion (panel : navigation_panel) (behavior : layer_behavior Action)
| DirectoryBrowserLocation (value : string)
| PanelToggle (expanded : bool) (action : control Action)
| CardContent (face : card_face)
| MovableCard (face : card_face) (destinations : list (placement Action))
| SummaryList
| Region
| ReadingTimeline (view : Identity.task_view) (generation : N)
| PageBody (page : Composition.page)
| PageContext (conversation : option Identity.task_view)
| ProjectGroup (project : N) (selected expanded : bool)
| TaskRow (task : N) (status caption : string) (working selected : bool)
| TaskChildren (task : N)
| ProjectChooser (selected : option N)
| WorkChoice (work : option N) (selected : bool) (action : control Action)
| DirectoryRow (path : string) (primary : bool)
| ContextSummary (owner : editor)
| SkillSuggestions (field_key : string) (expanded : bool) (active_option : option string)
| SkillSuggestion (selected : bool) (action : control Action)
| ChoiceGroup
| Choice (kind : choice_kind) (selected : bool) (description : string) (action : control Action)
| PageRegion (region : Composition.region) (position : Composition.position)
| BoardLane (stage : string) (count : N)
| CardArchive (count : N)
| BoardGroup (grouping : board_grouping)
| ReadOnly (text : string)
| Fact (value : string)
| EmbeddedMarkdown (value : string)
| PublishedText (document : DocumentPublication.document)
| RichText (source : CodeSource.source) (value : string)
| CodeFacts (view : CodeBlock.presentation)
| InteractiveRegion (policy : DocumentPublication.fence_policy)
| InteractiveNode (component : Components.component)
| InteractivePlacement (placement : Components.placement)
| Graphic (drawing : Graphics.plot Action)
| InteractiveTable (table : Components.table Action)
| Table (caption : string) (headings : list string) (rows : list (list string))
| Image (source alternative : string)
| Activate (action : control Action)
| Edit (owner : editor) (subject : UX.subject owner) (value : edit_control Action)
| InteractiveEdit (owner : CodeSource.identity) (member : string) (value : Components.editor Action)
| HistorySearchQuery (query : string) (receive : json -> option Action) (confirm : control Action)
| HistorySearchScope (project : bool) (selected : option N) (choices : list Fields.choice_value) (receive : json -> option Action)
| BoardSearch (selection : BoardFilter.filter) (receive : json -> option Action)
| SearchChoices (query : string) (receive : json -> option Action)
| ReceiveFile (owner : editor) (enabled : bool) (receive : json -> option Action)
| EnterDirectory (owner : editor) (text : string) (receive : json -> option Action) (confirm : option Action)
| BoardProfile (automatic : bool) (selected : string) (choices : list Fields.choice_value)
    (enabled : bool) (receive : json -> option Action).

Arguments SettingEntry {Action}.
Arguments ActivityContent {Action}.
Arguments ActivityRow {Action}.
Arguments ActivityGroup {Action}.
Arguments DecisionGroup {Action}.
Arguments WorkspaceCollection {Action}.
Arguments WorkspaceMember {Action}.
Arguments ActionUnit {Action}.
Arguments ActionFeedback {Action}.
Arguments ActionExplanation {Action}.
Arguments ActionCommit {Action}.
Arguments ObjectGroup {Action}.
Arguments SupportingControl {Action}.
Arguments InformationText {Action}.
Arguments LayerRegion {Action}.
Arguments NavigationRegion {Action}.
Arguments DirectoryBrowserLocation {Action}.
Arguments PanelToggle {Action}.
Arguments CardContent {Action}.
Arguments MovableCard {Action}.
Arguments SummaryList {Action}.
Arguments Region {Action}.
Arguments ReadingTimeline {Action}.
Arguments PageBody {Action}.
Arguments PageContext {Action}.
Arguments ProjectGroup {Action}.
Arguments TaskRow {Action}.
Arguments TaskChildren {Action}.
Arguments ProjectChooser {Action}.
Arguments WorkChoice {Action}.
Arguments DirectoryRow {Action}.
Arguments ContextSummary {Action}.
Arguments SkillSuggestions {Action}.
Arguments SkillSuggestion {Action}.
Arguments ChoiceGroup {Action}.
Arguments Choice {Action}.
Arguments PageRegion {Action}.
Arguments BoardLane {Action}.
Arguments CardArchive {Action}.
Arguments BoardGroup {Action}.
Arguments ReadOnly {Action}.
Arguments Fact {Action}.
Arguments EmbeddedMarkdown {Action}.
Arguments PublishedText {Action}.
Arguments RichText {Action}.
Arguments CodeFacts {Action}.
Arguments InteractiveRegion {Action}.
Arguments InteractiveNode {Action}.
Arguments InteractivePlacement {Action}.
Arguments Graphic {Action}.
Arguments InteractiveTable {Action}.
Arguments Table {Action}.
Arguments Image {Action}.
Arguments Activate {Action}.
Arguments Edit {Action}.
Arguments InteractiveEdit {Action}.
Arguments HistorySearchQuery {Action}.
Arguments HistorySearchScope {Action}.
Arguments BoardSearch {Action}.
Arguments SearchChoices {Action}.
Arguments ReceiveFile {Action}.
Arguments EnterDirectory {Action}.
Arguments BoardProfile {Action}.

Inductive node (Action : Type) :=
| Node (key semantic label : string) (role : Roles.role)
    (content : meaning Action) (children : list (node Action)).
Arguments Node {Action}.

Definition node_key {A} (value : node A) := match value with Node key _ _ _ _ _ => key end.
Definition semantic_key {A} (value : node A) := match value with Node _ key _ _ _ _ => key end.
Definition node_label {A} (value : node A) := match value with Node _ _ label _ _ _ => label end.
Definition node_role {A} (value : node A) := match value with Node _ _ _ role _ _ => role end.
Definition node_meaning {A} (value : node A) := match value with Node _ _ _ _ content _ => content end.
Definition node_children {A} (value : node A) := match value with Node _ _ _ _ _ children => children end.

Record surface (Action : Type) := Surface {
  workspace_key : string;
  main_key : string;
  base : list (node Action);
  overlays : list (node Action);
  surface_appearance : Appearance.appearance
}.
Arguments Surface {Action}.
Arguments workspace_key {Action}.
Arguments main_key {Action}.
Arguments base {Action}.
Arguments overlays {Action}.
Arguments surface_appearance {Action}.

Definition layer_region {A} (content : meaning A) :=
  match content with
  | ActivityGroup _ _ _ behavior | LayerRegion behavior | NavigationRegion _ behavior => Some behavior
  | _ => None
  end.

Definition press_control {A} (value : control A) :=
  if available (control_availability value) then Some (control_input value) else None.

Definition edit_value {A} (value : edit_control A) input :=
  if available (editing_availability value) then
    match editing_entry value, editing_input value with
    | Fields.DisplayOnly, _ | _, None => None
    | _, Some receive => receive input
    end
  else None.

Definition dismiss_layer {A} (behavior : layer_behavior A) value :=
  match as_string value with
  | Some "escape" => if layer_escape behavior then Some (layer_dismissal behavior) else None
  | Some "outside" => if layer_outside behavior then Some (layer_dismissal behavior) else None
  | _ => None
  end.

Definition resolve_meaning {A} (content : meaning A) gesture value : option A :=
  match gesture, content with
  | Gesture.Press, SettingEntry _ _ action
  | Gesture.Press, ActionCommit _ _ action
  | Gesture.Press, SupportingControl _ _ _ action
  | Gesture.Press, WorkChoice _ _ action
  | Gesture.Press, PanelToggle _ action
  | Gesture.Press, SkillSuggestion _ action
  | Gesture.Press, Choice _ _ _ action
  | Gesture.Press, Activate action => press_control action
  | Gesture.Change, Edit _ _ control => edit_value control value
  | Gesture.Key, Edit _ _ control =>
      match editing_key_input control with Some receive => receive value | None => None end
  | Gesture.Selection, Edit _ _ control =>
      match editing_selection_input control with Some receive => receive value | None => None end
  | Gesture.Change, InteractiveEdit _ _ control =>
      if Components.editing_enabled control then
        match Components.editing_receive control with
        | Some receive => receive value | None => None
        end
      else None
  | Gesture.Press, HistorySearchQuery _ _ confirm => press_control confirm
  | Gesture.Search, SearchChoices _ receive
  | Gesture.Change, HistorySearchQuery _ receive _
  | Gesture.Change, HistorySearchScope _ _ _ receive
  | Gesture.Search, BoardSearch _ receive => receive value
  | Gesture.Attach, ReceiveFile _ true receive => receive value
  | Gesture.Directory, EnterDirectory _ _ receive _ => receive value
  | Gesture.ConfirmDirectory, EnterDirectory _ _ _ confirm => confirm
  | Gesture.SelectBoardProfile, BoardProfile _ _ _ true receive => receive value
  | Gesture.Dismiss, ActivityGroup _ _ _ behavior
  | Gesture.Dismiss, LayerRegion behavior
  | Gesture.Dismiss, NavigationRegion _ behavior => dismiss_layer behavior value
  | Gesture.Place, MovableCard _ destinations =>
      match as_string value with
      | None => None
      | Some target =>
          match find (fun placement => String.eqb target (placement_target placement)) destinations with
          | None => None | Some placement => press_control (placement_control placement)
          end
      end
  | _, _ => None
  end.

Definition resolve_graphic {A} key gesture (drawing : Graphics.plot A) : option A :=
  match gesture with
  | Gesture.Press =>
      match find (fun primitive => match primitive with
        | Graphics.Hitbox identity _ _ _ _ _ _ => String.eqb key identity
        | _ => false end) (Graphics.primitives drawing) with
      | Some (Graphics.Hitbox _ _ _ _ _ _ action) => Some action
      | _ => None
      end
  | _ => None
  end.

Definition resolve_table {A} identity key gesture (table : Components.table A) : option A :=
  match gesture with
  | Gesture.Press => match find (fun column => String.eqb key (Components.column_key identity column))
      (Components.table_columns table) with
    | Some column => if Components.column_enabled column then Components.column_sort column else None
    | None => None end
  | _ => None end.

Fixpoint resolve_node {A} key gesture value (tree : node A) : option A :=
  let 'Node identity _ _ _ content children := tree in
  if String.eqb key identity then resolve_meaning content gesture value else
  match match content with
  | Graphic drawing => resolve_graphic key gesture drawing
  | InteractiveTable table => resolve_table identity key gesture table
  | _ => None end with
  | Some action => Some action
  | None =>
      let fix seek (items : list (node A)) := match items with
      | [] => None
      | child :: rest => match resolve_node key gesture value child with
        | Some action => Some action | None => seek rest end
      end in seek children
  end.

Fixpoint resolve_nodes {A} key gesture value (items : list (node A)) :=
  match items with
  | [] => None
  | child :: rest => match resolve_node key gesture value child with
    | Some action => Some action | None => resolve_nodes key gesture value rest end
  end.

Definition is_modal_node {A} (node : node A) :=
  match layer_region (node_meaning node) with
  |Some behavior => modal_layer behavior|None => false end.
Definition modal_nodes {A} (value : surface A) := filter is_modal_node (overlays value).
Definition active_modal {A} (value : surface A) := hd_error (rev (modal_nodes value)).

Definition resolve_element {A} (value : surface A) key gesture input :=
  match active_modal value with
  | Some modal => resolve_node key gesture input modal
  | None => resolve_nodes key gesture input (List.app (base value) (overlays value))
  end.

Definition map_receiver {A B} (f : A -> B) (receive : json -> option A) value :=
  option_map f (receive value).

Definition map_placement {A B} (f : A -> B) (value : placement A) :=
  Placement (placement_target value) (map_control f (placement_control value)).

Definition map_meaning {A B} (f : A -> B) (value : meaning A) : meaning B :=
  match value with
  | SettingEntry owner property action => SettingEntry owner property (map_control f action)
  | ActivityContent expanded audit => ActivityContent expanded audit
  | ActivityRow row => ActivityRow row
  | ActivityGroup owner activity view behavior => ActivityGroup owner activity view (map_layer_behavior f behavior)
  | DecisionGroup owner decision => DecisionGroup owner decision
  | WorkspaceCollection owner collection => WorkspaceCollection owner collection
  | WorkspaceMember owner collection path => WorkspaceMember owner collection path
  | ActionUnit owner action => ActionUnit owner action
  | ActionFeedback owner identity message => ActionFeedback owner identity message
  | ActionExplanation owner assessment => ActionExplanation owner assessment
  | ActionCommit owner assessment action => ActionCommit owner assessment (map_control f action)
  | ObjectGroup object => ObjectGroup object
  | SupportingControl owner support property action => SupportingControl owner support property (map_control f action)
  | InformationText role => InformationText role
  | LayerRegion behavior => LayerRegion (map_layer_behavior f behavior)
  | NavigationRegion panel behavior => NavigationRegion panel(map_layer_behavior f behavior)
  | DirectoryBrowserLocation value => DirectoryBrowserLocation value
  | PanelToggle expanded action => PanelToggle expanded (map_control f action)
  | CardContent face => CardContent face
  | MovableCard face destinations => MovableCard face (map (map_placement f) destinations)
  | SummaryList => SummaryList
  | Region => Region
  | ReadingTimeline view generation => ReadingTimeline view generation
  | PageBody page => PageBody page
  | PageContext conversation => PageContext conversation
  | ProjectGroup project selected expanded => ProjectGroup project selected expanded
  | TaskRow task status caption working selected => TaskRow task status caption working selected
  | TaskChildren task => TaskChildren task
  | ProjectChooser selected => ProjectChooser selected
  | WorkChoice work selected action => WorkChoice work selected (map_control f action)
  | DirectoryRow path primary => DirectoryRow path primary
  | ContextSummary owner => ContextSummary owner
  | SkillSuggestions field expanded active => SkillSuggestions field expanded active
  | SkillSuggestion selected action => SkillSuggestion selected (map_control f action)
  | ChoiceGroup => ChoiceGroup
  | Choice kind selected description action => Choice kind selected description (map_control f action)
  | PageRegion region position => PageRegion region position
  | BoardLane stage count => BoardLane stage count
  | CardArchive count => CardArchive count
  | BoardGroup grouping => BoardGroup grouping
  | ReadOnly text => ReadOnly text
  | Fact value => Fact value
  | EmbeddedMarkdown value => EmbeddedMarkdown value
  | PublishedText document => PublishedText document
  | RichText source value => RichText source value
  | CodeFacts view => CodeFacts view
  | InteractiveRegion policy => InteractiveRegion policy
  | InteractiveNode component => InteractiveNode component
  | InteractivePlacement placement => InteractivePlacement placement
  | Graphic drawing => Graphic (Graphics.map_actions f drawing)
  | InteractiveTable table => InteractiveTable (Components.map_table f table)
  | Table caption headings rows => Table caption headings rows
  | Image source alternative => Image source alternative
  | Activate action => Activate (map_control f action)
  | Edit owner subject value => Edit owner subject (map_edit_control f value)
  | InteractiveEdit owner member value => InteractiveEdit owner member (Components.map_editor f value)
  | HistorySearchQuery query receive confirm => HistorySearchQuery query (map_receiver f receive)(map_control f confirm)
  | HistorySearchScope project selected choices receive => HistorySearchScope project selected choices (map_receiver f receive)
  | BoardSearch selection receive => BoardSearch selection (map_receiver f receive)
  | SearchChoices query receive => SearchChoices query (map_receiver f receive)
  | ReceiveFile owner enabled receive => ReceiveFile owner enabled (map_receiver f receive)
  | EnterDirectory owner text receive confirm =>
      EnterDirectory owner text (map_receiver f receive) (option_map f confirm)
  | BoardProfile automatic selected choices enabled receive =>
      BoardProfile automatic selected choices enabled (map_receiver f receive)
  end.

Fixpoint map_node {A B} (f : A -> B) (value : node A) : node B :=
  let 'Node key semantic label role content children := value in
  Node key semantic label role (map_meaning f content) (map (map_node f) children).

Definition map_actions {A B} (f : A -> B) (value : surface A) : surface B :=
  Surface (workspace_key value) (main_key value)
    (map (map_node f) (base value)) (map (map_node f) (overlays value)) (surface_appearance value).

(** Enumerate only the finite observations already declared by a native control.
    Text receivers remain open; current parameter Apply actions are explicit nodes. *)
Definition receiver_actions {A}(receive:json->option A)(values:list json):list A:=
 fold_right(fun value rest=>match receive value with
 |Some action=>action::rest|None=>rest end)[] values.

Definition edit_actions {A e}(subject:UX.subject e)(value:edit_control A):list A:=
 match editing_entry value,editing_input value with
 |Fields.DisplayOnly,_|_,None=>[]
 |_,Some receive=>
   let field:=UX.subject_declaration subject in
   let inputs:=match editing_entry value with
   |Fields.Choice=>map(Parameters.choice_input e field)(editing_choices value)
   |_=>match Parameters.native_checked field(editing_observation value)with
     |Some _=>[JBool false;JBool true]|None=>[]end
   end in receiver_actions receive inputs
 end.

Definition meaning_actions {A}(content:meaning A):list A:=match content with
|SettingEntry _ _ action|ActionCommit _ _ action|SupportingControl _ _ _ action
|PanelToggle _ action|WorkChoice _ _ action|SkillSuggestion _ action|Choice _ _ _ action|Activate action=>[control_input action]
|ActivityGroup _ _ _ behavior|LayerRegion behavior|NavigationRegion _ behavior=>[layer_dismissal behavior]
|MovableCard _ destinations=>map(fun placement=>control_input(placement_control placement))destinations
|Graphic drawing=>fold_right(fun primitive rest=>match primitive with
  |Graphics.Hitbox _ _ _ _ _ _ action=>action::rest|_=>rest end)[](Graphics.primitives drawing)
|InteractiveTable table=>fold_right(fun column rest=>match Components.column_sort column with
  |Some action=>action::rest|None=>rest end)[](Components.table_columns table)
|EnterDirectory _ _ _ (Some confirm)=>[confirm]
|Edit _ subject value=>edit_actions subject value
|BoardProfile _ _ choices _ receive=>
 receiver_actions receive(map(fun choice=>JString(Fields.choice_value_of choice))choices)
|_=>[]end.
Fixpoint node_actions {A}(value:node A):list A:=
 let 'Node _ _ _ _ content children:=value in
 List.app(meaning_actions content)(flat_map node_actions children).
Definition actions {A}(value:surface A):list A:=
 flat_map node_actions(List.app(base value)(overlays value)).
Definition current_actions {A}(value:surface A):list A:=
 match active_modal value with Some modal=>node_actions modal|None=>actions value end.
