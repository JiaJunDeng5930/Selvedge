From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import TextJson.
From Selvedge.Kernel Require Domain.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require Import Codec Identity Input Context.
From Selvedge.Interaction Require Services.
From Selvedge.Interaction.Experience Require Model Activity Observation.
From Selvedge.Interaction.Session Require State Draft.
From Selvedge.Interaction.Submission Require Parameters Values.
From Selvedge.Interaction.Presentation Require Import Surface Model Construction Composer Editors Projection.
From Selvedge.Interaction.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.
Module UX := Selvedge.Interaction.Experience.Model.
Module Act := Selvedge.Interaction.Experience.Activity.
Definition candidate_node {e} (pending:bool) occurrence parent (decision:UX.decision e)
 (alternative:UX.alternative e(UX.decision_subject decision)) :=
 let label:=UX.alternative_label alternative in
 let key:=part parent("candidate/"++TextJson.render_json(Schema.encode_value(UX.subject_kind(UX.decision_subject decision))(UX.alternative_value alternative)))in
 let action:=Control label label Secondary
  (Input.ActivityAssignment occurrence e(Act.Assignment(UX.decision_subject decision)(UX.alternative_value alternative)))
  (if pending && Parameters.live_configuration e(UX.subject_declaration(UX.decision_subject decision))
   then Busy "This action is pending"else domain_availability(UX.alternative_availability alternative))in
 Node(part key "row")"choice-row" ""Roles.Section(ActivityRow ChoiceRow)
 [Node key "alternative"label Roles.Button
  (Choice SingleChoice(UX.alternative_selected alternative)(UX.alternative_explanation alternative)action)
  ([information key "label" Information.OptionLabel label]++
   (if String.eqb label(UX.alternative_explanation alternative)then[]else
    [information key "description" Information.Description(UX.alternative_explanation alternative)])++
   map(fun consequence=>information key("consequence/"++UX.subject_name(UX.summary_subject consequence))Information.Description
    (UX.readable_text(UX.summary_observation consequence)))(UX.alternative_consequences alternative))].
Definition alternative_search_key {e}(subject:UX.subject e)(value:denote(UX.subject_kind subject)) :=
 let encoded:=Schema.encode_value(UX.subject_kind subject)value in
 match UX.subject_declaration subject,encoded with
 |Fields.ModelProfile,JString key=>"model/"++key
 |Fields.ReasoningEffort,JString effort=>"effort/"++effort
 |Fields.SandboxMode,JString mode=>"filesystem/"++mode
 |Fields.NetworkAccess,JBool enabled=>if enabled then "network/enabled"else"network/disabled"
 |Fields.ApprovalReviewer,JString key=>"approval/automatic/"++key
 |Fields.ApprovalPolicy,JString "ask-for-approval"=>"strategy/ask"
 |Fields.ApprovalPolicy,JString "full-access"=>"strategy/full-access"
 |Fields.ApprovalPolicy,JString "approval-for-me"=>"strategy/automatic-review"
 |Fields.WorkspacePrimary,JString path=>"directory/"++path
 |_,_=>TextJson.render_json encoded end.
Definition decision_node {e} pending occurrence parent query (decision:UX.decision e) :=
 let identity:=part parent(UX.subject_name(UX.decision_subject decision))in
 let full:=UX.decision_alternatives decision in
 let visible:=filter(fun alternative=>
   BoardFilter.contains(BoardFilter.lower_text(BoardFilter.trim query))
    (BoardFilter.lower_text(UX.alternative_label alternative++" "++
      alternative_search_key(UX.decision_subject decision)(UX.alternative_value alternative))))full in
 let status:=match full,visible with
 |[],_=>[read_only identity "candidates/empty" "Choices" "No choices have been configured"]
 |_,[]=>[read_only identity "candidates/no-match" "Search" "No choices match this search"]
 |_,_=>if existsb(fun alternative=>match UX.alternative_availability alternative with
    UX.Available=>true|_=>false end)visible then[]else
    [read_only identity "candidates/unavailable" "Choices" "No available choices"]end in
 Node identity "decision"(UX.decision_question decision)Roles.Section(DecisionGroup e decision)
 ([Node(part identity "heading-row")"object-heading" ""Roles.Section(ActivityRow ObjectHeading)
   [group_title identity(UX.decision_question decision)]]++status++map(candidate_node pending occurrence identity decision)visible).
