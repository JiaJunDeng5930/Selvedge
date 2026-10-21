From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers TextJson Utf8.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax Local Sources Vocabulary Registry Types State Expand Paths Snapshot.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope nat_scope.

Definition prepared b environment := Registry.prepare b.(syntax) b.(locals) b.(sources) environment.
Definition mounted_at path occurrence (mounts:list(string*N)) :=
 existsb(fun current=>String.eqb path(fst current)&&N.eqb occurrence(snd current))mounts.
Definition current_feedback mounts entry := match entry.(feedback_transaction)with
 | Waiting _ occurrence _=>mounted_at entry.(feedback_path) occurrence mounts
 | CopyingDefinition _=>true
 | Answered _ _ _=>String.eqb entry.(feedback_path) "@source-copy" ||
   existsb(fun current=>String.eqb entry.(feedback_path)(fst current))mounts
 end.
Definition mount_block mounts next b :=
 State.with_feedbacks(filter(current_feedback mounts)b.(feedbacks))(State.with_mounts mounts next b).
Definition refresh (visible:owner->bool) b environment :=
 let p:=prepared b environment in
 let b:=State.with_sources p.(Registry.sources) (State.with_locals p.(prepared_locals) b) in
 if visible b.(block_owner) then
   let '(nodes,allocation):=Expand.expand b p environment in
   let views:=filter(fun entry=>match snd entry with SourceView _=>true|_=>Paths.retained p nodes entry end)b.(views) in
   (State.with_views views (mount_block allocation.(new_mounts) allocation.(Expand.next_occurrence) b),p,nodes)
 else (mount_block [] b.(State.next_occurrence) b,p,[]).
Definition mark_edit b := State.with_restoration RestorationSettled (State.changed true b).
Definition seal b :=
 let syntax:=b.(syntax) in
 let syntax:=match b.(block_ending) with Complete=>if b.(fence_closed)then Syntax.finish syntax else syntax|_=>syntax end in
 State.with_syntax syntax b.
Definition parse_turn b :=seal(State.with_syntax(Syntax.turn Bounds.parser_turn b.(syntax))b).
Definition finish (visible:owner->bool) b environment (persist:bool) output :=
 let '(b,p,nodes):=refresh visible b environment in
 let '(b,load):=if visible b.(block_owner)then Snapshot.request b p else(b,[]) in
 let '(b,save):=if persist then Snapshot.save b p nodes else(b,[]) in
 let parse:=if visible b.(block_owner)&&Syntax.pending b.(syntax)then[ParseMore b.(block_owner)]else[]in
 (b,output++parse++load++save).
Definition event_node b environment event_id :=
 let p:=prepared b environment in
 let '(nodes,_):=Expand.expand b p environment in
 Expand.find_event 8192 event_id nodes.
Definition replace_action path occurrence action b :=
 let '(ticket,b):=State.take_ticket b in
 (ticket,State.set_feedback path (Waiting ticket occurrence action) b).
Definition action_effect who path ticket action := match action with
 | Draft text=>[FillDraft who path text]
 | Submit text=>[SendMessage who path ticket text]
 | Copy text=>[WriteClipboard who path ticket text]
 | Navigate url=>[OpenUrl who path ticket url]
 | _=>[] end.
Definition perform_action event_id action b :=
 match action with
 | Assign id value=>match Local.find_local id b.(locals) with
   | Some local=>match Local.assign local value with
     | Some next=>(mark_edit(State.with_locals(Local.replace_local next b.(locals))b),[],true)
     | None=>(b,[],false)end|None=>(b,[],false)end
 | ResetAll=>(mark_edit(State.with_views [] (State.with_locals(map Local.reset b.(locals))b)),[],true)
 | Draft text=>(b,[FillDraft b.(block_owner) event_id.(path) text],false)
 | _=>if State.duplicate_pending action b then(b,[],false)else
   let '(ticket,b):=replace_action event_id.(path) event_id.(occurrence) action b in
   (b,action_effect b.(block_owner) event_id.(path) ticket action,false)
 end.
Definition field_edit event_id value b environment :=
 match event_node b environment event_id with
 | Some(Mounted _ _ (FieldLink id true) _) => match Local.find_local id b.(locals) with
   | None=>(b,[],false)
   | Some local=>let '(next,canonical_changed):=Local.edit local value in
     let output:=match Local.input_raw value with
       | Some raw=>if TextJson.within_scalars Bounds.raw_scalars raw then[]else[RestoreFieldBuffer event_id local.(Local.raw)]
       | None=>[]end in
     (mark_edit(State.with_locals(Local.replace_local next b.(locals))b),output,canonical_changed)
   end
 | _=>(b,[],false)end.
