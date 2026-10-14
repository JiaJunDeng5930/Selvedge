import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../appearance/DESIGN.bend as Design
import ../document/SOURCE.bend as Source
import ../../bendlib/categories.bend as Categories
import ./SIDEBAR.bend as Sidebar

def construction_evidence(+key:UIIdentity.Key, +owner:UIIdentity.Key, +depth:Nat, +visual:Design.Style, +entry:Sidebar.Entry) -> Sidebar.authored(Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source(key, owner, depth, visual, entry)}):
  Design.Style{font, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  match entry:
    case Sidebar.SingleAction{Sidebar.Command{command_key, style, attrs, name, enabled, first, remaining, children}, status}: Sidebar.Authored{{==}, {==}, {==}, {==}, {==}}
    case Sidebar.ProjectActions{Sidebar.Command{toggle_key, toggle_style, toggle_attrs, toggle_name, toggle_enabled, toggle_first, toggle_remaining, toggle_children}, Sidebar.Command{open_key, Source.Style{Source.Layout{open_direction, open_main, open_cross, open_frame, open_width, open_height, open_minimum, open_scroll, open_position}, open_font, open_chrome, open_states}, open_attrs, open_name, open_enabled, open_first, open_remaining, open_children}, Sidebar.Command{create_key, create_style, create_attrs, create_name, create_enabled, create_first, create_remaining, create_children}, Sidebar.Command{more_key, more_style, more_attrs, more_name, more_enabled, more_first, more_remaining, more_children}, visible}: Sidebar.Authored{{==}, {==}, {==}, {==}, {==}}

def Sidebar.construct():
  +key => +owner => +depth => +visual => +entry => Categories.Membership{Sidebar.Observation{key, owner, depth, visual, entry, Sidebar.entry_source(key, owner, depth, visual, entry)}, construction_evidence(key, owner, depth, visual, entry)}

def Sidebar.constructor_correspondence():
  +key => +owner => +depth => +visual => +entry => {==}

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
