From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Programming Require Import Schema.
From Selvedge.Features Require Domain BoardFacts Titles.
From Selvedge.Kernel Require Domain.
From Selvedge.Browser.Session Require Services.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity Context SkillMention.
From Selvedge.Browser.Session Require Import Input.
From Selvedge.Interaction.Experience Require Model Activity Observation Read.
From Selvedge.Interaction.Submission Require Draft GraphAuthoring Initialize.
From Selvedge.Browser.Session Require State Observation Authoring ObjectActions.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Browser.Scene Require Import Surface Model Construction Composer.
From Selvedge.Browser.Presentation Require Import ServiceControls Projection.
From Selvedge.Browser.Presentation Require Roles Information Settings.
From Selvedge.Browser.Session Require Import EditorContext.
Import ListNotations.
Open Scope string_scope.
Module UX := Selvedge.Interaction.Experience.Model.
Module Session := Selvedge.Browser.Session.State.
Module Observe := Selvedge.Interaction.Experience.Observation.

Definition editor_title e := match e with
|NewTask _=>"New conversation"|Message _=>"Message"
|Identity.Project None=>"新建项目"|Identity.Project(Some _)=>"编辑项目"|Card None=>"新建卡片"|Card(Some _)=>"编辑卡片"
|CardForConversation _=>"添加到看板"
|Fork _=>ObjectActions.fork_label|Compact _=>"压缩上下文"
|TaskGraph None _=>GraphAuthoring.handoff_creation_label|TaskGraph(Some _) _=>"编辑任务图"
|WorkName None=>"新建工作组"|WorkName(Some _) =>"重命名工作组"
|TitlePrompts ConversationTitles=>Settings.conversation_titles_label
|TitlePrompts BoardTitles=>"卡片提示词" end.
Definition submit_label snapshot draft e :=match Draft.contents draft with
|Draft.MessageBody _ _ Fields.Steer=>
 if Observe.delivery_responding(Observe.delivery_task snapshot e)
 then Observe.delivery_label Fields.Steer else "发送"
|_=>match e with
|NewTask _=>"Start task"|Message _=>"发送"|Identity.Project None=>"创建项目"|Identity.Project(Some _)=>"保存"|Card None=>"创建卡片"
|CardForConversation _=>"添加卡片"
|TaskGraph None _=>GraphAuthoring.handoff_creation_label|TaskGraph(Some _) _=>"保存"|Fork _=>"创建分支"|Card(Some _)=>"保存"
|WorkName None=>"创建工作组"|WorkName(Some _)=>"保存"
|Compact _=>"压缩"|TitlePrompts _=>"保存"end end.
Definition draft_feedback d :=match Draft.draft_feedback d with
|Draft.Rejected _ diagnostic=>Some(Codec.diagnostic_message diagnostic)
|Draft.WorkspaceRejected _ reason=>Some reason|_=>None end.
Definition commit_role {e}(unit:UX.action_unit e)(feedback:option string) :=
 if UX.action_pending unit then Roles.PrimaryButton else
 match feedback with Some _=>Roles.DestructiveButton|None=>Roles.PrimaryButton end.
Definition assessment_availability {e}(value:UX.assessment e) :=match UX.assessment_outcome value with
|UX.PreparationReady=>Available|UX.DirectoryObservationRequired _=>NeedsDirectoryObservation
|UX.PreparationBlocked first rest=>Unavailable
 (String.concat " · " (map(fun obstruction=>UX.obstruction_message obstruction)(first::rest)))end.
Definition unit_availability {e}(unit:UX.action_unit e)(assessment:UX.assessment e):availability:=
 if UX.action_pending unit then Busy
  (match Observe.assessment_obstructions(UX.assessment_outcome assessment)with
   |[]=>"This action is pending"
   |causes=>String.concat " · "(map UX.obstruction_message causes)end)
 else assessment_availability assessment.
