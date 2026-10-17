import Base
import ./MODEL.bend as C

# Workspace scope describes applicability only; it does not grant permission to
# change the task's workspace, sandbox or other execution settings.
def definition() -> C.Definition:
  C.record_context("project_guidance",
    "Apply these instructions within applies_to. The precedence directory orders guidance by ancestry: descendant directories take priority over ancestors; AGENTS.override.md takes priority over AGENTS.md in the same directory. Scope does not change execution permissions.",
    C.PrimaryWorkspaceScope{}, C.PrimaryGuidance{C.guidance_policy()},
    [C.IdentityField{"workspace", C.WorkspaceRoot{}, True{}}],
    [C.TextField{"content", C.Body{}, False{}},
     C.TextField{"path", C.ObservationField{"path"}, True{}},
     C.TextField{"applies_to", C.ObservationField{"applies_to"}, True{}},
     C.TextField{"precedence", C.ObservationField{"precedence"}, True{}}])

def directory_definition() -> C.Definition:
  C.record_context("directory_guidance",
    "Apply these instructions only within applies_to. The precedence directory orders guidance by ancestry: descendant directories take priority over ancestors; AGENTS.override.md takes priority over AGENTS.md in the same directory. Scope does not change execution permissions.",
    C.WorkspaceScope{}, C.WorkspaceGuidance{C.guidance_policy()},
    [C.IdentityField{"workspace", C.WorkspaceRoot{}, True{}}, C.IdentityField{"path", C.SourcePath{}, True{}}],
    [C.TextField{"content", C.Body{}, False{}}, C.IdentityValue{"path", "path"},
     C.TextField{"applies_to", C.ObservationField{"applies_to"}, True{}},
     C.TextField{"precedence", C.ObservationField{"precedence"}, True{}}])

def directory_entry(directory: String, name: String) -> String:
  match directory:
    case "/": "/" ++ name
    case other: other ++ "/" ++ name

def source_path_member(files: +List<String>, +workspace: String, +path: String) -> Bool:
  match files:
    case Nil{}: False{}
    case Con{file, rest}: String.eq(directory_entry(workspace, file), path) || source_path_member(rest, workspace, path)

def policy_source_path(policy: C.DiscoveryPolicy, workspace: String, path: String) -> Bool:
  C.DiscoveryPolicy{files, directories, repository_markers, excluded, max_directories, max_entries, max_sources, max_bytes} = policy
  source_path_member(files, workspace, path)

def source_path(workspace: String, path: String) -> Bool:
  policy_source_path(C.guidance_policy(), workspace, path)

def key(workspace: String) -> C.Key:
  C.ContextKey{definition(), [C.FieldValue{"workspace", workspace}]}

def snapshot(+workspace: String, path: String, revision: String, content: String) -> Maybe<&2, C.Snapshot>:
  C.construct_snapshot(definition(), [C.FieldValue{"workspace", workspace}], revision,
    [C.FieldValue{"content", content}, C.FieldValue{"path", path},
     C.FieldValue{"applies_to", workspace}, C.FieldValue{"precedence", workspace}])

# This projection belongs to the concrete definition's business clients. The
# generic history, patch and codec operations never inspect this category.
type Guidance is Data:
  Guidance{workspace: String, path: String, revision: String, content: String}

def selected(valid: Bool, snapshot: C.Snapshot) -> Maybe<&2, Guidance>:
  match valid snapshot:
    case True{} C.Snapshot{key, revision, +value}:
      Some{Guidance{C.field_text(C.key_identity(key), "workspace"), C.field_text(C.value_fields(value), "path"), revision, C.field_text(C.value_fields(value), "content")}}
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
