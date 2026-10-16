import ../layout/natural-size.bend as NaturalSize
import ../controls/PROGRAM.bend as ControlsProgram
import ../layout/ADAPTATION.bend as Adaptation
import ../controls/NAVIGATION.bend as Navigation
import Base
import ../../interaction/session/PROOF.bend as SessionProof
import ../../harness/INVARIANTS.bend as WorldInvariant
import ../../interaction/session/CONTRACT.bend as SessionRule
import ../document/MODEL.bend as CodeObservation
import ../../interaction/services/MODEL.bend as Services
import ../../bendlib/categories.bend as Categories
import ../../MODEL.bend as Model
import ../document/MODEL.bend as Document
import ./SEMANTICS.bend as Browser
import ./CONTRACT.bend as Rule
import ../../interaction/submission/MODEL.bend as Receipt
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ./frontend-utility.bend as Utility
import ./utility-proof.bend as UtilityProof
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

def publication_focus_spec(+ready: Bool, ticket: Nat, before: Focus.Target) -> Maybe<&2, Platform.Input>:
  match ready:
    case True{}: Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}}
    case False{}: None{}

def publication_focus_checked(+generation: Nat, +ticket: Nat, +before: Focus.Target, +ready: Bool,
  observed: {Bool.not(Nat.is_eq(generation, 0n)) == ready : Bool}) ->
  {BrowserModel.publication_focus_admitted(Categories.admit_checked(BrowserModel.PublicationFocusCandidate, BrowserModel.publication_focus_predicate, BrowserModel.PublicationFocusCandidate{generation, ticket, before}, ready, observed)) == publication_focus_spec(ready, ticket, before) : Maybe<&2, Platform.Input>}:
  match ready:
    case True{}: {==}
    case False{}: {==}

def publication_focus_equation(+generation: Nat, +ticket: Nat, +before: Focus.Target) ->
  {BrowserModel.publication_focus_current(generation, ticket, before) == publication_focus_spec(Bool.not(Nat.is_eq(generation, 0n)), ticket, before) : Maybe<&2, Platform.Input>}:
  publication_focus_checked(generation, ticket, before, Bool.not(Nat.is_eq(generation, 0n)), {==})

def edit_text_owned_spec(+allowed: Bool, +key: String, +text: String, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.edit_text(key, text, BrowserModel.legacy(state)), state)

