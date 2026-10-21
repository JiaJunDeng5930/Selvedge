From Stdlib Require Import String List Bool Ascii NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands WorkspaceBackend.
From Selvedge.Features Require Domain.
From Selvedge.Interaction Require Import Codec Identity Attachments.
Import ListNotations.
Open Scope string_scope.

Record form_field := FormField { specification:field_spec; label:string; help:string; widget:string }.
Definition text_input name caption := FormField(Field name KText)caption "" "text".
Definition multiline name caption := FormField(Field name KText)caption "" "textarea".
Definition select_input name caption first rest := FormField(Field name(KEnum first rest))caption "" "select".
Definition optional_input name caption kind widget := FormField(Field name(KOptional kind))caption "Use the inherited value when empty." widget.
Definition bool_input name caption := FormField(Field name KBool)caption "" "checkbox".
Definition natural_input name caption := FormField(Field name KNatural)caption "" "number".
Definition json_input name caption := FormField(Field name KJson)caption "" "json".
Definition context_fields :=
 [optional_input "project_id" "Defaults from" KNatural "project";
  optional_input "primary_root" "Primary directory" KText "directory";
  FormField(Field "roots"(KArray KText))"Working directories" "Additional directories available to this task." "lines";
  optional_input "sandbox" "Filesystem access" (KEnum "workspace-write" ["read-only"])"select";
  optional_input "network_access" "Network access" KBool "checkbox";
  optional_input "approval" "Approval policy" (KEnum "ask-for-approval" ["full-access";"approval-for-me"])"select";
  optional_input "reviewer_profile" "Reviewing model" KText "profile"].
Definition permission_fields := filter(fun f=>existsb(String.eqb(field_name(specification f)))["sandbox";"network_access";"approval";"reviewer_profile"])context_fields.
Definition concrete_permission_fields := map(fun f=>let spec:=specification f in
 match field_kind spec with KOptional k=>if String.eqb(field_name spec)"reviewer_profile"then f else FormField(Schema.Field(field_name spec)k)(label f)""(widget f)|_=>f end)permission_fields.
Definition model_fields := [FormField(Field "profile" KText)"Model" "The model used for this task." "profile";
  text_input "reasoning" "Reasoning effort"].
Inductive task_workspace := CurrentWorkspace | ManagedWorkspace (backend:WorkspaceBackend.backend).
Definition managed_workspace_names := match WorkspaceBackend.declaration with
 |KEnum first rest=>first::rest|_=>[] end.
Definition task_workspace_kind := KEnum "current" managed_workspace_names.
Definition task_workspace_name choice := match choice with
 |CurrentWorkspace=>"current"|ManagedWorkspace backend=>WorkspaceBackend.name backend end.
Definition task_workspace_value (value:denote task_workspace_kind) : task_workspace.
Proof.
 destruct value as [value member].
 destruct(String.eqb value "current")eqn:current.
 - exact CurrentWorkspace.
 - refine(ManagedWorkspace(WorkspaceBackend.of_value(exist _ value _))).
   simpl in member. destruct member as [same|member].
   + subst value. rewrite String.eqb_refl in current. discriminate.
   + exact member.
Defined.
Definition task_workspace_field := FormField(Field "task_environment" task_workspace_kind)
 "Task environment" "Cloud Bash uses Full Access; MCP tools remain on the host." "select".
Definition new_task_fields : list form_field := [multiline "message" "Task"]++model_fields++context_fields.
Definition form_fields (e:editor) : list form_field :=
  match e with
  | NewTask _=>new_task_fields++[task_workspace_field]
  | Message _=>[multiline "message" "Message";select_input "delivery" "Send as" "send"["steer"]]++model_fields++concrete_permission_fields
  | Project _=>[text_input "name" "Name";optional_input "primary_root" "Primary directory" KText "directory";
      FormField(Field "roots"(KArray KText))"Working directories" "Project directories." "lines";
      bool_input "create_worktree" "Create worktree for new tasks"]
  | Card _=>[text_input "title" "Title";multiline "description" "Description";
      select_input "status" "Stage"(Domain.stage_name Domain.Backlog)(map Domain.stage_name(tl Domain.stages));
      select_input "priority" "Priority"(Domain.priority_name Domain.NoPriority)(map Domain.priority_name(tl Domain.priorities));
      text_input "assignee" "Assignee";text_input "project" "Project";
      FormField(Field "labels"(KArray KText))"Labels" "One label per line." "lines";
      natural_input "revision" "Revision";bool_input "assisted" "Assist with title and description";
      text_input "draft_profile" "Assistance model";bool_input "keep_open" "Create another after saving"]
  | Agent _=>[text_input "name" "Name";multiline "instructions" "Instructions";
      natural_input "concurrency" "Concurrent tasks";natural_input "revision" "Revision"]++model_fields++context_fields
  | Fork _=>[natural_input "child_count" "Number of tasks";FormField(Field "messages"(KArray KText))"Initial messages" "One request per branch." "lines"]++context_fields
  | Compact _=>[optional_input "summary" "Summary override" KText "textarea"]
  | TaskGraph _ _=>[json_input "declaration" "Declaration"]
  | WorkName _=>[text_input "name" "Name"]
  | TitlePrompts=>[natural_input "revision" "Revision";multiline "task_prompt" "Task 看板标题提示词";multiline "agent_prompt" "Agent 会话标题提示词"]
  end.
