From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects Schema Utf8.
From Selvedge.Kernel Require Import Numbers Context Domain Codec.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Fixpoint text_fields (value : list (string * json)) : option (list (string * string)) :=
 match value with
 | [] => Some []
 | (key,JString text) :: rest =>
   if Utf8.well_formed text then option_map (cons (key,text)) (text_fields rest) else None
 | _ => None end.
Definition parse_fields (value : json) :=
 match value with JObject fields => text_fields fields | _ => None end.
Definition find_text := ContextTypes.find_text.
Definition construct_snapshot (definition : ContextTypes.definition)
 (identity : list (string * string)) (revision : string) (fields : list (string * string)) :=
 match admit_key definition identity with
 | Some key => admit_snapshot key revision fields | None => None end.
Definition global_guidance_fields :=
 [Field "path" KText; Field "revision" KText; Field "content" KText].
Definition global_guidance_from_fields (values : fields global_guidance_fields) :=
 construct_snapshot Context.global_guidance [("path",head values)]
   (head (tail values)) [("content",head (tail (tail values)))].

Definition registered_key_candidate (source : json) : option context_key :=
 match string_field "type" source, parse_fields (value_or_null "identity" source),
 find (fun definition => JsonObjects.equivalent (definition_json definition) (value_or_null "definition" source)) definitions with
 | Some kind, Some fields, Some definition =>
   if String.eqb kind (definition_kind definition)
   then admit_key definition fields else None
 | _,_,_ => None end.
Definition parse_key := registered_key_candidate.
Definition snapshot_candidate (source : json) : option snapshot :=
 match registered_key_candidate (value_or_null "key" source), string_field "revision" source,
 parse_fields (value_or_null "fields" (value_or_null "value" source)) with
 | Some key, Some revision, Some fields =>
   if String.eqb (text_default "type" (value_or_null "value" source) "") (definition_kind (key_definition key))
   then admit_snapshot key revision fields else None
 | _,_,_ => None end.
Definition parse_edit (source : json) : option text_edit :=
 match natural_field "start" source, string_field "removed" source, string_field "inserted" source with
 | Some start, Some removed, Some inserted =>
   if Utf8.well_formed removed && Utf8.well_formed inserted then Some (TextEdit start removed inserted) else None
 | _,_,_ => None end.
Definition parse_field_patch (source : json) : option field_patch :=
 match string_field "field" source, array_field "edits" source with
 | Some name, Some edits => option_map (FieldPatch name) (traverse parse_edit edits)
 | _,_ => None end.
Definition parse_patch (source : json) :=
 match string_field "type" source, array_field "fields" source with
 | Some "field_edits", Some fields => traverse parse_field_patch fields
 | _,_ => None end.
Definition parse_observation (source : json) : option context_observation :=
 match string_field "type" source with
 | Some "present" => Some (match snapshot_candidate (value_or_null "snapshot" source),
     parse_patch (value_or_null "patch" source) with
   | Some snapshot,Some patch => Present snapshot patch
   (* DEFENSE: An external source can supply malformed fields or a patch;
      reject that source while allowing the other observations to be consumed. *)
   | _,_ => RejectedObservation end)
 | Some "absent" => option_map Absent (parse_key (value_or_null "key" source))
 | Some "failure" => match parse_key (value_or_null "key" source), string_field "message" source with
   | Some key,Some message => Some (ObservationFailure key message) | _,_ => None end
 | _ => None end.
Definition same_key (left right : context_key) := Json.equal (key_json left) (key_json right).
Definition find_source definition identity (values : list snapshot) := find (fun value =>
 Json.equal (definition_json definition) (definition_json (key_definition (snapshot_key value))) &&
 Json.equal (fields_json identity) (fields_json (key_identity (snapshot_key value)))) values.
Definition find_snapshot (key : context_key) := find_source (key_definition key) (key_identity key).
Definition remove_snapshot (key : context_key) (values : list snapshot) := filter (fun value => negb (same_key key (snapshot_key value))) values.
Fixpoint apply_edits (edits : list text_edit) (cursor : N) (source : list (N * string)) : option (list (N * string)) :=
 match edits with
 | [] => Some source
 | edit :: rest =>
   let offset := (edit_start edit - cursor)%N in
   if N.leb cursor (edit_start edit) && N.leb offset (N.of_nat (List.length source)) then
   match Utf8.chunks (edit_removed edit), Utf8.chunks (edit_inserted edit) with
   | Some removed, Some inserted =>
     let prefix := firstn (N.to_nat offset) source in
     let remaining := skipn (N.to_nat offset) source in
     if String.eqb (Utf8.render_chunks (firstn (List.length removed) remaining)) (edit_removed edit) &&
        Nat.leb (List.length removed) (List.length remaining) then
       option_map (fun tail => prefix ++ inserted ++ tail)
         (apply_edits rest (edit_start edit + N.of_nat (List.length removed))%N (skipn (List.length removed) remaining))
     else None
   | _,_ => None end else None
 end.
Definition apply_text (source : string) (edits : list text_edit) :=
 match Utf8.chunks source with Some source => option_map Utf8.render_chunks (apply_edits edits 0 source) | None => None end.
Fixpoint replace_text (name value : string) (fields : list (string * string)) :=
 match fields with [] => [] | (key,previous) :: rest =>
 if String.eqb name key then (key,value) :: rest else (key,previous) :: replace_text name value rest end.
