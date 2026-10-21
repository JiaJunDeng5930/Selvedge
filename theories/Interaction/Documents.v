From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Kernel Require Import Conversation Streams.
From Selvedge.Interaction Require Import Codec Identity Origin Services ApplicationState ApplicationOps Navigation.
From Selvedge.Interaction.Interactive Require Import Types.
From Selvedge.Interaction.Interactive Require Bounds.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Record document := Document { viewer:N; provenance:output_origin; markdown:string; complete:bool }.
Definition key namespace doc:=content_key namespace(viewer doc)(provenance doc).
Definition history_document viewing message:option document:=
 if Conversation.json_message_assistant message then
  origin<-bind(field "origin" message)decode_origin;;body<-Conversation.json_message_text message;;
  if interactive_origin origin then Some(Document viewing origin body true)else None
 else None.
Definition history_documents viewing world:=
 match find_task viewing world with None=>[]|Some task=>
  fold_right(fun message rest=>match history_document viewing message with Some doc=>doc::rest|None=>rest end)[](items "history" task)end.
Definition live_documents viewing world s:=
 flat_map(fun output=>if N.eqb(Streams.output_task output)viewing then
  match find_task viewing world with None=>[]|Some task=>
   match bind(field "model_pending" task)(fun pending=>bind(string_field "mode" pending)decode_mode)with
   |None=>[]|Some Plain=>[]|Some InteractiveV1=>map(fun '(part,text)=>
     Document viewing(OutputOrigin(Streams.output_task output)(Streams.output_operation output)part InteractiveV1)text false)(Streams.output_parts output)
   end end else [])(active_previews world s).
Definition documents_for viewing world s:=history_documents viewing world++live_documents viewing world s.
Definition authoritative_documents namespace world s:=
 if valid_namespace namespace then flat_map(fun viewing=>documents_for viewing world s)(visible_tasks s)else [].
Definition stamp_in_namespace namespace stamp:=
 valid_namespace namespace&&interactive_origin(document_origin stamp)&&
 String.eqb(document_identity stamp)(content_key namespace(document_viewer stamp)(document_origin stamp)).
Definition stamp_is_current namespace world s stamp:=
 existsb(fun doc=>String.eqb(key namespace doc)(document_identity stamp))(documents_for(document_viewer stamp)world s).
Definition retained_stamps namespace world s:=filter(fun stamp=>
 stamp_in_namespace namespace stamp&&existsb(N.eqb(document_viewer stamp))(visible_tasks s)&&
 negb(stamp_is_current namespace world s stamp)&&
 match document_ending stamp with Types.Complete=>false|_=>true end)(document_lifetimes s).
Definition visible_documents namespace world s:=authoritative_documents namespace world s++
 map(fun stamp=>Document(document_viewer stamp)(document_origin stamp)(document_source stamp)false)
  (filter(fun stamp=>negb(document_archived stamp))(retained_stamps namespace world s)).

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
 let r:=document_retention s in
 let '(next_epoch,stamp):=match prior with
 |Some prior=>if continuous_document prior doc then
   (retention_next_epoch r,update_stamp(markdown doc)ending false false(document_observed_prefix prior)(document_observations prior)prior)
  else (N.succ(retention_next_epoch r),DocumentLifetime namespace(viewer doc)(provenance doc)(retention_next_epoch r)(markdown doc)ending false false 0[])
 |None=>(N.succ(retention_next_epoch r),DocumentLifetime namespace(viewer doc)(provenance doc)(retention_next_epoch r)(markdown doc)ending false false 0[])
 end in
 with_retention(Retention namespace next_epoch(stamp::filter(fun old=>negb(String.eqb identity(document_identity old)))(document_lifetimes s))(discarded_outputs s))s.
