From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Generated Require Commands.
From Selvedge.Features Require Domain.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Services.
From Selvedge.Interaction Require CommandAssessment CardDecisions ObjectDecisions.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Browser.Session Require State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.
Module Decisions := ObjectDecisions.

Inductive operation := NativeCommand(command:State.public_command)
| Destination(target:route) | Editor(owner:editor) | SideConversation(task:N)
| InspectCard(card:N).
Inductive status := Available | Awaiting | InFlight | Unavailable(reason:string) | AssessmentFailed(reason:string).
Record action := Action {
 action_key:string; action_label:string; action_operation:operation;
 action_confirmation:option(string*route); action_status:status
}.
Definition command value := match action_operation value with
|NativeCommand command=>Some command
|SideConversation task=>decode_command command_specs(G.encode(G.Cmd_open_side_conversation(G.Build_open_side_conversation task None None)))
|_=>None end.
Definition local key label operation := Action key label operation None Available.
Definition native key label confirmation (generated : G.proposal) :=
 option_map(fun command=>Action key label(NativeCommand command)confirmation Awaiting)
  (decode_command command_specs(G.encode generated)).
Definition singleton {A} (value:option A) := match value with Some value=>[value]|None=>[]end.
Definition confirmation_destination subject := match subject with
|ProjectActions _=>Projects |CardActions _=>Board |GraphActions _=>Graphs
|TaskActions task=>Conversation task end.
Definition from_decision subject value :=
 native (Decisions.decision_key value) (Decisions.decision_label value)
  (option_map (fun caption=>(caption,confirmation_destination subject))(Decisions.decision_confirmation value))
  (Decisions.decision_proposal value).
Definition add_to_board_key := "board/add".
Definition open_board_card_key := "board/card".
Definition menu_label subject := match subject with
 |TaskActions _=>"对话操作"|ProjectActions _=>"项目操作"
 |CardActions _=>"卡片操作"|GraphActions _=>"任务图操作" end.
Definition fork_label := "创建对话分支".
Definition task_fork_action task := local "fork" fork_label (Editor(Fork task)).
Definition task_board_action snapshot task :=
 match Read.board_cards snapshot with
 |None=>[]
 |Some cards=>match find(fun card=>Read.same_id (Read.card_task card) (Some task))cards with
  |Some card=>[local open_board_card_key "打开关联卡片" (InspectCard(Read.card_id card))]
  |None=>[local add_to_board_key "添加到看板" (Editor(CardForConversation task))] end
 end.
Definition declarations snapshot clock subject :=
 if Decisions.subject_exists snapshot subject then
 let commands := flat_map (fun value=>singleton(from_decision subject value))(Decisions.decisions snapshot clock subject) in
 match subject with
 |TaskActions id=>local "compact" "压缩上下文"(Editor(Compact id))::
  (commands++[local "side" "侧边对话"(SideConversation id)])
 |ProjectActions id=>local "edit" "编辑项目"(Editor(Project(Some id)))::commands
 |CardActions id=>local "edit" "编辑卡片"(Editor(Card(Some id)))::commands
 |GraphActions id=>local "edit" "Edit task graph"(Editor(graph_editor(Some id)None))::commands
 end else [].
Definition choice_key selected : string := match selected with
|CardDecisions.MoveTo(CardDecisions.EndOfStage stage)=>("move/"++Domain.stage_name stage)%string
|CardDecisions.MoveTo(CardDecisions.BeforeCard _ target _)=>("before/"++show_natural target)%string
|CardDecisions.LinkTo task=>("link/"++show_natural(CardDecisions.target_task task))%string end.
Definition choice_label selected : string := match selected with
|CardDecisions.MoveTo(CardDecisions.EndOfStage stage)=>("移至"++Domain.stage_label stage)%string
|CardDecisions.MoveTo(CardDecisions.BeforeCard _ _ title)=>("移到「"++title++"」之前")%string
|CardDecisions.LinkTo task=>CardDecisions.target_title task end.
Definition choice_caption snapshot selected :=
 let label:=choice_label selected in
 match selected with
 |CardDecisions.LinkTo task=>match Read.card_link_stage (CardDecisions.target_task task) snapshot with
  |Some stage=>(label++" · 预计进入 "++Domain.stage_label stage)%string|None=>label end
 |_=>label end.
Definition choice_declaration snapshot opportunity now selected :=
 native(choice_key selected)(choice_caption snapshot selected)None(CardDecisions.proposal opportunity now selected).
Definition find_choice snapshot clock card decision key :=
 opportunity<-CardDecisions.observe snapshot card;;
 now<-clock;;
 selected<-find(fun candidate=>String.eqb key(choice_key candidate))(CardDecisions.choices decision opportunity);;
 choice_declaration snapshot opportunity now selected.
