From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require Import Document Keyboard Focus Reading Publication Observation Typography Layout FieldSession ControlContent.
From Selvedge.Interaction Require Import CodeBlock.
Module NativeAppearance := Selvedge.Browser.Appearance.
Import ListNotations.
Open Scope string_scope.

Definition natural_field (name : string) (source : json) : option nat :=
  match number_field name source with Some text => parse_nat text | None => None end.
Definition binary_field (name : string) (source : json) : option N :=
  match number_field name source with Some text => parse_natural text | None => None end.
Definition binary_json (value : N) := JNumber (show_natural value).
Definition bool_value (name : string) (source : json) :=
  match bool_field name source with Some value => value | None => false end.
Definition nat_json (value : nat) := JNumber (show_nat value).
Definition invalid (message : string) := failure "TypeError" message.
Definition native_key (source : json) : json :=
  match string_field "keyboard" source with
  | None => invalid "Native key requires keyboard"
  | Some key =>
      let ime := match natural_field "key_code" source with
        Some code => Nat.eqb code 229 | None => false end in
      let input := Keyboard.Observe key (bool_value "composing" source) ime
        (bool_value "shift" source) (bool_value "alt" source) (bool_value "modified" source) in
      let editor_composing := bool_value "editor_composing" source in
      let decision := if editor_composing then Keyboard.Decide false false else
        Keyboard.normalize input (bool_value "multiline" source) (bool_value "enabled" source) (bool_value "pending" source) in
      success (JObject [("submit", JBool (Keyboard.submit decision));
        ("prevent_default", JBool (Keyboard.prevent_default decision));
        ("editing", JBool (Keyboard.editing_key input editor_composing));
        ("unmodified", JBool (Keyboard.unmodified_editing_key input editor_composing));
        ("confirm", JBool (Keyboard.text_confirmation input editor_composing));
        ("activate", JBool (Keyboard.control_activation input editor_composing));
        ("input_started", JBool (Keyboard.begins_input input editor_composing))])
  end.
Definition publication_state source : option Publication.state :=
 match binary_field "generation" source, string_field "phase" source,
 string_field "namespace" source,binary_field "sequence" source with
 |Some generation,Some phase,Some namespace,Some sequence=>
 match phase with "awaiting"=>Some(Publication.State generation Publication.AwaitingDocument namespace sequence)
 |"prepared"=>Some(Publication.State generation Publication.Prepared namespace sequence)
 |"published"=>Some(Publication.State generation Publication.Published namespace sequence)
 |"awaiting_presentation"=>Some(Publication.State generation Publication.AwaitingPresentation namespace sequence)
 |"prepared_presentation"=>Some(Publication.State generation Publication.PreparedPresentation namespace sequence)
 |"recovery"=>match string_field "reason" source with Some reason=>Some(Publication.State generation(Publication.Recovering reason)namespace sequence)|None=>None end
 |_=>None end
 |_,_,_,_=>None end.
Definition publication_json state := JObject [
 ("generation",binary_json(Publication.generation state));
 ("phase",JString(match Publication.current_phase state with Publication.AwaitingDocument=>"awaiting"|Publication.Prepared=>"prepared"|Publication.Published=>"published"|Publication.AwaitingPresentation=>"awaiting_presentation"|Publication.PreparedPresentation=>"prepared_presentation"|Publication.Recovering _=>"recovery" end));
 ("reason",match Publication.recovery_reason state with Some reason=>JString reason|None=>JNull end);
 ("namespace",JString(Publication.namespace state));("sequence",binary_json(Publication.sequence state))].
