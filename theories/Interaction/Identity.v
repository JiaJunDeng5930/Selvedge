From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

Inductive key:=Place(path:string)|Entity(owner:key)(kind identity:string)|Part(owner:key)(name:string).
Definition key_eq_dec :forall left right:key,{left=right}+{left<>right}.
Proof. decide equality;apply string_dec. Defined.
Definition same_key left right:=if key_eq_dec left right then true else false.
Fixpoint key_json value:=match value with
|Place path=>JArray[JString "place";JString path]
|Entity owner kind identity=>JArray[JString "entity";key_json owner;JString kind;JString identity]
|Part owner name=>JArray[JString "part";key_json owner;JString name]end.
Definition encode_key value:=TextJson.render_json(key_json value).
Definition key_part(parent name:string):=encode_key(Part(Place parent)name).

Inductive editor :=
| NewTask (work : option N) | Message (task : N) | Project (id : option N)
| Card (id : option N) | Agent (id : option N) | Fork (task : N)
| Compact (task : N) | TaskGraph (id work : option N)
| WorkName (work : N) | TitlePrompts.

Definition editor_task (e:editor) : option N := match e with
 |Message task|Fork task|Compact task=>Some task|_=>None end.
Definition task_observation_fields e fields := match editor_task e with
 |Some task=>("task_id",JNumber(show_natural task))::fields|None=>fields end.

Definition optional_id (id : option N) : json :=
  match id with None => JNull | Some id => JNumber (show_natural id) end.
Definition encode_editor (e : editor) : json :=
  let record kind id work := JObject [("kind",JString kind);("id",optional_id id);("work",optional_id work)] in
  match e with
  | NewTask w => record "new_task" None w | Message t => record "message" (Some t) None
  | Project i => record "project" i None | Card i => record "card" i None
  | Agent i => record "agent" i None | Fork t => record "fork" (Some t) None
  | Compact t => record "compact" (Some t) None | TaskGraph i w => record "graph" i w
  | WorkName w => record "work" (Some w) None | TitlePrompts => record "title_prompts" None None
  end.
Definition decode_id (j : json) : option (option N) :=
  match j with JNull => Some None | JNumber n => option_map (@Some N) (parse_natural n) | _ => None end.
Definition id_field name j := match field name j with Some v => decode_id v | None => Some None end.
Definition decode_editor (j : json) : option editor :=
  match string_field "kind" j, id_field "id" j, id_field "work" j with
  | Some "new_task", Some None, Some w => Some (NewTask w)
  | Some "message", Some (Some t), Some None => Some (Message t)
  | Some "project", Some i, Some None => Some (Project i)
  | Some "card", Some i, Some None => Some (Card i)
  | Some "agent", Some i, Some None => Some (Agent i)
  | Some "fork", Some (Some t), Some None => Some (Fork t)
  | Some "compact", Some (Some t), Some None => Some (Compact t)
  | Some "graph", Some i, Some w => Some (TaskGraph i w)
  | Some "work", Some (Some w), Some None => Some (WorkName w)
  | Some "title_prompts", Some None, Some None => Some TitlePrompts
  | _,_,_ => None
  end.
Definition editor_eq_dec : forall (a b : editor), {a = b} + {a <> b}.
Proof. repeat decide equality. Defined.
Definition same_editor (a b : editor) : bool := if editor_eq_dec a b then true else false.
Definition id_text id := match id with None => "new" | Some n => show_natural n end.
Definition editor_key (e : editor) : string :=
  match e with
  | NewTask w => "new-task/" ++ id_text w | Message t => "message/" ++ show_natural t
  | Project i => "project/" ++ id_text i | Card i => "card/" ++ id_text i
  | Agent i => "agent/" ++ id_text i | Fork t => "fork/" ++ show_natural t
  | Compact t => "compact/" ++ show_natural t
  | TaskGraph i w => "graph/" ++ id_text i ++ "/work/" ++ id_text w
  | WorkName w => "work/" ++ show_natural w | TitlePrompts => "title-prompts"
  end.
