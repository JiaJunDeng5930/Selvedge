From Stdlib Require Import String List Bool NArith Numbers.DecimalString.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema DeclarationFields.
From Selvedge.Programming Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.
Inductive scope := Global | PrimaryWorkspace | EveryWorkspace.
Record discovery_policy := DiscoveryPolicy {
  discovery_files : list string;
  discovery_directories : list string;
  discovery_markers : list string;
  discovery_excluded : list string;
  discovery_max_directories : N;
  discovery_max_entries : N;
  discovery_max_sources : N;
  discovery_max_bytes : N
}.
Inductive observer := NativeState | NativeText (revision content : string)
 | ConfigText (setting : string) | ConfigFiles (setting : string)
 | HomeFile (relative : string) | WorkspaceFile (relative : string)
 | HomeGuidance (policy : discovery_policy) | PrimaryGuidance (policy : discovery_policy)
 | WorkspaceGuidance (policy : discovery_policy) | HomeSkills (policy : discovery_policy)
 | WorkspaceSkills (policy : discovery_policy).
Inductive identity_source := Constant (value : string) | SourcePath | WorkspaceRoot | HomeRoot.
Record identity_field := IdentityField { identity_name : string; identity_from : identity_source; identity_required : bool }.
Inductive value_source := Body | Metadata (field : string) | ObservationField (field : string) | IdentityValue (field : string).
Record value_field := ValueField { value_name : string; value_from : value_source; value_required : bool }.
(** The context language admits a declaration once. Static declarations use
    the same constructor, whose fixed structural contract is solved by reduction. *)
Record definition_body := DefinitionBody { body_kind : string; body_semantics : string;
 body_scope : scope; body_observer : observer;
 body_identity : list identity_field; body_fields : list value_field }.
Definition nonempty_text value := negb (String.eqb value "").
Definition named_fields names := Schema.unique_names names && forallb nonempty_text names.
Definition well_defined (body : definition_body) :=
 let identity := body_identity body in let names := map identity_name identity in
 let fields := body_fields body in
 nonempty_text (body_kind body) && nonempty_text (body_semantics body) &&
 negb (Nat.eqb (List.length identity) 0) && negb (Nat.eqb (List.length fields) 0) &&
 (match body_scope body with Global => true | _ => existsb (fun field =>
   match identity_from field with WorkspaceRoot => identity_required field | _ => false end) identity end) &&
 named_fields names && named_fields (map value_name fields) &&
 forallb (fun field => match value_from field with
   | IdentityValue name => existsb (String.eqb name) names | _ => true end) fields &&
 forallb (fun field => match identity_from field with
   | Constant value => negb (identity_required field) || nonempty_text value | _ => true end) identity.