Definition publication_call source :=
 match publication_state source,string_field "event" source with
 |Some state,Some "advance"=>success(publication_json(Publication.advance state))
 |Some state,Some "present"=>success(publication_json(Publication.present state))
 |Some state,Some "semantic_pending"=>success(JBool(Publication.semantic_pending state))
 |Some state,Some "invalidate"=>success(publication_json(Publication.invalidate state))
 |Some state,Some "failure"=>match string_field "reason" source with
 |Some reason=>success(publication_json(Publication.failed reason state))|None=>invalid "Recovery requires its failure reason" end
 |Some state,Some "retry"=>success(publication_json(Publication.retry state))
 |Some state,Some "recovery"=>success(match Publication.recovery_reason state with Some reason=>JString reason|None=>JNull end)
 |Some state,Some "ready"=>success(JBool(Publication.fresh state))
 |Some state,Some "document"=>match binary_field "receipt_generation" source with
 Some n=>success(publication_json(Publication.document_ready n state))|None=>invalid "Document receipt requires its generation" end
 |Some state,Some "publish"=>match binary_field "receipt_generation" source with
 Some n=>success(publication_json(Publication.publish n state))|None=>invalid "Publication receipt requires its generation" end
 |Some state,Some "admit"=>match binary_field "receipt_generation" source with
 Some n=>success(JBool(Publication.admit n state))|None=>invalid "Input requires its publication generation" end
 |Some state,Some "refresh"=>match field "connection" source with
 |Some raw=>match Services.decode_connection raw with
 |Some connection=>success(JBool(Publication.refresh_needed (string_field "source_namespace" source)
   (binary_field "source_sequence" source) (bool_value "sources_fresh" source) connection state))
 |None=>invalid "Commit notice requires its current connection" end
 |None=>invalid "Commit notice requires its current connection" end
 |Some state,Some "completion"=>match string_field "expected_namespace" source,string_field "incoming_namespace" source with
 |Some expected,Some incoming=>success(JBool(Publication.admit_completion expected incoming state))
 |_,_=>success(JBool false)end
 |_,_=>invalid "Publication requires a valid state and event" end.
Definition snapshot_receipt origin accepted authenticated source :=
 success(JObject[("accepted",JBool accepted);
   ("authenticated",JBool authenticated);
   ("install_world",JBool(match publication_state source,string_field "incoming_namespace" source,binary_field "incoming_sequence" source with
     |Some current,Some incoming,Some seq=>accepted&&Publication.install_snapshot incoming seq current
     |_,_,_=>false end));
   ("sources_fresh",JBool(Publication.snapshot_freshness origin authenticated
     (bool_value "sources_fresh" source))) ]).
Definition snapshot_call source :=
 match publication_state source,string_field "expected_namespace" source,
 string_field "incoming_namespace" source,binary_field "incoming_sequence" source with
 |Some state,Some expected,Some incoming,Some seq=>
 if bool_value "authenticating" source then
 match binary_field "authentication_ticket" source,
   (match field "connection" source with
    |Some value=>Services.decode_connection value|None=>None end) with
 |Some ticket,Some connection=>snapshot_receipt Publication.Authentication
   (Publication.admit_authenticated_snapshot ticket connection expected incoming seq state)
   (Publication.admit_authentication ticket connection expected incoming state) source
 |_,_=>invalid "Authenticated snapshot requires its current connection and request ticket" end
 else snapshot_receipt Publication.ExistingSession
   (Publication.admit_snapshot Publication.ExistingSession expected incoming seq state) false source
 |_,_,_,_=>invalid "Snapshot requires request scope and source cursor" end.
Definition measurement_failure_call source :=
 match binary_field "measured_generation" source,binary_field "current_generation" source,
   string_field "reason" source with
 |Some measured,Some current,Some reason=>success
   (match Observation.measurement_failure measured current reason with
    |Some reason=>JString reason|None=>JNull end)
 |_,_,_=>invalid "Measurement failure requires its requested generation and reason" end.
Fixpoint text_observations (values : list json) : option (list string) :=
  match values with
  | [] => Some []
  | JString value :: rest => option_map (cons value) (text_observations rest)
  | _ => None end.
Definition target_observation (value : json) : option Focus.target_observation :=
  match string_field "key" value, array_field "aliases" value, string_field "view" value with
  | Some key, Some aliases, Some view => option_map (fun aliases => Focus.ObserveTarget key aliases view) (text_observations aliases)
  | _, _, _ => None end.
Fixpoint target_observations (values : list json) : option (list Focus.target_observation) :=
  match values with
  | [] => Some []
  | value :: rest => match target_observation value, target_observations rest with
      | Some value, Some rest => Some (value :: rest) | _, _ => None end
  end.
