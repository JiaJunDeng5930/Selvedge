import Base
import ./FRAME.bend as Frame
import ../layout/PROGRAM.bend as Allocation
import ../layout/CONTENT.bend as Content
import ../layout/physical-space.bend as Model
import ../layout/RENDERER.bend as Renderer
import ../layout/GEOMETRY.bend as Spatial
import ./MODEL.bend as Doc
import ./RENDERED.bend as Rendered
import ../controls/GEOMETRY.bend as Geometry
import ../layout/SPACE.bend as Space
import ../layout/enclosure.bend as Enclosure

type Requirements is Type:
  Requirements{
    actual_tree: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.DOMEvent> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      {Frame.expected(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Frame.forest([tree]) : +List<Frame.Expected>},
    complete_node: @+key:String -> @+bounds:Spatial.Box -> @+interaction:Model.Interaction<Doc.DOMEvent> -> @+rest:+List<Frame.Expected> -> @+elements:+List<Rendered.Element> -> @+viewport:Geometry.Rect ->
      {Frame.nodes(Frame.Expected{key, bounds, interaction} <> rest, elements, viewport) ==
        List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Nat.is_eq(Frame.occurrences(elements, key), 1n)), Rendered.MissingElement{key}),
          List.append(&2, Rendered.Violation, Frame.node_geometry(key, bounds, interaction, Rendered.find_element(elements, key), viewport), Frame.nodes(rest, elements, viewport))) : +List<Rendered.Violation>},
    source_tab_order: @+key:String -> @+bounds:Spatial.Box -> @+interaction:Model.Interaction<Doc.DOMEvent> -> @+rest:+List<Frame.Expected> ->
      {Frame.tabs(Frame.Expected{key, bounds, interaction} <> rest) == Rendered.tab_entry(Frame.interactive(interaction), key, Frame.tabs(rest)) : +List<String>},
    leaf_traversal: @+physical:String -> @+value:Content.Value -> @+interaction:Model.Interaction<Doc.DOMEvent> -> @+rule:Model.Rule -> @+demand:Space.Demand -> @+height:Model.Height -> @+bounds:Spatial.Box -> @+canvas:Enclosure.Extent -> @+rest:+List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>> ->
      {Frame.forest(Allocation.AllocatedLeaf{physical, value, interaction, rule, demand, height, bounds, canvas} <> rest) == Frame.entry(value, bounds, interaction, Frame.forest(rest)) : +List<Frame.Expected>},
    container_traversal: @+physical:String -> @+value:Content.Value -> @+interaction:Model.Interaction<Doc.DOMEvent> -> @+rule:Model.Rule -> @+bounds:Spatial.Box -> @+canvas:Enclosure.Extent -> @+direction:Allocation.ResolvedDirection -> @+children:+List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>> -> @+rest:+List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>> ->
      {Frame.forest(Allocation.AllocatedContainer{physical, value, interaction, rule, bounds, canvas, direction, children} <> rest) == Frame.entry(value, bounds, interaction, List.append(&2, Frame.Expected, Frame.forest(children), Frame.forest(rest))) : +List<Frame.Expected>},
    full_contract: @+world:Content.AllocatedWorld -> @+viewport:Geometry.Rect -> @+elements:+List<Rendered.Element> -> @+focused:Maybe<&2, String> -> @+tab_order:+List<String> -> @+native_focus:+List<Rendered.NativeFocus> ->
      {Frame.check(world, Rendered.Frame{viewport, elements, focused, tab_order, native_focus}) ==
        List.append(&2, Rendered.Violation, Frame.nodes(Frame.expected(world), elements, viewport),
          List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(Frame.tabs(Frame.expected(world)), tab_order)), Rendered.WrongTabOrder{}),
            List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Frame.no_native(world) && Frame.native_free(native_focus)), Rendered.FocusOutsideScope{}),
              List.append(&2, Rendered.Violation, Frame.focus_checks(focused, Frame.expected(world), elements, viewport),
                Rendered.independent_targets(Frame.controls(Frame.expected(world), elements)))))) : +List<Rendered.Violation>},
    allocated_rectangle: @+left:Nat -> @+top:Nat -> @+width:Nat -> @+height:Nat ->
      {Frame.rectangle(Spatial.Box{left, top, width, height}) == Geometry.Rect{F32.from_nat(left), F32.from_nat(top), F32.from_nat((left + width : Nat)), F32.from_nat((top + height : Nat))} : Geometry.Rect},
    observed_geometry: @+key:String -> @+bounds:Spatial.Box -> @+interaction:Model.Interaction<Doc.DOMEvent> -> @+viewport:Geometry.Rect -> @+observed:String -> @+visible:Bool -> @+enabled:Bool -> @+tab:Bool -> @+keyboard:Bool -> @+scroll:Bool -> @+measured:Geometry.Rect -> @+hit:String -> @+paint:Geometry.Rect ->
      {Frame.node_geometry(key, bounds, interaction, Some{Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, measured, hit, paint}}, viewport) ==
        List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(visible && Frame.same_rectangle(Frame.rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Rendered.paint_geometry_valid(visible, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}),
          Frame.operable_geometry(interaction, key, Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, measured, hit, paint}, viewport)) : +List<Rendered.Violation>},
    focus_contract: @+focused:Maybe<&2, String> -> @+entries:+List<Frame.Expected> -> @+elements:+List<Rendered.Element> -> @+viewport:Geometry.Rect ->
      {Frame.focus_checks(focused, entries, elements, viewport) == List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Frame.focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), Frame.focus_geometry(focused, elements, viewport)) : +List<Rendered.Violation>},
    display_only: @+key:String -> @+element:Rendered.Element -> @+viewport:Geometry.Rect ->
      {Frame.operable_geometry(Model.DisplayOnly{}, key, element, viewport) == Nil{} : +List<Rendered.Violation>}}

law evidence:
  Requirements
