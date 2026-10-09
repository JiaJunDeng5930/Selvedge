import Base
import ./SEMANTICS.bend as Browser
import ./CONTRACT.bend as Rule
import ../../interaction/submission/MODEL.bend as Receipt
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ./frontend-utility.bend as Utility
import ../appearance/TYPOGRAPHY.bend as T
import ./native-fields.bend as Native
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../bendlib/stdlib.bend as Std
import ../document/SOURCE.bend as Source
import ./MODEL.bend as BrowserModel
import ../../interaction/MODEL.bend as Product
import ../MODEL.bend as Web
import ../CONTRACT.bend as Interaction
import ../document/RENDERED.bend as Rendered
import ./PLATFORM.bend as Platform
import ../appearance/DESIGN.bend as Design
import ../appearance/FONT.bend as F
import ../PROOF.bend as Proof_laws
import ../../interaction/presentation/CONTRACT.bend as Rules_interface_program_rules
import ../document/presentation-order.bend as Order
import ../layout/PROGRAM.bend as Allocation
import ../layout/GEOMETRY.bend as AnchorGeometry
import ../focus/MODEL.bend as Focus
import ../layout/physical-plan.bend as Plan
import ../layout/MODEL.bend as World
import ../layout/CONTENT.bend as Content
import ../controls/SHELL.bend as Shell
import ../../interaction/presentation/MODEL.bend as View
import ../../bendlib/logic-proof.bend as Logic
import ../document/FRAME.bend as SourceFrame
import ../document/render-contract.bend as FrameRules
import ./request.bend as Request
import ../../harness/transport/command-codec.bend as Codec
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes

def receipt_recorded(+receipt: Maybe<&2, Receipt.Receipt>, decision: Browser.Decision) ->
  {Browser.decision_receipt(Browser.receipt_decision(receipt, decision)) == receipt : Maybe<&2, Receipt.Receipt>}:
  match decision:
    case Browser.Decision{Browser.State{web, sequence, next, pending, previous}, effects}: {==}

def direct(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, state: Browser.State) ->
  Rule.direct_claim(ticket, received, world, code, message, command, origin, status, state):
  receipt_recorded(Some{Receipt.Receipt{ticket, origin, code, message}},
    Browser.complete_ticket(ticket, received, world, D.failure(code, message), E.DirectCompletion{}, state))

def confirmation(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, selected: M.Command,
  trigger: String, destination: U.Route, occurrence: Nat, state: Browser.State) ->
  Rule.confirmation_claim(ticket, received, world, code, message, command, origin, status, selected, trigger, destination, occurrence, state):
  receipt_recorded(Some{Receipt.Receipt{ticket, origin, code, message}},
    Browser.complete_ticket(ticket, received, world, D.failure(code, message), E.ConfirmationCompletion{selected, trigger, destination, occurrence}, state))

def unknown_receipt(ticket: Nat, reason: String, +state: Browser.State) ->
  {Browser.decision_receipt(Browser.failed_completion(ticket, reason, state)) == Browser.operation_receipt(state) : Maybe<&2, Receipt.Receipt>}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def accepted_receipt(command: J.Json, completion: E.Completion, origin: String, state: Browser.State) ->
  {Browser.decision_receipt(Browser.request_ready(False{}, command, completion, origin, state)) == None{} : Maybe<&2, Receipt.Receipt>}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def Rule.browser_receipt_evidence():
  Rule.BrowserReceiptRequirements{direct, confirmation,
    received => world => reply => +state => {==},
    draft => receipt => +decision => {==},
    ticket => reason => +state => unknown_receipt(ticket, reason, state),
    command => completion => origin => +state => {==},
    command => completion => origin => state => accepted_receipt(command, completion, origin, state)}

def supported(+purpose: Utility.Purpose, +font: T.Presentation, +glyph_only: Bool) ->
  {Utility.supported(Utility.source(purpose, font, glyph_only)) == True{} : Bool}:
  match purpose:
    case Utility.Preparing{}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}
    case Utility.Recovery{message}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}

def owned(+purpose: Utility.Purpose, +font: T.Presentation, +glyph_only: Bool) ->
  {Utility.owned(Utility.source(purpose, font, glyph_only)) == True{} : Bool}:
  match purpose:
    case Utility.Preparing{}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}
    case Utility.Recovery{message}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}

def Rule.frontend_utility_evidence():
  Rule.FrontendUtilityRequirements{supported, +font => +reason => {==}, owned}

def unchanged(+record: Native.Record, +value: String,
  proof: {Native.canonical_same(Native.record_canonical(record), value) == True{} : Bool}) -> Rule.unchanged_claim(value, record):
  match record:
    case Native.Record{identity, +canonical, +session}:
      Std.transport(Bool, True{},
        (same => {Native.synchronized(same, value, Native.Record{identity, canonical, session}) == Native.Decision{Native.Record{identity, canonical, session}, False{}, False{}} : Native.Decision}),
        {==}, Native.canonical_same(canonical, value), proof)

def unmatched(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>,
  proof: {Native.owned_node(binding, found) == False{} : Bool}) -> Rule.unmatched_claim(binding, found):
  Std.transport(Bool, False{},
    (owned => {Native.update_owned(owned, binding, found) == Nil{} : +List<Native.Update>}),
    {==}, Native.owned_node(binding, found), proof)