Definition form_schema e := map specification(form_fields e).
Inductive feedback := Editing | Accepted(reply:json) | Rejected(reason:string) | WorkspaceRejected(reason:string).
Record draft := Draft { owner:editor; revision:N; values:fields(form_schema owner); attachments:list attachment; raw_fields:list(string*string); status:feedback }.
Definition new_draft e :=
  match e as e return draft with
  |TaskGraph id work=>Draft(TaskGraph id work)0(@FCons (Schema.Field "declaration" KJson) [] (encode graph_fields(defaults graph_fields)) FNil)[][]Editing
  |e=>Draft e 0 (defaults(form_schema e))[][]Editing end.
Fixpoint skip_fields (prefix suffix:schema) : fields(List.app prefix suffix)->fields suffix :=
 match prefix as prefix return fields(List.app prefix suffix)->fields suffix with
 |[]=>fun values=>values
 |_::rest=>fun values=>skip_fields rest suffix(tail values) end.
Definition new_task_workspace work (v:fields(form_schema(NewTask work))) :=
 task_workspace_value(head(skip_fields(map specification new_task_fields)[specification task_workspace_field]v)).
Definition selected_workspace d :=
 match d with Draft e _ v _ _ _=>
  match e as e return fields(form_schema e)->task_workspace with
  |NewTask work=>fun values=>new_task_workspace work values
  |_=>fun _=>CurrentWorkspace end v end.
Definition local_worktree d := match selected_workspace d with
 |ManagedWorkspace WorkspaceBackend.Local=>true|_=>false end.
Definition cloud_workspace d := match selected_workspace d with
 |ManagedWorkspace backend=>WorkspaceBackend.cloud backend|CurrentWorkspace=>false end.
Definition data d := encode(form_schema(owner d))(values d).
Definition get name d := value_or JNull(lookup_field name(values d)).
Definition read_text name d := value_or ""(as_string(get name d)).
Definition read_flag name d := value_or false(as_bool(get name d)).
Definition read_list name d := value_or [](as_array(get name d)).
Definition with_revision n d := Draft(owner d)n(values d)(attachments d)(raw_fields d)(status d).
Definition with_status f d := Draft(owner d)(revision d)(values d)(attachments d)(raw_fields d)f.
Definition with_attachments xs d := Draft(owner d)(N.succ(revision d))(values d)xs(raw_fields d)Editing.
Definition edit_field name value d : option draft :=
  v<-update_field name value(values d);;Some(Draft(owner d)(N.succ(revision d))v(attachments d)(filter(fun p=>negb(String.eqb name(fst p)))(raw_fields d))Editing).
Definition restore_field name value d : option draft :=
  v<-update_field name value(values d);;Some(Draft(owner d)(revision d)v(attachments d)(raw_fields d)(status d)).
Fixpoint restore_fields fields d := match fields with []=>Some d|(name,value)::rest=>d'<-restore_field name value d;;restore_fields rest d' end.
Fixpoint lines_from (current:string) (text:string) : list string :=
  match text with EmptyString=>[current]|String c rest=>if Ascii.eqb c (Ascii.ascii_of_nat 10) then current::lines_from "" rest else lines_from(String.append current(String c ""))rest end.
Definition lines text:=if String.eqb text ""then []else lines_from "" text.
Fixpoint raw_value (k:kind) (raw:json) : json :=
  match k,raw with
  |KNatural,JString s|KInteger,JString s|KDecimal,JString s=>JNumber s
  |KOptional _,JString ""=>JNull
  |KOptional k,raw=>raw_value k raw
  |KArray KText,JString s=>JArray(map JString(lines s))
  |_,_=>raw end.
Definition field_description name d := find(fun f=>String.eqb name(field_name f))(form_schema(owner d)).
Definition edit_raw_field name raw d : option draft :=
  f<-field_description name d;;
  match edit_field name(raw_value(field_kind f)raw)d with
  |Some d'=>Some d'
  |None=>match raw with JString text=>Some(Draft(owner d)(N.succ(revision d))(values d)(attachments d)((name,text)::filter(fun p=>negb(String.eqb name(fst p)))(raw_fields d))Editing)|_=>None end end.
