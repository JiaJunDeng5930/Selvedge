import Base
import ./spatial.bend as SpatialModel
import ./typography.bend as T
import ./enclosure.bend as Enclosure
import ./enclosure-laws.bend as EnclosureLaws
import ./controls.bend as Controls
import ./appearance.bend as Appearance
import ./design.bend as Design

def layout_insets(layout: Controls.ContentLayout) -> (Nat & (Nat & Nat)):
  Controls.ContentLayout{alignment, +content_area, gap} = layout
  (Enclosure.inline(content_area), (Enclosure.block(content_area), gap))

type Requirements is Type:
  Requirements{
    permission_layout: @filesystem:Controls.Icon -> @network:Controls.Icon -> @approval:Controls.Icon ->
      {Controls.content_layout(Controls.PermissionFace{filesystem, network, approval}) == Controls.ContentLayout{SpatialModel.LeadingContents{}, Enclosure.area(Enclosure.TextControl{}), 6n} : Controls.ContentLayout},
    icon_layout: @icon:Controls.Icon ->
      {Controls.content_layout(Controls.IconFace{icon}) == Controls.ContentLayout{SpatialModel.CenterContents{}, Enclosure.area(Enclosure.IconControl{}), 0n} : Controls.ContentLayout},
    picker_layout: @+leading:Maybe<&2, Controls.Icon> -> @label:String ->
      {Controls.content_layout(Controls.PickerFace{leading, label}) == Controls.ContentLayout{SpatialModel.LeadingContents{}, Enclosure.area(Enclosure.TextControl{}), 6n} : Controls.ContentLayout},
    appearance_consumes_layout: @text:T.Presentation -> @chrome:Design.Chrome -> @alignment:SpatialModel.Alignment -> @flow:SpatialModel.Flow -> @overflow:SpatialModel.Overflow -> @content_area:Enclosure.ContentArea -> @gap:Nat -> @height:Nat -> @maximum:Nat -> @states:Design.ControlStates -> @face:Controls.Face -> @size:Controls.Geometry ->
      {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content_area, Enclosure.EmbeddedContent{gap}}, height, maximum, states}, face, size))) == layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}}

law evidence:
  Requirements