Definition resolve_target_call (source : json) : json :=
  match string_field "target" source, string_field "view" source, array_field "candidates" source with
  | Some target, Some view, Some candidates =>
      match target_observations candidates with
      | Some candidates => success (match (match string_field "fallback" source with
          | Some fallback => Focus.resolve_return target fallback view candidates
          | None => Focus.resolve target view candidates end) with
          | Some key => JString key | None => JNull end)
      | None => invalid "Physical target candidates require key, aliases and view" end
  | _, _, _ => invalid "Target resolution requires target, view and observed candidates" end.
Definition focus_call (source : json) : json :=
  match string_field "current" source, array_field "targets" source with
  | Some current, Some targets =>
      match text_observations targets with
      | Some targets => success
          (match cycle (bool_value "backward" source) current targets with
          Some key => JString key | None => JNull end)
      | None => invalid "Focus targets must be strings"
      end
  | _, _ => invalid "Focus cycle requires current and targets"
  end.
Definition anchor_state source : option Reading.anchor :=
 match string_field "key" source,string_field "offset" source with
 |Some key,Some spelling=>option_map(Reading.Anchor key)(Reading.admit_extent spelling)|_,_=>None end.
Definition reading_state source : option Reading.state :=
 let point:=match field "anchor" source with Some value=>anchor_state value|None=>None end in
 match string_field "intent" source with
 |Some "follow"=>Some(Reading.State Reading.FollowLatest point)
 |Some "history"=>Some(Reading.State Reading.ReadHistory point)|_=>None end.
Definition anchor_json value := JObject [("key",JString(Reading.anchor_key value));
 ("offset",JString(proj1_sig(Reading.offset value)))].
Definition reading_json state := JObject [("intent",JString(match Reading.reading_intent state with Reading.FollowLatest=>"follow"|Reading.ReadHistory=>"history" end));
 ("anchor",match Reading.bookmark state with Some point=>anchor_json point|None=>JNull end)].
Definition reading_effect_json effect := match effect with
 |Reading.LeaveViewport=>JObject[("type",JString "leave_viewport")]
 |Reading.CancelAnchorObservation=>JObject[("type",JString "cancel_anchor")]
 |Reading.AlignLatest animate=>JObject[("type",JString "align_latest");("animate",JBool animate)]
 |Reading.PreserveAnchor point=>JObject[("type",JString "preserve_anchor");("anchor",anchor_json point)]
 |Reading.MeasureAnchor=>JObject[("type",JString "measure_anchor")]
 |Reading.LocateMessage index=>JObject[("type",JString "locate_message");("index",binary_json index)]
 |Reading.ReserveComposer height viewport=>JObject[("type",JString "reserve_composer");("clearance",JString(Reading.clearance_css height viewport))] end.
Definition extent_field name source := match string_field name source with
 Some spelling=>Reading.admit_extent spelling|None=>None end.
Definition scoped_reading_json generation state := match reading_json state with
 |JObject fields=>JObject(("scope_generation",binary_json generation)::fields)|value=>value end.
Definition reading_bind source := match binary_field "generation" source,field "state" source with
 |Some generation,Some JNull=>success(scoped_reading_json generation(Reading.State Reading.FollowLatest None))
 |Some generation,Some encoded=>match binary_field "scope_generation" encoded,reading_state encoded with
 |Some previous,Some state=>success(scoped_reading_json generation(Reading.bind_generation previous generation state))
 |_,_=>invalid "Reading binding requires its reader occurrence"end
 |_,_=>invalid "Reading binding requires the actual reader occurrence and optional prior state"end.
