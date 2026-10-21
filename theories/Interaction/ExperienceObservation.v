From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Interaction Require Import Codec Identity Forms Experience ModelSelection.
From Selvedge.Kernel Require ModelCapabilities.
Import ListNotations.
Open Scope string_scope.

Definition world_resource collection identity id world :=
  values <- array_field collection world ;;
  find (fun value => match natural_field identity value with
    | Some actual => N.eqb id actual | None => false end) values.
Definition project_resource id world := world_resource "projects" "project_id" id world.
Definition task_resource id world := world_resource "tasks" "id" id world.
Definition environment_settings world := bind (field "defaults" world) (field "settings").
Definition inherited_context d world : option (json * provenance) :=
  match owner d with
  | Message task | Execution task | Fork task =>
      t <- task_resource task world ;; settings <- field "settings" t ;;
      Some (settings, ParentTask task)
  | _ => settings <- environment_settings world ;; Some (settings, EnvironmentDefaults)
  end.
Definition workspace_context d world : option (json * provenance) :=
  match owner d with
  | Project _ => Some (workspace d, DraftChoice)
  | Message task | Execution task => t <- task_resource task world ;;
      settings <- field "settings" t ;; w <- field "workspace" settings ;;
      Some (w, FrozenTask task)
  | _ => match workspace_override d with
    | Some w => Some (w, DraftChoice)
    | None => match natural (get "project_id" d) with
      | Some id => project <- project_resource id world ;;
          w <- field "workspace" project ;; Some (w, ProjectDefaults id)
      | None => context <- inherited_context d world ;;
          w <- field "workspace" (fst context) ;; Some (w, snd context)
      end end
  end.
Definition resolved_workspace d world := option_map fst (workspace_context d world).
Definition permission_context d world name : option (json * provenance) :=
  let sandbox := existsb (String.eqb name) ["sandbox"; "network_access"] in
  let group := if sandbox then "sandbox" else "approval" in
  let member := if String.eqb name "sandbox" || String.eqb name "approval" then "mode" else name in
  match get group d with
  | JNull => context <- inherited_context d world ;;
      source <- field group (fst context) ;;
      Some (value_or JNull (field member source), snd context)
  | _ => Some (get name d, DraftChoice)
  end.
Definition committed_value task name world : option json :=
  t <- task_resource task world ;;
  if String.eqb name "profile" || String.eqb name "reasoning" then field name t
  else settings <- field "settings" t ;;
    if existsb (String.eqb name) ["roots"; "primary_root"] then
      w <- field "workspace" settings ;; field name w
    else if existsb (String.eqb name) ["sandbox"; "network_access"] then
      sandbox <- field "sandbox" settings ;;
      field (if String.eqb name "sandbox" then "mode" else name) sandbox
    else if existsb (String.eqb name) ["approval"; "reviewer_profile"] then
      approval <- field "approval" settings ;;
      Some (value_or JNull (field (if String.eqb name "approval" then "mode" else name) approval))
    else field name settings.

Definition draft_value d world (s : subject (owner d)) : option (json * provenance) :=
  let name := subject_name s in
  match meaning (subject_description s) with
  | PrimaryDirectory | DirectoryCollection => context <- workspace_context d world ;;
      value <- field name (fst context) ;; Some (value, snd context)
  | FilesystemSelection | NetworkSelection | ApprovalSelection | ReviewerSelection =>
      permission_context d world name
  | ProjectSelection => Some (get name d, match natural (get name d) with
      | Some id => ProjectDefaults id | None => EnvironmentDefaults end)
  | _ => Some (get name d, DraftChoice)
  end.
Definition current_value d world committed (s : subject (owner d)) :=
  match owner d, committed with
  | Execution task, true => value <- committed_value task (subject_name s) world ;;
      Some (value, FrozenTask task)
  | _, _ => draft_value d world s end.
Definition current_approval d world committed :=
  match owner d, committed with
  | Execution task, true => committed_value task "approval" world
  | _, _ => option_map fst (permission_context d world "approval") end.
Definition classify_information d world committed (s : subject (owner d)) value :=
  let role := meaning (subject_description s) in
  match role with
  | ProjectSelection => match natural value with
    | None => OptionalAbsence
    | Some id => match project_resource id world with Some _ => Present value
      | None => Unavailable "The selected project is no longer available" end end
  | ProfileSelection => match as_string value with
    | Some "" => RequiredAbsence "Choose a configured model"
    | Some key => match ModelSelection.observed_profile world key with
      | Some _ => Present value | None => Unavailable "The selected model is no longer available" end
    | None => Unavailable "The model observation is invalid" end
  | ReviewerSelection => match current_approval d world committed with
    | Some (JString "approval-for-me") => match as_string value with
      | Some key => match ModelSelection.observed_profile world key with
        | Some profile => if ModelCapabilities.valid_reviewer_profile profile then Present value
            else RequiredAbsence "Choose an available fixed-reasoning review model"
        | None => RequiredAbsence "Choose an available automatic review model" end
      | None => RequiredAbsence "Choose an available automatic review model" end
    | _ => NotApplicable "A reviewing model belongs to Automatic review" end
  | FilesystemSelection | NetworkSelection =>
    match current_approval d world committed with
    | Some (JString "full-access") => NotApplicable "Full access has no active sandbox limit"
    | _ => match value with JNull => OptionalAbsence | _ => Present value end end
  | _ => match value with JNull => OptionalAbsence | _ => Present value end
  end.