def edit_text_checked(+key: String, +text: String, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.edit_text_predicate(BrowserModel.TextEditCandidate{key, text, state}) == allowed : Bool}) ->
  {BrowserModel.edit_text_admitted(Categories.admit_checked(BrowserModel.TextEditCandidate, BrowserModel.edit_text_predicate, BrowserModel.TextEditCandidate{key, text, state}, allowed, observed), state) == edit_text_owned_spec(allowed, key, text, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def edit_text_equation(+key: String, +text: String, +state: BrowserModel.State) ->
  {BrowserModel.edit_text(key, text, state) == edit_text_owned_spec(BrowserModel.field_owned(key, state), key, text, state) : BrowserModel.Decision}:
  edit_text_checked(key, text, state, BrowserModel.field_owned(key, state), {==})

def edit_structured_text_owned_spec(+allowed: Bool, +key: String, +text: String, +parsed: Maybe<&2, J.Json>, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.edit_structured_text(key, text, parsed, BrowserModel.legacy(state)), state)

def edit_structured_text_checked(+key: String, +text: String, +parsed: Maybe<&2, J.Json>, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.edit_structured_text_predicate(BrowserModel.StructuredTextEditCandidate{key, text, parsed, state}) == allowed : Bool}) ->
  {BrowserModel.edit_structured_text_admitted(Categories.admit_checked(BrowserModel.StructuredTextEditCandidate, BrowserModel.edit_structured_text_predicate, BrowserModel.StructuredTextEditCandidate{key, text, parsed, state}, allowed, observed), state) == edit_structured_text_owned_spec(allowed, key, text, parsed, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def edit_structured_text_equation(+key: String, +text: String, +parsed: Maybe<&2, J.Json>, +state: BrowserModel.State) ->
  {BrowserModel.edit_structured_text(key, text, parsed, state) == edit_structured_text_owned_spec(BrowserModel.structured_text_owned(key, state), key, text, parsed, state) : BrowserModel.Decision}:
  edit_structured_text_checked(key, text, parsed, state, BrowserModel.structured_text_owned(key, state), {==})

def confirm_text_owned_spec(+allowed: Bool, +key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, BrowserModel.legacy(state)), state)

def confirm_text_checked(+key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.confirm_text_predicate(BrowserModel.TextConfirmationCandidate{key, keyboard, composing, control, alt, shift, meta, state}) == allowed : Bool}) ->
  {BrowserModel.confirm_text_admitted(Categories.admit_checked(BrowserModel.TextConfirmationCandidate, BrowserModel.confirm_text_predicate, BrowserModel.TextConfirmationCandidate{key, keyboard, composing, control, alt, shift, meta, state}, allowed, observed), state) == confirm_text_owned_spec(allowed, key, keyboard, composing, control, alt, shift, meta, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def confirm_text_equation(+key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: BrowserModel.State) ->
  {BrowserModel.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == confirm_text_owned_spec(BrowserModel.field_owned(key, state), key, keyboard, composing, control, alt, shift, meta, state) : BrowserModel.Decision}:
  confirm_text_checked(key, keyboard, composing, control, alt, shift, meta, state, BrowserModel.field_owned(key, state), {==})

def edit_toggle_owned_spec(+allowed: Bool, +key: String, +enabled: Bool, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.edit_toggle(key, enabled, BrowserModel.legacy(state)), state)

def edit_toggle_checked(+key: String, +enabled: Bool, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.edit_toggle_predicate(BrowserModel.ToggleEditCandidate{key, enabled, state}) == allowed : Bool}) ->
  {BrowserModel.edit_toggle_admitted(Categories.admit_checked(BrowserModel.ToggleEditCandidate, BrowserModel.edit_toggle_predicate, BrowserModel.ToggleEditCandidate{key, enabled, state}, allowed, observed), state) == edit_toggle_owned_spec(allowed, key, enabled, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def edit_toggle_equation(+key: String, +enabled: Bool, +state: BrowserModel.State) ->
  {BrowserModel.edit_toggle(key, enabled, state) == edit_toggle_owned_spec(BrowserModel.field_owned(key, state), key, enabled, state) : BrowserModel.Decision}:
  edit_toggle_checked(key, enabled, state, BrowserModel.field_owned(key, state), {==})

def attach_owned_spec(+allowed: Bool, +key: String, +file: Services.SelectedFile, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.attach(key, file, BrowserModel.legacy(state)), state)

def attach_checked(+key: String, +file: Services.SelectedFile, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.attach_predicate(BrowserModel.AttachmentCandidate{key, file, state}) == allowed : Bool}) ->
  {BrowserModel.attach_admitted(Categories.admit_checked(BrowserModel.AttachmentCandidate, BrowserModel.attach_predicate, BrowserModel.AttachmentCandidate{key, file, state}, allowed, observed), state) == attach_owned_spec(allowed, key, file, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def attach_equation(+key: String, +file: Services.SelectedFile, +state: BrowserModel.State) ->
  {BrowserModel.attach(key, file, state) == attach_owned_spec(BrowserModel.field_owned(key, state), key, file, state) : BrowserModel.Decision}:
  attach_checked(key, file, state, BrowserModel.field_owned(key, state), {==})

def received_frame_spec(+allowed: Bool, +received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.correlated_frame(frame, state)

def receive_frame_checked(+received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.receive_frame_predicate(BrowserModel.FrameCandidate{received, frame, state}) == allowed : Bool}) ->
  {BrowserModel.receive_frame_admitted(Categories.admit_checked(BrowserModel.FrameCandidate, BrowserModel.receive_frame_predicate, BrowserModel.FrameCandidate{received, frame, state}, allowed, observed), state) == received_frame_spec(allowed, received, frame, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def receive_frame_equation(+received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State) ->
  {BrowserModel.receive_frame(received, frame, state) == received_frame_spec(BrowserModel.frame_owned(received, state), received, frame, state) : BrowserModel.Decision}:
  receive_frame_checked(received, frame, state, BrowserModel.frame_owned(received, state), {==})

def measured_current_spec(+allowed: Bool, +ticket: BrowserModel.MeasurementTicket, +receipts: +List<String>, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.measured_pending(receipts, state)

def physical_measured_checked(+ticket: BrowserModel.MeasurementTicket, +receipts: +List<String>, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.physical_measured_predicate(BrowserModel.MeasurementCandidate{ticket, receipts, state}) == allowed : Bool}) ->
  {BrowserModel.physical_measured_admitted(Categories.admit_checked(BrowserModel.MeasurementCandidate, BrowserModel.physical_measured_predicate, BrowserModel.MeasurementCandidate{ticket, receipts, state}, allowed, observed), state) == measured_current_spec(allowed, ticket, receipts, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def physical_measured_equation(+ticket: BrowserModel.MeasurementTicket, +receipts: +List<String>, +state: BrowserModel.State) ->
  {BrowserModel.physical_measured(ticket, receipts, state) == measured_current_spec(BrowserModel.measurement_owned(ticket, state), ticket, receipts, state) : BrowserModel.Decision}:
  physical_measured_checked(ticket, receipts, state, BrowserModel.measurement_owned(ticket, state), {==})

def native_focus_if_owned_spec(+allowed: Bool, +generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(False{}, Browser.native(Web.PlatformInput{Platform.ContentFocusObserved{owner, identity}}, BrowserModel.legacy(state)), state)

def native_focus_observed_checked(+generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.native_focus_observed_predicate(BrowserModel.NativeObservationCandidate{generation, owner, identity, state}) == allowed : Bool}) ->
  {BrowserModel.native_focus_observed_admitted(Categories.admit_checked(BrowserModel.NativeObservationCandidate, BrowserModel.native_focus_observed_predicate, BrowserModel.NativeObservationCandidate{generation, owner, identity, state}, allowed, observed), state) == native_focus_if_owned_spec(allowed, generation, owner, identity, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def native_focus_observed_equation(+generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State) ->
  {BrowserModel.native_focus_observed(generation, owner, identity, state) == native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state) : BrowserModel.Decision}:
  native_focus_observed_checked(generation, owner, identity, state, BrowserModel.native_observation_owned(generation, owner, identity, state), {==})

def measurement_failed_spec(+allowed: Bool, +ticket: BrowserModel.MeasurementTicket, +reason: String, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.utility_measurement_failure(reason, state)

def physical_measurement_failed_checked(+ticket: BrowserModel.MeasurementTicket, +reason: String, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.physical_measurement_failed_predicate(BrowserModel.MeasurementFailureCandidate{ticket, reason, state}) == allowed : Bool}) ->
  {BrowserModel.physical_measurement_failed_admitted(Categories.admit_checked(BrowserModel.MeasurementFailureCandidate, BrowserModel.physical_measurement_failed_predicate, BrowserModel.MeasurementFailureCandidate{ticket, reason, state}, allowed, observed), state) == measurement_failed_spec(allowed, ticket, reason, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def physical_measurement_failed_equation(+ticket: BrowserModel.MeasurementTicket, +reason: String, +state: BrowserModel.State) ->
  {BrowserModel.physical_measurement_failed(ticket, reason, state) == measurement_failed_spec(BrowserModel.measurement_owned(ticket, state), ticket, reason, state) : BrowserModel.Decision}:
  physical_measurement_failed_checked(ticket, reason, state, BrowserModel.measurement_owned(ticket, state), {==})

def update_spec(owned: Bool, binding: Native.Binding, found: Maybe<&2, SurfaceTypes.Node>) -> +List<Native.Update>:
  match owned:
    case False{}: Nil{}
    case True{}: Native.update_found(found, binding)

def update_checked(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>, +owned: Bool,
  observed: {Native.owned_node(binding, found) == owned : Bool}) ->
  {Native.update_admitted(Categories.admit_checked(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found}, owned, observed)) == update_spec(owned, binding, found) : +List<Native.Update>}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def update_equation(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>) ->
  {Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found})) == update_spec(Native.owned_node(binding, found), binding, found) : +List<Native.Update>}:
  update_checked(binding, found, Native.owned_node(binding, found), {==})

def code_sources_spec(+qualified: Bool, +generation: Nat, +observations: +List<CodeObservation.Observation>, +state: BrowserModel.State) -> BrowserModel.Decision:
  match qualified:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, BrowserModel.code_sources_fold(observations, Browser.Decision{BrowserModel.legacy(state), Nil{}}), state)

def code_sources_checked(+generation: Nat, +observations: +List<CodeObservation.Observation>, +state: BrowserModel.State, +qualified: Bool,
  observed: {BrowserModel.code_batch_qualified(generation, observations, state) == qualified : Bool}) ->
  {BrowserModel.code_sources_admitted(Categories.admit_checked(BrowserModel.CodeSourcesCandidate, BrowserModel.code_sources_predicate, BrowserModel.CodeSourcesCandidate{generation, observations, state}, qualified, observed), state) == code_sources_spec(qualified, generation, observations, state) : BrowserModel.Decision}:
  match qualified:
    case False{}: {==}
    case True{}: {==}

def code_sources_equation(+generation: Nat, +observations: +List<CodeObservation.Observation>, +state: BrowserModel.State) ->
  {BrowserModel.code_sources(generation, observations, state) == code_sources_spec(BrowserModel.code_batch_qualified(generation, observations, state), generation, observations, state) : BrowserModel.Decision}:
  code_sources_checked(generation, observations, state, BrowserModel.code_batch_qualified(generation, observations, state), {==})

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
  Equal.trans(+List<Native.Update>, Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found})),
    update_spec(Native.owned_node(binding, found), binding, found), Nil{}, update_equation(binding, found),
    Std.transport(Bool, False{},
      (owned => {update_spec(owned, binding, found) == Nil{} : +List<Native.Update>}),
      {==}, Native.owned_node(binding, found), proof))

def matching(+binding: Native.Binding, +node: SurfaceTypes.Node,
  proof: {Native.owned_node(binding, Some{node}) == True{} : Bool}) -> Rule.matching_claim(binding, node):
  match binding node:
    case Native.Binding{+key, +kind, identity, original} SurfaceTypes.Node{current, semantic, label, role, +meaning, children}:
      Equal.trans(+List<Native.Update>, Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, Some{node}})),
        update_spec(Native.owned_node(binding, Some{node}), binding, Some{node}), Native.projected(key, kind, semantic, meaning), update_equation(binding, Some{node}),
        Std.transport(Bool, True{},
          (owned => {update_spec(owned, Native.Binding{key, kind, identity, original}, Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}),
          {==}, Native.owned_node(binding, Some{node}), proof))

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
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_text(key, text, state), edit_text_owned_spec(BrowserModel.field_owned(key, state), key, text, state),
    BrowserModel.Decision{state, Nil{}}, edit_text_equation(key, text, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_text_owned_spec(allowed, key, text, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.edit_text_accepted(key, text, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_text(key, text, state), edit_text_owned_spec(BrowserModel.field_owned(key, state), key, text, state),
    BrowserModel.accept(True{}, Browser.edit_text(key, text, BrowserModel.legacy(state)), state), edit_text_equation(key, text, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_text_owned_spec(allowed, key, text, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

def Rule.edit_structured_text_rejected(key, text, parsed, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_structured_text(key, text, parsed, state), edit_structured_text_owned_spec(BrowserModel.structured_text_owned(key, state), key, text, parsed, state),
    BrowserModel.Decision{state, Nil{}}, edit_structured_text_equation(key, text, parsed, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_structured_text_owned_spec(allowed, key, text, parsed, state)),
      BrowserModel.structured_text_owned(key, state), False{}, owned))

def Rule.edit_structured_text_accepted(key, text, parsed, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_structured_text(key, text, parsed, state), edit_structured_text_owned_spec(BrowserModel.structured_text_owned(key, state), key, text, parsed, state),
    BrowserModel.accept(True{}, Browser.edit_structured_text(key, text, parsed, BrowserModel.legacy(state)), state), edit_structured_text_equation(key, text, parsed, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_structured_text_owned_spec(allowed, key, text, parsed, state)),
      BrowserModel.structured_text_owned(key, state), True{}, owned))

def Rule.confirm_text_rejected(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.confirm_text(key, keyboard, composing, control, alt, shift, meta, state), confirm_text_owned_spec(BrowserModel.field_owned(key, state), key, keyboard, composing, control, alt, shift, meta, state),
    BrowserModel.Decision{state, Nil{}}, confirm_text_equation(key, keyboard, composing, control, alt, shift, meta, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => confirm_text_owned_spec(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.confirm_text_accepted(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.confirm_text(key, keyboard, composing, control, alt, shift, meta, state), confirm_text_owned_spec(BrowserModel.field_owned(key, state), key, keyboard, composing, control, alt, shift, meta, state),
    BrowserModel.accept(True{}, Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, BrowserModel.legacy(state)), state), confirm_text_equation(key, keyboard, composing, control, alt, shift, meta, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => confirm_text_owned_spec(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

def Rule.edit_toggle_rejected(key, enabled, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_toggle(key, enabled, state), edit_toggle_owned_spec(BrowserModel.field_owned(key, state), key, enabled, state),
    BrowserModel.Decision{state, Nil{}}, edit_toggle_equation(key, enabled, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_toggle_owned_spec(allowed, key, enabled, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.edit_toggle_accepted(key, enabled, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_toggle(key, enabled, state), edit_toggle_owned_spec(BrowserModel.field_owned(key, state), key, enabled, state),
    BrowserModel.accept(True{}, Browser.edit_toggle(key, enabled, BrowserModel.legacy(state)), state), edit_toggle_equation(key, enabled, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_toggle_owned_spec(allowed, key, enabled, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

def Rule.attach_rejected(key, file, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.attach(key, file, state), attach_owned_spec(BrowserModel.field_owned(key, state), key, file, state),
    BrowserModel.Decision{state, Nil{}}, attach_equation(key, file, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => attach_owned_spec(allowed, key, file, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.attach_accepted(key, file, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.attach(key, file, state), attach_owned_spec(BrowserModel.field_owned(key, state), key, file, state),
    BrowserModel.accept(True{}, Browser.attach(key, file, BrowserModel.legacy(state)), state), attach_equation(key, file, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => attach_owned_spec(allowed, key, file, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

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
  Equal.trans(BrowserModel.Decision, BrowserModel.receive_frame(received, frame, state), received_frame_spec(BrowserModel.frame_owned(received, state), received, frame, state),
    BrowserModel.Decision{state, Nil{}}, receive_frame_equation(received, frame, state),
    Std.transport(Bool, False{},
      (owned => {received_frame_spec(owned, received, frame, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
      {==}, BrowserModel.frame_owned(received, state), proof))

def stale_measurements(+received: BrowserModel.MeasurementTicket, +tokens: +List<String>, +state: BrowserModel.State,
  proof: {BrowserModel.measurement_owned(received, state) == False{} : Bool}) ->
  Rule.stale_measurements_claim(received, tokens, state):
  Equal.trans(BrowserModel.Decision, BrowserModel.physical_measured(received, tokens, state), measured_current_spec(BrowserModel.measurement_owned(received, state), received, tokens, state),
    BrowserModel.Decision{state, Nil{}}, physical_measured_equation(received, tokens, state),
    Std.transport(Bool, False{},
      (owned => {measured_current_spec(owned, received, tokens, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
      {==}, BrowserModel.measurement_owned(received, state), proof))

def ready_document(+rendering_capacity: Nat, +legacy: Browser.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface, +attention: Navigation.Attention) ->
  Rule.ready_document_claim(BrowserModel.State{legacy, serial, anchors, BrowserModel.Displaying{layout_capacity, engine, semantic}, Some{BrowserModel.published(world, layout_capacity, legacy, semantic)}, attention}, rendering_capacity, layout_capacity, engine, world, semantic):
  match legacy:
    case Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}:
      match world:
        case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def anchor_preserves_program(+key: String, +left: AnchorGeometry.Origin, +top: AnchorGeometry.Origin, +width: Nat, +height: Nat, +state: BrowserModel.State) ->
  Rule.anchor_preserves_program_claim(key, left, top, width, height, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
      match legacy:
        case Browser.State{web, sequence, ticket, pending, receipt}:
          match web:
            case Web.State{application, generation, realization, environment, font}:
              match environment:
                case Design.Environment{viewport, dark, root}:
                  match viewport:
                    case Design.Viewport{viewport_width, viewport_height}: {==}

def policy_spec(+accepted: Bool, +capacity: Nat, +state: BrowserModel.State) -> BrowserModel.Publication:
  match accepted:
    case True{}: BrowserModel.KeepPublished{BrowserModel.native_updates(state)}
    case False{}: BrowserModel.published_document(capacity, state)

def policy_checked(+capacity: Nat, +last: Nat, +state: BrowserModel.State, +accepted: Bool,
  observed: {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == accepted : Bool}) ->
  {BrowserModel.publication_policy_admitted(capacity, Categories.admit_checked(BrowserModel.PublicationCandidate, BrowserModel.publication_policy_predicate, BrowserModel.PublicationCandidate{capacity, last, state}, accepted, observed), state) == policy_spec(accepted, capacity, state) : BrowserModel.Publication}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def policy_equation(+capacity: Nat, +last: Nat, +state: BrowserModel.State) ->
  {BrowserModel.publication_policy_at(capacity, last, state) == policy_spec(BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), capacity, state) : BrowserModel.Publication}:
  policy_checked(capacity, last, state, BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), {==})

def keep_policy(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  accepted: {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == True{} : Bool}) ->
  {BrowserModel.publication_policy_at(capacity, last, state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}:
  Equal.trans(BrowserModel.Publication, BrowserModel.publication_policy_at(capacity, last, state),
    policy_spec(BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), capacity, state),
    BrowserModel.KeepPublished{BrowserModel.native_updates(state)}, policy_equation(capacity, last, state),
    Equal.cong(Bool, BrowserModel.Publication, value => policy_spec(value, capacity, state),
      BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), True{}, accepted))

def boolean_pending(+existing: Bool, current: Bool) -> {existing && (Bool.not(False{}) || current) == existing : Bool}:
  match existing:
    case True{}: {==}
    case False{}: {==}

def pending_predicate(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  waiting: {Rule.publication_pending(state) == True{} : Bool}) ->
  {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == Bool.not(Nat.is_eq(last, 0n)) : Bool}:
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: boolean_pending(Bool.not(Nat.is_eq(last, 0n)), Nat.is_eq(BrowserModel.displayed_generation(state), last))
        case BrowserModel.WaitingFont{}: boolean_pending(Bool.not(Nat.is_eq(last, 0n)), Nat.is_eq(BrowserModel.displayed_generation(state), last))
        case BrowserModel.Measuring{index, layout_capacity, engine, semantic, round}: boolean_pending(Bool.not(Nat.is_eq(last, 0n)), Nat.is_eq(BrowserModel.displayed_generation(state), last))
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: boolean_pending(Bool.not(Nat.is_eq(last, 0n)), Nat.is_eq(BrowserModel.displayed_generation(state), last))
        case BrowserModel.UtilityDisplaying{purpose, engine}: Logic.impossible(
          {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == Bool.not(Nat.is_eq(last, 0n)) : Bool}, waiting)
        case BrowserModel.UtilityRejected{problem}: Logic.impossible(
          {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == Bool.not(Nat.is_eq(last, 0n)) : Bool}, waiting)
        case BrowserModel.Displaying{layout_capacity, engine, semantic}: Logic.impossible(
          {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == Bool.not(Nat.is_eq(last, 0n)) : Bool}, waiting)
        case BrowserModel.Blocked{problem}: Logic.impossible(
          {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == Bool.not(Nat.is_eq(last, 0n)) : Bool}, waiting)


def pending_publication_at(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  waiting: {Rule.publication_pending(state) == True{} : Bool}) ->
  {BrowserModel.publication_policy_at(capacity, last, state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}:
  keep_policy(capacity, last, state,
    Equal.trans(Bool, BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), Bool.not(Nat.is_eq(last, 0n)), True{}, pending_predicate(capacity, last, state, waiting), existing))

def publication_preserves_pending_at(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  waiting: {Rule.publication_pending(state) == True{} : Bool}) -> Rule.publication_preserves_pending_claim_at(capacity, last, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.WaitingFont{}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.Measuring{index, layout_capacity, engine, semantic, round}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.UtilityDisplaying{purpose, engine}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)
        case BrowserModel.UtilityRejected{problem}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)
        case BrowserModel.Displaying{layout_capacity, engine, semantic}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)
        case BrowserModel.Blocked{problem}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)

def blocked_publication_at(+capacity: Nat, +last_published: Nat, +legacy: Browser.State, +serial: Nat,
  +anchors: +List<Shell.Anchor>, +problem: String, +displayed: Maybe<&2, BrowserModel.Published>, +attention: Navigation.Attention) -> Rule.blocked_publication_claim_at(BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed, attention}, capacity, last_published, problem):
  {==}

def current_predicate(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  ready: {BrowserModel.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(BrowserModel.displayed_generation(state), last) == True{} : Bool}) ->
  {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == True{} : Bool}:
  Std.transport(Bool, True{},
    (has_existing => {has_existing && (Bool.not(BrowserModel.display_ready(state)) || Nat.is_eq(BrowserModel.displayed_generation(state), last)) == True{} : Bool}),
    Std.transport(Bool, True{},
      (is_ready => {True{} && (Bool.not(is_ready) || Nat.is_eq(BrowserModel.displayed_generation(state), last)) == True{} : Bool}),
      Std.transport(Bool, True{},
        (is_current => {True{} && (Bool.not(True{}) || is_current) == True{} : Bool}),
        {==}, Nat.is_eq(BrowserModel.displayed_generation(state), last), current),
      BrowserModel.display_ready(state), ready), Bool.not(Nat.is_eq(last, 0n)), existing)

def publication_current_at(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  +ready: {BrowserModel.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(BrowserModel.displayed_generation(state), last) == True{} : Bool}) -> Rule.publication_current_claim_at(capacity, last, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
      match lifecycle:
        case BrowserModel.UtilityDisplaying{purpose, engine}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
        case BrowserModel.Displaying{layout_capacity, engine, semantic}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
        case BrowserModel.WaitingEnvironment{}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)
        case BrowserModel.WaitingFont{}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)
        case BrowserModel.Measuring{index, layout_capacity, engine, semantic, round}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)
        case BrowserModel.UtilityRejected{problem}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)
        case BrowserModel.Blocked{problem}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)

def frame_capture_program(+frame: Rendered.Frame, +state: BrowserModel.State) -> Rule.frame_capture_program_claim(frame, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{world, semantic, scope, basis, old}}: {==}

def Rule.forwarded_frame_uses_published_surface(model_state, world, semantic, scope, basis, old, frame):
  BrowserModel.State{+stored, +serial, +anchors, +lifecycle, +original_1, attention} = model_state
  {==}

def Rule.failed_font_candidate_blocked(model_state, font_generation, scale, index):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +realization, +environment, +original_1}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
  {==}

def Rule.unmet_frame_status(model_state, semantic, frame_generation, frame, violations, capacity, engine):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +original_3, +displayed, attention} = model_state
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
  Equal.trans(BrowserModel.Decision, BrowserModel.native_focus_observed(generation, owner, identity, state), native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state),
    BrowserModel.Decision{state, Nil{}}, native_focus_observed_equation(generation, owner, identity, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (owned => native_focus_if_owned_spec(owned, generation, owner, identity, state)),
      BrowserModel.native_observation_owned(generation, owner, identity, state), False{}, rejected))

def Rule.missing_native_frame_rejects(semantic, owner, identity): {==}

def stale_native_focus_spec(+generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State,
  stale: {BrowserModel.frame_owned(generation, state) == False{} : Bool}) ->
  {native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}:
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
          Equal.cong(Bool, BrowserModel.Decision,
            (current => native_focus_if_owned_spec(current && BrowserModel.source_delegates(source, owner) &&
              Rendered.read_only(InterfaceView.find_node(InterfaceView.active_nodes(semantic), owner)) && BrowserModel.native_frame_owned(frame, semantic, owner, identity), generation, owner, identity, state)),
            Nat.is_eq(generation, published), False{}, stale)

def Rule.stale_native_focus_preserves_state(generation, owner, identity, state, stale):
  Equal.trans(BrowserModel.Decision, BrowserModel.native_focus_observed(generation, owner, identity, state), native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state),
    BrowserModel.Decision{state, Nil{}}, native_focus_observed_equation(generation, owner, identity, state),
    stale_native_focus_spec(generation, owner, identity, state, stale))

def Rule.stale_measurement_failure(ticket, reason, state, stale):
  Equal.trans(BrowserModel.Decision, BrowserModel.physical_measurement_failed(ticket, reason, state), measurement_failed_spec(BrowserModel.measurement_owned(ticket, state), ticket, reason, state),
    BrowserModel.Decision{state, Nil{}}, physical_measurement_failed_equation(ticket, reason, state),
    Std.transport(Bool, False{},
      (owned => {measurement_failed_spec(owned, ticket, reason, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
      {==}, BrowserModel.measurement_owned(ticket, state), stale))

def Rule.current_measurement_failure(ticket, reason, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.physical_measurement_failed(ticket, reason, state), measurement_failed_spec(BrowserModel.measurement_owned(ticket, state), ticket, reason, state),
    BrowserModel.utility_measurement_failure(reason, state), physical_measurement_failed_equation(ticket, reason, state),
    Std.transport(Bool, True{},
      (accepted => {measurement_failed_spec(accepted, ticket, reason, state) == BrowserModel.utility_measurement_failure(reason, state) : BrowserModel.Decision}),
      {==}, BrowserModel.measurement_owned(ticket, state), owned))

def Rule.measurement_ownership_only_measuring(ticket, state, owned):
  match ticket:
    case BrowserModel.MeasurementTicket{generation, received_round}:
      match state:
        case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
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
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: {==}
        case BrowserModel.WaitingFont{}: {==}
        case BrowserModel.Displaying{capacity, engine, semantic}: {==}
        case BrowserModel.Blocked{problem}: {==}
        case BrowserModel.UtilityDisplaying{purpose, engine}: {==}
        case BrowserModel.UtilityRejected{problem}: {==}
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}:
          Logic.impossible({BrowserModel.measurement_request(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention}) == None{} : Maybe<&2, BrowserModel.MeasurementRequest>}, Equal.sym(Bool, True{}, False{}, inactive))
        case BrowserModel.Measuring{index, capacity, engine, semantic, round}:
          Logic.impossible(
            {BrowserModel.measurement_request(BrowserModel.State{legacy, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed, attention}) == None{} : Maybe<&2, BrowserModel.MeasurementRequest>},
            Equal.sym(Bool, True{}, False{}, inactive))

def Rule.measurement_wrong_round(model_state, generation, received_round, round, index, capacity, engine, semantic, same_generation, stale_round):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention} = model_state
  Std.transport(Bool, True{},
    (same => {same && Nat.is_eq(received_round, round) == False{} : Bool}),
    Std.transport(Bool, False{},
      (same_round => {True{} && same_round == False{} : Bool}),
      {==}, Nat.is_eq(received_round, round), stale_round),
    Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))), same_generation)

def Rule.measurement_request_canonical(model_state, index, capacity, engine, semantic, round, generation, first, remaining, awaiting):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention} = model_state
  Std.transport(Plan.Plan, Plan.Awaiting{generation, first, remaining},
    (plan => {BrowserModel.measurement_request_plan(plan, World.snapshot_generation(World.snapshot(engine)), round) ==
      Some{BrowserModel.MeasurementRequest{BrowserModel.MeasurementTicket{World.snapshot_generation(World.snapshot(engine)), round}, Plan.Awaiting{generation, first, remaining}}} : Maybe<&2, BrowserModel.MeasurementRequest>}),
    {==}, World.plan(engine), awaiting)

def Rule.render_violations_unmet(model_state, observed_generation, frame, violations):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
  {==}

def Rule.render_violations_awaiting(model_state, observed_generation):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
  {==}

def Rule.render_violations_realized(model_state, observed_generation, frame):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
  {==}

def Rule.pending_frame_effects(state):
  match state:
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, None{}, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, None{}}}, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, Some{frame}}}, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.WaitingEnvironment{}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.WaitingFont{}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Blocked{problem}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.Realized{observed_generation, frame}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.Unmet{observed_generation, frame, violations}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, None{}, attention}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, published_semantic, scope, basis, frame}}, attention}: {==}

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
  BrowserModel.State{+stored, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
  inspection_owned(BrowserModel.auxiliary_owned(BrowserModel.State{stored, serial, anchors, lifecycle, displayed, attention}), stored, displayed)

def state_ready_document_evidence(+model_state: BrowserModel.State, +rendering_capacity: Nat, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface) ->
  Rule.ready_document_claim(BrowserModel.with_displayed(Some{BrowserModel.published(world, layout_capacity, BrowserModel.legacy(model_state), semantic)}, BrowserModel.with_lifecycle(BrowserModel.Displaying{layout_capacity, engine, semantic}, model_state)), rendering_capacity, layout_capacity, engine, world, semantic):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +original_2, attention} = model_state
  ready_document(rendering_capacity, legacy, serial, anchors, layout_capacity, engine, world, semantic, attention)

def state_blocked_publication_at_evidence(+model_state: BrowserModel.State, +capacity: Nat, +last_published: Nat, +problem: String) ->
  Rule.blocked_publication_claim_at(BrowserModel.with_lifecycle(BrowserModel.Blocked{problem}, model_state), capacity, last_published, problem):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention} = model_state
  blocked_publication_at(capacity, last_published, legacy, serial, anchors, problem, displayed, attention)

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
  Equal.trans(Maybe<&2, Platform.Input>, BrowserModel.publication_focus_current(generation, ticket, before),
    publication_focus_spec(Bool.not(Nat.is_eq(generation, 0n)), ticket, before), Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}},
    publication_focus_equation(generation, ticket, before),
    Std.transport(Bool, True{},
      (ready => {publication_focus_spec(ready, ticket, before) == Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}} : Maybe<&2, Platform.Input>}),
      {==}, Bool.not(Nat.is_eq(generation, 0n)), confirmed))

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
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
  {==}

