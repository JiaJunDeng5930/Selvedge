import Base
import ./physical-content.bend as Content
import ./physical-allocation.bend as Allocation
import ./physical-space.bend as Model
import ./source.bend as Source
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ./typography.bend as T
import ./design.bend as Design
import ./paint.bend as Paint
import ./document.bend as Doc

def choose(~A: Data, +condition: Bool, +yes: A, +no: A) -> A:
  match condition:
    case True{}: yes
    case False{}: no

type Owned is Data:
  Owned{+owner_key: String, +node: Doc.Node}

def properties(+first: +List<Doc.Property>, +second: +List<Doc.Property>) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, first, second)

def attributes(+values: +List<Source.Attribute>) -> +List<Doc.Property>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, +rest}: Source.encode_attribute(value) <> attributes(rest)

def wrapping(+value: T.Wrapping) -> +List<Doc.Property>:
  [Paint.property("white-space", T.white_space(value)), Paint.property("overflow-wrap", T.overflow_wrap(value)),
   Paint.property("word-break", T.word_break(value))]

def code_wrapping(+value: Bool) -> T.Wrapping:
  match value:
    case True{}: T.WrapAnywhere{}
    case False{}: T.ScrollableCode{}

def rich_styles(+font: T.Presentation, +policy: Source.RichPolicy) -> +List<Doc.Property>:
  Source.RichPolicy{Enclosure.Insets{+inline, +block}, +toolbar_height, +block_gap, +list_indent, +code_text, +wrap} = policy
  properties(properties(Paint.rich_properties(font), Paint.rich_resolved("--rich-code", T.resolved(code_text))), properties(Paint.text_presentation(T.with_tier(font, T.Body{})),
    [Paint.property("--physical-code-padding-inline", Paint.px(inline)), Paint.property("--physical-code-padding-block", Paint.px(block)),
     Paint.property("--physical-toolbar-height", Paint.px(toolbar_height)), Paint.property("--physical-block-gap", Paint.px(block_gap)),
     Paint.property("--physical-list-indent", Paint.px(list_indent)),
     Paint.property("--physical-code-white-space", T.white_space(code_wrapping(wrap))),
     Paint.property("--physical-code-overflow-wrap", T.overflow_wrap(code_wrapping(wrap)))]))

# Measurement and emission share primitive typography, without outer geometry.
def primitive_styles(+value: Content.Value) -> +List<Doc.Property>:
  match value:
    case Content.Value{Source.Text{+key, +text, +choice, +wrap}, +font}: properties(Paint.text_presentation(font), wrapping(wrap))
    case Content.Value{Source.RichText{+key, +style, Source.RichContent{+source, +text, +policy}, +attachments}, +font}: rich_styles(font, policy)
    case Content.Value{Source.Field{+key, +kind, +style, +attrs, +text, +placeholder, +options, +policy, +name, +enabled, +first, +remaining}, +font}: Paint.text_presentation(font)
    case Content.Value{Source.Glyph{+key, +drawing, +style}, +font}: Paint.text_presentation(font)
    case Content.Value{Source.Box{+key, +tag, +style, +attrs, +children}, +font}: Paint.text_presentation(font)
    case Content.Value{Source.Control{+key, +tag, +style, +attrs, +name, +enabled, +first, +remaining, +children}, +font}: Paint.text_presentation(font)
    case Content.Value{Source.NativeAttachment{+key, +target, +attrs, +style, +children}, +font}: Paint.text_presentation(font)

def shadow(+value: Bool) -> +List<Doc.Property>:
  match value:
    case True{}: [Paint.property("box-shadow", "var(--shadow-sm)")]
    case False{}: Nil{}

def chrome(+value: Design.Chrome) -> +List<Doc.Property>:
  Design.Chrome{+foreground, +background, +border, +width, +radius, +cast_shadow} = value
  properties([Paint.property("color", Paint.paint(foreground)), Paint.property("background", Paint.paint(background)),
    Paint.property("border-color", Paint.paint(border)), Paint.property("border-radius", Paint.px(radius))], shadow(cast_shadow))