def matching(+binding: Native.Binding, +node: SurfaceTypes.Node,
  proof: {Native.owned_node(binding, Some{node}) == True{} : Bool}) -> Rule.matching_claim(binding, node):
  match binding node:
    case Native.Binding{+key, +kind, identity, original} SurfaceTypes.Node{current, semantic, label, role, +meaning, children}:
      Std.transport(Bool, True{},
        (owned => {Native.update_owned(owned, Native.Binding{key, kind, identity, original}, Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}),
        {==}, Native.owned_node(binding, Some{node}), proof)

def changed_composing(+identity: Maybe<&2, Native.Identity>, +old: Maybe<&2, String>, +value: String,
  proof: {Native.canonical_same(old, value) == False{} : Bool}) -> Rule.changed_composing_claim(identity, old, value):
  Std.transport(Bool, False{},
    (same => {Native.synchronized(same, value, Native.Record{identity, old, Native.Composing{}}) == Native.Decision{Native.Record{identity, Some{value}, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}),
    {==}, Native.canonical_same(old, value), proof)

def transaction(+record: Native.Record) -> Rule.transaction_claim(record):
  match record:
    case Native.Record{identity, canonical, session}: {==}

def equal_rebind(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session,
  proof: {Native.same_identity(old, identity) == True{} : Bool}) -> Rule.equal_rebind_claim(old, identity, canonical, session):
  Std.transport(Bool, True{},
    (same => {Native.rebound(same, identity, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{old}, canonical, session}, False{}, False{}} : Native.Decision}),
    {==}, Native.same_identity(old, identity), proof)

def changed_rebind(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session,
  proof: {Native.same_identity(old, identity) == False{} : Bool}) -> Rule.changed_rebind_claim(old, identity, canonical, session):
  Std.transport(Bool, False{},
    (same => {Native.rebound(same, identity, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{identity}, canonical, Native.rebind_session(session)}, False{}, True{}} : Native.Decision}),
    {==}, Native.same_identity(old, identity), proof)

def Rule.native_fields_evidence():
  Rule.NativeFieldsRequirements{
    +identity => +canonical => +session => {==},
    +old => +identity => +canonical => +session => proof => equal_rebind(old, identity, canonical, session, proof),
    +old => +identity => +canonical => +session => proof => changed_rebind(old, identity, canonical, session, proof),
    {==},
    {==},
    +editor => +other => +field => +entry => +value => +choices => +new_field => +new_entry => +new_value => +new_choices => {==},
    +value => +record => proof => unchanged(record, value, proof),
    +binding => +found => proof => unmatched(binding, found, proof),
    +binding => +node => proof => matching(binding, node, proof),
    +identity => +old => +value => proof => changed_composing(identity, old, value, proof),
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +record => transaction(record),
    +key => +semantic => +meaning => {==},
    +key => +semantic => +meaning => {==}}

def Rule.updates_empty(nodes): {==}

def Rule.updates_complete(binding, rest, nodes): {==}

def Rule.updates_basis(fields, controls, surface): {==}

def Rule.update_owner(key, kind, semantic, meaning, nodes): {==}

def Rule.all_field_projections(kind, key, semantic, meaning):
  match kind:
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.ToggleField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def Rule.edit_text_rejected(key, text, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.edit_text_owned(allowed, key, text, state)),
    BrowserModel.field_owned(key, state), False{}, owned)

def Rule.edit_text_accepted(key, text, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.edit_text_owned(allowed, key, text, state)),
    BrowserModel.field_owned(key, state), True{}, owned)

def Rule.confirm_text_rejected(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.confirm_text_owned(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
    BrowserModel.field_owned(key, state), False{}, owned)

def Rule.confirm_text_accepted(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.confirm_text_owned(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
    BrowserModel.field_owned(key, state), True{}, owned)

def Rule.edit_toggle_rejected(key, enabled, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.edit_toggle_owned(allowed, key, enabled, state)),
    BrowserModel.field_owned(key, state), False{}, owned)

def Rule.edit_toggle_accepted(key, enabled, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.edit_toggle_owned(allowed, key, enabled, state)),
    BrowserModel.field_owned(key, state), True{}, owned)

def Rule.attach_rejected(key, file, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.attach_owned(allowed, key, file, state)),
    BrowserModel.field_owned(key, state), False{}, owned)

def Rule.attach_accepted(key, file, state, owned):
  Equal.cong(Bool, BrowserModel.Decision,
    (allowed => BrowserModel.attach_owned(allowed, key, file, state)),
    BrowserModel.field_owned(key, state), True{}, owned)

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

def stale_snapshot(+received: Nat, +world: M.World(), +state: Browser.State,
  stale: {Nat.is_lt(Rule.sequence(state), received) == False{} : Bool}) ->
  {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  Browser.State{web, current, next, pending, receipt} = state
  Equal.cong(Bool, Browser.Decision,
    (newer => Browser.snapshot_new(newer, received, world, Browser.State{web, current, next, pending, receipt})),
    Nat.is_lt(current, received), False{}, stale)

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

def document_key_event(+key: String, +shift: Bool, +state: Browser.State) -> Rule.document_key_event_law(key, shift, state):
  Browser.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment, font}, sequence, next, requests, receipt} = state
  {==}

def receipt_input(observation: F.Observation, state: Browser.State) ->
  {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision}:
  {==}

