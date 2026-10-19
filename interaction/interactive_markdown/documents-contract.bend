import Base
import ../../bendlib/json.bend as Json
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/string-equality.bend as SafeText
import ./DOCUMENTS.bend as Docs
import ./MODEL.bend as Core
import ./SOURCES.bend as Sources
import ./TYPES.bend as UI
import ../conversation/CODE.bend as Code
import ../conversation/OUTPUT.bend as Live
import ../../harness/DOMAIN.bend as D
import ../../harness/MODEL.bend as Harness

law visible_document_exposure_uses_its_viewing_task:
  @+source:Code.Source -> @+text:String -> @+epoch:Nat -> @+revision:Nat -> @+ending:UI.Ending -> @+observed:Nat -> @+fences:+List<Docs.Fence> -> @active:Bool -> @+rest:+List<Docs.Document> -> @+viewers:+List<Nat> -> @+entries:+List<Docs.RetainedEntry> ->
  {Docs.exposed_visible_documents(Docs.Document{source, text, epoch, revision, ending, observed, fences, active} <> rest, viewers, entries) ==
    Docs.Document{source, text, epoch, revision, ending, observed, fences, Docs.present_nat(viewers, Docs.source_viewer(source)) && Bool.not(Docs.entry_archived(entries, Code.source_key(source)))} <> Docs.exposed_visible_documents(rest, viewers, entries) : +List<Docs.Document>}

law visible_document_exposure_refreshes_actual_documents:
  @+viewers:+List<Nat> -> @+world:Harness.World() -> @+state:Docs.State ->
  {Docs.expose_visible(viewers, world, state) == Docs.refresh(world, Docs.with_documents(Docs.exposed_visible_documents(Docs.documents(state), viewers, Docs.retained_entries(Docs.retention(state))), state)) : Docs.Decision}

# Authority is an identity in the current data space, not a retained eligibility
# flag. The viewer and immutable producer/request/part all occur in Code.key.
def canonical_source(+store: String, source: Code.Source) -> Bool:
  match source:
    case Code.Generated{+namespace, viewer, D.OutputOrigin{producer, operation, part, D.InteractiveV1{}}, complete}:
      Live.valid_namespace(namespace) && String.eq(namespace, store)
    case _: False{}

def owns_fence(+source: Code.Source, +epoch: Nat, +expected: UI.Owner, fence: Docs.Fence) -> Bool:
  UI.Owner{key, current_epoch} = expected
  Docs.Fence{ordinal, eligible, code, closed, visible} = fence
  eligible && Nat.is_eq(current_epoch, epoch) && String.eq(Code.key(Code.Identity{source, ordinal}), key)

def fence_owned(+source: Code.Source, +epoch: Nat, +expected: UI.Owner, fences: +List<Docs.Fence>) -> Bool:
  match fences:
    case Nil{}: False{}
    case Con{fence, rest}: owns_fence(source, epoch, expected, fence) || fence_owned(source, epoch, expected, rest)

def owns_document(+store: String, +expected: UI.Owner, +active_only: Bool, document: Docs.Document) -> Bool:
  Docs.Document{+source, text, +epoch, revision, ending, observed, +fences, active} = document
  canonical_source(store, source) && (Bool.not(active_only) || active) &&
    fence_owned(source, epoch, expected, fences)

def owns(+store: String, +expected: UI.Owner, +active_only: Bool, documents: +List<Docs.Document>) -> Bool:
  match documents:
    case Nil{}: False{}
    case Con{document, rest}: owns_document(store, expected, active_only, document) || owns(store, expected, active_only, rest)

# Event occurrence, mounted node and pending receipt correlation belong to the
# core component. This layer adds current document membership before delegation.
def permitted(+input: UI.Input, +state: Docs.State) -> Bool:
  match input:
    case UI.FieldEdited{UI.EventIdentity{UI.Identity{owner, path}, occurrence}, raw}: owns(Docs.namespace(state), owner, True{}, Docs.documents(state))
    case UI.Activated{UI.EventIdentity{UI.Identity{owner, path}, occurrence}}: owns(Docs.namespace(state), owner, True{}, Docs.documents(state))
    case UI.ViewChanged{UI.EventIdentity{UI.Identity{owner, path}, occurrence}, command}: owns(Docs.namespace(state), owner, True{}, Docs.documents(state))
    case UI.Restored{owner, definition, payload}: owns(Docs.namespace(state), owner, False{}, Docs.documents(state))
    case UI.StorageFailed{owner, message}: owns(Docs.namespace(state), owner, False{}, Docs.documents(state))
    case UI.ContinueParsing{owner}: owns(Docs.namespace(state), owner, False{}, Docs.documents(state))
    case UI.EffectCompleted{owner, path, ticket, success, message}: owns(Docs.namespace(state), owner, False{}, Docs.documents(state))
    case _: True{}

