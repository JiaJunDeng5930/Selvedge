From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Domain.
From Selvedge.Interaction Require Services.
From Selvedge.Interaction Require Import Codec Identity Input Context SkillMention.
From Selvedge.Interaction.Experience Require Model Activity Observation.
From Selvedge.Interaction.Session Require Draft State Observation Authoring.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Interaction.Presentation Require Import Surface Model Construction Composer ServiceControls Projection.
From Selvedge.Interaction.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.
Module UX := Selvedge.Interaction.Experience.Model.
Module Session := Selvedge.Interaction.Session.State.
Module Observe := Selvedge.Interaction.Experience.Observation.

Definition editor_title e := match e with
|NewTask _=>"New task"|Message _=>"Message"
|Identity.Project None=>"New project"|Identity.Project(Some _)=>"Edit project"|Card None=>"New card"|Card(Some _)=>"Edit card"
|Agent None=>"New agent"|Agent(Some _)=>"Edit agent"|Fork _=>"Fork task"|Compact _=>"Compact history"
|TaskGraph None _=>"New task graph"|TaskGraph(Some _) _=>"Edit task graph"
|WorkName _=>"Rename Work"|TitlePrompts=>"标题生成设置"end.
Definition submit_label e := match e with
|NewTask _=>"Start task"|Message _=>"Send"|Identity.Project None=>"Create project"|Card None=>"Create card"
|Agent None=>"Create agent"|TaskGraph None _=>"Create task graph"|Fork _=>"Fork task"
|Compact _=>"Compact history"|_=>"Save"end.
Definition draft_feedback d :=match Draft.draft_feedback d with
|Draft.Rejected _ diagnostic=>Some(Codec.diagnostic_message diagnostic)
|Draft.WorkspaceRejected _ reason=>Some reason|_=>None end.
Definition assessment_availability {e}(value:UX.assessment e) :=match UX.assessment_outcome value with
|UX.PreparationReady=>Available|UX.DirectoryObservationRequired _=>NeedsDirectoryObservation
|UX.PreparationBlocked first rest=>Unavailable
 (String.concat " · " (map(fun obstruction=>UX.obstruction_message obstruction)(first::rest)))end.
Definition unit_availability {e}(unit:UX.action_unit e)(assessment:UX.assessment e):availability:=
 if UX.action_pending unit then Unavailable "This action is pending"else assessment_availability assessment.
Definition field_control snapshot s {e}(subject:UX.subject e) :=
 EditControl(Observe.entry snapshot s subject)(Observe.observe_subject snapshot s subject)
  None(Observe.choices snapshot s subject)
  (match UX.subject_declaration subject with Fields.MessageText=>Draft.message_selection(Session.current_draft s e)|_=>None end) Available(if Parameters.editable e(UX.subject_declaration subject)then Some(Input.assign_subject subject)else None)
  (match UX.subject_declaration subject with Fields.MessageText=>Some(Input.selection_input subject)|_=>None end)
  (match UX.subject_declaration subject with Fields.MessageText=>
    let skills:=Selvedge.Interaction.Session.Authoring.skill_view snapshot s e in
    Some(Input.skill_key e(Selvedge.Interaction.Session.Authoring.skill_mention skills)(Selvedge.Interaction.Session.Authoring.skill_items skills))
   |_=>None end).
Definition workspace_observation value := match value with
|Fields.WorkspaceValue workspace=>Some(workspace,false)
|Fields.CommittedContextValue _ settings _=>Some(Domain.settings_workspace settings,true)
|Fields.ContextValue(Context.ProspectiveContext _ _ selected _ _ _) _=>match selected with
 |Context.InheritedWorkspace workspace=>Some(workspace,true)|Context.EnteredWorkspace workspace=>Some(workspace,false)end
