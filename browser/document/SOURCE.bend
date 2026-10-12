import Base
import ../../bendlib/categories.bend as Categories
import ../reading/MODEL.bend as ReadingBinding
import ../../interaction/IDENTITY.bend as Identity
import ../layout/GEOMETRY.bend as Spatial
import ../layout/enclosure.bend as Enclosure
import ../layout/physical-space.bend as Model
import ../appearance/DESIGN.bend as Design
import ../appearance/TYPOGRAPHY.bend as T
import ./MODEL.bend as Doc
import ../../interaction/conversation/CODE.bend as Code

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
  IdAttribute{value: String}
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
    case IdAttribute{value}: [Doc.Property{"id", value}]
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

def native_code_direction_valid(direction: Model.Direction) -> Bool:
  match direction:
    case Model.Horizontal{}: False{}
    case Model.Vertical{}: True{}
    case Model.Layered{}: False{}
    case Model.ResponsiveHorizontal{}: False{}

def native_code_alignment_valid(alignment: Spatial.Alignment) -> Bool:
  match alignment:
    case Spatial.Stretch{}: False{}
    case Spatial.Leading{}: True{}
    case Spatial.Trailing{}: False{}
    case Spatial.Centered{}: False{}

def native_code_size_valid(size: Model.AxisSize) -> Bool:
  match size:
    case Model.NaturalSize{}: True{}
    case Model.StretchSize{}: False{}
    case Model.CappedStretchSize{maximum}: False{}
    case Model.ExactSize{extent}: False{}
    case Model.LimitedSize{minimum, preferred_extra, maximum_extra}: False{}
    case Model.PercentSize{percent}: False{}
    case Model.CappedNaturalSize{maximum_percent}: False{}
    case Model.AdaptiveNaturalSize{preferred_maximum_percent}: False{}

def native_code_scroll_valid(scroll: Model.Scroll) -> Bool:
  match scroll:
    case Model.Confined{}: True{}
    case Model.ScrollHorizontally{}: False{}
    case Model.ScrollVertically{}: False{}
    case Model.ScrollBoth{}: False{}

def native_code_position_valid(position: Spatial.Position) -> Bool:
  match position:
    case Spatial.InFlow{}: True{}
    case Spatial.CenteredLayer{outside}: False{}
    case Spatial.AlignedLayer{outside, horizontal, vertical}: False{}
    case Spatial.AnchoredLayer{anchor_key, anchor, outside, gap, alignment}: False{}

def native_code_layout_valid(layout: Layout) -> Bool:
  Layout{direction, main_alignment, cross_alignment, +frame, width, height,
    Enclosure.Extent{minimum_width, minimum_height}, scroll, position} = layout
  native_code_direction_valid(direction)
    && native_code_alignment_valid(main_alignment) && native_code_alignment_valid(cross_alignment)
    && native_code_size_valid(width) && native_code_size_valid(height)
    && Nat.is_eq(minimum_width, 0n) && Nat.is_eq(minimum_height, 0n)
    && native_code_scroll_valid(scroll) && native_code_position_valid(position)
    && Nat.is_eq(Enclosure.inline(Enclosure.frame_content(frame)), 0n)
    && Nat.is_eq(Enclosure.block(Enclosure.frame_content(frame)), 0n)
    && Nat.is_eq(Enclosure.frame_gap(frame), 0n)

def native_code_chrome_valid(chrome: Design.Chrome) -> Bool:
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  Nat.is_eq(border_width, 0n)

def native_code_policy_valid(style: ResolvedStyle) -> Bool:
  ResolvedStyle{layout, font, chrome, states} = style
  native_code_layout_valid(layout) && native_code_chrome_valid(chrome)

# These construction axes preserve declarations; domain policy and physical
# frame validity remain obligations of their owning computations.

type BoxRequest is Data:
  BoxRequest{key: Identity.Key, tag: BoxTag, style: Style, attributes: +List<Attribute>, children: +List<Node>}

type BoxObservation is Data:
  BoxObservation{request: BoxRequest, result: Node}

def box_source(request: BoxRequest) -> Node:
  BoxRequest{key, tag, style, attributes, children} = request
  Box{key, tag, style, attributes, children}