def embed(+decision: UI.Decision, state: Docs.State) -> Docs.Decision:
  UI.Decision{core, effects} = decision
  Docs.State{namespace, sequence, fresh, allowed, ready, documents, previous, next, retention} = state
  Docs.Decision{Docs.State{namespace, sequence, fresh, allowed, ready, documents, core, next, retention},
    Std.map(~UI.Effect, ~Docs.Effect, ~(effect => Docs.CoreEffect{effect}), effects)}

def input_result(+authorized: Bool, +input: UI.Input, +state: Docs.State) -> Docs.Decision:
  match authorized:
    case False{}: Docs.Decision{state, Nil{}}
    case True{}: embed(Core.step(input, Docs.core(state)), state)

def required_input(+input: UI.Input, +state: Docs.State) -> Docs.Decision:
  input_result(permitted(input, state), input, state)

# A sequence is ordered only within its namespace. Changing namespace destroys
# the previous namespace's UI state and forgets each of its physical parsers.
def environment_result(+same_namespace: Bool, +current_sequence: Bool, +store: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: Docs.State) -> Docs.Decision:
  match same_namespace current_sequence state:
    case _ False{} +state: Docs.Decision{state, Nil{}}
    case True{} True{} Docs.State{previous, old_sequence, old_fresh, old_allowed, ready, documents, core, next, retention}:
      Docs.Decision{Docs.State{store, sequence, fresh, allowed, ready, documents, core, next, retention}, Nil{}}
    case False{} True{} Docs.State{previous, old_sequence, old_fresh, old_allowed, ready, +documents, core, next, retention}:
      Docs.Decision{Docs.State{store, sequence, fresh, allowed, True{}, Nil{}, Core.initial(), next, Docs.Retention{Nil{}, Nil{}}},
        Std.map(~Docs.Document, ~Docs.Effect, ~(document => Docs.ForgetMarkdown{Docs.document_key(document)}), documents)}

def required_environment(+store: String, +sequence: Nat, fresh: Bool, allowed: Bool, +state: Docs.State) -> Docs.Decision:
  Docs.State{+previous, +old_sequence, old_fresh, old_allowed, ready, documents, core, next, retention} = state
  environment_result(String.eq(store, previous), Bool.not(String.eq(store, previous)) || Nat.is_le(old_sequence, sequence), store, sequence, fresh, allowed, state)

def forbidden(request: UI.SourceRequest, sequence: Nat) -> Json.Field:
  UI.SourceRequest{owner, name, graph} = request
  Json.Field{name, Sources.source_handle("forbidden", False{}, sequence, Json.Null{})}

def forbidden_values(requests: +List<UI.SourceRequest>, +sequence: Nat) -> +List<Json.Field>:
  match requests:
    case Nil{}: Nil{}
    case Con{request, rest}: forbidden(request, sequence) <> forbidden_values(rest, sequence)

# Source projection is a separate operation because environment has no World.
# Authorization withdrawal emits null forbidden handles; transport staleness
# still observes the same World with fresh=False, retaining authorized values.
def source_values(allowed: Bool, requests: +List<UI.SourceRequest>, world: Harness.World(), +sequence: Nat, fresh: Bool) -> +List<Json.Field>:
  match allowed:
    case True{}: Sources.projection(requests, world, sequence, fresh)
    case False{}: forbidden_values(requests, sequence)

# The canonical store is keyed by full source identity. A write replaces only
# the first selected document/fence and preserves every unrelated payload.
def document_lookup(+key: String, values: +List<Docs.Document>) -> Maybe<&2, Docs.Document>:
  match values:
    case Nil{}: None{}
    case Con{+document, rest}:
      Bool.pick(Maybe<&2, Docs.Document>, String.eq(Docs.document_key(document), key), Some{document}, document_lookup(key, rest))

