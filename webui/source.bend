import Base
import ./reading-binding.bend as ReadingBinding
import ../core/ui-identity.bend as Identity
import ../bendlib/stdlib.bend as Std
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ./physical-space.bend as Model
import ./design.bend as Design
import ./typography.bend as T
import ./document.bend as Doc
import ../core/code-block.bend as Code

type Layout is Data:
  Layout{direction: Model.Direction, main_alignment: Spatial.Alignment,
    cross_alignment: Spatial.Alignment, frame: Enclosure.Frame,
    width: Model.AxisSize, height: Model.AxisSize, minimum: Enclosure.Extent,
    scroll: Model.Scroll, position: Spatial.Position}

type FontChoice is Data:
  InheritFont{}
  ExplicitFont{presentation: T.Presentation}

type Style is Data:
  Style{layout: Layout, font: FontChoice, chrome: Design.Chrome, states: Design.ControlStates}

type ResolvedStyle is Data:
  ResolvedStyle{layout: Layout, font: T.Presentation, chrome: Design.Chrome, states: Design.ControlStates}

type BoxTag is Data:
  Article{}
  Details{}
  Div{}
  Footer{}
  Heading2{}
  Heading3{}
  Header{}
  Label{}
  Main{}
  Navigation{}
  Option{}
  Output{}
  Paragraph{}
  Section{}
  Span{}
  Strong{}

type ControlTag is Data:
  Button{}
  Summary{}
  ArticleControl{}
  DivControl{}
  SectionControl{}
  SpanControl{}

type NativeFieldKind is Data:
  TextField{}
  MessageField{}
  TextAreaField{}
  SelectField{}
  MultiSelectField{}
  ToggleField{}
  NumberField{minimum: Nat}
  FileField{multiple: Bool}
  DirectoryField{}
  SearchField{}
  SecretField{}

type ToggleGeometry is Data:
  ToggleGeometry{visual_size: Nat, target_size: Nat}

def native_toggle_geometry() -> ToggleGeometry:
  ToggleGeometry{16n, 32n}

def toggle_visual_size(value: ToggleGeometry) -> Nat:
  ToggleGeometry{visual_size, target_size} = value
  visual_size

def toggle_target_size(value: ToggleGeometry) -> Nat:
  ToggleGeometry{visual_size, target_size} = value
  target_size

def toggle_center_offset(value: ToggleGeometry) -> Nat:
  ToggleGeometry{visual_size, target_size} = value
  Nat.div(Nat.sub(target_size, visual_size), 2n)

def native_field_appearance(kind: NativeFieldKind) -> String:
  "none"

type Attribute is Data:
  ReadingAttribute{binding: ReadingBinding.Binding}
  EditorBindingAttribute{key: Identity.Key}
  DataAttribute{name: String, value: String}
  AriaAttribute{name: String, value: String}
  RoleAttribute{value: String}
  TitleAttribute{value: String}
  TabIndexAttribute{value: String}
  ValueAttribute{value: String}
  CheckedAttribute{}
  OpenAttribute{}
  DraggableAttribute{value: String}
  InertAttribute{}

type FieldPolicy is Data:
  FieldPolicy{minimum_columns: Nat, minimum_lines: Nat, maximum_lines: Nat}

type Choice is Data:
  Choice{value: String, label: String, selected: Bool}

type DrawingPath is Data:
  DrawingPath{data: String}

type DrawingPaint is Data:
  FilledDrawing{}
  StrokedDrawing{weight_tenths: Nat}

type Drawing is Data:
  Drawing{view_box: String, paths: +List<DrawingPath>, width: Nat, height: Nat, paint: DrawingPaint}

type CodeSurface is Data:
  CodeSurface{frame: Enclosure.Frame, chrome: Design.Chrome}

def code_surface_frame(value: CodeSurface) -> Enclosure.Frame:
  CodeSurface{frame, chrome} = value
  frame

def code_surface_chrome(value: CodeSurface) -> Design.Chrome:
  CodeSurface{frame, chrome} = value
  chrome