Definition field_control snapshot (s:Session.state) {e}(subject:UX.subject e) :=
 EditControl(Observe.entry snapshot s subject)(Observe.observe_subject snapshot s subject)
  None(Observe.choices snapshot s subject)
  (match UX.subject_declaration subject with Fields.MessageText=>Draft.message_selection(Session.current_draft s e)|_=>None end) Available(if Parameters.editable e(UX.subject_declaration subject)then Some(Input.assign_subject subject)else None)
  (match UX.subject_declaration subject with Fields.MessageText=>Some(Input.selection_input subject)|_=>None end)
  (match UX.subject_declaration subject with Fields.MessageText=>
    let skills:=Selvedge.Browser.Session.Authoring.skill_view snapshot s e in
    Some(Input.skill_key e(Selvedge.Browser.Session.Authoring.skill_mention skills)(Selvedge.Browser.Session.Authoring.skill_items skills))
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
Definition workspace_field snapshot (s:Session.state) {e} parent(subject:UX.subject e) :=
 match workspace_observation(Observe.observe_subject snapshot s subject)with
 |None=>region parent "unavailable" "Working directories" Roles.Section
  [information parent "label" Information.FieldLabel "Working directories";
   information parent "status" Information.Status "Workspace observations unavailable"]
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
   |Fields.FileCollection=>ServiceControls.files e identity s "添加附件"
   |_=>Node identity(Parameters.name field)(Parameters.label field)Roles.Field(Edit e subject(field_control snapshot s subject))[]end)
 end.
Definition obstruction_nodes {e} parent(cause:UX.obstruction e):list(node Input.input):=
 let key:=part parent("repair/"++UX.obstruction_code cause)in
 ([Node key "property-repair"(UX.obstruction_message cause)Roles.Alert(ReadOnly(UX.obstruction_message cause))[]]++
 if String.eqb(UX.obstruction_code cause)"workspace_observation_failed"then
 [declared key Roles.Button(secondary "retry" "Retry"(Input.RetryWorkspace e(part key "retry")))]else[])%list.
Definition graph_handoff body :=
 match body with
 |Draft.TaskGraphBody _ _ parsed _=>bind parsed GraphAuthoring.observe_handoff
 |_=>None end.
Definition visible_field_obstruction {e} (outcome:UX.assessment_result e) :=
 cause<-Observe.attention_obstruction outcome;;
 match UX.obstruction_target cause with
 |UX.RepairField subject=>Some(subject,cause)
 |UX.RepairEditor=>None end.
Definition commit_reason {e} parent (assessment:UX.assessment e) : list(node Input.input) :=
 match visible_field_obstruction(UX.assessment_outcome assessment)with
 |Some(subject,cause)=>
   (* The directory entry already displays this instruction beside Add and Clear. *)
   if String.eqb(UX.obstruction_code cause)Observe.unadded_project_directory_code then []
   else let role:=match UX.subject_declaration subject with
    |Fields.CreateWorktree=>Information.Status|_=>Information.Description end in
    [information parent "editor-commit-reason" role (UX.obstruction_message cause)]
 |None=>[]end.
Definition commit_status {e} parent (unit:UX.action_unit e) : list(node Input.input) :=
 if UX.action_pending unit then
   [information parent "editor-commit-status" Information.Status "正在提交…"]
 else [].
Definition field_nodes snapshot (s:Session.state) e parent fields :=
 let obstruction:=visible_field_obstruction(UX.assessment_outcome(Observe.observe_assessment snapshot s e))in
 fold_right(fun field rest=>match field_node snapshot s e parent field with
 |Some node=>node::((match obstruction with
  |Some(subject,cause)=>if Parameters.field_eq_dec(UX.subject_declaration subject)field
     then obstruction_nodes parent cause else[]
  |None=>[]end)++rest)%list
 |None=>rest end)[]fields.
Definition property_button (snapshot:json) (s:Session.state) e parent (property:UX.property e) :=
 let identity:="composer/"++match UX.property_kind_of property with
 |UX.ProjectProperty=>"project"|UX.WorkspaceProperty=>"workspace"|UX.PermissionsProperty=>"permissions"
 |UX.ModelProperty=>"model"|UX.DeliveryProperty=>"delivery"end in
 Composer.supporting_control parent(Observe.property_support(Observe.action_unit_for s e)property)property
  (secondary identity(UX.property_label property)(Input.OpenActivity e(Activity.PropertyActivity(UX.property_kind_of property))(part parent identity))).
Definition property_controls snapshot (s:Session.state) e parent properties :=
 flat_map(fun property=>property_button snapshot s e parent property::
  match Observe.property_obstruction property(UX.assessment_outcome(Observe.observe_assessment snapshot s e))with
  |Some cause=>let run_environment:=match UX.obstruction_target cause with
     |UX.RepairField subject=>match UX.subject_declaration subject with Fields.TaskEnvironment=>true|_=>false end
     |UX.RepairEditor=>false end in
   if run_environment || String.eqb(UX.obstruction_code cause)"model_not_found" then []
   else obstruction_nodes parent cause
  |None=>[]end)
 (filter(fun property=>Observe.support_visible(Observe.property_support(Observe.action_unit_for s e)property))properties).
