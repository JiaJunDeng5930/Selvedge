From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import TextJson.
From Selvedge.Kernel Require Domain WorkspaceBackend.
From Selvedge.Features Require BoardFilter.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity Context.
From Selvedge.Browser.Session Require Import Input.
From Selvedge.Browser.Session Require Services Observation.
From Selvedge.Interaction.Experience Require Model Activity Observation.
From Selvedge.Browser.Session Require State.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Interaction.Submission Require Parameters Values.
From Selvedge.Browser.Scene Require Import Surface Model Construction Composer.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Browser.Presentation Require Import Editors Projection.
From Selvedge.Browser.Presentation Require Roles Information.
From Selvedge.Browser.Session Require Import EditorContext.
Import ListNotations.
Open Scope string_scope.
Module UX := Selvedge.Interaction.Experience.Model.
Module Act := Selvedge.Interaction.Experience.Activity.
Definition candidate_control {e} pending occurrence (decision:UX.decision e)
 (alternative:UX.alternative e(UX.decision_subject decision)) : control Input.input :=
 let label:=UX.alternative_label alternative in
 Control label label Secondary
  (Input.ActivityAssignment occurrence e(Act.Assignment(UX.decision_subject decision)(UX.alternative_value alternative)))
  (if pending && Parameters.live_configuration e(UX.subject_declaration(UX.decision_subject decision))
   then Busy "This action is pending"else domain_availability(UX.alternative_availability alternative)).
Definition candidate_node {e} (pending show_explanations show_consequences:bool)
 (common_obstruction:option string) occurrence parent (decision:UX.decision e)
 (alternative:UX.alternative e(UX.decision_subject decision)) :=
 let label:=UX.alternative_label alternative in
 let key:=part parent("candidate/"++TextJson.render_json(Schema.encode_value(UX.subject_kind(UX.decision_subject decision))(UX.alternative_value alternative)))in
 let action:=candidate_control pending occurrence decision alternative in
 Node(part key "row")"choice-row" ""Roles.Section(ActivityRow ChoiceRow)
 [Node key "alternative"label Roles.Button
  (Choice SingleChoice(UX.alternative_selected alternative)(UX.alternative_explanation alternative)action)
  ([information key "label" Information.OptionLabel label]++
   (if show_explanations && negb(String.eqb label(UX.alternative_explanation alternative))then
    [information key "description" Information.Description(UX.alternative_explanation alternative)]else[])++
   (match UX.alternative_availability alternative,common_obstruction with
    |UX.Unavailable reason,None=>[information key "obstruction" Information.Description reason]
    |_,_=>[]end)++
   (if show_consequences then match UX.alternative_consequences alternative with
    |[]=>[]
    |consequences=>[region key "choice-consequences" "" Roles.Content
      (map(fun consequence=>information key("consequence/"++UX.subject_name(UX.summary_subject consequence))Information.Description
        (UX.readable_text(UX.summary_observation consequence)))consequences)]
    end else []))].
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
Definition common_choice_obstruction (choices:list UX.availability) :=
 match choices with
 |UX.Unavailable reason::rest=>if forallb(fun choice=>match choice with
    |UX.Unavailable other=>String.eqb reason other|UX.Available=>false end)rest then Some reason else None
 |_=>None end.