def visual(+style: Source.Style) -> +List<Doc.Property>:
  Source.Style{+layout, +font, +surface, +states} = style
  properties(chrome(surface), Paint.states_style(states))

def overflow(+value: Model.Scroll) -> +List<Doc.Property>:
  match value:
    case Model.Confined{}: [Paint.property("overflow-x", "clip"), Paint.property("overflow-y", "clip")]
    case Model.ScrollHorizontally{}: [Paint.property("overflow-x", "auto"), Paint.property("overflow-y", "hidden")]
    case Model.ScrollVertically{}: [Paint.property("overflow-x", "hidden"), Paint.property("overflow-y", "auto")]
    case Model.ScrollBoth{}: [Paint.property("overflow-x", "auto"), Paint.property("overflow-y", "auto")]

def box_styles(+bounds: Spatial.Box, +origin: Spatial.Box, +fixed: Bool, +rule: Model.Rule) -> +List<Doc.Property>:
  Spatial.Box{+left, +top, +width, +height} = bounds
  Spatial.Box{+origin_left, +origin_top, +origin_width, +origin_height} = origin
  Model.Rule{+direction, +main, +cross, +frame, +border, +width_rule, +height_rule, +minimum, +scroll, position} = rule
  +position = choose(String, fixed, "fixed", "absolute")
  properties([Paint.property("position", position), Paint.property("display", "block"), Paint.property("left", Paint.px(Nat.sub(left, origin_left))),
    Paint.property("top", Paint.px(Nat.sub(top, origin_top))), Paint.property("width", Paint.px(width)), Paint.property("height", Paint.px(height)),
    Paint.property("min-width", "0"), Paint.property("min-height", "0"), Paint.property("max-width", "none"), Paint.property("max-height", "none"),
    Paint.property("margin", "0"), Paint.property("padding", "0"), Paint.property("box-sizing", "border-box"),
    Paint.property("border-style", "solid"), Paint.property("border-width", Paint.px(border))], overflow(scroll))

def child_origin(+bounds: Spatial.Box, +rule: Model.Rule) -> Spatial.Box:
  Spatial.Box{+left, +top, +width, +height} = bounds
  Model.Rule{+direction, +main, +cross, +frame, +border, +width_rule, +height_rule, +minimum, +scroll, position} = rule
  Spatial.Box{Nat.add(left, border), Nat.add(top, border), Nat.sub(width, Nat.mul(2n, border)), Nat.sub(height, Nat.mul(2n, border))}

def canvas(+key: String, +extent: Enclosure.Extent, +rule: Model.Rule, +children: +List<Doc.Node>) -> Doc.Node:
  Enclosure.Extent{+width, +height} = extent
  Model.Rule{+direction, +main, +cross, +frame, +border, +width_rule, +height_rule, +minimum, +scroll, position} = rule
  +insets = Enclosure.frame_content(frame)
  Doc.Element{key ++ "/physical-canvas", "div", Nil{},
    [Paint.property("position", "relative"), Paint.property("display", "block"), Paint.property("margin", "0"), Paint.property("padding", "0"),
     Paint.property("border", "0"), Paint.property("box-sizing", "border-box"),
     Paint.property("width", Paint.px(Nat.add(width, Nat.mul(2n, Enclosure.inline(insets))))),
     Paint.property("height", Paint.px(Nat.add(height, Nat.mul(2n, Enclosure.block(insets)))))], Nil{}, children}

def diagnostic(+key: String, +reason: String) -> Doc.Node:
  Doc.Element{key ++ "/invalid-physical-world", "div", [Paint.property("data-physical-error", reason)], Nil{}, Nil{}, [Doc.Text{"Invalid physical world: " ++ reason}]}