def Rule.selected_infeasible(failure, index, capacity, engine, state, semantic, round): {==}

def state_utility_publication_evidence(+model_state: BrowserModel.State, +world: Content.AllocatedWorld, +purpose: Utility.Purpose, +engine: World.Engine) ->
  {BrowserModel.utility_publish(world, purpose, engine, model_state) ==
        BrowserModel.Decision{BrowserModel.with_displayed(Some{BrowserModel.Published{world, BrowserModel.current_legacy_surface(BrowserModel.legacy(model_state)), Focus.Document{}, Native.Basis{Nil{}, Nil{}}, None{}}}, BrowserModel.with_lifecycle(BrowserModel.UtilityDisplaying{purpose, engine}, model_state)), Nil{}} : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
  {==}

def state_correlated_frame_evidence(+model_state: BrowserModel.State, +frame: Rendered.Frame, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface, +scope: Focus.Scope, +basis: Native.Basis, +old: Maybe<&2, Rendered.Frame>) ->
  {BrowserModel.correlated_frame_owned(True{}, frame, BrowserModel.with_displayed(Some{BrowserModel.Published{world, semantic, scope, basis, old}}, model_state)) ==
        BrowserModel.utility_frame_result(world, frame, BrowserModel.with_displayed(Some{BrowserModel.Published{world, semantic, scope, basis, old}}, model_state)) : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +original_1, attention} = model_state
  {==}

def state_correlated_measurement_failure_evidence(+model_state: BrowserModel.State, +purpose: Utility.Purpose, +engine: World.Engine, +round: Nat, +reason: String) ->
  {BrowserModel.utility_measurement_failure(reason, BrowserModel.with_lifecycle(BrowserModel.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) ==
        BrowserModel.utility_fallback(reason, BrowserModel.with_lifecycle(BrowserModel.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention} = model_state
  {==}

def state_rejected_frame_evidence(+model_state: BrowserModel.State, +first: Rendered.Violation, +rest: +List<Rendered.Violation>, +frame: Rendered.Frame) ->
  {BrowserModel.utility_frame_rejection(model_state) ==
        BrowserModel.Decision{BrowserModel.with_displayed(None{}, BrowserModel.with_lifecycle(BrowserModel.UtilityRejected{"Frontend utility frame does not match its admitted source"}, model_state)), Nil{}} : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed, attention} = model_state
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
  {Rule.decision_world(SessionRule.confirmation_result_spec(owned, D.failure("command_not_submitted", reason), destination,
    E.Application{program, session})) == program : M.World()}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def rejected_valid_world(completion: E.Completion, reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(SessionRule.valid_completion_spec(completion, program, D.failure("command_not_submitted", reason), session)) == program : M.World()}:
  match completion:
    case E.ExecutionCompletion{task, profile, reasoning, remember}: {==}
    case E.ExecutionViewCompletion{task, profile, reasoning, remember, occurrence}: {==}
    case E.DirectCompletion{}: {==}
    case E.DraftCompletion{draft}: {==}
    case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, +previews, code, next_layer, model_preference, draft_model_manual} = session
      confirmation_failed_world(SessionRule.confirmation_spec(layers, command, trigger, occurrence), reason, destination, program,
        E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual}, program))

def rejected_checked_world(+valid: Bool, +completion: E.Completion, +reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(SessionRule.completion_checked_spec(valid, completion, program, D.failure("command_not_submitted", reason), session, program)) == program : M.World()}:
  match valid:
    case False{}: {==}
    case True{}: rejected_valid_world(completion, reason, program, session)

def rejected_world(+completion: E.Completion, +reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session})) == program : M.World()}:
  Equal.trans(M.World(), Rule.decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session})),
    Rule.decision_world(SessionRule.completion_spec(completion, program, D.failure("command_not_submitted", reason), session, program)), program,
    Equal.cong(E.Decision, M.World(), decision => Rule.decision_world(decision),
      E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session}),
      SessionRule.completion_spec(completion, program, D.failure("command_not_submitted", reason), session, program),
      SessionProof.completed_refinement(completion, program, D.failure("command_not_submitted", reason), session, program)),
    rejected_checked_world(WorldInvariant.world(program), completion, reason, program, session))

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
    revision => +body => feedback => directory_entry => submitted => +reason => {==},
    state_uncertain_evidence,
    id => message => {==}}

