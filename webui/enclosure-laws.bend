import Base
import ./typography.bend as T
import ./enclosure.bend as E
import ./appearance.bend as A
import ./controls.bend as C
import ./design.bend as D
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms

def frame_coordinates(+frame: E.Frame) -> (Nat & (Nat & Nat)):
  (E.inline(E.frame_content(frame)), (E.block(E.frame_content(frame)), E.frame_gap(frame)))

def area(value: D.Style) -> E.ContentArea:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  E.frame_content(content_frame)

def chrome(value: D.Style) -> D.Chrome:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  chrome

def interaction(value: D.Style) -> D.ControlStates:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  states

type Requirements is Type:
  Requirements{positive: @+profile:E.Profile -> {(Nat.min(1n, E.inline(E.area(profile))), Nat.min(1n, E.block(E.area(profile)))) == (1n, 1n) : (Nat & Nat)},
    extent: @+width:Nat -> @+height:Nat -> @+border:Nat -> @+space:E.ContentArea -> {E.required_extent(width, height, border, space) == E.Extent{Nat.add(width, Nat.mul(2n, Nat.add(border, E.inline(space)))), Nat.add(height, Nat.mul(2n, Nat.add(border, E.block(space))))} : E.Extent},
    borderless: @+width:Nat -> @+height:Nat -> @+profile:E.Profile -> {E.required_extent(width, height, 0n, E.area(profile)) == E.Extent{Nat.add(width, Nat.mul(2n, E.inline(E.area(profile)))), Nat.add(height, Nat.mul(2n, E.block(E.area(profile))))} : E.Extent},
    action_insets: @+value:D.Style -> @+geometry:C.Geometry -> @+space:E.ContentArea -> @+gap:Nat -> @content_height:Nat -> {area(A.action_style_insets(value, geometry, space, gap, content_height)) == space : E.ContentArea},
    layout_copied: @+value:D.Style -> @+layout:C.ContentLayout -> @+geometry:C.Geometry -> @content_height:Nat -> {area(A.action_content_style(value, layout, geometry, content_height)) == C.layout_content_area(layout) : E.ContentArea},
    action_copied: @+value:D.Style -> @+face:C.Face -> @+geometry:C.Geometry -> {area(A.action_style(value, face, geometry)) == C.layout_content_area(C.content_layout(face)) : E.ContentArea},
    minimum_extent: @+typography:T.Presentation -> @+value:D.Style -> @+geometry:C.Geometry -> @+space:E.ContentArea -> @+gap:Nat -> @+content_height:Nat -> {D.style_minimum_height(A.action_style_insets(value, geometry, space, gap, content_height)) == Nat.max(C.geometry_minimum_height(geometry), E.extent_height(E.required_extent(0n, content_height, A.chrome_border_width(chrome(value)), space))) : Nat},
    choice_area: @+typography:T.Presentation -> {area(A.choice_button(True{}, typography)) == area(A.choice_button(False{}, typography)) : E.ContentArea},
    choice_text: @+typography:T.Presentation -> {D.style_text(A.choice_button(True{}, typography)) == D.style_text(A.choice_button(False{}, typography)) : T.Presentation},
    role_navigation: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Navigation{}, meaning, typography)) == E.area(E.Navigation{}) : E.ContentArea},
    role_usermessage: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.UserMessage{}, meaning, typography)) == E.area(E.UserMessage{}) : E.ContentArea},
    role_composer: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Composer{}, meaning, typography)) == E.area(E.Composer{}) : E.ContentArea},
    role_approval: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Approval{}, meaning, typography)) == E.area(E.Approval{}) : E.ContentArea},
    role_codeblock: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.CodeBlock{}, meaning, typography)) == E.area(E.CodeBlock{}) : E.ContentArea},
    role_menu: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Menu{}, meaning, typography)) == E.area(E.Menu{}) : E.ContentArea},
    role_details: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Details{}, meaning, typography)) == E.area(E.Details{}) : E.ContentArea},
    role_card: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Card{}, meaning, typography)) == E.area(E.Card{}) : E.ContentArea},
    role_dialog: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Dialog{}, meaning, typography)) == E.DialogPartitions{} : E.ContentArea},
    canvas: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {area(A.style(UI.Main{}, meaning, typography)) == E.ambient(0n, 0n) : E.ContentArea},
    field: @+typography:T.Presentation -> {area(A.editable_field(typography)) == E.area(E.Field{}) : E.ContentArea},
    part_header: {E.partition(E.Header{}) == E.ambient(24n, 14n) : E.ContentArea},
    part_body: {E.partition(E.Body{}) == E.ambient(24n, 20n) : E.ContentArea},
    part_footer: {E.partition(E.Footer{}) == E.ambient(24n, 12n) : E.ContentArea},
    state_allocation: @+value:D.Style -> @+space:E.ContentArea -> {interaction(A.with_content_area(value, space)) == interaction(value) : D.ControlStates},
    icon_layout: @+icon:C.Icon -> {C.layout_content_area(C.content_layout(C.IconFace{icon})) == E.area(E.IconControl{}) : E.ContentArea},
    text_layout: @+text:String -> {C.layout_content_area(C.content_layout(C.TextFace{text})) == E.area(E.TextControl{}) : E.ContentArea},
    option_layout: @+text:String -> @+selected:Bool -> {C.layout_content_area(C.content_layout(C.ChoiceFace{text, None{}, selected})) == E.area(E.OptionControl{}) : E.ContentArea},
    embedded_input: @+typography:T.Presentation -> {area(A.widget_field_style(C.MessageInput{}, Forms.Multiline{}, typography)) == E.ambient(8n, 6n) : E.ContentArea}}

law evidence:
  Requirements
