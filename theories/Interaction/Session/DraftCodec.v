From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Domain Codec WorkspaceBackend.
From Selvedge.Features Require Domain Observation BoardParameters.
From Selvedge.Interaction Require Import Codec Identity Context Attachments.
From Selvedge.Interaction.Session Require Import Draft.
From Selvedge.Interaction.Submission Require Fields.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition option_text value := match value with None=>JNull|Some text=>JString text end.
Definition decode_option_text value := match value with JNull=>Some None|JString text=>Some(Some text)|_=>None end.
Definition encode_origin source := match source with
|EnvironmentDefaults=>JObject[("kind",JString "environment")]
|ProjectDefaults project=>JObject[("kind",JString "project");("project",number project)]
|ParentTask task=>JObject[("kind",JString "parent");("task",number task)]
|ProjectForParent task project=>JObject[("kind",JString "parent_project");("task",number task);("project",number project)]end.
Definition decode_origin source := match string_field "kind" source with
|Some "environment"=>Some EnvironmentDefaults
|Some "project"=>option_map ProjectDefaults(natural_field "project" source)
|Some "parent"=>option_map ParentTask(natural_field "task" source)
|Some "parent_project"=>task<-natural_field "task" source;;project<-natural_field "project" source;;Some(ProjectForParent task project)
|_=>None end.
Definition encode_choice choice := match choice with Ask=>JObject[("mode",JString "ask-for-approval")]
|Unrestricted=>JObject[("mode",JString "full-access")]
|AutomaticReview profile=>JObject[("mode",JString "approval-for-me");("reviewer_profile",JString profile)]end.
Definition decode_choice source := match string_field "mode" source with
|Some "ask-for-approval"=>Some Ask|Some "full-access"=>Some Unrestricted
|Some "approval-for-me"=>option_map AutomaticReview(string_field "reviewer_profile" source)|_=>None end.
Definition optional_value {A}(encode:A->json)(value:option A):json:=match value with Some value=>encode value|None=>JNull end.
Definition parse_optional {A}(decode:json->option A)(value:json):option(option A):=match value with JNull=>Some None|value=>option_map (@Some A)(decode value)end.
Definition encode_configuration value := JObject[("origin",encode_origin(context_origin value));
 ("workspace",optional_value Codec.workspace_json(workspace_override value));
 ("sandbox",optional_value Codec.sandbox_json(sandbox_override value));
 ("approval",optional_value encode_choice(approval_override value))].
Definition decode_configuration value := source<-bind(field "origin" value)decode_origin;;
 workspace<-bind(field "workspace" value)(parse_optional Codec.parse_workspace);;
 sandbox<-bind(field "sandbox" value)(parse_optional Codec.parse_sandbox);;
 approval<-bind(field "approval" value)(parse_optional decode_choice);;
 Some(Configuration source workspace sandbox approval).
(** Origins in serialized drafts must agree with the editor that owns the context. *)
Definition valid_origin_for_editor (e : Identity.editor) (source : Context.origin) : bool :=
 match e with
 |Identity.NewTask _|Identity.Agent _=>match source with
   |Context.ParentTask _|Context.ProjectForParent _ _=>false|_=>true end
 |Identity.Fork task=>match source with
   |Context.ParentTask parent=>N.eqb task parent
   |Context.ProjectForParent parent _=>N.eqb task parent
   |_=>false end
 |_=>true end.
Definition decode_editor_configuration e value := configuration<-decode_configuration value;;
 if valid_origin_for_editor e (Context.context_origin configuration) then Some configuration else None.
Definition optional_setting {A}(decode:json->option A)(name:string)(value:json):option(option A):=
 match field name value with None|Some JNull=>Some None|Some raw=>option_map (@Some A)(decode raw)end.
Definition configuration_of_settings value:=
 project<-optional_setting natural "project_id" value;;
 workspace<-optional_setting Codec.parse_workspace "workspace" value;;
 sandbox<-optional_setting Codec.parse_sandbox "sandbox" value;;
 approval<-optional_setting decode_choice "approval" value;;
 Some(Configuration(match project with Some id=>ProjectDefaults id|None=>EnvironmentDefaults end)workspace sandbox approval).