def write_document(values: +List<Docs.Document>, +value: Docs.Document) -> +List<Docs.Document>:
  match values:
    case Nil{}: [value]
    case Con{+old, +rest}:
      Bool.pick(+List<Docs.Document>, String.eq(Docs.document_key(old), Docs.document_key(value)), value <> rest, old <> write_document(rest, value))

def write_fence(values: +List<Docs.Fence>, +value: Docs.Fence) -> +List<Docs.Fence>:
  match values:
    case Nil{}: [value]
    case Con{Docs.Fence{+ordinal, +eligible, +code, +closed, +visible}, +rest}:
      Docs.Fence{+target, +next_eligible, +next_code, +next_closed, +next_visible} = value
      Bool.pick(+List<Docs.Fence>, Nat.is_eq(ordinal, target),
        Docs.Fence{target, next_eligible, next_code, next_closed, visible} <> rest,
        Docs.Fence{ordinal, eligible, code, closed, visible} <> write_fence(rest, value))

def archived_entry(key: String, entry: Docs.RetainedEntry) -> Bool:
  Docs.RetainedEntry{current, archived, visible, dormant} = entry
  String.eq(current, key) && archived

def archived(+key: String, entries: +List<Docs.RetainedEntry>) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{entry, rest}: archived_entry(key, entry) || archived(key, rest)

def at_ordinal(ordinal: Nat, fence: Docs.Fence) -> Bool:
  Docs.Fence{current, eligible, code, closed, visible} = fence
  Nat.is_eq(current, ordinal) && eligible

def eligible_ordinal(+ordinal: Nat, fences: +List<Docs.Fence>) -> Bool:
  match fences:
    case Nil{}: False{}
    case Con{fence, rest}: at_ordinal(ordinal, fence) || eligible_ordinal(ordinal, rest)

def count_fence(fence: Docs.Fence, count: Nat) -> Nat:
  match fence:
    case Docs.Fence{ordinal, True{}, code, closed, visible}: 1n+count
    case _: count

def eligible_count(fences: +List<Docs.Fence>) -> Nat:
  List.foldr(~&2, ~Docs.Fence, ~Nat, ~(fence => count => count_fence(fence, count)), fences, 0n)

def accepts_observation(+observation: Docs.FenceObservation, document: Docs.Document, +state: Docs.State) -> Bool:
  Docs.FenceObservation{key, epoch, revision, ordinal, kind, info, info_complete, code, closed, +input_prefix} = observation
  Docs.Document{+source, +text, expected_epoch, current_revision, ending, observed_prefix, fences, active} = document
  canonical_source(Docs.namespace(state), source) &&
    (Nat.is_eq(epoch, expected_epoch) && Nat.is_le(revision, current_revision) &&
      Nat.is_le(observed_prefix, String.length(input_prefix)) && String.starts_with(text, input_prefix)) &&
    Bool.not(archived(Code.source_key(source), Docs.retained_entries(Docs.retention(state))))

def observation_eligible(+observation: Docs.FenceObservation, document: Docs.Document) -> Bool:
  Docs.FenceObservation{key, epoch, revision, +ordinal, kind, info, info_complete, code, closed, input_prefix} = observation
  Docs.Document{+source, text, current_epoch, current_revision, ending, observed, +fences, active} = document
  Core.eligible_fence(Docs.interactive_source(source), kind, info, info_complete) &&
    (eligible_ordinal(ordinal, fences) || Nat.is_lt(eligible_count(fences), 16n))

# A previously closed fence cannot reopen or change its code; an accepted fence
# cannot become literal. Open code may only extend its accepted prefix.
def extends_fence(+ordinal: Nat, +eligible: Bool, +code: String, +closed: Bool, previous: Docs.Fence) -> Bool:
  Docs.Fence{current, previous_eligible, +previous_code, previous_closed, visible} = previous
  Bool.pick(Bool, Nat.is_eq(current, ordinal),
    String.starts_with(code, previous_code) && (Bool.not(previous_closed) || (closed && SafeText.string_equal(previous_code, code))) &&
      (Bool.not(previous_eligible) || eligible), True{})

