import Base
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/string-equality.bend as Text

# Context source identity excludes revisions and content. A project's guidance
# source carries its scope, never authority to change task workspace permissions.
type Key is Data:
  InstructionKey{origin: String, path: String}
  ProjectGuidanceKey{workspace: String}
  SkillInformationKey{installation: String, path: String}

type Value is Data:
  Instruction{content: String}
  ProjectGuidance{content: String}
  SkillInformation{name: String, description: String, path: String}

type Snapshot is Data:
  Snapshot{key: Key, revision: String, value: Value}

# Every start offset addresses the original baseline, not the preceding edit's
# output. Removed text authenticates each range and makes deletion model-visible.
type TextEdit is Data:
  TextEdit{start: Nat, removed: String, inserted: String}

type Patch is Data:
  TextEdits{edits: +List<TextEdit>}
  SkillEdits{name: +List<TextEdit>, description: +List<TextEdit>}

type Change is Data:
  Introduce{snapshot: Snapshot}
  Amend{key: Key, base_revision: String, revision: String, patch: Patch}
  Remove{key: Key, base_revision: String}

type Observation is Data:
  Present{snapshot: Snapshot, patch: Patch}
  Absent{key: Key}
  ObservationFailure{key: Key, message: String}

def same_key(left: Key, right: Key) -> Bool:
  match left right:
    case InstructionKey{a, b} InstructionKey{x, y}: String.eq(a, x) && String.eq(b, y)
    case ProjectGuidanceKey{a} ProjectGuidanceKey{b}: String.eq(a, b)
    case SkillInformationKey{a, b} SkillInformationKey{x, y}: String.eq(a, x) && String.eq(b, y)
    case _ _: False{}

def same_value(left: Value, right: Value) -> Bool:
  match left right:
    case Instruction{a} Instruction{b}: Text.string_equal(a, b)
    case ProjectGuidance{a} ProjectGuidance{b}: Text.string_equal(a, b)
    case SkillInformation{a, b, c} SkillInformation{x, y, z}: Text.string_equal(a, x) && Text.string_equal(b, y) && Text.string_equal(c, z)
    case _ _: False{}

def source_value(key: Key, value: Value) -> Bool:
  match key value:
    case InstructionKey{+origin, +path} Instruction{content}:
      (String.eq(origin, "configured") && String.eq(path, "")) || (String.eq(origin, "global_agents") && Bool.not(String.eq(path, "")))
    case ProjectGuidanceKey{workspace} ProjectGuidance{content}: Bool.not(String.eq(workspace, ""))
    case SkillInformationKey{installation, +path} SkillInformation{name, description, actual}:
      Bool.not(String.eq(installation, "")) && Bool.not(String.eq(path, "")) && String.eq(path, actual)
    case _ _: False{}

def valid_snapshot(+snapshot: Snapshot) -> Bool:
  Snapshot{key, revision, value} = snapshot
  Bool.not(String.eq(revision, "")) && source_value(key, value)

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

def instruction_result(text: Maybe<&2, String>) -> Maybe<&2, Value>:
  match text:
    case Some{content}: Some{Instruction{content}}
    case None{}: None{}

def project_result(text: Maybe<&2, String>) -> Maybe<&2, Value>:
  match text:
    case Some{content}: Some{ProjectGuidance{content}}
    case None{}: None{}

def skill_result(name: Maybe<&2, String>, description: Maybe<&2, String>, path: String) -> Maybe<&2, Value>:
  match name description:
    case Some{name} Some{description}: Some{SkillInformation{name, description, path}}
    case _ _: None{}

def apply_patch(value: Value, patch: Patch) -> Maybe<&2, Value>:
  match value patch:
    case Instruction{content} TextEdits{edits}: instruction_result(apply_text(0n, content, edits))
    case ProjectGuidance{content} TextEdits{edits}: project_result(apply_text(0n, content, edits))
    case SkillInformation{name, description, path} SkillEdits{names, descriptions}:
      skill_result(apply_text(0n, name, names), apply_text(0n, description, descriptions), path)
    case _ _: None{}

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
        Bool.not(String.eq(base, snapshot_revision(observed))) && patch_matches(apply_patch(value, patch), snapshot_value(observed)), key, base, observed, patch)

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


def key_json(key: Key) -> J.Json:
  match key:
    case InstructionKey{origin, path}: J.Object{[J.Field{"type", J.Text{"instruction"}}, J.Field{"origin", J.Text{origin}}, J.Field{"path", J.Text{path}}]}
    case ProjectGuidanceKey{workspace}: J.Object{[J.Field{"type", J.Text{"project_guidance"}}, J.Field{"workspace", J.Text{workspace}}]}
    case SkillInformationKey{installation, path}: J.Object{[J.Field{"type", J.Text{"skill_information"}}, J.Field{"installation", J.Text{installation}}, J.Field{"path", J.Text{path}}]}

def value_json(value: Value) -> J.Json:
  match value:
    case Instruction{content}: J.Object{[J.Field{"type", J.Text{"instruction"}}, J.Field{"content", J.Text{content}}]}
    case ProjectGuidance{content}: J.Object{[J.Field{"type", J.Text{"project_guidance"}}, J.Field{"content", J.Text{content}}]}
    case SkillInformation{name, description, path}: J.Object{[J.Field{"type", J.Text{"skill_information"}}, J.Field{"name", J.Text{name}}, J.Field{"description", J.Text{description}}, J.Field{"path", J.Text{path}}]}

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

