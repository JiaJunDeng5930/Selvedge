import Base
import ./MODEL.bend as C
import ./instruction.bend as Instruction
import ./project-guidance.bend as ProjectGuidance
import ./skill-information.bend as SkillInformation
import ./interactive-markdown.bend as InteractiveMarkdown

# New context categories add a definition and register it here. Source
# observation, value admission, patches, history and wire consumers are generic.
def definitions() -> +List<C.Definition>:
  [Instruction.configured(), Instruction.global(), ProjectGuidance.definition(), ProjectGuidance.directory_definition(),
   SkillInformation.definition(), SkillInformation.home(), SkillInformation.workspace(), InteractiveMarkdown.definition()]
