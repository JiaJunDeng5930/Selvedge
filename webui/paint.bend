import Base
import ./document.bend as Doc
import ./design.bend as Design
import ./typography.bend as T
import ./natural-size.bend as NaturalSize
import ./surfaces.bend as Surfaces

def property(name: String, value: String) -> Doc.Property:
  Doc.Property{name, value}


def px(value: Nat) -> String:
  Nat.show(value) ++ "px"


def surface_color(value: Surfaces.Color) -> String:
  match value:
    case Surfaces.Clear{}: "transparent"
    case Surfaces.NeutralWash{strength}:
      +opacity = Surfaces.wash_opacity(strength)
      # The inactive imported scheme selector expands to whitespace.
      "var(--lightningcss-light, rgba(0, 0, 0, " ++ opacity ++ "))var(--lightningcss-dark, rgba(255, 255, 255, " ++ opacity ++ "))"
    case Surfaces.Token{name}: "var(" ++ name ++ ")"
    case Surfaces.Blend{foreground, percent, background}:
      "color-mix(in srgb, var(" ++ foreground ++ ") " ++ Nat.show(percent) ++ "%, var(" ++ background ++ "))"

def surface_background(role: Surfaces.Role, phase: Surfaces.Phase) -> String:
  surface_color(Surfaces.background(role, phase))

def paint(value: Design.Paint) -> String:
  match value:
    case Design.Transparent{}: "transparent"
    case Design.ThemeToken{name}: "var(" ++ name ++ ")"
    case Design.SurfacePaint{role, phase}: surface_background(role, phase)
    case Design.SurfaceForeground{role}: surface_color(Surfaces.foreground(role))
    case Design.TextForeground{tone}: surface_color(Surfaces.text_foreground(tone))




def text_properties(+value: T.TextStyle) -> +List<Doc.Property>:
  [property("font-family", T.font_family(T.resolved_font(value))), property("font-size", px(T.resolved_size(value))),
   property("line-height", px(T.resolved_line_height(value))), property("font-weight", Nat.show(T.resolved_weight(value)))]

def text_presentation_at(capacity: Nat, value: T.Presentation) -> +List<Doc.Property>:
  text_properties(T.resolve_presentation(capacity, value))

def text_presentation(value: T.Presentation) -> +List<Doc.Property>:
  text_presentation_at(NaturalSize.limit(), value)

def rich_resolved(+prefix: String, +value: T.TextStyle) -> +List<Doc.Property>:
  [property(prefix ++ "-size", px(T.resolved_size(value))), property(prefix ++ "-line", px(T.resolved_line_height(value))),
   property(prefix ++ "-weight", Nat.show(T.resolved_weight(value))), property(prefix ++ "-font", T.font_family(T.resolved_font(value)))]

def rich_role_at(capacity: Nat, prefix: String, parent: T.Presentation, tier: T.Tier, emphasis: T.Emphasis) -> +List<Doc.Property>:
  rich_resolved(prefix, T.resolve_presentation(capacity, T.with_emphasis(T.with_tier(parent, tier), emphasis)))

def rich_role(prefix: String, parent: T.Presentation, tier: T.Tier, emphasis: T.Emphasis) -> +List<Doc.Property>:
  rich_role_at(NaturalSize.limit(), prefix, parent, tier, emphasis)

def rich_properties_at(+capacity: Nat, +parent: T.Presentation) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, rich_role_at(capacity, "--rich-title", parent, T.Title{}, T.Strong{}),
    List.append(&2, Doc.Property, rich_role_at(capacity, "--rich-section", parent, T.Section{}, T.Medium{}),
      List.append(&2, Doc.Property, rich_resolved("--rich-body", T.resolve_presentation(capacity, parent)),
        List.append(&2, Doc.Property, rich_role_at(capacity, "--rich-support", parent, T.Support{}, T.Medium{}),
          List.append(&2, Doc.Property, rich_role_at(capacity, "--rich-code", parent, T.CodeBody{}, T.Regular{}),
            rich_resolved("--rich-body-strong", T.resolve_presentation(capacity, T.with_emphasis(parent, T.Strong{}))))))))

def rich_properties(+parent: T.Presentation) -> +List<Doc.Property>:
  rich_properties_at(NaturalSize.limit(), parent)

def focus_indicator_style(+indicator: Design.FocusIndicator) -> +List<Doc.Property>:
  Design.FocusIndicator{paint_value, width, inset} = indicator
  [property("--native-focus-ring", paint(paint_value)),
   property("--native-focus-width", px(width)),
   property("--native-focus-offset", "-" ++ px(Design.focus_indicator_inner_inset(Design.FocusIndicator{paint_value, width, inset})))]

def states_style(value: Design.ControlStates) -> +List<Doc.Property>:
  match value:
    case Design.Passive{}: Nil{}
    case Design.SurfaceFeedback{Design.PhasePaint{hfg, hbg}, Design.PhasePaint{pfg, pbg}}:
      [property("--native-hover-background", paint(hbg)), property("--native-hover-color", paint(hfg)), property("--native-pressed-background", paint(pbg)), property("--native-pressed-color", paint(pfg))]
    case Design.Interactive{Design.PhasePaint{hfg, hbg}, Design.PhasePaint{pfg, pbg}, opacity, indicator}:
      List.append(&2, Doc.Property,
        [property("--native-hover-background", paint(hbg)), property("--native-hover-color", paint(hfg)), property("--native-pressed-background", paint(pbg)), property("--native-pressed-color", paint(pfg)),
         property("--native-disabled-opacity", Nat.show(opacity) ++ "%")], focus_indicator_style(indicator))


