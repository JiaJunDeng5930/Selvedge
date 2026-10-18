import Base
import ../../bendlib/categories.bend as Categories
import ../document/SOURCE.bend as Source
import ./CONTENT.bend as Content
import ./field-dimensions.bend as FieldDimensions
import ./physical-content-measurement.bend as Measurements
import ./physical-space.bend as Model
import ./SPACE.bend as Space
import ./GEOMETRY.bend as Spatial
import ../appearance/TYPOGRAPHY.bend as T
import ./natural-size.bend as NaturalSize
import ./enclosure.bend as Enclosure
import ../../interaction/conversation/CODE.bend as Code
import ../document/MODEL.bend as Doc

type Context is Data:
  Ordinary{}
  RichSlots{owner_key: String, source: Maybe<&2, Code.Source>}

type Forest is Data:
  ReadyForest{trees: +List<Model.Tree<Content.Value, Doc.DOMEvent>>,
    native_roots: +List<Content.NativeRoot>, native_policies: +List<Content.NativePolicy>}
  MissingForest{first: Content.Request, remaining: +List<Content.Request>}
  InvalidForest{error: Content.Error}

type ForestPair is Data:
  ForestPair{first: Forest, second: Forest}

# Missing measurements retain preorder; any invalid subtree prevents preparation.

def merge_pair(pair: ForestPair) -> Forest:
  match pair:
    case ForestPair{InvalidForest{error}, second}: InvalidForest{error}
    case ForestPair{ReadyForest{trees, roots, policies}, InvalidForest{error}}: InvalidForest{error}
    case ForestPair{MissingForest{first, remaining}, InvalidForest{error}}: InvalidForest{error}
    case ForestPair{ReadyForest{first_trees, first_roots, first_policies}, ReadyForest{second_trees, second_roots, second_policies}}:
      ReadyForest{List.append(&2, Model.Tree<Content.Value, Doc.DOMEvent>, first_trees, second_trees),
        List.append(&2, Content.NativeRoot, first_roots, second_roots),
        List.append(&2, Content.NativePolicy, first_policies, second_policies)}
    case ForestPair{ReadyForest{trees, roots, policies}, MissingForest{first, remaining}}:
      MissingForest{first, remaining}
    case ForestPair{MissingForest{first, remaining}, ReadyForest{trees, roots, policies}}:
      MissingForest{first, remaining}
    case ForestPair{MissingForest{first, remaining}, MissingForest{second, second_remaining}}:
      MissingForest{first, List.append(&2, Content.Request, remaining, second <> second_remaining)}

def merge(first: Forest, second: Forest) -> Forest:
  merge_pair(ForestPair{first, second})

def resolved_font(style: Source.ResolvedStyle) -> T.Presentation:
  Source.ResolvedStyle{layout, font, chrome, states} = style
  font

def ordinary(context: Context, result: Forest, key: String) -> Forest:
  match context:
    case Ordinary{}: result
    case RichSlots{owner_key, source}: InvalidForest{Content.InvalidNativeChild{key}}

def text_rule() -> Model.Rule:
  Model.Rule{Model.Horizontal{}, Spatial.Leading{}, Spatial.Leading{},
    Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}, 0n,
    Model.NaturalSize{}, Model.NaturalSize{}, Enclosure.Extent{0n, 0n}, Model.Confined{}, Spatial.InFlow{}}

def text_height(wrapping: T.Wrapping, key: String, height: Nat) -> Model.Height:
  match wrapping:
    case T.SingleLine{}: Model.FixedHeight{height}
    case T.UnbrokenLine{}: Model.FixedHeight{height}
    case T.WrapAnywhere{}: Model.HeightAtWidth{key}
    case T.WrapWords{}: Model.HeightAtWidth{key}
    case T.ScrollableCode{}: Model.HeightAtWidth{key}
    case T.NormalAnywhere{}: Model.HeightAtWidth{key}
    case T.NormalWords{}: Model.HeightAtWidth{key}

def multiline(kind: Source.NativeFieldKind) -> Bool:
  FieldDimensions.multiline(kind)

def field_height(variable: Bool, key: String, height: Nat) -> Model.Height:
  FieldDimensions.height(variable, key, height)

