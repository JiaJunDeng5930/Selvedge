import Base
import ../submission-feedback-laws.bend as Rule
import ../appearance.bend as Appearance
import ../typography.bend as T
import ../design.bend as Design
import ../../core/interface.bend as UI
def alert_policy(value: Design.Style) ->
  {Rule.alert_policy_fields(Appearance.alert_style(UI.Alert{}, value)) ==
    (T.Presentation{T.Body{}, T.Regular{}, T.presentation_scale(Design.style_text(value))},
      (Design.ThemeToken{"--color-text-danger"}, Design.TextFlow{T.WrapAnywhere{}})) : (T.Presentation & (Design.Paint & Design.Overflow))}:
  match value:
    case Design.Style{T.Presentation{tier, emphasis, scale}, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def Rule.evidence():
  Rule.Requirements{
    alert_policy,
    wrapping => {==},
    +parent => semantic => revision => +reason => +visual => {==},
    +reason => {==},
    +parent => revision => +reason => +visual => {==}}
