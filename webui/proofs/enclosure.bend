import Base
import ../spatial.bend as SpatialModel
import ../space.bend as Space
import ../typography.bend as T
import ../enclosure.bend as E
import ../appearance.bend as A
import ../controls.bend as C
import ../design.bend as D
import ../../core/interface.bend as InterfaceView
import ../enclosure-laws.bend as Rule

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
    case E.PageContent{}: {==}

def action_insets(+value: D.Style, +geometry: C.Geometry, +space: E.ContentArea, +gap: Nat, content_height: Nat) ->
  {Rule.area(A.action_style_insets(value, geometry, space, gap, content_height)) == space : E.ContentArea}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}

def layout_copied(+value: D.Style, +layout: C.ContentLayout, +geometry: C.Geometry, content_height: Nat) ->
  {Rule.area(A.action_content_style(value, layout, geometry, content_height)) == C.layout_content_area(layout) : E.ContentArea}:
  C.ContentLayout{alignment, space, gap} = layout
  action_insets(value, geometry, space, gap, content_height)

def flow_preserves_area(+value: D.Style, flow: SpatialModel.Flow) ->
  {Rule.area(A.with_flow(value, flow)) == Rule.area(value) : E.ContentArea}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def minimum_extent(+value: D.Style, +geometry: C.Geometry, +space: E.ContentArea, +gap: Nat, +content_height: Nat) ->
  {D.style_minimum_height(A.action_style_insets(value, geometry, space, gap, content_height)) == Nat.max(C.geometry_minimum_height(geometry), E.extent_height(E.required_extent(0n, content_height, A.chrome_border_width(Rule.chrome(value)), space))) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}

def canvas(+meaning: InterfaceView.Meaning, +typography: T.Presentation) ->
  {Rule.area(A.style(InterfaceView.Main{}, meaning, typography)) == E.ambient(0n, 0n) : E.ContentArea}:
  {==}

def state_allocation(+value: D.Style, +space: E.ContentArea) ->
  {Rule.interaction(A.with_content_area(value, space)) == Rule.interaction(value) : D.ControlStates}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  E.Frame{old_area, old_arrangement} = content_frame
  {==}

def page_content() -> Rule.page_content(): {==}

def Rule.evidence():
  Rule.Requirements{page_content(), positive, +width => +height => +border => +space => {==}, +width => +height => +profile => {==}, action_insets, layout_copied, +value => +face => +geometry =>
      Equal.trans(E.ContentArea, Rule.area(A.action_style(value, face, geometry)),
        Rule.area(A.action_content_style(value, C.content_layout(face), geometry, A.intrinsic_content_height(face, D.style_text(value), geometry))), C.layout_content_area(C.content_layout(face)),
        flow_preserves_area(A.action_content_style(value, C.content_layout(face), geometry, A.intrinsic_content_height(face, D.style_text(value), geometry)), A.action_flow(face, C.content_layout(face))),
        layout_copied(value, C.content_layout(face), geometry, A.intrinsic_content_height(face, D.style_text(value), geometry)))
    ,
    +typography => minimum_extent,
    +typography => {==},
    +typography => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => {==},
    +typography => +meaning => canvas(meaning, typography),
    +typography => {==}, {==}, {==}, {==}, state_allocation, +text => {==}, +text => +selected => {==},
    +typography => {==}}
