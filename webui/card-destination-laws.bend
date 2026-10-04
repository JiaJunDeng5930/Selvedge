import Base
import ./typography.bend as T
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./document.bend as Doc
import ./design.bend as Design
import ./controls.bend as Controls
import ./renderer.bend as Render
import ./renderer-laws.bend as RendererLaws
# Observe the production container rather than reconstructing its children.

type Requirements is Type:
  Requirements{
    archive_identity: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> ->
      {(RendererLaws.node_key(Render.card_archive_node(key, label, count, children)),
          (Render.attr(Doc.element_attributes(Render.card_archive_node(key, label, count, children)), "data-native-key"),
           (Render.attr(Doc.element_attributes(Render.card_archive_node(key, label, count, children)), "data-card-archive"),
            Render.attr(Doc.element_attributes(Render.card_archive_node(key, label, count, children)), "aria-label")))) ==
          (key, (key, (Nat.show(count), label))) : (String & (String & (String & String)))},
    archive_children: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> ->
      {Doc.element_children(Render.card_archive_node(key, label, count, children)) == children : +List<Doc.Node>},
    archive_events: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> ->
      {Doc.element_events(Render.card_archive_node(key, label, count, children)) == [Doc.DropCard{key}] : +List<Doc.Event>},
    archive_dispatch: @+key:String -> @semantic:String -> @+label:String -> @role:UI.Role -> @+count:Nat ->
      @source:+List<Design.Node> -> @visual:Design.Style ->
      @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, UI.CardArchive{count}, visual, representation, source}, Render.render_children(source)) ==
        Render.card_archive_node(key, label, count, Render.documents(Render.render_children(source))) : Doc.Node},
    card_children_only: @+typography:T.Presentation -> @+key:String -> @+face:View.CardFace -> @destinations:+List<UI.Placement> ->
      @+source:+List<Render.Child> -> @visual:Design.Style ->
      {Doc.element_children(Render.card_node(key, face, destinations, source, visual, typography)) ==
        Render.card_children(key, face, source, typography) : +List<Doc.Node>},
    card_root_excludes_tab_target: @+typography:T.Presentation -> @+key:String -> @+face:View.CardFace -> @destinations:+List<UI.Placement> ->
      @source:+List<Render.Child> -> @+visual:Design.Style ->
      {Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual, typography)), "tabindex") == "" : String}}

law evidence:
  Requirements
