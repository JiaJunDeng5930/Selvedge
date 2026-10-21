From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Kernel Require Domain Codec Search ModelCapabilities.
From Selvedge.Interaction Require Import Codec Identity Forms Experience ExperienceObservation ExperienceAssessment Services.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Inductive activity_request := Compare (kind : property_family)
| Explain (kind : property_family) | EditObject.
Inductive view_intent := PrincipalView | SearchView (query:string) | InspectionView | DecisionView (field : string)
| ParameterView (field buffer : string) | SourceView (field : string).
Definition family_name kind := match kind with
| ProjectFamily => "project" | WorkspaceFamily => "workspace" | ModelFamily => "model"
| PermissionFamily => "permissions" | DeliveryFamily => "delivery" | ScalarFamily => "scalar" end.
Definition decode_family name := match name with
| "project" => Some ProjectFamily | "workspace" => Some WorkspaceFamily | "model" => Some ModelFamily
| "permissions" => Some PermissionFamily | "delivery" => Some DeliveryFamily | "scalar" => Some ScalarFamily
| _ => None end.
Definition encode_request request := match request with
| Compare kind => JObject [("kind", JString "compare"); ("property", JString (family_name kind))]
| Explain kind => JObject [("kind", JString "explain"); ("property", JString (family_name kind))]
| EditObject => JObject [("kind", JString "edit")] end.
Definition decode_request source := match string_field "kind" source with
| Some "compare" => option_map Compare (bind (string_field "property" source) decode_family)
| Some "explain" => option_map Explain (bind (string_field "property" source) decode_family)
| Some "edit" => Some EditObject | _ => None end.
Definition encode_view view := match view with
| PrincipalView => JObject [("kind", JString "principal")]
| SearchView query => JObject [("kind",JString "search");("query",JString query)]
| InspectionView => JObject [("kind", JString "inspection")]
| DecisionView name => JObject [("kind", JString "decision"); ("field", JString name)]
| ParameterView name buffer => JObject [("kind", JString "parameter"); ("field", JString name); ("buffer", JString buffer)]
| SourceView name => JObject [("kind", JString "source"); ("field", JString name)] end.
Definition decode_view source := match string_field "kind" source with
| Some "principal" => Some PrincipalView | Some "inspection" => Some InspectionView
| Some "search"=>option_map SearchView(string_field "query" source)
| Some "decision" => option_map DecisionView (string_field "field" source)
| Some "parameter" => name <- string_field "field" source ;; buffer <- string_field "buffer" source ;;
    Some (ParameterView name buffer)
| Some "source" => option_map SourceView (string_field "field" source) | _ => None end.

Inductive completion := ApplyAndDismiss | ApplyAndReturn | CompleteParameterAndReturn
| ReturnToPrincipal | ReturnToInspection | CommitAndDiscard | DismissActivity.

Inductive workspace_change := AddDirectory | ClearDirectoryEntry | UseInheritedWorkspace
| RemoveDirectory (path : string) | ChoosePrimary (path : string).
Definition encode_workspace_change change := match change with
| AddDirectory => JObject [("kind", JString "add")]
| ClearDirectoryEntry => JObject [("kind", JString "clear")]
| UseInheritedWorkspace => JObject [("kind",JString "inherit")]
| RemoveDirectory path => JObject [("kind", JString "remove"); ("path", JString path)]
| ChoosePrimary path => JObject [("kind", JString "primary"); ("path", JString path)] end.
Definition decode_workspace_change source := match string_field "kind" source with
| Some "add" => Some AddDirectory | Some "clear" => Some ClearDirectoryEntry
| Some "inherit"=>Some UseInheritedWorkspace
| Some "remove" => option_map RemoveDirectory (string_field "path" source)
| Some "primary" => option_map ChoosePrimary (string_field "path" source)
| _ => None end.
Definition view_entry_key e occurrence view := (editor_key e ++ "/activity/" ++ show_natural occurrence ++ "/" ++ match view with
| PrincipalView => "principal" | SearchView _ => "search" | InspectionView => "inspection"
| DecisionView name => "decision/" ++ name | ParameterView name _ => "parameter/" ++ name
| SourceView name => "source/" ++ name end)%string.
Definition activity_panel_key e occurrence :=
  (editor_key e ++ "/activity/" ++ show_natural occurrence ++ "/panel")%string.
