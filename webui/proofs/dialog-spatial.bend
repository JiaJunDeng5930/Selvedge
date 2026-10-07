import Base
import ../design.bend as Design
import ../appearance.bend as Appearance
import ../controls.bend as Controls
import ../editor-layout.bend as EditorLayout
import ../../core/interface.bend as InterfaceView
import ../dialog-spatial-laws.bend as Rule

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
