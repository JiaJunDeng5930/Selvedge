import Base
import ./browser.bend as Browser
import ./document.bend as Doc
import ./MODEL.bend as Web
import ./laws.bend as Interaction
import ./focus.bend as Focus
import ./rendered.bend as Rendered
import ./platform.bend as Platform
import ./design.bend as Design
import ./font-observation.bend as F
import ./appearance-laws.bend as AppearanceLaws
import ./layout.bend as Layout
import ./appearance.bend as Appearance
import ./typography.bend as T
import ./viewport-space.bend as ViewportSpace
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../MODEL.bend as M
import ../UI.bend as Product
import ../core/user-experience.bend as E
import ../bendlib/json.bend as J

# Settlement removes every matching ticket, even from malformed duplicate input.
def removed_choice_absent(+same: Bool, +entry: Browser.Pending,
  +rest: +List<Browser.Pending>, +ticket: Nat,
  matching: {Nat.is_eq(Browser.ticket_of(entry), ticket) == same : Bool},
  absent: {Browser.owns_ticket(rest, ticket) == False{} : Bool}) ->
  {Browser.owns_ticket(Browser.choose_removed(same, entry, rest), ticket) == False{} : Bool}:
  match same:
    case True{}: absent
    case False{}:
      Equal.trans(Bool,
        Browser.owns_ticket(entry <> rest, ticket),
        Browser.owned_choice(False{}, Browser.owns_ticket(rest, ticket)),
        False{},
        Equal.cong(Bool, Bool,
          (selected => Browser.owned_choice(selected, Browser.owns_ticket(rest, ticket))),
          Nat.is_eq(Browser.ticket_of(entry), ticket), False{}, matching), absent)

def consumed_ticket(+pending: +List<Browser.Pending>, +ticket: Nat) ->
  {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool}:
  match pending:
    case Nil{}: {==}
    case Con{+entry, rest}:
      Browser.Pending{current, completion, command, origin, status} = entry
      removed_choice_absent(Nat.is_eq(current, ticket), entry, Browser.remove(rest, ticket), ticket,
        {==}, consumed_ticket(rest, ticket))

# A stale snapshot never touches the program or any local interaction state.
def sequence(state: Browser.State) -> Nat:
  Browser.State{web, sequence, next, pending} = state
  sequence

# Admission reserves its ticket and carries the original completion exactly once.
def stale_snapshot(+received: Nat, +world: M.World(), +state: Browser.State,
  stale: {Nat.is_lt(sequence(state), received) == False{} : Bool}) ->
  {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  Browser.State{web, current, next, pending} = state
  Equal.cong(Bool, Browser.Decision,
    (newer => Browser.snapshot_new(newer, received, world, Browser.State{web, current, next, pending})),
    Nat.is_lt(current, received), False{}, stale)



def duplicate_retains_state(command: J.Json, completion: E.Completion, origin: String,
  state: Browser.State) ->
  {Browser.request_ready(True{}, command, completion, origin, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  {==}
def unmatched_completion(received: Nat, world: M.World(), reply: J.Json, state: Browser.State) ->
  {Browser.completed(None{}, received, world, reply, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  {==}









def pending(decision: Browser.Decision) -> +List<Browser.Pending>:
  Browser.Decision{Browser.State{web, sequence, next, requests}, effects} = decision
  requests

def web_state(decision: Browser.Decision) -> Web.State:
  Browser.Decision{Browser.State{web, sequence, next, requests}, effects} = decision
  web



def uncertain_entry_ticket(hit: Bool, entry: Browser.Pending, reason: String) ->
  {Browser.ticket_of(Browser.mark_uncertain(hit, entry, reason)) == Browser.ticket_of(entry) : Nat}:
  match hit:
    case False{}: {==}
    case True{}:
      Browser.Pending{ticket, completion, command, origin, status} = entry
      {==}

def uncertain_retains_tickets(+requests: +List<Browser.Pending>, +ticket: Nat, +reason: String, +observed: Nat) ->
  {Browser.owns_ticket(Browser.uncertain_pending(requests, ticket, reason), observed) ==
    Browser.owns_ticket(requests, observed) : Bool}:
  match requests:
    case Nil{}: {==}
    case Con{+entry, +rest}:
      Equal.trans(Bool,
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(Browser.mark_uncertain(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)), observed),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed)),
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed)),
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed), Browser.owns_ticket(rest, observed)),
        Equal.cong(Nat, Bool,
          (key => Browser.owned_choice(Nat.is_eq(key, observed), Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed))),
          Browser.ticket_of(Browser.mark_uncertain(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)), Browser.ticket_of(entry),
          uncertain_entry_ticket(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)),
        Equal.cong(Bool, Bool,
          (tail => Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed), tail)),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed), Browser.owns_ticket(rest, observed),
          uncertain_retains_tickets(rest, ticket, reason, observed)))



