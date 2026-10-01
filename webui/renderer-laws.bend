import ../core/interface.bend as Interface
import ./appearance.bend as Appearance
import Base
import ./document.bend as Doc
import ./renderer.bend as Render
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User

# These observations read the actual browser primitives, independently of the
# renderer's construction functions. Missing geometry is the empty observation.
def css_box(+properties: +List<Doc.Property>) -> (String & (String & (String & String))):
  (Render.attr(properties, "left"), (Render.attr(properties, "top"),
    (Render.attr(properties, "width"), Render.attr(properties, "height"))))

def observed_box(node: Doc.Node) -> (String & (String & (String & String))):
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: css_box(styles)
    case _: ("", ("", ("", "")))

def specified_box(box: Design.Box) -> (String & (String & (String & String))):
  Design.Box{left, top, width, height} = box
  (Nat.show(left) ++ "px", (Nat.show(top) ++ "px", (Nat.show(width) ++ "px", Nat.show(height) ++ "px")))

def bounds_refinement(box: Design.Box) ->
  {css_box(Render.bounds(box)) == specified_box(box) : (String & (String & (String & String)))}:
  Design.Box{left, top, width, height} = box
  {==}

def region_bounds(+key: String, +region: String, +box: Design.Box, +children: +List<Doc.Node>) ->
  {observed_box(Render.frame_region(key, region, box, children)) == specified_box(box) : (String & (String & (String & String)))}:
  match box:
    case Design.Box{left, top, width, height}: {==}

def node_events(node: Doc.Node) -> +List<Doc.Event>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: events
    case _: Nil{}

def node_attributes(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: attrs
    case _: Nil{}

def action_event(+key: String, +style: Design.Style, +input: Core.Input,
  +availability: View.Availability, +name: String, +face: Controls.Face,
  +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement,
  +help: Controls.Help, +feedback: Controls.Feedback) ->
  {node_events(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
    Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})) ==
    [Doc.Activate{key}] : +List<Doc.Event>}:
  {==}

