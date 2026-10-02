import Base
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./document.bend as Doc
import ./design.bend as Design
import ./controls.bend as Controls
import ./renderer.bend as Render
import ./renderer-laws.bend as RendererLaws

# Observe the production container rather than reconstructing its children.
def archive_identity(+key: String, +label: String, +count: Nat, +children: +List<Doc.Node>) ->
  {(RendererLaws.node_key(Render.card_archive_node(key, label, count, children)),
    (Render.attr(RendererLaws.node_attributes(Render.card_archive_node(key, label, count, children)), "data-native-key"),
     (Render.attr(RendererLaws.node_attributes(Render.card_archive_node(key, label, count, children)), "data-card-archive"),
      Render.attr(RendererLaws.node_attributes(Render.card_archive_node(key, label, count, children)), "aria-label")))) ==
    (key, (key, (Nat.show(count), label))) : (String & (String & (String & String)))}:
  {==}

def archive_children(+key: String, +label: String, +count: Nat, +children: +List<Doc.Node>) ->
  {RendererLaws.node_children(Render.card_archive_node(key, label, count, children)) == children : +List<Doc.Node>}:
  {==}

def archive_events(+key: String, +label: String, +count: Nat, +children: +List<Doc.Node>) ->
  {RendererLaws.node_events(Render.card_archive_node(key, label, count, children)) == [Doc.DropCard{key}] : +List<Doc.Event>}:
  {==}

def archive_dispatch(+key: String, +label: String, role: UI.Role, +count: Nat,
  source: +List<UI.Node>, +children: +List<Doc.Node>, visual: Design.Style,
  representation: Controls.Representation, appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, UI.CardArchive{count}, source, children, visual, representation, appearances) ==
    Render.card_archive_node(key, label, count, children) : Doc.Node}:
  {==}

def card_children_only(+key: String, +face: View.CardFace, destinations: +List<UI.Placement>,
  +source: +List<UI.Node>, +children: +List<Doc.Node>, visual: Design.Style) ->
  {RendererLaws.node_children(Render.card_node(key, face, destinations, source, children, visual)) ==
    Render.card_children(key, face, source, children) : +List<Doc.Node>}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

type Requirements is Type:
  Requirements{
    archive_identity: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> ->
      {(RendererLaws.node_key(Render.card_archive_node(key, label, count, children)),
        (Render.attr(RendererLaws.node_attributes(Render.card_archive_node(key, label, count, children)), "data-native-key"),
         (Render.attr(RendererLaws.node_attributes(Render.card_archive_node(key, label, count, children)), "data-card-archive"),
          Render.attr(RendererLaws.node_attributes(Render.card_archive_node(key, label, count, children)), "aria-label")))) ==
        (key, (key, (Nat.show(count), label))) : (String & (String & (String & String)))},
    archive_children: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> ->
      {RendererLaws.node_children(Render.card_archive_node(key, label, count, children)) == children : +List<Doc.Node>},
    archive_events: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> ->
      {RendererLaws.node_events(Render.card_archive_node(key, label, count, children)) == [Doc.DropCard{key}] : +List<Doc.Event>},
    archive_dispatch: @+key:String -> @+label:String -> @role:UI.Role -> @+count:Nat ->
      @source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @visual:Design.Style ->
      @representation:Controls.Representation -> @appearances:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, UI.CardArchive{count}, source, children, visual, representation, appearances) ==
        Render.card_archive_node(key, label, count, children) : Doc.Node},
    card_children_only: @+key:String -> @+face:View.CardFace -> @destinations:+List<UI.Placement> ->
      @+source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @visual:Design.Style ->
      {RendererLaws.node_children(Render.card_node(key, face, destinations, source, children, visual)) ==
        Render.card_children(key, face, source, children) : +List<Doc.Node>},
    card_root_excludes_tab_target: @+key:String -> @+face:View.CardFace -> @destinations:+List<UI.Placement> ->
      @source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style ->
      {Render.attr(RendererLaws.node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "tabindex") == "" : String}}

def evidence() -> Requirements:
  Requirements{
    key => label => count => children => archive_identity(key, label, count, children),
    key => label => count => children => archive_children(key, label, count, children),
    key => label => count => children => archive_events(key, label, count, children),
    key => label => role => count => source => children => visual => representation => appearances =>
      archive_dispatch(key, label, role, count, source, children, visual, representation, appearances),
    key => face => destinations => source => children => visual => card_children_only(key, face, destinations, source, children, visual),
    key => face => destinations => source => children => visual => RendererLaws.card_root_excludes_tab_target(key, face, destinations, source, children, visual)}
