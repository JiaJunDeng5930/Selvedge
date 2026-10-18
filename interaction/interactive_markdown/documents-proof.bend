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
import ./documents-contract.bend as Spec

# Proofs below connect these domain relations to complete production results.
def source_meaning(+source: Code.Source, +store: String) ->
  {Docs.source_scope(source, store) == Spec.canonical_source(store, source) : Bool}:
  match source:
    case Code.Generated{namespace, viewer, D.OutputOrigin{producer, operation, part, D.InteractiveV1{}}, complete}: {==}
    case Code.Generated{namespace, viewer, D.OutputOrigin{producer, operation, part, D.Plain{}}, complete}: {==}
    case Code.Message{task, message}: {==}
    case Code.StreamingPart{task, operation, part}: {==}

def fence_owner_meaning(+fences: +List<Docs.Fence>, +source: Code.Source, +epoch: Nat, +expected: UI.Owner) ->
  {Docs.owner_matches(fences, source, epoch, expected) ==
    Spec.fence_owned(source, epoch, expected, fences) : Bool}:
  match fences:
    case Nil{}: {==}
    case Con{Docs.Fence{+ordinal, +eligible, +code, +closed, +visible}, +rest}:
      UI.Owner{+key, +current_epoch} = expected
      Equal.cong(Bool, Bool, tail => (eligible && Nat.is_eq(current_epoch, epoch) && String.eq(Code.key(Code.Identity{source, ordinal}), key)) || tail,
        Docs.owner_matches(rest, source, epoch, expected),
        Spec.fence_owned(source, epoch, expected, rest), fence_owner_meaning(rest, source, epoch, expected))

def document_owner_meaning(+store: String, +documents: +List<Docs.Document>, +expected: UI.Owner, +active_only: Bool) ->
  {Docs.owner_known(store, documents, expected, active_only) == Spec.owns(store, expected, active_only, documents) : Bool}:
  match documents:
    case Nil{}: {==}
    case Con{Docs.Document{+source, +text, +epoch, +revision, +ending, +observed, +fences, +active}, +rest}:
      Equal.trans(Bool,
        Docs.owner_known(store, Docs.Document{source, text, epoch, revision, ending, observed, fences, active} <> rest, expected, active_only),
        (Spec.canonical_source(store, source) && (Bool.not(active_only) || active) && Spec.fence_owned(source, epoch, expected, fences)) || Docs.owner_known(store, rest, expected, active_only),
        Spec.owns(store, expected, active_only, Docs.Document{source, text, epoch, revision, ending, observed, fences, active} <> rest),
        Equal.trans(Bool,
          Docs.source_scope(source, store) && (Bool.not(active_only) || active) && Docs.owner_matches(fences, source, epoch, expected) || Docs.owner_known(store, rest, expected, active_only),
          Spec.canonical_source(store, source) && (Bool.not(active_only) || active) && Docs.owner_matches(fences, source, epoch, expected) || Docs.owner_known(store, rest, expected, active_only),
          Spec.canonical_source(store, source) && (Bool.not(active_only) || active) && Spec.fence_owned(source, epoch, expected, fences) || Docs.owner_known(store, rest, expected, active_only),
          Equal.cong(Bool, Bool, scoped => scoped && (Bool.not(active_only) || active) && Docs.owner_matches(fences, source, epoch, expected) || Docs.owner_known(store, rest, expected, active_only), Docs.source_scope(source, store), Spec.canonical_source(store, source), source_meaning(source, store)),
          Equal.cong(Bool, Bool, found => Spec.canonical_source(store, source) && (Bool.not(active_only) || active) && found || Docs.owner_known(store, rest, expected, active_only),
            Docs.owner_matches(fences, source, epoch, expected), Spec.fence_owned(source, epoch, expected, fences), fence_owner_meaning(fences, source, epoch, expected))),
        Equal.cong(Bool, Bool, tail => Spec.owns_document(store, expected, active_only, Docs.Document{source, text, epoch, revision, ending, observed, fences, active}) || tail,
          Docs.owner_known(store, rest, expected, active_only), Spec.owns(store, expected, active_only, rest), document_owner_meaning(store, rest, expected, active_only)))

def permission_meaning(+input: UI.Input, +state: Docs.State) ->
  {Docs.input_allowed(input, state) == Spec.permitted(input, state) : Bool}:
  match input:
    case UI.FieldEdited{UI.EventIdentity{UI.Identity{+owner, path}, occurrence}, raw}: document_owner_meaning(Docs.namespace(state), Docs.documents(state), owner, True{})
    case UI.Activated{UI.EventIdentity{UI.Identity{+owner, path}, occurrence}}: document_owner_meaning(Docs.namespace(state), Docs.documents(state), owner, True{})
    case UI.ViewChanged{UI.EventIdentity{UI.Identity{+owner, path}, occurrence}, command}: document_owner_meaning(Docs.namespace(state), Docs.documents(state), owner, True{})
    case UI.Restored{+owner, definition, payload}: document_owner_meaning(Docs.namespace(state), Docs.documents(state), owner, False{})
    case UI.StorageFailed{+owner, message}: document_owner_meaning(Docs.namespace(state), Docs.documents(state), owner, False{})
    case UI.ContinueParsing{+owner}: document_owner_meaning(Docs.namespace(state), Docs.documents(state), owner, False{})
    case UI.EffectCompleted{+owner, path, ticket, success, message}: document_owner_meaning(Docs.namespace(state), Docs.documents(state), owner, False{})
    case UI.SourceChanged{owner, source, closed, ending, external}: {==}
    case UI.SourcesChanged{owner, values}: {==}
    case UI.ExternalChanged{owner, allowed}: {==}
    case UI.Removed{owner}: {==}

def effects_meaning(+effects: +List<UI.Effect>) ->
  {Docs.core_effects(effects) == Std.map(~UI.Effect, ~Docs.Effect, ~(effect => Docs.CoreEffect{effect}), effects) : +List<Docs.Effect>}:
  match effects:
    case Nil{}: {==}
    case Con{+effect, +rest}: Equal.cong(+List<Docs.Effect>, +List<Docs.Effect>, tail => Docs.CoreEffect{effect} <> tail,
      Docs.core_effects(rest), Std.map(~UI.Effect, ~Docs.Effect, ~(effect => Docs.CoreEffect{effect}), rest), effects_meaning(rest))

def embedded_meaning(+decision: UI.Decision, +state: Docs.State) ->
  {Docs.apply_core_result(decision, state) == Spec.embed(decision, state) : Docs.Decision}:
  match decision state:
    case UI.Decision{+core, +effects} Docs.State{+namespace, +sequence, +fresh, +allowed, +ready, +documents, previous, +next, +retention}:
      Equal.cong(+List<Docs.Effect>, Docs.Decision, output => Docs.Decision{Docs.State{namespace, sequence, fresh, allowed, ready, documents, core, next, retention}, output},
        Docs.core_effects(effects), Std.map(~UI.Effect, ~Docs.Effect, ~(effect => Docs.CoreEffect{effect}), effects), effects_meaning(effects))

def input_branch_meaning(+authorized: Bool, +input: UI.Input, +state: Docs.State) ->
  {Docs.input_checked(authorized, input, state) == Spec.input_result(authorized, input, state) : Docs.Decision}:
  match authorized:
    case False{}: {==}
    case True{}: embedded_meaning(Core.step(input, Docs.core(state)), state)

def input_meaning(+input: UI.Input, +state: Docs.State) ->
  {Docs.input(input, state) == Spec.required_input(input, state) : Docs.Decision}:
  Equal.trans(Docs.Decision, Docs.input(input, state), Spec.input_result(Docs.input_allowed(input, state), input, state), Spec.required_input(input, state),
    input_branch_meaning(Docs.input_allowed(input, state), input, state),
    Equal.cong(Bool, Docs.Decision, authorized => Spec.input_result(authorized, input, state), Docs.input_allowed(input, state), Spec.permitted(input, state), permission_meaning(input, state)))