Definition workspace_nodes {e} s occurrence parent (members:UX.collection e) :=
 let workspace:=UX.collection_workspace members in
 let roots:=Domain.workspace_roots workspace in
 let editable:=Parameters.editable e Fields.WorkspaceDirectories in
 let buffer:=match find(fun layer=>N.eqb occurrence(State.layer_occurrence layer))(State.layers(State.navigation_state s))with
 |Some layer=>value_or ""(State.layer_parameter_buffer layer)|None=>""end in
 Node parent "workspace-collection" "Working directories"Roles.Section(WorkspaceCollection e members)
 (map(fun path=>let key:=part parent path in
  Node key "workspace-member"path Roles.Section(WorkspaceMember e members path)
   (read_only key "path" "Directory"path::
    information key "primary-state" Information.Status(if match Domain.workspace_primary workspace with Some primary=>String.eqb path primary|None=>false end then "Primary directory"else"")::
    if editable then
     [declared key Roles.Button(secondary "primary" "Use as primary"(Input.ActivityWorkspaceChange occurrence(Input.ChoosePrimaryDirectory path)));
      declared key Roles.Button(secondary "remove" "Remove directory"(Input.ActivityWorkspaceChange occurrence(Input.RemoveDirectory path)))]else[]))roots ++
  if editable then
   (if String.eqb buffer ""then[]else[information parent "unadded-directory" Information.Status "Add or clear the directory before saving"])++
   [Node(part parent "directory")"directory" "Add directory"Roles.Field
    (EnterDirectory e buffer(fun value=>option_map(Input.ActivityParameter occurrence)(as_string value))
      (if String.eqb buffer ""then None else Some(Input.ActivityWorkspaceChange occurrence(Input.AddDirectory buffer))))[];
    region parent "directory-entry-actions" ""Roles.Toolbar
     [declared parent Roles.Button(Control "add" "Add directory"Secondary
       (Input.ActivityWorkspaceChange occurrence(Input.AddDirectory buffer))
       (if String.eqb buffer ""then Unavailable "Enter a directory"else Available));
      declared parent Roles.Button(secondary "clear" "Clear"(Input.ActivityParameter occurrence ""));
      declared parent Roles.Button(Control "browse" "Browse…" Secondary
       (Input.ServiceInput(Services.OpenDirectory e
         (if String.eqb buffer ""then value_or ""(Domain.workspace_primary workspace)else buffer)(part parent "browse")))
       (if State.pending_editor e s then Unavailable "Wait for the current action to finish"else Available))]] ++
   if Parameters.inheritable e && negb(UX.collection_inherited members)then
    [declared parent Roles.Button(secondary "inherit" "Use inherited workspace"(Input.ActivityWorkspaceChange occurrence Input.InheritWorkspace))]else[]
  else[])%list.
Definition field_specification snapshot s {e} occurrence parent(subject:UX.subject e) :=
 let original:=Parameters.native_value(UX.subject_declaration subject)(Observation.observe_subject snapshot s subject)in
 let buffer:=match find(fun layer=>N.eqb occurrence(State.layer_occurrence layer))(State.layers(State.navigation_state s))with
 |Some layer=>value_or(value_or ""(as_string original))(State.layer_parameter_buffer layer)
 |None=>value_or ""(as_string original)end in
 let key:=part parent("specification/"++UX.subject_name subject)in
 let entry:=Observation.entry snapshot s subject in
 let field:=Node(part key "parameter")"parameter"(Parameters.label(UX.subject_declaration subject))Roles.Field
  (Edit e subject(EditControl entry(Observation.observe_subject snapshot s subject)(Some buffer)
   (Observation.choices snapshot s subject)None Available
   (match entry with Fields.DisplayOnly=>None|_=>Some(fun value=>option_map(Input.ActivityParameter occurrence)(as_string value))end)None None))[]in
 field::match entry with
 |Fields.DisplayOnly=>[]
 |_=>match Observation.alternative_from_choice snapshot s subject(Fields.ChoiceValue buffer "Apply")with
  |None=>[read_only key "invalid" "" "This value does not satisfy the parameter contract"]
  |Some candidate=>[declared key Roles.Button(Control "apply" "Apply"Secondary
    (Input.ActivityAssignment occurrence e(Act.Assignment subject(UX.alternative_value candidate)))
    (domain_availability(UX.alternative_availability candidate)))]end end.
