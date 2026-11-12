From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

From Selvedge.Interaction Require Import Identity.

Inductive key:=Place(path:string)|Entity(owner:key)(kind identity:string)|Part(owner:key)(name:string).
Definition key_eq_dec :forall left right:key,{left=right}+{left<>right}.
Proof. decide equality;apply string_dec. Defined.
Definition same_key left right:=if key_eq_dec left right then true else false.
Definition key_payload(value:string):=show_natural(N.of_nat(String.length value))++":"++value.
(* An opaque parent is already encoded. Framing its bytes avoids repeatedly
   escaping the whole ancestor chain when nested surfaces allocate parts. *)
Fixpoint encode_key value:=match value with
|Place path=>"p"++key_payload path
|Entity owner kind identity=>"e"++encode_key owner++key_payload kind++key_payload identity
|Part owner name=>"r"++encode_key owner++key_payload name end.
Definition key_part(parent name:string):=encode_key(Part(Place parent)name).
Definition message_markdown_key key := String.append key "/markdown".

Definition editor_key (e : editor) : string :=
  match e with
  | NewTask w => "new-task/" ++ id_text w | Message t => "message/" ++ show_natural t
  | Project i => "project/" ++ id_text i | Card i => "card/" ++ id_text i
  | CardForConversation task => "conversation-card/" ++ show_natural task
  | Fork t => "fork/" ++ show_natural t
  | Compact t => "compact/" ++ show_natural t
  | TaskGraph i w => "graph/" ++ id_text i ++ "/work/" ++ id_text w
  | WorkName w => "work/" ++ show_natural w | TitlePrompts => "title-prompts"
  end.
Inductive task_view := PrimaryTask(task:N)|SideTask(task:N).
Definition task_view_task view := match view with PrimaryTask task|SideTask task=>task end.
Definition task_view_scope view := match view with
 |PrimaryTask task=>"main-task/"++show_natural task|SideTask task=>"side-task/"++show_natural task end.

Definition task_view_key view logical := key_part(task_view_scope view)logical.

Definition menu_key subject := let '(kind,id):=object_identity subject in "actions/"++kind++"/"++show_natural id.

Inductive navigation_panel := GlobalMenu | WorkOverview | TasksDrawer.
Definition navigation_panel_name value := match value with GlobalMenu => "global" | WorkOverview => "works" | TasksDrawer => "tasks" end.
Definition decode_navigation_panel name := match name with "global" => Some GlobalMenu | "works" => Some WorkOverview | "tasks" => Some TasksDrawer | _ => None end.

Inductive route := Start | GraphConversation (work : option N) (trigger : string)
| Conversation (task : N) | Projects | ProjectHome (id:N)
| Board | Graphs | HistorySearch | SharedUI (work:N) (task:option N).
Definition encode_route r :=
  let pair name id := JObject [("kind",JString name);("id",optional_id id)] in
  match r with
  | Start => pair "start" None
  | GraphConversation work trigger => JObject [("kind",JString "graph_conversation");
      ("id",optional_id work);("trigger",JString trigger)]
  | Conversation id => pair "conversation" (Some id)
  | Projects => pair "projects" None | ProjectHome id => pair "project" (Some id)
  | Board => pair "board" None | Graphs => pair "graphs" None
  | HistorySearch => pair "search" None
  | SharedUI w t => JObject [("kind",JString "shared_ui");("id",optional_id (Some w));("task",optional_id t)]
  end.
Definition decode_route j :=
  match string_field "kind" j, id_field "id" j with
  | Some "start",Some None => Some Start
  | Some "graph_conversation",Some work => option_map (GraphConversation work) (string_field "trigger" j)
  | Some "conversation",Some (Some t) => Some (Conversation t)
  | Some "projects",Some None => Some Projects | Some "project",Some (Some t) => Some (ProjectHome t)
  | Some "board",Some None => Some Board
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