Inductive task_view := PrimaryTask(task:N)|SideTask(task:N).
Definition task_view_task view := match view with PrimaryTask task|SideTask task=>task end.
Definition task_view_scope view := match view with
 |PrimaryTask task=>"main-task/"++show_natural task|SideTask task=>"side-task/"++show_natural task end.

Definition task_view_key view logical := key_part(task_view_scope view)logical.

Inductive menu_subject := TaskActions(task:N)|ProjectActions(project:N)|CardActions(card:N)|AgentActions(agent:N)|GraphActions(graph:N).
Definition menu_identity subject := match subject with
 |TaskActions id=>("task",id)|ProjectActions id=>("project",id)|CardActions id=>("card",id)|AgentActions id=>("agent",id)|GraphActions id=>("graph",id)end.
Definition menu_key subject := let '(kind,id):=menu_identity subject in "actions/"++kind++"/"++show_natural id.
Definition encode_menu_subject subject := let '(kind,id):=menu_identity subject in
 JObject[("kind",JString kind);("id",number id)].
Definition decode_menu_subject value := id<-natural_field "id" value;;match string_field "kind" value with
 |Some "task"=>Some(TaskActions id)|Some "project"=>Some(ProjectActions id)
 |Some "card"=>Some(CardActions id)|Some "agent"=>Some(AgentActions id)|Some "graph"=>Some(GraphActions id)|_=>None end.

Inductive navigation_panel := GlobalMenu | WorkOverview | TasksDrawer.
Definition navigation_panel_name value := match value with GlobalMenu => "global" | WorkOverview => "works" | TasksDrawer => "tasks" end.
Definition decode_navigation_panel name := match name with "global" => Some GlobalMenu | "works" => Some WorkOverview | "tasks" => Some TasksDrawer | _ => None end.

Inductive route := Start | Conversation (task : N) | Projects | ProjectHome (id:N)
| Board | Agents | Graphs | HistorySearch | SharedUI (work:N) (task:option N).
Definition encode_route r :=
  let pair name id := JObject [("kind",JString name);("id",optional_id id)] in
  match r with
  | Start => pair "start" None | Conversation id => pair "conversation" (Some id)
  | Projects => pair "projects" None | ProjectHome id => pair "project" (Some id)
  | Board => pair "board" None | Agents => pair "agents" None | Graphs => pair "graphs" None
  | HistorySearch => pair "search" None
  | SharedUI w t => JObject [("kind",JString "shared_ui");("id",optional_id (Some w));("task",optional_id t)]
  end.
Definition decode_route j :=
  match string_field "kind" j, id_field "id" j with
  | Some "start",Some None => Some Start | Some "conversation",Some (Some t) => Some (Conversation t)
  | Some "projects",Some None => Some Projects | Some "project",Some (Some t) => Some (ProjectHome t)
  | Some "board",Some None => Some Board | Some "agents",Some None => Some Agents
  | Some "graphs",Some None => Some Graphs | Some "search",Some None => Some HistorySearch
  | Some "shared_ui",Some (Some w) => option_map (SharedUI w) (id_field "task" j)
  | _,_ => None
  end.

Definition history_key(task index:N):string :=
  "task/"++show_natural task++"/history/"++show_natural index.
Definition fence_key(document_key:string)(ordinal:N):string :=
  document_key++"/code/"++show_natural ordinal.
Definition fence_target(document_key:string)(ordinal:N):string :=
  fence_key document_key ordinal++"/ui".
Definition work_ui_target(work:N):string := "work/"++show_natural work++"/shared-ui".

Definition work_key (work:option N):string := "work/" ++ match work with None=>"all"|Some id=>show_natural id end.

Definition message_key(view:task_view):string:=key_part(task_view_key view(editor_key(Message(task_view_task view))))"message".