Fixpoint apply_fields (patches : list field_patch) (fields : list (string * string)) :=
 match patches with
 | [] => Some fields
 | patch :: rest => match find_text (patch_field patch) fields with
   | None => None
   | Some text => match apply_text text (patch_edits patch) with
     | None => None | Some text => apply_fields rest (replace_text (patch_field patch) text fields) end end
 end.
Definition patches_editable (key : context_key) (patches : list field_patch) :=
 unique_names (map patch_field patches) && forallb (fun patch => existsb (fun spec =>
 String.eqb (patch_field patch) (value_name spec) &&
 match value_from spec with IdentityValue _ => false | _ => true end) (definition_fields (key_definition key))) patches.
Fixpoint ordered_edits (cursor : N) (values : list text_edit) := match values with
 | [] => true | value :: rest => match Utf8.scalar_count (edit_removed value) with
   | None => false | Some removed => N.leb cursor (edit_start value) &&
      Utf8.well_formed (edit_inserted value) &&
      ordered_edits (edit_start value + N.of_nat removed)%N rest end end.
Definition valid_patch (key : context_key) (values : list field_patch) :=
 patches_editable key values && forallb (fun value => ordered_edits 0 (patch_edits value)) values.
Definition apply_change (change : context_change) (values : list snapshot) : list snapshot :=
 match change with
 | Introduce value => value :: remove_snapshot (snapshot_key value) values
 | Remove key base => match find_snapshot key values with
   | None => values
   | Some previous =>
     (* DEFENSE: A side return can carry a removal captured before the parent
        admitted a newer observation of the same source. *)
     if String.eqb (snapshot_revision previous) base then remove_snapshot key values else values
   end
 | Amend target base _ => let key := snapshot_key target in
   match find_snapshot key values with
   | None => values
   | Some previous =>
     (* DEFENSE: A side return can carry an amendment captured against an older
        baseline; installing its target must not overwrite newer context. *)
     if String.eqb (snapshot_revision previous) base
     then target :: remove_snapshot key values else values end
 end.
Definition bindings (history : list message) := fold_left
 (fun values message => match message with ContextObservation change => apply_change change values | _ => values end) history [].
Definition observation_changes (observation : context_observation) (values : list snapshot) : option (list context_change) :=
 match observation with
 | RejectedObservation => None
 | ObservationFailure _ _ => Some []
 | Absent key => match find_snapshot key values with
   | None => Some [] | Some previous => Some [Remove key (snapshot_revision previous)] end
 | Present current patch =>
   let key := snapshot_key current in
   match find_snapshot key values with
   | None => Some [Introduce current]
   | Some previous =>
     (* Observation revisions may change while content stays identical, notably
        when the initial configured snapshot receives its first IO hash. *)
     if Json.equal (fields_json (snapshot_fields current)) (fields_json (snapshot_fields previous)) then Some [] else
     if negb (String.eqb (snapshot_revision current) (snapshot_revision previous)) && valid_patch key patch then
     match apply_fields patch (snapshot_fields previous) with
     | Some fields => if Json.equal (fields_json fields) (fields_json (snapshot_fields current))
       then Some [Amend current (snapshot_revision previous) patch] else None
     | None => None end else None
   end
 end.
(** Internal sources supply one typed target. The selected previous binding
    fixes the baseline, and its declaration fixes the field order in both views. *)
Definition replace_snapshot (target : snapshot) (values : list snapshot) : option context_change :=
 match find_snapshot (snapshot_key target) values with
 | None => Some (Introduce target)
 | Some previous => let patches := flat_map (fun pair =>
   let '(before,after) := pair in
   if String.eqb (snd before) (snd after) then []
   else [FieldPatch (fst after) [TextEdit 0 (snd before) (snd after)]])
   (combine (snapshot_fields previous) (snapshot_fields target)) in
   match patches with [] => None | _ => Some (Amend target (snapshot_revision previous) patches) end
 end.
Definition source_diagnostics (observation : context_observation) :=
 match observation with
 | ObservationFailure _ message => [String.append "Context source observation failed: " message]
 | _ => [] end.
Fixpoint observe_all (observations : list context_observation) (values : list snapshot)
 : list context_change * list string :=
 match observations with
 | [] => ([],[])
 | observation :: rest => match observation_changes observation values with
   | None =>
     (* DEFENSE: An invalid revision or patch belongs to one observed source;
        reject it without discarding accepted updates from the other sources. *)
     let '(changes,diagnostics) := observe_all rest values in
     (changes,"Context update rejected: invalid revision or patch for tracked source." :: diagnostics)
   | Some changes =>
     let '(later,diagnostics) := observe_all rest
       (fold_left (fun values change => apply_change change values) changes values) in
     (changes ++ later,source_diagnostics observation ++ diagnostics) end
 end.

(* DEFENSE: A registered NativeText descriptor can arrive with an obsolete
   revision or changed body; only its exact advertised snapshot authorizes UI. *)
Definition interactive_available (values : list snapshot) :=
 match definition_observer Context.interactive_markdown with
 | NativeText revision content => existsb (fun value =>
    Json.equal (definition_json (key_definition (snapshot_key value)))
      (definition_json Context.interactive_markdown) &&
    String.eqb (snapshot_revision value) revision &&
    Json.equal (fields_json (snapshot_fields value)) (fields_json [("content",content)])) values
 | _ => false end.