Definition observe_subject d world committed (s : subject (owner d)) :=
  match current_value d world committed s with
  | None => Observation s (Unavailable "The owning context is no longer available")
      (match owner d with Execution task => FrozenTask task | _ => DraftChoice end)
  | Some (value, source) => Observation s (classify_information d world committed s value) source
  end.

Inductive property_family := ProjectFamily | WorkspaceFamily | ModelFamily
| PermissionFamily | DeliveryFamily | ScalarFamily.
Definition family role := match role with
| ProjectSelection | ProjectWorktreePreference => ProjectFamily
| PrimaryDirectory | DirectoryCollection | DirectoryEntry | TaskEnvironmentSelection => WorkspaceFamily
| ProfileSelection | ReasoningSelection => ModelFamily
| FilesystemSelection | NetworkSelection | ApprovalSelection | ReviewerSelection => PermissionFamily
| DeliverySelection => DeliveryFamily | Scalar => ScalarFamily end.
Definition family_eq_dec : forall (a b : property_family), {a=b}+{a<>b}.
Proof. decide equality. Defined.
Definition meaning_eq_dec : forall (a b : field_meaning), {a=b}+{a<>b}.
Proof. decide equality. Defined.
Definition subject_for_role (e : editor) (role : field_meaning) : option (subject e).
Proof.
  destruct (find (fun f => if meaning_eq_dec (meaning f) role then true else false)
    (form_fields e)) as [f|] eqn:Found.
  - refine (Some (Subject f _)). apply find_some in Found. exact (proj1 Found).
  - exact None.
Defined.
Definition family_principal kind := match kind with
| ProjectFamily => ProjectSelection | WorkspaceFamily => PrimaryDirectory
| ModelFamily => ProfileSelection | PermissionFamily => ApprovalSelection
| DeliveryFamily => DeliverySelection | ScalarFamily => Scalar end.
Definition own_observations {e} (first : observation e) (rest : list (observation e)) :
    { values : list (observation e) | Forall (fun item =>
      subject_object (observed_subject item) = subject_object (observed_subject first)) values }.
Proof.
  refine (exist _ (filter (fun item => same_object
    (subject_object (observed_subject item)) (subject_object (observed_subject first))) rest) _).
  apply Forall_forall. intros item Member. apply filter_In in Member.
  destruct Member as [_ Same]. unfold same_object in Same.
  destruct (object_eq_dec (subject_object (observed_subject item))
    (subject_object (observed_subject first))); auto; discriminate.
Defined.
Definition observe_property d world committed kind : option (property (owner d)) :=
  subject <- subject_for_role (owner d) (family_principal kind) ;;
  let first := observe_subject d world committed subject in
  let names := map (fun f => field_name (specification f))
    (filter (fun f => if family_eq_dec (family (meaning f)) kind then true else false)
      (form_fields (owner d))) in
  let rest := flat_map (fun name => match admit_subject (owner d) name with
    | Some other => if String.eqb (subject_name subject) (subject_name other) then []
      else [observe_subject d world committed other] | None => [] end) names in
  let admitted := own_observations first rest in
  Some (Property first (proj1_sig admitted) (proj2_sig admitted)).
Definition provenance_description source := match source with
| EnvironmentDefaults => "Environment defaults"
| ProjectDefaults project => "Project #" ++ show_natural project ++ " defaults"
| ParentTask task => "Inherited from task #" ++ show_natural task
| DraftChoice => "Chosen for this editor"
| FrozenTask task => "Recorded execution settings of task #" ++ show_natural task
| CatalogEntry profile => "Configured model " ++ profile
| MessageDelivery task => "Message delivery for task #" ++ show_natural task end.
Definition information_value value := match value with
| Present value => Some value | _ => None end.
Definition information_reason value := match value with
| RequiredAbsence reason | Unavailable reason | NotApplicable reason => Some reason
| _ => None end.
Definition property_source_observations {e} (p : property e) := principal p :: related p.
Definition property_source_description {e} (p : property e) :=
  map (fun item => (subject_description (observed_subject item),
    provenance_description (observed_provenance item))) (property_source_observations p).
