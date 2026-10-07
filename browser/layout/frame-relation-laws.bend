import Base
import ../../interaction/IDENTITY.bend as Identity
import ./GEOMETRY.bend as SpatialModel
import ../appearance/TYPOGRAPHY.bend as T
import ./enclosure.bend as E
import ./SPACE.bend as Space
import ../appearance/DESIGN.bend as D
import ../appearance/MODEL.bend as A
import ../controls/PROGRAM.bend as C
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/MODEL.bend as View

def actual_geometry(value: C.Representation) -> C.Geometry:
  match value:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: geometry
    case _: C.Geometry{Space.fixed_demand(0n, 0n), 0n, 0n, 0n}

def mark_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
  extent

def mark_icon_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
  icon_extent

def style_flow(value: D.Style) -> SpatialModel.Flow:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  flow

def choice_style_metrics(+value: D.Style) -> (Nat & SpatialModel.Flow):
  (E.frame_gap(D.style_frame(value)), style_flow(value))

def actual_choice_normalization_law(-key: Identity.Key, -selected: Bool, -description: String, -input: Core.Input, -availability: View.Availability, -label: String,
  -role: InterfaceView.Role, -context: C.Context, -fallback: D.Style, +typography: T.Presentation) -> Type:
  {choice_style_metrics(A.control_style(fallback, C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context), typography)) == (8n, SpatialModel.ChoiceFlow{}) : (Nat & SpatialModel.Flow)}

type Requirements is Type:
  Requirements{
    actual_action_flow: @+value:D.Style -> @+face:C.Face -> @+size:C.Geometry ->
      {style_flow(A.action_style(value, face, size)) == A.action_flow(face, C.content_layout(face)) : SpatialModel.Flow},
    actual_choice_normalization: @+typography:T.Presentation -> @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:InterfaceView.Role -> @+context:C.Context -> @+fallback:D.Style ->
      actual_choice_normalization_law(key, selected, description, input, availability, label, role, context, fallback, typography),
    embedded_gap: @+content:E.ContentArea -> @+gap:Nat -> {E.frame_gap(E.frame(content, E.EmbeddedContent{gap})) == gap : Nat},
    separate_gap: @+content:E.ContentArea -> @+spacing:E.Separation -> {E.frame_gap(E.frame(content, E.SeparateFrames{spacing})) == E.separation(spacing) : Nat},
    joined_gap: @content:E.ContentArea -> {E.frame_gap(E.frame(content, E.JoinedPartitions{})) == 0n : Nat},
    content_preserves_arrangement: @+value:D.Style -> @content:E.ContentArea -> {E.frame_gap(D.style_frame(A.with_content_area(value, content))) == E.frame_gap(D.style_frame(value)) : Nat},
    role_navigation: @+typography:T.Presentation -> @+meaning:InterfaceView.Meaning -> {D.style_frame(A.style(InterfaceView.Navigation{}, meaning, typography)) == E.Frame{E.area(E.Navigation{}), E.SeparateFrames{E.NavigationRows{}}} : E.Frame},
    role_menu: @+typography:T.Presentation -> @+meaning:InterfaceView.Meaning -> {D.style_frame(A.style(InterfaceView.Menu{}, meaning, typography)) == E.Frame{E.area(E.Menu{}), E.SeparateFrames{E.MenuItems{}}} : E.Frame},
    role_card: @+typography:T.Presentation -> @+meaning:InterfaceView.Meaning -> {D.style_frame(A.style(InterfaceView.Card{}, meaning, typography)) == E.Frame{E.area(E.Card{}), E.SeparateFrames{E.CardSections{}}} : E.Frame},
    role_details: @+typography:T.Presentation -> @+meaning:InterfaceView.Meaning -> {D.style_frame(A.style(InterfaceView.Details{}, meaning, typography)) == E.Frame{E.area(E.Details{}), E.SeparateFrames{E.Sections{}}} : E.Frame},
    role_dialog: @+typography:T.Presentation -> @+meaning:InterfaceView.Meaning -> {D.style_frame(A.style(InterfaceView.Dialog{}, meaning, typography)) == E.Frame{E.DialogPartitions{}, E.JoinedPartitions{}} : E.Frame},
    actual_choice_geometry: @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:InterfaceView.Role -> @+context:C.Context -> {actual_geometry(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : C.Geometry},
    actual_choice_layout: @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:InterfaceView.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout},
    actual_choice_mark_contains_icon: @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:InterfaceView.Role -> @+context:C.Context -> {Nat.is_le(mark_icon_extent(C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context))), mark_extent(C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)))) == True{} : Bool},
    selection_keeps_allocation: @+key:Identity.Key -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:InterfaceView.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, True{}, description, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, InterfaceView.SingleChoice{}, None{}, False{}, description, input, availability, label, role, context)) : C.ChoiceContentLayout},
    timeline_gap: @+typography:T.Presentation -> @+meaning:InterfaceView.Meaning -> {E.frame_gap(D.style_frame(A.style(InterfaceView.Timeline{}, meaning, typography))) == E.separation(E.Messages{}) : Nat},
    section_gap: @+typography:T.Presentation -> @+meaning:InterfaceView.Meaning -> {E.frame_gap(D.style_frame(A.style(InterfaceView.Section{}, meaning, typography))) == E.separation(E.Sections{}) : Nat}}

law evidence:
  Requirements
