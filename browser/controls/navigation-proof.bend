import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../appearance/DESIGN.bend as Design
import ../document/SOURCE.bend as Source
import ../../bendlib/categories.bend as Categories
import ./SIDEBAR.bend as Sidebar

import ../layout/physical-space.bend as Physical
import ../layout/natural-size.bend as NaturalSize

def local_axis_fields(+capacity:Nat, +key:UIIdentity.Key, +owner:UIIdentity.Key, +depth:Nat, +visual:Design.Style, +entry:Sidebar.Entry, +offset:Nat, +leading:Nat, +target:Nat, +trailing:Nat, +visual_rail:Nat) ->
  {Sidebar.columns(Sidebar.entry_source_fields_with_rail_at(capacity, key, owner, depth, visual, entry, offset, leading, target, trailing, visual_rail)) == [Physical.ExactSize{Nat.add(offset, Sidebar.leading_allocation(visual_rail, target))}, Physical.StretchSize{}, Physical.ExactSize{trailing}] : +List<Physical.AxisSize>}:
  Design.Style{font, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  match entry:
    case Sidebar.SingleAction{Sidebar.Command{command_key, style, attrs, name, enabled, first, remaining, children}, status}: {==}
    case Sidebar.ProjectActions{Sidebar.Command{toggle_key, toggle_style, toggle_attrs, toggle_name, toggle_enabled, toggle_first, toggle_remaining, toggle_children}, Sidebar.Command{open_key, Source.Style{Source.Layout{open_direction, open_main, open_cross, open_frame, open_width, open_height, open_minimum, open_scroll, open_position}, open_font, open_chrome, open_states}, open_attrs, open_name, open_enabled, open_first, open_remaining, open_children}, Sidebar.Command{create_key, create_style, create_attrs, create_name, create_enabled, create_first, create_remaining, create_children}, Sidebar.Command{more_key, more_style, more_attrs, more_name, more_enabled, more_first, more_remaining, more_children}, visible}: {==}

def shared_axis_fields(+capacity:Nat, +key:UIIdentity.Key, +owner:UIIdentity.Key, +depth:Nat, +visual:Design.Style, +entry:Sidebar.Entry, +offset:Nat, +leading:Nat, +target:Nat, +trailing:Nat, +rail:Nat, +visual_rail:Nat) ->
  {Sidebar.columns(Sidebar.first_aligned_node(Sidebar.entry_source_fields_with_rail_at(capacity, key, owner, depth, visual, entry, offset, leading, target, trailing, visual_rail), rail)) == [Physical.ExactSize{Nat.add(offset, Sidebar.leading_allocation(rail, target))}, Physical.StretchSize{}, Physical.ExactSize{trailing}] : +List<Physical.AxisSize>}:
  Design.Style{font, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  match entry:
    case Sidebar.SingleAction{Sidebar.Command{command_key, style, attrs, name, enabled, first, remaining, children}, status}: {==}
    case Sidebar.ProjectActions{Sidebar.Command{toggle_key, toggle_style, toggle_attrs, toggle_name, toggle_enabled, toggle_first, toggle_remaining, toggle_children}, Sidebar.Command{open_key, Source.Style{Source.Layout{open_direction, open_main, open_cross, open_frame, open_width, open_height, open_minimum, open_scroll, open_position}, open_font, open_chrome, open_states}, open_attrs, open_name, open_enabled, open_first, open_remaining, open_children}, Sidebar.Command{create_key, create_style, create_attrs, create_name, create_enabled, create_first, create_remaining, create_children}, Sidebar.Command{more_key, more_style, more_attrs, more_name, more_enabled, more_first, more_remaining, more_children}, visible}: {==}

def construction_evidence_axes(+capacity:Nat, +key:UIIdentity.Key, +owner:UIIdentity.Key, +depth:Nat, +visual:Design.Style, +entry:Sidebar.Entry, axes:Sidebar.common_axis_at(capacity, Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source_at(capacity, key, owner, depth, visual, entry)})) -> Sidebar.authored_at(capacity, Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source_at(capacity, key, owner, depth, visual, entry)}):
  Design.Style{font, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  match entry:
    case Sidebar.SingleAction{Sidebar.Command{command_key, style, attrs, name, enabled, first, remaining, children}, status}: Sidebar.Authored{{==}, {==}, {==}, axes, {==}, {==}, {==}}
    case Sidebar.ProjectActions{Sidebar.Command{toggle_key, toggle_style, toggle_attrs, toggle_name, toggle_enabled, toggle_first, toggle_remaining, toggle_children}, Sidebar.Command{open_key, Source.Style{Source.Layout{open_direction, open_main, open_cross, open_frame, open_width, open_height, open_minimum, open_scroll, open_position}, open_font, open_chrome, open_states}, open_attrs, open_name, open_enabled, open_first, open_remaining, open_children}, Sidebar.Command{create_key, create_style, create_attrs, create_name, create_enabled, create_first, create_remaining, create_children}, Sidebar.Command{more_key, more_style, more_attrs, more_name, more_enabled, more_first, more_remaining, more_children}, visible}: Sidebar.Authored{{==}, {==}, {==}, axes, {==}, {==}, {==}}


def construction_evidence(+capacity:Nat, +key:UIIdentity.Key, +owner:UIIdentity.Key, +depth:Nat, +visual:Design.Style, +entry:Sidebar.Entry) -> Sidebar.authored_at(capacity, Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source_at(capacity, key, owner, depth, visual, entry)}):
  local: Sidebar.local_axis_at(capacity, Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source_at(capacity, key, owner, depth, visual, entry)}) =
    local_axis_fields(capacity, key, owner, depth, visual, entry, Sidebar.indentation_at(capacity, depth, visual), Sidebar.entry_leading_requirement_at(capacity, entry, visual), Sidebar.navigation_target_at(capacity, visual), Sidebar.trailing_width_at(capacity, entry, visual), Sidebar.navigation_visual_rail_at(capacity, visual))
  shared: @+rail:Nat -> Sidebar.shared_axis_at(capacity, Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source_at(capacity, key, owner, depth, visual, entry)}, rail) =
    +rail => shared_axis_fields(capacity, key, owner, depth, visual, entry, Sidebar.indentation_at(capacity, depth, visual), Sidebar.entry_leading_requirement_at(capacity, entry, visual), Sidebar.navigation_target_at(capacity, visual), Sidebar.trailing_width_at(capacity, entry, visual), rail, Sidebar.navigation_visual_rail_at(capacity, visual))

  construction_evidence_axes(capacity, key, owner, depth, visual, entry, Sidebar.Axes{local, shared})