Definition information_value {e}(value:UX.information e):string:=match value with
|UX.PresentInformation first _=>UX.readable_text(UX.summary_observation first)
|UX.OptionalAbsence=>"Not set"
|UX.NotApplicable reason|UX.RequiredAbsence reason|UX.InvalidInformation reason|UX.UnavailableInformation reason=>reason end.
Definition dependency_summary snapshot s {e} occurrence parent(subject:UX.subject e) :=
 let name:=UX.subject_name subject in
 let key:=part parent("decision/"++name)in
 let value:=information_value(Observation.information_of snapshot subject(Observation.observe_subject snapshot s subject))in
 Node key "dependency" ""Roles.Section(ActivityRow DependencyRow)
 [Node(part key "entry")"entry"(Parameters.label(UX.subject_declaration subject))Roles.Button
   (Activate(secondary "entry"(Parameters.label(UX.subject_declaration subject))
    (Input.ActivityFocus occurrence e(Some subject))))
   [information key "label" Information.FieldLabel(Parameters.label(UX.subject_declaration subject));
    information key "value" Information.FieldValue value]].
Definition required_expression {e} parent(expression:Observation.subject_expression e):list(node Input.input):=
 match Observation.expression_kind_of expression with
 |Observation.SelectedSubject _|Observation.OwnedParameter _|Observation.PermissionConsequence _=>[]
 |Observation.OriginalIdentity=>match Observation.expression_information expression with
   |UX.PresentInformation first _=>
    [Node(part parent "original-project")"original-project" ""Roles.Section(ActivityRow SupportingRow)
      [read_only parent "original-project/value" "Original project"(UX.readable_text(UX.summary_observation first))]]
   |_=>[]end
 |_=>let subject:=Observation.expression_subject expression in
  let key:=part parent("fact/"++UX.subject_name subject)in
  [Node key "required-information" ""(match Observation.expression_information expression with UX.RequiredAbsence _=>Roles.Alert|_=>Roles.Section end)(ActivityRow SupportingRow)
    [read_only key "observation"(Parameters.label(UX.subject_declaration subject))
      (information_value(Observation.expression_information expression))]]end.
Definition inherited_permission_controls s e parent :=
 match Selvedge.Interaction.Session.Observation.draft_context(State.current_draft s e)with
 |None=>[]|Some configuration=>
  flat_map(fun (setting:Fields.field*string*bool)=>let '(field,label,overridden):=setting in if overridden then
   match UX.admit_subject e(Parameters.name field)with
   |Some subject=>match Input.assign_subject subject JNull with
     |Some input=>[declared parent Roles.Button(secondary("default/"++Parameters.name field)("Use defaults for "++label)input)]
     |None=>[]end
   |None=>[]end else[])
   [(Fields.SandboxMode,"filesystem and network access",match Context.sandbox_override configuration with Some _=>true|None=>false end);
    (Fields.ApprovalPolicy,"approval policy",match Context.approval_override configuration with Some _=>true|None=>false end)]end.
