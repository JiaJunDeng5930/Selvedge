From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Interaction Require Import Codec Origin Identity.
From Selvedge.Kernel Require Import Streams.
From Selvedge.Interaction.Interactive Require Types Bounds.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(** Logical generated-document lifetimes survive their physical viewers. A new
    execution namespace allocates new epochs instead of reviving old authority. *)
Record document_fence := DocumentFence { fence_ordinal:N; fence_code:string; fence_closed:bool }.
Record document_lifetime := DocumentLifetime {
 document_namespace:string; document_viewer:N; document_origin:Origin.output_origin;
 document_epoch:N; document_source:string; document_ending:Selvedge.Interaction.Interactive.Types.ending;
 document_archived:bool; document_revealed:bool; document_observed_prefix:nat; document_observations:list document_fence }.
Definition document_fences stamp := map fence_ordinal(document_observations stamp).
Definition document_identity stamp:=Origin.content_key(document_namespace stamp)(document_viewer stamp)(document_origin stamp).
Record retention := Retention { retention_namespace:string; retention_next_epoch:N; retention_documents:list document_lifetime; retention_discarded:list(N*N) }.

Definition initial_retention := Retention "" 1 [] [].

Definition encode_document_lifetime d:=JObject[
 ("key",JString(document_identity d));("viewer",number(document_viewer d));("origin",Origin.encode_origin(document_origin d));
 ("epoch",number(document_epoch d));("source",JString(document_source d));("ending",JString(Selvedge.Interaction.Interactive.Types.ending_name(document_ending d)));
 ("archived",JBool(document_archived d));("revealed",JBool(document_revealed d));("observed_prefix",number(N.of_nat(document_observed_prefix d)));
 ("fences",JArray(map(fun f=>JObject[("ordinal",number(fence_ordinal f));("code",JString(fence_code f));("closed",JBool(fence_closed f))])(document_observations d)))].

Definition decode_document_lifetime namespace j:=key<-string_field "key" j;;viewer<-natural_field "viewer" j;;origin<-bind(field "origin" j)Origin.decode_origin;;
 epoch<-natural_field "epoch" j;;source<-string_field "source" j;;ending<-bind(string_field "ending" j)Selvedge.Interaction.Interactive.Types.decode_ending;;
 archived<-bool_field "archived" j;;revealed<-bool_field "revealed" j;;observed<-natural_field "observed_prefix" j;;
 fences<-list_field(fun f=>ordinal<-natural_field "ordinal" f;;code<-string_field "code" f;;closed<-bool_field "closed" f;;Some(DocumentFence ordinal code closed))"fences" j;;
 let stamp:=DocumentLifetime namespace viewer origin epoch source ending archived revealed(N.to_nat observed)fences in
 (* DEFENSE: The public state carries a convenient derived key; it cannot
    override the namespace, viewer or provenance decoded for the document. *)
 if String.eqb key(document_identity stamp)then Some stamp else None.

Definition encode_retention r:=JObject[("namespace",JString(retention_namespace r));("next_epoch",number(retention_next_epoch r));("documents",JArray(map encode_document_lifetime(retention_documents r)));
 ("discarded",JArray(map(fun '(task,count)=>JArray[number task;number count])(retention_discarded r)))].

Definition valid_document_lifetime namespace next_epoch d:=
 Origin.interactive_origin(document_origin d)&&
 String.eqb namespace(document_namespace d)&&
 N.ltb(document_epoch d)next_epoch&&negb(N.eqb(document_epoch d)0)&&
 Nat.leb(document_observed_prefix d)(String.length(document_source d))&&
 Nat.leb(List.length(document_observations d))Bounds.interactive_fences_per_document&&
 Nat.eqb(List.length(nodup N.eq_dec(document_fences d)))(List.length(document_fences d))&&
 (negb(document_archived d)||match document_ending d with Selvedge.Interaction.Interactive.Types.Interrupted=>true|_=>false end).

Definition valid_retention r:=
 (Origin.valid_namespace(retention_namespace r)||
  (String.eqb(retention_namespace r)""&&match retention_documents r,retention_discarded r with [],[]=>true|_,_=>false end))&&
 negb(N.eqb(retention_next_epoch r)0)&&Schema.unique_names(map document_identity(retention_documents r))&&
 forallb(valid_document_lifetime(retention_namespace r)(retention_next_epoch r))(retention_documents r).

Definition decode_retention j:=namespace<-string_field "namespace" j;;next_epoch<-natural_field "next_epoch" j;;documents<-list_field(decode_document_lifetime namespace)"documents" j;;
 discarded<-list_field(fun j=>match j with JArray[a;b]=>a<-natural a;;b<-natural b;;Some(a,b)|_=>None end)"discarded" j;;
 let r:=Retention namespace next_epoch documents discarded in
 (* DEFENSE: Public calls decode client state; forged epochs, duplicate owners or
    prefixes beyond the actual source must not enter the lifetime allocator. *)
 if valid_retention r then Some r else None.

(** This is an assembled observation, never a second mutable application world.
    The application supplies only occurrences actually selected for publication. *)
Record shared_occurrence := SharedOccurrence {
 shared_work : N;
 shared_selected_task : option N
}.
Record context := DocumentContext {
 context_namespace : string;
 context_world : json;
 context_views : list Identity.task_view;
 context_shared : option shared_occurrence;
 context_work : option N;
 context_streams : Streams.state;
 context_connected : bool;
 context_revoked : bool
}.
Definition find_world collection identity value world :=
 find (fun item=>match natural_field identity item with Some found=>N.eqb value found|None=>false end)
   (items collection world).
Definition find_task task world := find_world "tasks" "id" task world.
Definition find_work work world := find_world "works" "work_id" work world.
Definition task_belongs work task world := match find_task task world with
 | None=>false
 | Some found=>match work with None=>true|Some work=>match natural_field "work_id" found with
     Some current=>N.eqb current work|None=>false end end end.
Definition visible_tasks observation :=
 fold_left (fun tasks view=>let task:=Identity.task_view_task view in
   if existsb (N.eqb task) tasks then tasks else tasks++[task]) (context_views observation) [].
Definition current_previews observation :=
 fold_right (fun entry rest=>let identity:=Streams.stream_identity entry in
   match find_task (Streams.stream_task identity) (context_world observation) with
   | None=>rest
   | Some task=>match field "model_pending" task with
     | None=>rest
     | Some pending=>match natural_field "ticket" pending,natural_field "operation_id" pending with
       | Some ticket,Some operation=>if N.eqb ticket (Streams.stream_ticket identity) then
           match Streams.cumulative (context_streams observation) (Streams.stream_task identity) ticket operation with
           | Some output=>output::rest|None=>rest end else rest
       | _,_=>rest end end end) [] (context_streams observation).