def action_accessible_name(+key: String, +style: Design.Style, +input: Core.Input,
  +availability: View.Availability, +name: String, +face: Controls.Face,
  +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement,
  +help: Controls.Help, +feedback: Controls.Feedback) ->
  {Render.attr(node_attributes(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
    Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "aria-label") == name : String}:
  {==}

def textarea_event(+key: String) ->
  {Render.input_events(key, Controls.MessageInput{}) == [Doc.EditText{key}] : +List<Doc.Event>}:
  {==}

def toggle_event(+key: String) ->
  {Render.input_events(key, Controls.ToggleInput{}) == [Doc.EditToggle{key}] : +List<Doc.Event>}:
  {==}

def file_event(+key: String, +face: Controls.Face) ->
  {Render.input_events(key, Controls.FileChooser{face}) == [Doc.SelectFiles{key}] : +List<Doc.Event>}:
  {==}

def first_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Nil{}: Doc.Text{""}
    case Con{value, rest}: value

def second_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{value, rest}: first_node(rest)
    case Nil{}: Doc.Text{""}

def creation_canvas(+children: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box,
  +band: Design.Band, +input: Maybe<&2, Design.InputMetrics>, +flow: Design.CreationFlow) ->
  {observed_box(first_node(Render.main_children(children, Design.CreationFrame{heading, canvas, band, input, flow}))) ==
    specified_box(canvas) : (String & (String & (String & String)))}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def unavailable_canvas(+children: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box, +band: Design.Band) ->
  {observed_box(first_node(Render.main_children(children, Design.UnavailableFrame{heading, canvas, band}))) ==
    specified_box(canvas) : (String & (String & (String & String)))}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

# The appearance traversal is the production traversal, so this statement rules
# out silently truncating a surface merely because the renderer zips two lists.

def rendered_region_count(+values: +List<Interface.Node>, +context: Controls.Context) ->
  {List.length(&2, Doc.Node, Render.render_nodes(values, Appearance.nodes_at(values, context))) ==
    List.length(&2, Interface.Node, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{Interface.Node{key, semantic, label, role, meaning, children}, rest}:
      Equal.cong(Nat, Nat, (count => (1n + count : Nat)),
        List.length(&2, Doc.Node, Render.render_nodes(rest, Appearance.nodes_at(rest, context))),
        List.length(&2, Interface.Node, rest), rendered_region_count(rest, context))


# This instance contains the checked production theorems, with their original
# quantifiers and conclusions retained verbatim.
def background_without_modal() ->
  {Render.background_properties(None{}) == Nil{} : +List<Doc.Property>}:
  {==}

def background_with_modal(current: String) ->
  {Render.background_properties(Some{current}) ==
    [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>}:
  {==}

def overlay_without_modal(key: String) ->
  {Render.modal_properties(None{}, key) == Nil{} : +List<Doc.Property>}:
  {==}

def overlay_with_modal(+current: String, +key: String) ->
  {Render.modal_properties(Some{current}, key) ==
    Render.modal_active_properties(String.eq(current, key)) : +List<Doc.Property>}:
  {==}

def active_overlay_properties() ->
  {Render.modal_active_properties(True{}) ==
    [Doc.Property{"role", "dialog"}, Doc.Property{"aria-modal", "true"}] : +List<Doc.Property>}:
  {==}

def inactive_overlay_properties() ->
  {Render.modal_active_properties(False{}) ==
    [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>}:
  {==}

def node_children(node: Doc.Node) -> +List<Doc.Node>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: children
    case _: Nil{}

def creation_group_retains_children(+children: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) ->
  {node_children(Render.creation_group(band, flow, children)) == children : +List<Doc.Node>}:
  match band:
    case Design.Band{left, width}: {==}

def creation_canvas_retains_group(+canvas: Design.Box, +band: Design.Band, +flow: Design.CreationFlow, +children: +List<Doc.Node>) ->
  {node_children(first_node(Render.creation_canvas_nodes(canvas, band, flow, children))) ==
    [Render.creation_group(band, flow, children)] : +List<Doc.Node>}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def root_theme_light() -> {Render.theme_name(Design.Light{}) == "light" : String}:
  {==}

def root_theme_dark() -> {Render.theme_name(Design.Dark{}) == "dark" : String}:
  {==}

def creation_composer_flows(heading: Design.Box, canvas: Design.Box, band: Design.Band,
  input: Maybe<&2, Design.InputMetrics>, flow: Design.CreationFlow) ->
  {Render.attr(Render.composer_styles(Design.CreationFrame{heading, canvas, band, input, flow}), "position") == "" : String}:
  {==}

def action_partition_order(+children: +List<Doc.Node>) ->
  {List.append(&2, Doc.Node, Render.action_leading(children), Render.action_trailing(children)) == children : +List<Doc.Node>}:
  match children:
    case Nil{}: {==}
    case Con{last, Nil{}}: {==}
    case Con{+first, Con{+second, +rest}}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => first <> tail),
        List.append(&2, Doc.Node, Render.action_leading(second <> rest), Render.action_trailing(second <> rest)), second <> rest,
        action_partition_order(second <> rest))

def composer_actions_keep_order(+key: String, +children: +List<Doc.Node>) ->
  {List.append(&2, Doc.Node,
    node_children(first_node(Render.composer_action_groups(key, children))),
    node_children(second_node(Render.composer_action_groups(key, children)))) == children : +List<Doc.Node>}:
  action_partition_order(children)

def target_attributes(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.TargetProperties{key, target, attributes, styles}: attributes
    case _: Nil{}

def target_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.TargetProperties{key, target, attributes, styles}: styles
    case _: Nil{}

def light_document_theme() ->
  {Render.document_theme(Design.Light{}) == Doc.TargetProperties{"document-theme", "@document/root",
    [Doc.Property{"data-theme", "light"}], [Doc.Property{"color-scheme", "light"}]} : Doc.Node}:
  {==}

def dark_document_theme() ->
  {Render.document_theme(Design.Dark{}) == Doc.TargetProperties{"document-theme", "@document/root",
    [Doc.Property{"data-theme", "dark"}], [Doc.Property{"color-scheme", "dark"}]} : Doc.Node}:
  {==}

def root_theme_attribute(+theme: Design.Theme) ->
  {Render.attr(target_attributes(Render.document_theme(theme)), "data-theme") == Render.theme_name(theme) : String}:
  {==}

def root_theme_color_scheme(+theme: Design.Theme) ->
  {Render.attr(target_styles(Render.document_theme(theme)), "color-scheme") == Render.theme_name(theme) : String}:
  {==}

def compound_field_preserves_children(+key: String, label: String, field: Forms.Field,
  visual: Design.Style, +children: +List<Doc.Node>) ->
  {node_children(Render.compound_field(key, label, field, visual, children)) == children : +List<Doc.Node>}:
  {==}

def compound_field_has_no_events(key: String, label: String, field: Forms.Field,
  visual: Design.Style, children: +List<Doc.Node>) ->
  {node_events(Render.compound_field(key, label, field, visual, children)) == Nil{} : +List<Doc.Event>}:
  {==}

def compound_field_is_not_tab_stop(key: String, label: String, field: Forms.Field,
  visual: Design.Style, children: +List<Doc.Node>) ->
  {Render.attr(node_attributes(Render.compound_field(key, label, field, visual, children)), "tabindex") == "-1" : String}:
  {==}

def directory_field_uses_compound(+key: String, +label: String, role: Interface.Role,
  owner: User.Editor, +field: Forms.Field, value: Forms.Observed, source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, representation: Controls.Representation,
  appearance: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.DirectoryCollection{}, value}, source, children, visual, representation, appearance) ==
    Render.compound_field(key, label, field, visual, children) : Doc.Node}:
  {==}

def file_field_uses_compound(+key: String, +label: String, role: Interface.Role,
  owner: User.Editor, +field: Forms.Field, value: Forms.Observed, source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, representation: Controls.Representation,
  appearance: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.FileCollection{}, value}, source, children, visual, representation, appearance) ==
    Render.compound_field(key, label, field, visual, children) : Doc.Node}:
  {==}

