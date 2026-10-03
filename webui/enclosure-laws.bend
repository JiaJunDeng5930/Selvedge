import Base
import ./enclosure.bend as E
import ./appearance.bend as A
import ./controls.bend as C
import ./design.bend as D
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms

def area(value: D.Style) -> E.ContentArea:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  E.frame_content(content_frame)

def typography(value: D.Style) -> D.TextStyle:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  text

def minimum(value: D.Style) -> Nat:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  height

def layout_area(value: C.ContentLayout) -> E.ContentArea:
  C.ContentLayout{alignment, area, gap} = value
  area

def chrome(value: D.Style) -> D.Chrome:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  chrome

def geometry_height(value: C.Geometry) -> Nat:
  C.Geometry{width, height, icon, radius, leading} = value
  height

def interaction(value: D.Style) -> D.ControlStates:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  states

def positive(+profile: E.Profile) ->
  {(Nat.min(1n, E.inline(E.area(profile))), Nat.min(1n, E.block(E.area(profile)))) == (1n, 1n) : (Nat & Nat)}:
  match profile:
    case E.IconControl{}: {==}
    case E.TextControl{}: {==}
    case E.OptionControl{}: {==}
    case E.NavigationRow{}: {==}
    case E.Field{}: {==}
    case E.SearchField{}: {==}
    case E.Composer{}: {==}
    case E.Card{}: {==}
    case E.Menu{}: {==}
    case E.UserMessage{}: {==}
    case E.Details{}: {==}
    case E.Navigation{}: {==}
    case E.Approval{}: {==}
    case E.CodeBlock{}: {==}
    case E.Lane{}: {==}
    case E.ArchiveGroup{}: {==}





def action_insets(+value: D.Style, +geometry: C.Geometry, +space: E.ContentArea, +gap: Nat) ->
  {area(A.action_style_insets(value, geometry, space, gap)) == space : E.ContentArea}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{width, height, icon, radius, leading} = geometry
  {==}

def layout_copied(+value: D.Style, +layout: C.ContentLayout, +geometry: C.Geometry) ->
  {area(A.action_content_style(value, layout, geometry)) == layout_area(layout) : E.ContentArea}:
  C.ContentLayout{alignment, space, gap} = layout
  action_insets(value, geometry, space, gap)

def flow_preserves_area(+value: D.Style, flow: D.Flow) ->
  {area(A.with_flow(value, flow)) == area(value) : E.ContentArea}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}