Definition decision_node {e} pending show_consequences occurrence parent query shared_explanation (decision:UX.decision e) :=
 let identity:=part parent(UX.subject_name(UX.decision_subject decision))in
 let full:=UX.decision_alternatives decision in
 let search:=BoardFilter.lower_text(BoardFilter.trim query)in
 let visible:=if String.eqb search ""then full else filter(fun alternative=>
   BoardFilter.contains search(BoardFilter.lower_text(UX.alternative_label alternative++" "++
      alternative_search_key(UX.decision_subject decision)(UX.alternative_value alternative))))full in
 let show_explanations:=match UX.subject_declaration(UX.decision_subject decision),full with
 |Fields.ModelProfile,first::rest=>
   existsb(fun alternative=>negb(String.eqb(UX.alternative_explanation first)(UX.alternative_explanation alternative)))rest
 |_,_=>true end in
 let obstruction:=common_choice_obstruction (map UX.alternative_availability visible) in
 let status:=match full,visible with
 |[],_=>[read_only identity "candidates/empty" "" (match UX.subject_declaration(UX.decision_subject decision)with
          |Fields.ModelProfile=>"No models available"|_=>"No choices have been configured"end)]
 |_,[]=>[read_only identity "candidates/no-match" "Search" "No choices match this search"]
 |_,_=>match obstruction with None=>[]
   |Some reason=>[information identity "candidates/obstruction" Information.Description reason]end end in
 Node identity "decision"(UX.decision_question decision)Roles.Section(DecisionGroup e decision)
 ([Node(part identity "heading-row")"object-heading" ""Roles.Section(ActivityRow ObjectHeading)
   [group_title identity(UX.decision_question decision)]]++status++
  map(candidate_node pending show_explanations show_consequences obstruction occurrence identity decision)visible++
  match shared_explanation with
  |Some text=>[information identity "shared-explanation" Information.Description text]
  |None=>[]end).
Definition workspace_nodes {e} s occurrence parent (members:UX.collection e) :=
 let workspace:=UX.collection_workspace members in
 let roots:=Domain.workspace_roots workspace in
 let editable:=Parameters.editable e Fields.WorkspaceDirectories in
 let heading:=match e with Identity.Project _=>
  if Selvedge.Browser.Session.Observation.worktree_required(State.current_draft s e)
  then "工作目录" else "工作目录（可选）" | _=>"" end in
 let buffer:=match find(fun layer=>N.eqb occurrence(State.layer_occurrence layer))(State.layers(State.navigation_state s))with
 |Some layer=>value_or ""(State.layer_parameter_buffer layer)|None=>""end in
 Node parent "workspace-collection" heading Roles.Section(WorkspaceCollection e members)
 ((match e with Identity.Project _=>[group_title parent heading]|_=>[]end)++
  map(fun path=>let key:=part parent path in
  let primary:=match Domain.workspace_primary workspace with Some root=>String.eqb path root|None=>false end in
  Node key "workspace-member"path Roles.Section(WorkspaceMember e members path)
   [region key "workspace-member-copy" "" Roles.Section
     [region key "workspace-member-heading" "" Roles.Section
       ([information key "name" Information.FieldValue (UX.directory_basename path)] ++
        if primary then [information key "primary-state" Information.Description "主目录"] else []);
      information key "full-path" Information.Description path];
    region key "workspace-member-actions" "" Roles.Section
     (if editable then
       ((if primary then [] else [declared key Roles.Button(secondary "primary" "设为主目录"
          (Input.ActivityWorkspaceChange occurrence(Input.ChoosePrimaryDirectory path)))]) ++
        [declared key Roles.Button(secondary "remove" "移除目录"
          (Input.ActivityWorkspaceChange occurrence(Input.RemoveDirectory path)))])%list else [])])roots ++
  if editable then
   (if String.eqb buffer ""then[]else[information parent "unadded-directory" Information.Status
     Observation.unadded_project_directory])++
   (let entry_label:=match e with
      |Identity.Project _=>match roots with []=>"目录路径"|_=>"添加另一个目录" end
      |_=>"目录路径" end in
    let entry:=Node(part parent "directory")"directory" entry_label Roles.Field
    (EnterDirectory e buffer(fun value=>option_map(Input.ActivityParameter occurrence)(as_string value))
      (if String.eqb buffer ""then None else Some(Input.ActivityWorkspaceChange occurrence(Input.AddDirectory buffer))))[] in
    let add:=declared parent Roles.Button(Control "add" "添加目录" Secondary
       (Input.ActivityWorkspaceChange occurrence(Input.AddDirectory buffer))
       (if String.eqb buffer ""then Unavailable "请输入目录路径" else Available)) in
    let clear:=if String.eqb buffer "" then [] else
       [declared parent Roles.Button(secondary "clear" "清空"(Input.ActivityParameter occurrence ""))] in
    let browse:=declared parent Roles.Button(Control "browse" "浏览…" Secondary
       (Input.ServiceInput(Services.OpenDirectory e
         (if String.eqb buffer ""then value_or ""(Domain.workspace_primary workspace)else buffer)(part parent "browse")))
       (if State.pending_editor e s then Unavailable "请等待当前操作完成。" else Available)) in
    let actions more:=region parent "directory-entry-actions" ""Roles.Toolbar (add::clear++more)%list in
    match e with
    |Identity.Project _=>
      let controls:=if String.eqb buffer "" then [browse] else [browse;add]++clear in
      [region parent "project-directory-input" entry_label Roles.Section (entry::controls)]
    |_=>[entry;actions [browse]]end) ++
   if Parameters.inheritable e && negb(UX.collection_inherited members)then
    [declared parent Roles.Button(secondary "inherit" "使用继承的工作目录"(Input.ActivityWorkspaceChange occurrence Input.InheritWorkspace))]else[]
  else[])%list.