def extends_fences(+ordinal: Nat, +eligible: Bool, +code: String, +closed: Bool, fences: +List<Docs.Fence>) -> Bool:
  match fences:
    case Nil{}: True{}
    case Con{fence, rest}: extends_fence(ordinal, eligible, code, closed, fence) && extends_fences(ordinal, eligible, code, closed, rest)

def observation_extends(+observation: Docs.FenceObservation, document: Docs.Document, eligible: Bool) -> Bool:
  Docs.FenceObservation{key, epoch, revision, ordinal, kind, info, info_complete, code, closed, input_prefix} = observation
  Docs.Document{source, text, current_epoch, current_revision, ending, observed, fences, active} = document
  extends_fences(ordinal, eligible, code, closed, fences)

def observation_state(+eligible: Bool, observation: Docs.FenceObservation, document: Docs.Document, +state: Docs.State) -> Docs.State:
  Docs.FenceObservation{key, epoch, revision, ordinal, kind, info, info_complete, code, closed, +input_prefix} = observation
  Docs.Document{source, text, current_epoch, current_revision, ending, observed, fences, active} = document
  Docs.with_documents(write_document(Docs.documents(state), Docs.Document{source, text, current_epoch, current_revision, ending, String.length(input_prefix),
    write_fence(fences, Docs.Fence{ordinal, eligible, code, closed, False{}}), active}), state)

# External model actions additionally require a completed output owned by its
# current viewer. Local editing does not depend on network freshness.
def completed_producer(source: Code.Source) -> Bool:
  match source:
    case Code.Generated{namespace, viewer, D.OutputOrigin{producer, operation, part, mode}, True{}}: Nat.is_eq(viewer, producer)
    case _: False{}

def complete_ending(ending: UI.Ending) -> Bool:
  match ending:
    case UI.Complete{}: True{}
    case _: False{}

def external_permission(document: Docs.Document, state: Docs.State) -> Bool:
  Docs.Document{+source, text, epoch, revision, ending, observed, fences, active} = document
  Docs.State{namespace, sequence, fresh, allowed, ready, documents, core, next, retention} = state
  active && fresh && allowed && ready && canonical_source(namespace, source) && completed_producer(source) && complete_ending(ending)

def apply_observation(eligible: Bool, observation: Docs.FenceObservation, +document: Docs.Document, +next: Docs.State) -> Docs.Decision:
  match eligible:
    case False{}: Docs.Decision{next, Nil{}}
    case True{}:
      Docs.FenceObservation{key, epoch, revision, ordinal, kind, info, info_complete, code, closed, +input_prefix} = observation
      Docs.Document{+source, +text, current_epoch, current_revision, +ending, observed, fences, active} = document
      required_input(UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed,
        Bool.pick(UI.Ending, SafeText.string_equal(input_prefix, text), ending, UI.Open{}), external_permission(document, next)}, next)

def observed_fence(+eligible: Bool, +observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) -> Docs.Decision:
  apply_observation(eligible, observation, document, observation_state(eligible, observation, document, state))

def observe_result(accepted: Bool, +eligible: Bool, +observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) -> Docs.Decision:
  match accepted:
    case False{}: Docs.Decision{state, Nil{}}
    case True{}: observed_fence(eligible, observation, document, state)

def observe_found(found: Maybe<&2, Docs.Document>, +observation: Docs.FenceObservation, +state: Docs.State) -> Docs.Decision:
  match found:
    case None{}: Docs.Decision{state, Nil{}}
    case Some{+document}:
      +eligible = observation_eligible(observation, document)
      observe_result(accepts_observation(observation, document, state) && observation_extends(observation, document, eligible), eligible, observation, document, state)

def required_observe(+observation: Docs.FenceObservation, +state: Docs.State) -> Docs.Decision:
  Docs.FenceObservation{+key, epoch, revision, ordinal, kind, info, info_complete, code, closed, input_prefix} = observation
  observe_found(document_lookup(key, Docs.documents(state)), observation, state)