def forget_meaning(+documents: +List<Docs.Document>) ->
  {Docs.forget_effects(documents) == Std.map(~Docs.Document, ~Docs.Effect, ~(document => Docs.ForgetMarkdown{Docs.document_key(document)}), documents) : +List<Docs.Effect>}:
  match documents:
    case Nil{}: {==}
    case Con{+document, +rest}: Equal.cong(+List<Docs.Effect>, +List<Docs.Effect>, tail => Docs.ForgetMarkdown{Docs.document_key(document)} <> tail,
      Docs.forget_effects(rest), Std.map(~Docs.Document, ~Docs.Effect, ~(document => Docs.ForgetMarkdown{Docs.document_key(document)}), rest), forget_meaning(rest))

def environment_same_meaning(+same: Bool, +store: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: Docs.State) ->
  {Docs.environment_same(same, store, sequence, fresh, allowed, state) == Spec.environment_result(same, True{}, store, sequence, fresh, allowed, state) : Docs.Decision}:
  match same state:
    case True{} Docs.State{previous, old_sequence, old_fresh, old_allowed, ready, documents, core, next, retention}: {==}
    case False{} Docs.State{previous, old_sequence, old_fresh, old_allowed, +ready, +documents, core, +next, retention}:
      Equal.cong(+List<Docs.Effect>, Docs.Decision, effects => Docs.Decision{Docs.State{store, sequence, fresh, allowed, True{}, Nil{}, Core.initial(), next, Docs.Retention{Nil{}, Nil{}}}, effects},
        Docs.forget_effects(documents), Std.map(~Docs.Document, ~Docs.Effect, ~(document => Docs.ForgetMarkdown{Docs.document_key(document)}), documents), forget_meaning(documents))

def environment_branch_meaning(+current: Bool, +same: Bool, +store: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: Docs.State,
  observed: {String.eq(store, Docs.namespace(state)) == same : Bool}) ->
  {Docs.environment_current(current, store, sequence, fresh, allowed, state) == Spec.environment_result(same, current, store, sequence, fresh, allowed, state) : Docs.Decision}:
  match current:
    case False{}:
      match same:
        case False{}: {==}
        case True{}: {==}
    case True{}:
      Equal.trans(Docs.Decision, Docs.environment_same(String.eq(store, Docs.namespace(state)), store, sequence, fresh, allowed, state),
        Docs.environment_same(same, store, sequence, fresh, allowed, state), Spec.environment_result(same, True{}, store, sequence, fresh, allowed, state),
        Equal.cong(Bool, Docs.Decision, equal => Docs.environment_same(equal, store, sequence, fresh, allowed, state), String.eq(store, Docs.namespace(state)), same, observed),
        environment_same_meaning(same, store, sequence, fresh, allowed, state))

def environment_meaning(+store: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: Docs.State) ->
  {Docs.environment(store, sequence, fresh, allowed, state) == Spec.required_environment(store, sequence, fresh, allowed, state) : Docs.Decision}:
  match state:
    case Docs.State{+previous, +old_sequence, +old_fresh, +old_allowed, +ready, +documents, +core, +next, +retention}:
      environment_branch_meaning(Bool.not(String.eq(store, previous)) || Nat.is_le(old_sequence, sequence), String.eq(store, previous), store, sequence, fresh, allowed,
        Docs.State{previous, old_sequence, old_fresh, old_allowed, ready, documents, core, next, retention}, {==})

def document_choice_meaning(+hit: Bool, +document: Docs.Document, +fallback: Maybe<&2, Docs.Document>) ->
  {Docs.choose_document(hit, document, fallback) == Bool.pick(Maybe<&2, Docs.Document>, hit, Some{document}, fallback) : Maybe<&2, Docs.Document>}:
  match hit:
    case False{}: {==}
    case True{}: {==}

def lookup_meaning(+documents: +List<Docs.Document>, +key: String) ->
  {Docs.find(documents, key) == Spec.document_lookup(key, documents) : Maybe<&2, Docs.Document>}:
  match documents:
    case Nil{}: {==}
    case Con{+document, +rest}:
      Equal.trans(Maybe<&2, Docs.Document>, Docs.find(document <> rest, key),
        Bool.pick(Maybe<&2, Docs.Document>, String.eq(Docs.document_key(document), key), Some{document}, Docs.find(rest, key)), Spec.document_lookup(key, document <> rest),
        document_choice_meaning(String.eq(Docs.document_key(document), key), document, Docs.find(rest, key)),
        Equal.cong(Maybe<&2, Docs.Document>, Maybe<&2, Docs.Document>, fallback => Bool.pick(Maybe<&2, Docs.Document>, String.eq(Docs.document_key(document), key), Some{document}, fallback),
          Docs.find(rest, key), Spec.document_lookup(key, rest), lookup_meaning(rest, key)))

def document_replacement_meaning(+hit: Bool, +old: Docs.Document, +rest: +List<Docs.Document>, +value: Docs.Document, +fallback: +List<Docs.Document>) ->
  {Docs.replace_document(hit, old, rest, value, fallback) == Bool.pick(+List<Docs.Document>, hit, value <> rest, old <> fallback) : +List<Docs.Document>}:
  match hit:
    case False{}: {==}
    case True{}: {==}

def write_document_meaning(+documents: +List<Docs.Document>, +value: Docs.Document) ->
  {Docs.save(documents, value) == Spec.write_document(documents, value) : +List<Docs.Document>}:
  match documents:
    case Nil{}: {==}
    case Con{+old, +rest}:
      Equal.trans(+List<Docs.Document>, Docs.save(old <> rest, value),
        Bool.pick(+List<Docs.Document>, String.eq(Docs.document_key(old), Docs.document_key(value)), value <> rest, old <> Docs.save(rest, value)), Spec.write_document(old <> rest, value),
        document_replacement_meaning(String.eq(Docs.document_key(old), Docs.document_key(value)), old, rest, value, Docs.save(rest, value)),
        Equal.cong(+List<Docs.Document>, +List<Docs.Document>, tail => Bool.pick(+List<Docs.Document>, String.eq(Docs.document_key(old), Docs.document_key(value)), value <> rest, old <> tail),
          Docs.save(rest, value), Spec.write_document(rest, value), write_document_meaning(rest, value)))

def retained_fence_visibility(old: Docs.Fence, value: Docs.Fence) -> Docs.Fence:
  Docs.Fence{old_ordinal, old_eligible, old_code, old_closed, visible} = old
  Docs.Fence{ordinal, eligible, code, closed, next_visible} = value
  Docs.Fence{ordinal, eligible, code, closed, visible}

def fence_replacement_meaning(+hit: Bool, +old: Docs.Fence, +rest: +List<Docs.Fence>, +value: Docs.Fence, +fallback: +List<Docs.Fence>) ->
  {Docs.replace_fence(hit, old, rest, value, fallback) == Bool.pick(+List<Docs.Fence>, hit, retained_fence_visibility(old, value) <> rest, old <> fallback) : +List<Docs.Fence>}:
  match hit old value:
    case False{} _ _: {==}
    case True{} Docs.Fence{old_ordinal, old_eligible, old_code, old_closed, visible} Docs.Fence{ordinal, eligible, code, closed, next_visible}: {==}

def write_fence_meaning(+fences: +List<Docs.Fence>, +value: Docs.Fence) ->
  {Docs.save_fence(fences, value) == Spec.write_fence(fences, value) : +List<Docs.Fence>}:
  match fences:
    case Nil{}: {==}
    case Con{Docs.Fence{+ordinal, +eligible, +code, +closed, +visible}, +rest}:
      Docs.Fence{+target, +next_eligible, +next_code, +next_closed, +next_visible} = value
      +old: Docs.Fence = Docs.Fence{ordinal, eligible, code, closed, visible}
      Equal.trans(+List<Docs.Fence>, Docs.save_fence(old <> rest, value),
        Bool.pick(+List<Docs.Fence>, Nat.is_eq(ordinal, target), Docs.Fence{target, next_eligible, next_code, next_closed, visible} <> rest, old <> Docs.save_fence(rest, value)), Spec.write_fence(old <> rest, value),
        fence_replacement_meaning(Nat.is_eq(ordinal, target), old, rest, value, Docs.save_fence(rest, value)),
        Equal.cong(+List<Docs.Fence>, +List<Docs.Fence>, tail => Bool.pick(+List<Docs.Fence>, Nat.is_eq(ordinal, target),
          Docs.Fence{target, next_eligible, next_code, next_closed, visible} <> rest, old <> tail),
          Docs.save_fence(rest, value), Spec.write_fence(rest, value), write_fence_meaning(rest, value)))