Definition composer_tools snapshot (s:Session.state) e parent :=
 let selected property:=match UX.property_kind_of property with
 |UX.ModelProperty|UX.PermissionsProperty|UX.DeliveryProperty=>true|_=>false end in
 let tools:=property_controls snapshot s e parent(filter selected(Observe.observe_properties snapshot s e))in
 match e with
 |NewTask _=>
  let key:="composer/environment" in
  (tools++[declared parent Roles.Button(secondary key "配置工作环境"
    (Input.OpenActivity e run_environment_request (part parent key)))])%list
 |_=>tools end.
Definition assessment_nodes {e} parent (assessment:UX.assessment e):node Input.input :=
 Node(part parent "assessment")"assessment" ""Roles.Content(ActionExplanation e assessment)
  (match Observe.action_obstruction(UX.assessment_outcome assessment)with
  |Some cause=>[read_only parent "reason" ""(UX.obstruction_message cause)]|None=>[]end).
Definition skill_option_key parent index:=part parent("skill/"++show_natural(N.of_nat index)).
Definition skill_nodes snapshot s e parent :=
 let view:=Selvedge.Browser.Session.Authoring.skill_view snapshot s e in
 let mention:=Selvedge.Browser.Session.Authoring.skill_mention view in
 match mention with SkillMention.Suggesting _ _=>
 let items:=Selvedge.Browser.Session.Authoring.skill_items view in
 let matches:=SkillMention.mention_candidates items mention in
 let highlighted:=SkillMention.highlighted_choice items mention in
 let indexed:=combine (seq 0 (List.length matches)) matches in
 let active:=option_map (fun item=>skill_option_key parent (fst item)) highlighted in
 let entries:=map(fun item=>let '(index,skill):=item in let key:=skill_option_key parent index in
  let selected:=match active with Some current=>String.eqb key current|None=>false end in
  Node key "skill-option"(SkillMention.skill_name skill)
   (if selected then Roles.SelectedButton else Roles.Button)
   (SkillSuggestion selected(secondary "select"(SkillMention.skill_name skill)(Input.SkillSelected e(SkillMention.skill_path skill))))
   [information key "name" Information.OptionLabel(SkillMention.skill_name skill);
    information key "description" Information.Description(SkillMention.skill_description skill);
    information key "path" Information.FieldValue(SkillMention.skill_path skill)])indexed in
 let empty:=match entries with _::_=>[]|[]=>
  [information parent "skills-status" Information.Status
   (match Selvedge.Browser.Session.Authoring.skill_error view with
    |Some reason=>"Could not load skills: "++reason
    |None=>if Selvedge.Browser.Session.Authoring.skill_loading view||Selvedge.Browser.Session.Authoring.skill_unrequested view then "Loading skills…"else"No matching skills"end)]end in
 [Node(part parent "skill-completion")"skill-completion" "Skills"Roles.Menu
   (SkillSuggestions(part parent "message")true active)(List.app entries empty)]
 |_=>[Node(part parent "skill-completion")"skill-completion" "Skills"Roles.Menu
   (SkillSuggestions(part parent "message")false None)[]]end.
Definition composer_view snapshot (s:Session.state) e parent :=
 match UX.admit_subject e "message"with
 |None=>None
 |Some subject=>let assessment:=Observe.observe_assessment snapshot s e in
 let unit:=Observe.action_unit_for s e in
 let feedback:=draft_feedback(Session.current_draft s e)in
 let message_label:=match e with NewTask _=>"Task"|_=>"Message"end in
 let commit:=Control "submit"(submit_label snapshot(Session.current_draft s e)e)Primary(Input.Submit e(part parent "submit"))(unit_availability unit assessment)in
 let '(failed, files):=partition (fun item=>match node_role item with Roles.Alert=>true|_=>false end)
   (ServiceControls.file_items e parent s) in
 let attachments:=match List.app failed files with
  |[]=>[]|items=>[region parent "attachments" "Attachments" Roles.Section items]end in
 let tools:=composer_tools snapshot s e parent in
 Some(Composer.composer parent message_label(commit_role unit feedback)unit subject(field_control snapshot s subject)
  (attachments++[assessment_nodes parent assessment]++skill_nodes snapshot s e parent)%list
  [ServiceControls.file_picker e parent s "Attach files";
   ServiceControls.speech_controls snapshot s e(Draft.revision(Session.current_draft s e))parent(Session.speech_state s)]
  tools assessment commit feedback)end.