Definition pending_stamp world stamp:=
 let origin:=document_origin stamp in
 match find_task(producer origin)world with None=>false|Some task=>
  match field "model_pending" task with None=>false|Some pending=>
   match natural_field "operation_id" pending,bind(string_field "mode" pending)decode_mode with
   |Some operation,Some mode=>same_origin origin(OutputOrigin(producer origin)operation(part origin)mode)
   |_,_=>false end end end.
Definition mark_interrupted namespace lagged world s stamp:=
 if same_ending(document_ending stamp)Types.Open&&stamp_in_namespace namespace stamp&&
    connected(service_state s)&&negb lagged&&negb(stamp_is_current namespace world s stamp)&&negb(pending_stamp world stamp)then
   update_stamp(document_source stamp)Types.Interrupted(document_archived stamp)(document_revealed stamp)
    (document_observed_prefix stamp)(document_observations stamp)stamp
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
Definition scoped_retention namespace world s:=
 let r:=document_retention s in
 if String.eqb namespace(retention_namespace r)then
  with_document_lifetimes(filter(fun stamp=>match find_task(document_viewer stamp)world with None=>false|Some _=>true end)(document_lifetimes s))s
 else with_retention(Retention namespace(retention_next_epoch r)[][])s.
Definition synchronize_documents namespace lagged world s:=
 let s:=scoped_retention namespace world s in
 let viewers:=nodup N.eq_dec(visible_tasks s++map document_viewer(document_lifetimes s)++map Streams.output_task(active_previews world s))in
 let docs:=if valid_namespace namespace then flat_map(fun viewing=>documents_for viewing world s)viewers else []in
 let next:=fold_left(fun current doc=>remember_document namespace doc current)docs s in
 let ended:=map(mark_interrupted namespace lagged world next)(document_lifetimes next)in
 let '(kept,discarded):=trim_archives(bound_interrupted(retention_order ended)[]0)0 in
 let r:=document_retention next in
 with_retention(Retention namespace(retention_next_epoch r)kept(fold_left(fun counts task=>add_discarded task counts)discarded(discarded_outputs next)))next.

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
Definition find_document namespace owner world s:=find(document_owns namespace owner s)(visible_documents namespace world s).
Definition shared_key namespace work:=(show_nat(String.length namespace)++":"++namespace++"/work/"++show_natural work)%string.
Definition shared_work namespace owner world s:=
 match location(navigation_state s)with SharedUI work _=>
  if valid_namespace namespace&&String.eqb(Types.owner_key owner)(shared_key namespace work)then
   match find_work work world with Some found=>
    match natural_field "revision" found with Some revision=>
    if N.eqb(Types.epoch owner)revision then Some work
    else None|None=>None end
   |None=>None end
  else None|_=>None end.
Definition shared_task namespace owner world s:=
 work<-shared_work namespace owner world s;;
 match location(navigation_state s)with SharedUI _ (Some task)=>
  if task_belongs(Some work)task world then Some task else None|_=>None end.
Definition owning_task namespace owner world s:=
 match find_document namespace owner world s with Some doc=>
  if interactive_origin(provenance doc)&&complete doc&&N.eqb(viewer doc)(producer(provenance doc))then Some(viewer doc)else None
 |None=>shared_task namespace owner world s end.
Definition document_external namespace doc s:=
 valid_namespace namespace&&complete doc&&external_allowed(connected(service_state s))true(viewer doc)(provenance doc).
Definition externally_allowed namespace owner world s:=
 valid_namespace namespace&&connected(service_state s)&&
 match find_document namespace owner world s with
 |Some doc=>document_external namespace doc s
 |None=>match shared_work namespace owner world s with Some _=>true|None=>false end end.
Definition portal_target namespace owner world s:=
 match find_document namespace owner world s with
 |Some doc=>match owner_ordinal namespace doc owner with
   |Some ordinal=>Some(fence_target(key namespace doc)ordinal)|None=>None end
 |None=>option_map work_ui_target(shared_work namespace owner world s)end.