def select_request(key: String, +request: UI.SourceRequest, +tail: +List<UI.SourceRequest>) -> +List<UI.SourceRequest>:
  UI.SourceRequest{UI.Owner{+current, +epoch}, +name, +graph} = request
  Bool.pick(+List<UI.SourceRequest>, String.eq(current, key), request <> tail, tail)

def selected_requests(+key: String, requests: +List<UI.SourceRequest>) -> +List<UI.SourceRequest>:
  match requests:
    case Nil{}: Nil{}
    case Con{request, rest}: select_request(key, request, selected_requests(key, rest))

def append_decision(before: +List<Docs.Effect>, result: Docs.Decision) -> Docs.Decision:
  Docs.Decision{next, after} = result
  Docs.Decision{next, List.append(&2, Docs.Effect, before, after)}

def after_decision(+first: Docs.Decision, continuation: @+state:Docs.State -> Docs.Decision) -> Docs.Decision:
  Docs.Decision{state, +before} = first
  append_decision(before, continuation(state))

# Both source projection and external-action permission use one captured World
# and the current environment. The order of emitted core effects is preserved.
def snapshot_fence(eligible: Bool, +ordinal: Nat, +document: Docs.Document, +world: Harness.World(), +state: Docs.State) -> Docs.Decision:
  match eligible:
    case False{}: Docs.Decision{state, Nil{}}
    case True{}:
      Docs.Document{+source, text, +epoch, revision, ending, observed, fences, active} = document
      Docs.State{namespace, +sequence, +fresh, +allowed, ready, documents, +core, next, retention} = state
      +owner = Docs.owner(source, ordinal, epoch)
      +requests = selected_requests(Docs.owner_key(owner), Core.source_requests(core))
      +changed = required_input(UI.SourcesChanged{owner, source_values(allowed, requests, world, sequence, fresh)}, state)
      after_decision(changed, +next_state => required_input(UI.ExternalChanged{owner, external_permission(document, next_state)}, next_state))

def document_source(document: Docs.Document) -> Code.Source:
  Docs.Document{source, text, epoch, revision, ending, observed, fences, active} = document
  source

def refresh_fence_plan(+document: Docs.Document, +world: Harness.World(), fence: Docs.Fence, +state: Docs.State) -> Docs.Decision:
  Docs.Fence{ordinal, eligible, code, closed, visible} = fence
  snapshot_fence(eligible && canonical_source(Docs.namespace(state), document_source(document)), ordinal, document, world, state)

def fence_plan(+document: Docs.Document, +world: Harness.World(), fences: +List<Docs.Fence>) -> @+state:Docs.State -> Docs.Decision:
  match fences:
    case Nil{}: +state => Docs.Decision{state, Nil{}}
    case Con{fence, rest}: +state => after_decision(refresh_fence_plan(document, world, fence, state), fence_plan(document, world, rest))

def document_fences(document: Docs.Document) -> +List<Docs.Fence>:
  Docs.Document{source, text, epoch, revision, ending, observed, fences, active} = document
  fences

def document_plan(+world: Harness.World(), documents: +List<Docs.Document>) -> @+state:Docs.State -> Docs.Decision:
  match documents:
    case Nil{}: +state => Docs.Decision{state, Nil{}}
    case Con{+document, rest}: +state => after_decision(fence_plan(document, world, document_fences(document))(state), document_plan(world, rest))

def required_refresh(+world: Harness.World(), +state: Docs.State) -> Docs.Decision:
  document_plan(world, Docs.documents(state))(state)