Definition encode_policy value := match value with
|Selvedge.Kernel.Domain.ReviewWith reviewer=>JObject[("mode",JString "approval-for-me");("reviewer",Codec.profile_json reviewer)]
|_=>Codec.approval_json value end.
Definition decode_policy value := match string_field "mode" value with
|Some "ask-for-approval"=>Some Selvedge.Kernel.Domain.AskForApproval|Some "full-access"=>Some Selvedge.Kernel.Domain.FullAccess
|Some "approval-for-me"=>profile<-bind(field "reviewer" value)Codec.parse_profile;;Some(Selvedge.Kernel.Domain.ReviewWith profile)|_=>None end.
Definition encode_text value:=JObject[("value",JString(text_value value));("images",JArray(map encode_attachment(text_images value)))].
Definition decode_text value:=text<-string_field "value" value;;images<-list_field decode_attachment "images" value;;Some(Text text images).
Definition encode_workspace_mode mode := JString(match mode with CurrentWorkspace=>"current"|ManagedWorkspace backend=>WorkspaceBackend.name backend end).
Definition decode_workspace_mode value := match value with
|JString "current"=>Some CurrentWorkspace|value=>name<-as_string value;;option_map ManagedWorkspace(WorkspaceBackend.decode name)end.
Definition encode_card value := JObject[("title",JString(Selvedge.Features.Domain.draft_title value));
 ("description",JString(Selvedge.Features.Domain.draft_description value));
 ("status",JString(Selvedge.Features.Domain.stage_name(Selvedge.Features.Domain.draft_stage value)));
 ("priority",JString(Selvedge.Features.Domain.priority_name(Selvedge.Features.Domain.draft_priority value)));
 ("assignee",JString(Selvedge.Features.Domain.owner_name(Selvedge.Features.Domain.draft_owner value)));
 ("project",optional_id(Selvedge.Features.Domain.draft_project value));
 ("labels",JArray(map JString(Selvedge.Features.Domain.draft_labels value)));
 ("attachments",JArray(map encode_attachment(Selvedge.Features.Domain.draft_attachments value)))].
Definition decode_card value := title<-string_field "title" value;;description<-string_field "description" value;;
 stage<-bind(string_field "status" value)BoardParameters.stage;;priority<-bind(string_field "priority" value)BoardParameters.priority;;
 owner<-bind(string_field "assignee" value)BoardParameters.owner;;project<-bind(field "project" value)decode_id;;
 labels<-list_field as_string "labels" value;;images<-list_field decode_attachment "attachments" value;;
 Some(Selvedge.Features.Domain.CardDraft title description stage priority owner project labels images).