def finish_unchanged_transport(web: Web.State, core: InteractionTypes.State, effects: +List<Web.Effect>, sequence: Nat,
  next: Nat, pending: +List<Browser.Pending>, origin: String) ->
  {Rule.transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  match core:
    case InteractionTypes.State{application, services}: {==}

def finished_receipt_transport(decision: Web.Decision, +core: InteractionTypes.State,
  unchanged: {Web.product(decision) == Platform.unchanged(core) : InteractionTypes.Decision},
  +sequence: Nat, +next: Nat, +pending: +List<Browser.Pending>, +origin: String) ->
  {Rule.transport(Browser.finish(decision, sequence, next, pending, origin, None{})) == (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  Web.Decision{+web, +product, +effects} = decision
  Equal.trans((Nat & (Nat & +List<Browser.Pending>)),
    Rule.transport(Browser.finish(Web.Decision{web, product, effects}, sequence, next, pending, origin, None{})),
    Rule.transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})),
    (sequence, (next, pending)),
    Equal.cong(InteractionTypes.Decision, (Nat & (Nat & +List<Browser.Pending>)),
      (current => Rule.transport(Browser.finish(Web.Decision{web, current, effects}, sequence, next, pending, origin, None{}))),
      product, Platform.unchanged(core), unchanged),
    finish_unchanged_transport(web, core, effects, sequence, next, pending, origin))

def nodes_current_surface(+web: Web.State, sequence: Nat, next: Nat, +pending: +List<Browser.Pending>) ->
  {Browser.nodes(Browser.State{web, sequence, next, pending, None{}}) == InterfaceView.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(web)), pending))) : +List<SurfaceTypes.Node>}:
  match web:
    case Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment, font}: {==}

def state_measurements_transport_evidence(+model_state: Browser.State, +observation: F.Observation) ->
  {Rule.transport(Browser.measurements(observation, Browser.with_receipt(None{}, model_state))) ==
    (Browser.sequence(model_state), (Browser.next_ticket(model_state), Browser.pending(model_state))) : (Nat & (Nat & +List<Browser.Pending>))}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  finished_receipt_transport(Web.step(Web.TypographyObserved{observation}, web),
    Interaction.model_core(Interaction.model_application(web)), Proof_laws.typography_product(web, observation), sequence, next, pending, "")

def state_nodes_current_surface_evidence(+model_state: Browser.State) ->
  {Browser.nodes(Browser.with_receipt(None{}, model_state)) == InterfaceView.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(Browser.web(model_state))), Browser.pending(model_state)))) : +List<SurfaceTypes.Node>}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  nodes_current_surface(web, sequence, next, pending)

def state_failed_transition_evidence(+model_state: Browser.State, ticket: Nat, error: String) ->
  {Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(Browser.uncertain_pending(Browser.pending(model_state), ticket, error), model_state)), Nil{}} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  {==}

def state_failed_preserves_web_evidence(+model_state: Browser.State, ticket: Nat, error: String) ->
  {Rule.web_state(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))) == Browser.web(model_state) : Web.State}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  {==}

def state_failed_retains_ticket_evidence(+model_state: Browser.State, ticket: Nat, error: String, observed: Nat) ->
  {Browser.owns_ticket(Rule.pending(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))), observed) ==
        Browser.owns_ticket(Browser.pending(model_state), observed) : Bool}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  uncertain_retains_tickets(requests, ticket, error, observed)

def state_admitted_request_evidence(+model_state: Browser.State, command: J.Json, completion: E.Completion, origin: String) ->
  {Browser.request_ready(False{}, command, completion, origin, Browser.with_receipt(None{}, model_state)) ==
          Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(List.append(&2, Browser.Pending, Browser.pending(model_state), [Browser.Pending{Browser.next_ticket(model_state), completion, command, origin, Browser.AwaitingReceipt{}}]), Browser.with_next_ticket((Browser.next_ticket(model_state) + 1n : Nat), model_state))),
            [Browser.Command{Browser.next_ticket(model_state), command}]} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  {==}

def state_stale_completion_evidence(+model_state: Browser.State, ticket: Nat, received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion) ->
  {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
          Browser.with_receipt(None{}, model_state)) ==
          Browser.product_input(Product.CommandCompleted{
            Browser.program(Browser.with_receipt(None{}, model_state)), reply, completion},
            Browser.with_receipt(None{}, Browser.with_pending(Browser.remove(Browser.pending(model_state), ticket), model_state))) : Browser.Decision}:
  Browser.State{+web, +current, +next, +pending, +original_1} = model_state
  {==}

def Rule.browser_evidence():
  Rule.BrowserRequirements{
    state_measurements_transport_evidence,
    finish_unchanged_transport,
    receipt_input,
    state_nodes_current_surface_evidence,
    Rules_interface_program_rules.interface_evidence(),
    +input => +state => {==},
    input => +state => {==},
    document_key_event,
    state_failed_transition_evidence,
    tab => escape => shift => realization => state => {==},
    state_failed_preserves_web_evidence,
    state_failed_retains_ticket_evidence,
    consumed_ticket,
    stale_snapshot,
    state_admitted_request_evidence,
    state_stale_completion_evidence}