Definition clicked event_id b environment := match event_node b environment event_id with
 | Some(Mounted _ _ (ActionLink action Enabled) _)=>
   if Expand.local_action action || Expand.external_allowed b (prepared b environment) environment
   then perform_action event_id action b else(b,[],false)
 | _=>(b,[],false)end.
Definition decimal_clamp low high value := Decimal.checked (Z.max low (Z.min high (Decimal.units value))).
Definition zoom_step:=Decimal.parse "0.25".
Definition view_update command props previous : option view_state :=
 match props.(description).(component_role),previous with
 | Graph,GraphView zoom x y selected=>
   let zoom_value value:=clamped <- decimal_clamp (Z.quot Decimal.scale 4) (2*Decimal.scale) value;;Some(GraphView clamped x y selected)in
   match command with
   | ZoomIn=>delta <- zoom_step;;v <- Decimal.binary "+" zoom delta;;zoom_value v
   | ZoomOut=>delta <- zoom_step;;v <- Decimal.binary "-" zoom delta;;zoom_value v
   | Pan dx dy=>dx <- Decimal.parse dx;;dy <- Decimal.parse dy;;x <- Decimal.binary "+" x dx;;y <- Decimal.binary "+" y dy;;
     x <- decimal_clamp (-2000*Decimal.scale)(2000*Decimal.scale)x;;
     y <- decimal_clamp (-2000*Decimal.scale)(2000*Decimal.scale)y;;Some(GraphView zoom x y selected)
   | Fit=>Some(GraphView Decimal.one Decimal.zero Decimal.zero selected)
   | SelectNode id=>if existsb(fun node=>match string_field "identity"node with Some actual=>String.eqb actual id|_=>false end)(property_array "nodes"props)
     then Some(GraphView zoom x y id)else None
   | _=>None end
 | Table,TableView column descending page=>match command with
   | SortColumn id=>if property_bool false "sortable" props then
     Some(TableView(Some id)(match column with Some active=>if String.eqb active id then negb descending else false|None=>false end)0)else None
   | Page next=>let count:=List.length(property_array "rows"props)in
     Some(TableView column descending (Nat.min next ((count-1)/Bounds.table_page)))
   | _=>None end
 | _,_=>None end.
Definition view_changed event_id command b environment : block*list effect*bool :=
 match event_node b environment event_id with
 | Some(Mounted _ props (Passive true) _) =>
   match Paths.describe (prepared b environment) event_id.(path) with
   | Some descriptor=>
     let allowed:=match descriptor,command with
       | TableDescriptor columns,SortColumn id=>existsb(String.eqb id)columns
       | _,_=>true end in
     if allowed then match view_update command props(State.view_at event_id.(path)
       (match descriptor with GraphDescriptor=>true|_=>false end)b)with
     | Some value=>match command,property "select"props with
       | SelectNode id,Some(JString local_id)=>match Local.find_local local_id b.(locals)with
         |Some local=>match Local.assign local (JString id)with
           |Some next=>(mark_edit(State.with_locals(Local.replace_local next b.(locals))b),[],true)
           |None=>(b,[],false)end
         |None=>(b,[],false)end
       |_,_=>(mark_edit(State.set_view event_id.(path)value b),[],true)end
     | None=>(b,[],false)end else(b,[],false)
   | None=>(b,[],false)end
 | _=>(b,[],false)end.
Definition settle_feedback path ticket ok message b :=
 match State.feedback_at path b with
 | Some(FeedbackEntry _ (Waiting expected occurrence _))=>
   if N.eqb ticket expected && mounted_at path occurrence b.(mounts)
   then State.set_feedback path (Answered ticket ok message) b else b
 | Some(FeedbackEntry _ (CopyingDefinition expected))=>
   if N.eqb ticket expected then State.set_feedback path (Answered ticket ok message) b else b
 | _=>b end.
Definition input_owner input := match input with
 | EnvironmentChanged=>None
 | ValueChanged event_id _|ActionClicked event_id|ViewChanged event_id _=>Some event_id.(event_owner)
 | SourceChanged who _ _ _ _|Continue who|ExternalChanged who _|Feedback who _ _ _ _|
   Restore who _ _ _|StorageResult who _ _ _|SourceDisclosure who|CopyDefinition who|Remove who=>Some who end.
