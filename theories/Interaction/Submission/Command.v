From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Kernel Require Domain Codec WorkspaceBackend.
From Selvedge.Interaction Require Import Codec Identity Context Attachments.
From Selvedge.Interaction.Session Require Draft DraftCodec.
From Selvedge.Interaction.Submission Require Fields Parameters.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition settings configuration :=
 let project:=match Context.context_origin configuration with Context.ProjectDefaults id|Context.ProjectForParent _ id=>[("project_id",number id)]|_=>[]end in
 JObject(project++
 (match Context.workspace_override configuration with Some workspace=>[("workspace",Codec.workspace_json workspace)]|None=>[]end)++
 (match Context.sandbox_override configuration with Some sandbox=>[("sandbox",Codec.sandbox_json sandbox)]|None=>[]end)++
 (match Context.approval_override configuration with Some approval=>[("approval",DraftCodec.encode_choice approval)]|None=>[]end)).
Definition content (text:string)(images:list attachment):json:=JArray
 (JObject[("type",JString "text");("text",JString text)]::map(fun image=>JObject[("type",JString "image");
 ("image",JObject[("id",JString(asset_id image));("mime",JString(asset_mime image));("bytes",number(asset_bytes image))]);("detail",JString "auto")])images).
Definition text_content value:=content(Draft.text_value value)(Draft.text_images value).
Definition side_question text:=let text:=Parameters.trim text in
 if String.eqb text "/side"then Some ""else if String.prefix "/side" text then
 match String.substring 5(String.length text)text with
 |String character rest=>if Parameters.space character || Nat.eqb(nat_of_ascii character)10 then Some(Parameters.trim rest)else None
 |_=>None end else None.
Definition present (name:string)(value:json)(fields:list(string*json)):=match value with JNull=>fields|_=> (name,value)::fields end.
Definition command_json (now:option N)(value:Draft.body):option json:=
 let record name fields:=JObject(("op",JString name)::fields)in
 match value with
 |Draft.WorkNameBody work name=>Some(record "rename_work"[("work_id",number work);("name",JString name)])
 |Draft.NewTaskBody message profile reasoning configuration mode work=>
   let fields:=[("profile",JString profile);("reasoning",JString reasoning);("message",text_content message);("settings",settings configuration)]in
   Some(match mode with
   |Draft.ManagedWorkspace WorkspaceBackend.TencentCvm=>record "create_workspace_task"(present "work_id"(optional_id work)(("backend",JString(WorkspaceBackend.name WorkspaceBackend.TencentCvm))::fields))
   |selection=>match work with
     |Some work=>record "create_work_task"(("work_id",number work)::("create_worktree",JBool(match selection with Draft.ManagedWorkspace _=>true|_=>false end))::fields)
     |None=>record(match selection with Draft.CurrentWorkspace=>"create"|_=>"create_worktree_task"end)fields end end)
 |Draft.MessageBody task message delivery=>Some(match side_question(Draft.text_value message)with
   |Some question=>record "open_side_conversation"[("task_id",number task);("message",content question(Draft.text_images message))]
   |None=>record(match delivery with Fields.Send=>"send"|Fields.Steer=>"steer"end)[("task_id",number task);("message",text_content message)]end)
 |Draft.ProjectBody project name workspace worktree=>Some(record(match project with None=>"create_project"|Some _=>"update_project"end)(present "project_id"(optional_id project)[("name",JString name);("workspace",Codec.workspace_json workspace);("create_worktree",JBool worktree)]))
 |Draft.CardBody card revision value assist profile _=>
   let metadata:=object_fields(DraftCodec.encode_card value)in
   let metadata:=set_field "project"(JString(match Selvedge.Features.Domain.draft_project value with None=>""|Some id=>show_natural id end))metadata in
   Some(record(match card with None=>"create_card"|Some _=>"update_card"end)
    (present "card_id"(optional_id card)((match card with Some _=>[("revision",number revision)]|None=>[]end)++
     (match now with Some now=>[("observed_at",JString(show_natural now))]|None=>[]end)++
     (match card with None=>[("assisted",JBool assist);("draft_profile",JString profile)]|Some _=>[]end)++metadata)))
 |Draft.AgentBody agent revision name profile reasoning instructions configuration concurrency=>Some(record "save_board_agent"[("agent",JString(match agent with None=>""|Some id=>show_natural id end));("revision",number revision);("name",JString name);("profile",JString profile);("reasoning",JString reasoning);("instructions",JString instructions);("concurrency",number concurrency);("settings",settings configuration)])
 |Draft.ForkBody task count messages configuration=>Some(record "fork"[("task_id",number task);("child_count",number count);("messages",JArray(map(fun text=>content text [])messages));("settings",settings configuration);
   ("settings_origin",JString(match Context.context_origin configuration with Context.EnvironmentDefaults|Context.ProjectDefaults _=>"environment"|_=>"parent"end))])
 |Draft.CompactBody task summary=>Some(record "compact"(present "summary"(DraftCodec.option_text summary)[("task_id",number task)]))
 |Draft.TaskGraphBody graph declaration parsed work=>parsed<-parsed;;Some(record(match graph with None=>"create_task_graph"|Some _=>"update_task_graph"end)
   (present "graph_id"(optional_id graph)(match graph with None=>present "work_id"(optional_id work)(object_fields parsed)|Some _=>object_fields parsed end)))
 |Draft.TitlePromptsBody revision task agent=>Some(record "configure_title_settings"[("revision",number revision);("task_prompt",JString task);("agent_prompt",JString agent)])end.
Definition command now value :=source<-command_json now(Draft.contents value);;Schema.decode_command command_specs source.
Definition admit_directories source:=kind<-string_field "kind" source;;if String.eqb kind "directories"then
 workspace<-bind(field "workspace" source)Codec.parse_workspace;;guidance<-field "guidance" source;;
 match Codec.parse_guidance workspace guidance with Some _=>Some(workspace,guidance)|None=>None end else None.
Definition prepare_command source (selected:Domain.workspace):option(command_value command_specs):=
 (* Browser preparation canonicalizes selected paths. The service observes
    authoritative guidance again during worker admission and execution. *)
 let workspace:=Codec.workspace_json selected in
 let prepared:=match field "workspace" source,field "settings" source with
 |Some _,_=>replace "workspace" workspace source
 |_,Some settings=>replace "settings"(replace "workspace" workspace settings)source
 |_,_=>source end in Schema.decode_command command_specs prepared.
Definition observed_command now draft (observation:Domain.workspace*json):=source<-command_json now(Draft.contents draft);;prepare_command source(fst observation).
Definition voice_json draft:=match Draft.contents draft with
|Draft.NewTaskBody _ profile reasoning configuration (Draft.ManagedWorkspace WorkspaceBackend.TencentCvm) _=>None
|Draft.NewTaskBody _ profile reasoning configuration mode work=>Some(JObject
 (("op",JString "create_idle")::("profile",JString profile)::("reasoning",JString reasoning)::("settings",settings configuration)::
  ("create_worktree",JBool(match mode with Draft.ManagedWorkspace WorkspaceBackend.Local=>true|_=>false end))::
  present "work_id"(optional_id work)[]))
|_=>None end.
Definition voice_command draft:=source<-voice_json draft;;Schema.decode_command command_specs source.
Definition observed_voice_command draft (observation:Domain.workspace*json):=source<-voice_json draft;;prepare_command source(fst observation).