Definition field_specification snapshot (s:State.state) {e} occurrence parent(subject:UX.subject e) :=
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
Definition dependency_summary snapshot (s:State.state) {e} occurrence parent(subject:UX.subject e) :=
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
      [read_only parent "original-project/value"
        (match e with Identity.Project _=>"原项目名称"|_=>"Original project"end)
        (UX.readable_text(UX.summary_observation first))]]
   |_=>[]end
 |_=>let subject:=Observation.expression_subject expression in
  let key:=part parent("fact/"++UX.subject_name subject)in
  [Node key "required-information" ""(match Observation.expression_information expression with UX.RequiredAbsence _=>Roles.Alert|_=>Roles.Section end)(ActivityRow SupportingRow)
    [read_only key "observation"(Parameters.label(UX.subject_declaration subject))
      (information_value(Observation.expression_information expression))]]end.
Definition configuration_source_label e :=
 match e with Identity.Project _=>"配置来源"|_=>"Configuration source"end.
Definition inherited_permission_controls s e parent :=
 match Selvedge.Browser.Session.Observation.draft_context(State.current_draft s e)with
 |None=>[]|Some configuration=>
  flat_map(fun (setting:Fields.field*string*bool)=>let '(field,label,overridden):=setting in if overridden then
   match UX.admit_subject e(Parameters.name field)with
   |Some subject=>match Input.assign_subject subject JNull with
     |Some input=>[declared parent Roles.Button(secondary("default/"++Parameters.name field)("Use defaults for "++label)input)]
     |None=>[]end
   |None=>[]end else[])
   [(Fields.SandboxMode,"filesystem and network access",match Context.sandbox_override configuration with Some _=>true|None=>false end);
    (Fields.ApprovalPolicy,"approval policy",match Context.approval_override configuration with Some _=>true|None=>false end)]end.
Definition model_picker {e} (activity:Act.activity e)(view:Act.view e) :=
 match UX.property_kind_of(Act.activity_property activity),view with
 |UX.ModelProperty,Act.PrincipalView=>true
 |_,_=>false end.
Definition selected_label {e}(decision:UX.decision e) :=
 option_map (@UX.alternative_label e (UX.decision_subject decision))
  (Observation.selected_alternative decision).
Definition picker_effort {e} (activity:Act.activity e) relations :=
 find (fun relation=>match relation with
  |Act.DependentDecision _ _ decision=>
    match UX.subject_declaration(UX.decision_subject decision),UX.decision_alternatives decision with
    |Fields.ReasoningEffort,_::_::_=>match Observation.relation_exposure activity Act.PrincipalView relation with
       |Observation.DependencySummary=>true|_=>false end
    |_,_=>false end
  |_=>false end)relations.
Definition picker_root {e} (activity:Act.activity e) :=
 find (fun relation=>match relation with
  |Act.RootDecision decision _=>match UX.subject_declaration(UX.decision_subject decision)with
     |Fields.ModelProfile=>true|_=>false end
  |_=>false end)(Act.activity_relations activity).
Definition model_settings owner occurrence parent :=
 declared parent Roles.Button(secondary "model-picker-settings" "Model settings"(Input.TogglePropertySource owner occurrence)).
