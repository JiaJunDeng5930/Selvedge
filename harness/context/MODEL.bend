import Base
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/string-equality.bend as Text

# The definition is an executable schema and observation program. New kinds use
# this finite construction language instead of extending history's constructors.
type Scope is Data:
  GlobalScope{}
  WorkspaceScope{}
  PrimaryWorkspaceScope{}

# Directory discovery is bounded as one collection. A failed or incomplete
# collection preserves its previous accepted bindings instead of withdrawing them.
type DiscoveryPolicy is Data:
  DiscoveryPolicy{files: +List<String>, directories: +List<String>, repository_markers: +List<String>, excluded: +List<String>, max_directories: Nat, max_entries: Nat, max_sources: Nat, max_bytes: Nat}

def discovery_excluded() -> +List<String>:
  [".git", ".hg", ".svn", "node_modules", "vendor", ".build", "dist", "build", "target", ".next", ".cache", ".workpad", "__pycache__", ".venv", "venv", ".agents", ".claude"]

def guidance_policy() -> DiscoveryPolicy:
  DiscoveryPolicy{["AGENTS.override.md", "AGENTS.md"], Nil{}, [".git"], discovery_excluded(), 10000n, 100000n, 1024n, 262144n}

def home_skills_policy() -> DiscoveryPolicy:
  DiscoveryPolicy{["SKILL.md"], ["skills", ".agents/skills"], [".git"], discovery_excluded(), 10000n, 100000n, 1024n, 262144n}

def workspace_skills_policy() -> DiscoveryPolicy:
  DiscoveryPolicy{["SKILL.md"], [".agents/skills", ".claude/skills"], [".git"], discovery_excluded(), 10000n, 100000n, 1024n, 262144n}

type Observer is Data:
  ConfigText{setting: String}
  HomeFile{relative: String}
  WorkspaceFile{relative: String}
  ConfigFiles{setting: String}
  HomeGuidance{policy: DiscoveryPolicy}
  PrimaryGuidance{policy: DiscoveryPolicy}
  WorkspaceGuidance{policy: DiscoveryPolicy}
  HomeSkills{policy: DiscoveryPolicy}
  WorkspaceSkills{policy: DiscoveryPolicy}

type IdentitySource is Data:
  Constant{value: String}
  SourcePath{}
  WorkspaceRoot{}
  HomeRoot{}

type IdentityField is Data:
  IdentityField{name: String, source: IdentitySource, required: Bool}

type TextSource is Data:
  Body{}
  Metadata{field: String}
  ObservationField{field: String}

type ValueField is Data:
  TextField{name: String, source: TextSource, required: Bool}
  IdentityValue{name: String, identity_name: String}

type Definition is Data:
  Definition{kind: String, semantics: String, scope: Scope, observer: Observer, identity: +List<IdentityField>, fields: +List<ValueField>}

def record_context(kind: String, semantics: String, scope: Scope, observer: Observer, identity: +List<IdentityField>, fields: +List<ValueField>) -> Definition:
  Definition{kind, semantics, scope, observer, identity, fields}

def text_context(kind: String, semantics: String, scope: Scope, observer: Observer, identity: +List<IdentityField>) -> Definition:
  record_context(kind, semantics, scope, observer, identity, [TextField{"content", Body{}, False{}}])

type FieldValue is Data:
  FieldValue{name: String, text: String}

type Key is Data:
  ContextKey{definition: Definition, identity: +List<FieldValue>}

type Value is Data:
  Record{kind: String, fields: +List<FieldValue>}

type Snapshot is Data:
  Snapshot{key: Key, revision: String, value: Value}

# Text offsets address the original baseline. Removed text authenticates the
# edit and makes deletions explicit in the model's appended context message.
type TextEdit is Data:
  TextEdit{start: Nat, removed: String, inserted: String}

type FieldPatch is Data:
  FieldPatch{field: String, edits: +List<TextEdit>}

type Patch is Data:
  FieldEdits{fields: +List<FieldPatch>}

type Change is Data:
  Introduce{snapshot: Snapshot}
  Amend{key: Key, base_revision: String, revision: String, patch: Patch}
  Remove{key: Key, base_revision: String}

type Observation is Data:
  Present{snapshot: Snapshot, patch: Patch}
  Absent{key: Key}
  ObservationFailure{key: Key, message: String}

def definition_kind(definition: Definition) -> String:
  Definition{kind, semantics, scope, observer, identity, fields} = definition
  kind

def definition_identity(definition: Definition) -> +List<IdentityField>:
  Definition{kind, semantics, scope, observer, identity, fields} = definition
  identity

def definition_fields(definition: Definition) -> +List<ValueField>:
  Definition{kind, semantics, scope, observer, identity, fields} = definition
  fields

def key_definition(key: Key) -> Definition:
  ContextKey{definition, identity} = key
  definition

def key_identity(key: Key) -> +List<FieldValue>:
  ContextKey{definition, identity} = key
  identity

def key_kind(key: Key) -> String:
  definition_kind(key_definition(key))

def workspace_identity(schema: +List<IdentityField>, values: +List<FieldValue>) -> Maybe<&2, String>:
  match schema values:
    case Con{IdentityField{name, WorkspaceRoot{}, required}, rest} Con{FieldValue{actual, text}, tail}: Some{text}
    case Con{head, rest} Con{value, tail}: workspace_identity(rest, tail)
    case _ _: None{}

def scoped_workspace(scope: Scope, schema: +List<IdentityField>, values: +List<FieldValue>) -> Maybe<&2, String>:
  match scope:
    case GlobalScope{}: None{}
    case WorkspaceScope{}: workspace_identity(schema, values)
    case PrimaryWorkspaceScope{}: workspace_identity(schema, values)

def key_workspace(key: Key) -> Maybe<&2, String>:
  ContextKey{Definition{kind, semantics, scope, observer, identity, fields}, values} = key
  scoped_workspace(scope, identity, values)

