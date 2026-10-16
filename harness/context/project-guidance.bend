import Base
import ./MODEL.bend as C

# Workspace scope describes applicability only; it does not grant permission to
# change the task's workspace, sandbox or other execution settings.
def definition() -> C.Definition:
  C.text_context("project_guidance",
    "Apply these instructions when working within this workspace.", C.WorkspaceScope{}, C.WorkspaceFile{"AGENTS.md"},
    [C.IdentityField{"workspace", C.WorkspaceRoot{}, True{}}])

def key(workspace: String) -> C.Key:
  C.ContextKey{definition(), [C.FieldValue{"workspace", workspace}]}

def snapshot(workspace: String, revision: String, content: String) -> Maybe<&2, C.Snapshot>:
  C.construct_snapshot(definition(), [C.FieldValue{"workspace", workspace}], revision, [C.FieldValue{"content", content}])

# This projection belongs to the concrete definition's business clients. The
# generic history, patch and codec operations never inspect this category.
type Guidance is Data:
  Guidance{workspace: String, revision: String, content: String}

def selected(valid: Bool, snapshot: C.Snapshot) -> Maybe<&2, Guidance>:
  match valid snapshot:
    case True{} C.Snapshot{key, revision, value}:
      Some{Guidance{C.field_text(C.key_identity(key), "workspace"), revision, C.field_text(C.value_fields(value), "content")}}
    case False{} _: None{}

def guidance(+snapshot: C.Snapshot) -> Maybe<&2, Guidance>:
  selected(C.same_key(C.snapshot_key(snapshot), C.ContextKey{definition(), C.key_identity(C.snapshot_key(snapshot))}) && C.valid_snapshot(snapshot), snapshot)

def first(found: Maybe<&2, Guidance>, rest: Maybe<&2, Guidance>) -> Maybe<&2, Guidance>:
  match found:
    case Some{guidance}: Some{guidance}
    case None{}: rest

def latest(bindings: +List<C.Snapshot>) -> Maybe<&2, Guidance>:
  match bindings:
    case Nil{}: None{}
    case Con{snapshot, rest}: first(guidance(snapshot), latest(rest))