def stale_frames(+received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State,
  proof: {BrowserModel.frame_owned(received, state) == False{} : Bool}) ->
  Rule.stale_frames_claim(received, frame, state):
  Std.transport(Bool, False{},
    (owned => {BrowserModel.received_frame(owned, frame, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
    {==}, BrowserModel.frame_owned(received, state), proof)

def stale_measurements(+received: BrowserModel.MeasurementTicket, +tokens: +List<String>, +state: BrowserModel.State,
  proof: {BrowserModel.measurement_owned(received, state) == False{} : Bool}) ->
  Rule.stale_measurements_claim(received, tokens, state):
  Std.transport(Bool, False{},
    (owned => {BrowserModel.measured_current(owned, tokens, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
    {==}, BrowserModel.measurement_owned(received, state), proof)

def ready_document(+rendering_capacity: Nat, +legacy: Browser.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface) ->
  Rule.ready_document_claim(BrowserModel.State{legacy, serial, anchors, BrowserModel.Displaying{layout_capacity, engine, semantic}, Some{BrowserModel.published(world, layout_capacity, legacy, semantic)}}, rendering_capacity, layout_capacity, engine, world, semantic):
  match legacy:
    case Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}:
      match world:
        case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def anchor_preserves_program(+key: String, +left: AnchorGeometry.Origin, +top: AnchorGeometry.Origin, +width: Nat, +height: Nat, +state: BrowserModel.State) ->
  Rule.anchor_preserves_program_claim(key, left, top, width, height, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed}:
      match legacy:
        case Browser.State{web, sequence, ticket, pending, receipt}:
          match web:
            case Web.State{application, generation, realization, environment, font}:
              match environment:
                case Design.Environment{viewport, dark, root}:
                  match viewport:
                    case Design.Viewport{viewport_width, viewport_height}: {==}

def pending_publication_at(+text_capacity: Nat, +last_published: Nat, +state: BrowserModel.State,
  waiting: {Rule.publication_pending(state) == True{} : Bool}) ->
  {BrowserModel.publication_for_at(text_capacity, True{}, BrowserModel.display_ready(state), Nat.is_eq(BrowserModel.displayed_generation(state), last_published), state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}:
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: {==}
        case BrowserModel.WaitingFont{}: {==}
        case BrowserModel.Measuring{index, capacity, engine, semantic, round}: {==}
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: {==}
        case BrowserModel.UtilityDisplaying{purpose, engine}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, Nat.is_eq(BrowserModel.displayed_generation(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, displayed}), last_published), BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, displayed})} : BrowserModel.Publication}, waiting)
        case BrowserModel.UtilityRejected{problem}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, False{}, Nat.is_eq(BrowserModel.displayed_generation(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed}), last_published), BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed})} : BrowserModel.Publication}, waiting)
        case BrowserModel.Displaying{capacity, engine, semantic}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, Nat.is_eq(BrowserModel.displayed_generation(BrowserModel.State{legacy, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed}), last_published), BrowserModel.State{legacy, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed})} : BrowserModel.Publication}, waiting)
        case BrowserModel.Blocked{problem}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, False{}, Nat.is_eq(BrowserModel.displayed_generation(BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed}), last_published), BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed})} : BrowserModel.Publication}, waiting)

def publication_preserves_pending_at(+text_capacity: Nat, +last_published: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  waiting: {Rule.publication_pending(state) == True{} : Bool}) -> Rule.publication_preserves_pending_claim_at(text_capacity, last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {BrowserModel.publication_for_at(text_capacity, has_existing, BrowserModel.display_ready(state),
      Nat.is_eq(BrowserModel.displayed_generation(state), last_published), state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}),
    pending_publication_at(text_capacity, last_published, state, waiting),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def ready_publication_at(+text_capacity: Nat, +state: BrowserModel.State, ready: {BrowserModel.display_ready(state) == True{} : Bool}) ->
  {BrowserModel.publication_for_at(text_capacity, True{}, True{}, True{}, state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}:
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed}:
      match lifecycle:
        case BrowserModel.Displaying{capacity, engine, semantic}: {==}
        case BrowserModel.UtilityDisplaying{purpose, engine}: {==}
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, True{}, BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed})} : BrowserModel.Publication}, ready)
        case BrowserModel.UtilityRejected{problem}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, True{}, BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed})} : BrowserModel.Publication}, ready)
        case BrowserModel.WaitingEnvironment{}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, True{}, BrowserModel.State{legacy, serial, anchors, BrowserModel.WaitingEnvironment{}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.WaitingEnvironment{}, displayed})} : BrowserModel.Publication}, ready)
        case BrowserModel.WaitingFont{}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, True{}, BrowserModel.State{legacy, serial, anchors, BrowserModel.WaitingFont{}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.WaitingFont{}, displayed})} : BrowserModel.Publication}, ready)
        case BrowserModel.Measuring{index, capacity, engine, semantic, round}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, True{}, BrowserModel.State{legacy, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed})} : BrowserModel.Publication}, ready)
        case BrowserModel.Blocked{problem}: Logic.impossible(
          {BrowserModel.publication_for_at(text_capacity, True{}, True{}, True{}, BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed}) == BrowserModel.KeepPublished{BrowserModel.native_updates(BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed})} : BrowserModel.Publication}, ready)

def blocked_publication_at(+capacity: Nat, +last_published: Nat, +legacy: Browser.State, +serial: Nat,
  +anchors: +List<Shell.Anchor>, +problem: String, +displayed: Maybe<&2, BrowserModel.Published>) -> Rule.blocked_publication_claim_at(BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed}, capacity, last_published, problem):
  match legacy:
    case Browser.State{web, sequence, ticket, pending, receipt}:
      match web:
        case Web.State{application, generation, realization, environment, font}: {==}