# Bind the application and display interfaces beside their representations.
def application_state(decision: Browser.Decision) -> Browser.State:
  Browser.Decision{state, effects} = decision
  state

def application_effects(decision: Browser.Decision) -> +List<Browser.Effect>:
  Browser.Decision{state, effects} = decision
  effects

def display_effects(decision: BrowserModel.Decision) -> +List<Browser.Effect>:
  BrowserModel.Decision{state, effects} = decision
  effects

def completion_dispatch(+ticket: Nat, +serial: Nat, +world: M.World(), +reply: J.Json, +state: Browser.State) ->
  {Browser.step(Browser.Completed{ticket, serial, world, reply}, state) ==
    Browser.completed(Browser.find(Browser.pending(state), ticket), serial, world, reply, state) : Browser.Decision}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def application_operations() -> Model.ApplicationOperations<M.World(), Browser.State, Browser.Input, Browser.Decision, Browser.Pending, Browser.Effect>:
  Model.ApplicationOperations{
      world => serial => Browser.initial(world, serial),
      user => Browser.Native{Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.UserInput{user}}}}}},
      serial => world => Browser.Snapshot{serial, world},
      ticket => serial => world => reply => Browser.Completed{ticket, serial, world, reply},
      input => state => Browser.step(input, state), decision => application_state(decision), decision => application_effects(decision),
      state => effects => Browser.Decision{state, effects},
      state => Browser.program(state), state => Browser.sequence(state),
      ticket => state => Browser.find(Browser.pending(state), ticket),
      serial => world => state => Browser.snapshot(serial, world, state),
      found => serial => world => reply => state => Browser.completed(found, serial, world, reply, state),
      capacity => state => Browser.semantic_surface(capacity, state)}