Fixpoint relation_nodes {e} snapshot s occurrence parent query request
 (activity:Act.activity e)(view:Act.view e)(relation:Act.relation e):list(node Input.input):=
 let children:=match relation with Act.RootDecision _ children=>
  flat_map(relation_nodes snapshot s occurrence parent query request activity view)children|_=>[]end in
 match Observation.relation_exposure activity view relation,relation with
 |Observation.CandidateChoices,Act.RootDecision root _=>decision_node(UX.action_pending(Observation.action_unit_for s e))occurrence parent query root::children
 |Observation.CandidateChoices,Act.DependentDecision _ _ child=>[decision_node(UX.action_pending(Observation.action_unit_for s e))occurrence parent "" child]
 |Observation.DependencySummary,Act.RootDecision root _=>dependency_summary snapshot s occurrence parent(UX.decision_subject root)::children
 |Observation.DependencySummary,Act.DependentDecision _ _ child=>[dependency_summary snapshot s occurrence parent(UX.decision_subject child)]
 |Observation.DependencySummary,Act.FieldSpecification _ subject _=>
   [match Observation.entry snapshot s subject with
    |Fields.DisplayOnly=>read_only parent("fact/"++UX.subject_name subject)(Parameters.label(UX.subject_declaration subject))
      (information_value(Observation.information_of snapshot subject(Observation.observe_subject snapshot s subject)))
    |_=>dependency_summary snapshot s occurrence parent subject end]
 |Observation.ParameterControl,Act.FieldSpecification _ subject _=>
   [Node(part parent("inspection/"++UX.subject_name subject))"field-specification" ""Roles.Section(ActivityRow InspectionRow)
    (field_specification snapshot s occurrence parent subject)]
 |Observation.RequiredExpression,Act.RequiredValue property=>
   let key:=part parent("required/"++UX.subject_name(UX.property_subject property))in
   [Node key "required-value" ""Roles.Section(ActivityRow ObjectHeading)
    (flat_map(required_expression key)(Observation.information_expressions snapshot s activity view property))]
 |Observation.RequestedInformation,Act.SupportingValue property=>
   let key:=part parent("supporting/"++UX.subject_name(UX.property_subject property))in
   match view with
   |Act.InspectionView None=>[Node key "supporting-value" ""Roles.Section(ActivityRow SupportingRow)
     ([read_only key "scope" "Scope"(match e with Identity.Project _=>"Applies to future tasks; existing working directories and explicit overrides are unchanged"|_=>editor_key e end);
      declared key Roles.Button(secondary "source/open" "Configuration source…"(Input.InspectSource e request(part key "source/open")))]++
      match UX.property_kind_of property with
      |UX.PermissionsProperty=>inherited_permission_controls s e key|_=>[]end)]
   |Act.CompoundView=>[Node key "supporting-value" ""Roles.Section(ActivityRow InspectionRow)
     (Composer.property_information key property++[declared key Roles.Button
       (secondary "source/open" "Configuration source…"(Input.InspectSource e request(part key "source/open")))]) ]
   |_=>[]end
 |Observation.CompoundContent,Act.CollectionMembers members=>[workspace_nodes s occurrence(part parent "workspace")members]
 |Observation.CompoundContent,Act.AssessedAction action outcome=>
   let assessment:=UX.Assessment(UX.action_identity_of action)outcome in
   [Node(part parent "commit")"commit" "Actions"Roles.Section(ActionUnit e action)
     ([Editors.assessment_nodes parent assessment]++
      Composer.action_feedback parent action(Editors.draft_feedback(State.current_draft s e))++
      [Node(part parent "terminal")"terminal" ""Roles.Section(ActivityRow TerminalRow)
        [Node(part parent "submit")"submit"(Editors.submit_label(State.current_draft s e)e)Roles.PrimaryButton
          (ActionCommit e assessment(Control "submit"(Editors.submit_label(State.current_draft s e)e)Primary(Input.Submit e(part parent "submit"))
           (Editors.unit_availability action assessment)))[]]])]
 |_,_=>children end.
Definition activity_fields snapshot s {e} (occurrence:N) parent (activity:Act.activity e) :=
 match activity with
 |Act.EditingActivity _ _ _=>
  fold_right(fun '(name,fields) rest=>
   let fields:=filter(fun field=>match field with Fields.WorkspaceDirectories|Fields.WorkspacePrimary=>false|_=>true end)fields in
   match fields with []=>rest|_=>Editors.field_section snapshot s e parent name fields::rest end)[]
   (Editors.editor_sections e)
 |_=>[]end.
