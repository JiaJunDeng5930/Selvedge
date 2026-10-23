From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction.Interactive Require Import Decimal Syntax Local Types.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Inductive action:=Assign(target:string)(value:json)|ResetAll|Draft(text:string)|Submit(message:string)|Copy(text:string)|Navigate(url:string).
Inductive transaction:=Waiting(ticket occurrence:N)(action:action)|CopyingDefinition(ticket:N)|Answered(ticket:N)(success:bool)(message:string).
Record feedback:=FeedbackEntry{feedback_path:string;feedback_transaction:transaction}.
Inductive view_state:=SourceView(open:bool)|GraphView(zoom pan_x pan_y:Decimal.decimal)(fit:bool)(selected:string)|TableView(sort_field:option string)(descending:bool)(page:nat).
Definition default_graph:=GraphView Decimal.one Decimal.zero Decimal.zero false "".
Definition default_table:=TableView None false 0.
Inductive restoration:=Unrequested|LoadingSnapshot(request_revision:N)|RestorationSettled.
Record block:=Block{
 block_owner:owner;source:string;syntax:Syntax.syntax;block_ending:ending;fence_closed:bool;external:bool;
 locals:list local;sources:list(string*json);views:list(string*view_state);mounts:list(string*N);feedbacks:list feedback;
 revision:N;next_ticket:N;next_occurrence:N;edited:bool;restore_state:restoration;storage_notice:option string }.
Definition initial_block who source ending closed external:=
 Block who source Syntax.empty ending closed external [][][][][] 0 0 0 false Unrequested None.
Definition owner_matches who block:=same_owner who block.(block_owner).
Definition find_block who blocks:=find(owner_matches who)blocks.
Definition replace_block next blocks:=map(fun old=>if String.eqb next.(block_owner).(owner_key)old.(block_owner).(owner_key)then next else old)blocks.
Definition with_locals value b := set locals (fun _=>value) b.
Definition with_sources value b := set sources (fun _=>value) b.
Definition with_views value b := set views (fun _=>value) b.
Definition with_feedbacks value b := set feedbacks (fun _=>value) b.
Definition with_mounts value next b := set next_occurrence (fun _=>next) (set mounts (fun _=>value) b).
Definition with_syntax value b := set syntax (fun _=>value) b.
Definition with_external value b := set external (fun _=>value) b.
Definition with_restoration value b := set restore_state (fun _=>value) b.
Definition with_notice value b := set storage_notice (fun _=>value) b.
Definition changed user_edit b := set edited (fun old=>user_edit||old) (set revision N.succ b).
Definition set_source value parsed ending closed allowed b :=
 set source (fun _=>value) (set syntax (fun _=>parsed) (set block_ending (fun _=>ending)
 (set fence_closed (fun _=>closed) (set external (fun _=>allowed) (set revision N.succ b))))).
Definition take_ticket b := (b.(next_ticket),set next_ticket N.succ b).
Definition feedback_at path b:=find(fun f=>String.eqb path f.(feedback_path))b.(feedbacks).
Definition set_feedback path value b:=with_feedbacks
 (FeedbackEntry path value::filter(fun f=>negb(String.eqb path f.(feedback_path)))b.(feedbacks))b.
Definition pending path b:=match feedback_at path b with
 |Some(FeedbackEntry _ (Waiting ticket _ _))|Some(FeedbackEntry _ (CopyingDefinition ticket))=>Some ticket|_=>None end.
Definition same_action a b:=match a,b with
 |Assign a v,Assign b w=>String.eqb a b&&Json.equal v w|ResetAll,ResetAll=>true
 |Draft a,Draft b|Submit a,Submit b|Copy a,Copy b|Navigate a,Navigate b=>String.eqb a b|_,_=>false end.
Definition duplicate_pending action b:=existsb(fun f=>match f.(feedback_transaction)with
 |Waiting _ _ current=>same_action action current
 |CopyingDefinition _=>same_action action(Copy b.(source))|_=>false end)b.(feedbacks).
Definition view_at path (graph:bool) b:=match find(fun kv=>String.eqb path(fst kv))b.(views)with
 |Some(_,v)=>v|None=>if graph then default_graph else default_table end.
Definition set_view path value b:=with_views((path,value)::filter(fun kv=>negb(String.eqb path(fst kv)))b.(views))b.
Record state:=State{blocks:list block}.
Definition initial:=State[].
Record decision:=Decision{next_state:state;effects:list effect}.