def archived_meaning(+entries: +List<Docs.RetainedEntry>, +key: String) ->
  {Docs.entry_archived(entries, key) == Spec.archived(key, entries) : Bool}:
  match entries:
    case Nil{}: {==}
    case Con{Docs.RetainedEntry{+current, +is_archived, +visible, +dormant}, +rest}:
      Equal.cong(Bool, Bool, tail => (String.eq(current, key) && is_archived) || tail,
        Docs.entry_archived(rest, key), Spec.archived(key, rest), archived_meaning(rest, key))

def ordinal_meaning(+fences: +List<Docs.Fence>, +ordinal: Nat) ->
  {Docs.ordinal_eligible(fences, ordinal) == Spec.eligible_ordinal(ordinal, fences) : Bool}:
  match fences:
    case Nil{}: {==}
    case Con{Docs.Fence{+current, +eligible, code, closed, visible}, +rest}:
      Equal.cong(Bool, Bool, tail => (Nat.is_eq(current, ordinal) && eligible) || tail,
        Docs.ordinal_eligible(rest, ordinal), Spec.eligible_ordinal(ordinal, rest), ordinal_meaning(rest, ordinal))

def count_meaning(+fences: +List<Docs.Fence>) ->
  {Docs.fence_eligible_count(fences) == Spec.eligible_count(fences) : Nat}:
  match fences:
    case Nil{}: {==}
    case Con{Docs.Fence{ordinal, True{}, code, closed, visible}, +rest}:
      Equal.cong(Nat, Nat, total => 1n+total, Docs.fence_eligible_count(rest), Spec.eligible_count(rest), count_meaning(rest))
    case Con{Docs.Fence{ordinal, False{}, code, closed, visible}, +rest}: count_meaning(rest)

def eligibility_meaning(+source: Code.Source, +kind: String, +info: String, +complete: Bool, +ordinal: Nat, +fences: +List<Docs.Fence>) ->
  {Core.eligible_fence(Docs.interactive_source(source), kind, info, complete) &&
    (Docs.ordinal_eligible(fences, ordinal) || Nat.is_lt(Docs.fence_eligible_count(fences), 16n)) ==
    Core.eligible_fence(Docs.interactive_source(source), kind, info, complete) &&
    (Spec.eligible_ordinal(ordinal, fences) || Nat.is_lt(Spec.eligible_count(fences), 16n)) : Bool}:
  Equal.trans(Bool,
    Core.eligible_fence(Docs.interactive_source(source), kind, info, complete) && (Docs.ordinal_eligible(fences, ordinal) || Nat.is_lt(Docs.fence_eligible_count(fences), 16n)),
    Core.eligible_fence(Docs.interactive_source(source), kind, info, complete) && (Spec.eligible_ordinal(ordinal, fences) || Nat.is_lt(Docs.fence_eligible_count(fences), 16n)),
    Core.eligible_fence(Docs.interactive_source(source), kind, info, complete) && (Spec.eligible_ordinal(ordinal, fences) || Nat.is_lt(Spec.eligible_count(fences), 16n)),
    Equal.cong(Bool, Bool, present => Core.eligible_fence(Docs.interactive_source(source), kind, info, complete) && (present || Nat.is_lt(Docs.fence_eligible_count(fences), 16n)),
      Docs.ordinal_eligible(fences, ordinal), Spec.eligible_ordinal(ordinal, fences), ordinal_meaning(fences, ordinal)),
    Equal.cong(Nat, Bool, count => Core.eligible_fence(Docs.interactive_source(source), kind, info, complete) && (Spec.eligible_ordinal(ordinal, fences) || Nat.is_lt(count, 16n)),
      Docs.fence_eligible_count(fences), Spec.eligible_count(fences), count_meaning(fences)))

def extension_at(same: Bool, eligible: Bool, +code: String, closed: Bool, previous: Docs.Fence) -> Bool:
  Docs.Fence{current, previous_eligible, +previous_code, previous_closed, visible} = previous
  Bool.pick(Bool, same,
    String.starts_with(code, previous_code) && (Bool.not(previous_closed) || (closed && SafeText.string_equal(previous_code, code))) &&
      (Bool.not(previous_eligible) || eligible), True{})

def extension_head_meaning(+same: Bool, +eligible: Bool, +code: String, +closed: Bool, +previous: Docs.Fence) ->
  {Docs.fence_monotonic_found(same, eligible, code, closed, previous) == extension_at(same, eligible, code, closed, previous) : Bool}:
  match same previous:
    case False{} Docs.Fence{current, previous_eligible, previous_code, previous_closed, visible}: {==}
    case True{} Docs.Fence{current, previous_eligible, previous_code, previous_closed, visible}: {==}

def fence_ordinal(fence: Docs.Fence) -> Nat:
  Docs.Fence{ordinal, eligible, code, closed, visible} = fence
  ordinal

def extension_meaning(+fences: +List<Docs.Fence>, +ordinal: Nat, +eligible: Bool, +code: String, +closed: Bool) ->
  {Docs.fence_monotonic(fences, ordinal, eligible, code, closed) == Spec.extends_fences(ordinal, eligible, code, closed, fences) : Bool}:
  match fences:
    case Nil{}: {==}
    case Con{+previous, +rest}:
      Docs.Fence{+current, +previous_eligible, +previous_code, +previous_closed, +visible} = previous
      Equal.trans(Bool, Docs.fence_monotonic(previous <> rest, ordinal, eligible, code, closed),
        Spec.extends_fence(ordinal, eligible, code, closed, previous) && Docs.fence_monotonic(rest, ordinal, eligible, code, closed),
        Spec.extends_fences(ordinal, eligible, code, closed, previous <> rest),
        Equal.cong(Bool, Bool, head => head && Docs.fence_monotonic(rest, ordinal, eligible, code, closed),
          Docs.fence_monotonic_found(Nat.is_eq(fence_ordinal(previous), ordinal), eligible, code, closed, previous),
          Spec.extends_fence(ordinal, eligible, code, closed, previous),
          extension_head_meaning(Nat.is_eq(fence_ordinal(previous), ordinal), eligible, code, closed, previous)),
        Equal.cong(Bool, Bool, tail => Spec.extends_fence(ordinal, eligible, code, closed, previous) && tail,
          Docs.fence_monotonic(rest, ordinal, eligible, code, closed), Spec.extends_fences(ordinal, eligible, code, closed, rest), extension_meaning(rest, ordinal, eligible, code, closed)))

def observation_guard_meaning(+observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) ->
  {Docs.source_scope_document(document, Docs.namespace(state)) && Docs.observation_valid(observation, document) &&
    Bool.not(Docs.entry_archived(Docs.retained_entries(Docs.retention(state)), Docs.document_key(document))) == Spec.accepts_observation(observation, document, state) : Bool}:
  Docs.FenceObservation{+key, +epoch, +revision, +ordinal, +kind, +info, +info_complete, +code, +closed, +input_prefix} = observation
  Docs.Document{+source, +text, +expected_epoch, +current_revision, +ending, +observed_prefix, +fences, +active} = document
  Equal.trans(Bool,
    Docs.source_scope(source, Docs.namespace(state)) && Docs.observation_valid(observation, document) && Bool.not(Docs.entry_archived(Docs.retained_entries(Docs.retention(state)), Code.source_key(source))),
    Spec.canonical_source(Docs.namespace(state), source) && Docs.observation_valid(observation, document) && Bool.not(Docs.entry_archived(Docs.retained_entries(Docs.retention(state)), Code.source_key(source))),
    Spec.accepts_observation(observation, document, state),
    Equal.cong(Bool, Bool, scoped => scoped && Docs.observation_valid(observation, document) && Bool.not(Docs.entry_archived(Docs.retained_entries(Docs.retention(state)), Code.source_key(source))),
      Docs.source_scope(source, Docs.namespace(state)), Spec.canonical_source(Docs.namespace(state), source), source_meaning(source, Docs.namespace(state))),
    Equal.cong(Bool, Bool, hidden => Spec.canonical_source(Docs.namespace(state), source) && Docs.observation_valid(observation, document) && Bool.not(hidden),
      Docs.entry_archived(Docs.retained_entries(Docs.retention(state)), Code.source_key(source)), Spec.archived(Code.source_key(source), Docs.retained_entries(Docs.retention(state))), archived_meaning(Docs.retained_entries(Docs.retention(state)), Code.source_key(source))))

