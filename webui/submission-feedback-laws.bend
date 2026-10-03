import Base
import ./appearance.bend as Appearance
import ./typography.bend as T
import ./document.bend as Doc
import ./renderer.bend as Render
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/interface.bend as UI
import ../core/user-input.bend as U











type Requirements is Type:
  Requirements{
    rejected_alert_output: @+parent:String -> @semantic:String -> @revision:Nat -> @+reason:String -> @+visual:Design.Style ->
      {Render.match_node(Design.Node{parent ++ "/feedback", semantic, "Submission failed", UI.Alert{}, UI.ReadOnly{reason}, visual, Controls.NoControl{}, Nil{}}, Nil{}) ==
          Doc.Element{parent ++ "/feedback", "div", [Render.property("data-native-key", parent ++ "/feedback"), Render.property("role", "alert"), Render.property("aria-label", "Submission failed")],
            List.append(&2, Doc.Property, Render.style(visual),
              List.append(&2, Doc.Property, Render.part_text(Appearance.style_text(visual), T.Body{}, T.Regular{}), [Render.property("color", "var(--color-text-danger)"), Render.property("white-space", "pre-wrap"), Render.property("overflow-wrap", "anywhere"), Render.property("min-width", "0"), Render.property("flex", "0 0 auto")])), Nil{}, [Doc.Text{reason}]} : Doc.Node},
    source_alert_passive: @+reason:String ->
      {UI.focusable(UI.ReadOnly{reason}) == False{} : Bool},
    rejected_source_rendered: @+parent:String -> @revision:Nat -> @+reason:String -> @+visual:Design.Style ->
      {Render.render_nodes([Design.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", UI.Alert{}, UI.ReadOnly{reason}, visual, Controls.NoControl{}, Nil{}}]) ==
          [Render.decorate("content", "submission-feedback",
            Doc.Element{parent ++ "/feedback", "div", [Render.property("data-native-key", parent ++ "/feedback"), Render.property("role", "alert"), Render.property("aria-label", "Submission failed")],
              List.append(&2, Doc.Property, Render.style(visual),
                List.append(&2, Doc.Property, Render.part_text(Appearance.style_text(visual), T.Body{}, T.Regular{}), [Render.property("color", "var(--color-text-danger)"), Render.property("white-space", "pre-wrap"), Render.property("overflow-wrap", "anywhere"), Render.property("min-width", "0"), Render.property("flex", "0 0 auto")])), Nil{}, [Doc.Text{reason}]})]
          : +List<Doc.Node>}}

def evidence() -> Requirements:
  Requirements{
    +parent => semantic => revision => +reason => +visual => {==},
    +reason => {==},
    +parent => revision => +reason => +visual => {==}}
