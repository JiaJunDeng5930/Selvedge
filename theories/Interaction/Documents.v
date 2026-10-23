From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Kernel Require Import Conversation Streams OutputClassification.
From Selvedge.Interaction Require Import Codec Identity Origin CodeSource DocumentState DocumentPublication.
From Selvedge.Interaction.Interactive Require Import Types.
From Selvedge.Interaction.Interactive Require Bounds.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Record document := Document { viewer:N; provenance:output_origin; markdown:string; complete:bool }.
Definition key namespace doc := content_key namespace (viewer doc) (provenance doc).
Definition code_identity namespace doc ordinal := CodeSource.CodeIdentity
 (CodeSource.Generated namespace (viewer doc) (provenance doc) (complete doc)) ordinal.
Definition document_lifetimes := DocumentState.retention_documents.
Definition discarded_outputs := DocumentState.retention_discarded.
Definition with_document_lifetimes values r :=
 Retention (retention_namespace r) (retention_next_epoch r) values (retention_discarded r).

Definition history_document viewing message:option document:=
 if Conversation.json_message_assistant message then
  origin<-bind(field "origin" message)decode_origin;;body<-Conversation.json_message_text message;;
  if interactive_origin origin then Some(Document viewing origin body true)else None
 else None.

Definition history_documents viewing world:=
 match find_task viewing world with None=>[]|Some task=>
  fold_right(fun message rest=>match history_document viewing message with Some doc=>doc::rest|None=>rest end)[](items "history" task)end.

Definition live_documents viewing observation :=
 flat_map (fun output=>if N.eqb (Streams.output_task output) viewing then
   match find_task viewing (context_world observation) with
   | None=>[]
   | Some task=>match bind (field "model_pending" task) (fun pending=>bind (string_field "mode" pending) decode_mode) with
     | None|Some Plain=>[]
     | Some InteractiveV1=>map (fun '(part,text)=>Document viewing
         (OutputOrigin (Streams.output_task output) (Streams.output_operation output) part InteractiveV1) text false)
         (Streams.output_parts output) end end else []) (current_previews observation).
Definition documents_for viewing observation :=
 history_documents viewing (context_world observation) ++ live_documents viewing observation.
Definition authoritative_documents observation :=
 if valid_namespace (context_namespace observation)
 then flat_map (fun viewing=>documents_for viewing observation) (visible_tasks observation) else [].
Definition stamp_in_namespace namespace stamp:=
 valid_namespace namespace&&interactive_origin(document_origin stamp)&&
 String.eqb(document_identity stamp)(content_key namespace(document_viewer stamp)(document_origin stamp)).

Definition stamp_is_current observation stamp :=
 existsb (fun doc=>String.eqb (key (context_namespace observation) doc) (document_identity stamp))
   (documents_for (document_viewer stamp) observation).
Definition retained_stamps observation r := filter (fun stamp=>
 stamp_in_namespace (context_namespace observation) stamp &&
 existsb (N.eqb (document_viewer stamp)) (visible_tasks observation) &&
 negb (stamp_is_current observation stamp) &&
 match document_ending stamp with Types.Complete=>false|_=>true end) (document_lifetimes r).
Definition visible_documents observation r := authoritative_documents observation ++
 map (fun stamp=>Document (document_viewer stamp) (document_origin stamp) (document_source stamp) false)
   (filter (fun stamp=>negb (document_archived stamp)) (retained_stamps observation r)).
Definition update_stamp source ending archived revealed observed fences stamp:=
 DocumentLifetime(document_namespace stamp)(document_viewer stamp)(document_origin stamp)(document_epoch stamp)
  source ending archived revealed observed fences.

Definition same_ending left right:=match left,right with
 |Types.Open,Types.Open|Types.Complete,Types.Complete|Types.Interrupted,Types.Interrupted=>true|_,_=>false end.

Definition continuous_document prior doc:=
 String.prefix(document_source prior)(markdown doc)&&
 (same_ending(document_ending prior)Types.Open||String.eqb(document_source prior)(markdown doc)).