def actual_observation_state(+eligible: Bool, observation: Docs.FenceObservation, document: Docs.Document, +state: Docs.State) -> Docs.State:
  Docs.FenceObservation{key, epoch, revision, ordinal, kind, info, info_complete, code, closed, input_prefix} = observation
  Docs.Document{source, text, current_epoch, current_revision, ending, observed, fences, active} = document
  Docs.with_documents(Docs.save(Docs.documents(state), Docs.Document{source, text, current_epoch, current_revision, ending, String.length(input_prefix),
    Docs.save_fence(fences, Docs.Fence{ordinal, eligible, code, closed, False{}}), active}), state)

def observation_state_meaning(+eligible: Bool, +observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) ->
  {actual_observation_state(eligible, observation, document, state) == Spec.observation_state(eligible, observation, document, state) : Docs.State}:
  Docs.FenceObservation{key, epoch, revision, +ordinal, kind, info, info_complete, +code, +closed, +input_prefix} = observation
  Docs.Document{+source, +text, +current_epoch, +current_revision, +ending, observed, +fences, +active} = document
  +next_document: Docs.Document = Docs.Document{source, text, current_epoch, current_revision, ending, String.length(input_prefix), Spec.write_fence(fences, Docs.Fence{ordinal, eligible, code, closed, False{}}), active}
  Equal.trans(Docs.State, actual_observation_state(eligible, observation, document, state),
    Docs.with_documents(Docs.save(Docs.documents(state), next_document), state), Spec.observation_state(eligible, observation, document, state),
    Equal.cong(+List<Docs.Fence>, Docs.State, updated => Docs.with_documents(Docs.save(Docs.documents(state),
      Docs.Document{source, text, current_epoch, current_revision, ending, String.length(input_prefix), updated, active}), state),
      Docs.save_fence(fences, Docs.Fence{ordinal, eligible, code, closed, False{}}), Spec.write_fence(fences, Docs.Fence{ordinal, eligible, code, closed, False{}}), write_fence_meaning(fences, Docs.Fence{ordinal, eligible, code, closed, False{}})),
    Equal.cong(+List<Docs.Document>, Docs.State, updated => Docs.with_documents(updated, state),
      Docs.save(Docs.documents(state), next_document), Spec.write_document(Docs.documents(state), next_document), write_document_meaning(Docs.documents(state), next_document)))

def actual_observation_input(eligible: Bool, observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) -> Docs.Decision:
  Docs.FenceObservation{key, epoch, revision, ordinal, kind, info, info_complete, code, closed, +input_prefix} = observation
  Docs.Document{+source, +text, current_epoch, current_revision, +ending, observed, fences, active} = document
  Docs.accepted_input(eligible, UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed,
    Docs.fence_ending(SafeText.string_equal(input_prefix, text), ending), Docs.external(document, state)}, state)

def completed_producer_meaning(+source: Code.Source) ->
  {Docs.external_source(source) == Spec.completed_producer(source) : Bool}:
  match source:
    case Code.Generated{namespace, viewer, D.OutputOrigin{producer, operation, part, mode}, True{}}: {==}
    case Code.Generated{namespace, viewer, D.OutputOrigin{producer, operation, part, mode}, False{}}: {==}
    case Code.Message{task, message}: {==}
    case Code.StreamingPart{task, operation, part}: {==}

def complete_ending_meaning(+ending: UI.Ending) ->
  {Docs.same_ending(ending, UI.Complete{}) == Spec.complete_ending(ending) : Bool}:
  match ending:
    case UI.Open{}: {==}
    case UI.Complete{}: {==}
    case UI.Interrupted{}: {==}

def external_meaning(+document: Docs.Document, +state: Docs.State) ->
  {Docs.external(document, state) == Spec.external_permission(document, state) : Bool}:
  Docs.Document{+source, text, epoch, revision, +ending, observed, fences, +active} = document
  Docs.State{+namespace, sequence, +fresh, +allowed, +ready, documents, core, next, retention} = state
  Equal.trans(Bool, Docs.external(document, state),
    active && fresh && allowed && ready && Spec.canonical_source(namespace, source) && Docs.external_source(source) && Docs.same_ending(ending, UI.Complete{}),
    Spec.external_permission(document, state),
    Equal.cong(Bool, Bool, scoped => active && fresh && allowed && ready && scoped && Docs.external_source(source) && Docs.same_ending(ending, UI.Complete{}),
      Docs.source_scope(source, namespace), Spec.canonical_source(namespace, source), source_meaning(source, namespace)),
    Equal.trans(Bool,
      active && fresh && allowed && ready && Spec.canonical_source(namespace, source) && Docs.external_source(source) && Docs.same_ending(ending, UI.Complete{}),
      active && fresh && allowed && ready && Spec.canonical_source(namespace, source) && Spec.completed_producer(source) && Docs.same_ending(ending, UI.Complete{}),
      Spec.external_permission(document, state),
      Equal.cong(Bool, Bool, completed => active && fresh && allowed && ready && Spec.canonical_source(namespace, source) && completed && Docs.same_ending(ending, UI.Complete{}),
        Docs.external_source(source), Spec.completed_producer(source), completed_producer_meaning(source)),
      Equal.cong(Bool, Bool, terminal => active && fresh && allowed && ready && Spec.canonical_source(namespace, source) && Spec.completed_producer(source) && terminal,
        Docs.same_ending(ending, UI.Complete{}), Spec.complete_ending(ending), complete_ending_meaning(ending))))

def ending_choice_meaning(+caught_up: Bool, +ending: UI.Ending) ->
  {Docs.fence_ending(caught_up, ending) == Bool.pick(UI.Ending, caught_up, ending, UI.Open{}) : UI.Ending}:
  match caught_up:
    case False{}: {==}
    case True{}: {==}

def application_meaning(+eligible: Bool, +observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) ->
  {actual_observation_input(eligible, observation, document, state) == Spec.apply_observation(eligible, observation, document, state) : Docs.Decision}:
  match eligible:
    case False{}:
      Docs.FenceObservation{key, epoch, revision, ordinal, kind, info, info_complete, code, closed, input_prefix} = observation
      Docs.Document{source, text, current_epoch, current_revision, ending, observed, fences, active} = document
      {==}
    case True{}:
      Docs.FenceObservation{key, epoch, revision, +ordinal, kind, info, info_complete, +code, +closed, +input_prefix} = observation
      Docs.Document{+source, +text, +current_epoch, current_revision, +ending, observed, fences, active} = document
      +terminal = Bool.pick(UI.Ending, SafeText.string_equal(input_prefix, text), ending, UI.Open{})
      Equal.trans(Docs.Decision, actual_observation_input(True{}, observation, document, state),
        Spec.required_input(UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed, terminal, Docs.external(document, state)}, state), Spec.apply_observation(True{}, observation, document, state),
        Equal.trans(Docs.Decision, actual_observation_input(True{}, observation, document, state),
          Docs.input(UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed, terminal, Docs.external(document, state)}, state),
          Spec.required_input(UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed, terminal, Docs.external(document, state)}, state),
          Equal.cong(UI.Ending, Docs.Decision, ending => Docs.input(UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed, ending, Docs.external(document, state)}, state),
            Docs.fence_ending(SafeText.string_equal(input_prefix, text), ending), terminal, ending_choice_meaning(SafeText.string_equal(input_prefix, text), ending)),
          input_meaning(UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed, terminal, Docs.external(document, state)}, state)),
        Equal.cong(Bool, Docs.Decision, allowed => Spec.required_input(UI.SourceChanged{Docs.owner(source, ordinal, current_epoch), code, closed, terminal, allowed}, state),
          Docs.external(document, state), Spec.external_permission(document, state), external_meaning(document, state)))

