import Base
import ./document.bend as Doc
import ./renderer.bend as Render
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/interface.bend as UI
import ../core/user-input.bend as U

def rejected_alert_output_law(-parent: String, -revision: Nat, -reason: String, -visual: Design.Style) -> Type:
  {Render.match_node(parent ++ "/feedback", "Submission failed", UI.Alert{}, UI.ReadOnly{reason}, Nil{}, Nil{}, visual, Controls.NoControl{}, Nil{}) ==
      Doc.Element{parent ++ "/feedback", "div", [Render.property("data-native-key", parent ++ "/feedback"), Render.property("role", "alert"), Render.property("aria-label", "Submission failed")],
        List.append(&2, Doc.Property, Render.style(visual),
          [Render.property("color", "var(--color-text-danger)"), Render.property("font-size", "13px"), Render.property("line-height", "20px"),
           Render.property("white-space", "pre-wrap"), Render.property("overflow-wrap", "anywhere"), Render.property("min-width", "0"), Render.property("flex", "0 0 auto")]), Nil{}, [Doc.Text{reason}]} : Doc.Node}

def rejected_alert_output(+parent: String, revision: Nat, +reason: String, +visual: Design.Style) -> rejected_alert_output_law(parent, revision, reason, visual):
  {==}

def source_alert_passive(+reason: String) ->
  {UI.focusable(UI.ReadOnly{reason}) == False{} : Bool}:
  {==}

def rejected_source_rendered_law(-parent: String, -revision: Nat, -reason: String, -visual: Design.Style) -> Type:
  {Render.render_nodes(UI.feedback_nodes(parent, U.Rejected{revision, reason}),
      [Design.Appearance{parent ++ "/feedback", visual, Controls.NoControl{}, Nil{}}]) ==
      [Render.decorate("content", "submission-feedback",
        Doc.Element{parent ++ "/feedback", "div", [Render.property("data-native-key", parent ++ "/feedback"), Render.property("role", "alert"), Render.property("aria-label", "Submission failed")],
          List.append(&2, Doc.Property, Render.style(visual),
            [Render.property("color", "var(--color-text-danger)"), Render.property("font-size", "13px"), Render.property("line-height", "20px"),
             Render.property("white-space", "pre-wrap"), Render.property("overflow-wrap", "anywhere"), Render.property("min-width", "0"), Render.property("flex", "0 0 auto")]), Nil{}, [Doc.Text{reason}]})]
      : +List<Doc.Node>}

def rejected_source_rendered(+parent: String, revision: Nat, +reason: String, +visual: Design.Style) -> rejected_source_rendered_law(parent, revision, reason, visual):
  {==}

type Requirements is Type:
  Requirements{
    rejected_alert_output: @+parent:String -> @revision:Nat -> @+reason:String -> @+visual:Design.Style ->
      rejected_alert_output_law(parent, revision, reason, visual),
    source_alert_passive: @+reason:String ->
      {UI.focusable(UI.ReadOnly{reason}) == False{} : Bool},
    rejected_source_rendered: @+parent:String -> @revision:Nat -> @+reason:String -> @+visual:Design.Style ->
      rejected_source_rendered_law(parent, revision, reason, visual)}

def evidence() -> Requirements:
  Requirements{
    parent => revision => reason => visual => rejected_alert_output(parent, revision, reason, visual),
    reason => source_alert_passive(reason),
    parent => revision => reason => visual => rejected_source_rendered(parent, revision, reason, visual)}
