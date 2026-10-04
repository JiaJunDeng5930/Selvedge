import Base
import ./document.bend as Doc
import ./design.bend as Design
import ./typography.bend as T
import ./surfaces.bend as Surfaces

def property(name: String, value: String) -> Doc.Property:
  Doc.Property{name, value}


def px(value: Nat) -> String:
  Nat.show(value) ++ "px"


def surface_color(value: Surfaces.Color) -> String:
  match value:
    case Surfaces.Clear{}: "transparent"
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

def text_presentation(value: T.Presentation) -> +List<Doc.Property>:
  text_properties(T.resolved(value))

def part_text(+parent: T.Presentation, tier: T.Tier, emphasis: T.Emphasis) -> +List<Doc.Property>:
  text_presentation(T.with_emphasis(T.with_tier(parent, tier), emphasis))

def rich_resolved(+prefix: String, +value: T.TextStyle) -> +List<Doc.Property>:
  [property(prefix ++ "-size", px(T.resolved_size(value))), property(prefix ++ "-line", px(T.resolved_line_height(value))),
   property(prefix ++ "-weight", Nat.show(T.resolved_weight(value))), property(prefix ++ "-font", T.font_family(T.resolved_font(value)))]

def rich_role(prefix: String, parent: T.Presentation, tier: T.Tier, emphasis: T.Emphasis) -> +List<Doc.Property>:
  rich_resolved(prefix, T.resolved(T.with_emphasis(T.with_tier(parent, tier), emphasis)))

def rich_properties(+parent: T.Presentation) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, rich_role("--rich-title", parent, T.Title{}, T.Strong{}),
    List.append(&2, Doc.Property, rich_role("--rich-section", parent, T.Section{}, T.Medium{}),
      List.append(&2, Doc.Property, rich_role("--rich-body", parent, T.Body{}, T.Regular{}),
        List.append(&2, Doc.Property, rich_role("--rich-support", parent, T.Support{}, T.Medium{}),
          List.append(&2, Doc.Property, rich_role("--rich-code", parent, T.CodeBody{}, T.Regular{}),
            rich_role("--rich-body-strong", parent, T.Body{}, T.Strong{}))))))

def states_style(value: Design.ControlStates) -> +List<Doc.Property>:
  match value:
    case Design.Passive{}: Nil{}
    case Design.SurfaceFeedback{Design.PhasePaint{hfg, hbg}, Design.PhasePaint{pfg, pbg}}:
      [property("--native-hover-background", paint(hbg)), property("--native-hover-color", paint(hfg)), property("--native-pressed-background", paint(pbg)), property("--native-pressed-color", paint(pfg))]
    case Design.Interactive{Design.PhasePaint{hfg, hbg}, Design.PhasePaint{pfg, pbg}, opacity, ring, width, offset}:
      [property("--native-hover-background", paint(hbg)), property("--native-hover-color", paint(hfg)), property("--native-pressed-background", paint(pbg)), property("--native-pressed-color", paint(pfg)),
       property("--native-disabled-opacity", Nat.show(opacity) ++ "%"), property("--native-focus-ring", paint(ring)), property("--native-focus-width", px(width)), property("--native-focus-offset", px(offset))]