def application_model() -> Model.Application(M.World(), Browser.State, Browser.Input, Browser.Decision, Browser.Pending, Browser.Effect):
  Categories.Membership{
    Categories.Implementation{application_operations(), application_operations()},
      Categories.Intersection{Model.ApplicationFaithfulness{a0 => a1 => {==}, a0 => {==}, a0 => a1 => {==}, a0 => a1 => a2 => a3 => {==}, a0 => a1 => {==}, a0 => {==}, a0 => {==}, a0 => a1 => {==}, a0 => {==}, a0 => {==}, a0 => a1 => {==}, a0 => a1 => a2 => {==}, a0 => a1 => a2 => a3 => a4 => {==}, a0 => a1 => {==}},

      Categories.Intersection{
      Model.ApplicationInitialization{world => serial => {==}},
      Categories.Intersection{
        Model.ApplicationCorrelation{
          serial => world => state => {==},
          ticket => serial => world => reply => state => completion_dispatch(ticket, serial, world, reply, state)},
        Model.ApplicationOrdering{
          serial => world => state => stale => stale_snapshot(serial, world, state, stale),
          serial => world => reply => state => {==}}}}}}

def display_operations() -> Model.DisplayOperations<M.World(), Browser.State, Browser.Input, Browser.Effect, BrowserModel.State, BrowserModel.Decision, BrowserModel.Publication, +List<Native.Update>, Document.Document>:
  Model.DisplayOperations{
          world => serial => BrowserModel.initial(world, serial), state => BrowserModel.legacy(state),
          state => BrowserModel.program(state),
          input => state => BrowserModel.step(input, state), decision => BrowserModel.decision_state(decision),
          decision => display_effects(decision), capacity => state => BrowserModel.observe(capacity, state),
          capacity => last => state => BrowserModel.publication(capacity, last, state),
          state => Rule.publication_pending(state),
          state => BrowserModel.native_updates(state), fields => BrowserModel.KeepPublished{fields}}