def box_identity_of(node: Node) -> Maybe<&2, Identity.Key>:
  match node:
    case Box{key, tag, style, attributes, children}: Some{key}
    case _: None{}

def box_identity(observation: BoxObservation) -> Type:
  BoxObservation{request, result} = observation
  BoxRequest{key, tag, style, attributes, children} = request
  {box_identity_of(result) == Some{key} : Maybe<&2, Identity.Key>}

def box_presentation_of(node: Node) -> Maybe<&2, Sigma<&2, &2, BoxTag, (_ => Style)>>:
  match node:
    case Box{key, tag, style, attributes, children}: Some{(tag, style)}
    case _: None{}

def box_presentation(observation: BoxObservation) -> Type:
  BoxObservation{request, result} = observation
  BoxRequest{key, tag, style, attributes, children} = request
  {box_presentation_of(result) == Some{(tag, style)} : Maybe<&2, Sigma<&2, &2, BoxTag, (_ => Style)>>}

def box_attributes_of(node: Node) -> Maybe<&2, +List<Attribute>>:
  match node:
    case Box{key, tag, style, attributes, children}: Some{attributes}
    case _: None{}

def box_attributes(observation: BoxObservation) -> Type:
  BoxObservation{request, result} = observation
  BoxRequest{key, tag, style, attributes, children} = request
  {box_attributes_of(result) == Some{attributes} : Maybe<&2, +List<Attribute>>}

def box_population_of(node: Node) -> Maybe<&2, +List<Node>>:
  match node:
    case Box{key, tag, style, attributes, children}: Some{children}
    case _: None{}

def box_population(observation: BoxObservation) -> Type:
  BoxObservation{request, result} = observation
  BoxRequest{key, tag, style, attributes, children} = request
  {box_population_of(result) == Some{children} : Maybe<&2, +List<Node>>}

def box_attributes_population(observation: BoxObservation) -> Type:
  Categories.intersection(BoxObservation, box_attributes, box_population, observation)

def box_presentation_attributes_population(observation: BoxObservation) -> Type:
  Categories.intersection(BoxObservation, box_presentation, box_attributes_population, observation)

def authored_box(observation: BoxObservation) -> Type:
  Categories.intersection(BoxObservation, box_identity, box_presentation_attributes_population, observation)

def project_box_identity(-observation: BoxObservation, evidence: authored_box(observation)) -> box_identity(observation):
  Categories.Intersection{identity, presentation_attributes_population} = evidence
  identity

def box_is_identity() -> Categories.Inclusion<BoxObservation, authored_box, box_identity>:
  Categories.Inclusion{observation => evidence => project_box_identity(observation, evidence)}

def project_box_presentation(-observation: BoxObservation, evidence: authored_box(observation)) -> box_presentation(observation):
  Categories.Intersection{identity, presentation_attributes_population} = evidence
  Categories.Intersection{presentation, attributes_population} = presentation_attributes_population
  presentation

def box_is_presentation() -> Categories.Inclusion<BoxObservation, authored_box, box_presentation>:
  Categories.Inclusion{observation => evidence => project_box_presentation(observation, evidence)}

def project_box_attributes(-observation: BoxObservation, evidence: authored_box(observation)) -> box_attributes(observation):
  Categories.Intersection{identity, presentation_attributes_population} = evidence
  Categories.Intersection{presentation, attributes_population} = presentation_attributes_population
  Categories.Intersection{attributes, population} = attributes_population
  attributes

def box_is_attributes() -> Categories.Inclusion<BoxObservation, authored_box, box_attributes>:
  Categories.Inclusion{observation => evidence => project_box_attributes(observation, evidence)}

def project_box_population(-observation: BoxObservation, evidence: authored_box(observation)) -> box_population(observation):
  Categories.Intersection{identity, presentation_attributes_population} = evidence
  Categories.Intersection{presentation, attributes_population} = presentation_attributes_population
  Categories.Intersection{attributes, population} = attributes_population
  population

def box_is_population() -> Categories.Inclusion<BoxObservation, authored_box, box_population>:
  Categories.Inclusion{observation => evidence => project_box_population(observation, evidence)}

