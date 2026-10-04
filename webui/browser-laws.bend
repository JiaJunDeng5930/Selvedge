import Base
import ./browser.bend as Browser
import ./document.bend as Doc
import ./MODEL.bend as Web
import ./focus.bend as Focus
import ./rendered.bend as Rendered
import ./platform.bend as Platform
import ./design.bend as Design
import ./font-observation.bend as F
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../MODEL.bend as M
import ../UI.bend as Product
import ../core/user-experience.bend as E
import ../bendlib/json.bend as J

# Settlement removes every matching ticket, even from malformed duplicate input.
import ../core/interface-program-rules.bend as Rules_interface_program_rules

def sequence(state: Browser.State) -> Nat:
  Browser.State{web, sequence, next, pending} = state
  sequence

# Admission reserves its ticket and carries the original completion exactly once.
def pending(decision: Browser.Decision) -> +List<Browser.Pending>:
  Browser.Decision{Browser.State{web, sequence, next, requests}, effects} = decision
  requests

def web_state(decision: Browser.Decision) -> Web.State:
  Browser.Decision{Browser.State{web, sequence, next, requests}, effects} = decision
  web



def document_state(core: Core.State, platform: Platform.Platform, generation: Nat, realization: Rendered.State, environment: Design.Environment, font: F.State,
  sequence: Nat, next: Nat, requests: +List<Browser.Pending>) -> Browser.State:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  Browser.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, Focus.Document{}}},
    generation, realization, environment, font}, sequence, next, requests}

def document_key_event_law(-key: String, -shift: Bool, -core: Core.State, -platform: Platform.Platform, -generation: Nat, -realization: Rendered.State, -environment: Design.Environment, -font: F.State, -sequence: Nat, -next: Nat, -requests: +List<Browser.Pending>) -> Type:
  {Browser.key_event(key, shift, document_state(core, platform, generation, realization, environment, font, sequence, next, requests)) ==
      Browser.KeyResult{False{}, Browser.Decision{document_state(core, platform, generation, realization, environment, font, sequence, next, requests), Nil{}}} : Browser.KeyResult}

def document_root(value: Doc.Document) -> Doc.Node:
  Doc.Document{root, title} = value
  root

def document_title(value: Doc.Document) -> String:
  Doc.Document{root, title} = value
  title

type RootIdentity is Data:
  RootIdentity{key: String, tag: String}

def node_identity(value: Doc.Node) -> Maybe<&2, RootIdentity>:
  match value:
    case Doc.Element{key, tag, attrs, styles, events, children}: Some{RootIdentity{key, tag}}
    case _: None{}



def first_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{node, rest}: node
    case Nil{}: Doc.Text{""}

def second_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{first, Con{second, rest}}: second
    case _: Doc.Text{""}

def application_node(value: Doc.Document) -> Doc.Node:
  second_node(Doc.element_children(document_root(value)))

def without_root_layout(value: Doc.Node) -> Doc.Node:
  match value:
    case Doc.Element{key, tag, attrs, styles, events, children}: Doc.Element{key, tag, attrs, Nil{}, events, children}
    case other: other







def semantic_scene(scene: Web.Scene) -> UI.Surface:
  Design.semantic_surface(Web.scene_surface(scene))

def semantic_or(outcome: Web.SceneOutcome, original: UI.Surface) -> UI.Surface:
  match outcome:
    case Web.ReadyScene{scene}: semantic_scene(scene)
    case _: original

def transport(decision: Browser.Decision) -> (Nat & (Nat & +List<Browser.Pending>)):
  Browser.Decision{Browser.State{web, sequence, next, pending}, effects} = decision
  (sequence, (next, pending))