Definition authored_input input := match input with
 |ValueChanged _ _|ActionClicked _|ViewChanged _ _|SourceDisclosure _|CopyDefinition _=>true|_=>false end.
Definition source_update who source closed ending external current :=
 match current with
 | None=>Some(seal(State.set_source source (Syntax.append source Syntax.empty) ending closed external
     (State.initial_block who "" Open false false)))
 | Some b=>if same_owner who b.(block_owner)then
     if String.eqb b.(State.source)source && Bool.eqb b.(fence_closed)closed &&
        String.eqb(Types.ending_name b.(block_ending))(Types.ending_name ending)then Some(State.with_external external b)else
     if String.prefix b.(State.source) source then
       let tail:=String.substring(String.length b.(State.source))(String.length source)source in
       Some(seal(State.set_source source (Syntax.append tail b.(syntax)) ending closed external b))
     else None
   else if N.ltb b.(block_owner).(epoch) who.(epoch)then
     Some(seal(State.set_source source (Syntax.append source Syntax.empty) ending closed external
       (State.initial_block who "" Open false false)))else None
 end.
Definition by_key who blocks:=find(fun b=>String.eqb who.(owner_key)b.(block_owner).(owner_key))blocks.
Definition save_block b blocks:=match by_key b.(block_owner) blocks with
 |Some _=>State.replace_block b blocks|None=>blocks++[b]end.
Definition reduce (visible:owner->bool) input b environment :=
 if authored_input input && negb(visible b.(block_owner))then(b,[])else
 match input with
 | Feedback who path ticket ok message=>(settle_feedback path ticket ok message b,[])
 | StorageResult _ callback_revision ok message=>if N.eqb callback_revision b.(revision)then
   let b:=if ok then b else State.with_restoration RestorationSettled b in
   (State.with_notice(if ok then None else Some message)b,[])else(b,[])
 | Restore _ definition callback_revision payload=>
   let p:=prepared b environment in
   if Snapshot.restore_admitted b p definition callback_revision then
     let '(next,output):=Snapshot.restore b p definition callback_revision payload in
     let '(next,_,_):=refresh visible next environment in(next,output)
   else(b,[])
 | _=>let '(next,output,persist):=match input with
   | ValueChanged event_id value=>field_edit event_id value b environment
   | ActionClicked event_id=>clicked event_id b environment
   | ViewChanged event_id command=>view_changed event_id command b environment
   | Continue _=>
     (* DEFENSE: A queued parser continuation can outlive a source update that consumed its remaining input. *)
     if Syntax.pending b.(syntax) then (parse_turn b,[],b.(State.edited)) else (b,[],false)
   | ExternalChanged _ allowed=>(State.with_external allowed b,[],false)
   | SourceDisclosure _=>let open:=match State.view_at "@source"false b with SourceView value=>negb value|_=>true end in
     (State.set_view "@source"(SourceView open)b,[],false)
   | CopyDefinition _=>let action:=Copy b.(State.source)in
     if State.duplicate_pending action b then(b,[],false)else
     let '(ticket,b):=State.take_ticket b in
     let b:=State.set_feedback "@source-copy"(CopyingDefinition ticket)b in
     (b,[WriteClipboard b.(block_owner)"@source-copy"ticket b.(State.source)],false)
   | _=>(b,[],false)end in
   finish visible next environment persist output
 end.
Definition step_visible (visible:owner->bool) input state environment :=
 match input with
 | SourceChanged who source closed ending external=>
   let previous:=by_key who state.(blocks) in
   match source_update who source closed ending external previous with
   | None=>Decision state []
   | Some b=>
     (* Completion can make earlier local edits saveable without another field event. *)
     let persist:=b.(State.edited) && match previous with
       | Some old=>negb(N.eqb old.(revision) b.(revision)) | None=>true end in
     let '(b,output):=finish visible b environment persist []in Decision(State(save_block b state.(blocks)))output end
 | Remove who=>Decision(State(filter(fun b=>negb(same_owner who b.(block_owner)))state.(blocks)))[]
 | EnvironmentChanged=>
   let result:=fold_right(fun b result=>let '(b,output):=finish visible b environment false []in
     (b::fst result,output++snd result))([],[])state.(blocks)in
   Decision(State(fst result))(snd result)
 | _=>match input_owner input with
   |None=>Decision state[]
   |Some who=>match State.find_block who state.(blocks)with
     |None=>Decision state[]
     |Some b=>let '(b,output):=reduce visible input b environment in
       Decision(State(State.replace_block b state.(blocks)))output
     end end
 end.
Definition step:=step_visible(fun _=>true).