def event_list(+value: Model.Interaction<Doc.Event>) -> +List<Doc.Event>:
  match value:
    case Model.DisplayOnly{}: Nil{}
    case Model.Operable{+first, +remaining, +enabled}: first <> remaining

def availability(+value: Model.Interaction<Doc.Event>, +native: Bool) -> +List<Doc.Property>:
  match value:
    case Model.DisplayOnly{}: Nil{}
    case Model.Operable{+first, +remaining, True{}}: [Paint.property("aria-disabled", "false")]
    case Model.Operable{+first, +remaining, False{}}:
      choose(+List<Doc.Property>, native, [Paint.property("disabled", ""), Paint.property("aria-disabled", "true")], [Paint.property("aria-disabled", "true")])

def control_tabindex(+interaction: Model.Interaction<Doc.Event>) -> String:
  match interaction:
    case Model.DisplayOnly{}: "-1"
    case Model.Operable{first, remaining, True{}}: "0"
    case Model.Operable{first, remaining, False{}}: "-1"

def control_attributes(+tag: Source.ControlTag, +attrs: +List<Source.Attribute>, +name: String, +interaction: Model.Interaction<Doc.Event>) -> +List<Doc.Property>:
  match tag:
    case Source.Button{}: properties(attributes(attrs), Paint.property("type", "button") <> Paint.property("aria-label", name) <> availability(interaction, True{}))
    case Source.Summary{}: properties(attributes(attrs), Paint.property("aria-label", name) <> availability(interaction, False{}))
    case Source.ArticleControl{}: properties(attributes(attrs), properties([Paint.property("tabindex", control_tabindex(interaction)), Paint.property("role", "button"), Paint.property("aria-label", name)], availability(interaction, False{})))
    case Source.DivControl{}: properties(attributes(attrs), properties([Paint.property("tabindex", control_tabindex(interaction)), Paint.property("role", "button"), Paint.property("aria-label", name)], availability(interaction, False{})))
    case Source.SectionControl{}: properties(attributes(attrs), properties([Paint.property("tabindex", control_tabindex(interaction)), Paint.property("role", "button"), Paint.property("aria-label", name)], availability(interaction, False{})))
    case Source.SpanControl{}: properties(attributes(attrs), properties([Paint.property("tabindex", control_tabindex(interaction)), Paint.property("role", "button"), Paint.property("aria-label", name)], availability(interaction, False{})))

def choices(+values: +List<Source.Choice>, +key: String) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Source.Choice{+value, +label, +selected}, +rest}:
      Doc.Element{key ++ "/option/" ++ value, "option", Paint.property("value", value) <> choose(+List<Doc.Property>, selected, [Paint.property("selected", "")], Nil{}), Nil{}, Nil{}, [Doc.Text{label}]} <> choices(rest, key)

def field_tag(+kind: Source.NativeFieldKind) -> String:
  match kind:
    case Source.TextField{}: "input"
    case Source.MessageField{}: "textarea"
    case Source.TextAreaField{}: "textarea"
    case Source.SelectField{}: "select"
    case Source.MultiSelectField{}: "select"
    case Source.ToggleField{}: "input"
    case Source.NumberField{+minimum}: "input"
    case Source.FileField{multiple}: "input"
    case Source.DirectoryField{}: "input"
    case Source.SearchField{}: "input"
    case Source.SecretField{}: "input"