Definition remember_document namespace doc s:=
 let identity:=key namespace doc in
 let prior:=find(fun stamp=>String.eqb identity(document_identity stamp))(document_lifetimes s)in
 let ending:=if complete doc then Types.Complete else Types.Open in
 let r:=s in
 let '(next_epoch,stamp):=match prior with
 |Some prior=>if continuous_document prior doc then
   (retention_next_epoch r,update_stamp(markdown doc)ending false false(document_observed_prefix prior)(document_observations prior)prior)
  else (N.succ(retention_next_epoch r),DocumentLifetime namespace(viewer doc)(provenance doc)(retention_next_epoch r)(markdown doc)ending false false 0[])
 |None=>(N.succ(retention_next_epoch r),DocumentLifetime namespace(viewer doc)(provenance doc)(retention_next_epoch r)(markdown doc)ending false false 0[])
 end in
 Retention namespace next_epoch (stamp::filter(fun old=>negb(String.eqb identity(document_identity old)))(document_lifetimes s)) (discarded_outputs s).
Definition pending_stamp world stamp:=
 let origin:=document_origin stamp in
 match find_task(producer origin)world with None=>false|Some task=>
  match field "model_pending" task with None=>false|Some pending=>
   match natural_field "operation_id" pending,bind(string_field "mode" pending)decode_mode with
   |Some operation,Some mode=>same_origin origin(OutputOrigin(producer origin)operation(part origin)mode)
   |_,_=>false end end end.

Definition mark_interrupted observation lagged stamp :=
 if same_ending (document_ending stamp) Types.Open && stamp_in_namespace (context_namespace observation) stamp &&
    context_connected observation && negb lagged && negb (stamp_is_current observation stamp) &&
    negb (pending_stamp (context_world observation) stamp) then
   update_stamp (document_source stamp) Types.Interrupted (document_archived stamp) (document_revealed stamp)
    (document_observed_prefix stamp) (document_observations stamp) stamp
 else stamp.
Definition count_for task counts:nat:=
 match find(fun entry=>N.eqb task(fst entry))counts with Some entry=>snd entry|None=>0 end.

Definition increment_count task counts:=
 (task,S(count_for task counts))::filter(fun entry=>negb(N.eqb task(fst entry)))counts.

Definition archive_stamp stamp:=update_stamp(document_source stamp)(document_ending stamp)true false
 (document_observed_prefix stamp)(document_observations stamp)stamp.

Fixpoint bound_interrupted stamps counts total:=match stamps with
 |[]=>[]|stamp::rest=>
  if same_ending(document_ending stamp)Types.Interrupted&&negb(document_archived stamp)then
   if Nat.ltb total Bounds.retained_per_session&&Nat.ltb(count_for(document_viewer stamp)counts)Bounds.retained_per_task
   then stamp::bound_interrupted rest(increment_count(document_viewer stamp)counts)(S total)
   else archive_stamp stamp::bound_interrupted rest counts total
  else stamp::bound_interrupted rest counts total end.

Definition newer_stamp left right:=
 N.ltb(operation(document_origin right))(operation(document_origin left))||
 (N.eqb(operation(document_origin right))(operation(document_origin left))&&N.ltb(part(document_origin right))(part(document_origin left))).

Fixpoint insert_newest stamp stamps:=match stamps with
 |[]=>[stamp]|old::rest=>if newer_stamp stamp old then stamp::stamps else old::insert_newest stamp rest end.

Definition newest stamps:=fold_right insert_newest[]stamps.

Definition retention_order stamps:=
 let '(retained,current):=partition(fun stamp=>same_ending(document_ending stamp)Types.Interrupted)stamps in
 current++newest retained.

Fixpoint trim_archives stamps (bytes:nat): list document_lifetime*list N:=match stamps with
 |[] => ([],[])|stamp::rest=>
  let size:=Utf8.byte_length(document_source stamp)in
  if document_archived stamp then
   if Nat.leb(Nat.add bytes size)Bounds.retained_source_bytes then
    let '(kept,discarded):=trim_archives rest(Nat.add bytes size)in(stamp::kept,discarded)
   else let '(kept,discarded):=trim_archives rest bytes in(kept,document_viewer stamp::discarded)
  else let '(kept,discarded):=trim_archives rest bytes in(stamp::kept,discarded)end.

