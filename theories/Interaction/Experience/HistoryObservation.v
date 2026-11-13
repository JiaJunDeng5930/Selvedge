From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Domain HistoryRole.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction.Experience Require Read.
Open Scope string_scope.

Record message_hit := MessageHit {
 hit_message : N;
 hit_speaker : Domain.speaker;
 hit_preview : option string
}.
Inductive history_hit := TitleMatch (task : Read.task) | MessageMatch (task : Read.task) (hit : message_hit).
Definition observe_speaker raw :=
 role<-string_field "role" raw;;
 match HistoryRole.parse role with
 |Some HistoryRole.User=>Some Domain.UserSpeaker
 |Some HistoryRole.Assistant=>Some Domain.AssistantSpeaker
 |_=>None end.
Definition observe_hit raw :=
 task<-bind(field "task" raw)Read.observe_task_summary;;
 match string_field "kind" raw with
 |Some "title"=>Some(TitleMatch task)
 |None=>index<-natural_field "message_index" raw;;speaker<-observe_speaker raw;;
 Some(MessageMatch task(MessageHit index speaker (string_field "preview" raw)))
 |_=>None end.
Record history_page := HistoryPage { hits : list history_hit; page_after : N; next_after : option N }.
Definition observe_page raw :=
 entries<-list_field observe_hit "hits" raw;;after<-natural_field "after" raw;;
 next<-id_field "next_after" raw;;Some(HistoryPage entries after next).
Definition search_result reply : sum string history_page :=
 match field "result" reply with
 |Some raw=>match observe_page raw with
  |Some page=>inr page|None=>inl "Search results unavailable" end
 |None=>inl(diagnostic_message(command_failure(inr reply))) end.
