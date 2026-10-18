import Base
import ./SOURCE.bend as SourceSource
import ./measurement-requirements.bend as Dimensions
import ../runtime/MODEL.bend as Browser
import ../runtime/SEMANTICS.bend as Legacy
import ./MODEL.bend as World
import ./CONTENT.bend as Content
import ./physical-content-measurement.bend as Measurements
import ./physical-native.bend as NativePhysical
import ../../interaction/conversation/CODE.bend as Code
import ./physical-plan.bend as Plan
import ./physical-space.bend as Physical
import ../document/MODEL.bend as Doc
import ../document/SOURCE.bend as Source
import ../controls/SHELL.bend as Shell
import ../appearance/TYPOGRAPHY.bend as T
import ./GEOMETRY.bend as Spatial
import ../focus/MODEL.bend as Focus
import ../runtime/native-fields.bend as Native
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/IDENTITY.bend as UIIdentity

def world_source(world: Content.AllocatedWorld) -> Source.Node:
  Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies} = world
  source

type Requirements is Type:
  Requirements{
    publication: @+world:Content.AllocatedWorld -> @capacity:View.Capacity -> @+legacy:Legacy.State -> @+semantic:SurfaceTypes.Surface ->
      {Browser.published(world, capacity, legacy, semantic) ==
        Browser.Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(legacy)),
          Native.basis([world_source(world)], semantic), None{}} : Browser.Published},
    awaiting: @generation:Nat -> @first:Plan.Job -> @remaining:+List<Plan.Job> -> @index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @state:Browser.State -> @semantic:SurfaceTypes.Surface -> @round:Nat ->
      {Browser.selected(Plan.Awaiting{generation, first, remaining}, index, capacity, engine, state, semantic, round) ==
        Browser.Stopped{Browser.Decision{Browser.set_lifecycle(state, Browser.Measuring{index, capacity, engine, semantic, round}), Nil{}}} : Browser.Search},
    remeasure: @+model_state:Browser.State ->  @+index:Nat ->
      @+capacity:View.Capacity -> @+engine:World.Engine -> @+semantic:SurfaceTypes.Surface -> @+round:Nat ->
      {Browser.remeasure(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
        Browser.Decision{Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state), Nil{}} : Browser.Decision}}

law evidence:
  Requirements

law rich_local_value_preserves_focus_owner:
  for key: UIIdentity.Key
  for style: Source.Style
  for content: Source.RichContent
  for attachments: +List<Source.Node>
  for native_owner: Maybe<&2, String>
  for font: T.Presentation
  {Content.local_value(Source.RichText{key, style, content, attachments, native_owner}, font) ==
    Content.Value{Source.RichText{key, style, content, Nil{}, native_owner}, font} : Content.Value}

# A measurement is accepted only under the independent complete request rule.
def receipt_request_claim(+request: Content.Request, +observation: Content.Observation) -> Type:
  {Measurements.observation_matches(request, observation) == Dimensions.observation_matches(request, observation) : Bool}

law receipt_uses_request_guard:
  for +request: Content.Request
  for +observation: Content.Observation
  receipt_request_claim(request, observation)

# The first fully admitted observation supplies every dimension and field.
def receipt_valid_observation(request: Content.Request, observation: Content.Observation) -> Bool:
  Dimensions.observation_matches(request, observation)

def required_receipt_pick(accepted: Bool, observation: Content.Observation,
  tail: Maybe<&2, Content.Observation>) -> Maybe<&2, Content.Observation>:
  match accepted:
    case True{}: Some{observation}
    case False{}: tail

def required_receipt(+request: Content.Request, observations: +List<Content.Observation>) -> Maybe<&2, Content.Observation>:
  match observations:
    case Nil{}: None{}
    case Con{+observation, rest}:
      required_receipt_pick(receipt_valid_observation(request, observation), observation, required_receipt(request, rest))

def receipt_selection_claim(+request: Content.Request, +observations: +List<Content.Observation>) -> Type:
  {Measurements.find(request, observations) == required_receipt(request, observations) : Maybe<&2, Content.Observation>}

law find_first_valid_receipt:
  for +request: Content.Request
  for +observations: +List<Content.Observation>
  receipt_selection_claim(request, observations)

law width_probe_dimensions:
  for generation: Nat
  for key: String
  for +node: Source.Node
  for font: T.Presentation
  for width: Nat
  for roots: +List<Content.NativeRoot>
  for policies: +List<Content.NativePolicy>
  for +height: Nat
  for +advance: Nat
  {Measurements.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, Content.AtWidth{width}, roots, policies}, height, advance) ==
    Dimensions.primitive_observation_valid(node, height, advance) : Bool}