Definition model_picker_view (s:State.state) {e} (activity:Act.activity e)
   occurrence parent behavior (compact:bool) query (focus:option(UX.subject e)) : node Input.input :=
 let '(root, dependencies):=match picker_root activity with
  |Some(Act.RootDecision decision relations)=>(Some decision,relations)|_=>(None,[])end in
 let effort:=match picker_effort activity dependencies with
  |Some(Act.DependentDecision _ _ decision)=>Some decision|_=>None end in
 let catalog:=match effort,focus with
   |None,_=>true
   |_,Some subject=>match UX.subject_declaration subject with Fields.ModelProfile=>true|_=>false end
   |_,None=>false end in
 let summary:=negb catalog in
 let close:=if compact then [declared parent Roles.Button(secondary "close" "Close model picker" Input.ClosePanel)]else [] in
 let switch_key:=part parent "model-picker-switch"in
 let nav:=if summary then match root with
  |Some decision=>match UX.decision_alternatives decision with
    |[]=>[model_settings e occurrence parent]
    |_=>let label:=value_or "Choose model"(selected_label decision)in
      let effort_label:=match effort with Some decision=>selected_label decision|None=>None end in
      [Node switch_key "model-picker-summary" label Roles.Button
        (Activate(secondary "model-picker-summary" ("Choose model: "++label++
          (match effort_label with Some text=>", "++text|None=>""end))
          (Input.ActivityFocus occurrence e(Some(UX.decision_subject decision)))))
        (information switch_key "model-name" Information.OptionLabel label::
         match effort_label with Some text=>[information switch_key "current-effort" Information.Description text]|None=>[]end)]
    end
  |None=>[model_settings e occurrence parent]end
  else match effort with Some _=>
    [Node switch_key "model-picker-back" "Back to reasoning effort" Roles.Button
      (Activate(secondary "model-picker-back" "Back to reasoning effort"(Input.ActivityFocus occurrence e None))) []]
  |None=>[]end in
 let pending:=UX.action_pending(Observation.action_unit_for s e)in
 let models:=if summary then [] else match root with
  |None=>[]
  |Some decision=>
    let search:=if negb(String.eqb query "") || Nat.leb 6 (List.length(UX.decision_alternatives decision)) then
      [Node(part parent "search")"search" "Search models"Roles.Field
        (SearchChoices query(fun value=>option_map(Input.ActivitySearch occurrence)(as_string value)))[]]else[] in
    (search++[region parent "model-picker-models" "" Roles.Section [decision_node pending false occurrence parent query None decision]])%list
  end in
 let effort_controls:=if catalog then [] else match effort with
   |Some decision=>[Node(part parent "model-picker-effort")"model-picker-effort" "Reasoning effort" Roles.Field
      (EffortRange(map(fun alternative=>(UX.alternative_selected alternative,candidate_control pending occurrence decision alternative))
         (UX.decision_alternatives decision)))[]]
   |None=>[]end in
 let content:=(models++effort_controls++(if summary then [] else [model_settings e occurrence parent]))%list in
 Node parent "model-picker" "Model" Roles.Dialog(ActivityGroup e activity Act.PrincipalView behavior)
  ([dialog_header parent [region parent "model-picker-header" "" Roles.Toolbar (nav++[title parent "Model"]++close)%list]]++
   match content with []=>[]|_=>[dialog_body parent content]end)%list.