def box_construction_evidence(+request: BoxRequest) -> authored_box(BoxObservation{request, box_source(request)}):
  BoxRequest{key, tag, style, attributes, children} = request
  Categories.Intersection{{==}, Categories.Intersection{{==}, Categories.Intersection{{==}, {==}}}}

def construct_box(+request: BoxRequest) -> Categories.Membership<BoxObservation, authored_box>:
  Categories.Membership{BoxObservation{request, box_source(request)}, box_construction_evidence(request)}

def constructed_box_node(constructed: Categories.Membership<BoxObservation, authored_box>) -> Node:
  Categories.Membership{BoxObservation{request, result}, evidence} = constructed
  result

type TextRequest is Data:
  TextRequest{key: Identity.Key, value: String, font: FontChoice, wrapping: T.Wrapping}

type TextObservation is Data:
  TextObservation{request: TextRequest, result: Node}

def text_source(request: TextRequest) -> Node:
  TextRequest{key, value, font, wrapping} = request
  Text{key, value, font, wrapping}

def text_identity_of(node: Node) -> Maybe<&2, Identity.Key>:
  match node:
    case Text{key, value, font, wrapping}: Some{key}
    case _: None{}

def text_identity(observation: TextObservation) -> Type:
  TextObservation{request, result} = observation
  TextRequest{key, value, font, wrapping} = request
  {text_identity_of(result) == Some{key} : Maybe<&2, Identity.Key>}

def text_content_of(node: Node) -> Maybe<&2, String>:
  match node:
    case Text{key, value, font, wrapping}: Some{value}
    case _: None{}

def text_content(observation: TextObservation) -> Type:
  TextObservation{request, result} = observation
  TextRequest{key, value, font, wrapping} = request
  {text_content_of(result) == Some{value} : Maybe<&2, String>}

def text_font_of(node: Node) -> Maybe<&2, FontChoice>:
  match node:
    case Text{key, value, font, wrapping}: Some{font}
    case _: None{}

def text_font(observation: TextObservation) -> Type:
  TextObservation{request, result} = observation
  TextRequest{key, value, font, wrapping} = request
  {text_font_of(result) == Some{font} : Maybe<&2, FontChoice>}

def text_wrapping_of(node: Node) -> Maybe<&2, T.Wrapping>:
  match node:
    case Text{key, value, font, wrapping}: Some{wrapping}
    case _: None{}

def text_wrapping(observation: TextObservation) -> Type:
  TextObservation{request, result} = observation
  TextRequest{key, value, font, wrapping} = request
  {text_wrapping_of(result) == Some{wrapping} : Maybe<&2, T.Wrapping>}

def text_font_wrapping(observation: TextObservation) -> Type:
  Categories.intersection(TextObservation, text_font, text_wrapping, observation)

def text_content_font_wrapping(observation: TextObservation) -> Type:
  Categories.intersection(TextObservation, text_content, text_font_wrapping, observation)

def authored_text(observation: TextObservation) -> Type:
  Categories.intersection(TextObservation, text_identity, text_content_font_wrapping, observation)

def project_text_identity(-observation: TextObservation, evidence: authored_text(observation)) -> text_identity(observation):
  Categories.Intersection{identity, content_font_wrapping} = evidence
  identity

def text_is_identity() -> Categories.Inclusion<TextObservation, authored_text, text_identity>:
  Categories.Inclusion{observation => evidence => project_text_identity(observation, evidence)}

def project_text_content(-observation: TextObservation, evidence: authored_text(observation)) -> text_content(observation):
  Categories.Intersection{identity, content_font_wrapping} = evidence
  Categories.Intersection{content, font_wrapping} = content_font_wrapping
  content

def text_is_content() -> Categories.Inclusion<TextObservation, authored_text, text_content>:
  Categories.Inclusion{observation => evidence => project_text_content(observation, evidence)}

def project_text_font(-observation: TextObservation, evidence: authored_text(observation)) -> text_font(observation):
  Categories.Intersection{identity, content_font_wrapping} = evidence
  Categories.Intersection{content, font_wrapping} = content_font_wrapping
  Categories.Intersection{font, wrapping} = font_wrapping
  font