Definition portal_targets namespace owner world s:=
 match find_document namespace owner world s with
 |Some doc=>match owner_ordinal namespace doc owner with
   |Some ordinal=>map(fun view=>(task_view_scope view,fence_target(key namespace doc)ordinal))
     (filter(fun view=>N.eqb(task_view_task view)(viewer doc))(Navigation.visible_task_views s))
   |None=>[]end
 |None=>match shared_work namespace owner world s with
   |Some work=>[(EmptyString,work_ui_target work)]|None=>[]end end.
Definition visible_owner namespace owner world s:=match portal_targets namespace owner world s with []=>false|_=>true end.

Record fence_observation:=FenceObservation {
 observation_key:string;observation_origin:output_origin;observation_viewer:N;observation_namespace:string;
 observation_prefix:string;observation_code:string;observation_ordinal:N;observation_epoch:N;observation_revision:N;observation_closed:bool }.
Definition decode_observation observation:option fence_observation:=
 document_key<-string_field "document_key" observation;;
 origin<-bind(field "origin" observation)decode_origin;;
 viewing<-bind(field "origin" observation)(natural_field "viewing_task");;
 namespace<-bind(field "origin" observation)(string_field "namespace");;
 prefix<-string_field "input_prefix" observation;;source<-string_field "code_prefix" observation;;
 info<-string_field "raw_info" observation;;kind<-string_field "fence_kind" observation;;
 info_complete<-bool_field "info_complete" observation;;
 ordinal<-natural_field "ordinal" observation;;epoch<-natural_field "epoch" observation;;
 revision<-natural_field "revision" observation;;closed<-bool_field "closed" observation;;
 if String.eqb info "selvedge-ui"&&String.eqb kind "fenced"&&info_complete then
  Some(FenceObservation document_key origin viewing namespace prefix source ordinal epoch revision closed)
 else None.
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
Definition observe_document namespace raw world s:option(Types.input*state):=
 observation<-decode_observation raw;;
 doc<-find(fun doc=>String.eqb(observation_key observation)(key namespace doc))(visible_documents namespace world s);;
 stamp<-document_stamp namespace doc s;;
 if observation_valid namespace observation doc stamp s then
  let accepted:=record_observation observation stamp in
  let next:=with_document_lifetimes(accepted::filter(fun old=>negb(String.eqb(document_identity stamp)(document_identity old)))(document_lifetimes s))s in
  let owner:=Types.Owner((key namespace doc++"/fence/"++show_natural(observation_ordinal observation))%string)(document_epoch stamp)in
  let ending:=if String.eqb(observation_prefix observation)(markdown doc)then document_ending stamp else Types.Open in
  Some(Types.SourceChanged owner(observation_code observation)(observation_closed observation)ending(document_external namespace doc s),next)
 else None.
Definition environment_with_revocation namespace lagged revoked world s:=JObject[
 ("world",world);("namespace",JString namespace);("connected",JBool(connected(service_state s)));
 ("display_lagged",JBool lagged);("revoked",JBool(revoked||negb(valid_namespace namespace)));
 ("viewing_tasks",JArray(map number(visible_tasks s)));("work",optional_id(active_work(navigation_state s)))].
Definition environment namespace lagged world s:=environment_with_revocation namespace lagged false world s.
Definition edit_retained namespace identity (toggle:bool) world s:=
 match find(fun stamp=>String.eqb identity(document_identity stamp))(retained_stamps namespace world s)with
 |None=>s|Some stamp=>if toggle then
   if document_archived stamp then with_document_lifetimes(map(fun old=>if String.eqb identity(document_identity old)then
    update_stamp(document_source old)(document_ending old)true(negb(document_revealed old))(document_observed_prefix old)(document_observations old)old
    else old)(document_lifetimes s))s else s
  else with_document_lifetimes(filter(fun stamp=>negb(String.eqb identity(document_identity stamp)))(document_lifetimes s))s end.