Definition add_discarded task counts:=
 let previous:=match find(fun entry=>N.eqb task(fst entry))counts with Some entry=>snd entry|None=>0 end in
 (task,N.succ previous)::filter(fun entry=>negb(N.eqb task(fst entry)))counts.

Definition discarded_count task r:=
 match find(fun entry=>N.eqb task(fst entry))(discarded_outputs r)with
 |Some entry=>snd entry|None=>0 end.
Definition clear_discarded task r:=
 Retention (retention_namespace r) (retention_next_epoch r) (document_lifetimes r)
  (filter(fun entry=>negb(N.eqb task(fst entry)))(discarded_outputs r)).

Definition scoped_retention namespace world r :=
 if String.eqb namespace (retention_namespace r) then
   with_document_lifetimes (filter (fun stamp=>match find_task (document_viewer stamp) world with
     None=>false|Some _=>true end) (document_lifetimes r)) r
 else Retention namespace (retention_next_epoch r) [] [].
Definition synchronize_documents observation lagged r :=
 let namespace:=context_namespace observation in
 let r:=scoped_retention namespace (context_world observation) r in
 let viewers:=nodup N.eq_dec (visible_tasks observation ++ map document_viewer (document_lifetimes r) ++
   map Streams.output_task (current_previews observation)) in
 let docs:=if valid_namespace namespace then flat_map (fun viewing=>documents_for viewing observation) viewers else [] in
 let next:=fold_left (fun current doc=>remember_document namespace doc current) docs r in
 let ended:=map (mark_interrupted observation lagged) (document_lifetimes next) in
 let '(kept,discarded):=trim_archives (bound_interrupted (retention_order ended) [] 0) 0 in
 Retention namespace (retention_next_epoch next) kept
   (fold_left (fun counts task=>add_discarded task counts) discarded (discarded_outputs next)).
Definition document_stamp namespace doc s:=find(fun stamp=>String.eqb(key namespace doc)(document_identity stamp))(document_lifetimes s).

Definition eligible_fence namespace doc ordinal s:=match document_stamp namespace doc s with None=>false|Some stamp=>
 negb(document_archived stamp)&&(existsb(N.eqb ordinal)(document_fences stamp)||Nat.ltb(List.length(document_fences stamp))Bounds.interactive_fences_per_document)end.

Definition owner_ordinal namespace doc owner:=
 let prefix:=String.append(key namespace doc)"/fence/"in
 if String.prefix prefix(Types.owner_key owner)then
  let suffix:=substring(String.length prefix)(String.length(Types.owner_key owner))(Types.owner_key owner)in
  ordinal<-parse_natural suffix;;if String.eqb suffix(show_natural ordinal)then Some ordinal else None
 else None.

Definition document_key_matches namespace doc owner:=match owner_ordinal namespace doc owner with Some _=>true|None=>false end.

Definition document_owns namespace owner s doc:=
 match owner_ordinal namespace doc owner,document_stamp namespace doc s with
 |Some ordinal,Some stamp=>negb(document_archived stamp)&&N.eqb(Types.epoch owner)(document_epoch stamp)&&existsb(N.eqb ordinal)(document_fences stamp)
 |_,_=>false end.

Definition find_document observation owner r :=
 find (document_owns (context_namespace observation) owner r) (visible_documents observation r).
Definition shared_key namespace work:=(show_nat(String.length namespace)++":"++namespace++"/work/"++show_natural work)%string.

Definition shared_work observation owner := match context_shared observation with
 |None=>None
 |Some shared=>let namespace:=context_namespace observation in
   if valid_namespace namespace && String.eqb (Types.owner_key owner) (shared_key namespace (DocumentState.shared_work shared)) then
     match find_work (DocumentState.shared_work shared) (context_world observation) with
     |Some found=>match natural_field "revision" found with
       |Some revision=>if N.eqb (Types.epoch owner) revision then Some (DocumentState.shared_work shared) else None
       |None=>None end
     |None=>None end
   else None end.
Definition shared_task observation owner := work<-shared_work observation owner;;
 match context_shared observation with
 |Some shared=>task<-shared_selected_task shared;;
   if task_belongs (Some work) task (context_world observation) then Some task else None
 |None=>None end.