Definition raw_text name d := match find(fun p=>String.eqb name(fst p))(raw_fields d)with Some(_,s)=>Some s|None=>None end.
Definition content text images := JArray
  (JObject[("type",JString "text");("text",JString text)]::map(fun a=>JObject[("type",JString "image");
    ("image",JObject[("id",JString(asset_id a));("mime",JString(asset_mime a));("bytes",number(asset_bytes a))]);("detail",JString "auto")])images).
Definition workspace_after_edit name d :=
 let roots:=read_list "roots" d in let primary:=get "primary_root" d in
 if String.eqb name "primary_root"then
  match primary with
  |JString path=>if existsb(Json.equal primary)roots then Some d else restore_field "roots"(JArray(roots++[JString path]))d
  |JNull=>match roots with []=>Some d|first::_=>restore_field "primary_root" first d end
  |_=>None end
 else if String.eqb name "roots"then
  if existsb(Json.equal primary)roots then Some d else
   restore_field "primary_root"(match roots with []=>JNull|first::_=>first end)d
 else Some d.
Definition workspace d := JObject[("roots",JArray(read_list "roots" d));("primary_root",get "primary_root" d)].
Definition present (name:string) value rest := match value with JNull=>rest|_=> (name,value)::rest end.
Definition settings d :=
  let approval:=read_text "approval" d in
  let policy:=match get "approval" d with JNull=>JNull|_=>JObject
    (present "reviewer_profile" (get "reviewer_profile" d)[("mode",JString approval)])end in
  let sandbox:=match get "sandbox" d with JNull=>JNull|v=>JObject[("mode",v);("network_access",JBool(read_flag "network_access" d))]end in
  let workspace:=match get "primary_root" d,read_list "roots" d with JNull,[]=>JNull|_,_=>workspace d end in
  JObject(present "project_id"(get "project_id" d)(present "workspace" workspace(present "sandbox" sandbox(present "approval" policy [])))).
Definition ascii_space c := existsb(Ascii.eqb c)[" "%char;Ascii.ascii_of_nat 9;Ascii.ascii_of_nat 10;Ascii.ascii_of_nat 13].
Fixpoint trim_start s := match s with String c rest=>if ascii_space c then trim_start rest else s|EmptyString=>s end.
Fixpoint trim_end s := match s with EmptyString=>s|String c rest=>let tail:=trim_end rest in if String.eqb tail "" && ascii_space c then "" else String c tail end.
Definition trim s := trim_end(trim_start s).
Definition side_question s :=
  let s:=trim s in
  if String.eqb s "/side" then Some "" else
  if String.prefix "/side" s then match String.substring 5 (String.length s) s with
    String c rest=>if ascii_space c then Some(trim rest)else None|_=>None end else None.
Definition message_command task d :=
  let body:=read_text "message" d in
  match side_question body with
  | Some question=>JObject[("op",JString "open_side_conversation");("task_id",number task);("message",content question(attachments d))]
  | None=>JObject[("op",JString(read_text "delivery" d));("task_id",number task);("message",content body(attachments d))]end.
Definition command d :=
  let record op fields:=JObject(("op",JString op)::fields)in
  let fs:=object_fields(data d)in
  match owner d with
  | NewTask work=>let fields:=[("profile",get "profile" d);("reasoning",get "reasoning" d);("message",content(read_text "message" d)(attachments d));("settings",settings d)]in
    match selected_workspace d with
    |ManagedWorkspace WorkspaceBackend.TencentCvm=>record "create_workspace_task"
      (present "work_id"(optional_id work)(("backend",JString(WorkspaceBackend.name WorkspaceBackend.TencentCvm))::fields))
    |selection=>match work with
      |Some w=>record "create_work_task"(("work_id",number w)::("create_worktree",JBool(local_worktree d))::fields)
      |None=>record(match selection with CurrentWorkspace=>"create"|ManagedWorkspace _=>"create_worktree_task"end)fields end end
  | Message task=>message_command task d
  | Project id=>record(match id with None=>"create_project"|Some _=>"update_project"end)
      (present "project_id"(optional_id id)[("name",get "name" d);("workspace",workspace d);("create_worktree",get "create_worktree" d)])
  | Card id=>record(match id with None=>"create_card"|Some _=>"update_card"end)
      (present "card_id"(optional_id id)(("attachments",JArray(map encode_attachment(attachments d)))::filter(fun p=>negb(existsb(String.eqb(fst p))(match id with None=>["keep_open";"revision"]|Some _=>["keep_open";"assisted";"draft_profile"]end)))fs))
  | Agent id=>record "save_board_agent"(("agent",JString(match id with None=>""|Some id=>show_natural id end))::[("revision",get "revision" d);("name",get "name" d);("instructions",get "instructions" d);("profile",get "profile" d);("reasoning",get "reasoning" d);("concurrency",get "concurrency" d);("settings",settings d)])
  | Fork task=>record "fork"[("task_id",number task);("child_count",get "child_count" d);("messages",JArray(map(fun j=>content(value_or ""(as_string j))[])(read_list "messages" d)));("settings",settings d)]
  | Compact task=>record "compact"(present "summary"(get "summary" d)[("task_id",number task)])
  | TaskGraph id work=>record(match id with None=>"create_task_graph"|Some _=>"update_task_graph"end)
      (present "graph_id"(optional_id id)(match id with None=>present "work_id"(optional_id work)(object_fields(get "declaration" d))|Some _=>object_fields(get "declaration" d)end))
  | WorkName work=>record "rename_work"[("work_id",number work);("name",get "name" d)]
  | TitlePrompts=>record "configure_title_settings"fs
  end.