def field_attributes(+kind: Source.NativeFieldKind, +value: String) -> +List<Doc.Property>:
  match kind:
    case Source.TextField{}: [Paint.property("type", "text"), Paint.property("value", value)]
    case Source.MessageField{}: [Paint.property("value", value)]
    case Source.TextAreaField{}: [Paint.property("value", value)]
    case Source.SelectField{}: [Paint.property("value", value)]
    case Source.MultiSelectField{}: [Paint.property("multiple", "")]
    case Source.ToggleField{}: [Paint.property("type", "checkbox"), Paint.property("value", value)]
    case Source.NumberField{+minimum}: [Paint.property("type", "number"), Paint.property("min", Nat.show(minimum)), Paint.property("value", value)]
    case Source.FileField{multiple}: Paint.property("type", "file") <>
      choose(+List<Doc.Property>, multiple, [Paint.property("multiple", "")], Nil{})
    case Source.DirectoryField{}: [Paint.property("type", "text"), Paint.property("value", value)]
    case Source.SearchField{}: [Paint.property("type", "search"), Paint.property("value", value)]
    case Source.SecretField{}: [Paint.property("type", "password"), Paint.property("value", value)]

def file_attributes(+values: +List<Source.Attribute>) -> +List<Doc.Property>:
  match values:
    case Nil{}: Nil{}
    case Con{Source.ValueAttribute{value}, rest}: file_attributes(rest)
    case Con{other, rest}: Source.encode_attribute(other) <> file_attributes(rest)

def field_authored(+kind: Source.NativeFieldKind, +values: +List<Source.Attribute>) -> +List<Doc.Property>:
  match kind:
    case Source.FileField{multiple}: file_attributes(values)
    case Source.TextField{}: attributes(values)
    case Source.MessageField{}: attributes(values)
    case Source.TextAreaField{}: attributes(values)
    case Source.SelectField{}: attributes(values)
    case Source.MultiSelectField{}: attributes(values)
    case Source.ToggleField{}: attributes(values)
    case Source.NumberField{minimum}: attributes(values)
    case Source.DirectoryField{}: attributes(values)
    case Source.SearchField{}: attributes(values)
    case Source.SecretField{}: attributes(values)

def field_padding(+rule: Model.Rule) -> +List<Doc.Property>:
  Model.Rule{+direction, +main, +cross, +frame, +border, +width, +height, +minimum, +scroll, position} = rule
  +insets = Enclosure.frame_content(frame)
  [Paint.property("padding-inline", Paint.px(Enclosure.inline(insets))), Paint.property("padding-block", Paint.px(Enclosure.block(insets))), Paint.property("appearance", "none")]

def owned_nodes(+values: +List<Owned>, +key: String) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Owned{+owner_key, +node}, +rest}:
      choose(+List<Doc.Node>, String.eq(owner_key, key), node <> owned_nodes(rest, key), owned_nodes(rest, key))

def drawing_offset(+alignment: Spatial.Alignment, +available: Nat, +size: Nat) -> Nat:
  match alignment:
    case Spatial.Stretch{}: 0n
    case Spatial.Leading{}: 0n
    case Spatial.Trailing{}: Nat.sub(available, size)
    case Spatial.Centered{}: Nat.div(Nat.sub(available, size), 2n)

def drawing_inline_alignment(direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment) -> Spatial.Alignment:
  match direction:
    case Model.Horizontal{}: main
    case Model.Vertical{}: cross
    case Model.Layered{}: cross
    case Model.ResponsiveHorizontal{}: main

def drawing_block_alignment(direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment) -> Spatial.Alignment:
  match direction:
    case Model.Horizontal{}: cross
    case Model.Vertical{}: main
    case Model.Layered{}: main
    case Model.ResponsiveHorizontal{}: cross

def paths(+values: +List<Source.DrawingPath>, +key: String) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Source.DrawingPath{+data}, +rest}:
      Doc.Element{key ++ "/path/" ++ data, "path", [Paint.property("d", data)], Nil{}, Nil{}, Nil{}} <> paths(rest, key)

def drawing_paint(paint: Source.DrawingPaint) -> +List<Doc.Property>:
  match paint:
    case Source.FilledDrawing{}: [Paint.property("fill", "currentColor"), Paint.property("stroke", "none")]
    case Source.StrokedDrawing{+weight_tenths}:
      [Paint.property("fill", "none"), Paint.property("stroke", "currentColor"),
       Paint.property("stroke-width", Nat.show(Nat.div(weight_tenths, 10n)) ++ "." ++ Nat.show(Nat.mod(weight_tenths, 10n))),
       Paint.property("stroke-linecap", "round"), Paint.property("stroke-linejoin", "round")]