def patch_json(patch: Patch) -> J.Json:
  match patch:
    case TextEdits{edits}: J.Object{[J.Field{"type", J.Text{"text_edits"}}, J.Field{"edits", edits_json(edits)}]}
    case SkillEdits{name, description}: J.Object{[J.Field{"type", J.Text{"skill_edits"}}, J.Field{"name", edits_json(name)}, J.Field{"description", edits_json(description)}]}

def change_json(change: Change) -> J.Json:
  match change:
    case Introduce{snapshot}: J.Object{[J.Field{"type", J.Text{"introduce"}}, J.Field{"snapshot", snapshot_json(snapshot)}]}
    case Amend{key, base, revision, patch}: J.Object{[J.Field{"type", J.Text{"amend"}}, J.Field{"key", key_json(key)}, J.Field{"base_revision", J.Text{base}}, J.Field{"revision", J.Text{revision}}, J.Field{"patch", patch_json(patch)}]}
    case Remove{key, base}: J.Object{[J.Field{"type", J.Text{"remove"}}, J.Field{"key", key_json(key)}, J.Field{"base_revision", J.Text{base}}]}

def parsed_key(kind: String, origin: J.Json, path: J.Json, workspace: J.Json, installation: J.Json) -> Maybe<&2, Key>:
  match kind origin path workspace installation:
    case "instruction" J.Text{origin} J.Text{path} _ _: Some{InstructionKey{origin, path}}
    case "project_guidance" _ _ J.Text{workspace} _: Some{ProjectGuidanceKey{workspace}}
    case "skill_information" _ J.Text{path} _ J.Text{installation}: Some{SkillInformationKey{installation, path}}
    case _ _ _ _ _: None{}

def key(+value: J.Json) -> Maybe<&2, Key>:
  parsed_key(J.text(J.get(value, "type")), J.get(value, "origin"), J.get(value, "path"), J.get(value, "workspace"), J.get(value, "installation"))

def parsed_value(kind: String, content: J.Json, name: J.Json, description: J.Json, path: J.Json) -> Maybe<&2, Value>:
  match kind content name description path:
    case "instruction" J.Text{content} _ _ _: Some{Instruction{content}}
    case "project_guidance" J.Text{content} _ _ _: Some{ProjectGuidance{content}}
    case "skill_information" _ J.Text{name} J.Text{description} J.Text{path}: Some{SkillInformation{name, description, path}}
    case _ _ _ _ _: None{}

def value(+item: J.Json) -> Maybe<&2, Value>:
  parsed_value(J.text(J.get(item, "type")), J.get(item, "content"), J.get(item, "name"), J.get(item, "description"), J.get(item, "path"))

def parsed_snapshot(key: Maybe<&2, Key>, revision: J.Json, value: Maybe<&2, Value>) -> Maybe<&2, Snapshot>:
  match key revision value:
    case Some{key} J.Text{revision} Some{value}: Some{Snapshot{key, revision, value}}
    case _ _ _: None{}

def snapshot(+item: J.Json) -> Maybe<&2, Snapshot>:
  parsed_snapshot(key(J.get(item, "key")), J.get(item, "revision"), value(J.get(item, "value")))

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

def parsed_patch(kind: String, text: Maybe<&2, +List<TextEdit>>, name: Maybe<&2, +List<TextEdit>>, description: Maybe<&2, +List<TextEdit>>) -> Maybe<&2, Patch>:
  match kind text name description:
    case "text_edits" Some{edits} _ _: Some{TextEdits{edits}}
    case "skill_edits" _ Some{name} Some{description}: Some{SkillEdits{name, description}}
    case _ _ _ _: None{}

def patch(+item: J.Json) -> Maybe<&2, Patch>:
  parsed_patch(J.text(J.get(item, "type")), edits(J.get(item, "edits")), edits(J.get(item, "name")), edits(J.get(item, "description")))

def parsed_observation(kind: String, snapshot: Maybe<&2, Snapshot>, patch: Maybe<&2, Patch>, key: Maybe<&2, Key>, message: J.Json) -> Maybe<&2, Observation>:
  match kind snapshot patch key message:
    case "present" Some{snapshot} Some{patch} _ _: Some{Present{snapshot, patch}}
    case "absent" _ _ Some{key} _: Some{Absent{key}}
    case "failure" _ _ Some{key} J.Text{message}: Some{ObservationFailure{key, message}}
    case _ _ _ _ _: None{}

def observation(+item: J.Json) -> Maybe<&2, Observation>:
  parsed_observation(J.text(J.get(item, "type")), snapshot(J.get(item, "snapshot")), patch(J.get(item, "patch")), key(J.get(item, "key")), J.get(item, "message"))

def prepend_observation(head: Maybe<&2, Observation>, tail: Maybe<&2, +List<Observation>>) -> Maybe<&2, +List<Observation>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def observation_items(items: +List<J.Json>) -> Maybe<&2, +List<Observation>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend_observation(observation(head), observation_items(tail))

def observations(item: J.Json) -> Maybe<&2, +List<Observation>>:
  match item:
    case J.Array{items}: observation_items(items)
    case _: None{}