def accepted_fence_meaning(+eligible: Bool, +observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) ->
  {Docs.accepted_fence(eligible, observation, document, state) == Spec.observed_fence(eligible, observation, document, state) : Docs.Decision}:
  Docs.FenceObservation{+key, +epoch, +revision, +ordinal, +kind, +info, +info_complete, +code, +closed, +input_prefix} = observation
  Docs.Document{+source, +text, +current_epoch, +current_revision, +ending, +observed, +fences, +active} = document
  Docs.State{+namespace, +sequence, +fresh, +allowed, +ready, +documents, +core, +next, +retention} = state
  Equal.trans(Docs.Decision, Docs.accepted_fence(eligible, observation, document, state),
    Spec.apply_observation(eligible, observation, document, actual_observation_state(eligible, observation, document, state)), Spec.observed_fence(eligible, observation, document, state),
    application_meaning(eligible, observation, document, actual_observation_state(eligible, observation, document, state)),
    Equal.cong(Docs.State, Docs.Decision, updated => Spec.apply_observation(eligible, observation, document, updated),
      actual_observation_state(eligible, observation, document, state), Spec.observation_state(eligible, observation, document, state), observation_state_meaning(eligible, observation, document, state)))

def monotonic_branch_meaning(+monotonic: Bool, +eligible: Bool, +observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) ->
  {Docs.observe_monotonic(monotonic, eligible, observation, document, state) == Spec.observe_result(monotonic, eligible, observation, document, state) : Docs.Decision}:
  match monotonic:
    case False{}: {==}
    case True{}: accepted_fence_meaning(eligible, observation, document, state)

def actual_eligible(observation: Docs.FenceObservation, document: Docs.Document) -> Bool:
  Docs.FenceObservation{key, epoch, revision, +ordinal, kind, info, info_complete, code, closed, input_prefix} = observation
  Docs.Document{source, text, current_epoch, current_revision, ending, observed, +fences, active} = document
  Core.eligible_fence(Docs.interactive_source(source), kind, info, info_complete) && (Docs.ordinal_eligible(fences, ordinal) || Nat.is_lt(Docs.fence_eligible_count(fences), 16n))

def checked_observation_meaning(+valid: Bool, +observation: Docs.FenceObservation, +document: Docs.Document, +state: Docs.State) ->
  {Docs.observe_checked(valid, observation, document, state) ==
    Spec.observe_result(valid && Spec.observation_extends(observation, document, Spec.observation_eligible(observation, document)), Spec.observation_eligible(observation, document), observation, document, state) : Docs.Decision}:
  match valid:
    case False{}: {==}
    case True{}:
      Docs.FenceObservation{key, epoch, revision, +ordinal, +kind, +info, +info_complete, +code, +closed, input_prefix} = observation
      Docs.Document{+source, text, current_epoch, current_revision, ending, observed, +fences, active} = document
      Equal.trans(Docs.Decision, Docs.observe_checked(True{}, observation, document, state),
        Spec.observe_result(Spec.observation_extends(observation, document, actual_eligible(observation, document)), actual_eligible(observation, document), observation, document, state),
        Spec.observe_result(Spec.observation_extends(observation, document, Spec.observation_eligible(observation, document)), Spec.observation_eligible(observation, document), observation, document, state),
        Equal.trans(Docs.Decision, Docs.observe_checked(True{}, observation, document, state),
          Spec.observe_result(Docs.fence_monotonic(fences, ordinal, actual_eligible(observation, document), code, closed), actual_eligible(observation, document), observation, document, state),
          Spec.observe_result(Spec.observation_extends(observation, document, actual_eligible(observation, document)), actual_eligible(observation, document), observation, document, state),
          monotonic_branch_meaning(Docs.fence_monotonic(fences, ordinal, actual_eligible(observation, document), code, closed), actual_eligible(observation, document), observation, document, state),
          Equal.cong(Bool, Docs.Decision, extends => Spec.observe_result(extends, actual_eligible(observation, document), observation, document, state),
            Docs.fence_monotonic(fences, ordinal, actual_eligible(observation, document), code, closed), Spec.observation_extends(observation, document, actual_eligible(observation, document)), extension_meaning(fences, ordinal, actual_eligible(observation, document), code, closed))),
        Equal.cong(Bool, Docs.Decision, eligible => Spec.observe_result(Spec.observation_extends(observation, document, eligible), eligible, observation, document, state),
          actual_eligible(observation, document), Spec.observation_eligible(observation, document), eligibility_meaning(source, kind, info, info_complete, ordinal, fences)))

def found_observation_meaning(+found: Maybe<&2, Docs.Document>, +observation: Docs.FenceObservation, +state: Docs.State) ->
  {Docs.observe_found(found, observation, state) == Spec.observe_found(found, observation, state) : Docs.Decision}:
  match found:
    case None{}: {==}
    case Some{+document}:
      +valid = Docs.source_scope_document(document, Docs.namespace(state)) && Docs.observation_valid(observation, document) &&
        Bool.not(Docs.entry_archived(Docs.retained_entries(Docs.retention(state)), Docs.document_key(document)))
      Equal.trans(Docs.Decision, Docs.observe_found(Some{document}, observation, state),
        Spec.observe_result(valid && Spec.observation_extends(observation, document, Spec.observation_eligible(observation, document)), Spec.observation_eligible(observation, document), observation, document, state), Spec.observe_found(Some{document}, observation, state),
        checked_observation_meaning(valid, observation, document, state),
        Equal.cong(Bool, Docs.Decision, accepted => Spec.observe_result(accepted && Spec.observation_extends(observation, document, Spec.observation_eligible(observation, document)), Spec.observation_eligible(observation, document), observation, document, state),
          valid, Spec.accepts_observation(observation, document, state), observation_guard_meaning(observation, document, state)))

def observation_meaning(+observation: Docs.FenceObservation, +state: Docs.State) ->
  {Docs.observe(observation, state) == Spec.required_observe(observation, state) : Docs.Decision}:
  Docs.FenceObservation{+key, epoch, revision, ordinal, kind, info, info_complete, code, closed, input_prefix} = observation
  Equal.trans(Docs.Decision, Docs.observe(observation, state), Spec.observe_found(Docs.find(Docs.documents(state), key), observation, state), Spec.required_observe(observation, state),
    found_observation_meaning(Docs.find(Docs.documents(state), key), observation, state),
    Equal.cong(Maybe<&2, Docs.Document>, Docs.Decision, found => Spec.observe_found(found, observation, state),
      Docs.find(Docs.documents(state), key), Spec.document_lookup(key, Docs.documents(state)), lookup_meaning(Docs.documents(state), key)))

def forbidden_meaning(+requests: +List<UI.SourceRequest>, +sequence: Nat) ->
  {Docs.forbidden_sources(requests, sequence) == Spec.forbidden_values(requests, sequence) : +List<Json.Field>}:
  match requests:
    case Nil{}: {==}
    case Con{UI.SourceRequest{owner, +name, graph}, +rest}:
      Equal.cong(+List<Json.Field>, +List<Json.Field>, tail => Json.Field{name, Sources.source_handle("forbidden", False{}, sequence, Json.Null{})} <> tail,
        Docs.forbidden_sources(rest, sequence), Spec.forbidden_values(rest, sequence), forbidden_meaning(rest, sequence))

def source_values_meaning(+allowed: Bool, +requests: +List<UI.SourceRequest>, +world: Harness.World(), +sequence: Nat, +fresh: Bool) ->
  {Docs.project_sources(allowed, requests, world, sequence, fresh) == Spec.source_values(allowed, requests, world, sequence, fresh) : +List<Json.Field>}:
  match allowed:
    case True{}: {==}
    case False{}: forbidden_meaning(requests, sequence)

def request_choice_meaning(+keep: Bool, +request: UI.SourceRequest, +tail: +List<UI.SourceRequest>) ->
  {Docs.keep_request(keep, request, tail) == Bool.pick(+List<UI.SourceRequest>, keep, request <> tail, tail) : +List<UI.SourceRequest>}:
  match keep:
    case False{}: {==}
    case True{}: {==}