type RichPolicy is Data:
  RichPolicy{code_surface: CodeSurface, toolbar_height: Nat, block_gap: Nat,
    list_indent: Nat, code_text: T.Presentation, wrap: Bool}

def rich_policy_code_surface(value: RichPolicy) -> CodeSurface:
  RichPolicy{surface, toolbar_height, block_gap, list_indent, code_text, wrap} = value
  surface

type RichContent is Data:
  RichContent{source: Maybe<&2, Code.Source>, value: String, policy: RichPolicy}

type NativeTarget is Data:
  ToolbarTarget{identity: Code.Identity}
  CodeBodyTarget{identity: Code.Identity, wrap: Bool}

type Node is Data:
  NativeAttachment{key: Identity.Key, target: NativeTarget, attributes: +List<Attribute>,
    style: Style, children: +List<Node>}

  Box{key: Identity.Key, tag: BoxTag, style: Style, attributes: +List<Attribute>, children: +List<Node>}
  Control{key: Identity.Key, tag: ControlTag, style: Style, attributes: +List<Attribute>,
    accessible_name: String, enabled: Bool, first_event: Doc.DOMEvent,
    remaining_events: +List<Doc.DOMEvent>, children: +List<Node>}
  Text{key: Identity.Key, value: String, font: FontChoice, wrapping: T.Wrapping}
  Glyph{key: Identity.Key, drawing: Drawing, style: Style}
  Field{key: Identity.Key, kind: NativeFieldKind, style: Style, attributes: +List<Attribute>,
    value: String, placeholder: String, options: +List<Choice>, policy: FieldPolicy,
    accessible_name: String, enabled: Bool, first_event: Doc.DOMEvent, remaining_events: +List<Doc.DOMEvent>}
  RichText{key: Identity.Key, style: Style, content: RichContent, attachments: +List<Node>, native_owner: Maybe<&2, String>}

def resolve_font(choice: FontChoice, parent: T.Presentation) -> T.Presentation:
  match choice:
    case InheritFont{}: parent
    case ExplicitFont{presentation}: presentation

def resolve_style(style: Style, parent: T.Presentation) -> ResolvedStyle:
  Style{layout, font, chrome, states} = style
  ResolvedStyle{layout, resolve_font(font, parent), chrome, states}

def physical_rule(style: ResolvedStyle) -> Model.Rule:
  ResolvedStyle{layout, font, chrome, states} = style
  Layout{direction, main_alignment, cross_alignment, frame, width, height, minimum, scroll, position} = layout
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  Model.Rule{direction, main_alignment, cross_alignment, frame, border_width, width, height, minimum, scroll, position}

# The toggle border paints an inner visual square; its native hit area has no border.
def native_field_layout(kind: NativeFieldKind, +rule: Model.Rule) -> Model.Rule:
  match kind:
    case ToggleField{}:
      Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
      Model.Rule{direction, main, cross, frame, 0n, width, height, minimum, scroll, position}
    case _: rule

def native_field_rule(kind: NativeFieldKind, style: ResolvedStyle) -> Model.Rule:
  native_field_layout(kind, physical_rule(style))

def box_tag_name(tag: BoxTag) -> String:
  match tag:
    case Article{}: "article"
    case Details{}: "details"
    case Div{}: "div"
    case Footer{}: "footer"
    case Heading2{}: "h2"
    case Heading3{}: "h3"
    case Header{}: "header"
    case Label{}: "label"
    case Main{}: "main"
    case Navigation{}: "nav"
    case Option{}: "option"
    case Output{}: "output"
    case Paragraph{}: "p"
    case Section{}: "section"
    case Span{}: "span"
    case Strong{}: "strong"

def control_tag_name(tag: ControlTag) -> String:
  match tag:
    case Button{}: "button"
    case Summary{}: "summary"
    case ArticleControl{}: "article"
    case DivControl{}: "div"
    case SectionControl{}: "section"
    case SpanControl{}: "span"

