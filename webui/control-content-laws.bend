import Base
import ./space.bend as Space
import ./typography.bend as T
import ./enclosure.bend as Enclosure
import ./enclosure-laws.bend as EnclosureLaws
import ./controls.bend as Controls
import ./appearance.bend as Appearance
import ./design.bend as Design
import ./document.bend as Doc
import ./renderer.bend as Render
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View

# These requirements observe the production document; CSS execution remains a
# browser boundary, including the physical glyph bounds and actual hit tests.
def layout_insets(layout: Controls.ContentLayout) -> (Nat & (Nat & Nat)):
  Controls.ContentLayout{alignment, +content_area, gap} = layout
  (Enclosure.inline(content_area), (Enclosure.block(content_area), gap))































def appearance_consumes_layout(text: T.Presentation, chrome: Design.Chrome, alignment: Design.Alignment, flow: Design.Flow, overflow: Design.Overflow, content_area: Enclosure.ContentArea, gap: Nat, height: Nat, maximum: Nat, states: Design.ControlStates, face: Controls.Face, size: Controls.Geometry) ->
  {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content_area, Enclosure.EmbeddedContent{gap}}, height, maximum, states}, face, size))) == layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}:
  T.Presentation{tier, emphasis, scale} = text
  Design.Chrome{foreground, background, border, border_width, chrome_radius, shadow} = chrome
  match face size:
    case Controls.IconFace{icon} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.TextFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.SingleLineFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.IconTextFace{icon, text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.PickerFace{leading, text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, slot}: {==}
    case Controls.ChoiceFace{text, description, checked} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.DisclosureFace{text, expanded} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.PermissionFace{filesystem, network, approval} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}






