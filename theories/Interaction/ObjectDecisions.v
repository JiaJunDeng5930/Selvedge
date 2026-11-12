From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Generated Require Commands.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction.Experience Require Read.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Record decision := Decision {
 decision_key : string;
 decision_label : string;
 decision_proposal : G.proposal;
 decision_confirmation : option string
}.
Definition immediate key label proposal := Decision key label proposal None.
Definition confirmed key label proposal := Decision key label proposal (Some label).
Definition present {A} (value:option A) := match value with Some _=>true|None=>false end.
Definition subject_exists snapshot subject := match subject with
|TaskActions id=>present(Read.find_task id snapshot)
|ProjectActions id=>present(Read.find_project id snapshot)
|GraphActions id=>present(Read.find_graph id snapshot)
|CardActions id=>present(Read.find_card id snapshot) end.

Definition task_decisions task := [
 immediate "interrupt" "停止当前执行" (G.Cmd_interrupt(G.Build_interrupt task));
 immediate "freeze" "暂停对话" (G.Cmd_freeze(G.Build_freeze task));
 immediate "unfreeze" "恢复对话" (G.Cmd_unfreeze(G.Build_unfreeze task));
 immediate "stop" "工具完成后停止" (G.Cmd_stop(G.Build_stop task));
 immediate "archive" "归档对话" (G.Cmd_archive(G.Build_archive task))].
Definition card_decisions snapshot clock (card:Read.card) :=
 match clock with None=>[] | Some now=>
  let id:=Read.card_id card in
  let revision:=Read.card_revision card in
  let observed:=Some(show_natural now) in
  [immediate "run" "启动对话" (G.Cmd_run_card(G.Build_run_card id revision observed));
   if Read.card_archived card
    then immediate "archive" "恢复卡片" (G.Cmd_restore_card(G.Build_restore_card id revision observed))
    else immediate "archive" "归档卡片" (G.Cmd_archive_card(G.Build_archive_card id revision observed));
   immediate "pin" (if Read.card_pinned card then "取消置顶" else "置顶卡片")
     (G.Cmd_pin_card(G.Build_pin_card id revision observed(Some(negb(Read.card_pinned card)))));
   confirmed "delete" "删除卡片" (G.Cmd_delete_card(G.Build_delete_card id revision observed));
   immediate "regenerate" "重新生成标题" (G.Cmd_regenerate_card_title
     (G.Build_regenerate_card_title id revision observed (option_map Read.board_draft_profile(Read.board_configuration snapshot))))]
 end.
Definition decisions snapshot clock subject :=
 if subject_exists snapshot subject then match subject with
 |TaskActions id=>task_decisions id
 |ProjectActions id=>[confirmed "delete" "删除项目" (G.Cmd_delete_project(G.Build_delete_project id))]
 |CardActions id=>match Read.find_card id snapshot with
  |Some card=>card_decisions snapshot clock card|None=>[] end
 |GraphActions id=>[confirmed "delete" "Delete task graph" (G.Cmd_delete_task_graph(G.Build_delete_task_graph id))]
 end else [].

Definition return_decision snapshot task :=
 parent<-Read.task_side_parent snapshot task;;
 Some(immediate "return" ("追加回 task #"++show_natural parent)%string
   (G.Cmd_return_side_conversation(G.Build_return_side_conversation task))).
Definition approval_decision task operation (allow:bool) :=
 let decision : denote(KEnum "allow" ["deny"]) := if allow then exist _ "allow"(or_introl eq_refl)
  else exist _ "deny"(or_intror(or_introl eq_refl)) in
 immediate ((if allow then "approve/" else "deny/")++show_natural operation)%string
   (if allow then "Approve once" else "Deny")
   (G.Cmd_review_approval(G.Build_review_approval task operation decision None)).
Definition cancellation_decision task operation :=
 immediate ("cancel/"++show_natural operation)%string "Cancel tool call"
   (G.Cmd_cancel_operation(G.Build_cancel_operation task operation)).
Definition worktree_retry_decision snapshot task :=
 value<-Read.task_workspace task snapshot;;
 if String.eqb(Read.worktree_status value)"archive_failed" then
 Some(immediate "worktree/retry-archive" "Retry archive"
   (G.Cmd_retry_worktree_archive(G.Build_retry_worktree_archive task))) else None.
Definition operation_decisions snapshot task :=
 let operations := value_or [] (Read.task_operations task snapshot) in
 flat_map (fun operation=>if Read.operation_human operation then
    let id:=Read.operation_id operation in [approval_decision task id true;approval_decision task id false]
    else []) operations ++
 map (fun operation=>cancellation_decision task (Read.operation_id operation)) operations.

Definition reading_decisions snapshot task :=
 let entries value := match value with Some decision=>[decision]|None=>[] end in
 operation_decisions snapshot task ++
 entries (return_decision snapshot task) ++ entries (worktree_retry_decision snapshot task).

Definition subjects snapshot :=
 map (fun task=>TaskActions(Read.task_id task)) (value_or [] (Read.tasks snapshot)) ++
 map (fun project=>ProjectActions(Read.project_id project)) (value_or [] (Read.projects snapshot)) ++
 map (fun graph=>GraphActions(Read.graph_id graph)) (value_or [] (Read.graphs snapshot)) ++
 map (fun card=>CardActions(Read.card_id card)) (value_or [] (Read.board_cards snapshot)).