Definition execution_command task d:=JObject[("op",JString "configure_task_execution");("task_id",number task);
 ("profile",get "profile" d);("reasoning",get "reasoning" d);
 ("sandbox",JObject[("mode",get "sandbox" d);("network_access",get "network_access" d)]);
 ("approval",JObject(present "reviewer_profile"(get "reviewer_profile" d)[("mode",get "approval" d)]))].
Definition has_message d := negb(String.eqb(trim(read_text "message" d))"") || negb(Nat.eqb(List.length(attachments d))0).
Definition intrinsic_obstruction d : option string :=
  match raw_fields d with (name,_)::_=>Some(String.append "Correct the value of " name)|[]=>
  match owner d with
  | NewTask _=>if has_message d then if String.eqb(read_text "profile" d)"" then Some "Select a model"else None else Some "Enter a message or attach an image"
  | Message _=>if has_message d then None else Some "Enter a message or attach an image"
  | Project _=>if String.eqb(trim(read_text "name" d))"" then Some "Enter a project name"else None
  | Agent _=>if String.eqb(trim(read_text "name" d))"" then Some "Enter an agent name"else
      if String.eqb(read_text "profile" d)"" then Some "Select a model"else
      if match natural(get "concurrency" d)with Some n=>N.eqb n 0|None=>true end then Some "Concurrency must be positive"else None
  | Fork _=>if match natural(get "child_count" d)with Some n=>N.eqb n 0|None=>true end then Some "Choose at least one branch"else None
  | TaskGraph _ _=>if String.eqb(trim(text "name"(get "declaration" d)))"" then Some "Enter a graph name"else None
  | _=>None end end.
Definition encode_feedback f := match f with Editing=>JObject[("kind",JString "editing")]|Accepted r=>JObject[("kind",JString "accepted");("value",r)]|Rejected e=>JObject[("kind",JString "rejected");("error",JString e)]|WorkspaceRejected e=>JObject[("kind",JString "workspace_rejected");("error",JString e)]end.
Definition decode_feedback j := match string_field "kind" j with Some "editing"=>Some Editing|Some "accepted"=>option_map Accepted(field "value" j)|Some "rejected"=>option_map Rejected(string_field "error" j)|Some "workspace_rejected"=>option_map WorkspaceRejected(string_field "error" j)|_=>None end.
Definition encode_draft d := JObject[("editor",encode_editor(owner d));("revision",number(revision d));("values",data d);("attachments",JArray(map encode_attachment(attachments d)));("raw",JArray(map(fun p=>JObject[("field",JString(fst p));("value",JString(snd p))])(raw_fields d)));("feedback",encode_feedback(status d))].
Definition decode_draft j :=
  e<-bind(field "editor" j)decode_editor;;r<-natural_field "revision" j;;
  v<-bind(field "values" j)(Schema.decode(form_schema e));;a<-list_field decode_attachment "attachments" j;;raw<-list_field(fun p=>n<-string_field "field" p;;s<-string_field "value" p;;Some(n,s)) "raw" j;;f<-bind(field "feedback" j)decode_feedback;;Some(Draft e r v a raw f).

Theorem form_field_names_unique : forall e, unique_names(map field_name(form_schema e))=true.
Proof. intros e;destruct e;reflexivity. Qed.
Theorem successful_edit_advances_revision : forall name value d d',
  edit_field name value d=Some d' -> revision d'=N.succ(revision d) /\ owner d'=owner d.
Proof. intros. unfold edit_field,bind in H. destruct(update_field name value(values d));inversion H;subst;auto. Qed.