def text_is_font() -> Categories.Inclusion<TextObservation, authored_text, text_font>:
  Categories.Inclusion{observation => evidence => project_text_font(observation, evidence)}

def project_text_wrapping(-observation: TextObservation, evidence: authored_text(observation)) -> text_wrapping(observation):
  Categories.Intersection{identity, content_font_wrapping} = evidence
  Categories.Intersection{content, font_wrapping} = content_font_wrapping
  Categories.Intersection{font, wrapping} = font_wrapping
  wrapping

def text_is_wrapping() -> Categories.Inclusion<TextObservation, authored_text, text_wrapping>:
  Categories.Inclusion{observation => evidence => project_text_wrapping(observation, evidence)}

def text_construction_evidence(+request: TextRequest) -> authored_text(TextObservation{request, text_source(request)}):
  TextRequest{key, value, font, wrapping} = request
  Categories.Intersection{{==}, Categories.Intersection{{==}, Categories.Intersection{{==}, {==}}}}

def construct_text(+request: TextRequest) -> Categories.Membership<TextObservation, authored_text>:
  Categories.Membership{TextObservation{request, text_source(request)}, text_construction_evidence(request)}

def constructed_text_node(constructed: Categories.Membership<TextObservation, authored_text>) -> Node:
  Categories.Membership{TextObservation{request, result}, evidence} = constructed
  result

type ControlRequest is Data:
  ControlRequest{key: Identity.Key, tag: ControlTag, style: Style, attributes: +List<Attribute>, accessible_name: String, enabled: Bool, first_event: Doc.DOMEvent, remaining_events: +List<Doc.DOMEvent>, children: +List<Node>}

type ControlObservation is Data:
  ControlObservation{request: ControlRequest, result: Node}

def control_source(request: ControlRequest) -> Node:
  ControlRequest{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children} = request
  Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}

def control_identity_of(node: Node) -> Maybe<&2, Identity.Key>:
  match node:
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: Some{key}
    case _: None{}

def control_identity(observation: ControlObservation) -> Type:
  ControlObservation{request, result} = observation
  ControlRequest{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children} = request
  {control_identity_of(result) == Some{key} : Maybe<&2, Identity.Key>}

def control_presentation_of(node: Node) -> Maybe<&2, Sigma<&2, &2, ControlTag, (_ => Style)>>:
  match node:
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: Some{(tag, style)}
    case _: None{}

def control_presentation(observation: ControlObservation) -> Type:
  ControlObservation{request, result} = observation
  ControlRequest{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children} = request
  {control_presentation_of(result) == Some{(tag, style)} : Maybe<&2, Sigma<&2, &2, ControlTag, (_ => Style)>>}

def control_metadata_of(node: Node) -> Maybe<&2, Sigma<&2, &2, +List<Attribute>, (_ => String)>>:
  match node:
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: Some{(attributes, accessible_name)}
    case _: None{}

def control_metadata(observation: ControlObservation) -> Type:
  ControlObservation{request, result} = observation
  ControlRequest{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children} = request
  {control_metadata_of(result) == Some{(attributes, accessible_name)} : Maybe<&2, Sigma<&2, &2, +List<Attribute>, (_ => String)>>}

def control_interaction_of(node: Node) -> Maybe<&2, Sigma<&2, &2, Bool, (_ => Sigma<&2, &2, Doc.DOMEvent, (_ => +List<Doc.DOMEvent>)>)>>:
  match node:
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: Some{(enabled, (first_event, remaining_events))}
    case _: None{}

def control_interaction(observation: ControlObservation) -> Type:
  ControlObservation{request, result} = observation
  ControlRequest{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children} = request
  {control_interaction_of(result) == Some{(enabled, (first_event, remaining_events))} : Maybe<&2, Sigma<&2, &2, Bool, (_ => Sigma<&2, &2, Doc.DOMEvent, (_ => +List<Doc.DOMEvent>)>)>>}

def control_population_of(node: Node) -> Maybe<&2, +List<Node>>:
  match node:
    case Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: Some{children}
    case _: None{}