def publication_current_at(+text_capacity: Nat, +last_published: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  +ready: {BrowserModel.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(BrowserModel.displayed_generation(state), last_published) == True{} : Bool}) -> Rule.publication_current_claim_at(text_capacity, last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {BrowserModel.publication_for_at(text_capacity, has_existing, BrowserModel.display_ready(state),
      Nat.is_eq(BrowserModel.displayed_generation(state), last_published), state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}),
    Std.transport(Bool, True{},
      (is_ready => {BrowserModel.publication_for_at(text_capacity, True{}, is_ready, Nat.is_eq(BrowserModel.displayed_generation(state), last_published), state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}),
      Std.transport(Bool, True{},
        (is_current => {BrowserModel.publication_for_at(text_capacity, True{}, True{}, is_current, state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}),
        ready_publication_at(text_capacity, state, ready), Nat.is_eq(BrowserModel.displayed_generation(state), last_published), current),
      BrowserModel.display_ready(state), ready),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def frame_capture_program(+frame: Rendered.Frame, +state: BrowserModel.State) -> Rule.frame_capture_program_claim(frame, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{world, semantic, scope, basis, old}}: {==}

def Rule.forwarded_frame_uses_published_surface(model_state, world, semantic, scope, basis, old, frame):
  BrowserModel.State{+stored, +serial, +anchors, +lifecycle, +original_1} = model_state
  {==}

def Rule.failed_font_candidate_blocked(model_state, font_generation, scale, index):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +realization, +environment, +original_1}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.unmet_frame_status(model_state, semantic, frame_generation, frame, violations, capacity, engine):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +original_3, +displayed} = model_state
  {==}

def eligible_fields(+enabled: Bool, +visible: Bool, +scroll: Bool,
  admitted: {enabled == True{} : Bool}, reachable: {visible || scroll == True{} : Bool}) ->
  {enabled && (visible || scroll) == True{} : Bool}:
  match enabled visible scroll:
    case False{} True{} True{}: admitted
    case False{} True{} False{}: admitted
    case False{} False{} True{}: admitted
    case False{} False{} False{}: admitted
    case True{} True{} True{}: {==}
    case True{} True{} False{}: {==}
    case True{} False{} True{}: {==}
    case True{} False{} False{}: reachable

def Rule.enabled_reachable_tab_member(element, admitted, reachable):
  match element:
    case Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds}:
      eligible_fields(enabled, visible, scroll, admitted, reachable)

def Rule.rejected_native_focus_preserves_state(generation, owner, identity, state, rejected):
  Equal.cong(Bool, BrowserModel.Decision,
    (owned => BrowserModel.native_focus_if_owned(owned, owner, identity, state)),
    BrowserModel.native_observation_owned(generation, owner, identity, state), False{}, rejected)

def Rule.missing_native_frame_rejects(semantic, owner, identity): {==}

def Rule.stale_native_focus_preserves_state(generation, owner, identity, state, stale):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
          Equal.cong(Bool, BrowserModel.Decision,
            (current => BrowserModel.native_focus_if_owned(current && BrowserModel.source_delegates(source, owner) &&
              Rendered.read_only(InterfaceView.find_node(InterfaceView.active_nodes(semantic), owner)) && BrowserModel.native_frame_owned(frame, semantic, owner, identity), owner, identity, state)),
            Nat.is_eq(generation, published), False{}, stale)

def Rule.stale_measurement_failure(ticket, reason, state, stale):
  Std.transport(Bool, False{},
    (owned => {BrowserModel.measurement_failed(owned, reason, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
    {==}, BrowserModel.measurement_owned(ticket, state), stale)

def Rule.current_measurement_failure(ticket, reason, state, owned):
  Std.transport(Bool, True{},
    (accepted => {BrowserModel.measurement_failed(accepted, reason, state) == BrowserModel.utility_measurement_failure(reason, state) : BrowserModel.Decision}),
    {==}, BrowserModel.measurement_owned(ticket, state), owned)

def Rule.measurement_ownership_only_measuring(ticket, state, owned):
  match ticket:
    case BrowserModel.MeasurementTicket{generation, received_round}:
      match state:
        case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed}:
          match lifecycle:
            case BrowserModel.Measuring{index, capacity, engine, semantic, round}: {==}
            case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: {==}
            case BrowserModel.UtilityDisplaying{purpose, engine}: owned
            case BrowserModel.UtilityRejected{problem}: owned
            case BrowserModel.WaitingEnvironment{}: owned
            case BrowserModel.WaitingFont{}: owned
            case BrowserModel.Displaying{capacity, engine, semantic}: owned
            case BrowserModel.Blocked{problem}: owned

def Rule.measurement_request_unavailable(state, inactive):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: {==}
        case BrowserModel.WaitingFont{}: {==}
        case BrowserModel.Displaying{capacity, engine, semantic}: {==}
        case BrowserModel.Blocked{problem}: {==}
        case BrowserModel.UtilityDisplaying{purpose, engine}: {==}
        case BrowserModel.UtilityRejected{problem}: {==}
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}:
          Logic.impossible({BrowserModel.measurement_request(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed}) == None{} : Maybe<&2, BrowserModel.MeasurementRequest>}, Equal.sym(Bool, True{}, False{}, inactive))
        case BrowserModel.Measuring{index, capacity, engine, semantic, round}:
          Logic.impossible(
            {BrowserModel.measurement_request(BrowserModel.State{legacy, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed}) == None{} : Maybe<&2, BrowserModel.MeasurementRequest>},
            Equal.sym(Bool, True{}, False{}, inactive))