def task_from_document(+store: String, +expected: UI.Owner, document: Docs.Document, fallback: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  Docs.Document{+source, text, +epoch, revision, ending, observed, fences, active} = document
  Bool.pick(Maybe<&2, Nat>, canonical_source(store, source) && active && completed_producer(source) &&
    fence_owned(source, epoch, expected, fences), Some{Docs.source_viewer(source)}, fallback)

def task_owner(+store: String, +expected: UI.Owner, documents: +List<Docs.Document>) -> Maybe<&2, Nat>:
  match documents:
    case Nil{}: None{}
    case Con{document, rest}: task_from_document(store, expected, document, task_owner(store, expected, rest))

def retained_key(entry: Docs.RetainedEntry) -> String:
  Docs.RetainedEntry{key, archived, visible, dormant} = entry
  key

# Publishing a continuous prefix changes only its document metadata. Local
# input lives in Core and survives stream append and final promotion unchanged.
def retained_without(+key: String, entries: +List<Docs.RetainedEntry>) -> +List<Docs.RetainedEntry>:
  match entries:
    case Nil{}: Nil{}
    case Con{+entry, rest}:
      +tail = retained_without(key, rest)
      Bool.pick(+List<Docs.RetainedEntry>, String.eq(retained_key(entry), key), tail, entry <> tail)

def publication(+document: Docs.Document, +state: Docs.State) -> Docs.Decision:
  Docs.State{namespace, sequence, fresh, allowed, ready, documents, core, next, Docs.Retention{entries, discarded}} = state
  Docs.Decision{Docs.State{namespace, sequence, fresh, allowed, ready, write_document(documents, document), core, next,
    Docs.Retention{retained_without(Docs.document_key(document), entries), discarded}}, [Docs.ObserveMarkdown{document}]}
# Public guarantees refer to real domain entry points and complete decisions.
# Restore's typed trial, newer-edit protection and effect receipt correlation
# remain the core boundary's obligations; document authority precedes them here.
type Requirements is Type:
  Requirements{
    document_input: @+input:UI.Input -> @+state:Docs.State ->
      {Docs.input(input, state) == required_input(input, state) : Docs.Decision},
    fence_observation: @+observation:Docs.FenceObservation -> @+state:Docs.State ->
      {Docs.observe(observation, state) == required_observe(observation, state) : Docs.Decision},
    environment_snapshot: @+store:String -> @+sequence:Nat -> @+fresh:Bool -> @+allowed:Bool -> @+state:Docs.State ->
      {Docs.environment(store, sequence, fresh, allowed, state) == required_environment(store, sequence, fresh, allowed, state) : Docs.Decision},
    live_snapshot: @+world:Harness.World() -> @+state:Docs.State ->
      {Docs.refresh(world, state) == required_refresh(world, state) : Docs.Decision},
    action_task: @+owner:UI.Owner -> @+state:Docs.State ->
      {Docs.current_owning_task(owner, state) == task_owner(Docs.namespace(state), owner, Docs.documents(state)) : Maybe<&2, Nat>},
    external_authority: @+document:Docs.Document -> @+state:Docs.State ->
      {Docs.external(document, state) == external_permission(document, state) : Bool},
    continuous_document: @+source:Code.Source -> @+text:String -> @+ending:UI.Ending -> @+old_source:Code.Source -> @+old_text:String ->
      @+epoch:Nat -> @+revision:Nat -> @+observed:Nat -> @+fences:+List<Docs.Fence> -> @+active:Bool -> @+rest:+List<Docs.Document> ->
      @+namespace:String -> @+sequence:Nat -> @+fresh:Bool -> @+allowed:Bool -> @+ready:Bool -> @+core:UI.State -> @+next:Nat -> @+retention:Docs.Retention ->
      {String.eq(Code.source_key(old_source), Code.source_key(source)) == True{} : Bool} ->
      {String.starts_with(text, old_text) == True{} : Bool} ->
      {SafeText.string_equal(old_text, text) && Docs.same_ending(UI.Open{}, ending) == False{} : Bool} ->
      {Docs.put(True{}, source, text, ending, Docs.State{namespace, sequence, fresh, allowed, ready,
          Docs.Document{old_source, old_text, epoch, revision, UI.Open{}, observed, fences, active} <> rest, core, next, retention}) ==
        publication(Docs.Document{source, text, epoch, 1n+revision, ending, observed, fences, True{}},
          Docs.State{namespace, sequence, fresh, allowed, ready,
            Docs.Document{old_source, old_text, epoch, revision, UI.Open{}, observed, fences, active} <> rest, core, 1n+next, retention}) : Docs.Decision},
    final_identity: @+origin:D.OutputOrigin -> @+namespace:String -> @+viewer:Nat -> @+ordinal:Nat ->
      {Code.key(Code.Identity{Code.Generated{namespace, viewer, origin, False{}}, ordinal}) ==
        Code.key(Code.Identity{Code.Generated{namespace, viewer, origin, True{}}, ordinal}) : String}}

law evidence:
  Requirements
