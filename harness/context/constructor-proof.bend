import Base
import ./MODEL.bend as C
import ./CONTRACT.bend as Spec
import ./patch-proof.bend as Patch
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J

# The source declaration determines the complete snapshot representation. Checked
# construction supplies both that origin equation and actual schema admission.
def checked_snapshot(+valid: Bool, +definition: C.Definition, +identity: +List<C.FieldValue>,
  +revision: String, +fields: +List<C.FieldValue>,
  checked: {C.valid_snapshot(C.Snapshot{C.ContextKey{definition, identity}, revision, C.Record{C.definition_kind(definition), fields}}) == valid : Bool}) ->
  Spec.ConstructedSnapshot(C.snapshot_checked(valid, C.Snapshot{C.ContextKey{definition, identity}, revision, C.Record{C.definition_kind(definition), fields}}), definition, identity, revision, fields):
  match valid:
    case False{}: Unit{}
    case True{}: Spec.SnapshotConstruction{{==}, checked}

def construction(+definition: C.Definition, +identity: +List<C.FieldValue>, +revision: String, +fields: +List<C.FieldValue>) ->
  Spec.ConstructedSnapshot(C.construct_snapshot(definition, identity, revision, fields), definition, identity, revision, fields):
  checked_snapshot(C.valid_snapshot(C.Snapshot{C.ContextKey{definition, identity}, revision, C.Record{C.definition_kind(definition), fields}}), definition, identity, revision, fields, {==})

# Wire fields are ordinary records; this round trip holds for arbitrary names,
# text and kinds rather than enumerating installed context definitions.
def fields_roundtrip(+fields: +List<C.FieldValue>) ->
  {C.field_values(C.fields_json(fields)) == Some{fields} : Maybe<&2, +List<C.FieldValue>>}:
  match fields:
    case Nil{}: {==}
    case Con{C.FieldValue{+name, +text}, +rest}:
      Equal.cong(Maybe<&2, +List<C.FieldValue>>, Maybe<&2, +List<C.FieldValue>>,
        (tail => C.prepend_field_value(Some{C.FieldValue{name, text}}, tail)),
        C.field_values(C.fields_json(rest)), Some{rest}, fields_roundtrip(rest))

def value_roundtrip(+value: C.Value) ->
  {C.value(C.value_json(value)) == Some{value} : Maybe<&2, C.Value>}:
  match value:
    case C.Record{+kind, +fields}:
      Equal.cong(Maybe<&2, +List<C.FieldValue>>, Maybe<&2, C.Value>,
        (result => C.parsed_value(J.Text{kind}, result)),
        C.field_values(C.fields_json(fields)), Some{fields}, fields_roundtrip(fields))

def edited_head_names(+name: String, text: String, +result: Maybe<&2, String>, +rest: +List<C.FieldValue>) ->
  Spec.FieldNames(C.prepend_field_result(name, result, rest), C.FieldValue{name, text} <> rest):
  match result:
    case None{}: Unit{}
    case Some{updated}: {==}

def unchanged_head_names(+name: String, +text: String, +result: Maybe<&2, +List<C.FieldValue>>, +rest: +List<C.FieldValue>,
  induction: Spec.FieldNames(result, rest)) ->
  Spec.FieldNames(C.prepend_unchanged(C.FieldValue{name, text}, result), C.FieldValue{name, text} <> rest):
  match result:
    case None{}: Unit{}
    case Some{updated}:
      Equal.cong(+List<String>, +List<String>, (names => name <> names),
        C.value_field_names(updated), C.value_field_names(rest), induction)

def selected_names(+same: Bool, +actual: String, +text: String, +rest: +List<C.FieldValue>,
  +edits: +List<C.TextEdit>, +tail: Maybe<&2, +List<C.FieldValue>>, induction: Spec.FieldNames(tail, rest)) ->
  Spec.FieldNames(C.edit_field_selected(same, actual, text, rest, edits, tail), C.FieldValue{actual, text} <> rest):
  match same:
    case True{}: edited_head_names(actual, text, C.apply_text(0n, text, edits), rest)
    case False{}: unchanged_head_names(actual, text, tail, rest, induction)

