From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction.Experience Require Read.
Open Scope string_scope.

Record history_hit := HistoryHit {
 hit_task : Read.task; hit_message : N;
 hit_before : string; hit_text : string; hit_after : string
}.
Definition observe_hit raw :=
 task<-bind(field "task" raw)Read.observe_task;;index<-natural_field "message_index" raw;;
 before<-string_field "before" raw;;snippet<-string_field "snippet" raw;;after<-string_field "after" raw;;
 Some(HistoryHit task index before snippet after).
Record history_page := HistoryPage { hits : list history_hit; page_after : N; next_after : option N }.
Definition observe_page raw :=
 entries<-list_field observe_hit "hits" raw;;after<-natural_field "after" raw;;
 next<-id_field "next_after" raw;;Some(HistoryPage entries after next).
Definition search_result reply : sum string history_page :=
 match field "result" reply with
 |Some raw=>match observe_page raw with
  |Some page=>inr page|None=>inl "Search results unavailable" end
 |None=>inl(diagnostic_message(command_failure(inr reply))) end.