Definition reading_call source := match field "state" source,string_field "event" source with
 |Some encoded,Some name=>match reading_state encoded,binary_field "scope_generation" encoded with
 |Some state,Some scope_generation=>
 let event:=match name with
 |"scroll"=>Some Reading.BeginUserScroll|"follow"=>Some Reading.Follow
 |"layout"=>match extent_field "dock_height" source,extent_field "viewport_height" source with
 Some h,Some v=>Some(Reading.LayoutChanged h v)|_,_=>None end
 |"anchor"=>match field "anchor" source with Some point=>option_map Reading.AnchorObserved(anchor_state point)|None=>None end
 |"locate"=>option_map Reading.JumpToMessage(binary_field "index" source)
 |"key"=>option_map(fun key=>Reading.NavigationKey key (bool_value "editable" source))(string_field "keyboard" source)
 |_=>None end in
 match event with None=>invalid "Reading event requires its physical observations"|Some event=>
 let '(state,effects):=Reading.step event (bool_value "reduced_motion" source) state in
 success(JObject[("state",scoped_reading_json scope_generation state);("effects",JArray(map reading_effect_json effects))])end
 |_,_=>invalid "Invalid reading state or missing reader occurrence"end
 |_,_=>invalid "Reading requires state and event" end.
Definition font_specs source := match natural_field "root_font_size_milli" source with
 |Some root=>success(JArray(map(fun spec=>JObject[("key",JString(Typography.measurement_key spec));
 ("sample",JString(Typography.measurement_sample spec));
 ("properties",DOM.properties_json(Typography.specification_properties root spec))])Typography.measurement_specs))
 |None=>invalid "Font measurements require actual root font size" end.
Definition observed_metric key values :=
 Observation.first_valid_observation Observation.valid_metric key values.
Definition observed_region key values :=
 match Observation.first_valid_observation Observation.valid_region key values with
 |Some value=>field "width" value
 (* DEFENSE: a matched native region without complete dimensions is a failed
    observation, not an absent region that can remain pending. *)
 |None=>if existsb(Observation.named_observation key)values then None else Some JNull end.
(* DEFENSE: native font measurement may finish after a newer document is
   published; the stale batch must not supply any font or region observation. *)
Definition environment_call source :=
 match binary_field "measured_generation" source,binary_field "current_generation" source with
 |Some measured,Some current=>
 if Observation.current_measurement measured current then
 match natural_field "requested_root_font_size_milli" source,field "observations" source with
 |Some requested,Some value=>
 match natural_field "root_font_size_milli" value with
 |Some observed=>
 (* DEFENSE: the root font size can change while document.fonts.ready is pending,
    leaving the requested probe styles inconsistent with the returned viewport. *)
 if Nat.eqb requested observed then
 match field "width" value,field "height" value,field "root_font_size_milli" value,
 array_field "metrics" value,array_field "regions" value,bool_field "system_dark" source,bool_field "reduced_motion" source with
 |Some width,Some height,Some root,Some metrics,Some regions,Some dark,Some motion=>
 match observed_metric "@font/body" metrics,observed_metric "@font/activity-primary" metrics,observed_metric "@font/activity-support" metrics,
 observed_region "workspace" regions,observed_region "main" regions with
 |Some body,Some primary,Some support,Some workspace,Some main=>let encoded:=JObject[("viewport_width",width);("viewport_height",height);("root_font_size_milli",root);
 ("font_metrics",JObject[("body",body);("primary",primary);("support",support)]);
 ("workspace_inner_width",workspace);("main_inner_width",main);
 ("system_dark",JBool dark);("reduced_motion",JBool motion)] in
 match Observation.decode_environment encoded with
 |Some _=>success(JObject[("stale",JBool false);("environment",encoded)])
 |None=>invalid "Invalid native font or viewport observation" end
 |_,_,_,_,_=>invalid "Complete positive font metrics and allocated region dimensions are required" end
 |_,_,_,_,_,_,_=>invalid "Incomplete physical observations" end
 else success(JObject[("stale",JBool true)])
 |None=>invalid "Environment requires the observed root font size" end
 |_,_=>invalid "Environment requires the requested root font size and native observations" end
 else success(JObject[("stale",JBool true)])
 |_,_=>invalid "Environment requires the measured and current document generations" end.
