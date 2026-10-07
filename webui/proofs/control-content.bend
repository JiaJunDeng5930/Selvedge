import Base
import ../spatial.bend as SpatialModel
import ../control-content-laws.bend as Rule
import ../space.bend as Space
import ../typography.bend as T
import ../enclosure.bend as Enclosure
import ../enclosure-laws.bend as EnclosureLaws
import ../controls.bend as Controls
import ../appearance.bend as Appearance
import ../design.bend as Design

def appearance_consumes_layout(text: T.Presentation, chrome: Design.Chrome, alignment: SpatialModel.Alignment, flow: SpatialModel.Flow, overflow: SpatialModel.Overflow, content_area: Enclosure.ContentArea, gap: Nat, height: Nat, maximum: Nat, states: Design.ControlStates, face: Controls.Face, size: Controls.Geometry) ->
  {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content_area, Enclosure.EmbeddedContent{gap}}, height, maximum, states}, face, size))) == Rule.layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}:
  T.Presentation{tier, emphasis, scale} = text
  Design.Chrome{foreground, background, border, border_width, chrome_radius, shadow} = chrome
  match face size:
    case Controls.IconFace{icon} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.TextFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.UnbrokenFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.SingleLineFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.IconTextFace{icon, text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.PickerFace{leading, text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, slot}: {==}
    case Controls.ChoiceFace{text, description, icon, checked} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.DisclosureFace{text, expanded} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.PermissionFace{filesystem, network, approval} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}

def Rule.picker_caption_single_line(leading,text): {==}
def Rule.disclosure_caption_single_line(text,expanded): {==}

def Rule.picker_face_caption(key,text,parent,leading,geometry):
  match leading:
    case None{}: {==}
    case Some{icon}: {==}

def Rule.disclosure_face_caption(key,text,parent,expanded,geometry): {==}

def Rule.evidence():
  Rule.Requirements{
    +availability => {==},
    text => description => icon => checked => {==},
    {==},
    text => {==},
    +key => +text => +parent => description => icon => checked => {==},
    +key => +text => +parent => {==},
    filesystem => network => approval => {==},
    icon => {==},
    +leading => label => {==},
    appearance_consumes_layout}

def Rule.unbroken_caption(text): {==}
def Rule.unbroken_face_caption(key,text,parent,geometry): {==}