def drawing(+key: String, +value: Source.Drawing, +bounds: Spatial.Box, +rule: Model.Rule) -> Doc.Node:
  Source.Drawing{+view_box, +path_values, +width, +height, paint} = value
  Spatial.Box{+left, +top, +outer_width, +outer_height} = bounds
  Model.Rule{+direction, +main, +cross, +frame, +border, +width_rule, +height_rule, +minimum, +scroll, position} = rule
  +insets = Enclosure.frame_content(frame)
  +inner_width = Nat.sub(outer_width, Nat.mul(2n, Nat.add(border, Enclosure.inline(insets))))
  +inner_height = Nat.sub(outer_height, Nat.mul(2n, Nat.add(border, Enclosure.block(insets))))
  choose(Doc.Node, Nat.is_le(width, inner_width) && Nat.is_le(height, inner_height),
    Doc.Element{key ++ "/svg", "svg", Paint.property("viewBox", view_box) <> Paint.property("aria-hidden", "true") <> drawing_paint(paint),
      [Paint.property("position", "absolute"), Paint.property("left", Paint.px(Nat.add(Enclosure.inline(insets), drawing_offset(drawing_inline_alignment(direction, main, cross), inner_width, width)))),
       Paint.property("top", Paint.px(Nat.add(Enclosure.block(insets), drawing_offset(drawing_block_alignment(direction, main, cross), inner_height, height)))), Paint.property("width", Paint.px(width)), Paint.property("height", Paint.px(height))], Nil{}, paths(path_values, key)},
    diagnostic(key, "drawing-exceeds-allocated-content"))

# The allocator has already excluded border and frame from this content extent.
def rich_content_frame(+key: String, extent: Enclosure.Extent, rule: Model.Rule, children: +List<Doc.Node>) -> Doc.Node:
  Enclosure.Extent{width, height} = extent
  Model.Rule{direction, main, cross, frame, border, width_rule, height_rule, minimum, scroll, position} = rule
  +insets = Enclosure.frame_content(frame)
  Doc.Element{key ++ "/content", "div", Nil{},
    [Paint.property("position", "absolute"), Paint.property("left", Paint.px(Enclosure.inline(insets))),
     Paint.property("top", Paint.px(Enclosure.block(insets))), Paint.property("width", Paint.px(width)), Paint.property("height", Paint.px(height)),
     Paint.property("margin", "0"), Paint.property("padding", "0"), Paint.property("border", "0"), Paint.property("box-sizing", "border-box")], Nil{}, children}

