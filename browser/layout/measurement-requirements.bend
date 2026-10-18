import Base
import ../../bendlib/stdlib.bend as Std
import ./CONTENT.bend as Content
import ./field-dimensions.bend as FieldDimensions
import ./SOURCE.bend as PhysicalSource
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Doc
import ../appearance/TYPOGRAPHY.bend as T
import ./physical-space.bend as Model
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure
import ../../interaction/conversation/CODE.bend as Code

# Complete request admission: exact generation/key/purpose, ordered dimensions,
# positive field height/advance and positive nonempty text height. A Natural
# rich-text probe may omit only its own prepared interactive viewport.
def same_purpose(first: Content.Purpose, second: Content.Purpose) -> Bool:
  match first second:
    case Content.Natural{} Content.Natural{}: True{}
    case Content.AtWidth{left} Content.AtWidth{right}: Nat.is_eq(left, right)
    case _ _: False{}

def content_height_valid(value: String, height: Nat) -> Bool:
  String.eq(value, "") || Nat.is_le(1n, height)

def primitive_observation_valid(node: Source.Node, +height: Nat, +advance: Nat) -> Bool:
  match node:
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      Nat.is_le(1n, advance) && Nat.is_le(1n, height)
    case Source.Text{key, value, font, wrapping}: content_height_valid(value, height)
    case Source.RichText{key, style, Source.RichContent{source, value, policy}, attachments, native_owner}:
      content_height_valid(value, height)
    case Source.NativeAttachment{key, target, attributes, style, children}: False{}
    case Source.Box{key, tag, style, attributes, children}: False{}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: False{}
    case Source.Glyph{key, drawing, style}: False{}

# Natural Markdown probes omit the native interactive viewport. Only the actual
# prepared root owned by this request may account for a zero-height probe.

def interactive_target_belongs(target: Source.NativeTarget, source: Maybe<&2, Code.Source>) -> Bool:
  match target source:
    case Source.InteractiveTarget{identity} Some{owner}: Code.belongs(identity, owner)
    case Source.InteractiveTarget{identity} None{}: False{}
    case Source.ToolbarTarget{identity} _: False{}
    case Source.CodeBodyTarget{identity, wrap} _: False{}
    case Source.InteractiveSourceTarget{identity, exposed} _: False{}
    case Source.InteractiveFrameTarget{identity, active} _: False{}

def owned_interactive_root(roots: +List<Content.NativeRoot>, +key: String, +source: Maybe<&2, Code.Source>) -> Bool:
  match roots:
    case Nil{}: False{}
    case Con{Content.NativeRoot{owner_key, target, tree, attributes, style}, rest}:
      (String.eq(owner_key, key) && interactive_target_belongs(target, source)) || owned_interactive_root(rest, key, source)

def natural_ui_zero(node: Source.Node, +key: String, +roots: +List<Content.NativeRoot>, +height: Nat) -> Bool:
  match node:
    case Source.RichText{identity, style, Source.RichContent{source, value, policy}, attachments, native_owner}:
      owned_interactive_root(roots, key, source) && Nat.is_eq(height, 0n)
    case Source.NativeAttachment{identity, target, attributes, style, children}: False{}
    case Source.Box{identity, tag, style, attributes, children}: False{}
    case Source.Control{identity, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: False{}
    case Source.Text{identity, value, font, wrapping}: False{}
    case Source.Glyph{identity, drawing, style}: False{}
    case Source.Field{identity, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: False{}

def zero_height_ui(purpose: Content.Purpose, +node: Source.Node, +key: String,
  +roots: +List<Content.NativeRoot>, +height: Nat) -> Bool:
  match purpose:
    case Content.Natural{}: natural_ui_zero(node, key, roots, height)
    case Content.AtWidth{width}: False{}

def request_observation_valid(request: Content.Request, +height: Nat, +advance: Nat) -> Bool:
  Content.Request{generation, key, Content.Value{+node, font}, purpose, native_roots, native_policies} = request
  primitive_observation_valid(node, height, advance) || zero_height_ui(purpose, node, key, native_roots, height)

def observation_matches(+request: Content.Request, observation: Content.Observation) -> Bool:
  Content.Request{generation, key, value, purpose, roots, policies} = request
  Content.Observation{observed_generation, observed_key, observed_purpose, minimum, preferred, height, advance} = observation
  Nat.is_eq(generation, observed_generation) && String.eq(key, observed_key)
    && same_purpose(purpose, observed_purpose) && Nat.is_le(minimum, preferred)
    && request_observation_valid(request, height, advance)


def local_value(node: Source.Node, +font: T.Presentation) -> Content.Value:
  match node:
    case Source.Box{key, tag, style, attributes, children}:
      Content.Value{Source.Box{key, tag, style, attributes, Nil{}}, font}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}:
      Content.Value{Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, Nil{}}, font}
    case Source.RichText{key, style, content, attachments, native_owner}:
      Content.Value{Source.RichText{key, style, content, Nil{}, native_owner}, font}
    case Source.NativeAttachment{key, target, attributes, style, children}:
      Content.Value{Source.NativeAttachment{key, target, attributes, style, Nil{}}, font}
    case Source.Text{key, value, choice, wrapping}:
      Content.Value{Source.Text{key, value, choice, wrapping}, font}
    case Source.Glyph{key, drawing, style}:
      Content.Value{Source.Glyph{key, drawing, style}, font}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      Content.Value{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, font}