law rootless_probe_dimensions:
  for generation: Nat
  for key: String
  for +node: Source.Node
  for font: T.Presentation
  for purpose: Content.Purpose
  for policies: +List<Content.NativePolicy>
  for +height: Nat
  for +advance: Nat
  {Measurements.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, purpose, Nil{}, policies}, height, advance) ==
    Dimensions.primitive_observation_valid(node, height, advance) : Bool}

def ordinary_probe(node: Source.Node) -> Bool:
  match node:
    case Source.RichText{key, style, content, attachments, native_owner}: False{}
    case Source.NativeAttachment{key, target, attributes, style, children}: True{}
    case Source.Box{key, tag, style, attributes, children}: True{}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: True{}
    case Source.Text{key, value, font, wrapping}: True{}
    case Source.Glyph{key, drawing, style}: True{}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: True{}

law ordinary_probe_dimensions:
  for generation: Nat
  for key: String
  for +node: Source.Node
  for font: T.Presentation
  for purpose: Content.Purpose
  for roots: +List<Content.NativeRoot>
  for policies: +List<Content.NativePolicy>
  for +height: Nat
  for +advance: Nat
  {ordinary_probe(node) == True{} : Bool} ->
  {Measurements.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, purpose, roots, policies}, height, advance) ==
    Dimensions.primitive_observation_valid(node, height, advance) : Bool}

# This independent ownership proposition quantifies an actual prepared root.
def target_interactive_owner(target: Source.NativeTarget, +source: Code.Source) -> Bool:
  match target:
    case Source.InteractiveTarget{identity}: Code.belongs(identity, source)
    case Source.ToolbarTarget{identity}: False{}
    case Source.CodeBodyTarget{identity, wrap}: False{}
    case Source.InteractiveSourceTarget{identity, exposed}: False{}
    case Source.InteractiveFrameTarget{identity, active}: False{}

def single_interactive_owner(root: Content.NativeRoot, +key: String, +source: Code.Source) -> Bool:
  Content.NativeRoot{owner_key, target, tree, attributes, style} = root
  String.eq(owner_key, key) && target_interactive_owner(target, source)

def rich_probe_request(generation: Nat, +key: String, font: T.Presentation, style: Source.Style,
  policy: Source.RichPolicy, source: Code.Source, value: String, purpose: Content.Purpose,
  root: Content.NativeRoot) -> Content.Request:
  Content.Request{generation, key,
    Content.Value{Source.RichText{UIIdentity.Place{key}, style, Source.RichContent{Some{source}, value, policy}, Nil{}, None{}}, font},
    purpose, root <> Nil{}, Nil{}}

law natural_owned_ui_zero_admissible:
  for generation: Nat
  for +key: String
  for font: T.Presentation
  for style: Source.Style
  for policy: Source.RichPolicy
  for +source: Code.Source
  for value: String
  for +root: Content.NativeRoot
  for advance: Nat
  {single_interactive_owner(root, key, source) == True{} : Bool} ->
  {Measurements.request_observation_valid(rich_probe_request(generation, key, font, style, policy, source, value, Content.Natural{}, root), 0n, advance) == True{} : Bool}

law foreign_ui_dimensions:
  for generation: Nat
  for +key: String
  for font: T.Presentation
  for style: Source.Style
  for policy: Source.RichPolicy
  for +source: Code.Source
  for +value: String
  for +root: Content.NativeRoot
  for +height: Nat
  for advance: Nat
  {single_interactive_owner(root, key, source) == False{} : Bool} ->
  {Measurements.request_observation_valid(rich_probe_request(generation, key, font, style, policy, source, value, Content.Natural{}, root), height, advance) ==
    Dimensions.content_height_valid(value, height) : Bool}

law foreign_root_owner_rejected:
  for +key: String
  for source: Code.Source
  for +owner_key: String
  for target: Source.NativeTarget
  for tree: Physical.Tree<Content.Value, Doc.DOMEvent>
  for attributes: +List<Source.Attribute>
  for style: Source.ResolvedStyle
  {String.eq(owner_key, key) == False{} : Bool} ->
  {single_interactive_owner(Content.NativeRoot{owner_key, target, tree, attributes, style}, key, source) == False{} : Bool}

law foreign_root_source_rejected:
  for key: String
  for +source: Code.Source
  for owner_key: String
  for +identity: Code.Identity
  for tree: Physical.Tree<Content.Value, Doc.DOMEvent>
  for attributes: +List<Source.Attribute>
  for style: Source.ResolvedStyle
  {Code.belongs(identity, source) == False{} : Bool} ->
  {single_interactive_owner(Content.NativeRoot{owner_key, Source.InteractiveTarget{identity}, tree, attributes, style}, key, source) == False{} : Bool}