type Requirements is Type:
  Requirements{measurements_transport: @+observation: F.Observation -> @+web: Web.State -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> {transport(Browser.measurements(observation, Browser.State{web, sequence, next, pending})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))},
    finish_unchanged_transport: @web: Web.State -> @core: Core.State -> @effects: +List<Web.Effect> -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> @origin: String -> {transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin)) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))},
    receipt_input: @observation: F.Observation -> @state: Browser.State -> {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision},
    request_binding: @application: Platform.State -> @generation: Nat -> @realization: Rendered.State -> @environment: Design.Environment -> @font: F.State -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> {Browser.measurement_plan(Browser.State{Web.State{application, generation, realization, environment, font}, sequence, next, pending}) == Web.measurement_plan(Web.State{application, generation, realization, environment, font}) : F.Plan},
    awaiting_nodes: {Browser.scene_nodes(Web.AwaitingTypography{}) == Nil{} : +List<UI.Node>},
    failed_nodes: {Browser.scene_nodes(Web.FailedTypography{}) == Nil{} : +List<UI.Node>},
    unsupported_nodes: @required: Nat -> @available: Nat -> {Browser.scene_nodes(Web.UnsupportedSpace{required, available}) == Nil{} : +List<UI.Node>},
    awaiting_outside: @identity: String -> @state: Browser.State -> {Browser.outside_scene(identity, Web.AwaitingTypography{}, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    failed_outside: @identity: String -> @state: Browser.State -> {Browser.outside_scene(identity, Web.FailedTypography{}, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    unsupported_outside: @identity: String -> @required: Nat -> @available: Nat -> @state: Browser.State -> {Browser.outside_scene(identity, Web.UnsupportedSpace{required, available}, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    awaiting_key: @key: String -> @shift: Bool -> @state: Browser.State -> {Browser.key_event_scene(Web.AwaitingTypography{}, key, shift, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult},
    failed_key: @key: String -> @shift: Bool -> @state: Browser.State -> {Browser.key_event_scene(Web.FailedTypography{}, key, shift, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult},
    unsupported_key: @required: Nat -> @available: Nat -> @key: String -> @shift: Bool -> @state: Browser.State -> {Browser.key_event_scene(Web.UnsupportedSpace{required, available}, key, shift, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult},

    pending_scene_preserves_semantics: @+web:Web.State -> @+sequence:Nat -> @+next:Nat ->
      @+pending:+List<Browser.Pending> -> @+scene:Web.Scene ->
      @ready:{Browser.scene(Browser.State{web, sequence, next, pending}) == Web.ReadyScene{scene} : Web.SceneOutcome} ->
      {semantic_scene(scene) == Browser.mask_surface(Web.observed_surface(web), pending) : UI.Surface},
    interface_bridge: Rules_interface_program_rules.InterfaceRequirements,
    dismissal_allowed: @+input:Core.Input -> @+state:Browser.State ->
      {Browser.dismiss_permitted(True{}, input, state) ==
        Browser.product_input(Product.InterfaceInput{input}, state) : Browser.Decision},
    dismissal_refused: @input:Core.Input -> @+state:Browser.State ->
      {Browser.dismiss_permitted(False{}, input, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    notice_identity: @notices:+List<Doc.Node> -> @root:Doc.Node -> @title:String ->
      {node_identity(first_node(Doc.element_children(document_root(Browser.with_notices(notices, root, title))))) == Some{RootIdentity{"@browser/unknown-status", "aside"}} : Maybe<&2, RootIdentity>},
    notice_root_identity: @notices: +List<Doc.Node> -> @root: Doc.Node -> @title: String -> {node_identity(document_root(Browser.with_notices(notices, root, title))) ==
    Some{RootIdentity{"@browser/interaction", "div"}} : Maybe<&2, RootIdentity>},
    notice_children: @+notices: +List<Doc.Node> -> @root: Doc.Node -> @title: String -> {Doc.element_children(document_root(Browser.with_notices(notices, root, title))) ==
    [Browser.notice_region(notices), Browser.application_for_notices(notices, root)] : +List<Doc.Node>},
    notice_title: @notices: +List<Doc.Node> -> @root: Doc.Node -> @+title: String -> {document_title(Browser.with_notices(notices, root, title)) == title : String},
    application_identity: @notices: +List<Doc.Node> -> @+root: Doc.Node -> @title: String -> {node_identity(application_node(Browser.with_notices(notices, root, title))) == node_identity(root) : Maybe<&2, RootIdentity>},
    application_content: @notices: +List<Doc.Node> -> @+root: Doc.Node -> @title: String -> {without_root_layout(application_node(Browser.with_notices(notices, root, title))) == without_root_layout(root) : Doc.Node},
    empty_application_unchanged: @+root: Doc.Node -> @title: String -> {application_node(Browser.with_notices(Nil{}, root, title)) == root : Doc.Node},
    empty_notice_hidden: @root: Doc.Node -> @title: String -> {first_node(Doc.element_children(document_root(Browser.with_notices(Nil{}, root, title)))) ==
    Doc.Element{"@browser/unknown-status", "aside", [Doc.Property{"hidden", ""}], [Doc.Property{"display", "none"}], Nil{}, Nil{}} : Doc.Node},
    notice_contents: @notices: +List<Doc.Node> -> @root: Doc.Node -> @title: String -> {Doc.element_children(first_node(Doc.element_children(document_root(Browser.with_notices(notices, root, title))))) == notices : +List<Doc.Node>},
    document_key_event: @+key:String -> @+shift:Bool -> @+core:Core.State -> @+platform:Platform.Platform -> @+generation:Nat ->
      @+realization:Rendered.State -> @+environment:Design.Environment -> @+font:F.State -> @+sequence:Nat -> @+next:Nat -> @+requests:+List<Browser.Pending> ->
      document_key_event_law(key, shift, core, platform, generation, realization, environment, font, sequence, next, requests),
    failed_transition: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> ->
      {Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests}) ==
        Browser.Decision{Browser.State{web, sequence, next, Browser.uncertain_pending(requests, ticket, error)}, Nil{}} : Browser.Decision},
    document_key: @tab:Bool -> @escape:Bool -> @shift:Bool -> @realization:Rendered.State -> @state:Browser.State ->
      {Browser.key_scoped(Focus.Document{}, tab, escape, shift, realization, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    failed_preserves_web: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> ->
      {web_state(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests})) == web : Web.State},
    failed_retains_ticket: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> -> @observed:Nat ->
      {Browser.owns_ticket(pending(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests})), observed) ==
        Browser.owns_ticket(requests, observed) : Bool},
    consumed_ticket: @+pending:+List<Browser.Pending> -> @+ticket:Nat ->
      {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    stale_snapshot: @+received:Nat -> @+world:M.World() -> @+state:Browser.State ->
      @stale:{Nat.is_lt(sequence(state), received) == False{} : Bool} ->
      {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    admitted_request: @command:J.Json -> @completion:E.Completion -> @origin:String ->
      @web:Web.State -> @sequence:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.request_ready(False{}, command, completion, origin, Browser.State{web, sequence, next, pending}) ==
          Browser.Decision{Browser.State{web, sequence, (next + 1n : Nat),
            List.append(&2, Browser.Pending, pending, [Browser.Pending{next, completion, command, origin, Browser.AwaitingReceipt{}}])},
            [Browser.Command{next, command}]} : Browser.Decision},
    stale_completion: @ticket:Nat -> @received:Nat -> @supplied:M.World() -> @reply:J.Json ->
      @completion:E.Completion -> @web:Web.State -> @current:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
          Browser.State{web, current, next, pending}) ==
          Browser.product_input(Product.CommandCompleted{
            Browser.program(Browser.State{web, current, next, pending}), reply, completion},
            Browser.State{web, current, next, Browser.remove(pending, ticket)}) : Browser.Decision}
  }
law evidence:
  Requirements