Definition definition := D.checked well_defined.
Definition definition_kind (value : definition) := body_kind (proj1_sig value).
Definition definition_semantics (value : definition) := body_semantics (proj1_sig value).
Definition definition_scope (value : definition) := body_scope (proj1_sig value).
Definition definition_observer (value : definition) := body_observer (proj1_sig value).
Definition definition_identity (value : definition) := body_identity (proj1_sig value).
Definition definition_fields (value : definition) := body_fields (proj1_sig value).
Class DeclaredDefinition (body : definition_body) : Prop := { declaration_checked : well_defined body = true }.
Arguments declaration_checked {body} {_}.
#[global] Hint Extern 0 (DeclaredDefinition _) => constructor; reflexivity : typeclass_instances.
Definition ContextDefinition kind semantics scope observer identity fields
 `{DeclaredDefinition (DefinitionBody kind semantics scope observer identity fields)} : definition :=
 exist _ (DefinitionBody kind semantics scope observer identity fields) declaration_checked.
Definition admit_definition := D.admit well_defined.
Lemma natural_nonempty value : nonempty_text (Numbers.show_natural value) = true.
Proof. unfold nonempty_text, Numbers.show_natural; destruct (N.to_uint value); reflexivity. Qed.
#[global] Hint Extern 1 (DeclaredDefinition _) => constructor;
 cbv -[nonempty_text Numbers.show_natural]; rewrite ?natural_nonempty; reflexivity : typeclass_instances.

Definition required_text := D.Text (D.TextConstraints 1 D.maximum_natural D.maximum_natural false false false None).
Definition text_declaration (required : bool) : D.t := if required then required_text else D.Value KText.
Definition text_value required := D.denote (text_declaration required).
Definition text_of required : text_value required -> string :=
 match required as required return text_value required -> string with
 | true => fun value => proj1_sig value | false => fun value => value end.
Definition identity_declaration (field : identity_field) := match identity_from field with
 | Constant value => D.Const (JString value) | _ => text_declaration (identity_required field) end.
Definition identity_text (field : identity_field) : D.denote (identity_declaration field) -> string :=
 match identity_from field as source return D.denote (match source with
 | Constant value => D.Const (JString value) | _ => text_declaration (identity_required field) end) -> string with
 | Constant value => fun _ => value | _ => text_of (identity_required field) end.
Definition identity_properties fields := map (fun field => F.required (identity_name field) (identity_declaration field)) fields.
Fixpoint identity_members fields : F.values (identity_properties fields) -> list (string * string) :=
 match fields as fields return F.values (identity_properties fields) -> list (string * string) with
 | [] => fun _ => []
 | first :: rest => fun values => (identity_name first,identity_text first (fst values)) :: identity_members rest (snd values) end.
Record context_key := ContextKey { key_definition : definition;
 key_values : D.denote (D.Object (identity_properties (definition_identity key_definition))) }.
Definition key_identity key := identity_members (definition_identity (key_definition key)) (proj1_sig (key_values key)).
Fixpoint find_text (name : string) (fields : list (string * string)) : option string := match fields with [] => None | (key,value)::rest =>
 if String.eqb name key then Some value else find_text name rest end.
Definition scoped_root key := match find (fun field => match identity_from field with
 | WorkspaceRoot => true | _ => false end) (definition_identity (key_definition key)) with
 | Some field => find_text (identity_name field) (key_identity key) | None => None end.
Definition policy_paths policy root := map (fun file =>
 if String.eqb root "/" then root ++ file else root ++ "/" ++ file) (discovery_files policy).
Definition path_declaration (required : bool) paths := D.Text (D.TextConstraints
 (if required then 1 else 0) D.maximum_natural D.maximum_natural false false false (Some paths)).
Definition observation_declaration key name required :=
 match definition_observer (key_definition key) with
 | PrimaryGuidance policy => if String.eqb name "path" then
   match scoped_root key with Some root => path_declaration required (policy_paths policy root) | None => D.Reject end
   else text_declaration required
 | _ => text_declaration required end.
Definition observation_text key name required : D.denote (observation_declaration key name required) -> string.
Proof.
 unfold observation_declaration; destruct (definition_observer (key_definition key));
 try exact (text_of required).
 destruct (String.eqb name "path"); [|exact (text_of required)].
 destruct (scoped_root key); [exact (fun value => proj1_sig value)|exact (fun impossible => match impossible with end)].
Defined.
Definition value_declaration key field := match value_from field with
 | Body | Metadata _ => text_declaration (value_required field)
 | ObservationField name => observation_declaration key name (value_required field)
 | IdentityValue name => match find_text name (key_identity key) with
   | Some value => D.Const (JString value) | None => D.Reject end end.
Definition value_text key field : D.denote (value_declaration key field) -> string.
Proof.
 unfold value_declaration; destruct (value_from field).
 - exact (text_of (value_required field)).
 - exact (text_of (value_required field)).
 - exact (observation_text key field0 (value_required field)).
 - destruct (find_text field0 (key_identity key)) as [value|];
   [exact (fun _ => value)|exact (fun impossible => match impossible with end)].
Defined.
Definition value_properties key fields := map (fun field => F.required (value_name field) (value_declaration key field)) fields.
Fixpoint value_members key fields : F.values (value_properties key fields) -> list (string * string) :=
 match fields as fields return F.values (value_properties key fields) -> list (string * string) with
 | [] => fun _ => []
 | first :: rest => fun values => (value_name first,value_text key first (fst values)) :: value_members key rest (snd values) end.
(** External revision strings and internal counters share one wire spelling;
    counters are constructed from their number without reparsing that spelling. *)
Definition revision_declaration := D.Union [required_text;D.NaturalText 0 None].
Definition revision := D.denote revision_declaration.
Definition revision_text (value : revision) := match value with
 | inl value => proj1_sig value | inr (inl value) => Numbers.show_natural (proj1_sig value)
 | inr (inr impossible) => match impossible with end end.
Definition counter_revision (value : N) : revision.
Proof. refine (inr (inl (exist _ value _))); unfold D.natural_range; rewrite Bool.andb_true_r; apply N.leb_le; apply N.le_0_l. Defined.
Definition initial_revision : revision := inl (exist _ "initial" eq_refl).
Record snapshot := Snapshot { snapshot_key : context_key; snapshot_version : revision;
 snapshot_values : D.denote (D.Object (value_properties snapshot_key (definition_fields (key_definition snapshot_key)))) }.
Definition snapshot_revision value := revision_text (snapshot_version value).
Definition snapshot_fields value := value_members (snapshot_key value)
 (definition_fields (key_definition (snapshot_key value))) (proj1_sig (snapshot_values value)).
Definition strings_json values := JObject (map (fun value => (fst value,JString (snd value))) values).
Definition admit_key definition fields := option_map (ContextKey definition)
 (D.decode (D.Object (identity_properties (definition_identity definition))) (strings_json fields)).
Definition admit_snapshot key revision fields :=
 match D.decode revision_declaration (JString revision),
 D.decode (D.Object (value_properties key (definition_fields (key_definition key)))) (strings_json fields) with
 | Some revision,Some fields => Some (Snapshot key revision fields) | _,_ => None end.

Record text_edit := TextEdit { edit_start : N; edit_removed : string; edit_inserted : string }.
Record field_patch := FieldPatch { patch_field : string; patch_edits : list text_edit }.
Inductive context_change := Introduce (value : snapshot)
 | Amend (target : snapshot) (base : string) (patches : list field_patch)
 | Remove (key : context_key) (base : string).
Inductive context_observation := Present (value : snapshot) (patches : list field_patch)
 | Absent (key : context_key) | ObservationFailure (key : context_key) (message : string)
 | RejectedObservation.