Definition view_eq_dec : forall (a b : view_intent), {a=b}+{a<>b}.
Proof. decide equality; apply string_dec. Defined.

Inductive parameter_entry := OpenEntry | DisplayEntry.
Record parameter {e} (parent : decision e) := OwnedParameter {
  parameter_subject : subject e;
  parameter_prerequisite : denote (subject_kind (decision_subject parent));
  parameter_form : parameter_entry;
  parameter_owned : subject_object (decision_subject parent) = subject_object parameter_subject
}.
Arguments OwnedParameter {e parent}.
Arguments parameter_subject {e parent}.
Arguments parameter_prerequisite {e parent}.
Arguments parameter_form {e parent}.
Definition parameter_active {e parent} (p : parameter (e:=e) parent) :=
  match decision_selected parent with None=>false|Some value=>
    Json.equal (encode_value _ value) (encode_value _ (parameter_prerequisite p)) end.
Record decision_group (e : editor) := DecisionGroup {
  root_decision : decision e;
  dependent_decisions : list (dependency root_decision);
  owned_parameters : list (parameter root_decision)
}.
Arguments DecisionGroup {e}.
Arguments root_decision {e}.
Arguments dependent_decisions {e}.
Arguments owned_parameters {e}.
Record editing_observation (e : editor) := EditingObservation {
  editing_draft : draft;
  editing_owner : owner editing_draft = e;
  editing_original : option json;
  editing_pending : bool;
  editing_changed : bool;
  editing_assessment : assessment e;
  editing_information : list (observation e)
}.
Arguments EditingObservation {e}.
Arguments editing_draft {e}.
Arguments editing_original {e}.
Arguments editing_pending {e}.
Arguments editing_changed {e}.
Arguments editing_assessment {e}.
Arguments editing_information {e}.
Inductive activity (e : editor) :=
| ComparisonActivity (property : property e) (decisions : decision_group e)
    (owned : property_owner property = subject_object (decision_subject (root_decision decisions)))
    (assessment : assessment e) (catalogue:list Selvedge.Kernel.Domain.profile)
| ExplanationActivity (property : property e) (decisions : decision_group e)
    (owned : property_owner property = subject_object (decision_subject (root_decision decisions)))
    (assessment : assessment e) (catalogue:list Selvedge.Kernel.Domain.profile)
| EditingActivity (edit : editing_observation e).
Arguments ComparisonActivity {e}.
Arguments ExplanationActivity {e}.
Arguments EditingActivity {e}.
Definition activity_property {e} (a : activity e) := match a with
| ComparisonActivity property _ _ _ _ | ExplanationActivity property _ _ _ _ => Some property
| EditingActivity _ => None end.
Definition activity_group {e} (a : activity e) := match a with
| ComparisonActivity _ group _ _ _ | ExplanationActivity _ group _ _ _ => Some group
| EditingActivity _ => None end.
Definition activity_editing {e} (a : activity e) := match a with EditingActivity edit=>Some edit|_=>None end.
Definition activity_assessment {e} (a : activity e) := match a with
| ComparisonActivity _ _ _ assessment _ | ExplanationActivity _ _ _ assessment _ => assessment
| EditingActivity edit => editing_assessment edit end.
Definition activity_catalog {e}(a:activity e):=match a with
|ComparisonActivity _ _ _ _ catalogue|ExplanationActivity _ _ _ _ catalogue=>catalogue
|EditingActivity _=>[]end.
Definition model_comparison {e}(a:activity e):=match a with
|ComparisonActivity property _ _ _ _=>match meaning(subject_description(observed_subject(principal property)))with
  ProfileSelection=>true|_=>false end|_=>false end.
Definition initial_view {e}(a:activity e):=
  if model_comparison a && Nat.ltb 8 (List.length(filter(fun profile=>negb(ModelCapabilities.is_codex_auto_review profile))(activity_catalog a)))
  then SearchView ""else PrincipalView.
Definition activity_information {e} (a : activity e) := match activity_property a with
| Some property => principal property :: related property
| None => match activity_editing a with Some edit=>editing_information edit|None=>[]end end.
Definition active_decisions {e} (group : decision_group e) :=
  root_decision group :: map (@dependency_child e (root_decision group))
    (filter dependency_applies (dependent_decisions group)).
Definition active_parameters {e} (group : decision_group e) :=
  map (fun p=>(parameter_subject p,parameter_form p))
    (filter parameter_active (owned_parameters group)).
