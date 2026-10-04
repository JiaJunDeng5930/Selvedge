import Base
import ./appearance.bend as Appearance
import ./typography.bend as T
import ./document.bend as Doc
import ./renderer.bend as Render
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/interface.bend as UI

def alert_policy_fields(value: Design.Style) -> (T.Presentation & (Design.Paint & Design.Overflow)):
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  (text, (foreground, overflow))

def alert_policy(value: Design.Style) ->
  {alert_policy_fields(Appearance.alert_style(UI.Alert{}, value)) ==
    (T.Presentation{T.Body{}, T.Regular{}, T.presentation_scale(Design.style_text(value))},
      (Design.ThemeToken{"--color-text-danger"}, Design.TextFlow{T.WrapAnywhere{}})) : (T.Presentation & (Design.Paint & Design.Overflow))}:
  match value:
    case Design.Style{T.Presentation{tier, emphasis, scale}, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

type Requirements is Type:
  Requirements{
    alert_style_policy: @value:Design.Style ->
      {alert_policy_fields(Appearance.alert_style(UI.Alert{}, value)) ==
        (T.Presentation{T.Body{}, T.Regular{}, T.presentation_scale(Design.style_text(value))},
          (Design.ThemeToken{"--color-text-danger"}, Design.TextFlow{T.WrapAnywhere{}})) : (T.Presentation & (Design.Paint & Design.Overflow))},
    text_flow_serialization: @wrapping:T.Wrapping ->
      {Render.overflow_style(Design.TextFlow{wrapping}) ==
        List.append(&2, Doc.Property, Render.wrapping_properties(wrapping), [Render.property("flex", "0 0 auto")]) : +List<Doc.Property>},
    rejected_alert_output: @+parent:String -> @semantic:String -> @revision:Nat -> @+reason:String -> @+visual:Design.Style ->
      {Render.match_node(Design.Node{parent ++ "/feedback", semantic, "Submission failed", UI.Alert{}, UI.ReadOnly{reason}, visual, Controls.NoControl{}, Nil{}}, Nil{}) ==
          Doc.Element{parent ++ "/feedback", "div", [Render.property("data-native-key", parent ++ "/feedback"), Render.property("role", "alert"), Render.property("aria-label", "Submission failed")],
            Render.style(visual), Nil{}, [Doc.Text{reason}]} : Doc.Node},
    source_alert_passive: @+reason:String ->
      {UI.focusable(UI.ReadOnly{reason}) == False{} : Bool},
    rejected_source_rendered: @+parent:String -> @revision:Nat -> @+reason:String -> @+visual:Design.Style ->
      {Render.render_nodes([Design.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", UI.Alert{}, UI.ReadOnly{reason}, visual, Controls.NoControl{}, Nil{}}]) ==
          [Render.decorate("content", "submission-feedback",
            Doc.Element{parent ++ "/feedback", "div", [Render.property("data-native-key", parent ++ "/feedback"), Render.property("role", "alert"), Render.property("aria-label", "Submission failed")],
              Render.style(visual), Nil{}, [Doc.Text{reason}]})]
          : +List<Doc.Node>}}

def evidence() -> Requirements:
  Requirements{
    alert_policy,
    wrapping => {==},
    +parent => semantic => revision => +reason => +visual => {==},
    +reason => {==},
    +parent => revision => +reason => +visual => {==}}