Fixpoint relation_nodes {e} snapshot (s:State.state) occurrence parent query request
 (activity:Act.activity e)(view:Act.view e)(relation:Act.relation e):list(node Input.input):=
 let children:=match relation with Act.RootDecision _ children=>
  flat_map(relation_nodes snapshot s occurrence parent query request activity view)children|_=>[]end in
 match Observation.relation_exposure activity view relation,relation with
 |Observation.CandidateChoices,Act.RootDecision root _=>
  let subject:=UX.decision_subject root in
  let shared:=match UX.subject_declaration subject with
  |Fields.ApprovalPolicy=>Some(Observation.shared_permission_explanation(Observation.observe_subject snapshot s subject))
  |_=>None end in
  decision_node(UX.action_pending(Observation.action_unit_for s e))true occurrence parent query shared root::children
 |Observation.CandidateChoices,Act.DependentDecision _ _ child=>[decision_node(UX.action_pending(Observation.action_unit_for s e))true occurrence parent "" None child]
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
   match flat_map(required_expression key)(Observation.information_expressions snapshot s activity view property)with
   |[]=>[]
   |facts=>[Node key "required-value" ""Roles.Section(ActivityRow ObjectHeading)facts]end
 |Observation.RequestedInformation,Act.SupportingValue property=>
   let key:=part parent("supporting/"++UX.subject_name(UX.property_subject property))in
   match view with
   |Act.InspectionView None=>[Node key "supporting-value" ""Roles.Section(ActivityRow SupportingRow)
     ((match e with Identity.Project _=>
        [read_only key "scope" "Scope" "Applies to future tasks; existing working directories and explicit overrides are unchanged"]
       |_=>[]end)++
       [declared key Roles.Button(secondary "source/open" (configuration_source_label e++"…")(Input.InspectSource e request(part key "source/open")))]++
      match UX.property_kind_of property with
      |UX.PermissionsProperty=>inherited_permission_controls s e key|_=>[]end)]
   |Act.CompoundView=>match e with Identity.Project None=>[]|_=>
     [Node key "supporting-value" ""Roles.Section(ActivityRow InspectionRow)
     ((match e with Identity.Project _=>[]|_=>Composer.property_information key property end)++[declared key Roles.Button
       (secondary "source/open" (configuration_source_label e++"…")(Input.InspectSource e request(part key "source/open")))])]end
   |_=>[]end
 |Observation.CompoundContent,Act.CollectionMembers members=>
   workspace_nodes s occurrence(part parent "workspace")members::
   (match e with Identity.Project _=>
     (* The project commit footer shows the Git check beside the disabled action. *)
     match Editors.field_node snapshot s e parent Fields.CreateWorktree with
     |Some checkbox=>[checkbox]|None=>[]end
   |_=>[]end)
 |Observation.CompoundContent,Act.AssessedAction action outcome=>
   let assessment:=UX.Assessment(UX.action_identity_of action)outcome in
   let draft:=State.current_draft s e in
   [Node(part parent "commit")"commit" "Actions"Roles.Section(ActionUnit e action)
     (Editors.commit_reason parent assessment++Editors.commit_status parent action++[Editors.assessment_nodes parent assessment]++
      Composer.action_feedback parent action(Editors.draft_feedback draft)++
      [Node(part parent "terminal")"terminal" ""Roles.Section(ActivityRow TerminalRow)
        [Node(part parent "submit")"submit"(Editors.submit_label snapshot draft e)Roles.PrimaryButton
          (ActionCommit e assessment(Control "submit"(Editors.submit_label snapshot draft e)Primary(Input.Submit e(part parent "submit"))
           (Editors.unit_availability action assessment)))[]]])]
 |_,_=>children end.
Definition activity_fields snapshot s {e} (occurrence:N) parent (activity:Act.activity e) :=
 match activity with
 |Act.EditingActivity _ _ _=>match e with
  |Identity.Project _=>Editors.field_nodes snapshot s e parent [Fields.ProjectName]
  |_=>fold_right(fun '(name,fields) rest=>
   let fields:=filter(fun field=>match field with Fields.WorkspaceDirectories|Fields.WorkspacePrimary=>false|_=>true end)fields in
   match fields with []=>rest|_=>Editors.field_section snapshot s e parent name fields::rest end)[]
   (Editors.editor_sections e)end
 |_=>[]end.