def text_height(wrapping: T.Wrapping, key: String, height: Nat) -> Model.Height:
  match wrapping:
    case T.SingleLine{}: Model.FixedHeight{height}
    case T.UnbrokenLine{}: Model.FixedHeight{height}
    case T.WrapAnywhere{}: Model.HeightAtWidth{key}
    case T.WrapWords{}: Model.HeightAtWidth{key}
    case T.ScrollableCode{}: Model.HeightAtWidth{key}
    case T.NormalAnywhere{}: Model.HeightAtWidth{key}
    case T.NormalWords{}: Model.HeightAtWidth{key}

def select_root(same: Bool, root: Content.NativeRoot, rest: +List<Content.NativeRoot>) -> +List<Content.NativeRoot>:
  match same:
    case True{}: root <> rest
    case False{}: rest

def owned_root(roots: +List<Content.NativeRoot>, +owner: String) -> +List<Content.NativeRoot>:
  match roots:
    case Nil{}: Nil{}
    case Con{+root, rest}:
      Content.NativeRoot{owner_key, target, tree, attributes, style} = root
      select_root(String.eq(owner_key, owner), root, owned_root(rest, owner))

def toolbar_minimum(roots: +List<Content.NativeRoot>) -> Enclosure.Extent:
  match roots:
    case Nil{}: Enclosure.Extent{0n, 0n}
    case Con{Content.NativeRoot{owner_key, Source.ToolbarTarget{identity}, tree, attributes, style}, rest}:
      Model.extent_max(Model.minimum_demand(Model.demand(~Content.Value, ~Doc.DOMEvent, tree)), toolbar_minimum(rest))
    case Con{Content.NativeRoot{owner_key, Source.CodeBodyTarget{identity, wrap}, tree, attributes, style}, rest}:
      toolbar_minimum(rest)
    case Con{Content.NativeRoot{owner_key, Source.InteractiveTarget{identity}, tree, attributes, style}, rest}:
      toolbar_minimum(rest)
    case Con{Content.NativeRoot{owner_key, Source.InteractiveSourceTarget{identity, exposed}, tree, attributes, style}, rest}:
      toolbar_minimum(rest)
    case Con{Content.NativeRoot{owner_key, Source.InteractiveFrameTarget{identity, active}, tree, attributes, style}, rest}:
      toolbar_minimum(rest)

def rich_minimum(node: Source.Node, +roots: +List<Content.NativeRoot>, +observed: Nat) -> Nat:
  match node:
    case Source.RichText{key, style, Source.RichContent{source, value,
      Source.RichPolicy{Source.CodeSurface{frame, chrome}, toolbar_height, block_gap, list_indent, code_text, wrap}}, attachments, native_owner}:
      Nat.max(observed, Nat.add(Enclosure.extent_width(toolbar_minimum(roots)), Nat.mul(2n, Enclosure.inline(Enclosure.frame_content(frame)))))
    case Source.Box{key, tag, style, attributes, children}: observed
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: observed
    case Source.Text{key, value, font, wrapping}: observed
    case Source.Glyph{key, drawing, style}: observed
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: observed
    case Source.NativeAttachment{key, target, attributes, style, children}: observed

def observation_minimum(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum_width, preferred_width, content_height, reference_advance} = observation
  minimum_width

def observation_preferred(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum_width, preferred_width, content_height, reference_advance} = observation
  preferred_width

def observation_height(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum_width, preferred_width, content_height, reference_advance} = observation
  content_height

def observation_advance(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum_width, preferred_width, content_height, reference_advance} = observation
  reference_advance

