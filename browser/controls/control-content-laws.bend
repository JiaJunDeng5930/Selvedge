import Base
import ../layout/GEOMETRY.bend as SpatialModel
import ../appearance/TYPOGRAPHY.bend as T
import ../layout/enclosure.bend as Enclosure
import ../layout/enclosure-laws.bend as EnclosureLaws
import ./PROGRAM.bend as Controls
import ../appearance/MODEL.bend as Appearance
import ../appearance/DESIGN.bend as Design
import ./CONTROLS.bend as Authored
import ../document/SOURCE.bend as Source
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View

def layout_insets(layout: Controls.ContentLayout) -> (Nat & (Nat & Nat)):
  Controls.ContentLayout{alignment, +content_area, gap} = layout
  (Enclosure.inline(content_area), (Enclosure.block(content_area), gap))

def first_caption(values: +List<Source.Node>) -> Maybe<&2, Source.Node>:
  match values:
    case Con{Source.Text{key,text,font,wrapping}, rest}: Some{Source.Text{key,text,font,wrapping}}
    case _: None{}

def trigger_caption(values: +List<Source.Node>) -> Maybe<&2, Source.Node>:
  match values:
    case Nil{}: None{}
    case Con{Source.Text{key,text,font,wrapping}, rest}: Some{Source.Text{key,text,font,wrapping}}
    case Con{Source.Box{key,tag,style,attributes,children}, rest}: first_caption(children)
    case Con{node, rest}: trigger_caption(rest)

law picker_caption_single_line:
  for leading: Maybe<&2,Controls.Icon>
  for text: String
  {Controls.caption_wrapping(Controls.PickerFace{leading,text}) == T.SingleLine{} : T.Wrapping}

law disclosure_caption_single_line:
  for text: String
  for expanded: Bool
  {Controls.caption_wrapping(Controls.DisclosureFace{text,expanded}) == T.SingleLine{} : T.Wrapping}

law picker_face_caption:
  for +key: Identity.Key
  for +text: String
  for +parent: Design.Style
  for leading: Maybe<&2,Controls.Icon>
  for geometry: Controls.Geometry
  {trigger_caption(Authored.face(key,Controls.PickerFace{leading,text},parent,geometry)) ==
    Some{Source.Text{Identity.part(key,"caption"),text,Source.ExplicitFont{Authored.parent_font(parent)},T.SingleLine{}}} : Maybe<&2,Source.Node>}

law disclosure_face_caption:
  for +key: Identity.Key
  for +text: String
  for +parent: Design.Style
  for expanded: Bool
  for geometry: Controls.Geometry
  {trigger_caption(Authored.face(key,Controls.DisclosureFace{text,expanded},parent,geometry)) ==
    Some{Source.Text{Identity.part(key,"caption"),text,Source.ExplicitFont{Authored.parent_font(parent)},T.SingleLine{}}} : Maybe<&2,Source.Node>}

law unbroken_caption:
  for text: String
  {Controls.caption_wrapping(Controls.UnbrokenFace{text}) == T.UnbrokenLine{} : T.Wrapping}

law unbroken_face_caption:
  for +key: Identity.Key
  for +text: String
  for +parent: Design.Style
  for geometry: Controls.Geometry
  {Authored.face(key,Controls.UnbrokenFace{text},parent,geometry) ==
    [Source.Text{Identity.part(key,"caption"),text,Source.ExplicitFont{Authored.parent_font(parent)},T.UnbrokenLine{}}] : +List<Source.Node>}

type Requirements is Type:
  Requirements{
    enabled_matches_interface: @+availability:View.Availability ->
      {Authored.enabled(availability) == InterfaceView.available(availability) : Bool},
    choice_caption_words: @text:String -> @description:Maybe<&2,String> -> @icon:Maybe<&2,Controls.Icon> -> @checked:Bool ->
      {Controls.caption_wrapping(Controls.ChoiceFace{text,description,icon,checked}) == T.NormalWords{} : T.Wrapping},
    choice_description_words: {Controls.description_wrapping() == T.NormalWords{} : T.Wrapping},
    single_line_caption: @text:String ->
      {Controls.caption_wrapping(Controls.SingleLineFace{text}) == T.SingleLine{} : T.Wrapping},
    choice_caption_source: @+key:Identity.Key -> @+text:String -> @+parent:Design.Style -> @description:Maybe<&2,String> -> @icon:Maybe<&2,Controls.Icon> -> @checked:Bool ->
      {Authored.caption(key,text,parent,Controls.caption_wrapping(Controls.ChoiceFace{text,description,icon,checked})) ==
        Source.Text{key,text,Source.ExplicitFont{Authored.parent_font(parent)},T.NormalWords{}} : Source.Node},
    choice_description_source: @+key:Identity.Key -> @+text:String -> @+parent:Design.Style ->
      {Authored.face_description(Some{text},key,parent) ==
        [Source.Text{Identity.part(key,"description"),text,Source.ExplicitFont{T.supporting(Authored.parent_font(parent))},T.NormalWords{}}] : +List<Source.Node>},
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

law unbroken_icon_caption:
  for icon: Controls.Icon
  for text: String
  {Controls.caption_wrapping(Controls.UnbrokenIconTextFace{icon,text}) == T.UnbrokenLine{} : T.Wrapping}

law unbroken_icon_face_caption:
  for +key: Identity.Key
  for icon: Controls.Icon
  for +text: String
  for +parent: Design.Style
  for geometry: Controls.Geometry
  {trigger_caption(Authored.face(key,Controls.UnbrokenIconTextFace{icon,text},parent,geometry)) ==
    Some{Source.Text{Identity.part(key,"caption"),text,Source.ExplicitFont{Authored.parent_font(parent)},T.UnbrokenLine{}}} : Maybe<&2,Source.Node>}

law named_text_caption:
  for text: String
  for compact: Bool
  {Controls.named_face(None{},text,compact) == Controls.UnbrokenFace{text} : Controls.Face}

law named_icon_caption:
  for icon: Controls.Icon
  for text: String
  {Controls.named_face(Some{icon},text,False{}) == Controls.UnbrokenIconTextFace{icon,text} : Controls.Face}
