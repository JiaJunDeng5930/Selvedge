import Base
import ./authored.bend as Authored
import ./design.bend as Design
import ../core/interface.bend as Interface
import ../core/ui-identity.bend as Identity
import ../core/live-output.bend as Live
import ./code-observation.bend as Observation
import ./physical-browser.bend as Browser
import ./physical-content.bend as Content
import ./browser.bend as Legacy
import ./MODEL.bend as Web
import ./platform.bend as Platform
import ./source.bend as Source
import ../UI.bend as Product
import ../core/SYSTEM.bend as Core
import ../core/user-experience.bend as E
import ../core/code-block.bend as Code
def published_display_claim(displayed: Maybe<&2, Browser.Published>, +generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Type:
  match displayed:
    case None{}: {Browser.code_batch_qualified(generation, observations, state) == False{} : Bool}
    case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
      {Browser.code_batch_qualified(generation, observations, state) ==
        Browser.code_batch_owned(observations, source) : Bool}


def published_qualification_claim(+generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Type:
  published_display_claim(Browser.displayed(state), generation, observations, state)

law published_qualification:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  published_qualification_claim(generation, observations, state)
law rejected_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for rejected: {Browser.code_batch_qualified(generation, observations, state) == False{} : Bool}
  {Browser.code_sources(generation, observations, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
law qualified_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for qualified: {Browser.code_batch_qualified(generation, observations, state) == True{} : Bool}
  {Browser.code_sources(generation, observations, state) ==
    Browser.accept(True{}, Browser.code_sources_fold(observations, Legacy.Decision{Browser.legacy(state), Nil{}}), state) : Browser.Decision}
law empty_batch:
  for +generation: Nat
  for +state: Browser.State
  {Browser.code_sources(generation, Nil{}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

# NOTE: Rejection concerns the published source version, independently of tracing generation.
law stale_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for stale: {actual_membership(observations, state) == False{} : Bool}
  {Browser.code_sources(generation, observations, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
law unowned_entry:
  for +identity: Code.Identity
  for +text: String
  for +source_value: String
  for +rest: +List<Observation.Observation>
  for +source: Source.Node
  for unowned: {Browser.code_source_owned(source, identity, source_value) == False{} : Bool}
  {Browser.code_batch_owned(Con{Observation.Observation{identity, text, source_value}, rest}, source) == False{} : Bool}
law unowned_tail:
  for +observation: Observation.Observation
  for +rest: +List<Observation.Observation>
  for +source: Source.Node
  for invalid: {Browser.code_observations_owned(rest, source) == False{} : Bool}
  {Browser.code_batch_owned(Con{observation, rest}, source) == False{} : Bool}
law fold_empty:
  for decision: Legacy.Decision
  {Browser.code_sources_fold(Nil{}, decision) == decision : Legacy.Decision}
law fold_order:
  for source: Code.Source
  for ordinal: Nat
  for text: String
  for source_value: String
  for rest: +List<Observation.Observation>
  for state: Legacy.State
  for effects: +List<Legacy.Effect>
  {Browser.code_sources_fold(Con{Observation.Observation{Code.Identity{source, ordinal}, text, source_value}, rest}, Legacy.Decision{state, effects}) ==
    Browser.code_sources_fold(rest, Legacy.append_decision(effects, Legacy.code_source(source, ordinal, text, state))) : Legacy.Decision}
law native_batch:
  for generation: Nat
  for observations: +List<Observation.Observation>
  for state: Browser.State
  {Browser.step(Legacy.Native{Web.CodeSourcesObserved{generation, observations}}, state) == Browser.code_sources(generation, observations, state) : Browser.Decision}
law raw_source_rejected:
  for identity: Code.Identity
  for text: String
  for state: Browser.State
  {Browser.step(Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.CodeSource{identity, text}}}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
law raw_content_rejected:
  for identity: Code.Identity
  for text: String
  for state: Browser.State
  {Browser.step(Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{Core.ApplicationInput{E.ContentInput{identity, Code.SourceChanged{text}}}}}}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
law direct_web_rejected:
  for generation: Nat
  for observations: +List<Observation.Observation>
  for +state: Web.State
  direct_web_claim(generation, observations, state)
def direct_web_claim(+generation: Nat, +observations: +List<Observation.Observation>, +state: Web.State) -> Type:
  +application = Web.application(state)
  +serial = Web.generation(state)
  +realization = Web.realization(state)
  +environment = Web.environment(state)
  +font = Web.typography(state)
  {Web.step(Web.CodeSourcesObserved{generation, observations}, state) == Web.idle(application, serial, realization, environment, font) : Web.Decision}

def missing_publication_claim(+generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Type:
  {Browser.code_sources(generation, observations, Browser.with_displayed(None{}, state)) ==
    Browser.Decision{Browser.with_displayed(None{}, state), Nil{}} : Browser.Decision}

law missing_publication:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  missing_publication_claim(generation, observations, state)
law all_entries:
  for identity: Code.Identity
  for text: String
  for source_value: String
  for rest: +List<Observation.Observation>
  for source: Source.Node
  {Browser.code_batch_owned(Con{Observation.Observation{identity, text, source_value}, rest}, source) ==
    (Browser.code_source_owned(source, identity, source_value) && Browser.code_observations_owned(rest, source)) : Bool}
law declared_content:
  for +owner: Code.Source
  for +identity: Code.Identity
  for +value: String
  for +source_value: String
  for policy: Source.RichPolicy
  {Browser.code_content_owned(Source.RichContent{Some{owner}, value, policy}, identity, source_value) ==
    declared_content_claim(owner, identity, value, source_value) : Bool}
def declared_content_claim(owner: Code.Source, identity: Code.Identity, value: String, source_value: String) -> Bool:
  Code.Identity{source, ordinal} = identity
  Browser.code_same_source(owner, source) && String.eq(value, source_value)

law undeclared_content:
  for +identity: Code.Identity
  for +value: String
  for +source_value: String
  for policy: Source.RichPolicy
  {Browser.code_content_owned(Source.RichContent{None{}, value, policy}, identity, source_value) == False{} : Bool}
law generation_independent:
  for +first: Nat
  for +second: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  {Browser.code_batch_qualified(first, observations, state) ==
    Browser.code_batch_qualified(second, observations, state) : Bool}
def published_membership(displayed: Maybe<&2, Browser.Published>, observations: +List<Observation.Observation>) -> Bool:
  match displayed:
    case None{}: False{}
    case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
      Browser.code_batch_owned(observations, source)

def actual_membership(observations: +List<Observation.Observation>, +state: Browser.State) -> Bool:
  published_membership(Browser.displayed(state), observations)

law invalid_published_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for invalid: {actual_membership(observations, state) == False{} : Bool}
  {Browser.code_sources(generation, observations, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
law authored_source:
  for +key: Identity.Key
  for +value: String
  for +visual: Design.Style
  for +code_visual: Design.Style
  for +owner: Code.Source
  for +attachments: +List<Source.Node>
  for +native_owner: Maybe<&2, String>
  for +identity: Code.Identity
  for +source_value: String
  {Browser.code_node_owned(Authored.rich_leaf(key, value, visual, code_visual, Some{owner}, attachments, native_owner), identity, source_value) ==
    declared_content_claim(owner, identity, value, source_value) : Bool}
law stream_source:
  for +task: Nat
  for +operation: Nat
  for +index: Nat
  for +text: String
  for +parent: Identity.Key
  for +state: Core.State
  {Interface.live_parts([Live.Part{index, text}], task, operation, parent, state) ==
    [Interface.Node{Identity.Entity{parent, "part", Nat.show(index)}, "stream/part/" ++ Nat.show(index), "Agent output", Interface.Content{},
      Interface.RichText{Code.StreamingPart{task, operation, index}, text},
      Interface.code_nodes(Core.code_scenes(Interface.application(state)), Code.StreamingPart{task, operation, index}, Identity.Entity{parent, "part", Nat.show(index)})}] : +List<Interface.Node>}