def container(children: Forest, +key: String, +node: Source.Node, +style: Source.ResolvedStyle) -> Forest:
  match children:
    case ReadyForest{trees, roots, policies}:
      ReadyForest{[Model.Container{key, Content.local_value(node, resolved_font(style)),
        Source.interaction_of(node), Source.physical_rule(style), trees}], roots, policies}
    case MissingForest{first, remaining}: MissingForest{first, remaining}
    case InvalidForest{error}: InvalidForest{error}

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

def select_policy(same: Bool, policy: Content.NativePolicy, rest: +List<Content.NativePolicy>) -> +List<Content.NativePolicy>:
  match same:
    case True{}: policy <> rest
    case False{}: rest

def owned_policy(policies: +List<Content.NativePolicy>, +owner: String) -> +List<Content.NativePolicy>:
  match policies:
    case Nil{}: Nil{}
    case Con{+policy, rest}:
      Content.NativePolicy{owner_key, target, attributes, style} = policy
      select_policy(String.eq(owner_key, owner), policy, owned_policy(rest, owner))

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

def field_height_extent(variable: Bool, +line_floor: Nat, maximum_lines: Nat, line_height: Nat, +measured: Nat) -> Nat:
  FieldDimensions.height_extent(variable, line_floor, maximum_lines, line_height, measured)

def field_natural_height_at(capacity: Nat, variable: Bool, policy: Source.FieldPolicy, +font: T.Presentation, +measured: Nat) -> Nat:
  FieldDimensions.natural_height(variable, policy, T.resolved_line_height(T.resolve_presentation(capacity, font)), measured)

def field_natural_height(variable: Bool, policy: Source.FieldPolicy, +font: T.Presentation, +measured: Nat) -> Nat:
  field_natural_height_at(NaturalSize.limit(), variable, policy, font, measured)

# Native content remains part of the demand; multiline fields bound the viewport
# by the same line policy used when sampling their height at an allocated width.

def field_natural_demand_at(capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy,
  +font: T.Presentation, observation: Content.Observation) -> Space.Demand:
  Content.Observation{generation, key, purpose, minimum, preferred, measured, advance} = observation
  FieldDimensions.natural_demand(kind, policy, T.resolved_line_height(T.resolve_presentation(capacity, font)), minimum, preferred, measured, advance)

def field_natural_demand(+kind: Source.NativeFieldKind, +policy: Source.FieldPolicy,
  +font: T.Presentation, +observation: Content.Observation) -> Space.Demand:
  field_natural_demand_at(NaturalSize.limit(), kind, policy, font, observation)

