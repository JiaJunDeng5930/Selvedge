import Base
import ../appearance/DESIGN.bend as Design
import ../appearance/MODEL.bend as Appearance
import ./PROGRAM.bend as Controls
import ../editor/editor-layout.bend as EditorLayout
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ./dialog-spatial-laws.bend as Rule

def Rule.evidence():
  Rule.Requirements{
    +typography => editor => +field => +entry => +value => choices => toggle =>
      Equal.cong(Controls.Widget, Design.Style,
        (widget => Appearance.normalize_field(EditorLayout.field_kind(InterfaceView.Edit{editor, field, entry, value, choices}),
          widget, Appearance.widget_field_style(widget, entry, typography))),
        Controls.widget_for(entry, field, value), Controls.ToggleInput{}, toggle),
    +typography => {==},
    {==},
    +card => +field => +entry => +value => choices => {==},
    {==}}
