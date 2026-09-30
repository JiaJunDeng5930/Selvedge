import ../core/interface.bend as Interface
import ./appearance.bend as Appearance
import Base
import ./document.bend as Doc
import ./renderer.bend as Render
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View

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
  bounds_refinement(box)

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
  +band: Design.Band, +input: Maybe<&2, Design.InputMetrics>) ->
  {observed_box(second_node(Render.main_children(children, Design.CreationFrame{heading, canvas, band, input}))) ==
    specified_box(canvas) : (String & (String & (String & String)))}:
  bounds_refinement(canvas)

def unavailable_canvas(+children: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box, +band: Design.Band) ->
  {observed_box(second_node(Render.main_children(children, Design.UnavailableFrame{heading, canvas, band}))) ==
    specified_box(canvas) : (String & (String & (String & String)))}:
  bounds_refinement(canvas)

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
type Requirements is Type:
  Requirements{
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
    creation_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band -> @+input:Maybe<&2, Design.InputMetrics> ->
      {observed_box(second_node(Render.main_children(children, Design.CreationFrame{heading, canvas, band, input}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    unavailable_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band ->
      {observed_box(second_node(Render.main_children(children, Design.UnavailableFrame{heading, canvas, band}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    rendered_region_count: @+values:+List<Interface.Node> -> @+context:Controls.Context ->
      {List.length(&2, Doc.Node, Render.render_nodes(values, Appearance.nodes_at(values, context))) ==
          List.length(&2, Interface.Node, values) : Nat}
  }

def evidence() -> Requirements:
  Requirements{
    box => bounds_refinement(box),
    key => region => box => children => region_bounds(key, region, box, children),
    key => style => input => availability => name => face => behavior => geometry => placement => help => feedback => action_event(key, style, input, availability, name, face, behavior, geometry, placement, help, feedback),
    key => style => input => availability => name => face => behavior => geometry => placement => help => feedback => action_accessible_name(key, style, input, availability, name, face, behavior, geometry, placement, help, feedback),
    key => textarea_event(key),
    key => toggle_event(key),
    key => face => file_event(key, face),
    children => heading => canvas => band => input => creation_canvas(children, heading, canvas, band, input),
    children => heading => canvas => band => unavailable_canvas(children, heading, canvas, band),
    values => context => rendered_region_count(values, context)
  }