def scoped_primary_workspace(scope: Scope, schema: +List<IdentityField>, values: +List<FieldValue>) -> Maybe<&2, String>:
  match scope:
    case PrimaryWorkspaceScope{}: workspace_identity(schema, values)
    case _: None{}

def key_primary_workspace(key: Key) -> Maybe<&2, String>:
  ContextKey{Definition{kind, semantics, scope, observer, identity, fields}, values} = key
  scoped_primary_workspace(scope, identity, values)

def value_fields(value: Value) -> +List<FieldValue>:
  Record{kind, fields} = value
  fields

def field_name(field: ValueField) -> String:
  match field:
    case TextField{name, source, required}: name
    case IdentityValue{name, identity_name}: name

def identity_name(field: IdentityField) -> String:
  IdentityField{name, source, required} = field
  name

def select_field(same: Bool, text: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match same:
    case True{}: Some{text}
    case False{}: rest

def field_lookup(fields: +List<FieldValue>, +name: String) -> Maybe<&2, String>:
  match fields:
    case Nil{}: None{}
    case Con{FieldValue{actual, text}, rest}: select_field(String.eq(actual, name), text, field_lookup(rest, name))

def optional_text(result: Maybe<&2, String>) -> String:
  match result:
    case Some{text}: text
    case None{}: ""

def field_text(fields: +List<FieldValue>, name: String) -> String:
  optional_text(field_lookup(fields, name))

def same_fields(left: +List<FieldValue>, right: +List<FieldValue>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{FieldValue{a, b}, rest} Con{FieldValue{x, y}, tail}: String.eq(a, x) && Text.string_equal(b, y) && same_fields(rest, tail)
    case _ _: False{}

def scope_json(scope: Scope) -> J.Json:
  match scope:
    case GlobalScope{}: J.Text{"global"}
    case WorkspaceScope{}: J.Text{"workspace"}
    case PrimaryWorkspaceScope{}: J.Text{"primary_workspace"}

def discovery_policy_json(policy: DiscoveryPolicy) -> J.Json:
  DiscoveryPolicy{files, directories, repository_markers, excluded, max_directories, max_entries, max_sources, max_bytes} = policy
  J.Object{[J.Field{"files", J.Array{J.text_items(files)}}, J.Field{"directories", J.Array{J.text_items(directories)}},
    J.Field{"repository_markers", J.Array{J.text_items(repository_markers)}}, J.Field{"excluded", J.Array{J.text_items(excluded)}},
    J.Field{"max_directories", J.nat(max_directories)}, J.Field{"max_entries", J.nat(max_entries)}, J.Field{"max_sources", J.nat(max_sources)}, J.Field{"max_bytes", J.nat(max_bytes)}]}

def discovery_observer_json(kind: String, policy: DiscoveryPolicy) -> J.Json:
  J.Object{[J.Field{"type", J.Text{kind}}, J.Field{"policy", discovery_policy_json(policy)}]}

def observer_json(observer: Observer) -> J.Json:
  match observer:
    case ConfigText{setting}: J.Object{[J.Field{"type", J.Text{"config_text"}}, J.Field{"setting", J.Text{setting}}]}
    case HomeFile{relative}: J.Object{[J.Field{"type", J.Text{"home_file"}}, J.Field{"relative", J.Text{relative}}]}
    case WorkspaceFile{relative}: J.Object{[J.Field{"type", J.Text{"workspace_file"}}, J.Field{"relative", J.Text{relative}}]}
    case ConfigFiles{setting}: J.Object{[J.Field{"type", J.Text{"config_files"}}, J.Field{"setting", J.Text{setting}}]}
    case HomeGuidance{policy}: discovery_observer_json("home_guidance", policy)
    case PrimaryGuidance{policy}: discovery_observer_json("primary_guidance", policy)
    case WorkspaceGuidance{policy}: discovery_observer_json("workspace_guidance", policy)
    case HomeSkills{policy}: discovery_observer_json("home_skills", policy)
    case WorkspaceSkills{policy}: discovery_observer_json("workspace_skills", policy)

def identity_source_json(source: IdentitySource) -> J.Json:
  match source:
    case Constant{value}: J.Object{[J.Field{"type", J.Text{"constant"}}, J.Field{"value", J.Text{value}}]}
    case SourcePath{}: J.Object{[J.Field{"type", J.Text{"source_path"}}]}
    case WorkspaceRoot{}: J.Object{[J.Field{"type", J.Text{"workspace_root"}}]}
    case HomeRoot{}: J.Object{[J.Field{"type", J.Text{"home_root"}}]}

def identity_field_json(field: IdentityField) -> J.Json:
  IdentityField{name, source, required} = field
  J.Object{[J.Field{"name", J.Text{name}}, J.Field{"source", identity_source_json(source)}, J.Field{"required", J.Boolean{required}}]}

def text_source_json(source: TextSource) -> J.Json:
  match source:
    case Body{}: J.Object{[J.Field{"type", J.Text{"body"}}]}
    case Metadata{field}: J.Object{[J.Field{"type", J.Text{"metadata"}}, J.Field{"field", J.Text{field}}]}
    case ObservationField{field}: J.Object{[J.Field{"type", J.Text{"observation_field"}}, J.Field{"field", J.Text{field}}]}

def value_field_json(field: ValueField) -> J.Json:
  match field:
    case TextField{name, source, required}: J.Object{[J.Field{"name", J.Text{name}}, J.Field{"source", text_source_json(source)}, J.Field{"required", J.Boolean{required}}]}
    case IdentityValue{name, identity_name}: J.Object{[J.Field{"name", J.Text{name}}, J.Field{"source", J.Object{[J.Field{"type", J.Text{"identity"}}, J.Field{"field", J.Text{identity_name}}]}}]}

def definition_json(definition: Definition) -> J.Json:
  Definition{kind, semantics, scope, observer, identity, fields} = definition
  J.Object{[J.Field{"kind", J.Text{kind}}, J.Field{"semantics", J.Text{semantics}}, J.Field{"scope", scope_json(scope)}, J.Field{"observer", observer_json(observer)}, J.Field{"identity", J.Array{Std.map(~IdentityField, ~J.Json, ~identity_field_json, identity)}}, J.Field{"fields", J.Array{Std.map(~ValueField, ~J.Json, ~value_field_json, fields)}}]}

def definitions_json(definitions: +List<Definition>) -> J.Json:
  J.Array{Std.map(~Definition, ~J.Json, ~definition_json, definitions)}

def same_key(left: Key, right: Key) -> Bool:
  ContextKey{a, left} = left
  ContextKey{b, right} = right
  J.same(definition_json(a), definition_json(b)) && same_fields(left, right)

def same_value(left: Value, right: Value) -> Bool:
  Record{a, left} = left
  Record{b, right} = right
  String.eq(a, b) && same_fields(left, right)

def has_name(names: +List<String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case Con{actual, rest}: String.eq(actual, name) || has_name(rest, name)

def unique_names(names: +List<String>) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{+name, +rest}: Bool.not(String.eq(name, "")) && Bool.not(has_name(rest, name)) && unique_names(rest)

def identity_names(fields: +List<IdentityField>) -> +List<String>:
  Std.map(~IdentityField, ~String, ~identity_name, fields)

def field_names(fields: +List<ValueField>) -> +List<String>:
  Std.map(~ValueField, ~String, ~field_name, fields)

def value_field_names(fields: +List<FieldValue>) -> +List<String>:
  match fields:
    case Nil{}: Nil{}
    case Con{FieldValue{name, text}, rest}: name <> value_field_names(rest)

def identity_references(fields: +List<ValueField>, +names: +List<String>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{TextField{name, source, required}, rest}: identity_references(rest, names)
    case Con{IdentityValue{name, identity_name}, rest}: has_name(names, identity_name) && identity_references(rest, names)

def nonempty_identity(fields: +List<IdentityField>) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{head, tail}: True{}

def nonempty_fields(fields: +List<ValueField>) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{head, tail}: True{}

def has_workspace_identity(identity: +List<IdentityField>) -> Bool:
  match identity:
    case Nil{}: False{}
    case Con{IdentityField{name, WorkspaceRoot{}, True{}}, rest}: True{}
    case Con{head, rest}: has_workspace_identity(rest)

def valid_scope(scope: Scope, identity: +List<IdentityField>) -> Bool:
  match scope:
    case GlobalScope{}: True{}
    case WorkspaceScope{}: has_workspace_identity(identity)
    case PrimaryWorkspaceScope{}: has_workspace_identity(identity)

def valid_definition(+definition: Definition) -> Bool:
  Definition{kind, semantics, scope, observer, +identity, +fields} = definition
  Bool.not(String.eq(kind, "")) && Bool.not(String.eq(semantics, "")) &&
    nonempty_identity(identity) && nonempty_fields(fields) &&
    valid_scope(scope, identity) && unique_names(identity_names(identity)) && unique_names(field_names(fields)) && identity_references(fields, identity_names(identity))

def required_text(required: Bool, text: String) -> Bool:
  match required:
    case True{}: Bool.not(String.eq(text, ""))
    case False{}: True{}

def identity_source_matches(source: IdentitySource, text: String) -> Bool:
  match source:
    case Constant{value}: String.eq(value, text)
    case _: True{}

def valid_identity(schema: +List<IdentityField>, fields: +List<FieldValue>) -> Bool:
  match schema fields:
    case Nil{} Nil{}: True{}
    case Con{IdentityField{a, source, required}, rest} Con{FieldValue{b, +text}, tail}:
      String.eq(a, b) && required_text(required, text) && identity_source_matches(source, text) && valid_identity(rest, tail)
    case _ _: False{}

def field_matches(schema: ValueField, field: FieldValue, identity: +List<FieldValue>) -> Bool:
  match schema field:
    case TextField{a, source, required} FieldValue{b, text}: String.eq(a, b) && required_text(required, text)
    case IdentityValue{a, name} FieldValue{b, text}: String.eq(a, b) && String.eq(field_text(identity, name), text)

def valid_fields(schema: +List<ValueField>, fields: +List<FieldValue>, +identity: +List<FieldValue>) -> Bool:
  match schema fields:
    case Nil{} Nil{}: True{}
    case Con{field, rest} Con{value, tail}: field_matches(field, value, identity) && valid_fields(rest, tail, identity)
    case _ _: False{}

def source_value(key: Key, value: Value) -> Bool:
  ContextKey{+definition, +identity} = key
  Record{kind, fields} = value
  valid_definition(definition) && String.eq(definition_kind(definition), kind) && valid_identity(definition_identity(definition), identity) && valid_fields(definition_fields(definition), fields, identity)

def valid_key(+key: Key) -> Bool:
  ContextKey{+definition, identity} = key
  valid_definition(definition) && valid_identity(definition_identity(definition), identity)

def valid_snapshot(snapshot: Snapshot) -> Bool:
  Snapshot{key, revision, value} = snapshot
  Bool.not(String.eq(revision, "")) && source_value(key, value)

def snapshot_checked(valid: Bool, snapshot: Snapshot) -> Maybe<&2, Snapshot>:
  match valid:
    case True{}: Some{snapshot}
    case False{}: None{}

def construct_snapshot(+definition: Definition, identity: +List<FieldValue>, revision: String, fields: +List<FieldValue>) -> Maybe<&2, Snapshot>:
  +snapshot: Snapshot = Snapshot{ContextKey{definition, identity}, revision, Record{definition_kind(definition), fields}}
  snapshot_checked(valid_snapshot(snapshot), snapshot)

def text_length_acc(text: String, count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{head, tail}: text_length_acc(tail, 1n+count)

def text_length(text: String) -> Nat:
  text_length_acc(text, 0n)

def text_drop(count: Nat, text: String) -> Maybe<&2, String>:
  match count text:
    case 0n other: Some{other}
    case 1n+rest SCon{head, tail}: text_drop(rest, tail)
    case _ _: None{}

type PatchCursor is Data:
  Seeking{offset: Nat, remaining: String, reversed: String, edits: +List<TextEdit>}
  Erasing{offset: Nat, remaining: String, reversed: String, removed: String, inserted: String, edits: +List<TextEdit>}
  Rejected{}

def reverse_into(text: String, tail: String) -> String:
  match text:
    case SNil{}: tail
    case SCon{head, rest}: reverse_into(rest, SCon{head, tail})

def seek_position(order: Cmp, offset: Nat, remaining: String, reversed: String, start: Nat, removed: String, inserted: String, edits: +List<TextEdit>) -> PatchCursor:
  match order remaining:
    case EQ{} remaining: Erasing{offset, remaining, reversed, removed, inserted, edits}
    case LT{} SCon{head, tail}: Seeking{1n+offset, tail, SCon{head, reversed}, TextEdit{start, removed, inserted} <> edits}
    case _ _: Rejected{}

def erased_character(same: Bool, offset: Nat, remaining: String, reversed: String, removed: String, inserted: String, edits: +List<TextEdit>) -> PatchCursor:
  match same:
    case True{}: Erasing{offset, remaining, reversed, removed, inserted, edits}
    case False{}: Rejected{}

def same_character(compared: (Char & Char) & Cmp) -> Bool:
  ((left, right), order) = compared
  Cmp.is_eq(order)

def patch_step(cursor: PatchCursor) -> PatchCursor:
  match cursor:
    case Seeking{offset, remaining, reversed, Nil{}}: Seeking{offset, remaining, reversed, Nil{}}
    case Seeking{+offset, remaining, reversed, Con{TextEdit{+start, removed, inserted}, rest}}:
      seek_position(Nat.cmp(offset, start), offset, remaining, reversed, start, removed, inserted, rest)
    case Erasing{offset, remaining, reversed, SNil{}, inserted, edits}:
      Seeking{offset, remaining, reverse_into(inserted, reversed), edits}
    case Erasing{offset, SCon{a, tail}, reversed, SCon{b, removed}, inserted, edits}:
      erased_character(same_character(Char.cmp(a, b)), 1n+offset, tail, reversed, removed, inserted, edits)
    case _: Rejected{}

# Each step consumes a baseline character or enters/exits one edit. The bound is
# independent of inserted text and rejects incomplete or overlapping patches.
def apply_text_go(fuel: Nat, cursor: PatchCursor) -> Maybe<&2, String>:
  match fuel cursor:
    case _ Seeking{offset, remaining, reversed, Nil{}}: Some{reverse_into(reversed, remaining)}
    case _ Rejected{}: None{}
    case 1n+budget other: apply_text_go(budget, patch_step(other))
    case _ _: None{}

def apply_text(cursor: Nat, +text: String, +edits: +List<TextEdit>) -> Maybe<&2, String>:
  apply_text_go(Nat.add(text_length(text), Nat.mul(2n, List.length(&2, TextEdit, edits))), Seeking{cursor, text, "", edits})

def prepend_field_result(name: String, result: Maybe<&2, String>, rest: +List<FieldValue>) -> Maybe<&2, +List<FieldValue>>:
  match result:
    case Some{text}: Some{FieldValue{name, text} <> rest}
    case None{}: None{}

def prepend_unchanged(field: FieldValue, result: Maybe<&2, +List<FieldValue>>) -> Maybe<&2, +List<FieldValue>>:
  match result:
    case Some{rest}: Some{field <> rest}
    case None{}: None{}

def edit_field_selected(same: Bool, actual: String, text: String, rest: +List<FieldValue>, edits: +List<TextEdit>, tail: Maybe<&2, +List<FieldValue>>) -> Maybe<&2, +List<FieldValue>>:
  match same:
    case True{}: prepend_field_result(actual, apply_text(0n, text, edits), rest)
    case False{}: prepend_unchanged(FieldValue{actual, text}, tail)

def edit_field(fields: +List<FieldValue>, +name: String, +edits: +List<TextEdit>) -> Maybe<&2, +List<FieldValue>>:
  match fields:
    case Nil{}: None{}
    case Con{FieldValue{+actual, +text}, +rest}: edit_field_selected(String.eq(actual, name), actual, text, rest, edits, edit_field(rest, name, edits))

def apply_fields_go(patches: +List<FieldPatch>, fields: Maybe<&2, +List<FieldValue>>) -> Maybe<&2, +List<FieldValue>>:
  match patches fields:
    case Nil{} Some{fields}: Some{fields}
    case Con{FieldPatch{name, edits}, rest} Some{fields}: apply_fields_go(rest, edit_field(fields, name, edits))
    case _ _: None{}

def apply_fields(fields: +List<FieldValue>, patches: +List<FieldPatch>) -> Maybe<&2, +List<FieldValue>>:
  apply_fields_go(patches, Some{fields})

def patch_field_names(fields: +List<FieldPatch>) -> +List<String>:
  match fields:
    case Nil{}: Nil{}
    case Con{FieldPatch{name, edits}, rest}: name <> patch_field_names(rest)

def record_result(valid: Bool, kind: String, fields: Maybe<&2, +List<FieldValue>>) -> Maybe<&2, Value>:
  match valid fields:
    case True{} Some{fields}: Some{Record{kind, fields}}
    case _ _: None{}

def apply_patch(value: Value, patch: Patch) -> Maybe<&2, Value>:
  Record{kind, fields} = value
  FieldEdits{+patches} = patch
  record_result(unique_names(patch_field_names(patches)), kind, apply_fields(fields, patches))

def editable_field(fields: +List<ValueField>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{TextField{actual, source, required}, rest}: String.eq(actual, name) || editable_field(rest, name)
    case Con{IdentityValue{actual, identity_name}, rest}: editable_field(rest, name)

def editable_patches(+schema: +List<ValueField>, patches: +List<FieldPatch>) -> Bool:
  match patches:
    case Nil{}: True{}
    case Con{FieldPatch{name, edits}, rest}: editable_field(schema, name) && editable_patches(schema, rest)

def valid_patch(key: Key, patch: Patch) -> Bool:
  FieldEdits{+fields} = patch
  unique_names(patch_field_names(fields)) && editable_patches(definition_fields(key_definition(key)), fields)

def snapshot_key(snapshot: Snapshot) -> Key:
  Snapshot{key, revision, value} = snapshot
  key

def find_selected(same: Bool, snapshot: Snapshot, rest: Maybe<&2, Snapshot>) -> Maybe<&2, Snapshot>:
  match same:
    case True{}: Some{snapshot}
    case False{}: rest

def find(bindings: +List<Snapshot>, +key: Key) -> Maybe<&2, Snapshot>:
  match bindings:
    case Nil{}: None{}
    case Con{+snapshot, rest}: find_selected(same_key(snapshot_key(snapshot), key), snapshot, find(rest, key))


def keep_binding(keep: Bool, snapshot: Snapshot, rest: +List<Snapshot>) -> +List<Snapshot>:
  match keep:
    case True{}: snapshot <> rest
    case False{}: rest

def remove_binding(bindings: +List<Snapshot>, +key: Key) -> +List<Snapshot>:
  match bindings:
    case Nil{}: Nil{}
    case Con{+snapshot, rest}: keep_binding(Bool.not(same_key(snapshot_key(snapshot), key)), snapshot, remove_binding(rest, key))


def put(+snapshot: Snapshot, +bindings: +List<Snapshot>) -> +List<Snapshot>:
  snapshot <> remove_binding(bindings, snapshot_key(snapshot))

def patch_matches(result: Maybe<&2, Value>, observed: Value) -> Bool:
  match result:
    case None{}: False{}
    case Some{value}: same_value(value, observed)

def snapshot_value(snapshot: Snapshot) -> Value:
  Snapshot{key, revision, value} = snapshot
  value

def snapshot_revision(snapshot: Snapshot) -> String:
  Snapshot{key, revision, value} = snapshot
  revision

def introduce_checked(valid: Bool, snapshot: Snapshot) -> Maybe<&2, Change>:
  match valid:
    case True{}: Some{Introduce{snapshot}}
    case False{}: None{}

def amend_checked(valid: Bool, key: Key, base: String, observed: Snapshot, patch: Patch) -> Maybe<&2, Change>:
  match valid:
    case True{}: Some{Amend{key, base, snapshot_revision(observed), patch}}
    case False{}: None{}

def observed_change(previous: Maybe<&2, Snapshot>, +observed: Snapshot, +patch: Patch) -> Maybe<&2, Change>:
  match previous:
    case None{}: introduce_checked(valid_snapshot(observed), observed)
    case Some{Snapshot{+key, +base, +value}}:
      amend_checked(valid_snapshot(observed) && same_key(key, snapshot_key(observed)) && Bool.not(same_value(value, snapshot_value(observed))) &&
        Bool.not(String.eq(base, snapshot_revision(observed))) && valid_patch(key, patch) && patch_matches(apply_patch(value, patch), snapshot_value(observed)), key, base, observed, patch)

def absent_change(previous: Maybe<&2, Snapshot>) -> Maybe<&2, Change>:
  match previous:
    case None{}: None{}
    case Some{Snapshot{key, revision, value}}: Some{Remove{key, revision}}

def observation_change(bindings: +List<Snapshot>, observation: Observation) -> Maybe<&2, Change>:
  match observation:
    case Present{+snapshot, patch}: observed_change(find(bindings, snapshot_key(snapshot)), snapshot, patch)
    case Absent{key}: absent_change(find(bindings, key))
    case ObservationFailure{key, message}: None{}

def same_revision(snapshot: Maybe<&2, Snapshot>, base: String) -> Bool:
  match snapshot:
    case None{}: False{}
    case Some{Snapshot{key, revision, value}}: String.eq(base, revision)

def replace_checked(valid: Bool, value: Maybe<&2, Value>, key: Key, revision: String, bindings: +List<Snapshot>) -> +List<Snapshot>:
  match valid value:
    case True{} Some{value}: put(Snapshot{key, revision, value}, bindings)
    case _ _: bindings

def remove_checked(valid: Bool, key: Key, bindings: +List<Snapshot>) -> +List<Snapshot>:
  match valid:
    case True{}: remove_binding(bindings, key)
    case False{}: bindings

def replace_patched(previous: Maybe<&2, Snapshot>, key: Key, base: String, revision: String, patch: Patch, bindings: +List<Snapshot>) -> +List<Snapshot>:
  match previous:
    case None{}: bindings
    case Some{Snapshot{old_key, old_revision, value}}:
      replace_checked(String.eq(old_revision, base), apply_patch(value, patch), key, revision, bindings)

def apply_change(change: Change, +bindings: +List<Snapshot>) -> +List<Snapshot>:
  match change:
    case Introduce{snapshot}: put(snapshot, bindings)
    case Amend{+key, base, revision, patch}: replace_patched(find(bindings, key), key, base, revision, patch, bindings)
    case Remove{+key, base}: remove_checked(same_revision(find(bindings, key), base), key, bindings)


def field_value_json(field: FieldValue) -> J.Field:
  FieldValue{name, text} = field
  J.Field{name, J.Text{text}}

def fields_json(fields: +List<FieldValue>) -> J.Json:
  J.Object{Std.map(~FieldValue, ~J.Field, ~field_value_json, fields)}

def key_json(key: Key) -> J.Json:
  ContextKey{+definition, identity} = key
  J.Object{[J.Field{"type", J.Text{definition_kind(definition)}}, J.Field{"definition", definition_json(definition)}, J.Field{"identity", fields_json(identity)}]}

def value_json(value: Value) -> J.Json:
  Record{kind, fields} = value
  J.Object{[J.Field{"type", J.Text{kind}}, J.Field{"fields", fields_json(fields)}]}

def snapshot_json(snapshot: Snapshot) -> J.Json:
  Snapshot{key, revision, value} = snapshot
  J.Object{[J.Field{"key", key_json(key)}, J.Field{"revision", J.Text{revision}}, J.Field{"value", value_json(value)}]}

def snapshots_json(snapshots: +List<Snapshot>) -> J.Json:
  J.Array{Std.map(~Snapshot, ~J.Json, ~snapshot_json, snapshots)}

def edit_json(edit: TextEdit) -> J.Json:
  TextEdit{start, removed, inserted} = edit
  J.Object{[J.Field{"start", J.nat(start)}, J.Field{"removed", J.Text{removed}}, J.Field{"inserted", J.Text{inserted}}]}

def edits_json(edits: +List<TextEdit>) -> J.Json:
  J.Array{Std.map(~TextEdit, ~J.Json, ~edit_json, edits)}

def field_patch_json(field: FieldPatch) -> J.Json:
  FieldPatch{name, edits} = field
  J.Object{[J.Field{"field", J.Text{name}}, J.Field{"edits", edits_json(edits)}]}

def patch_json(patch: Patch) -> J.Json:
  FieldEdits{fields} = patch
  J.Object{[J.Field{"type", J.Text{"field_edits"}}, J.Field{"fields", J.Array{Std.map(~FieldPatch, ~J.Json, ~field_patch_json, fields)}}]}

def change_json(change: Change) -> J.Json:
  match change:
    case Introduce{snapshot}: J.Object{[J.Field{"type", J.Text{"introduce"}}, J.Field{"snapshot", snapshot_json(snapshot)}]}
    case Amend{key, base, revision, patch}: J.Object{[J.Field{"type", J.Text{"amend"}}, J.Field{"key", key_json(key)}, J.Field{"base_revision", J.Text{base}}, J.Field{"revision", J.Text{revision}}, J.Field{"patch", patch_json(patch)}]}
    case Remove{key, base}: J.Object{[J.Field{"type", J.Text{"remove"}}, J.Field{"key", key_json(key)}, J.Field{"base_revision", J.Text{base}}]}

def parsed_scope(item: J.Json) -> Maybe<&2, Scope>:
  match item:
    case J.Text{"global"}: Some{GlobalScope{}}
    case J.Text{"workspace"}: Some{WorkspaceScope{}}
    case J.Text{"primary_workspace"}: Some{PrimaryWorkspaceScope{}}
    case _: None{}

def prepend_discovery_string(head: J.Json, tail: Maybe<&2, +List<String>>) -> Maybe<&2, +List<String>>:
  match head tail:
    case J.Text{text} Some{tail}: Some{text <> tail}
    case _ _: None{}

def discovery_string_items(items: +List<J.Json>) -> Maybe<&2, +List<String>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_discovery_string(head, discovery_string_items(tail))

def discovery_strings(item: J.Json) -> Maybe<&2, +List<String>>:
  match item:
    case J.Array{items}: discovery_string_items(items)
    case _: None{}

def parsed_discovery_policy(files: Maybe<&2, +List<String>>, directories: Maybe<&2, +List<String>>, repository_markers: Maybe<&2, +List<String>>, excluded: Maybe<&2, +List<String>>,
  max_directories: Maybe<&2, Nat>, max_entries: Maybe<&2, Nat>, max_sources: Maybe<&2, Nat>, max_bytes: Maybe<&2, Nat>) -> Maybe<&2, DiscoveryPolicy>:
  match files directories repository_markers excluded max_directories max_entries max_sources max_bytes:
    case Some{files} Some{directories} Some{repository_markers} Some{excluded} Some{max_directories} Some{max_entries} Some{max_sources} Some{max_bytes}:
      Some{DiscoveryPolicy{files, directories, repository_markers, excluded, max_directories, max_entries, max_sources, max_bytes}}
    case _ _ _ _ _ _ _ _: None{}

def discovery_policy(+item: J.Json) -> Maybe<&2, DiscoveryPolicy>:
  parsed_discovery_policy(discovery_strings(J.get(item, "files")), discovery_strings(J.get(item, "directories")),
    discovery_strings(J.get(item, "repository_markers")), discovery_strings(J.get(item, "excluded")),
    J.natural(J.get(item, "max_directories")), J.natural(J.get(item, "max_entries")), J.natural(J.get(item, "max_sources")), J.natural(J.get(item, "max_bytes")))

def parsed_observer(kind: String, setting: J.Json, relative: J.Json, policy: Maybe<&2, DiscoveryPolicy>) -> Maybe<&2, Observer>:
  match kind setting relative policy:
    case "config_text" J.Text{setting} _ _: Some{ConfigText{setting}}
    case "config_files" J.Text{setting} _ _: Some{ConfigFiles{setting}}
    case "home_file" _ J.Text{relative} _: Some{HomeFile{relative}}
    case "workspace_file" _ J.Text{relative} _: Some{WorkspaceFile{relative}}
    case "home_guidance" _ _ Some{policy}: Some{HomeGuidance{policy}}
    case "primary_guidance" _ _ Some{policy}: Some{PrimaryGuidance{policy}}
    case "workspace_guidance" _ _ Some{policy}: Some{WorkspaceGuidance{policy}}
    case "home_skills" _ _ Some{policy}: Some{HomeSkills{policy}}
    case "workspace_skills" _ _ Some{policy}: Some{WorkspaceSkills{policy}}
    case _ _ _ _: None{}

def observer(+item: J.Json) -> Maybe<&2, Observer>:
  parsed_observer(J.text(J.get(item, "type")), J.get(item, "setting"), J.get(item, "relative"), discovery_policy(J.get(item, "policy")))

def parsed_identity_source(kind: String, value: J.Json) -> Maybe<&2, IdentitySource>:
  match kind value:
    case "constant" J.Text{value}: Some{Constant{value}}
    case "source_path" _: Some{SourcePath{}}
    case "workspace_root" _: Some{WorkspaceRoot{}}
    case "home_root" _: Some{HomeRoot{}}
    case _ _: None{}

def identity_source(+item: J.Json) -> Maybe<&2, IdentitySource>:
  parsed_identity_source(J.text(J.get(item, "type")), J.get(item, "value"))

def parsed_identity_field(name: J.Json, source: Maybe<&2, IdentitySource>, required: J.Json) -> Maybe<&2, IdentityField>:
  match name source required:
    case J.Text{name} Some{source} J.Boolean{required}: Some{IdentityField{name, source, required}}
    case _ _ _: None{}

def identity_field(+item: J.Json) -> Maybe<&2, IdentityField>:
  parsed_identity_field(J.get(item, "name"), identity_source(J.get(item, "source")), J.get(item, "required"))

def prepend_identity_field(head: Maybe<&2, IdentityField>, tail: Maybe<&2, +List<IdentityField>>) -> Maybe<&2, +List<IdentityField>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def identity_items(items: +List<J.Json>) -> Maybe<&2, +List<IdentityField>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_identity_field(identity_field(head), identity_items(tail))

def identity_schema(item: J.Json) -> Maybe<&2, +List<IdentityField>>:
  match item:
    case J.Array{items}: identity_items(items)
    case _: None{}

def parsed_value_field(name: J.Json, source: String, field: J.Json, required: J.Json) -> Maybe<&2, ValueField>:
  match name source field required:
    case J.Text{name} "body" _ J.Boolean{required}: Some{TextField{name, Body{}, required}}
    case J.Text{name} "metadata" J.Text{field} J.Boolean{required}: Some{TextField{name, Metadata{field}, required}}
    case J.Text{name} "observation_field" J.Text{field} J.Boolean{required}: Some{TextField{name, ObservationField{field}, required}}
    case J.Text{name} "identity" J.Text{field} _: Some{IdentityValue{name, field}}
    case _ _ _ _: None{}

def value_field(+item: J.Json) -> Maybe<&2, ValueField>:
  +source = J.get(item, "source")
  parsed_value_field(J.get(item, "name"), J.text(J.get(source, "type")), J.get(source, "field"), J.get(item, "required"))

def prepend_value_field(head: Maybe<&2, ValueField>, tail: Maybe<&2, +List<ValueField>>) -> Maybe<&2, +List<ValueField>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def value_field_items(items: +List<J.Json>) -> Maybe<&2, +List<ValueField>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_value_field(value_field(head), value_field_items(tail))

def value_schema(item: J.Json) -> Maybe<&2, +List<ValueField>>:
  match item:
    case J.Array{items}: value_field_items(items)
    case _: None{}

def definition_checked(valid: Bool, definition: Definition) -> Maybe<&2, Definition>:
  match valid:
    case True{}: Some{definition}
    case False{}: None{}

def parsed_definition(kind: J.Json, semantics: J.Json, scope: Maybe<&2, Scope>, observer: Maybe<&2, Observer>, identity: Maybe<&2, +List<IdentityField>>, fields: Maybe<&2, +List<ValueField>>) -> Maybe<&2, Definition>:
  match kind semantics scope observer identity fields:
    case J.Text{kind} J.Text{semantics} Some{scope} Some{observer} Some{identity} Some{fields}:
      +definition: Definition = record_context(kind, semantics, scope, observer, identity, fields)
      definition_checked(valid_definition(definition), definition)
    case _ _ _ _ _ _: None{}

def definition(+item: J.Json) -> Maybe<&2, Definition>:
  parsed_definition(J.get(item, "kind"), J.get(item, "semantics"), parsed_scope(J.get(item, "scope")), observer(J.get(item, "observer")), identity_schema(J.get(item, "identity")), value_schema(J.get(item, "fields")))

def lookup_selected(same: Bool, definition: Definition, rest: Maybe<&2, Definition>) -> Maybe<&2, Definition>:
  match same:
    case True{}: Some{definition}
    case False{}: rest

def lookup_definition(definitions: +List<Definition>, +kind: String) -> Maybe<&2, Definition>:
  match definitions:
    case Nil{}: None{}
    case Con{+definition, rest}: lookup_selected(String.eq(definition_kind(definition), kind), definition, lookup_definition(rest, kind))

def parsed_field_value(field: J.Field) -> Maybe<&2, FieldValue>:
  match field:
    case J.Field{name, J.Text{text}}: Some{FieldValue{name, text}}
    case _: None{}

def prepend_field_value(head: Maybe<&2, FieldValue>, tail: Maybe<&2, +List<FieldValue>>) -> Maybe<&2, +List<FieldValue>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def field_value_items(items: +List<J.Field>) -> Maybe<&2, +List<FieldValue>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_field_value(parsed_field_value(head), field_value_items(tail))

def field_values(item: J.Json) -> Maybe<&2, +List<FieldValue>>:
  match item:
    case J.Object{fields}: field_value_items(fields)
    case _: None{}

def key_checked(valid: Bool, key: Key) -> Maybe<&2, Key>:
  match valid:
    case True{}: Some{key}
    case False{}: None{}

def parsed_key(kind: J.Json, definition: Maybe<&2, Definition>, identity: Maybe<&2, +List<FieldValue>>) -> Maybe<&2, Key>:
  match kind definition identity:
    case J.Text{kind} Some{+definition} Some{+identity}:
      key_checked(String.eq(kind, definition_kind(definition)) && valid_identity(definition_identity(definition), identity), ContextKey{definition, identity})
    case _ _ _: None{}

def self_key(+item: J.Json) -> Maybe<&2, Key>:
  parsed_key(J.get(item, "type"), definition(J.get(item, "definition")), field_values(J.get(item, "identity")))

def registered_selected(found: Maybe<&2, Definition>, +key: Key) -> Maybe<&2, Key>:
  match found:
    case None{}: None{}
    case Some{definition}: key_checked(J.same(definition_json(definition), definition_json(key_definition(key))), key)

def registered_key(registry: +List<Definition>, candidate: Maybe<&2, Key>) -> Maybe<&2, Key>:
  match candidate:
    case None{}: None{}
    case Some{+key}: registered_selected(lookup_definition(registry, key_kind(key)), key)

def key(registry: +List<Definition>, item: J.Json) -> Maybe<&2, Key>:
  registered_key(registry, self_key(item))

def parsed_value(kind: J.Json, fields: Maybe<&2, +List<FieldValue>>) -> Maybe<&2, Value>:
  match kind fields:
    case J.Text{kind} Some{fields}: Some{Record{kind, fields}}
    case _ _: None{}

def value(+item: J.Json) -> Maybe<&2, Value>:
  parsed_value(J.get(item, "type"), field_values(J.get(item, "fields")))

def snapshot_from_parts(same: Bool, definition: Definition, identity: +List<FieldValue>, revision: String, fields: +List<FieldValue>) -> Maybe<&2, Snapshot>:
  match same:
    case True{}: construct_snapshot(definition, identity, revision, fields)
    case False{}: None{}

def parsed_snapshot(key: Maybe<&2, Key>, revision: J.Json, value: Maybe<&2, Value>) -> Maybe<&2, Snapshot>:
  match key revision value:
    case Some{ContextKey{+definition, identity}} J.Text{revision} Some{Record{kind, fields}}:
      snapshot_from_parts(String.eq(kind, definition_kind(definition)), definition, identity, revision, fields)
    case _ _ _: None{}

def self_snapshot(+item: J.Json) -> Maybe<&2, Snapshot>:
  parsed_snapshot(self_key(J.get(item, "key")), J.get(item, "revision"), value(J.get(item, "value")))

def snapshot(registry: +List<Definition>, +item: J.Json) -> Maybe<&2, Snapshot>:
  parsed_snapshot(key(registry, J.get(item, "key")), J.get(item, "revision"), value(J.get(item, "value")))
def parsed_edit(start: Maybe<&2, Nat>, removed: J.Json, inserted: J.Json) -> Maybe<&2, TextEdit>:
  match start removed inserted:
    case Some{start} J.Text{removed} J.Text{inserted}: Some{TextEdit{start, removed, inserted}}
    case _ _ _: None{}

def edit(+item: J.Json) -> Maybe<&2, TextEdit>:
  parsed_edit(J.natural(J.get(item, "start")), J.get(item, "removed"), J.get(item, "inserted"))

def prepend_edit(head: Maybe<&2, TextEdit>, tail: Maybe<&2, +List<TextEdit>>) -> Maybe<&2, +List<TextEdit>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def edit_items(items: +List<J.Json>) -> Maybe<&2, +List<TextEdit>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_edit(edit(head), edit_items(tail))

def edits(item: J.Json) -> Maybe<&2, +List<TextEdit>>:
  match item:
    case J.Array{items}: edit_items(items)
    case _: None{}

def parsed_field_patch(field: J.Json, edits: Maybe<&2, +List<TextEdit>>) -> Maybe<&2, FieldPatch>:
  match field edits:
    case J.Text{name} Some{edits}: Some{FieldPatch{name, edits}}
    case _ _: None{}

def field_patch(+item: J.Json) -> Maybe<&2, FieldPatch>:
  parsed_field_patch(J.get(item, "field"), edits(J.get(item, "edits")))

def prepend_field_patch(head: Maybe<&2, FieldPatch>, tail: Maybe<&2, +List<FieldPatch>>) -> Maybe<&2, +List<FieldPatch>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def field_patch_items(items: +List<J.Json>) -> Maybe<&2, +List<FieldPatch>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_field_patch(field_patch(head), field_patch_items(tail))

def parsed_patch_fields(result: Maybe<&2, +List<FieldPatch>>) -> Maybe<&2, Patch>:
  match result:
    case Some{fields}: Some{FieldEdits{fields}}
    case None{}: None{}

def parsed_patch(kind: String, fields: J.Json) -> Maybe<&2, Patch>:
  match kind fields:
    case "field_edits" J.Array{items}: parsed_patch_fields(field_patch_items(items))
    case _ _: None{}

def patch(+item: J.Json) -> Maybe<&2, Patch>:
  parsed_patch(J.text(J.get(item, "type")), J.get(item, "fields"))

def parsed_observation(kind: String, snapshot: Maybe<&2, Snapshot>, patch: Maybe<&2, Patch>, key: Maybe<&2, Key>, message: J.Json) -> Maybe<&2, Observation>:
  match kind snapshot patch key message:
    case "present" Some{snapshot} Some{patch} _ _: Some{Present{snapshot, patch}}
    case "absent" _ _ Some{key} _: Some{Absent{key}}
    case "failure" _ _ Some{key} J.Text{message}: Some{ObservationFailure{key, message}}
    case _ _ _ _ _: None{}

def observation(+registry: +List<Definition>, +item: J.Json) -> Maybe<&2, Observation>:
  parsed_observation(J.text(J.get(item, "type")), snapshot(registry, J.get(item, "snapshot")), patch(J.get(item, "patch")), key(registry, J.get(item, "key")), J.get(item, "message"))

def prepend_observation(head: Maybe<&2, Observation>, tail: Maybe<&2, +List<Observation>>) -> Maybe<&2, +List<Observation>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def observation_items(+registry: +List<Definition>, items: +List<J.Json>) -> Maybe<&2, +List<Observation>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_observation(observation(registry, head), observation_items(registry, tail))

def observations(registry: +List<Definition>, item: J.Json) -> Maybe<&2, +List<Observation>>:
  match item:
    case J.Array{items}: observation_items(registry, items)
    case _: None{}