Definition encode_body value := match value with
|WorkNameBody _ name=>JObject[("name",JString name)]
|NewTaskBody message profile reasoning configuration mode _=>JObject[("message",encode_text message);("profile",JString profile);("reasoning",JString reasoning);("context",encode_configuration configuration);("task_environment",encode_workspace_mode mode)]
|MessageBody _ message delivery=>JObject[("message",encode_text message);("delivery",JString(match delivery with Fields.Send=>"send"|Fields.Steer=>"steer"end))]
|ProjectBody _ name workspace worktree=>JObject[("name",JString name);("workspace",Codec.workspace_json workspace);("create_worktree",JBool worktree)]
|CardBody _ revision value assist profile keep=>JObject[("revision",number revision);("card",encode_card value);("assisted",JBool assist);("draft_profile",JString profile);("keep_open",JBool keep)]
|AgentBody _ revision name profile reasoning instructions configuration concurrency=>JObject[("revision",number revision);("name",JString name);("profile",JString profile);("reasoning",JString reasoning);("instructions",JString instructions);("context",encode_configuration configuration);("concurrency",number concurrency)]
|ForkBody _ count messages configuration=>JObject[("child_count",number count);("messages",JArray(map JString messages));("context",encode_configuration configuration)]
|CompactBody _ summary=>JObject[("summary",option_text summary)]
|TaskGraphBody _ declaration parsed _=>JObject[("declaration",JString declaration);("parsed",optional_value(fun x=>x)parsed)]
|TitlePromptsBody revision task agent=>JObject[("revision",number revision);("task_prompt",JString task);("agent_prompt",JString agent)]end.
Definition decode_body e value :option body :=match e with
|Identity.WorkName work=>option_map(WorkNameBody work)(string_field "name" value)
|Identity.NewTask work=>message<-bind(field "message" value)decode_text;;profile<-string_field "profile" value;;reasoning<-string_field "reasoning" value;;configuration<-bind(field "context" value)(decode_editor_configuration e);;mode<-bind(field "task_environment" value)decode_workspace_mode;;Some(NewTaskBody message profile reasoning configuration mode work)
|Identity.Message task=>message<-bind(field "message" value)decode_text;;delivery<-string_field "delivery" value;;match delivery with "send"=>Some(MessageBody task message Fields.Send)|"steer"=>Some(MessageBody task message Fields.Steer)|_=>None end
|Identity.Project project=>name<-string_field "name" value;;workspace<-bind(field "workspace" value)Codec.parse_workspace;;worktree<-bool_field "create_worktree" value;;Some(ProjectBody project name workspace worktree)
|Identity.Card card=>revision<-natural_field "revision" value;;contents<-bind(field "card" value)decode_card;;assist<-bool_field "assisted" value;;profile<-string_field "draft_profile" value;;keep<-bool_field "keep_open" value;;Some(CardBody card revision contents assist profile keep)
|Identity.Agent agent=>revision<-natural_field "revision" value;;name<-string_field "name" value;;profile<-string_field "profile" value;;reasoning<-string_field "reasoning" value;;instructions<-string_field "instructions" value;;configuration<-bind(field "context" value)(decode_editor_configuration e);;concurrency<-natural_field "concurrency" value;;Some(AgentBody agent revision name profile reasoning instructions configuration concurrency)
|Identity.Fork task=>count<-natural_field "child_count" value;;messages<-list_field as_string "messages" value;;configuration<-bind(field "context" value)(decode_editor_configuration e);;Some(ForkBody task count messages configuration)
|Identity.Compact task=>option_map(CompactBody task)(bind(field "summary" value)decode_option_text)
|Identity.TaskGraph graph work=>declaration<-string_field "declaration" value;;parsed<-bind(field "parsed" value)(parse_optional(fun value=>Some value));;Some(TaskGraphBody graph declaration parsed work)
|Identity.TitlePrompts=>revision<-natural_field "revision" value;;task<-string_field "task_prompt" value;;agent<-string_field "agent_prompt" value;;Some(TitlePromptsBody revision task agent)end.
Definition encode_feedback value:=match value with Editing=>JObject[("kind",JString "editing")]
|Accepted revision reply=>JObject[("kind",JString "accepted");("revision",number revision);("reply",reply)]
|Rejected revision diagnostic=>JObject[("kind",JString "rejected");("revision",number revision);("reason",diagnostic)]
|WorkspaceRejected revision reason=>JObject[("kind",JString "workspace_rejected");("revision",number revision);("reason",JString reason)]end.
Definition decode_feedback value:=match string_field "kind" value with
|Some "editing"=>Some Editing|Some "accepted"=>revision<-natural_field "revision" value;;reply<-field "reply" value;;Some(Accepted revision reply)
|Some "rejected"=>revision<-natural_field "revision" value;;diagnostic<-field "reason" value;;Some(Rejected revision diagnostic)
|Some "workspace_rejected"=>revision<-natural_field "revision" value;;reason<-string_field "reason" value;;Some(WorkspaceRejected revision reason)|_=>None end.
Definition encode_draft value:=JObject[("owner",encode_editor(owner value));("revision",number(revision value));("body",encode_body(contents value));("feedback",encode_feedback(draft_feedback value));("directory_entry",JString(directory_entry value))].
Definition decode_draft value:=e<-bind(field "owner" value)decode_editor;;revision<-natural_field "revision" value;;body<-bind(field "body" value)(decode_body e);;feedback<-bind(field "feedback" value)decode_feedback;;entry<-string_field "directory_entry" value;;Some(Draft revision body feedback entry).