Definition current_layer s occurrence:=find(fun layer=>N.eqb occurrence(State.layer_occurrence layer))(State.layers(State.navigation_state s)).
Definition inspection_label kind:=match kind with
|UX.ModelProperty=>"Model settings…"|UX.PermissionsProperty=>"Custom permissions…"|_=>"Configuration source…"end.
Definition view_title {e}(activity:Act.activity e)(view:Act.view e):string:=match view with
|Act.DependentView subject|Act.InspectionView(Some subject)=>Parameters.label(UX.subject_declaration subject)
|Act.InspectionView None=>match UX.property_kind_of(Act.activity_property activity)with UX.ModelProperty=>"Model settings"|UX.PermissionsProperty=>"Permissions"|_=>UX.property_label(Act.activity_property activity)end
|_=>match activity with Act.EditingActivity _ _ _=>Editors.editor_title e|_=>UX.property_label(Act.activity_property activity)end end.
Definition workspace_menu snapshot s e occurrence parent behavior:=
 Node parent "workspace-settings" "Workspace"Roles.Menu(LayerRegion behavior)
  (title parent "Workspace"::
   (match Observation.observe_collection snapshot s e with
    |Some members=>[workspace_nodes s occurrence(part parent "workspace")members]
    |None=>[read_only parent "unavailable" "Workspace" "The working directory observation is unavailable"]end)++
   [declared parent Roles.Button(secondary "done" "Done" Input.ClosePanel)])%list.
Definition workspace_request request:=match request with
|Act.WorkspaceActivity|Act.PropertyActivity UX.WorkspaceProperty=>true|_=>false end.
Definition project_choice_details snapshot s {e}(subject:UX.subject e)(choice:Fields.choice_value):string*string:=
 match Values.context_origin_choice(Draft.contents(State.current_draft s e))(Fields.choice_value_of choice)with
 |Some(Context.ProjectDefaults id)|Some(Context.ProjectForParent _ id)=>
  match Projection.projects snapshot with
  |Some projects=>match find(fun project=>N.eqb id(Projection.project_id project))projects with
   |Some project=>(value_or "No primary directory"(Domain.workspace_primary(Projection.project_workspace project)),
     String.concat " "(Domain.workspace_roots(Projection.project_workspace project)))
   |None=>("Project information is unavailable","")end
  |None=>("Project observations unavailable","")end
 |Some(Context.ParentTask _)=>("Use parent task defaults","")
 |Some Context.EnvironmentDefaults=>("Use environment defaults","")
 |None=>("","")end.
Definition project_choice snapshot s {e} occurrence parent(subject:UX.subject e)(choice:Fields.choice_value)description:=
 let label:=Fields.choice_label choice in
 let key:=part parent("project/"++Fields.choice_value_of choice)in
 match Observation.alternative_from_choice snapshot s subject choice with
 |None=>read_only key "unavailable"label "Project selection is unavailable"
 |Some alternative=>Node key "project-choice"label Roles.Button
  (Choice SingleChoice(UX.alternative_selected alternative)description
    (Control "select"label Secondary(Input.ActivityAssignment occurrence e(Act.Assignment subject(UX.alternative_value alternative)))
      (domain_availability(UX.alternative_availability alternative))))
  [information key "label" Information.OptionLabel label;information key "description" Information.Description description]end.