|_=>None end.
Definition assignment_node {e} parent identity label (subject:UX.subject e) incoming :=
 match Input.assign_subject subject incoming with
 |Some input=>declared parent Roles.Button(secondary identity label input)
 |None=>read_only parent identity label "This value does not satisfy the field contract"end.
Definition workspace_field snapshot s {e} parent(subject:UX.subject e) :=
 match workspace_observation(Observe.observe_subject snapshot s subject)with
 |None=>read_only parent "unavailable" "Working directories" "Workspace observations unavailable"
 |Some(workspace,inherited)=>let collection:=UX.Collection workspace inherited in
  let roots:=Domain.workspace_roots workspace in
  Node parent "workspace-collection" "Working directories"Roles.Section(WorkspaceCollection e collection)
   (map(fun path=>let key:=part parent path in
    Node key "workspace-member"path Roles.Section(WorkspaceMember e collection path)
     [read_only key "path" "Directory"path;
      information key "primary-state" Information.Status(if match Domain.workspace_primary workspace with Some primary=>String.eqb path primary|None=>false end then "Primary directory"else"");
      assignment_node key "remove" "Remove directory" subject(JArray(map JString(filter(fun root=>negb(String.eqb root path))roots)));
      match UX.admit_subject e "primary_root"with
       |Some primary=>assignment_node key "primary" "Use as primary"primary(JString path)
       |None=>read_only key "primary" "Primary directory"path end])roots ++
    [declared parent Roles.Button(secondary "browse" "Add directory"
      (Input.ServiceInput(Services.OpenDirectory e(value_or ""(Domain.workspace_primary workspace))(part parent "browse"))))])%list end.
Definition field_node snapshot s e parent field :=
 match UX.admit_subject e(Parameters.name field)with
 |None=>None
 |Some subject=>let identity:=part parent(Parameters.name field)in
  Some(match Parameters.entry_for field with
   |Fields.DirectoryCollection=>workspace_field snapshot s identity subject
   |Fields.FileCollection=>ServiceControls.files e identity s
   |_=>Node identity(Parameters.name field)(Parameters.label field)Roles.Field(Edit e subject(field_control snapshot s subject))[]end)
 end.
Definition obstruction_nodes {e} parent(cause:UX.obstruction e):list(node Input.input):=
 let key:=part parent("repair/"++UX.obstruction_code cause)in
 ([Node key "property-repair"(UX.obstruction_message cause)Roles.Alert(ReadOnly(UX.obstruction_message cause))[]]++
 if String.eqb(UX.obstruction_code cause)"workspace_observation_failed"then
 [declared key Roles.Button(secondary "retry" "Retry"(Input.RetryWorkspace e(part key "retry")))]else[])%list.
Definition field_nodes snapshot s e parent fields :=
 fold_right(fun field rest=>match field_node snapshot s e parent field with
 |Some node=>node::((match Observe.attention_obstruction(UX.assessment_outcome(Observe.observe_assessment snapshot s e))with
  |Some cause=>match UX.obstruction_target cause with
   |UX.RepairField subject=>if Parameters.field_eq_dec(UX.subject_declaration subject)field
     then obstruction_nodes parent cause else[]|UX.RepairEditor=>[]end
  |None=>[]end)++rest)%list
 |None=>rest end)[]fields.
Definition property_button (snapshot:json) (s:Session.state) e parent (property:UX.property e) :=
 let identity:="composer/"++match UX.property_kind_of property with
 |UX.ProjectProperty=>"project"|UX.WorkspaceProperty=>"workspace"|UX.PermissionsProperty=>"permissions"
 |UX.ModelProperty=>"model"|UX.DeliveryProperty=>"delivery"end in
 Composer.supporting_control parent(Observe.property_support(Observe.action_unit_for s e)property)property
  (secondary identity(UX.property_label property)(Input.OpenActivity e(Activity.PropertyActivity(UX.property_kind_of property))(part parent identity))).