Definition activity_decisions {e} (a : activity e) :=
  match activity_group a with Some group=>active_decisions group|None=>[]end.
Definition activity_parameters {e} (a : activity e) :=
  match activity_group a with Some group=>active_parameters group|None=>[]end.
Definition profile_caption profile := match string_field "name" profile with
|Some name=>name|None=>text "key" profile end.
Definition typed_alternative {e} (s : subject e) raw caption explanation refusal supporting : option (alternative s) :=
  value <- decode_value (subject_kind s) raw ;;
  Some (Alternative value caption explanation refusal supporting).
Definition listed_alternative {e} (s : subject e) raw caption explanation refusal supporting :=
  match typed_alternative s raw caption explanation refusal supporting with Some value=>[value]|None=>[]end.
Definition catalog world := flat_map (fun raw=>match Selvedge.Kernel.Codec.parse_profile raw with
|Some profile=>[profile]|None=>[]end) (items "profiles" world).
Definition model_catalog world := filter(fun profile=>negb(ModelCapabilities.is_codex_auto_review profile))(catalog world).
Definition reviewer_catalog world := filter ModelCapabilities.valid_reviewer_profile(catalog world).
Definition reviewer_for d world committed :=
  let reviewer:=match owner d,committed with
    |Execution task,true=>option_map(fun value=>(value,FrozenTask task))(committed_value task "reviewer_profile" world)
    |_,_=>permission_context d world "reviewer_profile"end in
  match reviewer with
  | Some (JString key,_) => match ModelSelection.observed_profile world key with
    |Some profile=>if ModelCapabilities.valid_reviewer_profile profile then Some profile else hd_error(reviewer_catalog world)
    |None=>hd_error(reviewer_catalog world)end
  | _ => hd_error(reviewer_catalog world) end.
Definition reviewer_assignment d world committed :=
  profile <- reviewer_for d world committed ;;
  subject <- subject_for_role (owner d) ReviewerSelection ;;
  value <- decode_value (subject_kind subject) (JString (Selvedge.Kernel.Domain.profile_key profile)) ;;
  Some (Assignment subject value).
Definition inherited_permission_choice d (s:subject(owner d)) :=
  match subject_kind s with KOptional _=>
    if Json.equal(get(subject_name s)d)JNull then []else
      listed_alternative s JNull "Use inherited permissions"
        "Use this permission group from the owning environment or parent task." None []
  |_=>[]end.
Definition alternatives_for d world committed (s : subject (owner d)) :=
  match meaning (subject_description s) with
  | ProfileSelection => flat_map (fun profile=>let raw:=Selvedge.Kernel.Domain.profile_metadata profile in
      listed_alternative s (JString(Selvedge.Kernel.Domain.profile_key profile))
        (profile_caption raw) (text "description" raw) None []) (model_catalog world)
  | ReasoningSelection => let profile:=match owner d,committed with
      |Execution task,true=>bind(committed_value task "profile" world)as_string
      |_,_=>Some(read_text "profile" d)end in
      flat_map(fun value=>listed_alternative s (JString value) value "" None [])
        (match profile with Some key=>ModelSelection.reasoning_values world key|None=>[]end)
  | ApprovalSelection =>
      inherited_permission_choice d s ++ listed_alternative s (JString "ask-for-approval") "Ask"
        "Bash may request explicit escalation; you decide each request." None [] ++
      (match reviewer_assignment d world committed with
      |Some reviewer=>listed_alternative s (JString "approval-for-me") "Automatic review"
          "The selected reviewing model handles approval requests." None [reviewer]
      |None=>listed_alternative s (JString "approval-for-me") "Automatic review"
          "A configured reviewing model is required." (Some "No automatic review models are available") []end) ++
      listed_alternative s (JString "full-access") "Full access"
        "Bash has unrestricted filesystem and network access." None []
  | ReviewerSelection => flat_map(fun profile=>listed_alternative s
      (JString(Selvedge.Kernel.Domain.profile_key profile))
      (profile_caption(Selvedge.Kernel.Domain.profile_metadata profile)) "" None []) (reviewer_catalog world)
  | FilesystemSelection =>
      inherited_permission_choice d s ++ listed_alternative s (JString "read-only") "Read only" "Bash cannot write files." None [] ++
      listed_alternative s (JString "workspace-write") "Workspace write" "Bash may write within the selected workspace." None []
  | NetworkSelection => listed_alternative s (JBool false) "Network disabled" "" None [] ++
      listed_alternative s (JBool true) "Network enabled" "" None []
  | PrimaryDirectory => match resolved_workspace d world with
      |Some workspace=>flat_map(fun value=>listed_alternative s value (value_or ""(as_string value)) "" None [])(items "roots" workspace)
      |None=>[]end
  | ProjectSelection => listed_alternative s JNull "Environment defaults" "" None [] ++
      flat_map(fun project=>listed_alternative s(value_or JNull(field "project_id" project))
        (text "name" project) "" None [])(items "projects" world)
  | DeliverySelection => listed_alternative s (JString "send") "Send" "Queue a message for this task." None [] ++
      listed_alternative s (JString "steer") "Steer" "Send guidance to the running task." None []
  | _ => [] end.