def Rule.measurement_wrong_round(model_state, generation, received_round, round, index, capacity, engine, semantic, same_generation, stale_round):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  Std.transport(Bool, True{},
    (same => {same && Nat.is_eq(received_round, round) == False{} : Bool}),
    Std.transport(Bool, False{},
      (same_round => {True{} && same_round == False{} : Bool}),
      {==}, Nat.is_eq(received_round, round), stale_round),
    Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))), same_generation)

def Rule.measurement_request_canonical(model_state, index, capacity, engine, semantic, round, generation, first, remaining, awaiting):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  Std.transport(Plan.Plan, Plan.Awaiting{generation, first, remaining},
    (plan => {BrowserModel.measurement_request_plan(plan, World.snapshot_generation(World.snapshot(engine)), round) ==
      Some{BrowserModel.MeasurementRequest{BrowserModel.MeasurementTicket{World.snapshot_generation(World.snapshot(engine)), round}, Plan.Awaiting{generation, first, remaining}}} : Maybe<&2, BrowserModel.MeasurementRequest>}),
    {==}, World.plan(engine), awaiting)

def Rule.render_violations_unmet(model_state, observed_generation, frame, violations):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.render_violations_awaiting(model_state, observed_generation):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.render_violations_realized(model_state, observed_generation, frame):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.pending_frame_effects(state):
  match state:
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, None{}}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, None{}}}}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, Some{frame}}}}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.WaitingEnvironment{}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.WaitingFont{}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Blocked{problem}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.Realized{observed_generation, frame}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.Unmet{observed_generation, frame, violations}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, None{}}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, published_semantic, scope, basis, frame}}}: {==}

def Rule.retained_frame_decision(first, state):
  Std.transport(+List<Browser.Effect>, BrowserModel.pending_frame_effects(state),
    (effects => {BrowserModel.accepted(False{}, first, state) == BrowserModel.Decision{state,
      List.append(&2, Browser.Effect, first, effects)} : BrowserModel.Decision}),
    {==}, Rule.pending_frame_effects_expected(state),
    Equal.sym(+List<Browser.Effect>, BrowserModel.pending_frame_effects(state),
      Rule.pending_frame_effects_expected(state), Rule.pending_frame_effects(state)))

def Rule.rebuilt_frame_decision(first, state): {==}

def inspection_product(+stored: Browser.State, +displayed: Maybe<&2, BrowserModel.Published>) ->
  {BrowserModel.render_inspection_owned(False{}, stored, displayed) == Rule.inspection_owned_expected(False{}, stored, displayed) : BrowserModel.RenderInspection}:
  match stored:
    case Browser.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{world, semantic, scope, basis, published_frame}}: {==}
    case Browser.State{Web.State{application, generation, Rendered.Realized{observed_generation, Rendered.Frame{viewport, elements, focused, tabs, native_focus}}, environment, font}, sequence, ticket, pending, receipt}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{world, semantic, scope, basis, published_frame}}: {==}
    case Browser.State{Web.State{application, generation, Rendered.Unmet{observed_generation, Rendered.Frame{viewport, elements, focused, tabs, native_focus}, violations}, environment, font}, sequence, ticket, pending, receipt}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{world, semantic, scope, basis, published_frame}}: {==}

def inspection_owned(+utility: Bool, +stored: Browser.State, +displayed: Maybe<&2, BrowserModel.Published>) ->
  {BrowserModel.render_inspection_owned(utility, stored, displayed) == Rule.inspection_owned_expected(utility, stored, displayed) : BrowserModel.RenderInspection}:
  match utility:
    case True{}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{world, semantic, scope, basis, frame}}: {==}
    case False{}: inspection_product(stored, displayed)

def Rule.render_inspection(model_state):
  BrowserModel.State{+stored, +serial, +anchors, +lifecycle, +displayed} = model_state
  inspection_owned(BrowserModel.auxiliary_owned(BrowserModel.State{stored, serial, anchors, lifecycle, displayed}), stored, displayed)

def state_ready_document_evidence(+model_state: BrowserModel.State, +rendering_capacity: Nat, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface) ->
  Rule.ready_document_claim(BrowserModel.with_displayed(Some{BrowserModel.published(world, layout_capacity, BrowserModel.legacy(model_state), semantic)}, BrowserModel.with_lifecycle(BrowserModel.Displaying{layout_capacity, engine, semantic}, model_state)), rendering_capacity, layout_capacity, engine, world, semantic):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +original_2} = model_state
  ready_document(rendering_capacity, legacy, serial, anchors, layout_capacity, engine, world, semantic)

def state_blocked_publication_at_evidence(+model_state: BrowserModel.State, +capacity: Nat, +last_published: Nat, +problem: String) ->
  Rule.blocked_publication_claim_at(BrowserModel.with_lifecycle(BrowserModel.Blocked{problem}, model_state), capacity, last_published, problem):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  blocked_publication_at(capacity, last_published, legacy, serial, anchors, problem, displayed)

def Rule.evidence():
  Rule.Requirements{
    +shift => +identity => +initial => +restore => +occurrence => +basis => +semantic => +frame => +state => {==},
    Rule.native_fields_evidence,
    +frame => +state => frame_capture_program(frame, state),
    +key => +shift => +basis => +semantic => +frame => +state => {==},
    +received => +frame => +state => proof => stale_frames(received, frame, state, proof),
    +received => +tokens => +state => proof => stale_measurements(received, tokens, state, proof),
    state_ready_document_evidence,
    +key => +left => +top => +width => +height => +state => anchor_preserves_program(key, left, top, width, height, state),
    +capacity => +last_published => +state => existing => waiting => publication_preserves_pending_at(capacity, last_published, state, existing, waiting),
    state_blocked_publication_at_evidence,
    +capacity => +last_published => +state => existing => +ready => current => publication_current_at(capacity, last_published, state, existing, ready, current)}