def edit_names(+fields: +List<C.FieldValue>, +name: String, +edits: +List<C.TextEdit>) ->
  Spec.FieldNames(C.edit_field(fields, name, edits), fields):
  match fields:
    case Nil{}: Unit{}
    case Con{C.FieldValue{+actual, +text}, +rest}:
      selected_names(String.eq(actual, name), actual, text, rest, edits,
        C.edit_field(rest, name, edits), edit_names(rest, name, edits))

def compose_names(+result: Maybe<&2, +List<C.FieldValue>>, +original: +List<C.FieldValue>, +middle: +List<C.FieldValue>,
  first: {C.value_field_names(middle) == C.value_field_names(original) : +List<String>},
  second: Spec.FieldNames(result, middle)) -> Spec.FieldNames(result, original):
  match result:
    case None{}: Unit{}
    case Some{updated}:
      Equal.trans(+List<String>, C.value_field_names(updated), C.value_field_names(middle), C.value_field_names(original), second, first)

def field_patch_names_go(+patches: +List<C.FieldPatch>, +result: Maybe<&2, +List<C.FieldValue>>, +original: +List<C.FieldValue>,
  preserved: Spec.FieldNames(result, original)) ->
  Spec.FieldNames(C.apply_fields_go(patches, result), original):
  match patches result:
    case Nil{} Some{fields}: preserved
    case Con{C.FieldPatch{+name, +edits}, +rest} Some{+fields}:
      field_patch_names_go(rest, C.edit_field(fields, name, edits), original,
        compose_names(C.edit_field(fields, name, edits), original, fields, preserved, edit_names(fields, name, edits)))
    case _ None{}: Unit{}

def field_patch_names(+fields: +List<C.FieldValue>, +patches: +List<C.FieldPatch>) ->
  Spec.FieldNames(C.apply_fields(fields, patches), fields):
  field_patch_names_go(patches, Some{fields}, fields, {==})

def record_schema(+valid: Bool, +kind: String, +fields: +List<C.FieldValue>, +result: Maybe<&2, +List<C.FieldValue>>,
  preserved: Spec.FieldNames(result, fields)) ->
  Spec.PatchedSchema(C.record_result(valid, kind, result), C.Record{kind, fields}):
  match valid result:
    case True{} Some{updated}: Spec.ValueSchema{{==}, preserved}
    case True{} None{}: Unit{}
    case False{} _: Unit{}

# The shared interpreter may edit text but cannot change kind, field order or
# field names. Identity projections are separately protected by source admission.
def patch_schema(+value: C.Value, +patch: C.Patch) -> Spec.PatchedSchema(C.apply_patch(value, patch), value):
  match value patch:
    case C.Record{+kind, +fields} C.FieldEdits{+patches}:
      record_schema(C.unique_names(C.patch_field_names(patches)), kind, fields, C.apply_fields(fields, patches), field_patch_names(fields, patches))

def definition_evidence(+definition: C.Definition) -> Spec.DefinitionEvidence<definition>:
  Spec.DefinitionEvidence{
    identity => revision => fields => construction(definition, identity, revision, fields),
    value_roundtrip, patch_schema,
    Patch.accepted_snapshot,
    identity => base => value => observed => patch => Patch.observed_amendment_patch(C.ContextKey{definition, identity}, base, value, observed, patch),
    bindings => identity => base => previous_revision => previous => revision => patch => value => found => base_matches => patched =>
      Patch.apply_amendment(bindings, C.ContextKey{definition, identity}, base, previous_revision, previous, revision, patch, value, found, base_matches, patched)}

def family(+definition: C.Definition) -> Categories.Membership<C.Definition, (definition => Spec.DefinitionEvidence<definition>)>:
  Categories.Membership{definition, definition_evidence(definition)}