def leaf(+value: Content.Value, +physical_key: String, +bounds: Spatial.Box, +content_canvas: Enclosure.Extent, +rule: Model.Rule,
  +interaction: Model.Interaction<Doc.Event>, +styles: +List<Doc.Property>, +owned: +List<Owned>) -> Doc.Node:
  match value:
    case Content.Value{Source.Text{+key, +text, +choice, +wrap}, +font}:
      Doc.Element{key, "span", Nil{}, properties(styles, properties(primitive_styles(value), [Paint.property("text-overflow", "ellipsis")])), Nil{}, [Doc.Text{text}]}
    case Content.Value{Source.Glyph{+key, +picture, +style}, +font}:
      Doc.Element{key, "span", Nil{}, properties(styles, properties(primitive_styles(value), visual(style))), Nil{}, [drawing(key, picture, bounds, rule)]}
    case Content.Value{Source.Field{+key, +kind, +style, +attrs, +text, +placeholder, +options, +policy, +name, +enabled, +first, +remaining}, +font}:
      Doc.Element{key, field_tag(kind), properties(field_authored(kind, attrs), properties(field_attributes(kind, text),
        properties([Paint.property("class", "native-control"), Paint.property("placeholder", placeholder), Paint.property("aria-label", name)], availability(interaction, True{})))),
        properties(styles, properties(primitive_styles(value), properties(visual(style), field_padding(rule)))), event_list(interaction), choices(options, key)}
    case Content.Value{Source.RichText{+key, +style, Source.RichContent{+source, +text, +policy}, +attachments}, +font}:
      Doc.Element{key, "div", [Paint.property("class", "physical-markdown")], properties(styles, properties(primitive_styles(value), visual(style))), Nil{},
        [rich_content_frame(key, content_canvas, rule, Doc.Markdown{key ++ "/markdown", source, text} <> owned_nodes(owned, physical_key))]}
    case Content.Value{Source.Box{+key, +tag, +style, +attrs, +children}, +font}: diagnostic(key, "box-as-leaf")
    case Content.Value{Source.Control{+key, +tag, +style, +attrs, +name, +enabled, +first, +remaining, +children}, +font}: diagnostic(key, "control-as-leaf")
    case Content.Value{Source.NativeAttachment{+key, +target, +attrs, +style, +children}, +font}: diagnostic(key, "native-attachment-as-leaf")

def container(+value: Content.Value, +interaction: Model.Interaction<Doc.Event>, +styles: +List<Doc.Property>, +children: +List<Doc.Node>, +native: Bool) -> Doc.Node:
  match value:
    case Content.Value{Source.Box{+key, +tag, +style, +attrs, +original_children}, +font}:
      Doc.Element{key, Source.box_tag_name(tag), attributes(attrs), properties(styles, properties(primitive_styles(value), visual(style))), Nil{}, children}
    case Content.Value{Source.Control{+key, +tag, +style, +attrs, +name, +enabled, +first, +remaining, +original_children}, +font}:
      Doc.Element{key, Source.control_tag_name(tag), control_attributes(tag, attrs, name, interaction), properties(styles, properties(primitive_styles(value), visual(style))), event_list(interaction), children}
    case Content.Value{Source.NativeAttachment{+key, +target, +attrs, +style, +original_children}, +font}:
      choose(Doc.Node, native, Doc.Element{key, "div", attributes(attrs), properties(styles, properties(primitive_styles(value), visual(style))), Nil{}, children}, diagnostic(key, "native-attachment-outside-portal"))
    case Content.Value{Source.Text{+key, +text, +choice, +wrap}, +font}: diagnostic(key, "text-as-container")
    case Content.Value{Source.Glyph{+key, +picture, +style}, +font}: diagnostic(key, "glyph-as-container")
    case Content.Value{Source.Field{+key, +kind, +style, +attrs, +text, +placeholder, +options, +policy, +name, +enabled, +first, +remaining}, +font}: diagnostic(key, "field-as-container")
    case Content.Value{Source.RichText{+key, +style, +content, +attachments}, +font}: diagnostic(key, "rich-text-as-container")

# Positional metric keys never replace authored DOM keys.
def forest(+values: +List<Allocation.AllocatedTree<Content.Value, Doc.Event>>, +origin: Spatial.Box, +fixed: Bool, +native: Bool, +owned: +List<Owned>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Allocation.AllocatedLeaf{+key, +value, +interaction, +rule, +demand, +height, +bounds, +extent}, +rest}:
      leaf(value, key, bounds, extent, rule, interaction, box_styles(bounds, origin, fixed, rule), owned) <> forest(rest, origin, fixed, native, owned)
    case Con{Allocation.AllocatedContainer{+key, +value, +interaction, +rule, +bounds, +extent, +direction, +children}, +rest}:
      container(value, interaction, box_styles(bounds, origin, fixed, rule),
        [canvas(key, extent, rule, forest(children, child_origin(bounds, rule), False{}, native, owned))], native) <> forest(rest, origin, fixed, native, owned)