# Native viewport selection returns the first complete matching observation.
# A target identifies its DOM slot; presentation flags do not name another slot.
# Selection preserves the complete observed bounds for subsequent allocation.
def required_viewport_purpose(first: Content.Purpose, second: Content.Purpose) -> Bool:
  match first second:
    case Content.Natural{} Content.Natural{}: True{}
    case Content.Natural{} Content.AtWidth{width}: False{}
    case Content.AtWidth{width} Content.Natural{}: False{}
    case Content.AtWidth{left} Content.AtWidth{right}: Nat.is_eq(left, right)

def required_viewport_matches(query: NativePhysical.Query, value: Content.NativeViewport) -> Bool:
  NativePhysical.Query{generation, owner, purpose, target} = query
  Content.NativeViewport{observed_generation, observed_owner, observed_purpose, observed_target, bounds} = value
  Nat.is_eq(generation, observed_generation) && String.eq(owner, observed_owner)
    && required_viewport_purpose(purpose, observed_purpose)
    && String.eq(Dimensions.target_key(target), Dimensions.target_key(observed_target))

def required_viewport_pick(matches: Bool, value: Content.NativeViewport, tail: Maybe<&2, Content.NativeViewport>) -> Maybe<&2, Content.NativeViewport>:
  match matches:
    case True{}: Some{value}
    case False{}: tail

def required_viewport(+query: NativePhysical.Query, values: +List<Content.NativeViewport>) -> Maybe<&2, Content.NativeViewport>:
  match values:
    case Nil{}: None{}
    case Con{+value, rest}: required_viewport_pick(required_viewport_matches(query, value), value, required_viewport(query, rest))

law viewport_matches_complete:
  for +query: NativePhysical.Query
  for +value: Content.NativeViewport
  {NativePhysical.viewport_matches(query, value) == required_viewport_matches(query, value) : Bool}

law viewport_complete:
  for +query: NativePhysical.Query
  for +values: +List<Content.NativeViewport>
  {NativePhysical.viewport(query, values) == required_viewport(query, values) : Maybe<&2, Content.NativeViewport>}

law viewport_empty:
  for query: NativePhysical.Query
  {NativePhysical.viewport(query, Nil{}) == None{} : Maybe<&2, Content.NativeViewport>}

law viewport_matching_head:
  for +query: NativePhysical.Query
  for +value: Content.NativeViewport
  for +rest: +List<Content.NativeViewport>
  for matches: {required_viewport_matches(query, value) == True{} : Bool}
  {NativePhysical.viewport(query, value <> rest) == Some{value} : Maybe<&2, Content.NativeViewport>}

law viewport_nonmatching_head:
  for +query: NativePhysical.Query
  for +value: Content.NativeViewport
  for +rest: +List<Content.NativeViewport>
  for rejected: {required_viewport_matches(query, value) == False{} : Bool}
  {NativePhysical.viewport(query, value <> rest) == NativePhysical.viewport(query, rest) : Maybe<&2, Content.NativeViewport>}

law viewport_first_duplicate:
  for +query: NativePhysical.Query
  for +first: Content.NativeViewport
  for +second: Content.NativeViewport
  for +rest: +List<Content.NativeViewport>
  for first_matches: {required_viewport_matches(query, first) == True{} : Bool}
  for second_matches: {required_viewport_matches(query, second) == True{} : Bool}
  {NativePhysical.viewport(query, first <> second <> rest) == Some{first} : Maybe<&2, Content.NativeViewport>}

law measured_receipt_complete:
  for +request: Content.Request
  for +rule: Physical.Rule
  for +roots: +List<Content.NativeRoot>
  for +policies: +List<Content.NativePolicy>
  for +observations: +List<Content.Observation>
  {SourceSource.measured(request, rule, roots, policies, observations) ==
    Dimensions.receipt(required_receipt(request, observations), request, rule, roots, policies) : SourceSource.Forest}

law preparation_receipt_complete:
  for +request: Content.Request
  for +rule: Physical.Rule
  for +roots: +List<Content.NativeRoot>
  for +policies: +List<Content.NativePolicy>
  for +observations: +List<Content.Observation>
  for +snapshot: Content.Snapshot
  {SourceSource.preparation(SourceSource.measured(request, rule, roots, policies, observations), snapshot) ==
    Dimensions.preparation(Dimensions.receipt(required_receipt(request, observations), request, rule, roots, policies), snapshot) : Content.Preparation}
