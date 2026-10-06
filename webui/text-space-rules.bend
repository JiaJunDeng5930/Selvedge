import Base
import ../core/ui-identity.bend as UIIdentity
import ./physical-source.bend as PhysicalSource
import ./physical-renderer.bend as Renderer
import ./physical-content.bend as Content
import ./physical-space.bend as Model
import ./source.bend as Source
import ./typography.bend as T
import ./space.bend as Space
import ./enclosure.bend as Enclosure
import ./spatial.bend as Spatial
import ./document.bend as Doc
import ./paint.bend as Paint

def minimum_width(demand: Space.Demand) -> Nat:
  Space.Demand{Enclosure.Extent{width, height}, preferred} = demand
  width

def preferred_width(demand: Space.Demand) -> Nat:
  Space.Demand{minimum, Enclosure.Extent{width, height}} = demand
  width

def demand_claim_parameters(+wrapping: T.Wrapping, +observation: Content.Observation, +minimum: Nat, preferred: Nat, +height: Nat) -> Type:
  match wrapping:
    case T.SingleLine{}:
      +visible: Nat = Nat.min(minimum, PhysicalSource.observation_advance(observation))
      {PhysicalSource.text_natural_demand(wrapping, observation) ==
        Space.Demand{Enclosure.Extent{visible, height}, Enclosure.Extent{Nat.max(visible, preferred), height}} : Space.Demand}
    case _:
      {PhysicalSource.text_natural_demand(wrapping, observation) ==
        Space.Demand{Enclosure.Extent{minimum, height}, Enclosure.Extent{preferred, height}} : Space.Demand}

def demand_claim(+wrapping: T.Wrapping, +observation: Content.Observation) -> Type:
  demand_claim_parameters(wrapping, observation, PhysicalSource.observation_minimum(observation), PhysicalSource.observation_preferred(observation), PhysicalSource.observation_height(observation))

def source_claim(label: UIIdentity.Key, text: String, choice: Source.FontChoice, +wrapping: T.Wrapping,
  key: String, font: T.Presentation, rule: Model.Rule, +observation: Content.Observation,
  roots: +List<Content.NativeRoot>, policies: +List<Content.NativePolicy>) -> Type:
  {PhysicalSource.observed_leaf(Source.Text{label, text, choice, wrapping}, key, font, rule, observation, roots, policies) ==
    PhysicalSource.ReadyForest{[Model.Leaf{key, Content.local_value(Source.Text{label, text, choice, wrapping}, font), Model.DisplayOnly{}, rule,
      PhysicalSource.text_natural_demand(wrapping, observation), PhysicalSource.text_height(wrapping, key, PhysicalSource.observation_height(observation))}], roots, policies} : PhysicalSource.Forest}

def render_claim(+capacity: Nat, +key: UIIdentity.Key, +text: String, choice: Source.FontChoice, font: T.Presentation,
  bounds: Spatial.Box, canvas: Enclosure.Extent, rule: Model.Rule, interaction: Model.Interaction<Doc.Event>,
  styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) -> Type:
  +value : Content.Value = Content.Value{Source.Text{key, text, choice, T.SingleLine{}}, font}
  {Renderer.leaf_at(capacity, value, UIIdentity.encode(key), bounds, canvas, rule, interaction, styles, owned) ==
    Doc.Element{UIIdentity.encode(key), "span", [Doc.Property{"title", text}],
      Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, value), [Paint.property("text-overflow", "ellipsis")])),
      Nil{}, [Doc.Text{text}]} : Doc.Node}

def attributes_claim(+wrapping: T.Wrapping, +text: String) -> Type:
  match wrapping:
    case T.SingleLine{}: {Renderer.text_attributes(wrapping, text) == [Doc.Property{"title", text}] : +List<Doc.Property>}
    case _: {Renderer.text_attributes(wrapping, text) == Nil{} : +List<Doc.Property>}

type Requirements is Type:
  Requirements{
    measured_minimum_bound: @+observation:Content.Observation ->
      {Nat.is_le(minimum_width(PhysicalSource.text_natural_demand(T.SingleLine{}, observation)), PhysicalSource.observation_advance(observation)) == True{} : Bool},
    natural_preferred_bound: @+observation:Content.Observation ->
      {Nat.is_le(PhysicalSource.observation_preferred(observation), preferred_width(PhysicalSource.text_natural_demand(T.SingleLine{}, observation))) == True{} : Bool},
    demand_policy: @+wrapping:T.Wrapping -> @+observation:Content.Observation -> demand_claim(wrapping, observation),
    production_source: @label:UIIdentity.Key -> @text:String -> @choice:Source.FontChoice -> @+wrapping:T.Wrapping ->
      @key:String -> @font:T.Presentation -> @rule:Model.Rule -> @+observation:Content.Observation ->
      @roots:+List<Content.NativeRoot> -> @policies:+List<Content.NativePolicy> -> source_claim(label, text, choice, wrapping, key, font, rule, observation, roots, policies),
    complete_render: @+capacity:Nat -> @+key:UIIdentity.Key -> @+text:String -> @choice:Source.FontChoice -> @font:T.Presentation ->
      @bounds:Spatial.Box -> @canvas:Enclosure.Extent -> @rule:Model.Rule -> @interaction:Model.Interaction<Doc.Event> ->
      @styles:+List<Doc.Property> -> @owned:+List<Renderer.Owned> -> render_claim(capacity, key, text, choice, font, bounds, canvas, rule, interaction, styles, owned),
    attributes_policy: @+wrapping:T.Wrapping -> @+text:String -> attributes_claim(wrapping, text)}

law evidence:
  Requirements