def rich_union(+first: Maybe<&2, Source.RichPolicy>, +second: Maybe<&2, Source.RichPolicy>) -> Maybe<&2, Source.RichPolicy>:
  match first:
    case None{}: second
    case Some{+policy}: Some{policy}

def find_rich(+values: +List<Allocation.AllocatedTree<Content.Value, Doc.Event>>, +owner: String) -> Maybe<&2, Source.RichPolicy>:
  match values:
    case Nil{}: None{}
    case Con{Allocation.AllocatedLeaf{+key, Content.Value{Source.RichText{+label, +style, Source.RichContent{+source, +text, +policy}, +attachments}, +font}, +interaction, +rule, +demand, +height, +bounds, +canvas}, +rest}:
      choose(Maybe<&2, Source.RichPolicy>, String.eq(key, owner), Some{policy}, find_rich(rest, owner))
    case Con{Allocation.AllocatedLeaf{+key, +value, +interaction, +rule, +demand, +height, +bounds, +canvas}, +rest}: find_rich(rest, owner)
    case Con{Allocation.AllocatedContainer{+key, +value, +interaction, +rule, +bounds, +canvas, +direction, +children}, +rest}:
      rich_union(find_rich(children, owner), find_rich(rest, owner))

def policy_present(+value: Maybe<&2, Source.RichPolicy>) -> Bool:
  match value:
    case None{}: False{}
    case Some{+policy}: True{}

def native_roots_valid(+values: +List<Content.AllocatedNative>, +tree: Allocation.AllocatedTree<Content.Value, Doc.Event>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{Content.AllocatedNative{+owner, +target, +native_tree}, +rest}: policy_present(find_rich([tree], owner)) && native_roots_valid(rest, tree)

def native_policies_valid(+values: +List<Content.NativePolicy>, +tree: Allocation.AllocatedTree<Content.Value, Doc.Event>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{Content.NativePolicy{+owner, +target, +attrs, +style}, +rest}: policy_present(find_rich([tree], owner)) && native_policies_valid(rest, tree)

def native_origin(+tree: Allocation.AllocatedTree<Content.Value, Doc.Event>) -> Spatial.Box:
  match tree:
    case Allocation.AllocatedLeaf{+key, +value, +interaction, +rule, +demand, +height, Spatial.Box{+left, +top, +width, +height}, +canvas}: Spatial.Box{0n, 0n, width, height}
    case Allocation.AllocatedContainer{+key, +value, +interaction, +rule, Spatial.Box{+left, +top, +width, +height}, +canvas, +direction, +children}: Spatial.Box{0n, 0n, width, height}

def native_box_properties(bounds: Spatial.Box) -> +List<Doc.Property>:
  Spatial.Box{left, top, +width, +height} = bounds
  [Paint.property("position", "relative"), Paint.property("box-sizing", "border-box"),
   Paint.property("padding", "0px"), Paint.property("border", "0px"),
   Paint.property("width", Paint.px(width)), Paint.property("height", Paint.px(height))]

def native_value(tree: Allocation.AllocatedTree<Content.Value, Doc.Event>) -> Content.Value:
  match tree:
    case Allocation.AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}: value
    case Allocation.AllocatedContainer{key, value, interaction, rule, bounds, canvas, direction, children}: value

def native_attributes(value: Content.Value) -> +List<Doc.Property>:
  match value:
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, children}, font}: attributes(attrs)
    case Content.Value{Source.Box{key, tag, style, attrs, children}, font}: attributes(attrs)
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, font}: attributes(attrs)
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: Nil{}
    case Content.Value{Source.RichText{key, style, content, attachments}, font}: Nil{}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}: attributes(attrs)
    case Content.Value{Source.Glyph{key, drawing, style}, font}: Nil{}

