import Base
import ./controls.bend as Controls
import ./appearance.bend as Appearance
import ./design.bend as Design
import ./document.bend as Doc
import ./renderer.bend as Render
import ./renderer-laws.bend as Renderer
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View

# These requirements observe the production document; CSS execution remains a
# browser boundary, including the physical glyph bounds and actual hit tests.
def insets(style: Design.Style) -> (Nat & (Nat & Nat)):
  Design.Style{text, chrome, alignment, flow, overflow, inline, block, gap, height, maximum, states} = style
  (inline, (block, gap))

def layout_insets(layout: Controls.ContentLayout) -> (Nat & (Nat & Nat)):
  Controls.ContentLayout{alignment, inline, block, gap} = layout
  (inline, (block, gap))

def icon_layout(icon: Controls.Icon) ->
  {Controls.content_layout(Controls.IconFace{icon}) == Controls.ContentLayout{Controls.CenterContents{}, 4n, 4n, 0n} : Controls.ContentLayout}:
  {==}

def picker_layout(+leading: Maybe<&2, Controls.Icon>, label: String) ->
  {Controls.content_layout(Controls.PickerFace{leading, label}) == Controls.ContentLayout{Controls.LeadingContents{}, 8n, 4n, 6n} : Controls.ContentLayout}:
  {==}

def filled_arrow(+key: String) ->
  {Render.attr(Renderer.node_attributes(Render.icon(key, Controls.ArrowUp{})), "fill") == "currentColor" : String}:
  {==}

def unstroked_arrow(+key: String) ->
  {Render.attr(Renderer.node_attributes(Render.icon(key, Controls.ArrowUp{})), "stroke") == "none" : String}:
  {==}

def picker_production(+key: String, +leading: Maybe<&2, Controls.Icon>, label: String) ->
  {Render.face(key, Controls.PickerFace{leading, label}) == List.append(&2, Doc.Node, Render.optional_icon(key ++ "/leading", leading), [Render.face_label(key, label), Render.icon(key ++ "/disclosure", Controls.ChevronDown{})]) : +List<Doc.Node>}:
  {==}

def check_frame_reserved(+key: String) ->
  {Renderer.node_styles(Render.check_slot(key, True{})) == Renderer.node_styles(Render.check_slot(key, False{})) : +List<Doc.Property>}:
  {==}