def display_model() -> Model.DisplayModel(M.World(), Browser.State, Browser.Input, Browser.Effect,
  world => serial => Browser.initial(world, serial), state => Browser.program(state)):
  (BrowserModel.State, (BrowserModel.Decision, (BrowserModel.Publication,
          (+List<Native.Update>, (Document.Document,
      Categories.Membership{
        Categories.Implementation{display_operations(), display_operations()},
      Categories.Intersection{Model.DisplayFaithfulness{a0 => a1 => {==}, a0 => {==}, a0 => {==}, a0 => a1 => {==}, a0 => {==}, a0 => {==}, a0 => a1 => {==}, a0 => a1 => a2 => {==}, a0 => {==}, a0 => {==}, a0 => {==}},
          Categories.Intersection{
          Model.DisplayComposition{
            world => serial => {==},
            state => {==}},
          Model.DisplayRetention{capacity => last => state => published => pending =>
            publication_preserves_pending_at(capacity, last, state, published, pending)}}}})))))

def Rule.supporting_mask_evidence(blocked, support, property, input, availability):
  match blocked:
    case True{}: {==}
    case False{}: {==}

def supporting_compact_ready(requirement: Maybe<&2, Adaptation.RegionDemand>) ->
  {BrowserModel.supporting_width_admitted(ControlsProgram.CompactSupporting{}, requirement) == True{} : Bool}:
  match requirement:
    case None{}: {==}
    case Some{Adaptation.RegionDemand{available, preferred}}: {==}