Definition current_layer s occurrence:=find(fun layer=>N.eqb occurrence(State.layer_occurrence layer))(State.layers(State.navigation_state s)).
Definition inspection_label kind:=match kind with
|UX.ModelProperty=>"Model settings…"|UX.PermissionsProperty=>"自定义权限…"|UX.DeliveryProperty=>"发送方式详情…"|_=>"Configuration source…"end.
Definition view_title {e}(activity:Act.activity e)(view:Act.view e):string:=match view with
|Act.DependentView subject|Act.InspectionView(Some subject)=>Parameters.label(UX.subject_declaration subject)
|Act.InspectionView None=>match UX.property_kind_of(Act.activity_property activity)with UX.ModelProperty=>"Model settings"|_=>UX.property_label(Act.activity_property activity)end
|_=>match activity with Act.EditingActivity _ _ _=>Editors.editor_title e|_=>UX.property_label(Act.activity_property activity)end end.
Definition navigation_header parent caption back (action:Input.input):node Input.input:=
 Node(part parent "navigation")"navigation" ""Roles.Toolbar(ActivityRow NavigationRow)
  [declared parent Roles.Button(secondary "back" back action);title parent caption].
Definition workspace_context_header s e occurrence parent caption:=
 match State.layers(State.navigation_state s)with
 |current::origin::_=>
  if N.eqb occurrence(State.layer_occurrence current)&&run_environment_panel e(State.layer_panel origin)
  then navigation_header parent caption "返回工作环境"(Input.ActivityComplete occurrence)
  else title parent caption
 |_=>title parent caption end.
Definition run_environment_choices snapshot (s:State.state) e occurrence parent :=
 match UX.admit_subject e(Parameters.name Fields.TaskEnvironment)with
 |None=>[]
 |Some subject=>
  let decision:=Observation.decision_for snapshot s subject in
  let alternatives:=UX.decision_alternatives decision in
  let is_mode mode (alternative:UX.alternative e subject):=
    Json.equal (JString mode) (Schema.encode_value (UX.subject_kind subject) (UX.alternative_value alternative)) in
  match alternatives,find (is_mode "current") alternatives,
      find (is_mode (WorkspaceBackend.name WorkspaceBackend.Local)) alternatives with
  |[_;_],Some current,Some worktree=>
   let checked:=UX.alternative_selected worktree in
   let next:=if checked then current else worktree in
   let key:=part parent "worktree" in
   let label:="新建工作树" in
   [Node key "creation-worktree" label Roles.Button
    (Choice MultipleChoice checked ""
      (Control "worktree" label Secondary
        (Input.ActivityAssignment occurrence e(Act.Assignment subject(UX.alternative_value next)))
        (domain_availability(UX.alternative_availability next))))[]]
  |_,_,_=>map(candidate_node false false false None occurrence parent decision)alternatives
  end end.
Definition run_environment_menu snapshot (s:State.state) e occurrence parent behavior :=
 let draft:=State.current_draft s e in
 let cloud_help:=if Selvedge.Browser.Session.Observation.cloud_workspace_configured snapshot &&
    Selvedge.Browser.Session.Observation.cloud_workspace_requested draft then
  [information parent "cloud-workspace-help" Information.Description
    (Observation.cloud_source_caption snapshot draft++"请推送包含 .selvedge/env.sh 的当前提交，并选择该仓库内的目录。")]
  else[]in
 let workspace label:=declared parent Roles.Button(secondary "cloud-workspace" label
  (Input.OpenActivity e (Act.PropertyActivity UX.WorkspaceProperty)(part parent "cloud-workspace")))in
 let repair:=match Observation.run_environment_problem_for snapshot s draft with
  |None=>[]
  |Some problem=>((match Observation.environment_problem_repair problem with
    |Some Observation.ChooseCloudDirectory=>[workspace "选择工作目录…"]
    |Some Observation.UseCloudProjectDirectory=>[workspace "使用项目目录…"]
    |Some(Observation.EditCloudProject project)=>[declared parent Roles.Button(secondary "cloud-project" "编辑项目…"
       (Input.OpenEditor(Identity.Project(Some project))(part parent "cloud-project")))]
    |None=>[]end)++
    (if Observation.environment_problem_recheck problem then
      [declared parent Roles.Button(secondary "cloud-check" "重新检查"(Input.ServiceInput(Services.RefreshCloudRepository e)))]
     else[]))%list end in
 let context:=filter(fun property=>match UX.property_kind_of property with
  |UX.ProjectProperty|UX.WorkspaceProperty=>true|_=>false end)(Observation.observe_properties snapshot s e)in
 let status:=match Observation.run_environment_problem_for snapshot s draft with
 |Some problem=>[information parent "run-environment-status" Information.Status(Observation.environment_problem_message problem)]
 |None=>[]end in
 Node parent "creation-environment" "工作环境" Roles.Menu (LayerRegion behavior)
  (title parent "工作环境"::(run_environment_choices snapshot s e occurrence parent ++
    Editors.property_controls snapshot s e parent context++cloud_help++status++repair)%list).