Definition property_controls snapshot s e parent properties :=
 flat_map(fun property=>property_button snapshot s e parent property::
  match Observe.property_obstruction property(UX.assessment_outcome(Observe.observe_assessment snapshot s e))with
  |Some cause=>obstruction_nodes parent cause|None=>[]end)
 (filter(fun property=>Observe.support_visible(Observe.property_support(Observe.action_unit_for s e)property))properties).
Definition composer_tools snapshot s e parent :=
 let selected property:=match UX.property_kind_of property with
 |UX.ModelProperty|UX.PermissionsProperty|UX.DeliveryProperty=>true|_=>false end in
 property_controls snapshot s e parent(filter selected(Observe.observe_properties snapshot s e)).
Definition assessment_nodes {e} parent (assessment:UX.assessment e):node Input.input :=
 Node(part parent "assessment")"assessment" ""Roles.Content(ActionExplanation e assessment)
  (match Observe.action_obstruction(UX.assessment_outcome assessment)with
  |Some cause=>[read_only parent "reason" ""(UX.obstruction_message cause)]|None=>[]end).
Definition skill_option_key parent skill:=part parent("skill/"++SkillMention.skill_path skill).
Definition skill_nodes snapshot s e parent :=
 let view:=Selvedge.Interaction.Session.Authoring.skill_view snapshot s e in
 let mention:=Selvedge.Interaction.Session.Authoring.skill_mention view in
 match mention with SkillMention.Suggesting _ _=>
 let items:=Selvedge.Interaction.Session.Authoring.skill_items view in
 let matches:=SkillMention.mention_candidates items mention in
 let highlighted:=SkillMention.highlighted items mention in
 let active:=option_map(skill_option_key parent)highlighted in
 let entries:=map(fun skill=>let key:=skill_option_key parent skill in
  let selected:=match active with Some current=>String.eqb key current|None=>false end in
  Node key "skill-option"(SkillMention.skill_name skill)
   (if selected then Roles.SelectedButton else Roles.Button)
   (SkillSuggestion selected(secondary "select"(SkillMention.skill_name skill)(Input.SkillSelected e(SkillMention.skill_path skill))))
   [information key "name" Information.OptionLabel(SkillMention.skill_name skill);
    information key "description" Information.Description(SkillMention.skill_description skill);
    information key "path" Information.FieldValue(SkillMention.skill_path skill)])matches in
 let empty:=match entries with _::_=>[]|[]=>
  [information parent "skills-status" Information.Status
   (match Selvedge.Interaction.Session.Authoring.skill_error view with
    |Some reason=>"Could not load skills: "++reason
    |None=>if Selvedge.Interaction.Session.Authoring.skill_loading view||Selvedge.Interaction.Session.Authoring.skill_unrequested view then "Loading skills…"else"No matching skills"end)]end in
 [Node(part parent "skill-completion")"skill-completion" "Skills"Roles.Menu
   (SkillSuggestions(part parent "message")true active)(List.app entries empty)]
 |_=>[Node(part parent "skill-completion")"skill-completion" "Skills"Roles.Menu
   (SkillSuggestions(part parent "message")false None)[]]end.
Definition composer_view snapshot s e parent :=
 match UX.admit_subject e "message"with
 |None=>None
 |Some subject=>let assessment:=Observe.observe_assessment snapshot s e in
 let unit:=Observe.action_unit_for s e in
 let commit:=Control "submit"(submit_label e)Primary(Input.Submit e(part parent "submit"))(unit_availability unit assessment)in
 Some(Composer.composer parent unit subject(field_control snapshot s subject)
  (List.app (List.app (match e with NewTask _=>field_nodes snapshot s e parent [Fields.TaskEnvironment]|_=>[]end)
     [ServiceControls.speech_controls snapshot s e(Draft.revision(Session.current_draft s e))parent(Session.speech_state s);
      ServiceControls.files e parent s;assessment_nodes parent assessment])
     (skill_nodes snapshot s e parent))
  (composer_tools snapshot s e parent)assessment commit(draft_feedback(Session.current_draft s e)))end.