def Rule.supporting_admission_evidence():
  Rule.SupportingAdmissionRequirements{
    {==},
    +available => +preferred => {==},
    supporting_compact_ready,
    +index => +world => {==},
    +world => +index => +capacity => +engine => +state => +semantic => round => {==},
    +world => index => +capacity => +engine => +state => +semantic => {==},
    world => +index => capacity => engine => +state => semantic => {==},
    +index => +state => {==}}

def navigation_interest_keeps_legacy(+attention: Navigation.Attention, +state: BrowserModel.State) ->
  {BrowserModel.legacy(BrowserModel.with_attention(attention, state)) == BrowserModel.legacy(state) : Browser.State}:
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, previous}: {==}

def fresh_attention_candidate(+state: BrowserModel.State) -> Rule.fresh_attention_candidate(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: {==}
        case BrowserModel.WaitingFont{}: {==}
        case BrowserModel.Measuring{index, capacity, engine, semantic, round}: {==}
        case BrowserModel.Displaying{capacity, engine, semantic}: {==}
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: {==}
        case BrowserModel.UtilityDisplaying{purpose, engine}: {==}
        case BrowserModel.UtilityRejected{problem}: {==}
        case BrowserModel.Blocked{problem}: {==}

def Rule.navigation_evidence():
  Rule.NavigationRequirements{
    navigation_interest_keeps_legacy,
    +attention => +state => {==},
    +attention => +state => {==},
    fresh_attention_candidate}

def Rule.reviewer_field_gesture(editor, entry, value, text, state): {==}


def Rule.role_calibration_request(capacity, state):
  F.activity_request_correspondence(capacity, BrowserModel.current_font(BrowserModel.legacy(state)))

def Rule.missing_activity_calibration_waits(physical_capacity, body, index, state):
  {==}

def Rule.actual_activity_calibration(physical_capacity, body, primary, support, index, state):
  {==}