def minimum_extent(+value: D.Style, +geometry: C.Geometry, +space: E.ContentArea, +gap: Nat) ->
  {minimum(A.action_style_insets(value, geometry, space, gap)) == Nat.max(geometry_height(geometry), A.extent_height(E.required_extent(0n, A.text_line_height(typography(value)), A.chrome_border_width(chrome(value)), space))) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{width, height, icon, radius, leading} = geometry
  {==}























def canvas(+meaning: UI.Meaning) ->
  {area(A.style(UI.Main{}, meaning)) == E.ambient(0n, 0n) : E.ContentArea}:
  {==}









def state_allocation(+value: D.Style, +space: E.ContentArea) ->
  {interaction(A.with_content_area(value, space)) == interaction(value) : D.ControlStates}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  E.Frame{old_area, old_arrangement} = content_frame
  {==}









type Requirements is Type:
  Requirements{positive: @+profile:E.Profile -> {(Nat.min(1n, E.inline(E.area(profile))), Nat.min(1n, E.block(E.area(profile)))) == (1n, 1n) : (Nat & Nat)},
    extent: @+width:Nat -> @+height:Nat -> @+border:Nat -> @+space:E.ContentArea -> {E.required_extent(width, height, border, space) == E.Extent{Nat.add(width, Nat.mul(2n, Nat.add(border, E.inline(space)))), Nat.add(height, Nat.mul(2n, Nat.add(border, E.block(space))))} : E.Extent},
    borderless: @+width:Nat -> @+height:Nat -> @+profile:E.Profile -> {E.required_extent(width, height, 0n, E.area(profile)) == E.Extent{Nat.add(width, Nat.mul(2n, E.inline(E.area(profile)))), Nat.add(height, Nat.mul(2n, E.block(E.area(profile))))} : E.Extent},
    action_insets: @+value:D.Style -> @+geometry:C.Geometry -> @+space:E.ContentArea -> @+gap:Nat -> {area(A.action_style_insets(value, geometry, space, gap)) == space : E.ContentArea},
    layout_copied: @+value:D.Style -> @+layout:C.ContentLayout -> @+geometry:C.Geometry -> {area(A.action_content_style(value, layout, geometry)) == layout_area(layout) : E.ContentArea},
    action_copied: @+value:D.Style -> @+face:C.Face -> @+geometry:C.Geometry -> {area(A.action_style(value, face, geometry)) == layout_area(C.content_layout(face)) : E.ContentArea},
    minimum_extent: @+value:D.Style -> @+geometry:C.Geometry -> @+space:E.ContentArea -> @+gap:Nat -> {minimum(A.action_style_insets(value, geometry, space, gap)) == Nat.max(geometry_height(geometry), A.extent_height(E.required_extent(0n, A.text_line_height(typography(value)), A.chrome_border_width(chrome(value)), space))) : Nat},
    choice_area: {area(A.choice_button(True{})) == area(A.choice_button(False{})) : E.ContentArea},
    choice_text: {typography(A.choice_button(True{})) == typography(A.choice_button(False{})) : D.TextStyle},
    role_navigation: @+meaning:UI.Meaning -> {area(A.style(UI.Navigation{}, meaning)) == E.area(E.Navigation{}) : E.ContentArea},
    role_usermessage: @+meaning:UI.Meaning -> {area(A.style(UI.UserMessage{}, meaning)) == E.area(E.UserMessage{}) : E.ContentArea},
    role_composer: @+meaning:UI.Meaning -> {area(A.style(UI.Composer{}, meaning)) == E.area(E.Composer{}) : E.ContentArea},
    role_approval: @+meaning:UI.Meaning -> {area(A.style(UI.Approval{}, meaning)) == E.area(E.Approval{}) : E.ContentArea},
    role_codeblock: @+meaning:UI.Meaning -> {area(A.style(UI.CodeBlock{}, meaning)) == E.area(E.CodeBlock{}) : E.ContentArea},
    role_menu: @+meaning:UI.Meaning -> {area(A.style(UI.Menu{}, meaning)) == E.area(E.Menu{}) : E.ContentArea},
    role_details: @+meaning:UI.Meaning -> {area(A.style(UI.Details{}, meaning)) == E.area(E.Details{}) : E.ContentArea},
    role_card: @+meaning:UI.Meaning -> {area(A.style(UI.Card{}, meaning)) == E.area(E.Card{}) : E.ContentArea},
    role_dialog: @+meaning:UI.Meaning -> {area(A.style(UI.Dialog{}, meaning)) == E.DialogPartitions{} : E.ContentArea},
    canvas: @+meaning:UI.Meaning -> {area(A.style(UI.Main{}, meaning)) == E.ambient(0n, 0n) : E.ContentArea},
    field: {area(A.editable_field()) == E.area(E.Field{}) : E.ContentArea},
    part_header: {E.partition(E.Header{}) == E.ambient(24n, 14n) : E.ContentArea},
    part_body: {E.partition(E.Body{}) == E.ambient(24n, 20n) : E.ContentArea},
    part_footer: {E.partition(E.Footer{}) == E.ambient(24n, 12n) : E.ContentArea},
    state_allocation: @+value:D.Style -> @+space:E.ContentArea -> {interaction(A.with_content_area(value, space)) == interaction(value) : D.ControlStates},
    icon_layout: @+icon:C.Icon -> {layout_area(C.content_layout(C.IconFace{icon})) == E.area(E.IconControl{}) : E.ContentArea},
    text_layout: @+text:String -> {layout_area(C.content_layout(C.TextFace{text})) == E.area(E.TextControl{}) : E.ContentArea},
    option_layout: @+text:String -> @+selected:Bool -> {layout_area(C.content_layout(C.ChoiceFace{text, selected})) == E.area(E.OptionControl{}) : E.ContentArea},
    embedded_input: {area(A.widget_field_style(C.MessageInput{}, Forms.Multiline{})) == E.ambient(8n, 6n) : E.ContentArea}}

def evidence() -> Requirements:
  Requirements{positive, +width => +height => +border => +space => {==}, +width => +height => +profile => {==}, action_insets, layout_copied, +value => +face => +geometry =>
      Equal.trans(E.ContentArea, area(A.action_style(value, face, geometry)),
        area(A.action_content_style(A.action_text(value, face, geometry), C.content_layout(face), geometry)), layout_area(C.content_layout(face)),
        flow_preserves_area(A.action_content_style(A.action_text(value, face, geometry), C.content_layout(face), geometry), A.action_flow(face, C.content_layout(face))),
        layout_copied(A.action_text(value, face, geometry), C.content_layout(face), geometry))
    , minimum_extent, {==}, {==}, +meaning => {==}, +meaning => {==}, +meaning => {==}, +meaning => {==}, +meaning => {==}, +meaning => {==}, +meaning => {==}, +meaning => {==}, +meaning => {==}, canvas, {==}, {==}, {==}, {==}, state_allocation, +icon => {==}, +text => {==}, +text => +selected => {==}, {==}}