Definition assessment_revision s := State.generation(State.navigation_state s).
Definition action_revision s subject := match State.layers(State.navigation_state s),subject with
|layer::_,CardActions card=>match State.layer_panel layer with
 |State.CardDecisionPanel source _=>if N.eqb source card then State.layer_occurrence layer else assessment_revision s
 |_=>assessment_revision s end
|_,_=>assessment_revision s end.
Definition action_owner subject value := CommandAssessment.ObjectActionOwner subject(action_key value).
Definition assessment_for subject value s := find(Services.owned_assessment(action_owner subject value))
 (Services.command_assessments(State.service_state s)).
Definition availability snapshot s subject value :=match command value with
|None=>Available
|Some command=>if State.pending_command command s then InFlight else if negb(Services.connected(State.service_state s))then Unavailable "Connect to continue"else
 match natural_field "sequence" snapshot,assessment_for subject value s with
 |Some sequence,Some(Loaded _ request observation)=>
   if CommandAssessment.matches(action_owner subject value)(action_revision s subject)sequence command request &&
      CommandAssessment.current_owned(action_owner subject value)(action_revision s subject)sequence observation
   then match CommandAssessment.observed_admission observation with
    |CommandAssessment.Admitted=>Available|CommandAssessment.Refused _ reason=>Unavailable reason end
   else Awaiting
 |Some sequence,Some(Failed _ request reason)=>
   if CommandAssessment.matches(action_owner subject value)(action_revision s subject)sequence command request
   then AssessmentFailed reason else Awaiting
 |_,_=>Awaiting end end.
Definition observe snapshot s subject value :=Action(action_key value)(action_label value)(action_operation value)
 (action_confirmation value)(availability snapshot s subject value).
Definition items snapshot s subject :=map(observe snapshot s subject)(declarations snapshot(State.now s)subject).
Definition task_menu_actions (task:Read.task) (actions:list action) :=
 filter (fun value=>match action_key value with
  |"interrupt"|"unfreeze"=>false
  |"freeze"=>String.eqb(Read.task_status task)"active"
  |"stop"=>String.eqb(Read.task_status task)"active" && Read.task_working task
  |"archive"=>negb(String.eqb(Read.task_status task)"archived")
  |_=>true end) actions.
Definition available_first (actions:list action) :=
 let '(available,unavailable):=partition
   (fun value=>match action_status value with
    |Unavailable _|AssessmentFailed _=>false|_=>true end) actions in
 available++unavailable.
Definition menu_items snapshot s subject :=
 let actions:=items snapshot s subject in
 match subject with
 |TaskActions id=>match Read.find_task id snapshot with
  |Some task=>available_first
    (map(observe snapshot s subject)(task_board_action snapshot id)++task_menu_actions task actions)
  |None=>[]end
 |CardActions _=>available_first actions
 |_=>actions end.
Definition active_decision s subject := match State.layers(State.navigation_state s),subject with
|layer::_,CardActions card=>match State.layer_panel layer with
 |State.CardDecisionPanel source decision=>if N.eqb source card then Some decision else None
 |_=>None end
|_,_=>None end.
Definition resolve snapshot s subject key :=
 let matching:=fun value=>String.eqb key(action_key value)in
 let declared:=if String.eqb key add_to_board_key || String.eqb key open_board_card_key then
  match subject with
  |TaskActions task=>if Decisions.subject_exists snapshot subject then find matching (task_board_action snapshot task) else None
  |_=>None end
 else match subject,active_decision s subject with
 |CardActions card,Some decision=>find_choice snapshot(State.now s)card decision key
 |_,_=>find matching (declarations snapshot(State.now s)subject)end in
 option_map(observe snapshot s subject)declared.

Definition observed_decision snapshot state task value :=
 option_map (observe snapshot state(TaskActions task)) (from_decision (TaskActions task) value).
Definition return_action snapshot state task :=
 bind (Decisions.return_decision snapshot task) (observed_decision snapshot state task).
Definition approval_action snapshot state task operation allow :=
 observed_decision snapshot state task (Decisions.approval_decision task operation allow).
Definition cancellation_action snapshot state task operation :=
 observed_decision snapshot state task (Decisions.cancellation_decision task operation).
Definition worktree_retry_action snapshot state task :=
 bind (Decisions.worktree_retry_decision snapshot task) (observed_decision snapshot state task).
Definition reading_actions snapshot state task :=
 flat_map (fun value=>singleton(observed_decision snapshot state task value))(Decisions.reading_decisions snapshot task).
Definition descriptors snapshot state subject :=items snapshot state subject++
 match subject with TaskActions task=>reading_actions snapshot state task|_=>[]end.
Definition descriptor_for_command snapshot state (accepted:State.public_command) :=
 find(fun entry=>match command(snd entry)with
  |Some candidate=>Json.equal(encode_command candidate)(encode_command accepted)|None=>false end)
  (flat_map(fun subject=>map(fun action=>(subject,action))(descriptors snapshot state subject))(Decisions.subjects snapshot)).