Definition workspace_menu snapshot (s:State.state) e occurrence parent behavior:=
 Node parent "workspace-settings" "工作目录"Roles.Menu(LayerRegion behavior)
  (workspace_context_header s e occurrence parent "工作目录"::
   (match Observation.observe_collection snapshot s e with
    |Some members=>[workspace_nodes s occurrence(part parent "workspace")members]
    |None=>[read_only parent "unavailable" "工作目录" "无法读取工作目录。"]end)++
   [])%list.
Definition workspace_request request:=match request with
|Act.WorkspaceActivity|Act.PropertyActivity UX.WorkspaceProperty=>true|_=>false end.
Definition project_choice_details snapshot s {e}(subject:UX.subject e)(choice:Fields.choice_value):string*string:=
 match Values.context_origin_choice(Draft.contents(State.current_draft s e))(Fields.choice_value_of choice)with
 |Some(Context.ProjectDefaults id)|Some(Context.ProjectForParent _ id)=>
  match Read.projects snapshot with
  |Some projects=>match find(fun project=>N.eqb id(Read.project_id project))projects with
   |Some project=>(value_or "未设置主目录"(Domain.workspace_primary(Read.project_workspace project)),
     String.concat " "(Domain.workspace_roots(Read.project_workspace project)))
   |None=>("无法读取该项目的信息。","")end
  |None=>("无法读取项目信息。","")end
 |Some(Context.ParentTask _)=>("继承父对话的配置","")
 |Some Context.EnvironmentDefaults=>("","")
 |None=>("","")end.
Definition project_choice snapshot (s:State.state) {e} occurrence parent(subject:UX.subject e)(choice:Fields.choice_value)description:=
 let label:=Fields.choice_label choice in
 let key:=part parent("project/"++Fields.choice_value_of choice)in
 match Observation.alternative_from_choice snapshot s subject choice with
 |None=>read_only key "unavailable"label "无法选择项目。"
 |Some alternative=>Node key "project-choice"label Roles.Button
  (Choice SingleChoice(UX.alternative_selected alternative)description
    (Control "select"label Secondary(Input.ActivityAssignment occurrence e(Act.Assignment subject(UX.alternative_value alternative)))
      (domain_availability(UX.alternative_availability alternative))))
  [information key "label" Information.OptionLabel label;information key "description" Information.Description description]end.
Definition project_menu snapshot (s:State.state) e occurrence parent behavior:=
 let query:=match current_layer s occurrence with Some layer=>State.layer_query layer|None=>""end in
 let content:=match Observation.observe_property snapshot s e UX.ProjectProperty with
 |None=>[read_only parent "unavailable" "项目" "无法选择项目。"]
 |Some property=>let subject:=UX.property_subject property in
  Node(part parent "search")"search" "搜索项目"Roles.Field
   (SearchChoices query(fun value=>option_map(Input.ActivitySearch occurrence)(as_string value)))[]::
  (map(fun choice=>project_choice snapshot s occurrence parent subject choice(fst(project_choice_details snapshot s subject choice)))
   (filter(fun choice=>negb(String.prefix "project/"(Fields.choice_value_of choice))||
    (let details:=project_choice_details snapshot s subject choice in
    BoardFilter.contains(BoardFilter.lower_text(BoardFilter.trim query))
      (BoardFilter.lower_text(String.concat " "[Fields.choice_label choice;fst details;snd details]))))
    (Observation.context_origin_choices snapshot s subject))++
  (match Read.projects snapshot with None=>[read_only parent "unavailable" "项目" "无法读取项目信息。"]|Some _=>[]end))%list end in
 Node parent "project-selection" "选择项目"Roles.Dialog(LayerRegion behavior)
  [dialog_header parent [workspace_context_header s e occurrence parent "选择项目"];dialog_body parent
    (content++[declared parent Roles.Button(secondary "project/new" "新建项目"
      (Input.OpenEditor(Identity.Project None)(part parent "project/new")))])].