def requests_meaning(+requests: +List<UI.SourceRequest>, +key: String) ->
  {Docs.select_requests(requests, key) == Spec.selected_requests(key, requests) : +List<UI.SourceRequest>}:
  match requests:
    case Nil{}: {==}
    case Con{UI.SourceRequest{UI.Owner{+current, +epoch}, +name, +graph}, +rest}:
      +request: UI.SourceRequest = UI.SourceRequest{UI.Owner{current, epoch}, name, graph}
      Equal.trans(+List<UI.SourceRequest>, Docs.select_requests(request <> rest, key),
        Bool.pick(+List<UI.SourceRequest>, String.eq(current, key), request <> Docs.select_requests(rest, key), Docs.select_requests(rest, key)), Spec.selected_requests(key, request <> rest),
        request_choice_meaning(String.eq(current, key), request, Docs.select_requests(rest, key)),
        Equal.cong(+List<UI.SourceRequest>, +List<UI.SourceRequest>, tail => Bool.pick(+List<UI.SourceRequest>, String.eq(current, key), request <> tail, tail),
          Docs.select_requests(rest, key), Spec.selected_requests(key, rest), requests_meaning(rest, key)))

def append_result_meaning(+effects: +List<Docs.Effect>, +result: Docs.Decision) ->
  {Docs.append_result(effects, result) == Spec.append_decision(effects, result) : Docs.Decision}:
  match result:
    case Docs.Decision{state, after}: {==}

def continuation_meaning(+first: Docs.Decision, continuation: @+state:Docs.State -> Docs.Decision) ->
  {Docs.append_result(Docs.result_effects(first), continuation(Docs.result_state(first))) == Spec.after_decision(first, continuation) : Docs.Decision}:
  match first:
    case Docs.Decision{+state, +effects}: append_result_meaning(effects, continuation(state))

def following_input_meaning(+first: Docs.Decision, +owner: UI.Owner, +document: Docs.Document) ->
  {Spec.after_decision(first, +next => Docs.input(UI.ExternalChanged{owner, Docs.external(document, next)}, next)) ==
    Spec.after_decision(first, +next => Spec.required_input(UI.ExternalChanged{owner, Spec.external_permission(document, next)}, next)) : Docs.Decision}:
  match first:
    case Docs.Decision{+state, +effects}:
      Equal.cong(Docs.Decision, Docs.Decision, last => Spec.append_decision(effects, last),
        Docs.input(UI.ExternalChanged{owner, Docs.external(document, state)}, state), Spec.required_input(UI.ExternalChanged{owner, Spec.external_permission(document, state)}, state),
        Equal.trans(Docs.Decision, Docs.input(UI.ExternalChanged{owner, Docs.external(document, state)}, state),
          Spec.required_input(UI.ExternalChanged{owner, Docs.external(document, state)}, state), Spec.required_input(UI.ExternalChanged{owner, Spec.external_permission(document, state)}, state),
          input_meaning(UI.ExternalChanged{owner, Docs.external(document, state)}, state),
          Equal.cong(Bool, Docs.Decision, allowed => Spec.required_input(UI.ExternalChanged{owner, allowed}, state),
            Docs.external(document, state), Spec.external_permission(document, state), external_meaning(document, state))))

def scoped_fence_meaning(+eligible: Bool, +ordinal: Nat, +document: Docs.Document, +world: Harness.World(), +state: Docs.State) ->
  {Docs.refresh_scoped_fence(eligible, ordinal, document, world, state) == Spec.snapshot_fence(eligible, ordinal, document, world, state) : Docs.Decision}:
  match eligible:
    case False{}: {==}
    case True{}:
      Docs.Document{+source, text, +epoch, revision, ending, observed, fences, active} = document
      Docs.State{namespace, +sequence, +fresh, +allowed, ready, documents, +core, next, retention} = state
      +owner = Docs.owner(source, ordinal, epoch)
      +key = Docs.owner_key(owner)
      +requests = Docs.select_requests(Core.source_requests(core), key)
      +expected_requests = Spec.selected_requests(key, Core.source_requests(core))
      +actual_first = Docs.input(UI.SourcesChanged{owner, Docs.project_sources(allowed, requests, world, sequence, fresh)}, state)
      +expected_first = Spec.required_input(UI.SourcesChanged{owner, Spec.source_values(allowed, expected_requests, world, sequence, fresh)}, state)
      Equal.trans(Docs.Decision, Docs.refresh_scoped_fence(True{}, ordinal, document, world, state),
        Spec.after_decision(expected_first, +next => Docs.input(UI.ExternalChanged{owner, Docs.external(document, next)}, next)), Spec.snapshot_fence(True{}, ordinal, document, world, state),
        Equal.trans(Docs.Decision, Docs.refresh_scoped_fence(True{}, ordinal, document, world, state),
          Spec.after_decision(actual_first, +next => Docs.input(UI.ExternalChanged{owner, Docs.external(document, next)}, next)),
          Spec.after_decision(expected_first, +next => Docs.input(UI.ExternalChanged{owner, Docs.external(document, next)}, next)),
          continuation_meaning(actual_first, +next => Docs.input(UI.ExternalChanged{owner, Docs.external(document, next)}, next)),
          Equal.cong(Docs.Decision, Docs.Decision, first => Spec.after_decision(first, +next => Docs.input(UI.ExternalChanged{owner, Docs.external(document, next)}, next)),
            actual_first, expected_first,
            Equal.trans(Docs.Decision, actual_first,
              Spec.required_input(UI.SourcesChanged{owner, Docs.project_sources(allowed, requests, world, sequence, fresh)}, state), expected_first,
              input_meaning(UI.SourcesChanged{owner, Docs.project_sources(allowed, requests, world, sequence, fresh)}, state),
              Equal.cong(+List<Json.Field>, Docs.Decision, values => Spec.required_input(UI.SourcesChanged{owner, values}, state),
                Docs.project_sources(allowed, requests, world, sequence, fresh), Spec.source_values(allowed, expected_requests, world, sequence, fresh),
                Equal.trans(+List<Json.Field>, Docs.project_sources(allowed, requests, world, sequence, fresh), Spec.source_values(allowed, requests, world, sequence, fresh), Spec.source_values(allowed, expected_requests, world, sequence, fresh),
                  source_values_meaning(allowed, requests, world, sequence, fresh),
                  Equal.cong(+List<UI.SourceRequest>, +List<Json.Field>, selected => Spec.source_values(allowed, selected, world, sequence, fresh),
                    requests, expected_requests, requests_meaning(Core.source_requests(core), key))))))),
        following_input_meaning(expected_first, owner, document))

def refresh_fence_meaning(+eligible: Bool, +ordinal: Nat, +document: Docs.Document, +world: Harness.World(), +state: Docs.State) ->
  {Docs.refresh_fence(eligible, ordinal, document, world, state) ==
    Spec.snapshot_fence(eligible && Spec.canonical_source(Docs.namespace(state), Spec.document_source(document)), ordinal, document, world, state) : Docs.Decision}:
  Docs.Document{+source, +text, +epoch, +revision, +ending, +observed, +fences, +active} = document
  Equal.trans(Docs.Decision, Docs.refresh_fence(eligible, ordinal, document, world, state),
    Spec.snapshot_fence(eligible && Docs.source_scope_document(document, Docs.namespace(state)), ordinal, document, world, state),
    Spec.snapshot_fence(eligible && Spec.canonical_source(Docs.namespace(state), Spec.document_source(document)), ordinal, document, world, state),
    scoped_fence_meaning(eligible && Docs.source_scope_document(document, Docs.namespace(state)), ordinal, document, world, state),
    Equal.cong(Bool, Docs.Decision, scoped => Spec.snapshot_fence(eligible && scoped, ordinal, document, world, state),
      Docs.source_scope_document(document, Docs.namespace(state)), Spec.canonical_source(Docs.namespace(state), Spec.document_source(document)), source_meaning(Spec.document_source(document), Docs.namespace(state))))

def fence_continuation_meaning(+first: Docs.Decision, +fences: +List<Docs.Fence>, +document: Docs.Document, +world: Harness.World(),
  recursive: @+state:Docs.State -> {Docs.refresh_fences(fences, document, world, state) == Spec.fence_plan(document, world, fences)(state) : Docs.Decision}) ->
  {Docs.append_result(Docs.result_effects(first), Docs.refresh_fences(fences, document, world, Docs.result_state(first))) ==
    Spec.after_decision(first, Spec.fence_plan(document, world, fences)) : Docs.Decision}:
  match first:
    case Docs.Decision{+state, +effects}:
      Equal.trans(Docs.Decision, Docs.append_result(effects, Docs.refresh_fences(fences, document, world, state)),
        Spec.append_decision(effects, Docs.refresh_fences(fences, document, world, state)), Spec.append_decision(effects, Spec.fence_plan(document, world, fences)(state)),
        append_result_meaning(effects, Docs.refresh_fences(fences, document, world, state)),
        Equal.cong(Docs.Decision, Docs.Decision, result => Spec.append_decision(effects, result),
          Docs.refresh_fences(fences, document, world, state), Spec.fence_plan(document, world, fences)(state), recursive(state)))