def Rule.unconfirmed_publication_has_no_focus_feedback(document, fields, ticket, before, after):
  match before:
    case None{}: {==}
    case Some{target}:
      match after:
        case None{}: {==}
        case Some{target}: {==}

def Rule.retained_publication_has_no_focus_feedback(fields, ticket, before, after): {==}

def Rule.absent_focus_has_no_publication_feedback(publication, ticket, after):
  match publication:
    case BrowserModel.KeepPublished{fields}: {==}
    case BrowserModel.Publish{generation, document, fields}: {==}

def Rule.owned_focus_has_no_publication_feedback(publication, ticket, before, after):
  match publication:
    case BrowserModel.KeepPublished{fields}: {==}
    case BrowserModel.Publish{generation, document, fields}:
      match before:
        case None{}: {==}
        case Some{target}: {==}

def Rule.confirmed_publication_focus_loss(generation, document, fields, ticket, before, confirmed):
  Std.transport(Bool, True{},
    (ready => {BrowserModel.publication_focus_loss(ready, ticket, before) ==
      Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}} : Maybe<&2, Platform.Input>}),
    {==}, Bool.not(Nat.is_eq(generation, 0n)), confirmed)

def Rule.failure_message(key, axis, required, available, reason):
  match axis:
    case Allocation.InlineAxis{}:
      match reason:
        case Allocation.AuthoredRangeConflict{}: {==}
        case Allocation.InsufficientSpace{}: {==}
        case Allocation.AllocationBoundExceeded{budget}: {==}
    case Allocation.BlockAxis{}:
      match reason:
        case Allocation.AuthoredRangeConflict{}: {==}
        case Allocation.InsufficientSpace{}: {==}
        case Allocation.AllocationBoundExceeded{budget}: {==}

def Rule.infeasible_candidate_retries(index, state, failure): {==}

def Rule.infeasible_candidate_reports(model_state, index, failure):
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.selected_infeasible(failure, index, capacity, engine, state, semantic, round): {==}

def state_utility_publication_evidence(+model_state: BrowserModel.State, +world: Content.AllocatedWorld, +purpose: Utility.Purpose, +engine: World.Engine) ->
  {BrowserModel.utility_publish(world, purpose, engine, model_state) ==
        BrowserModel.Decision{BrowserModel.with_displayed(Some{BrowserModel.Published{world, BrowserModel.current_legacy_surface(BrowserModel.legacy(model_state)), Focus.Document{}, Native.Basis{Nil{}, Nil{}}, None{}}}, BrowserModel.with_lifecycle(BrowserModel.UtilityDisplaying{purpose, engine}, model_state)), Nil{}} : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def state_correlated_frame_evidence(+model_state: BrowserModel.State, +frame: Rendered.Frame, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface, +scope: Focus.Scope, +basis: Native.Basis, +old: Maybe<&2, Rendered.Frame>) ->
  {BrowserModel.correlated_frame_owned(True{}, frame, BrowserModel.with_displayed(Some{BrowserModel.Published{world, semantic, scope, basis, old}}, model_state)) ==
        BrowserModel.utility_frame_result(SourceFrame.check(world, frame), frame, BrowserModel.with_displayed(Some{BrowserModel.Published{world, semantic, scope, basis, old}}, model_state)) : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +original_1} = model_state
  {==}

def state_correlated_measurement_failure_evidence(+model_state: BrowserModel.State, +purpose: Utility.Purpose, +engine: World.Engine, +round: Nat, +reason: String) ->
  {BrowserModel.utility_measurement_failure(reason, BrowserModel.with_lifecycle(BrowserModel.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) ==
        BrowserModel.utility_fallback(reason, BrowserModel.with_lifecycle(BrowserModel.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  {==}

def state_rejected_frame_evidence(+model_state: BrowserModel.State, +first: Rendered.Violation, +rest: +List<Rendered.Violation>, +frame: Rendered.Frame) ->
  {BrowserModel.utility_frame_result(first <> rest, frame, model_state) ==
        BrowserModel.Decision{BrowserModel.with_displayed(None{}, BrowserModel.with_lifecycle(BrowserModel.UtilityRejected{"Frontend utility frame does not match its admitted source"}, model_state)), Nil{}} : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.recovery_evidence():
  Rule.RecoveryRequirements{
    Rule.frontend_utility_evidence(),
    FrameRules.source_frame_evidence(),
    +capacity => +lifecycle => +world => +font => {==},
    +capacity => +lifecycle => +font => {==},
    state_utility_publication_evidence,
    state_correlated_frame_evidence,
    +world => +purpose => +engine => +round => +glyph_only => +state => {==},
    state_correlated_measurement_failure_evidence,
    +frame => +state => {==},
    state_rejected_frame_evidence,
    +state => {==},
    +state => {==},
    +input => +state => {==}}

def update_payload(id: Nat, +selected_name: Maybe<&2, String>, +selected_workspace: J.Json, guidance: +List<J.Field>) ->
  {Browser.request_payload(M.UpdateProject{id, selected_name, selected_workspace, J.Object{guidance}}) ==
    Codec.command_json(M.UpdateProject{id, selected_name, selected_workspace, J.Null{}}) : J.Json}:
  match selected_name:
    case None{}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}
    case Some{selected}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}

def unrelated_pending(+entry: Browser.Pending, +rest: +List<Browser.Pending>, +ticket: Nat,
  distinct: {Nat.is_eq(Browser.ticket_of(entry), ticket) == False{} : Bool}) ->
  {Browser.remove(entry <> rest, ticket) == entry <> Browser.remove(rest, ticket) : +List<Browser.Pending>}:
  Browser.Pending{current, completion, command, origin, status} = entry
  Equal.cong(Bool, +List<Browser.Pending>,
    (hit => Browser.choose_removed(hit, Browser.Pending{current, completion, command, origin, status}, Browser.remove(rest, ticket))),
    Nat.is_eq(current, ticket), False{}, distinct)

def confirmation_failed_world(owned: Bool, reason: String, destination: U.Route, +program: M.World(), session: E.Session) ->
  {Rule.decision_world(E.complete_confirmation(owned, D.failure("command_not_submitted", reason), destination,
    E.Application{program, session})) == program : M.World()}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def rejected_world(completion: E.Completion, reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion,
    E.Application{program, session})) == program : M.World()}:
  match completion:
    case E.DirectCompletion{}: {==}
    case E.DraftCompletion{draft}: {==}
    case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, +previews, code, next_layer} = session
      confirmation_failed_world(E.confirmation_owned(layers, command, trigger, occurrence), reason, destination, program,
        E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer}, program))