def allocated_native_properties(+owner: String, +target: Source.NativeTarget, +tree: Allocation.AllocatedTree<Content.Value, Doc.Event>) -> Owned:
  +value: Content.Value = native_value(tree)
  Owned{owner, Doc.TargetProperties{owner ++ "/" ++ Source.target_key(target), Source.target_key(target),
    native_attributes(value), properties(primitive_styles(value), native_box_properties(native_origin(tree)))}}

def native_roots(+values: +List<Content.AllocatedNative>) -> +List<Owned>:
  match values:
    case Nil{}: Nil{}
    case Con{Content.AllocatedNative{+owner, +target, +tree}, +rest}:
      allocated_native_properties(owner, target, tree) <> Owned{owner, Doc.Portal{owner ++ "/" ++ Source.target_key(target), Source.target_key(target), forest([tree], native_origin(tree), False{}, True{}, Nil{})}} <> native_roots(rest)

# Bound code bodies carry their block's state; RichPolicy remains only the
# default for code fences that have not acquired a native target policy.
def native_wrapping(target: Source.NativeTarget) -> +List<Doc.Property>:
  match target:
    case Source.ToolbarTarget{identity}: Nil{}
    case Source.CodeBodyTarget{identity, wrap}: wrapping(code_wrapping(wrap))

def native_style(+value: Source.ResolvedStyle, target: Source.NativeTarget) -> +List<Doc.Property>:
  Source.ResolvedStyle{+layout, +font, +surface, +states} = value
  properties(Paint.text_presentation(font), properties(chrome(surface), properties(Paint.states_style(states), native_wrapping(target))))

def native_policy_document(+owner: String, +target: Source.NativeTarget, +attrs: +List<Source.Attribute>, +style: Source.ResolvedStyle) -> Owned:
  Owned{owner, Doc.TargetProperties{owner ++ "/" ++ Source.target_key(target), Source.target_key(target), attributes(attrs), native_style(style, target)}}

def policy_documents(values: +List<Content.NativePolicy>) -> +List<Owned>:
  match values:
    case Nil{}: Nil{}
    case Con{Content.NativePolicy{owner, target, attrs, style}, rest}:
      native_policy_document(owner, target, attrs, style) <> policy_documents(rest)

def unowned(values: +List<Owned>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Owned{owner, node}, rest}: node <> unowned(rest)

def native_documents(+roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>) -> +List<Doc.Node>:
  unowned(List.append(&2, Owned, native_roots(roots), policy_documents(policies)))

def native_policy(+owner: String, +target: Source.NativeTarget, +attrs: +List<Source.Attribute>, +style: Source.ResolvedStyle, +policy: Maybe<&2, Source.RichPolicy>) -> Owned:
  match policy:
    case None{}: Owned{owner, diagnostic(owner, "native-policy-missing-rich-owner")}
    case Some{+rich}: native_policy_document(owner, target, attrs, style)

def native_policies(+values: +List<Content.NativePolicy>, +tree: Allocation.AllocatedTree<Content.Value, Doc.Event>) -> +List<Owned>:
  match values:
    case Nil{}: Nil{}
    case Con{Content.NativePolicy{+owner, +target, +attrs, +style}, +rest}:
      native_policy(owner, target, attrs, style, find_rich([tree], owner)) <> native_policies(rest, tree)

def emit_world(+tree: Allocation.AllocatedTree<Content.Value, Doc.Event>, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, +valid: Bool) -> +List<Doc.Node>:
  match valid:
    case False{}: [diagnostic("physical-world", "native-attachment-missing-rich-owner")]
    case True{}: forest([tree], Spatial.Box{0n, 0n, 0n, 0n}, True{}, False{}, List.append(&2, Owned, native_roots(roots), native_policies(policies, tree)))

def nodes(+world: Content.AllocatedWorld) -> +List<Doc.Node>:
  Content.AllocatedWorld{+snapshot, +tree, +roots, +policies} = world
  emit_world(tree, roots, policies, native_roots_valid(roots, tree) && native_policies_valid(policies, tree))