def fence_plan_meaning(+fences: +List<Docs.Fence>, +document: Docs.Document, +world: Harness.World(), +state: Docs.State) ->
  {Docs.refresh_fences(fences, document, world, state) == Spec.fence_plan(document, world, fences)(state) : Docs.Decision}:
  match fences:
    case Nil{}: {==}
    case Con{Docs.Fence{+ordinal, +eligible, +code, +closed, +visible}, +rest}:
      +first = Docs.refresh_fence(eligible, ordinal, document, world, state)
      +required_first = Spec.refresh_fence_plan(document, world, Docs.Fence{ordinal, eligible, code, closed, visible}, state)
      Equal.trans(Docs.Decision, Docs.refresh_fences(Docs.Fence{ordinal, eligible, code, closed, visible} <> rest, document, world, state),
        Spec.after_decision(first, Spec.fence_plan(document, world, rest)), Spec.fence_plan(document, world, Docs.Fence{ordinal, eligible, code, closed, visible} <> rest)(state),
        fence_continuation_meaning(first, rest, document, world, +next => fence_plan_meaning(rest, document, world, next)),
        Equal.cong(Docs.Decision, Docs.Decision, result => Spec.after_decision(result, Spec.fence_plan(document, world, rest)), first, required_first, refresh_fence_meaning(eligible, ordinal, document, world, state)))

def document_continuation_meaning(+first: Docs.Decision, +documents: +List<Docs.Document>, +world: Harness.World(),
  recursive: @+state:Docs.State -> {Docs.refresh_documents(documents, world, state) == Spec.document_plan(world, documents)(state) : Docs.Decision}) ->
  {Docs.append_result(Docs.result_effects(first), Docs.refresh_documents(documents, world, Docs.result_state(first))) == Spec.after_decision(first, Spec.document_plan(world, documents)) : Docs.Decision}:
  match first:
    case Docs.Decision{+state, +effects}:
      Equal.trans(Docs.Decision, Docs.append_result(effects, Docs.refresh_documents(documents, world, state)),
        Spec.append_decision(effects, Docs.refresh_documents(documents, world, state)), Spec.append_decision(effects, Spec.document_plan(world, documents)(state)),
        append_result_meaning(effects, Docs.refresh_documents(documents, world, state)),
        Equal.cong(Docs.Decision, Docs.Decision, result => Spec.append_decision(effects, result),
          Docs.refresh_documents(documents, world, state), Spec.document_plan(world, documents)(state), recursive(state)))

def document_plan_meaning(+documents: +List<Docs.Document>, +world: Harness.World(), +state: Docs.State) ->
  {Docs.refresh_documents(documents, world, state) == Spec.document_plan(world, documents)(state) : Docs.Decision}:
  match documents:
    case Nil{}: {==}
    case Con{+document, +rest}:
      Docs.Document{+source, +text, +epoch, +revision, +ending, +observed, +fences, +active} = document
      +first = Docs.refresh_fences(Spec.document_fences(document), document, world, state)
      Equal.trans(Docs.Decision, Docs.refresh_documents(document <> rest, world, state),
        Spec.after_decision(first, Spec.document_plan(world, rest)), Spec.document_plan(world, document <> rest)(state),
        document_continuation_meaning(first, rest, world, +next => document_plan_meaning(rest, world, next)),
        Equal.cong(Docs.Decision, Docs.Decision, result => Spec.after_decision(result, Spec.document_plan(world, rest)),
          first, Spec.fence_plan(document, world, Spec.document_fences(document))(state), fence_plan_meaning(Spec.document_fences(document), document, world, state)))

def refresh_meaning(+world: Harness.World(), +state: Docs.State) ->
  {Docs.refresh(world, state) == Spec.required_refresh(world, state) : Docs.Decision}:
  document_plan_meaning(Docs.documents(state), world, state)

def owner_task_authority(+store: String, +source: Code.Source, +active: Bool, +fences: +List<Docs.Fence>, +epoch: Nat, +expected: UI.Owner) ->
  {Docs.source_scope(source, store) && active && Docs.external_source(source) && Docs.owner_matches(fences, source, epoch, expected) ==
    Spec.canonical_source(store, source) && active && Spec.completed_producer(source) && Spec.fence_owned(source, epoch, expected, fences) : Bool}:
  Equal.trans(Bool, Docs.source_scope(source, store) && active && Docs.external_source(source) && Docs.owner_matches(fences, source, epoch, expected),
    Spec.canonical_source(store, source) && active && Docs.external_source(source) && Docs.owner_matches(fences, source, epoch, expected),
    Spec.canonical_source(store, source) && active && Spec.completed_producer(source) && Spec.fence_owned(source, epoch, expected, fences),
    Equal.cong(Bool, Bool, scoped => scoped && active && Docs.external_source(source) && Docs.owner_matches(fences, source, epoch, expected), Docs.source_scope(source, store), Spec.canonical_source(store, source), source_meaning(source, store)),
    Equal.trans(Bool, Spec.canonical_source(store, source) && active && Docs.external_source(source) && Docs.owner_matches(fences, source, epoch, expected),
      Spec.canonical_source(store, source) && active && Spec.completed_producer(source) && Docs.owner_matches(fences, source, epoch, expected),
      Spec.canonical_source(store, source) && active && Spec.completed_producer(source) && Spec.fence_owned(source, epoch, expected, fences),
      Equal.cong(Bool, Bool, completed => Spec.canonical_source(store, source) && active && completed && Docs.owner_matches(fences, source, epoch, expected), Docs.external_source(source), Spec.completed_producer(source), completed_producer_meaning(source)),
      Equal.cong(Bool, Bool, owned => Spec.canonical_source(store, source) && active && Spec.completed_producer(source) && owned,
        Docs.owner_matches(fences, source, epoch, expected), Spec.fence_owned(source, epoch, expected, fences), fence_owner_meaning(fences, source, epoch, expected))))

def task_choice_meaning(+owned: Bool, +task: Nat, +fallback: Maybe<&2, Nat>) ->
  {Docs.task_if_owned(owned, task, fallback) == Bool.pick(Maybe<&2, Nat>, owned, Some{task}, fallback) : Maybe<&2, Nat>}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def task_owner_meaning(+store: String, +documents: +List<Docs.Document>, +expected: UI.Owner) ->
  {Docs.owning_task(store, documents, expected) == Spec.task_owner(store, expected, documents) : Maybe<&2, Nat>}:
  match documents:
    case Nil{}: {==}
    case Con{Docs.Document{+source, +text, +epoch, +revision, +ending, +observed, +fences, +active}, +rest}:
      +document: Docs.Document = Docs.Document{source, text, epoch, revision, ending, observed, fences, active}
      +authorized: Bool = Docs.source_scope(source, store) && active && Docs.external_source(source) && Docs.owner_matches(fences, source, epoch, expected)
      Equal.trans(Maybe<&2, Nat>, Docs.owning_task(store, document <> rest, expected),
        Bool.pick(Maybe<&2, Nat>, authorized, Some{Docs.source_viewer(source)}, Docs.owning_task(store, rest, expected)), Spec.task_owner(store, expected, document <> rest),
        task_choice_meaning(authorized, Docs.source_viewer(source), Docs.owning_task(store, rest, expected)),
        Equal.trans(Maybe<&2, Nat>, Bool.pick(Maybe<&2, Nat>, authorized, Some{Docs.source_viewer(source)}, Docs.owning_task(store, rest, expected)),
          Spec.task_from_document(store, expected, document, Docs.owning_task(store, rest, expected)), Spec.task_owner(store, expected, document <> rest),
          Equal.cong(Bool, Maybe<&2, Nat>, owned => Bool.pick(Maybe<&2, Nat>, owned, Some{Docs.source_viewer(source)}, Docs.owning_task(store, rest, expected)),
            authorized, Spec.canonical_source(store, source) && active && Spec.completed_producer(source) && Spec.fence_owned(source, epoch, expected, fences),
            owner_task_authority(store, source, active, fences, epoch, expected)),
          Equal.cong(Maybe<&2, Nat>, Maybe<&2, Nat>, fallback => Spec.task_from_document(store, expected, document, fallback),
            Docs.owning_task(store, rest, expected), Spec.task_owner(store, expected, rest), task_owner_meaning(store, rest, expected))))