def observed_leaf_resolved(+line_height: Nat, node: Source.Node, +key: String, +font: T.Presentation,
  +rule: Model.Rule, +observation: Content.Observation, +roots: +List<Content.NativeRoot>,
  +policies: +List<Content.NativePolicy>) -> Forest:
  match node:
    case Source.Text{+label, +value, +choice, +wrapping}:
      +demand = text_natural_demand(wrapping, observation)
      +height = observation_height(observation)
      +local = Content.local_value(Source.Text{label, value, choice, wrapping}, font)
      ReadyForest{[Model.Leaf{key, local, Model.DisplayOnly{}, rule,
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
      ReadyForest{[Model.Leaf{key, Content.local_value(field, font), Source.interaction_of(field), rule,
        demand, FieldDimensions.height(FieldDimensions.multiline(kind), key, height)}], roots, policies}
    case Source.RichText{+label, +style, +content, +attachments, +native_owner}:
      +minimum = observation_minimum(observation)
      +preferred = observation_preferred(observation)
      +height = observation_height(observation)
      +rich: Source.Node = Source.RichText{label, style, content, attachments, native_owner}
      +lower = rich_minimum(rich, owned_root(roots, key), minimum)
      ReadyForest{[Model.Leaf{key, Content.local_value(rich, font), Model.DisplayOnly{}, rule,
        Space.Demand{Enclosure.Extent{lower, height}, Enclosure.Extent{Nat.max(lower, preferred), height}},
        Model.HeightAtWidth{key}}], roots, policies}
    case Source.Box{label, tag, style, attributes, children}: InvalidForest{Content.InvalidObservation{key}}
    case Source.Control{label, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: InvalidForest{Content.InvalidObservation{key}}
    case Source.Glyph{label, drawing, style}: InvalidForest{Content.InvalidObservation{key}}
    case Source.NativeAttachment{label, target, attributes, style, children}: InvalidForest{Content.InvalidObservation{key}}

def observed_leaf_at(capacity: Nat, node: Source.Node, +key: String, +font: T.Presentation,
  +rule: Model.Rule, +observation: Content.Observation, +roots: +List<Content.NativeRoot>,
  +policies: +List<Content.NativePolicy>) -> Forest:
  observed_leaf_resolved(T.resolved_line_height(T.resolve_presentation(capacity, font)), node, key, font, rule, observation, roots, policies)

def observed_leaf(node: Source.Node, +key: String, +font: T.Presentation,
  +rule: Model.Rule, +observation: Content.Observation, +roots: +List<Content.NativeRoot>,
  +policies: +List<Content.NativePolicy>) -> Forest:
  observed_leaf_resolved(T.resolved_line_height(T.resolved(font)), node, key, font, rule, observation, roots, policies)

def receipt(found: Maybe<&2, Content.Observation>, +request: Content.Request,
  +rule: Model.Rule, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) -> Forest:
  match found:
    case None{}: MissingForest{request, Nil{}}
    case Some{observation}:
      Content.Request{generation, key, Content.Value{node, font}, purpose, native_roots, native_policies} = request
      observed_leaf(node, key, font, rule, observation, roots, policies)

def measured(+request: Content.Request, rule: Model.Rule, roots: +List<Content.NativeRoot>,
  policies: +List<Content.NativePolicy>, observations: +List<Content.Observation>) -> Forest:
  receipt(Measurements.find(request, observations), request, rule, roots, policies)

def text(empty: Bool, +node: Source.Node, +key: String, +font: T.Presentation,
  generation: Nat, observations: +List<Content.Observation>) -> Forest:
  match empty:
    case True{}:
      ReadyForest{[Model.Leaf{key, Content.local_value(node, font), Model.DisplayOnly{}, text_rule(),
        Space.fixed_demand(0n, 0n), Model.FixedHeight{0n}}], Nil{}, Nil{}}
    case False{}:
      measured(Content.Request{generation, key, Content.local_value(node, font), Content.Natural{}, Nil{}, Nil{}},
        text_rule(), Nil{}, Nil{}, observations)

def glyph_valid(node: Source.Node) -> Bool:
  match node:
    case Source.Glyph{key, Source.Drawing{view_box, paths, width, height, paint}, style}:
      Nat.is_le(1n, width) && Nat.is_le(1n, height) && Source.drawing_paint_valid(paint)
    case _: False{}

def glyph_category() -> Source.Node -> Type:
  Categories.holds(Source.Node, glyph_valid)

def glyph_success(member: Categories.Membership<Source.Node, glyph_category()>, +key: String,
  +style: Source.ResolvedStyle, +width: Nat, +height: Nat) -> Forest:
  Categories.Membership{node, evidence} = member
  ReadyForest{[Model.Leaf{key, Content.local_value(node, resolved_font(style)), Model.DisplayOnly{},
    Source.physical_rule(style), Space.fixed_demand(width, height), Model.FixedHeight{height}}], Nil{}, Nil{}}

def glyph_admitted(member: Maybe<&1, Categories.Membership<Source.Node, glyph_category()>>, +key: String,
  +style: Source.ResolvedStyle, +width: Nat, +height: Nat) -> Forest:
  match member:
    case Some{value}: glyph_success(value, key, style, width, height)
    case None{}: InvalidForest{Content.InvalidDrawing{key}}

def glyph_result(node: Source.Node, +key: String, +style: Source.ResolvedStyle,
  +width: Nat, +height: Nat) -> Forest:
  glyph_admitted(Categories.admit(Source.Node, glyph_valid, node), key, style, width, height)

def field_valid(node: Source.Node) -> Bool:
  match node:
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      Source.field_policy_valid(policy)
    case _: False{}

def field_category() -> Source.Node -> Type:
  Categories.holds(Source.Node, field_valid)

def field_measurement(kind: Source.NativeFieldKind, node: Source.Node, +key: String, +style: Source.ResolvedStyle,
  generation: Nat, observations: +List<Content.Observation>) -> Forest:
  measured(Content.Request{generation, key, Content.local_value(node, resolved_font(style)), Content.Natural{}, Nil{}, Nil{}},
    Source.native_field_rule(kind, style), Nil{}, Nil{}, observations)

def field_success(member: Categories.Membership<Source.Node, field_category()>, kind: Source.NativeFieldKind,
  +key: String, +style: Source.ResolvedStyle, generation: Nat, observations: +List<Content.Observation>) -> Forest:
  Categories.Membership{node, evidence} = member
  field_measurement(kind, node, key, style, generation, observations)

def field_admitted(member: Maybe<&1, Categories.Membership<Source.Node, field_category()>>, kind: Source.NativeFieldKind,
  +key: String, +style: Source.ResolvedStyle, generation: Nat, observations: +List<Content.Observation>) -> Forest:
  match member:
    case Some{value}: field_success(value, kind, key, style, generation, observations)
    case None{}: InvalidForest{Content.InvalidFieldPolicy{key}}

def field(kind: Source.NativeFieldKind, node: Source.Node, +key: String, +style: Source.ResolvedStyle,
  generation: Nat, observations: +List<Content.Observation>) -> Forest:
  field_admitted(Categories.admit(Source.Node, field_valid, node), kind, key, style, generation, observations)

def rich(attachments: Forest, +node: Source.Node, +key: String, +style: Source.ResolvedStyle,
  generation: Nat, observations: +List<Content.Observation>) -> Forest:
  match attachments:
    case ReadyForest{trees, +roots, +policies}:
      measured(Content.Request{generation, key, Content.local_value(node, resolved_font(style)), Content.Natural{},
        owned_root(roots, key), owned_policy(policies, key)}, Source.physical_rule(style), roots, policies, observations)
    case MissingForest{first, remaining}: MissingForest{first, remaining}
    case InvalidForest{error}: InvalidForest{error}

def identity_matches(identity: Code.Identity, expected: Code.Source) -> Bool:
  Code.Identity{+actual, +ordinal} = identity
  String.eq(Code.key(Code.Identity{expected, ordinal}), Code.key(Code.Identity{actual, ordinal}))

def owner_matches(source: Maybe<&2, Code.Source>, identity: Code.Identity) -> Bool:
  match source:
    case None{}: False{}
    case Some{expected}: identity_matches(identity, expected)

def owner_category(+source: Maybe<&2, Code.Source>) -> Code.Identity -> Type:
  Categories.holds(Code.Identity, identity => owner_matches(source, identity))

def toolbar(children: Forest, +owner: String, +key: String, +node: Source.Node,
  target: Source.NativeTarget, attributes: +List<Source.Attribute>, +style: Source.ResolvedStyle) -> Forest:
  match children:
    case ReadyForest{trees, roots, policies}:
      +tree: Model.Tree<Content.Value, Doc.DOMEvent> = Model.Container{key, Content.local_value(node, resolved_font(style)), Model.DisplayOnly{}, Source.physical_rule(style), trees}
      ReadyForest{Nil{}, Content.NativeRoot{owner, target, tree, attributes, style} <> roots, policies}
    case MissingForest{first, remaining}: MissingForest{first, remaining}
    case InvalidForest{error}: InvalidForest{error}

def attachment_success(-source: Maybe<&2, Code.Source>, member: Categories.Membership<Code.Identity, owner_category(source)>,
  children: Forest, +owner: String, +key: String, +node: Source.Node,
  attributes: +List<Source.Attribute>, +style: Source.ResolvedStyle) -> Forest:
  Categories.Membership{identity, evidence} = member
  toolbar(children, owner, key, node, Source.ToolbarTarget{identity}, attributes, style)

def attachment_valid(-source: Maybe<&2, Code.Source>, member: Maybe<&1, Categories.Membership<Code.Identity, owner_category(source)>>,
  children: Forest, +owner: String, +key: String, +node: Source.Node,
  attributes: +List<Source.Attribute>, +style: Source.ResolvedStyle) -> Forest:
  match member:
    case Some{value}: attachment_success(source, value, children, owner, key, node, attributes, style)
    case None{}: InvalidForest{Content.InvalidNativeOwner{key}}

def native_toolbar(context: Context, children: Forest, +key: String, node: Source.Node,
  +identity: Code.Identity, attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  match context:
    case Ordinary{}: InvalidForest{Content.InvalidNativeOwner{key}}
    case RichSlots{+owner_key, source}:
      attachment_valid(source, Categories.admit(Code.Identity, identity => owner_matches(source, identity), identity),
        children, owner_key, key, node, attributes, style)

def interactive_region_admitted(accepted: Bool, children: Forest, owner: String, +key: String,
  node: Source.Node, target: Source.NativeTarget, attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  match accepted:
    case True{}: toolbar(children, owner, key, node, target, attributes, style)
    case False{}: InvalidForest{Content.InvalidNativeOwner{key}}

def native_interactive(context: Context, children: Forest, +key: String, node: Source.Node,
  +identity: Code.Identity, target: Source.NativeTarget, attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  match context:
    case Ordinary{}: InvalidForest{Content.InvalidNativeOwner{key}}
    case RichSlots{owner, source}: interactive_region_admitted(owner_matches(source, identity), children, owner, key, node, target, attributes, style)

def interactive_policy_admitted(accepted: Bool, children: +List<Source.Node>, owner: String, +key: String,
  target: Source.NativeTarget, attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  match accepted children:
    case True{} Nil{}: ReadyForest{Nil{}, Nil{}, [Content.NativePolicy{owner, target, attributes, style}]}
    case _ _: InvalidForest{Content.InvalidNativeOwner{key}}

def native_interactive_policy(context: Context, children: +List<Source.Node>, +key: String,
  +identity: Code.Identity, target: Source.NativeTarget, attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  match context:
    case Ordinary{}: InvalidForest{Content.InvalidNativeOwner{key}}
    case RichSlots{owner, source}: interactive_policy_admitted(owner_matches(source, identity), children, owner, key, target, attributes, style)

def native_code_category() -> Source.ResolvedStyle -> Type:
  Categories.holds(Source.ResolvedStyle, Source.native_code_policy_valid)

def native_code_success(member: Categories.Membership<Source.ResolvedStyle, native_code_category()>, owner: String,
  target: Source.NativeTarget, attributes: +List<Source.Attribute>) -> Forest:
  Categories.Membership{style, evidence} = member
  ReadyForest{Nil{}, Nil{}, [Content.NativePolicy{owner, target, attributes, style}]}

def native_code_admitted(member: Maybe<&1, Categories.Membership<Source.ResolvedStyle, native_code_category()>>, owner: String,
  +key: String, target: Source.NativeTarget, attributes: +List<Source.Attribute>) -> Forest:
  match member:
    case Some{value}: native_code_success(value, owner, target, attributes)
    case None{}: InvalidForest{Content.InvalidNativeChild{key}}

def native_code_policy(owner: String, +key: String,
  target: Source.NativeTarget, attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  native_code_admitted(Categories.admit(Source.ResolvedStyle, Source.native_code_policy_valid, style), owner, key, target, attributes)

def code_body_children(children: +List<Source.Node>, owner: String, +key: String,
  target: Source.NativeTarget, attributes: +List<Source.Attribute>, +style: Source.ResolvedStyle) -> Forest:
  match children:
    case Nil{}: native_code_policy(owner, key, target, attributes, style)
    case Con{first, rest}: InvalidForest{Content.InvalidNativeContentChildren{key}}

def owned_code_success(-source: Maybe<&2, Code.Source>, member: Categories.Membership<Code.Identity, owner_category(source)>,
  children: +List<Source.Node>, owner: String, +key: String, wrap: Bool,
  attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  Categories.Membership{identity, evidence} = member
  code_body_children(children, owner, key, Source.CodeBodyTarget{identity, wrap}, attributes, style)

def owned_code_body(-source: Maybe<&2, Code.Source>, member: Maybe<&1, Categories.Membership<Code.Identity, owner_category(source)>>,
  children: +List<Source.Node>, owner: String, +key: String, wrap: Bool,
  attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  match member:
    case Some{value}: owned_code_success(source, value, children, owner, key, wrap, attributes, style)
    case None{}: InvalidForest{Content.InvalidNativeOwner{key}}

def native_code_body(context: Context, children: +List<Source.Node>, +key: String,
  +identity: Code.Identity, wrap: Bool, attributes: +List<Source.Attribute>, style: Source.ResolvedStyle) -> Forest:
  match context:
    case Ordinary{}: InvalidForest{Content.InvalidNativeOwner{key}}
    case RichSlots{owner_key, source}:
      owned_code_body(source, Categories.admit(Code.Identity, identity => owner_matches(source, identity), identity),
        children, owner_key, key, wrap, attributes, style)

# This list-first recursion visits the authored tree and every owned native region.
# Helpers consume completed recursive results and never traverse source indirectly.

def prepare_forest(nodes: +List<Source.Node>, +parent_font: T.Presentation, +generation: Nat,
  +prefix: String, +index: Nat, +context: Context, +observations: +List<Content.Observation>) -> Forest:
  match nodes:
    case Nil{}: ReadyForest{Nil{}, Nil{}, Nil{}}
    case Con{Source.Box{+key, +tag, +style, +attributes, +children}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +node: Source.Node = Source.Box{key, tag, style, attributes, children}
      +resolved = Source.resolve_style(style, parent_font)
      merge(ordinary(context, container(prepare_forest(children, resolved_font(resolved), generation, path, 0n, Ordinary{}, observations), path, node, resolved), path),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.Control{+key, +tag, +style, +attributes, +accessible_name, +enabled, +first_event, +remaining_events, +children}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +node: Source.Node = Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}
      +resolved = Source.resolve_style(style, parent_font)
      merge(ordinary(context, container(prepare_forest(children, resolved_font(resolved), generation, path, 0n, Ordinary{}, observations), path, node, resolved), path),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.Text{+key, +value, +choice, +wrapping}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +node: Source.Node = Source.Text{key, value, choice, wrapping}
      merge(ordinary(context, text(String.eq(value, ""), node, path, Source.resolve_font(choice, parent_font), generation, observations), path),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.Glyph{+key, Source.Drawing{+view_box, +paths, +width, +height, +paint}, +style}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +node: Source.Node = Source.Glyph{key, Source.Drawing{view_box, paths, width, height, paint}, style}
      +resolved = Source.resolve_style(style, parent_font)
      merge(ordinary(context, glyph_result(node, path, resolved, width, height), path),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.Field{+key, +kind, +style, +attributes, +value, +placeholder, +options, +policy, +accessible_name, +enabled, +first_event, +remaining_events}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +node: Source.Node = Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}
      +resolved = Source.resolve_style(style, parent_font)
      merge(ordinary(context, field(kind, node, path, resolved, generation, observations), path),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.RichText{+key, +style, Source.RichContent{+source, +value, +policy}, +attachments, +native_owner}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +node: Source.Node = Source.RichText{key, style, Source.RichContent{source, value, policy}, attachments, native_owner}
      +resolved = Source.resolve_style(style, parent_font)
      merge(ordinary(context, rich(prepare_forest(attachments, resolved_font(resolved), generation, path, 0n, RichSlots{path, source}, observations), node, path, resolved, generation, observations), path),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.NativeAttachment{+key, Source.ToolbarTarget{+identity}, +attributes, +style, +children}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +resolved = Source.resolve_style(style, parent_font)
      +node: Source.Node = Source.NativeAttachment{key, Source.ToolbarTarget{identity}, attributes, style, children}
      merge(native_toolbar(context,
        prepare_forest(children, resolved_font(resolved), generation, path, 0n, Ordinary{}, observations),
        path, node, identity, attributes, resolved),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.NativeAttachment{+key, Source.CodeBodyTarget{+identity, +wrap}, +attributes, +style, +children}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +resolved = Source.resolve_style(style, parent_font)
      merge(native_code_body(context, children, path, identity, wrap, attributes, resolved),
        prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.NativeAttachment{+key, Source.InteractiveTarget{+identity}, +attributes, +style, +children}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      +resolved = Source.resolve_style(style, parent_font)
      +node: Source.Node = Source.NativeAttachment{key, Source.InteractiveTarget{identity}, attributes, style, children}
      merge(native_interactive(context, prepare_forest(children, resolved_font(resolved), generation, path, 0n, Ordinary{}, observations), path, node, identity, Source.InteractiveTarget{identity}, attributes, resolved), prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.NativeAttachment{+key, Source.InteractiveSourceTarget{+identity, +exposed}, +attributes, +style, +children}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      merge(native_interactive_policy(context, children, path, identity, Source.InteractiveSourceTarget{identity, exposed}, attributes, Source.resolve_style(style, parent_font)), prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))
    case Con{Source.NativeAttachment{+key, Source.InteractiveFrameTarget{+identity, +active}, +attributes, +style, +children}, +rest}:
      +path = prefix ++ "/" ++ Nat.show(index)
      merge(native_interactive_policy(context, children, path, identity, Source.InteractiveFrameTarget{identity, active}, attributes, Source.resolve_style(style, parent_font)), prepare_forest(rest, parent_font, generation, prefix, 1n+index, context, observations))

# Native targets are admitted together before any prepared forest leaves this boundary.

def native_targets_category() -> Content.Prepared -> Type:
  Categories.holds(Content.Prepared, Measurements.native_targets_valid)

def native_targets_success(member: Categories.Membership<Content.Prepared, native_targets_category()>) -> Content.Preparation:
  Categories.Membership{prepared, evidence} = member
  Content.Ready{prepared}

def reject_duplicate(duplicate: Maybe<&2, Content.NativeSlot>, +prepared: Content.Prepared) -> Content.Preparation:
  match duplicate:
    case None{}:
      Content.Prepared{snapshot, tree, roots, policies} = prepared
      Content.Invalid{snapshot, Content.InvalidNativeChild{"/0"}}
    case Some{Content.NativeSlot{owner_key, target_key}}:
      Content.Prepared{snapshot, tree, roots, policies} = prepared
      Content.Invalid{snapshot, Content.DuplicateNativeTarget{owner_key, target_key}}

def native_targets_admitted(member: Maybe<&1, Categories.Membership<Content.Prepared, native_targets_category()>>,
  +prepared: Content.Prepared) -> Content.Preparation:
  match member:
    case Some{value}: native_targets_success(value)
    case None{}: reject_duplicate(Content.duplicate_native_slot(Content.native_slots(prepared)), prepared)

def admit_native_targets(+prepared: Content.Prepared) -> Content.Preparation:
  native_targets_admitted(Categories.admit(Content.Prepared, Measurements.native_targets_valid, prepared), prepared)

def single_root(trees: +List<Model.Tree<Content.Value, Doc.DOMEvent>>, snapshot: Content.Snapshot,
  roots: +List<Content.NativeRoot>, policies: +List<Content.NativePolicy>) -> Content.Preparation:
  match trees:
    case Nil{}: Content.Invalid{snapshot, Content.InvalidNativeChild{"/0"}}
    case Con{tree, Nil{}}: admit_native_targets(Content.Prepared{snapshot, tree, roots, policies})
    case Con{tree, Con{next, rest}}: Content.Invalid{snapshot, Content.InvalidNativeChild{"/0"}}

def preparation(result: Forest, +snapshot: Content.Snapshot) -> Content.Preparation:
  match result:
    case ReadyForest{trees, roots, policies}: single_root(trees, snapshot, roots, policies)
    case MissingForest{first, remaining}: Content.NeedsMeasurements{snapshot, first, remaining}
    case InvalidForest{error}: Content.Invalid{snapshot, error}

def prepare(+snapshot: Content.Snapshot, observations: +List<Content.Observation>) -> Content.Preparation:
  Content.Snapshot{generation, source, default_font} = snapshot
  preparation(prepare_forest(source <> Nil{}, default_font, generation, "", 0n, Ordinary{}, observations), snapshot)

def height_request(node: Source.Node, +key: String, +font: T.Presentation, +generation: Nat,
  +width: Nat, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) -> Content.Request:
  match node:
    case Source.RichText{label, style, content, attachments, native_owner}:
      Content.Request{generation, key, Content.local_value(Source.RichText{label, style, content, attachments, native_owner}, font),
        Content.AtWidth{width}, owned_root(roots, key), owned_policy(policies, key)}
    case Source.Text{label, value, choice, wrapping}:
      Content.Request{generation, key, Content.local_value(Source.Text{label, value, choice, wrapping}, font), Content.AtWidth{width}, Nil{}, Nil{}}
    case Source.Field{label, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      Content.Request{generation, key, Content.local_value(Source.Field{label, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, font), Content.AtWidth{width}, Nil{}, Nil{}}
    case Source.Box{label, tag, style, attributes, children}:
      Content.Request{generation, key, Content.local_value(Source.Box{label, tag, style, attributes, children}, font), Content.AtWidth{width}, Nil{}, Nil{}}
    case Source.Control{label, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}:
      Content.Request{generation, key, Content.local_value(Source.Control{label, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}, font), Content.AtWidth{width}, Nil{}, Nil{}}
    case Source.Glyph{label, drawing, style}:
      Content.Request{generation, key, Content.local_value(Source.Glyph{label, drawing, style}, font), Content.AtWidth{width}, Nil{}, Nil{}}
    case Source.NativeAttachment{label, target, attributes, style, children}:
      Content.Request{generation, key, Content.local_value(Source.NativeAttachment{label, target, attributes, style, children}, font), Content.AtWidth{width}, Nil{}, Nil{}}

def collect_height_requests(requests: +List<Model.HeightRequest<Content.Value>>, +generation: Nat,
  +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) -> +List<Content.Request>:
  match requests:
    case Nil{}: Nil{}
    case Con{Model.HeightRequest{key, Content.Value{node, font}, width}, rest}:
      height_request(node, key, font, generation, width, roots, policies)
        <> collect_height_requests(rest, generation, roots, policies)

def height_requests(prepared: Content.Prepared, requests: +List<Model.HeightRequest<Content.Value>>) -> +List<Content.Request>:
  Content.Prepared{Content.Snapshot{generation, source, default_font}, tree, roots, policies} = prepared
  collect_height_requests(requests, generation, roots, policies)

def viewport_height(policy: Source.FieldPolicy, measured: Nat, font: T.Presentation) -> Nat:
  Source.FieldPolicy{minimum_columns, minimum_lines, maximum_lines} = policy
  +line_height = T.resolved_line_height(T.resolved(font))
  Nat.max(Nat.mul(minimum_lines, line_height), Nat.min(Nat.mul(maximum_lines, line_height), measured))

def capped_height(variable: Bool, measured: Nat, policy: Source.FieldPolicy, font: T.Presentation) -> Nat:
  match variable:
    case True{}: viewport_height(policy, measured, font)
    case False{}: measured

def sample_height(node: Source.Node, +font: T.Presentation, +measured: Nat) -> Nat:
  match node:
    case Source.Field{label, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      capped_height(multiline(kind), measured, policy, font)
    case Source.Box{label, tag, style, attributes, children}: measured
    case Source.Control{label, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: measured
    case Source.Text{label, value, choice, wrapping}: measured
    case Source.Glyph{label, drawing, style}: measured
    case Source.RichText{label, style, content, attachments, native_owner}: measured
    case Source.NativeAttachment{label, target, attributes, style, children}: measured

def sample_request(request: Content.Request, width: Nat, measured: Nat) -> +List<Model.HeightSample>:
  Content.Request{generation, key, Content.Value{node, font}, purpose, roots, policies} = request
  [Model.HeightSample{key, width, sample_height(node, font, measured)}]

def sampled(found: Maybe<&2, Content.Observation>, request: Content.Request) -> +List<Model.HeightSample>:
  match found:
    case None{}: Nil{}
    case Some{Content.Observation{observed_generation, observed_key, Content.Natural{}, minimum, preferred, height, advance}}: Nil{}
    case Some{Content.Observation{observed_generation, observed_key, Content.AtWidth{width}, minimum, preferred, height, advance}}:
      sample_request(request, width, height)

def height_samples(requests: +List<Content.Request>, +observations: +List<Content.Observation>) -> +List<Model.HeightSample>:
  match requests:
    case Nil{}: Nil{}
    case Con{+request, rest}:
      List.append(&2, Model.HeightSample, sampled(Measurements.find(request, observations), request), height_samples(rest, observations))