(** Product sections reference the shared parameter declaration; they do not
    repeat field types, codecs, validation or assignments. *)
Definition execution_section :=("Execution context",Parameters.context_fields).
Definition model_section :=("Model",Parameters.model_fields).
Definition editor_sections e :=match e with
|NewTask _=>[("Message",[Fields.MessageText]);model_section;execution_section;("Workspace",[Fields.TaskEnvironment])]
|Message _=>[("Message",[Fields.MessageText;Fields.DeliveryIntent]);model_section;
 ("Permissions",[Fields.SandboxMode;Fields.NetworkAccess;Fields.ApprovalPolicy;Fields.ApprovalReviewer])]
|Card id=>([("Work",[Fields.CardTitle;Fields.CardDescription]);
 ("Organization",[Fields.CardStage;Fields.CardPriority;Fields.CardOwner;Fields.CardProject;Fields.CardLabels]);
 ("Attachments",[Fields.CardAttachments])]++match id with
 |None=>[("Creation options",[Fields.ContinueCapture;Fields.AssistedCapture;Fields.AssistanceProfile])]|Some _=>[]end)%list
|Fork _=>[("Fork",[Fields.ForkCount;Fields.ForkMessages]);execution_section]
|Compact _=>[("Compaction",[Fields.CompactionSummary])]
|TaskGraph _ _=>[("Task graph",[Fields.TaskGraphDeclaration])]
|Identity.Project _|CardForConversation _|WorkName _|TitlePrompts _=>[]end.
Definition field_section snapshot s e parent name fields:=
 Node(part parent name)name name Roles.Section(ObjectGroup(UX.group_owner e fields))
  (group_title(part parent name)name::field_nodes snapshot s e parent fields).
Definition editor_options {A} parent key label (children:list(node A)) :=
 Node(part parent key)key label Roles.Section EditorOptions children.
Definition card_editor snapshot s e parent (target:Identity.card_subject) :=
 let source:=match target with
 |Identity.BoardCard _=>[]
 |Identity.ConversationCard task=>
  List.app [read_only parent "linked-conversation" "关联对话"
    (value_or ("对话 #"++show_natural task)(option_map task_title(find_task task snapshot)))] (
  match Read.card_link_stage task snapshot with
  |Some stage=>List.app [read_only parent "destination-stage" "预计进入"(Selvedge.Features.Domain.stage_label stage)]
   (match stage with
   |Selvedge.Features.Domain.InReview=>[information parent "destination-reason" Information.Description "对话当前未运行。"]
   |_=>[]end)
  |None=>[] end) end in
 let stage:=match target with Identity.BoardCard _=>[Fields.CardStage]|_=>[]end in
 let pair key fields:=Node(part parent key)"card-option-pair" "" Roles.Content Region
   (field_nodes snapshot s e parent fields)in
 let details:=List.app
   [pair "classification" (List.app stage [Fields.CardPriority]);
    pair "ownership" [Fields.CardOwner;Fields.CardProject]]
   (field_nodes snapshot s e parent [Fields.CardLabels]) in
 let assistance:=match target with
  |Identity.BoardCard None=>match Draft.contents(Session.current_draft s e)with
      |Draft.CardBody _ _ _ true _ _=>[Fields.AssistedCapture;Fields.AssistanceProfile]
      |_=>[Fields.AssistedCapture] end
  |_=>[]end in
 let content:=Node(part parent "card-content")"card-content" "" Roles.Content Region
   (field_nodes snapshot s e parent ([Fields.CardDescription;Fields.CardAttachments]++assistance)) in
 (source++field_nodes snapshot s e parent [Fields.CardTitle]++
 [content;editor_options parent "card-options" "更多卡片选项" details])%list.
Definition fork_editor snapshot s e parent task :=
 let source:=value_or ("对话 #"++show_natural task)(option_map task_title(find_task task snapshot)) in
 [read_only parent "fork-source" "来源对话" source;
  information parent "fork-history" Information.Description "分支会继承这条对话当前的历史。";
  editor_options parent "fork-options" "分支选项"
   [field_section snapshot s e parent "分支" [Fields.ForkCount;Fields.ForkMessages];
    field_section snapshot s e parent "运行设置" Parameters.context_fields]].
