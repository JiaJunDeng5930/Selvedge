import Base
import ./MODEL.bend as C

# Both instruction sources instantiate the same text-context construction. Their
# identities distinguish the configuration slot from the global guidance file.
def configured() -> C.Definition:
  C.text_context("configured_instruction",
    "Follow these instructions while carrying out this task.", C.GlobalScope{}, C.ConfigText{"instructions"},
    [C.IdentityField{"origin", C.Constant{"configured"}, True{}}])

def global() -> C.Definition:
  C.text_context("global_agents",
    "Apply these instructions throughout this task, including work outside the selected workspace.", C.GlobalScope{}, C.HomeFile{"AGENTS.md"},
    [C.IdentityField{"path", C.SourcePath{}, True{}}])

def configured_snapshot(content: String) -> Maybe<&2, C.Snapshot>:
  C.construct_snapshot(configured(), [C.FieldValue{"origin", "configured"}], "initial", [C.FieldValue{"content", content}])

def global_snapshot(path: String, revision: String, content: String) -> Maybe<&2, C.Snapshot>:
  C.construct_snapshot(global(), [C.FieldValue{"path", path}], revision, [C.FieldValue{"content", content}])
