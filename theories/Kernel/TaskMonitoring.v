From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require KeyedScope.
From Selvedge.Kernel Require Import Domain State Conversation TaskWake.
From Selvedge.Features Require Import TaskMonitoringTypes.
From Selvedge.Programming Require Import DecisionComposition TaskChange TaskResult.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition subscriptions_in (value : world) :=
 Selvedge.Features.Domain.feature_task_monitoring (world_features value).
Definition with_subscriptions (subscriptions : registry) (value : world) :=
 with_features (set Selvedge.Features.Domain.feature_task_monitoring
  (fun _ => subscriptions) (world_features value)) value.

Definition task_observers (source : N) (subscriptions : registry) :=
 match KeyedScope.lookup source (KeyedScope.rows subscriptions) with
 | Some entry => monitoring_tasks entry
 | None => [] end.
Definition subscribe (observer source : N) (value : world) :=
 let subscriptions := subscriptions_in value in
 let observers := task_observers source subscriptions in
 if existsb (N.eqb observer) observers then value
 else with_subscriptions (KeyedScope.put source (Subscriptions source (observer :: observers)) subscriptions) value.
Definition remove_observer (observer source : N) (subscriptions : registry) :=
 let current := task_observers source subscriptions in
 if existsb (N.eqb observer) current then
  match filter (fun other => negb (N.eqb observer other)) current with
  | [] => KeyedScope.remove source subscriptions
  | kept => KeyedScope.put source (Subscriptions source kept) subscriptions end
 else subscriptions.
Definition archive (id : N) (value : world) :=
 let subscriptions := subscriptions_in value in
 with_subscriptions
  (fold_left (fun current entry => remove_observer id (monitored_task entry) current)
    (KeyedScope.members (observer_key id) subscriptions)
    (KeyedScope.remove id subscriptions)) value.

Definition monitor (observer : option N) (source : N) (value : world) :=
 match observer with
 | None => reject "task_required" "Only a task can monitor another task" value
 | Some id =>
   if N.eqb id source then reject "cannot_monitor_self" "A task cannot monitor itself" value else
   match find_task id value, find_task source value with
   | Some watcher, Some watched =>
     if task_archived watcher || task_archived watched then
      reject "task_archived" "Archived tasks cannot participate in monitoring" value
     else accept JNull (subscribe id source value) []
   | _, _ => reject "task_not_found" "The monitoring task or source does not exist" value
   end
 end.
Definition unmonitor (observer : option N) (source : N) (value : world) :=
 match observer with
 | None => reject "task_required" "Only a task can cancel its monitoring" value
 | Some id => accept JNull (with_subscriptions (remove_observer id source (subscriptions_in value)) value) []
 end.

Definition delivery_changes (outputs : list message) (task : task) :=
 WakeDemand (resume_for_input task ++ [TaskChange.AppendHistory outputs]).
Definition deliver (outputs : list message) (observer : N) (value : world) :=
 TaskResult.commit_result observer (delivery_changes outputs) value.
Definition monitored_message (source : N) (item : message) :=
 match assistant_output item with
 | Some (origin, text) =>
   match origin_assistant_phase origin with
   | Some _ => if N.eqb source (origin_producer origin) && negb (String.eqb text "")
               then Some (MonitoredOutput origin text) else None
   | None => None end
 | None => None end.
Definition after_model_output (before : world) (source : N) : DecisionComposition.step :=
 fun value _ =>
 match task_observers source (subscriptions_in value), find_task source value with
 | first :: rest, Some task =>
   let previous := match find_task source before with
    | Some task => List.length (task_history task)
    | None => 0%nat end in
   let outputs := fold_right (fun item kept =>
    match monitored_message source item with
    | Some output => output :: kept
    | None => kept end) [] (skipn previous (task_history task)) in
   match outputs with
   | [] => DecisionComposition.unchanged value
   | _ => DecisionComposition.unchanged
     (fold_left (fun next observer => deliver outputs observer next) (first :: rest) value)
   end
 | _, _ => DecisionComposition.unchanged value
 end.