def attribute_properties(attribute: Attribute) -> +List<Doc.Property>:
  match attribute:
    case ReadingAttribute{ReadingBinding.Binding{ReadingBinding.Context{task, generation}, part}}:
      [Doc.Property{"data-reading-task", Nat.show(task)}, Doc.Property{"data-reading-generation", Nat.show(generation)}, Doc.Property{"data-reading-" ++ ReadingBinding.part_name(part), ""}]
    case EditorBindingAttribute{key}: [Doc.Property{"data-native-editor-key", Identity.encode(key)}]
    case DataAttribute{name, value}: [Doc.Property{"data-" ++ name, value}]
    case AriaAttribute{name, value}: [Doc.Property{"aria-" ++ name, value}]
    case RoleAttribute{value}: [Doc.Property{"role", value}]
    case TitleAttribute{value}: [Doc.Property{"title", value}]
    case TabIndexAttribute{value}: [Doc.Property{"tabindex", value}]
    case ValueAttribute{value}: [Doc.Property{"value", value}]
    case CheckedAttribute{}: [Doc.Property{"checked", ""}]
    case OpenAttribute{}: [Doc.Property{"open", ""}]
    case DraggableAttribute{value}: [Doc.Property{"draggable", value}]
    case InertAttribute{}: [Doc.Property{"inert", ""}]

def key_of(node: Node) -> Identity.Key:
  match node:
    case Box{key, tag, style, attributes, children}: key
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: key
    case Text{key, value, font, wrapping}: key
    case Glyph{key, drawing, style}: key
    case Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: key
    case RichText{key, style, content, attachments, native_owner}: key
    case NativeAttachment{key, target, attributes, style, children}: key

def children_of(node: Node) -> +List<Node>:
  match node:
    case Box{key, tag, style, attributes, children}: children
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: children
    case Text{key, value, font, wrapping}: Nil{}
    case Glyph{key, drawing, style}: Nil{}
    case Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: Nil{}
    case RichText{key, style, content, attachments, native_owner}: attachments
    case NativeAttachment{key, target, attributes, style, children}: children

def events_of(node: Node) -> +List<Doc.DOMEvent>:
  match node:
    case Box{key, tag, style, attributes, children}: Nil{}
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: first_event <> remaining_events
    case Text{key, value, font, wrapping}: Nil{}
    case Glyph{key, drawing, style}: Nil{}
    case Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: first_event <> remaining_events
    case RichText{key, style, content, attachments, native_owner}: Nil{}
    case NativeAttachment{key, target, attributes, style, children}: Nil{}

def interaction_of(node: Node) -> Model.Interaction<Doc.DOMEvent>:
  match node:
    case Box{key, tag, style, attributes, children}: Model.DisplayOnly{}
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: Model.Operable{first_event, remaining_events, enabled}
    case Text{key, value, font, wrapping}: Model.DisplayOnly{}
    case Glyph{key, drawing, style}: Model.DisplayOnly{}
    case Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: Model.Operable{first_event, remaining_events, enabled}
    case RichText{key, style, content, attachments, native_owner}: Model.DisplayOnly{}
    case NativeAttachment{key, target, attributes, style, children}: Model.DisplayOnly{}

def drawing_paint_valid(paint: DrawingPaint) -> Bool:
  match paint:
    case FilledDrawing{}: True{}
    case StrokedDrawing{weight_tenths}: Nat.is_le(1n, weight_tenths)

def target_key(target: NativeTarget) -> String:
  match target:
    case ToolbarTarget{identity}: Code.dom_key(identity) ++ "/toolbar"
    case CodeBodyTarget{identity, wrap}: Code.dom_key(identity) ++ "/code"

def field_policy_valid(policy: FieldPolicy) -> Bool:
  FieldPolicy{minimum_columns, +minimum_lines, maximum_lines} = policy
  Nat.is_le(1n, minimum_columns) && Nat.is_le(1n, minimum_lines) && Nat.is_le(minimum_lines, maximum_lines)

# The extras encode strictly positive viewport minima and a nonnegative range.
def field_policy(columns_extra: Nat, +lines_extra: Nat, additional_lines: Nat) -> FieldPolicy:
  FieldPolicy{1n+columns_extra, 1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)}