Definition owning_task observation owner r := match find_document observation owner r with
 |Some doc=>if interactive_origin (provenance doc) && complete doc && N.eqb (viewer doc) (producer (provenance doc))
   then Some (viewer doc) else None
 |None=>shared_task observation owner end.
Definition document_external observation doc :=
 valid_namespace (context_namespace observation) && complete doc &&
 external_allowed (context_connected observation) true (viewer doc) (provenance doc).
Definition externally_allowed observation owner r :=
 valid_namespace (context_namespace observation) && context_connected observation &&
 match find_document observation owner r with
 |Some doc=>document_external observation doc
 |None=>match shared_work observation owner with Some _=>true|None=>false end end.
(** A shared definition is identified by the selected work's actual revision;
    it is not a retained Markdown fence and owns no fabricated document stamp. *)
Definition shared_definition observation retained:option Types.input:=
 shared<-context_shared observation;;
 value<-find_work(DocumentState.shared_work shared)(context_world observation);;
 revision<-natural_field "revision" value;;source<-string_field "source" value;;
 let owner:=Types.Owner(shared_key(context_namespace observation)(DocumentState.shared_work shared))revision in
 if String.eqb source ""then None else
 match shared_work observation owner with
 |Some _=>Some(Types.SourceChanged owner source true Types.Complete(externally_allowed observation owner retained))
 |None=>None end.
Definition publication_identity observation owner r :=
 match find_document observation owner r with
 |Some doc=>ordinal<-owner_ordinal (context_namespace observation) doc owner;;
   Some (code_identity (context_namespace observation) doc ordinal)
 |None=>work<-shared_work observation owner;;
   Some (CodeSource.CodeIdentity (CodeSource.SharedDocument (context_namespace observation)
     (shared_key (context_namespace observation) work)) 0) end.
Definition portal_target observation owner r :=
 match find_document observation owner r with
 |Some doc=>ordinal<-owner_ordinal (context_namespace observation) doc owner;;
   Some (DocumentPublication.target_key (code_identity (context_namespace observation) doc ordinal) Preview)
 |None=>option_map work_ui_target (shared_work observation owner) end.
Definition portal_targets observation owner r :=
 match find_document observation owner r with
 |Some doc=>match owner_ordinal (context_namespace observation) doc owner with
   |Some ordinal=>map (fun view=>(task_view_scope view,
       DocumentPublication.target_key (code_identity (context_namespace observation) doc ordinal) Preview))
       (filter (fun view=>N.eqb (task_view_task view) (viewer doc)) (context_views observation))
   |None=>[] end
 |None=>match shared_work observation owner with Some work=>[(EmptyString,work_ui_target work)]|None=>[] end end.
Definition visible_owner observation owner r := match portal_targets observation owner r with []=>false|_=>true end.
Record fence_observation:=FenceObservation {
 observation_key:string;observation_origin:output_origin;observation_viewer:N;observation_namespace:string;
 observation_prefix:string;observation_code:string;observation_ordinal:N;observation_epoch:N;observation_revision:N;observation_closed:bool }.

Definition decode_fence_observation observation:option fence_observation:=
 document_key<-string_field "document_key" observation;;
 origin<-bind(field "origin" observation)decode_origin;;
 viewing<-bind(field "origin" observation)(natural_field "viewing_task");;
 namespace<-bind(field "origin" observation)(string_field "namespace");;
 prefix<-string_field "input_prefix" observation;;source<-string_field "code_prefix" observation;;
 info<-string_field "raw_info" observation;;kind<-string_field "fence_kind" observation;;
 info_complete<-bool_field "info_complete" observation;;
 ordinal<-natural_field "ordinal" observation;;epoch<-natural_field "epoch" observation;;
 revision<-natural_field "revision" observation;;closed<-bool_field "closed" observation;;
 Some(FenceObservation document_key origin viewing namespace prefix source ordinal epoch revision closed).

Definition decode_observation observation:option fence_observation:=
 if OutputClassification.interactive_markdown_fence_observation observation
 then decode_fence_observation observation else None.

