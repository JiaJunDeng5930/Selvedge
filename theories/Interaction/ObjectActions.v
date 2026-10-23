From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Generated Require Commands.
From Selvedge.Features Require Domain.
From Selvedge.Interaction Require Import Codec Identity Resource Services DocumentState.
From Selvedge.Interaction Require CommandAssessment.
From Selvedge.Interaction.Session Require State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Inductive operation := NativeCommand(command:State.public_command)
| Destination(target:route) | Editor(owner:editor) | SideConversation(task:N).
Inductive status := Available | Awaiting | Unavailable(reason:string) | AssessmentFailed(reason:string).
Record action := Action {
 action_key:string; action_label:string; action_operation:operation;
 action_confirmation:option(string*route); action_status:status
}.
Definition command value := match action_operation value with
|NativeCommand command=>Some command
|SideConversation task=>decode_command command_specs(G.encode(G.Cmd_open_side_conversation(G.Build_open_side_conversation task None None)))
|_=>None end.
Definition local key label operation := Action key label operation None Available.
Definition native key label confirmation generated :=
 option_map(fun command=>Action key label(NativeCommand command)confirmation Awaiting)
  (decode_command command_specs(G.encode generated)).
Definition singleton {A} (value:option A) := match value with Some value=>[value]|None=>[]end.
Definition subject_value snapshot subject :=match subject with
|TaskActions id=>DocumentState.find_task id snapshot
|ProjectActions id=>DocumentState.find_world "projects" "project_id" id snapshot
|GraphActions id=>DocumentState.find_world "graphs" "graph_id" id snapshot
|CardActions id=>board<-field "board" snapshot;;DocumentState.find_world "cards" "card_id" id board
|AgentActions id=>board<-field "board" snapshot;;DocumentState.find_world "agents" "agent_id" id board end.
Definition task_actions id :=
 flat_map(fun '(key,label,command)=>singleton(native key label None command))[
  ("interrupt","Interrupt",G.Cmd_interrupt(G.Build_interrupt id));
  ("freeze","Freeze",G.Cmd_freeze(G.Build_freeze id));
  ("unfreeze","Resume",G.Cmd_unfreeze(G.Build_unfreeze id));
  ("stop","Stop",G.Cmd_stop(G.Build_stop id));
  ("archive","Archive",G.Cmd_archive(G.Build_archive id))] ++
 [local "side" "Side conversation"(SideConversation id);
  local "fork" "Fork"(Editor(Fork id));local "compact" "Compact"(Editor(Compact id))].