type Requirements is Type:
  Requirements{
    production_icon_paint: @+key:String -> @+icon:Controls.Icon ->
      {Doc.element_attributes(Render.icon(key, icon)) == List.append(&2, Doc.Property, [Render.property("viewBox", "0 0 20 20"), Render.property("aria-hidden", "true")], Render.icon_paint_properties(Controls.icon_paint(icon))) : +List<Doc.Property>},
    permission_layout: @filesystem:Controls.Icon -> @network:Controls.Icon -> @approval:Controls.Icon ->
      {Controls.content_layout(Controls.PermissionFace{filesystem, network, approval}) == Controls.ContentLayout{Controls.LeadingContents{}, Enclosure.area(Enclosure.TextControl{}), 6n} : Controls.ContentLayout},
    icon_layout: @icon:Controls.Icon ->
      {Controls.content_layout(Controls.IconFace{icon}) == Controls.ContentLayout{Controls.CenterContents{}, Enclosure.area(Enclosure.IconControl{}), 0n} : Controls.ContentLayout},
    picker_layout: @+leading:Maybe<&2, Controls.Icon> -> @label:String ->
      {Controls.content_layout(Controls.PickerFace{leading, label}) == Controls.ContentLayout{Controls.LeadingContents{}, Enclosure.area(Enclosure.TextControl{}), 6n} : Controls.ContentLayout},
    filled_arrow: @+key:String ->
      {Render.attr(Doc.element_attributes(Render.icon(key, Controls.ArrowUp{})), "fill") == "currentColor" : String},
    unstroked_arrow: @+key:String ->
      {Render.attr(Doc.element_attributes(Render.icon(key, Controls.ArrowUp{})), "stroke") == "none" : String},
    picker_production: @+typography:T.Presentation -> @geometry:Controls.Geometry -> @+key:String -> @+leading:Maybe<&2, Controls.Icon> -> @label:String ->
      {Render.face(key, Controls.PickerFace{leading, label}, typography, geometry) == List.append(&2, Doc.Node, Render.optional_icon(key ++ "/leading", leading), [Render.face_label(key, label), Render.icon(key ++ "/disclosure", Controls.ChevronDown{})]) : +List<Doc.Node>},
    check_frame_reserved: @+key:String ->
      {Doc.element_styles(Render.check_slot(key, True{})) == Doc.element_styles(Render.check_slot(key, False{})) : +List<Doc.Property>},
    selected_check_svg: @+typography:T.Presentation -> @+key:String -> @label:String -> @+description:Maybe<&2, String> -> @width:Nat -> @height:Nat -> @preferred:Enclosure.Extent -> @icon:Nat -> @radius:Nat -> @slot:Nat ->
      {Render.face(key, Controls.ChoiceFace{label, description, True{}}, typography, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, slot}) ==
        [Render.choice_text_content(key, label, description, 2n, typography), Doc.Element{key ++ "/check-slot", "span", [Render.property("aria-hidden", "true")], [Render.property("width", Render.px(slot)), Render.property("height", Render.px(icon)), Render.property("flex-shrink", "0"), Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center")], Nil{}, [Render.icon(key ++ "/check", Controls.Check{})]}] : +List<Doc.Node>},
    unselected_check_empty: @+typography:T.Presentation -> @+key:String -> @label:String -> @+description:Maybe<&2, String> -> @width:Nat -> @height:Nat -> @preferred:Enclosure.Extent -> @icon:Nat -> @radius:Nat -> @slot:Nat ->
      {Render.face(key, Controls.ChoiceFace{label, description, False{}}, typography, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, slot}) ==
        [Render.choice_text_content(key, label, description, 2n, typography), Doc.Element{key ++ "/check-slot", "span", [Render.property("aria-hidden", "true")], [Render.property("width", Render.px(slot)), Render.property("height", Render.px(icon)), Render.property("flex-shrink", "0"), Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center")], Nil{}, Nil{}}] : +List<Doc.Node>},
    permission_icons: @+typography:T.Presentation -> @geometry:Controls.Geometry -> @+key:String -> @filesystem:Controls.Icon -> @network:Controls.Icon -> @approval:Controls.Icon ->
      {Render.face(key, Controls.PermissionFace{filesystem, network, approval}, typography, geometry) == [Render.icon(key ++ "/filesystem", filesystem), Render.icon(key ++ "/network", network), Render.icon(key ++ "/approval", approval)] : +List<Doc.Node>},
    centered_icon_geometry: @icon:Controls.Icon -> @width:Nat -> @height:Nat -> @preferred:Enclosure.Extent -> @size:Nat -> @radius:Nat -> @slot:Nat ->
      {Render.content_geometry(Controls.IconFace{icon}, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, size, radius, slot}) == [Render.property("width", Render.px(Render.square_extent(width, height))), Render.property("height", Render.px(Render.square_extent(width, height))), Render.property("flex-shrink", "0"), Render.property("box-sizing", "border-box")] : +List<Doc.Property>} &
      {Render.flow(Appearance.action_flow(Controls.IconFace{icon}, Controls.content_layout(Controls.IconFace{icon}))) == [Render.property("display", "inline-flex"), Render.property("flex-direction", "row"), Render.property("align-items", "center"), Render.property("justify-content", "center")] : +List<Doc.Property>},
    action_content_is_last: @+key:String -> @+visual:Design.Style -> @input:Core.Input -> @availability:View.Availability -> @name:String -> @+face:Controls.Face -> @behavior:Controls.Behavior -> @+size:Controls.Geometry -> @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback ->
      {Doc.element_styles(Render.action(key, visual, Controls.Action{input, availability, name, face, behavior, size, placement, help, feedback})) == Render.action_styles(key, visual, face, size, placement) : +List<Doc.Property>},
    appearance_consumes_layout: @text:T.Presentation -> @chrome:Design.Chrome -> @alignment:Design.Alignment -> @flow:Design.Flow -> @overflow:Design.Overflow -> @content_area:Enclosure.ContentArea -> @gap:Nat -> @height:Nat -> @maximum:Nat -> @states:Design.ControlStates -> @face:Controls.Face -> @size:Controls.Geometry ->
      {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content_area, Enclosure.EmbeddedContent{gap}}, height, maximum, states}, face, size))) == layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}}

def evidence() -> Requirements:
  Requirements{+key => +icon => {==}, filesystem => network => approval => {==}, icon => {==}, +leading => label => {==}, +key => {==}, +key => {==}, +typography => geometry => +key => +leading => label => {==}, +key => {==}, +typography => +key => label => +description => width => height => preferred => icon => radius => slot => {==}, +typography => +key => label => +description => width => height => preferred => icon => radius => slot => {==}, +typography => geometry => +key => filesystem => network => approval => {==}, icon => width => height => preferred => size => radius => slot => ({==}, {==}), +key => +visual => input => availability => name => +face => behavior => +size => placement => help => feedback => {==}, appearance_consumes_layout}