Definition handoff_choices (available:list task) :=
 map(fun task=>
  let id:=task_id task in
  let title:=task_title task in
  let duplicated:=existsb(fun other=>negb(N.eqb id(task_id other))&&
   String.eqb title(task_title other))available in
  let value:=show_natural id in
  Fields.ChoiceValue value (if duplicated then title++" · #"++value else title))available.
Definition graph_input parent key label text options (receive:json->option Input.input) :=
 Node(part parent key)key label Roles.Field(ConfigurationField false text options true receive)[].
Definition graph_endpoint parent key label (available:list Fields.choice_value) selected other receive :=
 let excluded:=value_or ""(option_map show_natural other) in
 let choices:=Fields.ChoiceValue "" "选择对话"::
   filter(fun choice=>negb(String.eqb excluded(Fields.choice_value_of choice)))available in
 graph_input parent key label (value_or ""(option_map show_natural selected))(Some choices)
   (fun value=>text<-as_string value;;
    if String.eqb text "" then receive None else
    id<-parse_natural text;;
    if existsb(fun choice=>String.eqb text(Fields.choice_value_of choice))choices
    then receive(Some id)else None).
Definition handoff_fields snapshot e parent work (handoff:GraphAuthoring.handoff) :=
 let name:=GraphAuthoring.handoff_name handoff in
 let source:=GraphAuthoring.handoff_source handoff in
 let target:=GraphAuthoring.handoff_target handoff in
 match UX.admit_subject e (Parameters.name Fields.TaskGraphDeclaration) with
 |None=>[]
 |Some subject=>
  let assign name source target:=Input.assign_subject subject(JString(TextJson.render_json
    (GraphAuthoring.handoff_declaration(GraphAuthoring.Handoff name source target)))) in
  graph_input parent "handoff-name" GraphAuthoring.handoff_name_label name None
    (fun value=>name<-as_string value;;assign name source target)::
  match Observe.handoff_conversations snapshot work with
  |Some(inr available)=>
    let choices:=handoff_choices available in
    [region parent "handoff-route" "转发方向" Roles.Section
      [graph_endpoint parent "handoff-source" GraphAuthoring.source_endpoint_label choices source target (fun id=>assign name id target);
       Node(part parent "handoff-direction")"handoff-direction" "" Roles.Decorative(Fact "→")[];
       graph_endpoint parent "handoff-target" GraphAuthoring.target_endpoint_label choices target source (fun id=>assign name source id)];
     information parent "handoff-purpose" Information.Description "自动把新回复作为消息转发。"]
  |Some(inl shortage)=>
    information parent "handoff-needs-conversations" Information.Description shortage::
    match e with
    |TaskGraph None _=>[declared parent Roles.Button(secondary "handoff-new-conversation" "新建对话" Input.BeginGraphConversation)]
    |_=>[]end
  |None=>[information parent "handoff-conversations-unavailable" Information.Description Observe.handoff_conversations_loading]
  end
 end.
Definition graph_editor snapshot s e parent (graph:option N) work :=
 let declaration:=field_nodes snapshot s e parent [Fields.TaskGraphDeclaration] in
 (* Select the editor from the saved graph so changing JSON cannot replace the
    active textarea. An existing graph always keeps its own Work scope. *)
 let picker_scope:=match graph with
  |None=>Some work
  |Some id=>match bind (Initialize.materialize_body snapshot None e) graph_handoff with
    |Some _=>option_map graph_work (find_graph id snapshot)
    |None=>None end
  end in
 match picker_scope with
 |None=>declaration
 |Some scope=>
   let quick:=match graph_handoff (Draft.contents(Session.current_draft s e)) with
    |Some handoff=>handoff_fields snapshot e parent scope handoff
    |None=>[]end in
   (quick++[editor_options parent "graph-options" "编辑 JSON 定义" declaration])%list
 end.
Definition title_prompt_reset snapshot s scope parent : list (node Input.input) :=
 let owner := TitlePrompts scope in
 let default := Titles.instruction_text (match scope with
  |ConversationTitles=>Titles.default_instructions|BoardTitles=>Titles.default_board_instructions end) in
 match UX.admit_subject owner (Parameters.name (Parameters.title_prompt_field scope)) with
 |Some subject=>match Observe.observe_subject snapshot s subject, Input.assign_subject subject (JString default) with
  |Fields.TextValue value, Some input=>if String.eqb value default then [] else
   let label := match scope with
    |ConversationTitles=>"恢复默认" ++ Parameters.label (Parameters.title_prompt_field scope)
    |BoardTitles=>"恢复默认卡片提示词" end in
   [declared parent Roles.Button(Control "title-prompts/reset" label Secondary input
     (if UX.action_pending (Observe.action_unit_for s owner) then Unavailable "请等待当前操作完成" else Available))]
  |_,_=>[] end
 |None=>[] end.
