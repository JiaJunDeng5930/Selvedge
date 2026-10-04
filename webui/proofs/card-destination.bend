import ./renderer.bend as RendererLawsProof
import Base
import ../card-destination-laws.bend as Rule
import ../typography.bend as T
import ../../core/interface.bend as UI
import ../../core/ui-world.bend as View
import ../document.bend as Doc
import ../design.bend as Design
import ../renderer.bend as Render
def card_children_only(+key: String, +face: View.CardFace, destinations: +List<UI.Placement>,
  +source: +List<Render.Child>, +visual: Design.Style, +typography: T.Presentation) ->
  {Doc.element_children(Render.card_node(key, face, destinations, source, visual, typography)) ==
    Render.card_children(key, face, source, typography) : +List<Doc.Node>}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def Rule.evidence():
  Rule.Requirements{
    +key => +label => +count => +children => {==},
    +key => +label => +count => +children => {==},
    +key => +label => +count => +children => {==},
    +key => semantic => +label => role => +count => source => visual => representation => {==},
    +typography => key => face => destinations => source => visual => card_children_only(key, face, destinations, source, visual, typography),
    +typography => key => face => destinations => source => visual => RendererLawsProof.card_root_excludes_tab_target(key, face, destinations, source, visual, typography)}
