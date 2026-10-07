import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ./task-details-laws.bend as Rule
import ../appearance/DESIGN.bend as Design
import ../controls/MODEL.bend as Authored
import ./SOURCE.bend as Source
import ../layout/physical-space.bend as Model
import ../appearance/TYPOGRAPHY.bend as T

def instructions_same(empty: Bool, +value: String) -> {Authored.project_instructions(empty, value) == Rule.instructions_text_when(empty, value) : String}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def frozen_project(+owner: UIIdentity.Key, +label: String, +directory: String, +revision: String, +instructions: String, +visual: Design.Style) -> Rule.project_law(owner, label, directory, revision, instructions, visual):
  Equal.cong(String, +List<Source.Node>,
    supplied_text => [Authored.group(owner, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(UIIdentity.part(owner, "title"), label, visual, T.Body{}, T.Strong{}), Authored.fact(UIIdentity.part(owner, "directory"), "Directory", directory, visual), Authored.fact(UIIdentity.part(owner, "revision"), "Revision", revision, visual), Authored.fact(UIIdentity.part(owner, "instructions"), "Instructions", supplied_text, visual)])],
    Authored.project_instructions(String.eq(instructions, ""), instructions),
    Rule.instructions_text_when(String.eq(instructions, ""), instructions),
    instructions_same(String.eq(instructions, ""), instructions))

def Rule.evidence():
  Rule.Requirements{
    +owner => +label => +visual => {==},
    frozen_project,
    +owner => +visual => {==},
    +owner => +name => +description => +schema => +source => +rest => +visual => {==},
    {==},
    +ancestor => +rest => {==},
    +owner => +task => +roots => +primary => +mode => +network => +approval => +project => +guidance => +access => +id => +provider => +name => +policy => +options => +reasoning => +model_guidance => +tools => +lineage => +queued => +status => +phase => +visual => {==}}