Definition retain_selected {e} (s:subject e) selected (alternatives:list(alternative s)) :=
  match selected with None=>alternatives|Some value=>
    if existsb(fun candidate=>Json.equal(encode_value _ value)(encode_value _ (alternative_value candidate)))alternatives
    then alternatives else Alternative value "Selected value is unavailable"
      "The original selection is retained for inspection." (Some "The selection is no longer available") [] :: alternatives end.
Definition decision_for d world committed (s:subject(owner d)) :=
  let selected:=bind(current_value d world committed s)(fun value=>decode_value(subject_kind s)(fst value))in
  Decision s selected (retain_selected s selected (alternatives_for d world committed s)).
Definition make_dependency {e} (parent:decision e) (prerequisite:json) (child:decision e) : option (dependency parent).
Proof.
  destruct (decode_value (subject_kind (decision_subject parent)) prerequisite) as [value|].
  - destruct (object_eq_dec (subject_object (decision_subject parent)) (subject_object (decision_subject child))) as [Owned|].
    + exact (Some (Dependency value child Owned)).
    + exact None.
  - exact None.
Defined.
Definition dependent_for d world committed (parent:decision(owner d)) prerequisite role :=
  match subject_for_role(owner d)role with
  |None=>[]|Some subject=>match make_dependency parent prerequisite (decision_for d world committed subject)with
    Some dependency=>[dependency]|None=>[]end end.
Definition make_parameter {e} (parent:decision e) (prerequisite:json) (subject:subject e) (entry:parameter_entry) : option (parameter parent).
Proof.
  destruct (decode_value (subject_kind (decision_subject parent)) prerequisite) as [value|].
  - destruct (object_eq_dec (subject_object (decision_subject parent)) (subject_object subject)) as [Owned|].
    + exact (Some (OwnedParameter subject value entry Owned)).
    + exact None.
  - exact None.
Defined.
Definition parameter_for d (parent:decision(owner d)) prerequisite role entry :=
  match subject_for_role(owner d)role with None=>[]|Some subject=>
    match make_parameter parent prerequisite subject entry with Some parameter=>[parameter]|None=>[]end end.
Definition group_for d world committed (root:decision(owner d)) :=
  let values : list(dependency root)*list(parameter root) :=
  match meaning(subject_description(decision_subject root))with
  |ProfileSelection=>
      let selected:=bind(current_value d world committed(decision_subject root))(fun value=>as_string(fst value))in
      match bind selected(ModelSelection.observed_profile world)with
      |None=>([],[])
      |Some profile=>let prerequisite:=JString(Selvedge.Kernel.Domain.profile_key profile)in
        match Selvedge.Kernel.Domain.profile_policy profile with
        |Selvedge.Kernel.Domain.AdaptivePolicy _=>([],parameter_for d root prerequisite ReasoningSelection DisplayEntry)
        |Selvedge.Kernel.Domain.FixedReasoning=>
          match Selvedge.Kernel.Domain.profile_reasoning_options profile with
          |[]=>([],parameter_for d root prerequisite ReasoningSelection OpenEntry)
          |_ =>(dependent_for d world committed root prerequisite ReasoningSelection,[])end end end
  |ApprovalSelection=>(
      (dependent_for d world committed root (JString "approval-for-me") ReviewerSelection ++
       flat_map(fun selected=>dependent_for d world committed root (JString selected) FilesystemSelection ++
         dependent_for d world committed root (JString selected) NetworkSelection)
         ["ask-for-approval";"approval-for-me"]),[])
  |_ =>([],[])end in
  DecisionGroup root(fst values)(snd values).