def Sidebar.construct_at():
  +capacity => +key => +owner => +depth => +visual => +entry => Categories.Membership{Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source_at(capacity, key, owner, depth, visual, entry)}, construction_evidence(capacity, key, owner, depth, visual, entry)}

def Sidebar.construct():
  +key => +owner => +depth => +visual => +entry => Sidebar.construct_at(NaturalSize.limit(), key, owner, depth, visual, entry)

def Sidebar.constructor_correspondence_at():
  +capacity => +key => +owner => +depth => +visual => +entry => {==}

def Sidebar.constructor_correspondence():
  +key => +owner => +depth => +visual => +entry => Sidebar.constructor_correspondence_at(NaturalSize.limit(), key, owner, depth, visual, entry)

def collection_evidence(+request:Sidebar.CollectionRequest) -> Sidebar.collection_authored(Sidebar.CollectionObservation{request, Sidebar.collection_request_source(request)}):
  match request:
    case Sidebar.CollectionRequest{key, Sidebar.Collection{}, Design.Style{font, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}, other}: Sidebar.CollectionAuthored{{==}, {==}}
    case Sidebar.CollectionRequest{key, Sidebar.Members{}, Design.Style{font, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}, other}: Sidebar.CollectionAuthored{{==}, {==}}
    case Sidebar.CollectionRequest{key, Sidebar.Section{}, Design.Style{font, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}, Nil{}}: Sidebar.CollectionAuthored{{==}, {==}}
    case Sidebar.CollectionRequest{key, Sidebar.Section{}, Design.Style{font, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}, Con{header, Nil{}}}: Sidebar.CollectionAuthored{{==}, {==}}
    case Sidebar.CollectionRequest{key, Sidebar.Section{}, Design.Style{font, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}, Con{header, Con{member, rest}}}: Sidebar.CollectionAuthored{{==}, {==}}

def Sidebar.construct_collection():
  +request => Categories.Membership{Sidebar.CollectionObservation{request, Sidebar.collection_request_source(request)}, collection_evidence(request)}

def Sidebar.collection_constructor_correspondence():
  +request => {==}


def Sidebar.navigation_row_minimum_combines_target_and_actual_line_box():
  +capacity => +visual => {==}

def Sidebar.navigation_caption_keeps_complete_single_line_text():
  key => value => font => wrapping => rest => {==}

def Sidebar.collection_separates_groups_with_hierarchy_heading_gap():
  {==}

def Sidebar.project_header_and_members_are_contiguous():
  {==}

def Sidebar.task_rows_are_contiguous():
  {==}


def Sidebar.indentation_uses_hierarchy_membership_step():
  +capacity => +depth => +visual => {==}

def Sidebar.navigation_title_keeps_existing_reason():
  name => {==}

def Sidebar.navigation_title_supplies_complete_name_without_reason():
  +name => {==}