(** Product sections reference the shared parameter declaration; they do not
    repeat field types, codecs, validation or assignments. *)
Definition execution_section :=("Execution context",Parameters.context_fields).
Definition model_section :=("Model",Parameters.model_fields).
Definition editor_sections e :=match e with
|WorkName _=>[("Work",[Fields.WorkName])]
|NewTask _=>[("Message",[Fields.MessageText]);model_section;execution_section;("Workspace",[Fields.TaskEnvironment])]
|Message _=>[("Message",[Fields.MessageText;Fields.DeliveryIntent]);model_section;
 ("Permissions",[Fields.SandboxMode;Fields.NetworkAccess;Fields.ApprovalPolicy;Fields.ApprovalReviewer])]
|Identity.Project _=>[("Project",[Fields.ProjectName;Fields.CreateWorktree]);("Default workspace",[Fields.WorkspaceDirectories])]
|Card id=>([("Work",[Fields.CardTitle;Fields.CardDescription]);
 ("Organization",[Fields.CardStage;Fields.CardPriority;Fields.CardOwner;Fields.CardProject;Fields.CardLabels]);
 ("Attachments",[Fields.CardAttachments])]++match id with
 |None=>[("Creation options",[Fields.ContinueCapture;Fields.AssistedCapture;Fields.AssistanceProfile])]|Some _=>[]end)%list
|Agent _=>[("Agent",[Fields.AgentName;Fields.AgentInstructions;Fields.AgentConcurrency]);model_section;execution_section]
|Fork _=>[("Fork",[Fields.ForkCount;Fields.ForkMessages]);execution_section]
|Compact _=>[("Compaction",[Fields.CompactionSummary])]
|TaskGraph _ _=>[("Task graph",[Fields.TaskGraphDeclaration])]
|TitlePrompts=>[("标题生成",[Fields.TaskTitlePrompt;Fields.AgentTitlePrompt])]end.
Definition field_section snapshot s e parent name fields:=
 Node(part parent name)name name Roles.Section(ObjectGroup(UX.group_owner e fields))
  (group_title(part parent name)name::field_nodes snapshot s e parent fields).
Definition section_nodes snapshot s e parent :=map(fun '(name,fields)=>
 field_section snapshot s e parent name fields)(editor_sections e).
Definition title_prompt_controls e parent (pending:bool):list(node Input.input):=match e with
|TitlePrompts=>
 [read_only parent "title-prompts/help" "说明"
   "Task 用于看板任务，Agent 用于执行会话，分别生成标题。修改只影响后续生成；标题最多 36 个字符。";
  declared parent Roles.Button(Control "title-prompts/reset" "恢复 Codex 默认提示词" Secondary Input.ResetTitlePrompts
   (if pending then Unavailable "The current action is pending"else Available))]
|_=>[]end.
Definition editor_view snapshot s e parent :=
 let assessment:=Observe.observe_assessment snapshot s e in
 let unit:=Observe.action_unit_for s e in
 let submit:=Control "submit"(submit_label e)Primary(Input.Submit e(part parent "submit"))(unit_availability unit assessment)in
 let body := (title_prompt_controls e parent (UX.action_pending unit) ++
   section_nodes snapshot s e parent ++
   [assessment_nodes parent assessment] ++
   Composer.action_feedback parent unit (draft_feedback (Session.current_draft s e)))%list in
 [dialog_header parent [title parent(editor_title e)];
  Node parent "editor"(editor_title e)Roles.Section(ActionUnit e unit)
   (dialog_body parent body::
    [dialog_actions parent
      [Node(part parent "submit")"submit"(control_label submit)
        (Composer.commit_role unit(draft_feedback(Session.current_draft s e)))(ActionCommit e assessment submit)[]]])].