Definition decode_scope source := match string_field "type" source with
 |Some "document"=>Some Focus.Document
 |Some "temporary"=>match string_field "identity" source,string_field "initial" source,
 string_field "restore" source,string_field "fallback" source,field "occurrence" source with
 |Some identity,Some initial,Some restore,Some fallback,Some JNull=>Some(Focus.Temporary identity initial restore fallback None)
 |Some identity,Some initial,Some restore,Some fallback,Some value=>option_map(fun n=>Focus.Temporary identity initial restore fallback (Some n))
 (match value with JNumber n=>parse_natural n|_=>None end)
 |_,_,_,_,_=>None end|_=>None end.
Fixpoint decode_scopes values := match values with []=>Some[]|value::rest=>
 match decode_scope value,decode_scopes rest with Some value,Some rest=>Some(value::rest)|_,_=>None end end.
Definition focus_plan source := match array_field "previous" source,array_field "current" source,bool_field "eligible" source with
 |Some previous,Some current,Some eligible=>match decode_scopes previous,decode_scopes current with
 |Some previous,Some current=>success(match Focus.request previous current eligible with
 Some(target,fallback)=>JObject[("target",JString target);("fallback",JString fallback)]|None=>JNull end)
 |_,_=>invalid "Invalid focus scopes" end|_,_,_=>invalid "Focus transition requires both scope stacks and observed eligibility" end.
Definition row_direction_name direction := match direction with
 |Layout.Horizontal=>"row"|Layout.Vertical=>"column" end.
Definition responsive_row_layout available row : option (list (string * json)) :=
 match field "full_preferred" row,field "compact_minimum" row with
 |None,None=>match natural_field "minimum" row with
   |Some minimum=>match field "nested_compact_minimum" row with
    |None=>Some[("direction",JString(row_direction_name(Layout.row_flow available minimum)))]
    |Some _=>match natural_field "nested_compact_minimum" row with
     |Some compact=>Some[("direction",JString(row_direction_name(Layout.row_flow available (Nat.min minimum compact))))]
     |None=>None end end
   |None=>None end
 |Some _,Some _=>match natural_field "full_preferred" row,natural_field "compact_minimum" row with
   |Some full,Some compact=>let choice:=ControlContent.choose_supporting available full compact in
     Some[("direction",JString(row_direction_name(ControlContent.supporting_direction choice)));
       ("supporting_form",JString(ControlContent.form_name(ControlContent.supporting_representation choice)))]
   |_,_=>None end
 |_,_=>None end.
Definition responsive_rows source := match array_field "rows" source with None=>invalid "Responsive rows require native observations"|Some rows=>
 let fix decode rows:=match rows with []=>Some[]|row::rest=>
 match string_field "key" row,natural_field "available" row,decode rest with
 |Some key,Some available,Some rest=>match responsive_row_layout available row with
   |Some layout=>Some(JObject(("key",JString key)::layout)::rest)|None=>None end
 |_,_,_=>None end end in match decode rows with Some rows=>success(JArray rows)|None=>invalid "Invalid responsive row observation" end end.
Definition code_targets who view := JObject(map(fun part=>(DocumentPublication.target_name part,
 JString(Observation.physical_target view(DocumentPublication.target_key who part))))
 [DocumentPublication.Toolbar;DocumentPublication.Body;DocumentPublication.Source;DocumentPublication.Frame;DocumentPublication.Preview]).