Definition card_actions snapshot clock id value :=
 match natural_field "revision" value,clock with
 |Some revision,Some now=>
  let observed:=Some(show_natural now)in
  let generated:=
   [("run","Run",G.Cmd_run_card(G.Build_run_card id revision observed),None);
    ("archive",(if flag "archived" value then "Restore"else"Archive"),
      (if flag "archived" value then G.Cmd_restore_card(G.Build_restore_card id revision observed)
       else G.Cmd_archive_card(G.Build_archive_card id revision observed)),None);
    ("pin",(if flag "pinned" value then "Unpin"else"Pin"),
      G.Cmd_pin_card(G.Build_pin_card id revision observed(Some(negb(flag "pinned" value)))),None);
    ("delete","Delete",G.Cmd_delete_card(G.Build_delete_card id revision observed),Some("Delete card",Board));
    ("regenerate","Regenerate title",G.Cmd_regenerate_card_title(G.Build_regenerate_card_title id revision observed
       (bind(field "board" snapshot)(string_field "draft_profile"))),None)]in
  flat_map(fun '(key,label,command,confirmation)=>singleton(native key label confirmation command))generated ++
  flat_map(fun stage=>singleton(native("move/"++stage)("Move to "++stage)None
   (G.Cmd_move_card(G.Build_move_card id revision observed(Some stage)(Some "")))))
   (map Selvedge.Features.Domain.stage_name Selvedge.Features.Domain.stages) ++
  flat_map(fun target=>match natural_field "card_id" target with
   |Some target_id=>if negb(flag "archived" target)&&negb(N.eqb id target_id)then
     singleton(native("before/"++show_natural target_id)("Move before "++text "title" target)None
       (G.Cmd_move_card(G.Build_move_card id revision observed(Some(text "status" target))(Some(show_natural target_id)))))
    else[]|None=>[]end)(match field "board" snapshot with Some board=>items "cards" board|None=>[]end) ++
  flat_map(fun task=>match natural_field "id" task with
   |Some task_id=>singleton(native("link/"++show_natural task_id)("Link "++text "title" task)None
      (G.Cmd_link_card(G.Build_link_card id revision observed(Some task_id))))
   |None=>[]end)(Codec.items "tasks" snapshot)
 |_,_=>[]end.
Definition declarations snapshot clock subject :=match subject_value snapshot subject with
|None=>[]
|Some value=>match subject with
 |TaskActions id=>task_actions id
 |ProjectActions id=>[local "details" "Project details"(Destination(ProjectHome id));
    local "edit" "Edit project"(Editor(Project(Some id)))] ++
    singleton(native "delete" "Delete project"(Some("Delete project",Projects))(G.Cmd_delete_project(G.Build_delete_project id)))
 |CardActions id=>local "edit" "Edit card"(Editor(Card(Some id)))::card_actions snapshot clock id value
 |AgentActions id=>[local "edit" "Edit agent"(Editor(Agent(Some id)))] ++
    match natural_field "revision" value with Some revision=>singleton(native "delete" "Delete agent"None
     (G.Cmd_delete_board_agent(G.Build_delete_board_agent id revision)))|None=>[]end
 |GraphActions id=>[local "edit" "Edit task graph"(Editor(graph_editor(Some id)None))] ++
    singleton(native "delete" "Delete task graph"(Some("Delete task graph",Graphs))(G.Cmd_delete_task_graph(G.Build_delete_task_graph id)))
 end end.
Definition occurrence s := match State.layers(State.navigation_state s)with
|layer::_=>State.layer_occurrence layer|[]=>State.generation(State.navigation_state s)end.
Definition assessment_revision s := State.generation(State.navigation_state s).
Definition action_owner subject value := CommandAssessment.MenuOwner subject(action_key value).
Definition assessment_for subject value s := find(Services.owned_assessment(action_owner subject value))
 (Services.command_assessments(State.service_state s)).
Definition availability snapshot s subject value :=match command value with
|None=>Available
|Some command=>if negb(Services.connected(State.service_state s))then Unavailable "Connect to continue"else
 match natural_field "sequence" snapshot,assessment_for subject value s with
 |Some sequence,Some(Loaded _ request observation)=>
   if CommandAssessment.matches(action_owner subject value)(assessment_revision s)sequence command request &&
      CommandAssessment.current_owned(action_owner subject value)(assessment_revision s)sequence observation
   then match CommandAssessment.observed_admission observation with
    |CommandAssessment.Admitted=>Available|CommandAssessment.Refused _ reason=>Unavailable reason end
   else Awaiting
 |Some sequence,Some(Failed _ request reason)=>
   if CommandAssessment.matches(action_owner subject value)(assessment_revision s)sequence command request
   then AssessmentFailed reason else Awaiting
 |_,_=>Awaiting end end.
Definition observe snapshot s subject value :=Action(action_key value)(action_label value)(action_operation value)
 (action_confirmation value)(availability snapshot s subject value).
Definition items snapshot s subject :=map(observe snapshot s subject)(declarations snapshot(State.now s)subject).
Definition resolve snapshot s subject key :=find(fun value=>String.eqb key(action_key value))(items snapshot s subject).

Definition return_action snapshot state task :=
 value<-DocumentState.find_task task snapshot;;parent<-natural_field "side_parent" value;;
 action<-native "return" ("追加回 task #"++show_natural parent) None
  (G.Cmd_return_side_conversation(G.Build_return_side_conversation task));;
 Some(observe snapshot state(TaskActions task)action).
Definition approval_action snapshot state task operation (allow:bool) :=
 let decision : denote(KEnum "allow" ["deny"]) := if allow then exist _ "allow"(or_introl eq_refl)
  else exist _ "deny"(or_intror(or_introl eq_refl))in
 action<-native ((if allow then"approve/"else"deny/")++show_natural operation)
  (if allow then"Approve once"else"Deny")None
  (G.Cmd_review_approval(G.Build_review_approval task operation decision None));;
 Some(observe snapshot state(TaskActions task)action).
Definition approval_actions snapshot state task :=match DocumentState.find_task task snapshot with
|None=>[]|Some value=>flat_map(fun operation=>match natural_field "operation_id" operation with
 |Some id=>if flag "awaitingHuman" operation then
   singleton(approval_action snapshot state task id true)++singleton(approval_action snapshot state task id false)
  else[]|None=>[]end)(Codec.items "operations" value)end.
Definition cancellation_action snapshot state task id :=
 action<-native("cancel/"++show_natural id)("Cancel operation #"++show_natural id)None
  (G.Cmd_cancel_operation(G.Build_cancel_operation task id));;
 Some(observe snapshot state(TaskActions task)action).
Definition cancellation_actions snapshot state task :=match DocumentState.find_task task snapshot with
|None=>[]|Some value=>flat_map(fun operation=>match natural_field "operation_id" operation with
 |Some id=>singleton(cancellation_action snapshot state task id)|None=>[]end)(Codec.items "operations" value)end.
Definition worktree_retry_action snapshot state task :=
 value<-DocumentState.find_world "worktrees" "task_id" task snapshot;;
 if String.eqb(text "status" value)"archive_failed"then
 action<-native "worktree/retry-archive" "Retry archive" None
  (G.Cmd_retry_worktree_archive(G.Build_retry_worktree_archive task));;
 Some(observe snapshot state(TaskActions task)action)else None.
Definition reading_actions snapshot state task :=
 approval_actions snapshot state task++cancellation_actions snapshot state task++singleton(return_action snapshot state task)++singleton(worktree_retry_action snapshot state task).
Definition subject_entries snapshot :=
 flat_map(fun '(collection,field_name,construct)=>
  fold_right(fun item rest=>match natural_field field_name item with Some id=>construct id::rest|None=>rest end)[]
   (Codec.items collection snapshot))[("tasks","id",TaskActions);("projects","project_id",ProjectActions);("graphs","graph_id",GraphActions)]++
 match field "board" snapshot with
 |None=>[]|Some board=>flat_map(fun '(collection,field_name,construct)=>
  fold_right(fun item rest=>match natural_field field_name item with Some id=>construct id::rest|None=>rest end)[]
   (Codec.items collection board))[("cards","card_id",CardActions);("agents","agent_id",AgentActions)]end.
Definition descriptors snapshot state subject :=items snapshot state subject++
 match subject with TaskActions task=>reading_actions snapshot state task|_=>[]end.
Definition descriptor_for_command snapshot state (accepted:State.public_command) :=
 find(fun entry=>match command(snd entry)with
  |Some candidate=>Json.equal(encode_command candidate)(encode_command accepted)|None=>false end)
  (flat_map(fun subject=>map(fun action=>(subject,action))(descriptors snapshot state subject))(subject_entries snapshot)).