def selected_check_svg(+key: String) ->
  {Render.face(key, Controls.ChoiceFace{"", True{}}) == [Doc.Element{key ++ "/check-slot", "span", [Render.property("aria-hidden", "true")], [Render.property("width", "var(--native-leading-slot,20px)"), Render.property("height", "var(--native-icon-size,16px)"), Render.property("flex-shrink", "0"), Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center")], Nil{}, [Render.icon(key ++ "/check", Controls.Check{})]}, Render.face_label(key, "")] : +List<Doc.Node>}:
  {==}

def unselected_check_empty(+key: String) ->
  {Render.face(key, Controls.ChoiceFace{"", False{}}) == [Doc.Element{key ++ "/check-slot", "span", [Render.property("aria-hidden", "true")], [Render.property("width", "var(--native-leading-slot,20px)"), Render.property("height", "var(--native-icon-size,16px)"), Render.property("flex-shrink", "0"), Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center")], Nil{}, Nil{}}, Render.face_label(key, "")] : +List<Doc.Node>}:
  {==}

def permission_icons(+key: String, filesystem: Controls.Icon, network: Controls.Icon, approval: Controls.Icon) ->
  {Render.face(key, Controls.PermissionFace{filesystem, network, approval}) == [Render.icon(key ++ "/filesystem", filesystem), Render.icon(key ++ "/network", network), Render.icon(key ++ "/approval", approval)] : +List<Doc.Node>}:
  {==}

def centered_icon_geometry(icon: Controls.Icon, width: Nat, height: Nat, size: Nat, radius: Nat, slot: Nat) ->
  {Render.content_geometry(Controls.IconFace{icon}, Controls.Geometry{width, height, size, radius, slot}) == [Render.property("justify-content", "center"), Render.property("align-items", "center"), Render.property("gap", "0px"), Render.property("width", Render.px(Render.square_extent(width, height))), Render.property("height", Render.px(Render.square_extent(width, height))), Render.property("flex-shrink", "0"), Render.property("box-sizing", "border-box")] : +List<Doc.Property>}:
  {==}

def action_content_is_last(+key: String, +visual: Design.Style, input: Core.Input, availability: View.Availability, name: String, +face: Controls.Face, behavior: Controls.Behavior, +size: Controls.Geometry, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {Renderer.node_styles(Render.action(key, Design.Appearance{key, visual, Controls.NoControl{}, Nil{}}, Controls.Action{input, availability, name, face, behavior, size, placement, help, feedback})) == List.append(&2, Doc.Property, Render.style(visual), List.append(&2, Doc.Property, Render.geometry(size), List.append(&2, Doc.Property, Render.placement_styles(placement), List.append(&2, Doc.Property, [Render.property("anchor-name", Render.css_anchor(key))], Render.content_geometry(face, size))))) : +List<Doc.Property>}:
  {==}

def appearance_consumes_layout(text: Design.TextStyle, chrome: Design.Chrome, alignment: Design.Alignment, flow: Design.Flow, overflow: Design.Overflow, inline: Nat, block: Nat, gap: Nat, height: Nat, maximum: Nat, states: Design.ControlStates, face: Controls.Face, size: Controls.Geometry) ->
  {insets(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, inline, block, gap, height, maximum, states}, face, size)) == layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}:
  match face size:
    case Controls.IconFace{icon} Controls.Geometry{width, height, icon_size, radius, leading}: {==}
    case Controls.TextFace{text} Controls.Geometry{width, height, icon_size, radius, leading}: {==}
    case Controls.IconTextFace{icon, text} Controls.Geometry{width, height, icon_size, radius, leading}: {==}
    case Controls.PickerFace{leading, text} Controls.Geometry{width, height, icon_size, radius, slot}: {==}
    case Controls.ChoiceFace{text, checked} Controls.Geometry{width, height, icon_size, radius, leading}: {==}
    case Controls.DisclosureFace{text, expanded} Controls.Geometry{width, height, icon_size, radius, leading}: {==}
    case Controls.PermissionFace{filesystem, network, approval} Controls.Geometry{width, height, icon_size, radius, leading}: {==}


def permission_layout(filesystem: Controls.Icon, network: Controls.Icon, approval: Controls.Icon) ->
  {Controls.content_layout(Controls.PermissionFace{filesystem, network, approval}) == Controls.ContentLayout{Controls.LeadingContents{}, 8n, 4n, 6n} : Controls.ContentLayout}:
  {==}

def production_icon_paint(+key: String, +icon: Controls.Icon) ->
  {Renderer.node_attributes(Render.icon(key, icon)) == List.append(&2, Doc.Property, [Render.property("viewBox", "0 0 20 20"), Render.property("aria-hidden", "true")], Render.icon_paint_properties(Controls.icon_paint(icon))) : +List<Doc.Property>}:
  {==}

type Requirements is Type:
  Requirements{
    production_icon_paint: @+key:String -> @+icon:Controls.Icon ->
      {Renderer.node_attributes(Render.icon(key, icon)) == List.append(&2, Doc.Property, [Render.property("viewBox", "0 0 20 20"), Render.property("aria-hidden", "true")], Render.icon_paint_properties(Controls.icon_paint(icon))) : +List<Doc.Property>},
    permission_layout: @filesystem:Controls.Icon -> @network:Controls.Icon -> @approval:Controls.Icon ->
      {Controls.content_layout(Controls.PermissionFace{filesystem, network, approval}) == Controls.ContentLayout{Controls.LeadingContents{}, 8n, 4n, 6n} : Controls.ContentLayout},
    icon_layout: @icon:Controls.Icon ->
      {Controls.content_layout(Controls.IconFace{icon}) == Controls.ContentLayout{Controls.CenterContents{}, 4n, 4n, 0n} : Controls.ContentLayout},
    picker_layout: @+leading:Maybe<&2, Controls.Icon> -> @label:String ->
      {Controls.content_layout(Controls.PickerFace{leading, label}) == Controls.ContentLayout{Controls.LeadingContents{}, 8n, 4n, 6n} : Controls.ContentLayout},
    filled_arrow: @+key:String ->
      {Render.attr(Renderer.node_attributes(Render.icon(key, Controls.ArrowUp{})), "fill") == "currentColor" : String},
    unstroked_arrow: @+key:String ->
      {Render.attr(Renderer.node_attributes(Render.icon(key, Controls.ArrowUp{})), "stroke") == "none" : String},
    picker_production: @+key:String -> @+leading:Maybe<&2, Controls.Icon> -> @label:String ->
      {Render.face(key, Controls.PickerFace{leading, label}) == List.append(&2, Doc.Node, Render.optional_icon(key ++ "/leading", leading), [Render.face_label(key, label), Render.icon(key ++ "/disclosure", Controls.ChevronDown{})]) : +List<Doc.Node>},
    check_frame_reserved: @+key:String ->
      {Renderer.node_styles(Render.check_slot(key, True{})) == Renderer.node_styles(Render.check_slot(key, False{})) : +List<Doc.Property>},
    selected_check_svg: @+key:String ->
      {Render.face(key, Controls.ChoiceFace{"", True{}}) == [Doc.Element{key ++ "/check-slot", "span", [Render.property("aria-hidden", "true")], [Render.property("width", "var(--native-leading-slot,20px)"), Render.property("height", "var(--native-icon-size,16px)"), Render.property("flex-shrink", "0"), Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center")], Nil{}, [Render.icon(key ++ "/check", Controls.Check{})]}, Render.face_label(key, "")] : +List<Doc.Node>},
    unselected_check_empty: @+key:String ->
      {Render.face(key, Controls.ChoiceFace{"", False{}}) == [Doc.Element{key ++ "/check-slot", "span", [Render.property("aria-hidden", "true")], [Render.property("width", "var(--native-leading-slot,20px)"), Render.property("height", "var(--native-icon-size,16px)"), Render.property("flex-shrink", "0"), Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center")], Nil{}, Nil{}}, Render.face_label(key, "")] : +List<Doc.Node>},
    permission_icons: @+key:String -> @filesystem:Controls.Icon -> @network:Controls.Icon -> @approval:Controls.Icon ->
      {Render.face(key, Controls.PermissionFace{filesystem, network, approval}) == [Render.icon(key ++ "/filesystem", filesystem), Render.icon(key ++ "/network", network), Render.icon(key ++ "/approval", approval)] : +List<Doc.Node>},
    centered_icon_geometry: @icon:Controls.Icon -> @width:Nat -> @height:Nat -> @size:Nat -> @radius:Nat -> @slot:Nat ->
      {Render.content_geometry(Controls.IconFace{icon}, Controls.Geometry{width, height, size, radius, slot}) == [Render.property("justify-content", "center"), Render.property("align-items", "center"), Render.property("gap", "0px"), Render.property("width", Render.px(Render.square_extent(width, height))), Render.property("height", Render.px(Render.square_extent(width, height))), Render.property("flex-shrink", "0"), Render.property("box-sizing", "border-box")] : +List<Doc.Property>},
    action_content_is_last: @+key:String -> @+visual:Design.Style -> @input:Core.Input -> @availability:View.Availability -> @name:String -> @+face:Controls.Face -> @behavior:Controls.Behavior -> @+size:Controls.Geometry -> @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback ->
      {Renderer.node_styles(Render.action(key, Design.Appearance{key, visual, Controls.NoControl{}, Nil{}}, Controls.Action{input, availability, name, face, behavior, size, placement, help, feedback})) == List.append(&2, Doc.Property, Render.style(visual), List.append(&2, Doc.Property, Render.geometry(size), List.append(&2, Doc.Property, Render.placement_styles(placement), List.append(&2, Doc.Property, [Render.property("anchor-name", Render.css_anchor(key))], Render.content_geometry(face, size))))) : +List<Doc.Property>},
    appearance_consumes_layout: @text:Design.TextStyle -> @chrome:Design.Chrome -> @alignment:Design.Alignment -> @flow:Design.Flow -> @overflow:Design.Overflow -> @inline:Nat -> @block:Nat -> @gap:Nat -> @height:Nat -> @maximum:Nat -> @states:Design.ControlStates -> @face:Controls.Face -> @size:Controls.Geometry ->
      {insets(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, inline, block, gap, height, maximum, states}, face, size)) == layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}}

def evidence() -> Requirements:
  Requirements{production_icon_paint, permission_layout, icon_layout, picker_layout, filled_arrow, unstroked_arrow, picker_production, check_frame_reserved, selected_check_svg, unselected_check_empty, permission_icons, centered_icon_geometry, action_content_is_last, appearance_consumes_layout}