Definition title_prompt_fields snapshot s scope parent :=
 let owner := TitlePrompts scope in
 let prompt := part parent "title-prompt" in
 (match scope with
  |ConversationTitles=>field_nodes snapshot s owner parent [Fields.AgentTitleProfile]
  |BoardTitles=>[] end ++
  [region parent "title-prompt" "" Roles.Section
    (field_nodes snapshot s owner prompt [Parameters.title_prompt_field scope] ++
     title_prompt_reset snapshot s scope prompt)])%list.
Definition section_nodes snapshot s e parent :=
 match e with
 |Card id=>card_editor snapshot s e parent (Identity.BoardCard id)
 |CardForConversation task=>card_editor snapshot s e parent (Identity.ConversationCard task)
 |Fork task=>fork_editor snapshot s e parent task
 |TaskGraph graph work=>graph_editor snapshot s e parent graph work
 |WorkName _=>field_nodes snapshot s e parent [Fields.WorkName]
 |TitlePrompts scope=>title_prompt_fields snapshot s scope parent
 |_=>map(fun '(name,fields)=>field_section snapshot s e parent name fields)(editor_sections e)
 end.
Definition title_prompt_help e parent : list (node Input.input) := match e with
|TitlePrompts ConversationTitles=>
 [information parent "title-prompts/help" Information.Description
   "对话标题根据首条消息生成。标题最多 36 个字符，更改只影响之后的生成。"]
|TitlePrompts BoardTitles=>
 [information parent "title-prompts/help" Information.Description
   "新建时勾选模型整理，会生成标题和描述。重新生成标题时保留描述。"]
|_=>[]end.
Definition editor_view snapshot (s:Session.state) e parent :=
 let draft:=Session.current_draft s e in
 let assessment:=Observe.observe_assessment snapshot s e in
 let unit:=Observe.action_unit_for s e in
 let submit:=Control "submit"(submit_label snapshot draft e)Primary(Input.Submit e(part parent "submit"))(unit_availability unit assessment)in
 let reason:=commit_reason parent assessment in
 let consequence:=if UX.action_pending unit then [] else match e with
 |Card _=>match Observe.card_save_consequence snapshot s draft with
  |Some value=>[information parent "card-save-consequence" Information.Description
   (match value with
    |BoardFacts.SaveManual=>"只保存卡片。对话需要手动启动。"
    |BoardFacts.SaveNeedsStage=>"只保存卡片。移到「待办」可自动排队。"
    |BoardFacts.SaveStarts=>"保存后会尝试启动对话。"
    |BoardFacts.SaveQueues=>"保存后自动排队，轮到这张卡片时尝试启动对话。"
    |BoardFacts.SaveWaitsForModel=>"保存后进入队列，等模型空闲再尝试启动对话。"
    |BoardFacts.SaveDrafts=>"保存后先生成卡片内容，暂不启动对话。"
    |BoardFacts.SaveDraftsThenQueues=>"保存后先生成卡片内容，成功后自动排队。"
    |BoardFacts.SaveLinked=>"保存卡片，保留已关联的对话。"end)]
  |None=>[]end
 |_=>[]end in
 let body := (title_prompt_help e parent ++
   section_nodes snapshot s e parent ++
   [assessment_nodes parent assessment] ++
   Composer.action_feedback parent unit (draft_feedback draft))%list in
 let context := match e with
   |TitlePrompts ConversationTitles=>[Settings.editor_context parent Services.SettingsGeneral]
   |_=>[]end in
 let capture:=match e with
   |Card None=>field_nodes snapshot s e parent [Fields.ContinueCapture]
   |_=>[]end in
 [dialog_header parent (context ++ [title parent(editor_title e)]);
  Node parent "editor"(editor_title e)Roles.Section(ActionUnit e unit)
   (dialog_body parent body::
    [dialog_actions parent
      (reason ++ commit_status parent unit ++ consequence ++ capture ++ [declared parent Roles.Button(secondary "cancel"
        (match e with Card _|TaskGraph _ _|Fork _|Compact _|WorkName _|TitlePrompts _=>"取消"|_=>"Cancel"end) Input.ClosePanel)] ++
       [Node(part parent "submit")"submit"(control_label submit)
         (commit_role unit(draft_feedback draft))(ActionCommit e assessment submit)[]])%list])].