Definition project_request request:=match request with Act.PropertyActivity UX.ProjectProperty=>true|_=>false end.
Definition activity_view snapshot (s:State.state) e request occurrence source_expanded parent behavior compact_model_picker :=
 if is_run_environment_request request then run_environment_menu snapshot s e occurrence parent behavior else
 if workspace_request request && match e with Identity.Project _=>false|_=>true end
 then workspace_menu snapshot s e occurrence parent behavior else
 if project_request request && match e with Identity.Project _=>false|_=>true end
 then project_menu snapshot s e occurrence parent behavior else
 match Observation.observe_activity snapshot s e request with
 |None=>
   let '(caption,reason):=match e with
    |Identity.Project _=>("项目设置不可用","未能读取当前项目设置。")
    |_=>("Settings unavailable","The original settings observation is unavailable")end in
   Node parent "activity-unavailable" caption Roles.Dialog(LayerRegion behavior)
   [dialog_header parent [title parent caption];dialog_body parent [read_only parent "unavailable" caption reason]]
 |Some activity=>
  let layer:=current_layer s occurrence in
  let focus:=match layer with Some layer=>EditorContext.layer_focus layer|None=>None end in
  let view:=Observation.view_for activity focus source_expanded in
  let query:=match layer with Some layer=>State.layer_query layer|None=>""end in
  if model_picker activity view then model_picker_view s activity occurrence parent behavior compact_model_picker query focus else
  let caption:=view_title activity view in
  let completion:=Observation.completion_for activity view in
  let header:=match completion with
    |Observation.ApplyAndReturn|Observation.ReturnToOwner=>
      let back:=match UX.property_kind_of(Act.activity_property activity)with
       |UX.PermissionsProperty|UX.DeliveryProperty=>"返回"|_=>"Back"end in
      [navigation_header parent caption back(Input.ActivityComplete occurrence)]
    |_=>[title parent caption]end in
  let relations:=Act.activity_relations activity in
  let terminal:=fun relation=>match relation with Act.AssessedAction _ _=>true|_=>false end in
 let actions:=((match completion with
    |Observation.CommitOrDiscard=>[declared parent Roles.Button(secondary "discard"
       (match e with Identity.Project _=>"取消"|_=>"Cancel"end) Input.ClosePanel)]
    |_=>[]end) ++ flat_map(relation_nodes snapshot s occurrence parent query request activity view)
    (filter terminal relations))%list in
  let body:=((if Observation.search_required activity view then
     [Node(part parent "search")"search" "Search models"Roles.Field
      (SearchChoices query(fun value=>option_map(Input.ActivitySearch occurrence)(as_string value)))[]]else[])++
    activity_fields snapshot s occurrence parent activity++
    flat_map(relation_nodes snapshot s occurrence parent query request activity view)(filter(fun relation=>negb(terminal relation))relations)++
    (match view with Act.PrincipalView=>
      [Node(part parent "inspection")"inspection" ""Roles.Section(ActivityRow InspectionRow)
       [declared parent Roles.Button(secondary "source"(inspection_label(UX.property_kind_of(Act.activity_property activity)))
         (Input.TogglePropertySource e occurrence))]]|_=>[]end))%list in
  Node parent (match e with Identity.Project _=>"project-editor"|_=>"activity"end)
   caption Roles.Dialog(ActivityGroup e activity view behavior)
   (if Model.modal_layer behavior then
      ([dialog_header parent header;dialog_body parent body] ++
      (match actions with []=>[]|_=>[dialog_actions parent actions]end))%list
    else (header++body++actions)%list) end.
