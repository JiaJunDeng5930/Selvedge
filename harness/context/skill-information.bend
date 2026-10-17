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
