From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

Inductive title_prompt_scope := ConversationTitles | BoardTitles.

Inductive editor :=
| NewTask (work : option N) | Message (task : N) | Project (id : option N)
| Card (id : option N) | CardForConversation (task : N) | Fork (task : N)
| Compact (task : N) | TaskGraph (id work : option N)
| WorkName (work : option N) | TitlePrompts (scope : title_prompt_scope).

(* Existing graphs keep their editor when the surrounding Work selection changes. *)
Definition graph_editor id work := TaskGraph id (match id with Some _=>None|None=>work end).

Inductive card_subject := BoardCard (id : option N) | ConversationCard (task : N).
Definition card_editor subject := match subject with
|BoardCard id=>Card id|ConversationCard task=>CardForConversation task end.

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
  | CardForConversation task => record "conversation_card" (Some task) None
  | Fork t => record "fork" (Some t) None
  | Compact t => record "compact" (Some t) None | TaskGraph i w => record "graph" i w
  | WorkName w => record "work" w None
  | TitlePrompts ConversationTitles => record "title_prompts" None None
  | TitlePrompts BoardTitles => record "board_title_prompt" None None
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
  | Some "conversation_card", Some (Some task), Some None => Some (CardForConversation task)
  | Some "fork", Some (Some t), Some None => Some (Fork t)
  | Some "compact", Some (Some t), Some None => Some (Compact t)
  | Some "graph", Some i, Some w => Some (graph_editor i w)
  | Some "work", Some w, Some None => Some (WorkName w)
  | Some "title_prompts", Some None, Some None => Some (TitlePrompts ConversationTitles)
  | Some "board_title_prompt", Some None, Some None => Some (TitlePrompts BoardTitles)
  | _,_,_ => None
  end.
Definition editor_eq_dec : forall (a b : editor), {a = b} + {a <> b}.
Proof. repeat decide equality. Defined.
Definition same_editor (a b : editor) : bool := if editor_eq_dec a b then true else false.
Definition id_text id := match id with None => "new" | Some n => show_natural n end.
Inductive object_subject := TaskActions(task:N)|ProjectActions(project:N)|CardActions(card:N)|GraphActions(graph:N).
Definition object_identity subject := match subject with
 |TaskActions id=>("task",id)|ProjectActions id=>("project",id)|CardActions id=>("card",id)|GraphActions id=>("graph",id)end.
Definition encode_object_subject subject := let '(kind,id):=object_identity subject in
 JObject[("kind",JString kind);("id",number id)].
Definition decode_object_subject value := id<-natural_field "id" value;;match string_field "kind" value with
 |Some "task"=>Some(TaskActions id)|Some "project"=>Some(ProjectActions id)
 |Some "card"=>Some(CardActions id)|Some "graph"=>Some(GraphActions id)|_=>None end.