Definition fence_extends observation fence:=
 if N.eqb(observation_ordinal observation)(fence_ordinal fence)then
  String.prefix(fence_code fence)(observation_code observation)&&
  (negb(fence_closed fence)||(observation_closed observation&&String.eqb(fence_code fence)(observation_code observation)))
 else true.
Definition observation_valid namespace observation doc stamp s:=
 String.eqb namespace(observation_namespace observation)&&N.eqb(observation_viewer observation)(viewer doc)&&
 same_origin(observation_origin observation)(provenance doc)&&eligible_fence namespace doc(observation_ordinal observation)s&&
 N.eqb(observation_epoch observation)(document_epoch stamp)&&
 N.leb(observation_revision observation)(N.of_nat(Utf8.byte_length(markdown doc)))&&
 Nat.leb(document_observed_prefix stamp)(Utf8.byte_length(observation_prefix observation))&&
 String.prefix(observation_prefix observation)(markdown doc)&&
 forallb(fence_extends observation)(document_observations stamp).
Definition record_observation observation stamp:=
 let ordinal:=observation_ordinal observation in
 update_stamp(document_source stamp)(document_ending stamp)(document_archived stamp)(document_revealed stamp)
  (Utf8.byte_length(observation_prefix observation))
  (DocumentFence ordinal(observation_code observation)(observation_closed observation)::
   filter(fun fence=>negb(N.eqb ordinal(fence_ordinal fence)))(document_observations stamp))stamp.
(** The history/preview lookup supplies provenance. The callback only supplies
    facts from the physical Markdown parser, including its monotone prefix. *)

Definition observe_document context raw r : option (Types.input * retention) :=
 observation<-decode_observation raw;;
 let namespace:=context_namespace context in
 doc<-find (fun doc=>String.eqb (observation_key observation) (key namespace doc)) (visible_documents context r);;
 stamp<-document_stamp namespace doc r;;
 if observation_valid namespace observation doc stamp r then
   let accepted:=record_observation observation stamp in
   let next:=with_document_lifetimes (accepted::filter
     (fun old=>negb (String.eqb (document_identity stamp) (document_identity old))) (document_lifetimes r)) r in
   let owner:=Types.Owner (CodeSource.owner_key (code_identity namespace doc (observation_ordinal observation))) (document_epoch stamp) in
   let ending:=if String.eqb (observation_prefix observation) (markdown doc) then document_ending stamp else Types.Open in
   Some (Types.SourceChanged owner (observation_code observation) (observation_closed observation) ending (document_external context doc),next)
 else None.
Inductive observation_admission :=
 | MalformedObservation
 | IrrelevantObservation
 | AdmittedObservation (incoming:Types.input) (retained:retention).

(** DEFENSE: physical Markdown reports include ordinary fences and callbacks
    whose document has since been replaced. A well-formed report without a
    current document owner must not change the product or its publication. *)
Definition admit_observation context raw retained :=
 match decode_fence_observation raw with
 | None=>MalformedObservation
 | Some _=>match observe_document context raw retained with
   |None=>IrrelevantObservation
   |Some(incoming,next)=>AdmittedObservation incoming next end
 end.

Definition environment_with_revocation observation lagged revoked := JObject [
 ("world",context_world observation);("namespace",JString (context_namespace observation));
 ("connected",JBool (context_connected observation));("display_lagged",JBool lagged);
 ("revoked",JBool (revoked || negb (valid_namespace (context_namespace observation))));
 ("viewing_tasks",JArray (map number (visible_tasks observation)));("work",optional_id (context_work observation))].
Definition environment observation lagged := environment_with_revocation observation lagged (context_revoked observation).
Definition edit_retained observation identity (toggle:bool) r :=
 match find (fun stamp=>String.eqb identity (document_identity stamp)) (retained_stamps observation r) with
 |None=>r
 |Some stamp=>if toggle then
   if document_archived stamp then with_document_lifetimes (map (fun old=>if String.eqb identity (document_identity old) then
     update_stamp (document_source old) (document_ending old) true (negb (document_revealed old))
       (document_observed_prefix old) (document_observations old) old else old) (document_lifetimes r)) r
   else r
 else with_document_lifetimes (filter (fun stamp=>negb (String.eqb identity (document_identity stamp))) (document_lifetimes r)) r end.