def document_state(core: Core.State, platform: Platform.Platform, generation: Nat, realization: Rendered.State, environment: Design.Environment, font: F.State,
  sequence: Nat, next: Nat, requests: +List<Browser.Pending>) -> Browser.State:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  Browser.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, Focus.Document{}}},
    generation, realization, environment, font}, sequence, next, requests}

def document_key_event_law(-key: String, -shift: Bool, -core: Core.State, -platform: Platform.Platform, -generation: Nat, -realization: Rendered.State, -environment: Design.Environment, -font: F.State, -sequence: Nat, -next: Nat, -requests: +List<Browser.Pending>) -> Type:
  {Browser.key_event(key, shift, document_state(core, platform, generation, realization, environment, font, sequence, next, requests)) ==
      Browser.KeyResult{False{}, Browser.Decision{document_state(core, platform, generation, realization, environment, font, sequence, next, requests), Nil{}}} : Browser.KeyResult}

def document_event_outcome(outcome: Web.SceneOutcome, key: String, shift: Bool, core: Core.State,
  platform: Platform.Platform, generation: Nat, realization: Rendered.State, environment: Design.Environment,
  font: F.State, sequence: Nat, next: Nat, requests: +List<Browser.Pending>) ->
  {Browser.key_event_scene(outcome, key, shift, document_state(core, platform, generation, realization, environment, font, sequence, next, requests)) ==
    Browser.KeyResult{False{}, Browser.Decision{document_state(core, platform, generation, realization, environment, font, sequence, next, requests), Nil{}}} : Browser.KeyResult}:
  match outcome:
    case Web.ReadyScene{scene}:
      Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
      {==}
    case Web.AwaitingTypography{}: {==}
    case Web.FailedTypography{}: {==}
    case Web.UnsupportedSpace{required, available}: {==}

def document_key_event(+key: String, +shift: Bool, +core: Core.State, +platform: Platform.Platform, +generation: Nat,
  +realization: Rendered.State, +environment: Design.Environment, +font: F.State, +sequence: Nat, +next: Nat, +requests: +List<Browser.Pending>) -> document_key_event_law(key, shift, core, platform, generation, realization, environment, font, sequence, next, requests):
  document_event_outcome(Browser.scene(document_state(core, platform, generation, realization, environment, font, sequence, next, requests)),
    key, shift, core, platform, generation, realization, environment, font, sequence, next, requests)

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







def application_identity(notices: +List<Doc.Node>, +root: Doc.Node, title: String) ->
  {node_identity(application_node(Browser.with_notices(notices, root, title))) == node_identity(root) : Maybe<&2, RootIdentity>}:
  match notices root:
    case Nil{} _: {==}
    case Con{notice, rest} Doc.Element{key, tag, attrs, styles, events, children}: {==}
    case Con{notice, rest} Doc.Text{text}: {==}
    case Con{notice, rest} Doc.Markdown{key, source, text}: {==}
    case Con{notice, rest} Doc.Portal{key, target, children}: {==}
    case Con{notice, rest} Doc.TargetProperties{key, target, attributes, styles}: {==}

def application_content(notices: +List<Doc.Node>, +root: Doc.Node, title: String) ->
  {without_root_layout(application_node(Browser.with_notices(notices, root, title))) == without_root_layout(root) : Doc.Node}:
  match notices root:
    case Nil{} _: {==}
    case Con{notice, rest} Doc.Element{key, tag, attrs, styles, events, children}: {==}
    case Con{notice, rest} Doc.Text{text}: {==}
    case Con{notice, rest} Doc.Markdown{key, source, text}: {==}
    case Con{notice, rest} Doc.Portal{key, target, children}: {==}
    case Con{notice, rest} Doc.TargetProperties{key, target, attributes, styles}: {==}





def notice_contents(notices: +List<Doc.Node>, root: Doc.Node, title: String) ->
  {Doc.element_children(first_node(Doc.element_children(document_root(Browser.with_notices(notices, root, title))))) == notices : +List<Doc.Node>}:
  match notices:
    case Nil{}: {==}
    case Con{notice, rest}: {==}