def omission_step(+same: Bool, +name: String, +value: J.Json, +rest: +List<J.Field>,
  matching: {String.eq(name, "guidance") == same : Bool},
  absent: {J.find(rest, "guidance") == J.Null{} : J.Json}) ->
  {J.find(Request.kept_field(same, J.Field{name, value}, rest), "guidance") == J.Null{} : J.Json}:
  match same:
    case True{}: absent
    case False{}:
      Equal.trans(J.Json,
        J.choose_field(String.eq(name, "guidance"), value, J.find(rest, "guidance")),
        J.choose_field(False{}, value, J.find(rest, "guidance")), J.Null{},
        Equal.cong(Bool, J.Json, (hit => J.choose_field(hit, value, J.find(rest, "guidance"))),
          String.eq(name, "guidance"), False{}, matching), absent)

def owned_field_absent(+fields: +List<J.Field>) ->
  {J.find(Request.without_guidance(fields), "guidance") == J.Null{} : J.Json}:
  match fields:
    case Nil{}: {==}
    case Con{J.Field{+name, +value}, +rest}:
      omission_step(String.eq(name, "guidance"), name, value, Request.without_guidance(rest), {==}, owned_field_absent(rest))

def state_current_world_evidence(+model_state: E.Application, completion: E.Completion, reason: String) ->
  {Rule.decision_world(E.complete_command(E.program(model_state), D.failure("command_not_submitted", reason), completion, model_state)) == E.program(model_state) : M.World()}:
  E.Application{+program, +session} = model_state
  rejected_world(completion, reason, program, session)

def state_settlement_evidence(+model_state: Browser.State, ticket: Nat, completion: E.Completion, command: J.Json, origin: String, status: Browser.RequestStatus, reason: String) ->
  {Browser.rejected_pending(Some{Browser.Pending{ticket, completion, command, origin, status}}, reason,
          Browser.with_receipt(None{}, model_state)) ==
          Browser.completion_receipt(completion, Receipt.from_reply(ticket, origin, D.failure("command_not_submitted", reason)), Browser.product_input(Product.CommandCompleted{Browser.program(Browser.with_receipt(None{}, model_state)),
            D.failure("command_not_submitted", reason), completion},
            Browser.with_receipt(None{}, Browser.with_pending(Browser.remove(Browser.pending(model_state), ticket), model_state)))) : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  {==}

def state_stale_evidence(+model_state: Browser.State, +ticket: Nat, reason: String, stale: {Browser.find(Browser.pending(model_state), ticket) == None{} : Maybe<&2, Browser.Pending>}) ->
  {Browser.command_rejected(ticket, reason, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, model_state), Nil{}} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  Equal.cong(Maybe<&2, Browser.Pending>, Browser.Decision,
    (found => Browser.rejected_pending(found, reason, Browser.State{web, sequence, next, pending, None{}})),
    Browser.find(pending, ticket), None{}, stale)

def state_uncertain_evidence(+model_state: Browser.State, ticket: Nat, reason: String) ->
  {Browser.failed_completion(ticket, reason, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(Browser.uncertain_pending(Browser.pending(model_state), ticket, reason), model_state)), Nil{}} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  {==}

def Rule.request_evidence():
  Rule.RequestRequirements{
    state_current_world_evidence,
    owned_field_absent,
    profile => reasoning => message => fields => {==},
    id => count => messages => fields => {==},
    name => workspace => guidance => {==},
    update_payload,
    id => revision => name => profile => reasoning => instructions => fields => concurrency => {==},
    +name => +value => +rest => unrelated =>
      Equal.cong(Bool, +List<J.Field>,
        (owned => Request.kept_field(owned, J.Field{name, value}, Request.without_guidance(rest))),
        String.eq(name, "guidance"), False{}, unrelated),
    state_settlement_evidence,
    state_stale_evidence,
    +pending => +ticket => consumed_ticket(pending, ticket),
    unrelated_pending,
    revision => body => feedback => directory_entry => submitted => reason => {==},
    state_uncertain_evidence,
    id => message => {==}}
