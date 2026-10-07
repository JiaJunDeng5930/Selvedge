import Base
import ./paint.bend as Paint
import ./design.bend as Design
import ./typography.bend as T
import ./document.bend as Doc

def selected_property(matches: Bool, value: String, fallback: String) -> String:
  match matches:
    case True{}: value
    case False{}: fallback

def property_value(values: +List<Doc.Property>, +name: String) -> String:
  match values:
    case Nil{}: ""
    case Con{Doc.Property{current, value}, rest}:
      selected_property(String.eq(current, name), value, property_value(rest, name))

def rich_body(+values: +List<Doc.Property>) -> (String & (String & (String & String))):
  (property_value(values, "--rich-body-font"), (property_value(values, "--rich-body-size"),
    (property_value(values, "--rich-body-line"), property_value(values, "--rich-body-weight"))))

def rich_strong(+values: +List<Doc.Property>) -> (String & (String & (String & String))):
  (property_value(values, "--rich-body-strong-font"), (property_value(values, "--rich-body-strong-size"),
    (property_value(values, "--rich-body-strong-line"), property_value(values, "--rich-body-strong-weight"))))

def text_style(+style: T.TextStyle) -> (String & (String & (String & String))):
  (T.font_family(T.resolved_font(style)), (Paint.px(T.resolved_size(style)),
    (Paint.px(T.resolved_line_height(style)), Nat.show(T.resolved_weight(style)))))

type Requirements is Type:
  Requirements{
    focus_projection: @+paint:Design.Paint -> @+width:Nat -> @+inset:Nat ->
      {Paint.focus_indicator_style(Design.FocusIndicator{paint, width, inset}) ==
        [Doc.Property{"--native-focus-ring", Paint.paint(paint)},
         Doc.Property{"--native-focus-width", Paint.px(width)},
         Doc.Property{"--native-focus-offset", "-" ++ Paint.px(Nat.add(inset, width))}] : +List<Doc.Property>},
    focus_outer_edge: @paint:Design.Paint -> @width:Nat -> @inset:Nat ->
      {Design.focus_indicator_outer_inset(Design.FocusIndicator{paint, width, inset}) == inset : Nat},
    focus_inner_edge: @paint:Design.Paint -> @+width:Nat -> @+inset:Nat ->
      {Design.focus_indicator_inner_inset(Design.FocusIndicator{paint, width, inset}) == Nat.add(inset, width) : Nat},
    parent_body: @+capacity:Nat -> @+parent:T.Presentation ->
      {rich_body(Paint.rich_properties_at(capacity, parent)) == text_style(T.resolve_presentation(capacity, parent)) : (String & (String & (String & String)))},
    parent_strong: @+capacity:Nat -> @+parent:T.Presentation ->
      {rich_strong(Paint.rich_properties_at(capacity, parent)) == text_style(T.resolve_presentation(capacity, T.with_emphasis(parent, T.Strong{}))) : (String & (String & (String & String)))},
    code_family: @+capacity:Nat -> @+parent:T.Presentation ->
      {property_value(Paint.rich_properties_at(capacity, parent), "--rich-code-font") == "var(--font-mono, monospace)" : String}}

law evidence:
  Requirements