def current_task_owner_meaning(+owner: UI.Owner, +state: Docs.State) ->
  {Docs.current_owning_task(owner, state) == Spec.task_owner(Docs.namespace(state), owner, Docs.documents(state)) : Maybe<&2, Nat>}:
  task_owner_meaning(Docs.namespace(state), Docs.documents(state), owner)

def retained_choice_meaning(+equal: Bool, +entry: Docs.RetainedEntry, +tail: +List<Docs.RetainedEntry>) ->
  {Docs.keep_entry(Bool.not(equal), entry, tail) == Bool.pick(+List<Docs.RetainedEntry>, equal, tail, entry <> tail) : +List<Docs.RetainedEntry>}:
  match equal:
    case False{}: {==}
    case True{}: {==}

def retained_without_meaning(+entries: +List<Docs.RetainedEntry>, +key: String) ->
  {Docs.without_entry(entries, key) == Spec.retained_without(key, entries) : +List<Docs.RetainedEntry>}:
  match entries:
    case Nil{}: {==}
    case Con{Docs.RetainedEntry{+current, +archived, +visible, +dormant}, +rest}:
      +entry: Docs.RetainedEntry = Docs.RetainedEntry{current, archived, visible, dormant}
      Equal.trans(+List<Docs.RetainedEntry>, Docs.without_entry(entry <> rest, key),
        Bool.pick(+List<Docs.RetainedEntry>, String.eq(current, key), Docs.without_entry(rest, key), entry <> Docs.without_entry(rest, key)), Spec.retained_without(key, entry <> rest),
        retained_choice_meaning(String.eq(current, key), entry, Docs.without_entry(rest, key)),
        Equal.cong(+List<Docs.RetainedEntry>, +List<Docs.RetainedEntry>, tail => Bool.pick(+List<Docs.RetainedEntry>, String.eq(current, key), tail, entry <> tail),
          Docs.without_entry(rest, key), Spec.retained_without(key, rest), retained_without_meaning(rest, key)))

def publication_meaning(+document: Docs.Document, +state: Docs.State) ->
  {Docs.publish_document(document, state) == Spec.publication(document, state) : Docs.Decision}:
  match state:
    case Docs.State{+namespace, +sequence, +fresh, +allowed, +ready, +documents, +core, +next, Docs.Retention{+entries, +discarded}}:
      Equal.trans(Docs.Decision, Docs.publish_document(document, state),
        Docs.Decision{Docs.State{namespace, sequence, fresh, allowed, ready, Spec.write_document(documents, document), core, next,
          Docs.Retention{Docs.without_entry(entries, Docs.document_key(document)), discarded}}, [Docs.ObserveMarkdown{document}]}, Spec.publication(document, state),
        Equal.cong(+List<Docs.Document>, Docs.Decision, values => Docs.Decision{Docs.State{namespace, sequence, fresh, allowed, ready, values, core, next,
          Docs.Retention{Docs.without_entry(entries, Docs.document_key(document)), discarded}}, [Docs.ObserveMarkdown{document}]},
          Docs.save(documents, document), Spec.write_document(documents, document), write_document_meaning(documents, document)),
        Equal.cong(+List<Docs.RetainedEntry>, Docs.Decision, values => Docs.Decision{Docs.State{namespace, sequence, fresh, allowed, ready, Spec.write_document(documents, document), core, next,
          Docs.Retention{values, discarded}}, [Docs.ObserveMarkdown{document}]},
          Docs.without_entry(entries, Docs.document_key(document)), Spec.retained_without(Docs.document_key(document), entries), retained_without_meaning(entries, Docs.document_key(document))))

# These premises are text/identity facts, not the result of an implementation
# admission helper. They include terminal Complete/Interrupted promotion with
# unchanged text, as well as a strict streaming suffix.
def continuous_update(+source: Code.Source, +text: String, +ending: UI.Ending, +old_source: Code.Source, +old_text: String,
  +epoch: Nat, +revision: Nat, +observed: Nat, +fences: +List<Docs.Fence>, +active: Bool, +rest: +List<Docs.Document>,
  +namespace: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +ready: Bool, +core: UI.State, +next: Nat, +retention: Docs.Retention,
  same_source: {String.eq(Code.source_key(old_source), Code.source_key(source)) == True{} : Bool},
  prefix: {String.starts_with(text, old_text) == True{} : Bool},
  changed: {SafeText.string_equal(old_text, text) && Docs.same_ending(UI.Open{}, ending) == False{} : Bool}) ->
  {Docs.put(True{}, source, text, ending, Docs.State{namespace, sequence, fresh, allowed, ready,
      Docs.Document{old_source, old_text, epoch, revision, UI.Open{}, observed, fences, active} <> rest, core, next, retention}) ==
    Spec.publication(Docs.Document{source, text, epoch, 1n+revision, ending, observed, fences, True{}},
      Docs.State{namespace, sequence, fresh, allowed, ready,
        Docs.Document{old_source, old_text, epoch, revision, UI.Open{}, observed, fences, active} <> rest, core, 1n+next, retention}) : Docs.Decision}:
  +previous: Docs.Document = Docs.Document{old_source, old_text, epoch, revision, UI.Open{}, observed, fences, active}
  +state: Docs.State = Docs.State{namespace, sequence, fresh, allowed, ready, previous <> rest, core, next, retention}
  +next_state: Docs.State = Docs.State{namespace, sequence, fresh, allowed, ready, previous <> rest, core, 1n+next, retention}
  +updated: Docs.Document = Docs.Document{source, text, epoch, 1n+revision, ending, observed, fences, True{}}
  Equal.trans(Docs.Decision, Docs.put(True{}, source, text, ending, state), Docs.put_found(Some{previous}, source, text, ending, state), Spec.publication(updated, next_state),
    Equal.cong(Bool, Docs.Decision, same => Docs.put_found(Docs.choose_document(same, previous, Docs.find(rest, Code.source_key(source))), source, text, ending, state),
      String.eq(Code.source_key(old_source), Code.source_key(source)), True{}, same_source),
    Equal.trans(Docs.Decision, Docs.put_found(Some{previous}, source, text, ending, state), Docs.put_existing(False{}, source, text, ending, previous, state), Spec.publication(updated, next_state),
      Equal.cong(Bool, Docs.Decision, same => Docs.put_existing(same, source, text, ending, previous, state),
        SafeText.string_equal(old_text, text) && Docs.same_ending(UI.Open{}, ending), False{}, changed),
      Equal.trans(Docs.Decision, Docs.put_existing(False{}, source, text, ending, previous, state), Docs.publish_document(updated, next_state), Spec.publication(updated, next_state),
        Equal.cong(Bool, Docs.Decision, continuous => Docs.publish_updated(continuous, source, text, ending, previous, next, next_state),
          String.starts_with(text, old_text) && True{}, True{},
          Equal.cong(Bool, Bool, present => present && True{}, String.starts_with(text, old_text), True{}, prefix)), publication_meaning(updated, next_state))))

def final_dom_identity(+origin: D.OutputOrigin, +namespace: String, +viewer: Nat, +ordinal: Nat) ->
  {Code.key(Code.Identity{Code.Generated{namespace, viewer, origin, False{}}, ordinal}) ==
    Code.key(Code.Identity{Code.Generated{namespace, viewer, origin, True{}}, ordinal}) : String}:
  match origin:
    case D.OutputOrigin{producer, operation, part, mode}: {==}

def requirements() -> Spec.Requirements:
  Spec.Requirements{input_meaning, observation_meaning, environment_meaning, refresh_meaning,
    current_task_owner_meaning, external_meaning, continuous_update, final_dom_identity}

def Spec.evidence(): requirements()