def notice_identity(notices: +List<Doc.Node>, root: Doc.Node, title: String) ->
  {node_identity(first_node(Doc.element_children(document_root(Browser.with_notices(notices, root, title))))) ==
    Some{RootIdentity{"@browser/unknown-status", "aside"}} : Maybe<&2, RootIdentity>}:
  match notices:
    case Nil{}: {==}
    case Con{notice, rest}: {==}





def semantic_scene(scene: Web.Scene) -> UI.Surface:
  Web.Scene{surface, platform, generation, realization, layout} = scene
  Design.semantic_surface(surface)

def semantic_or(outcome: Web.SceneOutcome, original: UI.Surface) -> UI.Surface:
  match outcome:
    case Web.ReadyScene{scene}: semantic_scene(scene)
    case _: original

def allocated_semantics(outcome: Layout.Outcome, application: Platform.State, generation: Nat,
  realization: Rendered.State, +surface: UI.Surface, dark: Bool, scale: T.Scale) ->
  {semantic_or(Web.allocated_scene(outcome, application, generation, realization, surface, dark, scale), surface) == surface : UI.Surface}:
  match outcome:
    case Layout.LayoutReady{layout}: AppearanceLaws.present_preserves_semantics(surface, dark, scale)
    case Layout.LayoutUnsupported{required, available}: {==}

def font_semantics(font: F.State, application: Platform.State, generation: Nat, realization: Rendered.State,
  +viewport: Design.Viewport, dark: Bool, +surface: UI.Surface) ->
  {semantic_or(Web.font_scene(font, application, generation, realization, viewport, dark, surface), surface) == surface : UI.Surface}:
  match font:
    case F.Pending{font_generation, scale}: {==}
    case F.Failed{font_generation, scale}: {==}
    case F.Ready{font_generation, +scale, metric}:
      allocated_semantics(Layout.present(ViewportSpace.parameters(scale, metric), viewport, surface), application,
        generation, realization, surface, dark, scale)

def web_semantics(state: Web.State, +surface: UI.Surface) ->
  {semantic_or(Web.scene_for_surface(state, surface), surface) == surface : UI.Surface}:
  Web.State{application, generation, realization, Design.Environment{viewport, dark, root}, font} = state
  font_semantics(font, application, generation, realization, viewport, dark, surface)

def pending_scene_preserves_semantics(+web: Web.State, +sequence: Nat, +next: Nat,
  +pending: +List<Browser.Pending>, +scene: Web.Scene,
  ready: {Browser.scene(Browser.State{web, sequence, next, pending}) == Web.ReadyScene{scene} : Web.SceneOutcome}) ->
  {semantic_scene(scene) == Browser.mask_surface(Web.observed_surface(web), pending) : UI.Surface}:
  +original = Browser.mask_surface(Web.observed_surface(web), pending)
  Equal.trans(UI.Surface, semantic_scene(scene), semantic_or(Browser.scene(Browser.State{web, sequence, next, pending}), original), original,
    Equal.sym(UI.Surface, semantic_or(Browser.scene(Browser.State{web, sequence, next, pending}), original), semantic_scene(scene),
      Equal.cong(Web.SceneOutcome, UI.Surface, (outcome => semantic_or(outcome, original)),
        Browser.scene(Browser.State{web, sequence, next, pending}), Web.ReadyScene{scene}, ready)),
    web_semantics(web, original))

def receipt_input(observation: F.Observation, state: Browser.State) ->
  {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision}:
  {==}

def request_binding(application: Platform.State, generation: Nat, realization: Rendered.State,
  environment: Design.Environment, font: F.State, sequence: Nat, next: Nat, pending: +List<Browser.Pending>) ->
  {Browser.measurement_plan(Browser.State{Web.State{application, generation, realization, environment, font}, sequence, next, pending}) == F.request(font) : F.Plan}:
  {==}

def awaiting_nodes() -> {Browser.scene_nodes(Web.AwaitingTypography{}) == Nil{} : +List<UI.Node>}:
  {==}

def failed_nodes() -> {Browser.scene_nodes(Web.FailedTypography{}) == Nil{} : +List<UI.Node>}:
  {==}

def unsupported_nodes(required: Nat, available: Nat) ->
  {Browser.scene_nodes(Web.UnsupportedSpace{required, available}) == Nil{} : +List<UI.Node>}:
  {==}