Definition project_menu snapshot s e occurrence parent behavior:=
 let query:=match current_layer s occurrence with Some layer=>State.layer_query layer|None=>""end in
 let content:=match Observation.observe_property snapshot s e UX.ProjectProperty with
 |None=>[read_only parent "unavailable" "Project" "Project selection is unavailable"]
 |Some property=>let subject:=UX.property_subject property in
  Node(part parent "search")"search" "Search projects"Roles.Field
   (SearchChoices query(fun value=>option_map(Input.ActivitySearch occurrence)(as_string value)))[]::
  (map(fun choice=>project_choice snapshot s occurrence parent subject choice(fst(project_choice_details snapshot s subject choice)))
   (filter(fun choice=>negb(String.prefix "project/"(Fields.choice_value_of choice))||
    (let details:=project_choice_details snapshot s subject choice in
    BoardFilter.contains(BoardFilter.lower_text(BoardFilter.trim query))
      (BoardFilter.lower_text(String.concat " "[Fields.choice_label choice;fst details;snd details]))))
    (Observation.context_origin_choices snapshot s subject))++
  (match Projection.projects snapshot with None=>[read_only parent "unavailable" "Projects" "Project observations unavailable"]|Some _=>[]end))%list end in
 Node parent "project-selection" "Choose project"Roles.Dialog(LayerRegion behavior)
  [dialog_header parent [title parent "Choose project"];dialog_body parent
    (content++[declared parent Roles.Button(secondary "project/new" "New project"
      (Input.OpenEditor(Identity.Project None)(part parent "project/new")))])].
Definition project_request request:=match request with Act.PropertyActivity UX.ProjectProperty=>true|_=>false end.
Definition navigation_header parent caption (action:Input.input):node Input.input:=
 Node(part parent "navigation")"navigation" ""Roles.Toolbar(ActivityRow NavigationRow)
  [declared parent Roles.Button(secondary "back" "Back"action);title parent caption].
Definition activity_view snapshot s e request occurrence source_expanded parent behavior :=
 if workspace_request request && match e with Identity.Project _=>false|_=>true end
 then workspace_menu snapshot s e occurrence parent behavior else
 if project_request request && match e with Identity.Project _=>false|_=>true end
 then project_menu snapshot s e occurrence parent behavior else
 match Observation.observe_activity snapshot s e request with
 |None=>Node parent "activity-unavailable" "Settings unavailable"Roles.Dialog(LayerRegion behavior)
   [dialog_header parent [title parent "Settings unavailable"];
    dialog_body parent [read_only parent "unavailable" "Settings unavailable" "The original settings observation is unavailable"]]
 |Some activity=>
  let layer:=current_layer s occurrence in
  let view:=Observation.view_for activity(match layer with Some layer=>Observation.layer_focus layer|None=>None end)source_expanded in
  let query:=match layer with Some layer=>State.layer_query layer|None=>""end in
  let caption:=view_title activity view in
  let completion:=Observation.completion_for activity view in
  let header:=match completion with
    |Observation.ApplyAndReturn|Observation.ReturnToOwner=>
      [navigation_header parent caption(Input.ActivityComplete occurrence)]
    |_=>[title parent caption]end in
  let relations:=Act.activity_relations activity in
  let terminal:=fun relation=>match relation with Act.AssessedAction _ _=>true|_=>false end in
  let actions:=(flat_map(relation_nodes snapshot s occurrence parent query request activity view)
    (filter terminal relations) ++ match completion with
    |Observation.CommitOrDiscard=>[declared parent Roles.Button(secondary "discard" "Cancel" Input.ClosePanel)]
    |_=>[]end)%list in
  let body:=((if Observation.search_required activity view then
     [Node(part parent "search")"search" "Search models"Roles.Field
      (SearchChoices query(fun value=>option_map(Input.ActivitySearch occurrence)(as_string value)))[]]else[])++
    activity_fields snapshot s occurrence parent activity++
    flat_map(relation_nodes snapshot s occurrence parent query request activity view)(filter(fun relation=>negb(terminal relation))relations)++
    (match view with Act.PrincipalView=>
      [Node(part parent "inspection")"inspection" ""Roles.Section(ActivityRow InspectionRow)
       [declared parent Roles.Button(secondary "source"(inspection_label(UX.property_kind_of(Act.activity_property activity)))
         (Input.TogglePropertySource e occurrence))]]|_=>[]end))%list in
  Node parent "activity"caption Roles.Dialog(ActivityGroup e activity view behavior)
   (if Model.modal_layer behavior then
      ([dialog_header parent header;dialog_body parent body] ++
      (match actions with []=>[]|_=>[dialog_actions parent actions]end))%list
    else (header++body++actions)%list) end.