def control_population(observation: ControlObservation) -> Type:
  ControlObservation{request, result} = observation
  ControlRequest{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children} = request
  {control_population_of(result) == Some{children} : Maybe<&2, +List<Node>>}

def control_interaction_population(observation: ControlObservation) -> Type:
  Categories.intersection(ControlObservation, control_interaction, control_population, observation)

def control_metadata_interaction_population(observation: ControlObservation) -> Type:
  Categories.intersection(ControlObservation, control_metadata, control_interaction_population, observation)

def control_presentation_metadata_interaction_population(observation: ControlObservation) -> Type:
  Categories.intersection(ControlObservation, control_presentation, control_metadata_interaction_population, observation)

def authored_control(observation: ControlObservation) -> Type:
  Categories.intersection(ControlObservation, control_identity, control_presentation_metadata_interaction_population, observation)

def project_control_identity(-observation: ControlObservation, evidence: authored_control(observation)) -> control_identity(observation):
  Categories.Intersection{identity, presentation_metadata_interaction_population} = evidence
  identity

def control_is_identity() -> Categories.Inclusion<ControlObservation, authored_control, control_identity>:
  Categories.Inclusion{observation => evidence => project_control_identity(observation, evidence)}

def project_control_presentation(-observation: ControlObservation, evidence: authored_control(observation)) -> control_presentation(observation):
  Categories.Intersection{identity, presentation_metadata_interaction_population} = evidence
  Categories.Intersection{presentation, metadata_interaction_population} = presentation_metadata_interaction_population
  presentation

def control_is_presentation() -> Categories.Inclusion<ControlObservation, authored_control, control_presentation>:
  Categories.Inclusion{observation => evidence => project_control_presentation(observation, evidence)}

def project_control_metadata(-observation: ControlObservation, evidence: authored_control(observation)) -> control_metadata(observation):
  Categories.Intersection{identity, presentation_metadata_interaction_population} = evidence
  Categories.Intersection{presentation, metadata_interaction_population} = presentation_metadata_interaction_population
  Categories.Intersection{metadata, interaction_population} = metadata_interaction_population
  metadata

def control_is_metadata() -> Categories.Inclusion<ControlObservation, authored_control, control_metadata>:
  Categories.Inclusion{observation => evidence => project_control_metadata(observation, evidence)}

def project_control_interaction(-observation: ControlObservation, evidence: authored_control(observation)) -> control_interaction(observation):
  Categories.Intersection{identity, presentation_metadata_interaction_population} = evidence
  Categories.Intersection{presentation, metadata_interaction_population} = presentation_metadata_interaction_population
  Categories.Intersection{metadata, interaction_population} = metadata_interaction_population
  Categories.Intersection{interaction, population} = interaction_population
  interaction

def control_is_interaction() -> Categories.Inclusion<ControlObservation, authored_control, control_interaction>:
  Categories.Inclusion{observation => evidence => project_control_interaction(observation, evidence)}

def project_control_population(-observation: ControlObservation, evidence: authored_control(observation)) -> control_population(observation):
  Categories.Intersection{identity, presentation_metadata_interaction_population} = evidence
  Categories.Intersection{presentation, metadata_interaction_population} = presentation_metadata_interaction_population
  Categories.Intersection{metadata, interaction_population} = metadata_interaction_population
  Categories.Intersection{interaction, population} = interaction_population
  population

def control_is_population() -> Categories.Inclusion<ControlObservation, authored_control, control_population>:
  Categories.Inclusion{observation => evidence => project_control_population(observation, evidence)}

def control_construction_evidence(+request: ControlRequest) -> authored_control(ControlObservation{request, control_source(request)}):
  ControlRequest{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children} = request
  Categories.Intersection{{==}, Categories.Intersection{{==}, Categories.Intersection{{==}, Categories.Intersection{{==}, {==}}}}}

def construct_control(+request: ControlRequest) -> Categories.Membership<ControlObservation, authored_control>:
  Categories.Membership{ControlObservation{request, control_source(request)}, control_construction_evidence(request)}

def constructed_control_node(constructed: Categories.Membership<ControlObservation, authored_control>) -> Node:
  Categories.Membership{ControlObservation{request, result}, evidence} = constructed
  result