Definition request_view source := match field "view" source with Some value=>Observation.decode_view value|None=>None end.
Definition code_document env physical_view state :=
 let view:=CodeBlock.observe state in let who:=CodeBlock.identity state in
 DOM.encode(DOM.Document
 (DOM.Element (Observation.physical_target physical_view (DocumentPublication.target_key who DocumentPublication.Toolbar)) "div"
 [("role","toolbar");("aria-label","Code actions")] (NativeAppearance.role_properties env Roles.Toolbar) [] (JObject[])
 (map(fun control=>DOM.Element (Observation.physical_target physical_view (String.append(CodeSource.key who)(match control with CodeBlock.CopyControl=>"/copy"|CodeBlock.WrapControl=>"/wrap" end))) "button"
 (([("type","button");("aria-label",CodeBlock.control_label view control)]++
 (match control with CodeBlock.WrapControl=>[("aria-pressed",Document.flag(CodeBlock.presented_wrap view))]
 |CodeBlock.CopyControl=>match CodeBlock.presented_copy view with CodeBlock.Pending _=>[("data-interactive-motion","spin")]|_=>[]end end))++Document.disabled(CodeBlock.control_enabled view control))
 (NativeAppearance.role_properties env (match control with
  |CodeBlock.CopyControl=>match CodeBlock.presented_copy view with
    |CodeBlock.Feedback _ false=>Roles.DestructiveButton|_=>Roles.Button end
  |_=>Roles.Button end))
 [DOM.Binding "click" "activate" (DOM.CodeTarget(CodeBlock.encode_input(CodeBlock.control_input control)))]
 (JObject[]) (Document.glyph(match control with CodeBlock.WrapControl=>"wrap-lines"|CodeBlock.CopyControl=>
 match CodeBlock.presented_copy view with CodeBlock.Idle=>"copy-sheets"|CodeBlock.Pending _=>"spinner"|CodeBlock.Feedback _ true=>"check"|CodeBlock.Feedback _ false=>"warning"end end)))CodeBlock.controls))
 "" 0 false [] []).
Definition code_call operation source := match
 (if String.eqb operation "present" then match field "state" source with
 Some encoded=>match CodeBlock.decode_state encoded with Some state=>CodeBlock.Executed state []|None=>CodeBlock.Rejected "TypeError" "Invalid code state" end
 |None=>CodeBlock.Rejected "TypeError" "Code state is required" end
 else CodeBlock.execute operation source),
 (match field "environment" source with Some env=>Observation.decode_environment env|None=>None end),request_view source with
 |CodeBlock.Executed state effects,Some env,Some view=>success(JObject[("state",CodeBlock.encode_state state);
 ("effects",JArray(map CodeBlock.encode_effect effects));("document",code_document env view state);
 ("targets",code_targets(CodeBlock.identity state)view);
 ("body_styles",DOM.properties_json [("white-space",if CodeBlock.wrap state then "pre-wrap" else "pre")]);("wrap",JBool(CodeBlock.wrap state))])
 |CodeBlock.Rejected name message,_,_=>failure name message
 |_,_,_=>invalid "Code presentation requires actual environment and view observations" end.
Definition call operation source := match operation with
 |"recovery"=>match natural_field "root_font_size_milli" source,binary_field "generation" source,string_field "reason" source with
 |Some root,Some generation,Some reason=>success(Document.recovery root generation reason)
 |_,_,_=>invalid "Recovery requires the actual root font size, generation and reason"end
 |"focus_plan"=>focus_plan source|"responsive_rows"=>responsive_rows source
 |"key"=>native_key source
 |"field_session"=>FieldSession.field_session_call source
 |"publication"=>publication_call source|"snapshot"=>snapshot_call source
 |"measurement_failure"=>measurement_failure_call source
 |"focus_cycle"=>focus_call source|"resolve_target"=>resolve_target_call source
 |"reading_bind"=>reading_bind source|"reading"=>reading_call source|"font_specs"=>font_specs source|"environment"=>environment_call source
 |"code_present"=>code_call "present" source
 |"code_key"=>match field "identity" source with Some encoded=>match CodeSource.decode_identity encoded with Some identity=>success(JString(CodeSource.key identity))|None=>invalid "Invalid code identity" end|None=>invalid "Code identity is required" end
 |"code_initial"=>code_call "initial" source|"code_step"=>code_call "step" source
 |"code_targets"=>match field "identity" source,request_view source with Some who,Some view=>match CodeSource.decode_identity who with
 Some who=>success(code_targets who view)|None=>invalid "Invalid code identity" end|_,_=>invalid "Code identity and view are required" end
 |"code_identity"=>match field "source" source,binary_field "ordinal" source with
 Some source,Some ordinal=>match CodeSource.decode_source source with Some who=>success(CodeSource.encode_identity(CodeSource.CodeIdentity who ordinal))
 |None=>invalid "Invalid document provenance" end|_,_=>invalid "Document provenance and ordinal are required" end
 |_=>failure "RangeError" "Unknown browser operation" end.
