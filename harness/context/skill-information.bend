import Base
import ./MODEL.bend as C

# Skill metadata is projected independently of its body: changing the body does
# not introduce it into the model context or generate a metadata amendment.
def definition() -> C.Definition:
  C.record_context("skill_information",
    "Use this name and description to decide whether the skill applies; read its instructions at the listed path before using it.",
    C.GlobalScope{}, C.ConfigFiles{"skills"},
    [C.IdentityField{"installation", C.HomeRoot{}, True{}}, C.IdentityField{"path", C.SourcePath{}, True{}}],
    [C.TextField{"name", C.Metadata{"name"}, True{}},
     C.TextField{"description", C.Metadata{"description"}, True{}},
     C.IdentityValue{"path", "path"}])

# Discovery retains competing skill names as separate sources. The applicable
# installation is selected from metadata; its body remains an ordinary tool read.
def discovered_fields() -> +List<C.ValueField>:
  [C.TextField{"name", C.Metadata{"name"}, True{}},
   C.TextField{"description", C.Metadata{"description"}, True{}},
   C.IdentityValue{"path", "path"},
   C.TextField{"applies_to", C.ObservationField{"applies_to"}, True{}},
   C.TextField{"precedence", C.ObservationField{"precedence"}, True{}}]

def home() -> C.Definition:
  C.record_context("user_skill_information",
    "Use this name and description to decide whether the skill applies. Skills in a more specific applicable directory take priority over ancestors; explicitly configured skills are preferred when names conflict. Read the listed path through an ordinary tool before using the skill. Its body is not tracked context.",
    C.GlobalScope{}, C.HomeSkills{C.home_skills_policy()},
    [C.IdentityField{"installation", C.HomeRoot{}, True{}}, C.IdentityField{"path", C.SourcePath{}, True{}}], discovered_fields())

def workspace() -> C.Definition:
  C.record_context("workspace_skill_information",
    "Use this name and description only within applies_to. The precedence directory orders matching skills by ancestry, with descendant directories taking priority over ancestors; explicitly configured skills are preferred when names conflict. Read the listed path through an ordinary tool before using the skill. Its body is not tracked context.",
    C.WorkspaceScope{}, C.WorkspaceSkills{C.workspace_skills_policy()},
    [C.IdentityField{"workspace", C.WorkspaceRoot{}, True{}}, C.IdentityField{"path", C.SourcePath{}, True{}}], discovered_fields())