Definition editing_original_for d world := match owner d with
|Project _=>project_original d world
|Card(Some id)=>bind(field "board" world)(world_resource "cards" "card_id" id)
|Agent(Some id)=>bind(field "board" world)(world_resource "agents" "agent_id" id)
|TaskGraph(Some id) _=>world_resource "graphs" "graph_id" id world
|WorkName id=>world_resource "works" "work_id" id world
|TitlePrompts=>field "title_settings" world|_=>None end.
Definition draft_observations d world := flat_map(fun f=>match admit_subject(owner d)(field_name(specification f))with
|Some subject=>[observe_subject d world false subject]|None=>[]end)(form_fields(owner d)).
Definition build_activity request d world services pending : option(activity(owner d)) :=
  let assessed:=assess_draft d world services pending in
  match request with
  |EditObject=>if editor_can_submit(owner d)then
      Some(EditingActivity(EditingObservation d eq_refl(editing_original_for d world)pending
        (match owner d with Project _=>project_changed d world|_=>true end)assessed(draft_observations d world)))else None
  |Compare family|Explain family=>
      let committed:=match owner d with Execution _=>true|_=>false end in
      property<-observe_property d world committed family;;
      let root:=decision_for d world committed(observed_subject(principal property))in
      let group:=group_for d world committed root in
      match request with
      |Compare _=>Some(ComparisonActivity property group eq_refl assessed(catalog world))
      |_=>Some(ExplanationActivity property group eq_refl assessed(catalog world))end
  end.
Record admitted_view (e:editor) := AdmittedView {
  admitted_intent:view_intent;
  admitted_subject:option(subject e);
  admitted_completion:completion
}.
Arguments AdmittedView {e}.
Arguments admitted_intent {e}.
Arguments admitted_subject {e}.
Arguments admitted_completion {e}.
Definition admit_view {e}(a:activity e)intent:option(admitted_view e):=
  match intent with
  |PrincipalView=>Some(AdmittedView intent None(match a with EditingActivity _=>CommitAndDiscard|_=>ApplyAndDismiss end))
  |SearchView _=>if model_comparison a then Some(AdmittedView intent None ApplyAndDismiss)else None
  |InspectionView=>Some(AdmittedView intent None ReturnToPrincipal)
  |DecisionView name=>decision<-find(fun decision=>String.eqb name(subject_name(decision_subject decision)))(activity_decisions a);;
      Some(AdmittedView intent(Some(decision_subject decision))ApplyAndReturn)
  |ParameterView name _=>parameter<-find(fun p=>String.eqb name(subject_name(fst p)))(activity_parameters a);;
      match snd parameter with OpenEntry=>Some(AdmittedView intent(Some(fst parameter))CompleteParameterAndReturn)
      |DisplayEntry=>None end
  |SourceView name=>observation<-find(fun observation=>String.eqb name(subject_name(observed_subject observation)))(activity_information a);;
      Some(AdmittedView intent(Some(observed_subject observation))ReturnToInspection)
  end.
Definition choose_json {e}(a:activity e)name value:option(list(assignment e)):=
  decision<-find(fun decision=>String.eqb name(subject_name(decision_subject decision)))(activity_decisions a);;
  candidate<-find(fun candidate=>Json.equal value(encode_value _ (alternative_value candidate)))(decision_alternatives decision);;
  choose candidate.
Definition visible_alternatives {e}(decision:decision e)query:=
  filter(fun candidate=>
    (match decision_selected decision with Some selected=>Json.equal(encode_value _ selected)(encode_value _ (alternative_value candidate))|None=>false end)||
    Search.contains(Search.lower(trim query))
      (Search.lower((alternative_label candidate++" "++
        match encode_value _ (alternative_value candidate)with JString text=>text|value=>TextJson.render_json value end)%string)))
    (decision_alternatives decision).
Definition complete_parameter {e}(a:activity e)name buffer world:option(list(assignment e)):=
  parameter<-find(fun p=>String.eqb name(subject_name(fst p)))(activity_parameters a);;
  match snd parameter with DisplayEntry=>None|OpenEntry=>
    group<-activity_group a;;selected<-decision_selected(root_decision group);;
    key<-as_string(encode_value _ selected);;
    if ModelSelection.permitted world key buffer then
      value<-decode_value(subject_kind(fst parameter))(JString buffer);;
      Some[Assignment(fst parameter)value]else None end.

