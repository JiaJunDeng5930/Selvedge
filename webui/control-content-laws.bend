import Base
import ./spatial.bend as SpatialModel
import ./typography.bend as T
import ./enclosure.bend as Enclosure
import ./enclosure-laws.bend as EnclosureLaws
import ./controls.bend as Controls
import ./appearance.bend as Appearance
import ./design.bend as Design
import ./authored-controls.bend as Authored
import ./source.bend as Source
import ../core/ui-identity.bend as Identity

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

type Requirements is Type:
  Requirements{
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