def text_natural_dimensions(wrapping: T.Wrapping, +minimum: Nat, +preferred: Nat, +height: Nat, advance: Nat) -> Space.Demand:
  match wrapping:
    case T.SingleLine{}:
      # The complete single-line value remains available through its native title.
      +visible_minimum: Nat = Nat.min(minimum, advance)
      Space.Demand{Enclosure.Extent{visible_minimum, height}, Enclosure.Extent{Nat.max(visible_minimum, preferred), height}}
    case T.UnbrokenLine{}:
      # A complete short caption contributes its full measured width to row selection.
      Space.Demand{Enclosure.Extent{preferred, height}, Enclosure.Extent{preferred, height}}
    case _: Space.Demand{Enclosure.Extent{minimum, height}, Enclosure.Extent{preferred, height}}

def text_natural_demand(wrapping: T.Wrapping, +observation: Content.Observation) -> Space.Demand:
  text_natural_dimensions(wrapping, observation_minimum(observation), observation_preferred(observation), observation_height(observation), observation_advance(observation))

def observed_leaf_resolved(+line_height: Nat, node: Source.Node, +key: String, +font: T.Presentation,
  +rule: Model.Rule, +observation: Content.Observation, +roots: +List<Content.NativeRoot>,
  +policies: +List<Content.NativePolicy>) -> PhysicalSource.Forest:
  match node:
    case Source.Text{+label, +value, +choice, +wrapping}:
      +demand = text_natural_demand(wrapping, observation)
      +height = observation_height(observation)
      +local = local_value(Source.Text{label, value, choice, wrapping}, font)
      PhysicalSource.ReadyForest{[Model.Leaf{key, local, Model.DisplayOnly{}, rule,
        demand,
        text_height(wrapping, key, height)}], roots, policies}
    case Source.Field{+label, +kind, +style, +attributes, +value, +placeholder, +options,
      Source.FieldPolicy{+columns, +lines, +maximum_lines}, +accessible_name, +enabled, +first_event, +remaining_events}:
      Content.Observation{generation, observed_key, purpose, minimum, preferred, measured, advance} = observation
      +policy: Source.FieldPolicy = Source.FieldPolicy{columns, lines, maximum_lines}
      +demand: Space.Demand = FieldDimensions.natural_demand(kind, policy, line_height, minimum, preferred, measured, advance)
      +height = Enclosure.extent_height(Model.minimum_demand(demand))
      +field: Source.Node = Source.Field{label, kind, style, attributes, value, placeholder, options,
        policy, accessible_name, enabled, first_event, remaining_events}
      PhysicalSource.ReadyForest{[Model.Leaf{key, local_value(field, font), Source.interaction_of(field), rule,
        demand, FieldDimensions.height(FieldDimensions.multiline(kind), key, height)}], roots, policies}
    case Source.RichText{+label, +style, +content, +attachments, +native_owner}:
      +minimum = observation_minimum(observation)
      +preferred = observation_preferred(observation)
      +height = observation_height(observation)
      +rich: Source.Node = Source.RichText{label, style, content, attachments, native_owner}
      +lower = rich_minimum(rich, owned_root(roots, key), minimum)
      PhysicalSource.ReadyForest{[Model.Leaf{key, local_value(rich, font), Model.DisplayOnly{}, rule,
        Space.Demand{Enclosure.Extent{lower, height}, Enclosure.Extent{Nat.max(lower, preferred), height}},
        Model.HeightAtWidth{key}}], roots, policies}
    case Source.Box{label, tag, style, attributes, children}: PhysicalSource.InvalidForest{Content.InvalidObservation{key}}
    case Source.Control{label, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: PhysicalSource.InvalidForest{Content.InvalidObservation{key}}
    case Source.Glyph{label, drawing, style}: PhysicalSource.InvalidForest{Content.InvalidObservation{key}}
    case Source.NativeAttachment{label, target, attributes, style, children}: PhysicalSource.InvalidForest{Content.InvalidObservation{key}}

def observed_leaf(node: Source.Node, +key: String, +font: T.Presentation,
  +rule: Model.Rule, +observation: Content.Observation, +roots: +List<Content.NativeRoot>,
  +policies: +List<Content.NativePolicy>) -> PhysicalSource.Forest:
  observed_leaf_resolved(T.resolved_line_height(T.resolved(font)), node, key, font, rule, observation, roots, policies)

def receipt(found: Maybe<&2, Content.Observation>, +request: Content.Request,
  +rule: Model.Rule, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) -> PhysicalSource.Forest:
  match found:
    case None{}: PhysicalSource.MissingForest{request, Nil{}}
    case Some{observation}:
      Content.Request{generation, key, Content.Value{node, font}, purpose, native_roots, native_policies} = request
      observed_leaf(node, key, font, rule, observation, roots, policies)

def target_key(target: Source.NativeTarget) -> String:
  match target:
    case Source.ToolbarTarget{identity}: Code.dom_key(identity) ++ "/toolbar"
    case Source.CodeBodyTarget{identity, wrap}: Code.dom_key(identity) ++ "/code"
    case Source.InteractiveTarget{identity}: Code.dom_key(identity) ++ "/ui"
    case Source.InteractiveSourceTarget{identity, exposed}: Code.dom_key(identity) ++ "/source"
    case Source.InteractiveFrameTarget{identity, active}: Code.dom_key(identity) ++ "/frame"

def root_slot(root: Content.NativeRoot) -> Content.NativeSlot:
  Content.NativeRoot{owner_key, target, tree, attributes, style} = root
  Content.NativeSlot{owner_key, target_key(target)}

def policy_slot(policy: Content.NativePolicy) -> Content.NativeSlot:
  Content.NativePolicy{owner_key, target, attributes, style} = policy
  Content.NativeSlot{owner_key, target_key(target)}

def native_slots(prepared: Content.Prepared) -> +List<Content.NativeSlot>:
  Content.Prepared{snapshot, tree, roots, policies} = prepared
  List.append(&2, Content.NativeSlot, Std.map(~Content.NativeRoot, ~Content.NativeSlot, ~root_slot, roots),
    Std.map(~Content.NativePolicy, ~Content.NativeSlot, ~policy_slot, policies))

def slot_member(slots: +List<Content.NativeSlot>, +owner: String, +target: String) -> Bool:
  match slots:
    case Nil{}: False{}
    case Con{Content.NativeSlot{slot_owner, slot_target}, rest}:
      (String.eq(slot_owner, owner) && String.eq(slot_target, target)) || slot_member(rest, owner, target)

def duplicate_member(found: Bool, slot: Content.NativeSlot, remaining: Maybe<&2, Content.NativeSlot>) -> Maybe<&2, Content.NativeSlot>:
  match found:
    case True{}: Some{slot}
    case False{}: remaining

def duplicate_native_slot(slots: +List<Content.NativeSlot>) -> Maybe<&2, Content.NativeSlot>:
  match slots:
    case Nil{}: None{}
    case Con{Content.NativeSlot{+owner, +target}, +rest}:
      duplicate_member(slot_member(rest, owner, target), Content.NativeSlot{owner, target}, duplicate_native_slot(rest))

def no_duplicate(duplicate: Maybe<&2, Content.NativeSlot>) -> Bool:
  match duplicate:
    case None{}: True{}
    case Some{slot}: False{}

def target_outcome(duplicate: Maybe<&2, Content.NativeSlot>, +prepared: Content.Prepared) -> Content.Preparation:
  match duplicate:
    case None{}: Content.Ready{prepared}
    case Some{Content.NativeSlot{owner, target}}:
      Content.Prepared{snapshot, tree, roots, policies} = prepared
      Content.Invalid{snapshot, Content.DuplicateNativeTarget{owner, target}}

def admitted_targets(+prepared: Content.Prepared) -> Content.Preparation:
  target_outcome(duplicate_native_slot(native_slots(prepared)), prepared)

def single_root(trees: +List<Model.Tree<Content.Value, Doc.DOMEvent>>, snapshot: Content.Snapshot,
  roots: +List<Content.NativeRoot>, policies: +List<Content.NativePolicy>) -> Content.Preparation:
  match trees:
    case Nil{}: Content.Invalid{snapshot, Content.InvalidNativeChild{"/0"}}
    case Con{tree, Nil{}}: admitted_targets(Content.Prepared{snapshot, tree, roots, policies})
    case Con{tree, Con{next, rest}}: Content.Invalid{snapshot, Content.InvalidNativeChild{"/0"}}

def preparation(result: PhysicalSource.Forest, +snapshot: Content.Snapshot) -> Content.Preparation:
  match result:
    case PhysicalSource.ReadyForest{trees, roots, policies}: single_root(trees, snapshot, roots, policies)
    case PhysicalSource.MissingForest{first, remaining}: Content.NeedsMeasurements{snapshot, first, remaining}
    case PhysicalSource.InvalidForest{error}: Content.Invalid{snapshot, error}