def awaiting_outside(identity: String, state: Browser.State) ->
  {Browser.outside_scene(identity, Web.AwaitingTypography{}, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision}:
  {==}

def failed_outside(identity: String, state: Browser.State) ->
  {Browser.outside_scene(identity, Web.FailedTypography{}, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision}:
  {==}

def unsupported_outside(identity: String, required: Nat, available: Nat, state: Browser.State) ->
  {Browser.outside_scene(identity, Web.UnsupportedSpace{required, available}, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision}:
  {==}

def awaiting_key(key: String, shift: Bool, state: Browser.State) ->
  {Browser.key_event_scene(Web.AwaitingTypography{}, key, shift, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult}:
  {==}

def failed_key(key: String, shift: Bool, state: Browser.State) ->
  {Browser.key_event_scene(Web.FailedTypography{}, key, shift, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult}:
  {==}

def unsupported_key(required: Nat, available: Nat, key: String, shift: Bool, state: Browser.State) ->
  {Browser.key_event_scene(Web.UnsupportedSpace{required, available}, key, shift, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult}:
  {==}

def transport(decision: Browser.Decision) -> (Nat & (Nat & +List<Browser.Pending>)):
  Browser.Decision{Browser.State{web, sequence, next, pending}, effects} = decision
  (sequence, (next, pending))

def finish_unchanged_transport(web: Web.State, core: Core.State, effects: +List<Web.Effect>, sequence: Nat,
  next: Nat, pending: +List<Browser.Pending>, origin: String) ->
  {transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin)) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  match core:
    case Core.State{application, services}: {==}

def finished_receipt_transport(decision: Web.Decision, +core: Core.State,
  unchanged: {Web.product(decision) == Platform.unchanged(core) : Core.Decision},
  +sequence: Nat, +next: Nat, +pending: +List<Browser.Pending>, +origin: String) ->
  {transport(Browser.finish(decision, sequence, next, pending, origin)) == (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  Web.Decision{+web, +product, +effects} = decision
  Equal.trans((Nat & (Nat & +List<Browser.Pending>)),
    transport(Browser.finish(Web.Decision{web, product, effects}, sequence, next, pending, origin)),
    transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin)),
    (sequence, (next, pending)),
    Equal.cong(Core.Decision, (Nat & (Nat & +List<Browser.Pending>)),
      (current => transport(Browser.finish(Web.Decision{web, current, effects}, sequence, next, pending, origin))),
      product, Platform.unchanged(core), unchanged),
    finish_unchanged_transport(web, core, effects, sequence, next, pending, origin))

def measurements_transport(+observation: F.Observation, +web: Web.State, sequence: Nat, next: Nat, pending: +List<Browser.Pending>) ->
  {transport(Browser.measurements(observation, Browser.State{web, sequence, next, pending})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  finished_receipt_transport(Web.step(Web.TypographyObserved{observation}, web),
    Interaction.model_core(Interaction.model_application(web)), Interaction.typography_product(web, observation), sequence, next, pending, "")

type Requirements is Type:
  Requirements{measurements_transport: @+observation: F.Observation -> @+web: Web.State -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> {transport(Browser.measurements(observation, Browser.State{web, sequence, next, pending})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))},
    finish_unchanged_transport: @web: Web.State -> @core: Core.State -> @effects: +List<Web.Effect> -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> @origin: String -> {transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin)) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))},
    receipt_input: @observation: F.Observation -> @state: Browser.State -> {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision},
    request_binding: @application: Platform.State -> @generation: Nat -> @realization: Rendered.State -> @environment: Design.Environment -> @font: F.State -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> {Browser.measurement_plan(Browser.State{Web.State{application, generation, realization, environment, font}, sequence, next, pending}) == F.request(font) : F.Plan},
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
    interface_bridge: Product.InterfaceRequirements,
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
def evidence() -> Requirements:
  Requirements{measurements_transport, finish_unchanged_transport, receipt_input, request_binding, awaiting_nodes(), failed_nodes(), unsupported_nodes, awaiting_outside, failed_outside, unsupported_outside, awaiting_key, failed_key, unsupported_key, pending_scene_preserves_semantics, Product.interface_evidence(), +input => +state => {==}, input => +state => {==}, notice_identity, notices => root => title => {==}, +notices => root => title => {==}, notices => root => +title => {==}, application_identity, application_content, +root => title => {==}, root => title => {==}, notice_contents, document_key_event, ticket => error => web => sequence => next => requests => {==}, tab => escape => shift => realization => state => {==}, ticket => error => web => sequence => next => requests => {==}, ticket => error => web => sequence => next => requests => observed => uncertain_retains_tickets(requests, ticket, error, observed), consumed_ticket, stale_snapshot, command => completion => origin => web => sequence => next => pending => {==}, ticket => received => supplied => reply => completion => web => current => next => pending => {==}}
