import Base
import ./controls.bend as Controls
import ./design.bend as Design
import ./document.bend as Doc
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User
import ../core/user-experience.bend as Experience
import ../core/SYSTEM.bend as Core

type FieldKind is Data:
  Ordinary{}
  WorkTitle{}
  WorkDescription{}
  MetadataFlexible{}
  MetadataWide{}
  CaptureOption{}

type SectionKind is Data:
  GenericSection{}
  WorkSection{}
  MetadataSection{}
  CaptureSection{}
  SubmitAction{}

type Suffix is Data:
  Suffix{body: +List<Doc.Node>, footer: +List<Doc.Node>}

def card_field(field: Forms.Field) -> FieldKind:
  match field:
    case Forms.CardTitle{}: WorkTitle{}
    case Forms.CardDescription{}: WorkDescription{}
    case Forms.CardStage{}: MetadataFlexible{}
    case Forms.CardPriority{}: MetadataFlexible{}
    case Forms.CardProject{}: MetadataFlexible{}
    case Forms.CardOwner{}: MetadataWide{}
    case Forms.CardLabels{}: MetadataWide{}
    case Forms.ContinueCapture{}: CaptureOption{}
    case Forms.AssistedCapture{}: CaptureOption{}
    case Forms.AssistanceProfile{}: CaptureOption{}
    case _: Ordinary{}

def field_kind(meaning: UI.Meaning) -> FieldKind:
  match meaning:
    case UI.Edit{User.CardEditor{card}, field, entry, value}: card_field(field)
    case _: Ordinary{}

def field_section(kind: FieldKind) -> SectionKind:
  match kind:
    case WorkTitle{}: WorkSection{}
    case WorkDescription{}: WorkSection{}
    case MetadataFlexible{}: MetadataSection{}
    case MetadataWide{}: MetadataSection{}
    case CaptureOption{}: CaptureSection{}
    case Ordinary{}: GenericSection{}

def submit_input(input: Core.Input) -> Bool:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{editor}}}}: True{}
    case _: False{}

def submit_kind(enabled: Bool) -> SectionKind:
  match enabled:
    case True{}: SubmitAction{}
    case False{}: GenericSection{}

def representation_kind(value: Controls.Representation) -> SectionKind:
  match value:
    case Controls.Input{binding, name, widget, label, availability}: field_section(field_kind(binding))
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      submit_kind(submit_input(input))
    case _: GenericSection{}

def same_section(first: SectionKind, second: SectionKind) -> Bool:
  match first second:
    case WorkSection{} WorkSection{}: True{}
    case MetadataSection{} MetadataSection{}: True{}
    case CaptureSection{} CaptureSection{}: True{}
    case _ _: False{}

def section_match(matches: Bool, remainder: SectionKind) -> SectionKind:
  match matches:
    case True{}: remainder
    case False{}: GenericSection{}

def section_rest(+kind: SectionKind, children: +List<Design.Node>) -> SectionKind:
  match children:
    case Nil{}: kind
    case Con{Design.Node{identity, semantic, label, role, meaning, visual, representation, nested}, rest}:
      section_match(same_section(kind, representation_kind(representation)), section_rest(kind, rest))

def section_seed(kind: SectionKind) -> SectionKind:
  match kind:
    case WorkSection{}: WorkSection{}
    case MetadataSection{}: MetadataSection{}
    case CaptureSection{}: CaptureSection{}
    case _: GenericSection{}

def section_kind(children: +List<Design.Node>) -> SectionKind:
  match children:
    case Nil{}: GenericSection{}
    case Con{Design.Node{identity, semantic, label, role, meaning, visual, representation, nested}, rest}:
      section_rest(section_seed(representation_kind(representation)), rest)

def appearance_kind(value: Design.Node) -> SectionKind:
  Design.Node{identity, semantic, label, role, meaning, visual, representation, children} = value
  match representation:
    case Controls.NoControl{}: section_kind(children)
    case _: representation_kind(representation)

def body(value: Suffix) -> +List<Doc.Node>:
  Suffix{+content, footer} = value
  content

def footer(value: Suffix) -> +List<Doc.Node>:
  Suffix{content, +actions} = value
  actions

# Only a terminal submit, optionally preceded by the capture section, is moved.
# Earlier capture sections remain body content and all source order is retained.
def prepend(kind: SectionKind, +node: Doc.Node, suffix: Suffix) -> Suffix:
  match kind suffix:
    case SubmitAction{} Suffix{Nil{}, Nil{}}: Suffix{Nil{}, [node]}
    case CaptureSection{} Suffix{Nil{}, Con{submit, Nil{}}}: Suffix{Nil{}, [node, submit]}
    case _ Suffix{+content, +actions}: Suffix{node <> content, actions}

def split(nodes: +List<Doc.Node>, kinds: +List<SectionKind>) -> Suffix:
  match nodes kinds:
    case Con{node, rest} Con{kind, remaining}: prepend(kind, node, split(rest, remaining))
    case +values _: Suffix{values, Nil{}}