type Requirements is Type:
  Requirements{
    background_without_modal: {Render.background_properties(None{}) == Nil{} : +List<Doc.Property>},
    background_with_modal: @current:String ->
      {Render.background_properties(Some{current}) ==
        [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>},
    overlay_without_modal: @key:String ->
      {Render.modal_properties(None{}, key) == Nil{} : +List<Doc.Property>},
    overlay_with_modal: @+current:String -> @+key:String ->
      {Render.modal_properties(Some{current}, key) ==
        Render.modal_active_properties(String.eq(current, key)) : +List<Doc.Property>},
    active_overlay_properties: {Render.modal_active_properties(True{}) ==
      [Doc.Property{"role", "dialog"}, Doc.Property{"aria-modal", "true"}] : +List<Doc.Property>},
    inactive_overlay_properties: {Render.modal_active_properties(False{}) ==
      [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>},
    bounds_refinement: @box:Design.Box ->
      {css_box(Render.bounds(box)) == specified_box(box) : (String & (String & (String & String)))},
    region_bounds: @+key:String -> @+region:String -> @+box:Design.Box -> @+children:+List<Doc.Node> ->
      {observed_box(Render.frame_region(key, region, box, children)) == specified_box(box) : (String & (String & (String & String)))},
    action_event: @+key:String -> @+style:Design.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback ->
      {node_events(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
          Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})) ==
          [Doc.Activate{key}] : +List<Doc.Event>},
    action_accessible_name: @+key:String -> @+style:Design.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback ->
      {Render.attr(node_attributes(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
          Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "aria-label") == name : String},
    textarea_event: @+key:String ->
      {Render.input_events(key, Controls.MessageInput{}) == [Doc.EditText{key}] : +List<Doc.Event>},
    toggle_event: @+key:String ->
      {Render.input_events(key, Controls.ToggleInput{}) == [Doc.EditToggle{key}] : +List<Doc.Event>},
    file_event: @+key:String -> @+face:Controls.Face ->
      {Render.input_events(key, Controls.FileChooser{face}) == [Doc.SelectFiles{key}] : +List<Doc.Event>},
    creation_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band -> @+input:Maybe<&2, Design.InputMetrics> -> @+flow:Design.CreationFlow ->
      {observed_box(first_node(Render.main_children(children, Design.CreationFrame{heading, canvas, band, input, flow}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    unavailable_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band ->
      {observed_box(first_node(Render.main_children(children, Design.UnavailableFrame{heading, canvas, band}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    rendered_region_count: @+values:+List<Interface.Node> -> @+context:Controls.Context ->
      {List.length(&2, Doc.Node, Render.render_nodes(values, Appearance.nodes_at(values, context))) ==
          List.length(&2, Interface.Node, values) : Nat},
    creation_group_retains_children: @+children:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {node_children(Render.creation_group(band, flow, children)) == children : +List<Doc.Node>},
    creation_canvas_retains_group: @+canvas:Design.Box -> @+band:Design.Band -> @+flow:Design.CreationFlow -> @+children:+List<Doc.Node> ->
      {node_children(first_node(Render.creation_canvas_nodes(canvas, band, flow, children))) == [Render.creation_group(band, flow, children)] : +List<Doc.Node>},
    creation_composer_flows: @heading:Design.Box -> @canvas:Design.Box -> @band:Design.Band -> @input:Maybe<&2, Design.InputMetrics> -> @flow:Design.CreationFlow ->
      {Render.attr(Render.composer_styles(Design.CreationFrame{heading, canvas, band, input, flow}), "position") == "" : String},
    composer_actions_keep_order: @+key:String -> @+children:+List<Doc.Node> ->
      {List.append(&2, Doc.Node, node_children(first_node(Render.composer_action_groups(key, children))),
        node_children(second_node(Render.composer_action_groups(key, children)))) == children : +List<Doc.Node>},
    light_document_theme: {Render.document_theme(Design.Light{}) == Doc.TargetProperties{"document-theme", "@document/root",
      [Doc.Property{"data-theme", "light"}], [Doc.Property{"color-scheme", "light"}]} : Doc.Node},
    dark_document_theme: {Render.document_theme(Design.Dark{}) == Doc.TargetProperties{"document-theme", "@document/root",
      [Doc.Property{"data-theme", "dark"}], [Doc.Property{"color-scheme", "dark"}]} : Doc.Node},
    root_theme_attribute: @+theme:Design.Theme -> {Render.attr(target_attributes(Render.document_theme(theme)), "data-theme") == Render.theme_name(theme) : String},
    root_theme_color_scheme: @+theme:Design.Theme -> {Render.attr(target_styles(Render.document_theme(theme)), "color-scheme") == Render.theme_name(theme) : String},
    compound_field_preserves_children: @+key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @+children:+List<Doc.Node> ->
      {node_children(Render.compound_field(key, label, field, visual, children)) == children : +List<Doc.Node>},
    compound_field_has_no_events: @key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @children:+List<Doc.Node> ->
      {node_events(Render.compound_field(key, label, field, visual, children)) == Nil{} : +List<Doc.Event>},
    compound_field_is_not_tab_stop: @key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @children:+List<Doc.Node> ->
      {Render.attr(node_attributes(Render.compound_field(key, label, field, visual, children)), "tabindex") == "-1" : String},
    directory_field_uses_compound: @+key:String -> @+label:String -> @role:Interface.Role -> @owner:User.Editor -> @+field:Forms.Field ->
      @value:Forms.Observed -> @source:+List<Interface.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @representation:Controls.Representation -> @appearance:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.DirectoryCollection{}, value}, source, children, visual, representation, appearance) == Render.compound_field(key, label, field, visual, children) : Doc.Node},
    file_field_uses_compound: @+key:String -> @+label:String -> @role:Interface.Role -> @owner:User.Editor -> @+field:Forms.Field ->
      @value:Forms.Observed -> @source:+List<Interface.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @representation:Controls.Representation -> @appearance:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.FileCollection{}, value}, source, children, visual, representation, appearance) == Render.compound_field(key, label, field, visual, children) : Doc.Node}
  }

def evidence() -> Requirements:
  Requirements{
    background_without_modal(),
    current => background_with_modal(current),
    key => overlay_without_modal(key),
    current => key => overlay_with_modal(current, key),
    active_overlay_properties(),
    inactive_overlay_properties(),
    box => bounds_refinement(box),
    key => region => box => children => region_bounds(key, region, box, children),
    key => style => input => availability => name => face => behavior => geometry => placement => help => feedback => action_event(key, style, input, availability, name, face, behavior, geometry, placement, help, feedback),
    key => style => input => availability => name => face => behavior => geometry => placement => help => feedback => action_accessible_name(key, style, input, availability, name, face, behavior, geometry, placement, help, feedback),
    key => textarea_event(key),
    key => toggle_event(key),
    key => face => file_event(key, face),
    children => heading => canvas => band => input => flow => creation_canvas(children, heading, canvas, band, input, flow),
    children => heading => canvas => band => unavailable_canvas(children, heading, canvas, band),
    values => context => rendered_region_count(values, context),
    children => band => flow => creation_group_retains_children(children, band, flow),
    canvas => band => flow => children => creation_canvas_retains_group(canvas, band, flow, children),
    heading => canvas => band => input => flow => creation_composer_flows(heading, canvas, band, input, flow),
    key => children => composer_actions_keep_order(key, children),
    light_document_theme(),
    dark_document_theme(),
    theme => root_theme_attribute(theme),
    theme => root_theme_color_scheme(theme),
    key => label => field => visual => children => compound_field_preserves_children(key, label, field, visual, children),
    key => label => field => visual => children => compound_field_has_no_events(key, label, field, visual, children),
    key => label => field => visual => children => compound_field_is_not_tab_stop(key, label, field, visual, children),
    key => label => role => owner => field => value => source => children => visual => representation => appearance =>
      directory_field_uses_compound(key, label, role, owner, field, value, source, children, visual, representation, appearance),
    key => label => role => owner => field => value => source => children => visual => representation => appearance =>
      file_field_uses_compound(key, label, role, owner, field, value, source, children, visual, representation, appearance)
  }
