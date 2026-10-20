import Base
import ../../bendlib/string-equality.bend as SafeText
import ./TYPES.bend as UI
import ./MODEL.bend as Core
import ./SOURCES.bend as Sources
import ../conversation/CODE.bend as Code
import ../conversation/OUTPUT.bend as Live
import ../../harness/DOMAIN.bend as D
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/conversation/PROGRAM.bend as Conversation
import ../../bendlib/json.bend as J

# Canonical output provenance belongs to Bend. Markdown observations are facts
# from the shared streaming parser and never grant eligibility or authority.
type Fence is Data:
  Fence{ordinal: Nat, eligible: Bool, code: String, closed: Bool, source_visible: Bool}

type Document is Data:
  Document{source: Code.Source, text: String, epoch: Nat, revision: Nat,
    ending: UI.Ending, observed_prefix: Nat, fences: +List<Fence>, active: Bool}

type FenceObservation is Data:
  FenceObservation{key: String, epoch: Nat, revision: Nat, ordinal: Nat,
    kind: String, info: String, info_complete: Bool, code: String,
    closed: Bool, input_prefix: String}

type BlockScene is Data:
  BlockScene{identity: Code.Identity, scene: UI.Scene}

type RetainedPart is Data:
  RetainedPart{source: Code.Source, text: String, archived: Bool, visible: Bool, label: String}

type RetainedEntry is Data:
  RetainedEntry{key: String, archived: Bool, visible: Bool, dormant: Bool}

type Discarded is Data:
  Discarded{task: Nat, count: Nat}

type Retention is Data:
  Retention{entries: +List<RetainedEntry>, discarded: +List<Discarded>}

type State is Data:
  State{namespace: String, sequence: Nat, fresh: Bool, allowed: Bool,
    display_ready: Bool, documents: +List<Document>, core: UI.State, next_epoch: Nat, retention: Retention}

type Effect is Data:
  ObserveMarkdown{document: Document}
  ForgetMarkdown{key: String}
  CoreEffect{effect: UI.Effect}

type Decision is Data:
  Decision{state: State, effects: +List<Effect>}

def result_state(+result: Decision) -> State:
  Decision{+state, +effects} = result
  state

def result_effects(+result: Decision) -> +List<Effect>:
  Decision{+state, +effects} = result
  effects

def owner_key(+owner: UI.Owner) -> String:
  UI.Owner{+key, +epoch} = owner
  key

def retention(+state: State) -> Retention:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  retention

def with_retention(+value: Retention, +state: State) -> State:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  State{namespace, sequence, fresh, allowed, display_ready, documents, core, next_epoch, value}

def retained_entries(+value: Retention) -> +List<RetainedEntry>:
  Retention{+entries, +discarded} = value
  entries

def entry_archived(+entries: +List<RetainedEntry>, +key: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{RetainedEntry{+current, +archived, +visible, +dormant}, +rest}: (String.eq(current, key) && archived) || entry_archived(rest, key)

def entry_visible(+entries: +List<RetainedEntry>, +key: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{RetainedEntry{+current, +archived, +visible, +dormant}, +rest}: (String.eq(current, key) && visible) || entry_visible(rest, key)

def entry_dormant(+entries: +List<RetainedEntry>, +key: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{RetainedEntry{+current, +archived, +visible, +dormant}, +rest}: (String.eq(current, key) && dormant) || entry_dormant(rest, key)

def keep_entry(+keep: Bool, +entry: RetainedEntry, +rest: +List<RetainedEntry>) -> +List<RetainedEntry>:
  match keep:
    case True{}: entry <> rest
    case False{}: rest

def without_entry(+entries: +List<RetainedEntry>, +key: String) -> +List<RetainedEntry>:
  match entries:
    case Nil{}: Nil{}
    case Con{RetainedEntry{+current, +archived, +visible, +dormant}, +rest}: keep_entry(Bool.not(String.eq(current, key)), RetainedEntry{current, archived, visible, dormant}, without_entry(rest, key))

def forget_retained_value(+value: Retention, +key: String, +state: State) -> State:
  Retention{+entries, +discarded} = value
  with_retention(Retention{without_entry(entries, key), discarded}, state)

def forget_retained(+key: String, +state: State) -> State:
  forget_retained_value(retention(state), key, state)

def save_entry_value(+entry: RetainedEntry, +value: Retention, +state: State) -> State:
  RetainedEntry{+key, +archived, +visible, +dormant} = entry
  Retention{+entries, +discarded} = value
  with_retention(Retention{entry <> without_entry(entries, key), discarded}, state)

def save_entry(+entry: RetainedEntry, +state: State) -> State:
  save_entry_value(entry, retention(state), state)

def dormant(+key: String, +state: State) -> State:
  +entries: +List<RetainedEntry> = retained_entries(retention(state))
  +archived: Bool = entry_archived(entries, key)
  save_entry(RetainedEntry{key, archived, Bool.not(archived) || entry_visible(entries, key), True{}}, state)

def initial() -> State:
  State{"", 0n, False{}, True{}, True{}, Nil{}, Core.initial(), 1n, Retention{Nil{}, Nil{}}}

def namespace(+state: State) -> String:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  namespace

def core(+state: State) -> UI.State:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  core

def documents(+state: State) -> +List<Document>:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  documents

def with_core(+value: UI.State, +state: State) -> State:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  State{namespace, sequence, fresh, allowed, display_ready, documents, value, next_epoch, retention}

def with_documents(+value: +List<Document>, +state: State) -> State:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  State{namespace, sequence, fresh, allowed, display_ready, value, core, next_epoch, retention}

def document_key(+document: Document) -> String:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
  Code.source_key(source)

def same_ending(+left: UI.Ending, +right: UI.Ending) -> Bool:
  match left right:
    case UI.Open{} UI.Open{}: True{}
    case UI.Complete{} UI.Complete{}: True{}
    case UI.Interrupted{} UI.Interrupted{}: True{}
    case _ _: False{}

def prefix(+prefix: String, +text: String) -> Bool:
  String.starts_with(text, prefix)

def source_viewer(+source: Code.Source) -> Maybe<&2, Nat>:
  match source:
    case Code.SharedDocument{+namespace, +owner}: None{}
    case Code.Generated{+namespace, +viewer, +origin, +complete}: Some{viewer}
    case Code.Message{+task, +message}: Some{task}
    case Code.StreamingPart{+task, +operation, +part}: Some{task}

def interactive_source(+source: Code.Source) -> Bool:
  match source:
    case Code.Generated{+namespace, +viewer, D.OutputOrigin{+producer, +operation, +part, D.InteractiveV1{}}, +complete}: Live.valid_namespace(namespace)
    case _: False{}

# A retained fence is authoritative only inside its current journal namespace.
def source_scope(+source: Code.Source, +store: String) -> Bool:
  match source:
    case Code.SharedDocument{+namespace, +owner}: Live.valid_namespace(namespace) && String.eq(namespace, store)
    case Code.Generated{+namespace, +viewer, D.OutputOrigin{+producer, +operation, +part, D.InteractiveV1{}}, +complete}:
      Live.valid_namespace(namespace) && String.eq(namespace, store)
    case _: False{}

def source_scope_document(+document: Document, store: String) -> Bool:
  Document{source, text, epoch, revision, ending, observed_prefix, fences, active} = document
  source_scope(source, store)


def owner(+source: Code.Source, +ordinal: Nat, +epoch: Nat) -> UI.Owner:
  UI.Owner{Code.key(Code.Identity{source, ordinal}), epoch}

def external_source(+source: Code.Source) -> Bool:
  match source:
    case Code.SharedDocument{+namespace, +owner}: True{}
    case Code.Generated{+namespace, +viewer, D.OutputOrigin{+producer, +operation, +part, +mode}, True{}}: Nat.is_eq(viewer, producer)
    case _: False{}

def external(+document: Document, +state: State) -> Bool:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  active && fresh && allowed && display_ready && source_scope(source, namespace) && external_source(source) && same_ending(ending, UI.Complete{})

def choose_document(+hit: Bool, +document: Document, +fallback: Maybe<&2, Document>) -> Maybe<&2, Document>:
  match hit:
    case True{}: Some{document}
    case False{}: fallback

def find(+documents: +List<Document>, +key: String) -> Maybe<&2, Document>:
  match documents:
    case Nil{}: None{}
    case Con{+document, +rest}: choose_document(String.eq(document_key(document), key), document, find(rest, key))

def replace_document(+hit: Bool, +old: Document, +rest: +List<Document>, +value: Document, +fallback: +List<Document>) -> +List<Document>:
  match hit:
    case True{}: value <> rest
    case False{}: old <> fallback

def save(+documents: +List<Document>, +value: Document) -> +List<Document>:
  match documents:
    case Nil{}: [value]
    case Con{+old, +rest}: replace_document(String.eq(document_key(old), document_key(value)), old, rest, value, save(rest, value))

def core_effects(+effects: +List<UI.Effect>) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{+effect, +rest}: CoreEffect{effect} <> core_effects(rest)

def apply_core_result(+result: UI.Decision, +state: State) -> Decision:
  UI.Decision{+core, +effects} = result
  Decision{with_core(core, state), core_effects(effects)}

def owner_matches(+fences: +List<Fence>, +source: Code.Source, +epoch: Nat, +expected: UI.Owner) -> Bool:
  match fences:
    case Nil{}: False{}
    case Con{Fence{+ordinal, +eligible, +code, +closed, +source_visible}, +rest}:
      UI.Owner{+key, +e} = expected
      (eligible && Nat.is_eq(e, epoch) && String.eq(Code.key(Code.Identity{source, ordinal}), key)) || owner_matches(rest, source, epoch, expected)

def owner_known(+store: String, +values: +List<Document>, +expected: UI.Owner, +must_be_active: Bool) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}, +rest}:
      source_scope(source, store) && (Bool.not(must_be_active) || active) && owner_matches(fences, source, epoch, expected) || owner_known(store, rest, expected, must_be_active)

def input_allowed(+input: UI.Input, +state: State) -> Bool:
  match input:
    case UI.FieldEdited{UI.EventIdentity{UI.Identity{+owner, +path}, +occurrence}, +raw}: owner_known(namespace(state), documents(state), owner, True{})
    case UI.Activated{UI.EventIdentity{UI.Identity{+owner, +path}, +occurrence}}: owner_known(namespace(state), documents(state), owner, True{})
    case UI.ViewChanged{UI.EventIdentity{UI.Identity{+owner, +path}, +occurrence}, +command}: owner_known(namespace(state), documents(state), owner, True{})
    case UI.Restored{+owner, +definition, +payload}: owner_known(namespace(state), documents(state), owner, False{})
    case UI.StorageFailed{+owner, +message}: owner_known(namespace(state), documents(state), owner, False{})
    case UI.ContinueParsing{+owner}: owner_known(namespace(state), documents(state), owner, False{})
    case UI.EffectCompleted{+owner, +path, +ticket, +success, +message}: owner_known(namespace(state), documents(state), owner, False{})
    case _: True{}

def input_checked(+allowed: Bool, +input: UI.Input, +state: State) -> Decision:
  match allowed:
    case False{}: Decision{state, Nil{}}
    case True{}: apply_core_result(Core.step(input, core(state)), state)

def input(+input: UI.Input, +state: State) -> Decision:
  input_checked(input_allowed(input, state), input, state)

def append_result(+previous: +List<Effect>, +result: Decision) -> Decision:
  Decision{+state, +effects} = result
  Decision{state, List.append(&2, Effect, previous, effects)}

def remove_fences(+fences: +List<Fence>, +source: Code.Source, +epoch: Nat, +state: State) -> Decision:
  match fences:
    case Nil{}: Decision{state, Nil{}}
    case Con{Fence{+ordinal, +eligible, +code, +closed, +source_visible}, +rest}:
      +decision_1: Decision = input(UI.Removed{owner(source, ordinal, epoch)}, state)
      +next: State = result_state(decision_1)
      +effects: +List<Effect> = result_effects(decision_1)
      append_result(effects, remove_fences(rest, source, epoch, next))

def remove_old(+document: Document, +state: State) -> Decision:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
  remove_fences(fences, source, epoch, state)

def publish_document(+document: Document, +state: State) -> Decision:
  Decision{with_documents(save(documents(state), document), forget_retained(document_key(document), state)), [ObserveMarkdown{document}]}

def reactivate(+document: Document) -> Document:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
  Document{source, text, epoch, revision, ending, observed_prefix, fences, True{}}

def updated_document(+continuous: Bool, +source: Code.Source, +text: String, +ending: UI.Ending, +previous: Document, +epoch: Nat) -> Document:
  match continuous previous:
    case True{} Document{+old_source, +old_text, +old_epoch, +revision, +old_ending, +observed_prefix, +fences, +active}: Document{source, text, old_epoch, 1n+revision, ending, observed_prefix, fences, True{}}
    case False{} _: Document{source, text, epoch, 0n, ending, 0n, Nil{}, True{}}

def publish_updated(+continuous: Bool, +source: Code.Source, +text: String, +ending: UI.Ending, +previous: Document, +epoch: Nat, +state: State) -> Decision:
  match continuous:
    case True{}: publish_document(updated_document(True{}, source, text, ending, previous, epoch), state)
    case False{}:
      +decision_2: Decision = remove_old(previous, state)
      +next: State = result_state(decision_2)
      +effects: +List<Effect> = result_effects(decision_2)
      append_result(effects, publish_document(updated_document(False{}, source, text, ending, previous, epoch), next))

def put_existing(+same: Bool, +source: Code.Source, +text: String, +ending: UI.Ending, +previous: Document, +state: State) -> Decision:
  match same:
    case True{}: Decision{with_documents(save(documents(state), reactivate(previous)), forget_retained(document_key(previous), state)), Nil{}}
    case False{}:
      Document{+old_source, +old_text, +old_epoch, +revision, +old_ending, +observed_prefix, +fences, +active} = previous
      State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
      +continuous: Bool = prefix(old_text, text) && (same_ending(old_ending, UI.Open{}) || SafeText.string_equal(old_text, text))
      publish_updated(continuous, source, text, ending, previous, next_epoch,
        State{namespace, sequence, fresh, allowed, display_ready, documents, core, 1n+next_epoch, retention})

def put_found(+found: Maybe<&2, Document>, +source: Code.Source, +text: String, +ending: UI.Ending, +state: State) -> Decision:
  match found:
    case None{}:
      State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
      publish_document(Document{source, text, next_epoch, 0n, ending, 0n, Nil{}, True{}},
        State{namespace, sequence, fresh, allowed, display_ready, documents, core, 1n+next_epoch, retention})
    case Some{+previous}:
      Document{+old_source, +old_text, +old_epoch, +revision, +old_ending, +observed_prefix, +fences, +active} = previous
      put_existing(SafeText.string_equal(old_text, text) && same_ending(old_ending, ending), source, text, ending, previous, state)

def keep_document(+keep: Bool, +document: Document, +rest: +List<Document>) -> +List<Document>:
  match keep:
    case True{}: document <> rest
    case False{}: rest

def without(+values: +List<Document>, +key: String) -> +List<Document>:
  match values:
    case Nil{}: Nil{}
    case Con{+document, +rest}: keep_document(Bool.not(String.eq(document_key(document), key)), document, without(rest, key))

def discard_found(+found: Maybe<&2, Document>, +state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{+document}:
      +decision_3: Decision = remove_old(document, state)
      +next: State = result_state(decision_3)
      +effects: +List<Effect> = result_effects(decision_3)
      Decision{with_documents(without(documents(next), document_key(document)), forget_retained(document_key(document), next)), List.append(&2, Effect, [ForgetMarkdown{document_key(document)}], effects)}

def put(+eligible: Bool, +source: Code.Source, +text: String, +ending: UI.Ending, +state: State) -> Decision:
  match eligible:
    case False{}: discard_found(find(documents(state), Code.source_key(source)), state)
    case True{}: put_found(find(documents(state), Code.source_key(source)), source, text, ending, state)

def generated(+namespace: String, +viewer: Nat, +origin: D.OutputOrigin, +complete: Bool) -> Code.Source:
  Code.Generated{namespace, viewer, origin, complete}

def message_source(+viewer: Nat, +occurrence: Nat, +message: D.Message, +namespace: String) -> Code.Source:
  match message:
    case D.AssistantMessage{+origin, +text}: generated(namespace, viewer, origin, True{})
    case D.ModelContext{+origin, +value}: generated(namespace, viewer, origin, True{})
    case _: Code.Message{viewer, occurrence}

def message(+message: D.Message, +viewer: Nat, +state: State) -> Decision:
  match message:
    case D.AssistantMessage{+origin, +text}:
      +source: Code.Source = generated(namespace(state), viewer, origin, True{})
      put(interactive_source(source), source, text, UI.Complete{}, state)
    case D.ModelContext{+origin, +value}:
      +source: Code.Source = generated(namespace(state), viewer, origin, True{})
      put(Conversation.provider_assistant(value) && interactive_source(source), source, Conversation.provider_text(value), UI.Complete{}, state)
    case _: Decision{state, Nil{}}

def observe_messages(+values: +List<D.Message>, +viewer: Nat, +state: State) -> Decision:
  match values:
    case Nil{}: Decision{state, Nil{}}
    case Con{+value, +rest}:
      +decision_4: Decision = message(value, viewer, state)
      +next: State = result_state(decision_4)
      +effects: +List<Effect> = result_effects(decision_4)
      append_result(effects, observe_messages(rest, viewer, next))

def preview_part(+found: Maybe<&2, D.OutputOrigin>, +text: String, +viewer: Nat, +state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{+origin}:
      +source: Code.Source = generated(namespace(state), viewer, origin, False{})
      put(interactive_source(source), source, text, UI.Open{}, state)

def preview_parts(+parts: +List<Live.Part>, +output: Live.Output, +viewer: Nat, +world: M.World(), +state: State) -> Decision:
  match parts:
    case Nil{}: Decision{state, Nil{}}
    case Con{Live.Part{+index, +text}, +rest}:
      +decision_5: Decision = preview_part(Live.origin(output, index, world), text, viewer, state)
      +next: State = result_state(decision_5)
      +effects: +List<Effect> = result_effects(decision_5)
      append_result(effects, preview_parts(rest, output, viewer, world, next))

def preview_outputs(+outputs: +List<Live.Output>, +viewer: Nat, +world: M.World(), +state: State) -> Decision:
  match outputs:
    case Nil{}: Decision{state, Nil{}}
    case Con{+output, +rest}:
      Live.Output{+task, +operation, +parts} = output
      +decision_6: Decision = preview_parts(parts, output, viewer, world, state)
      +next: State = result_state(decision_6)
      +effects: +List<Effect> = result_effects(decision_6)
      append_result(effects, preview_outputs(rest, viewer, world, next))

def deactivate_all(+documents: +List<Document>) -> +List<Document>:
  match documents:
    case Nil{}: Nil{}
    case Con{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}, +rest}:
      Document{source, text, epoch, revision, ending, observed_prefix, fences, False{}} <> deactivate_all(rest)

def interrupted_document(+document: Document) -> Document:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
  Document{source, text, epoch, 1n+revision, UI.Interrupted{}, observed_prefix, fences, True{}}

def inactive_document(+document: Document) -> Document:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
  Document{source, text, epoch, revision, ending, observed_prefix, fences, False{}}

def environment_fresh(+state: State) -> Bool:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  fresh && allowed

def source_pending(+source: Code.Source, +world: M.World()) -> Bool:
  match source:
    case Code.Generated{+namespace, +viewer, D.OutputOrigin{+producer, +operation, +part, +mode}, +complete}:
      Live.has_origin(Live.origin(Live.Output{producer, operation, Nil{}}, part, world))
    case _: False{}

def dormant_result(+result: Decision, +key: String) -> Decision:
  Decision{+state, +effects} = result
  Decision{dormant(key, state), effects}

def dormant_open(+terminal: Bool, +document: Document, +state: State) -> Decision:
  match terminal:
    case True{}: dormant_result(publish_document(interrupted_document(document), state), document_key(document))
    case False{}: Decision{dormant(document_key(document), with_documents(save(documents(state), reactivate(document)), state)), Nil{}}

def dormant_interrupted(+document: Document, +state: State) -> Decision:
  +archived: Bool = entry_archived(retained_entries(retention(state)), document_key(document))
  +current: Document = Bool.pick(Document, archived, inactive_document(document), reactivate(document))
  Decision{dormant(document_key(document), with_documents(save(documents(state), current), state)), Nil{}}

def interrupted_if(+document: Document, +world: M.World(), +state: State) -> Decision:
  match document:
    case Document{+source, +text, +epoch, +revision, UI.Open{}, +observed_prefix, +fences, False{}}:
      dormant_open(environment_fresh(state) && Bool.not(source_pending(source, world)), document, state)
    case Document{+source, +text, +epoch, +revision, UI.Interrupted{}, +observed_prefix, +fences, False{}}: dormant_interrupted(document, state)
    case _: Decision{state, Nil{}}

def retain_interrupted(+values: +List<Document>, +world: M.World(), +state: State) -> Decision:
  match values:
    case Nil{}: Decision{state, Nil{}}
    case Con{+document, +rest}:
      +result: Decision = interrupted_if(document, world, state)
      append_result(result_effects(result), retain_interrupted(rest, world, result_state(result)))

def keep_request(+keep: Bool, +request: UI.SourceRequest, +rest: +List<UI.SourceRequest>) -> +List<UI.SourceRequest>:
  match keep:
    case True{}: request <> rest
    case False{}: rest


def select_requests(+values: +List<UI.SourceRequest>, +owner_key: String) -> +List<UI.SourceRequest>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.SourceRequest{+request_owner, +name, +graph_id}, +rest}:
      UI.Owner{+key, +epoch} = request_owner
      keep_request(String.eq(key, owner_key), UI.SourceRequest{request_owner, name, graph_id}, select_requests(rest, owner_key))

def forbidden_sources(+requests: +List<UI.SourceRequest>, +sequence: Nat) -> +List<J.Field>:
  match requests:
    case Nil{}: Nil{}
    case Con{UI.SourceRequest{+owner, +name, +graph_id}, +rest}:
      J.Field{name, Sources.source_handle("forbidden", False{}, sequence, J.Null{})} <> forbidden_sources(rest, sequence)

def project_sources(+allowed: Bool, +requests: +List<UI.SourceRequest>, +world: M.World(), +sequence: Nat, +fresh: Bool) -> +List<J.Field>:
  match allowed:
    case True{}: Sources.projection(requests, world, sequence, fresh)
    case False{}: forbidden_sources(requests, sequence)

def refresh_scoped_fence(+eligible: Bool, +ordinal: Nat, +document: Document, +world: M.World(), +state: State) -> Decision:
  match eligible:
    case False{}: Decision{state, Nil{}}
    case True{}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
      +block_owner: UI.Owner = owner(source, ordinal, epoch)
      +key: String = owner_key(block_owner)
      +requests: +List<UI.SourceRequest> = select_requests(Core.source_requests(core), key)
      +decision_8: Decision = input(UI.SourcesChanged{block_owner, project_sources(allowed, requests, world, sequence, fresh)}, state)
      +next: State = result_state(decision_8)
      +effects: +List<Effect> = result_effects(decision_8)
      append_result(effects, input(UI.ExternalChanged{block_owner, external(document, next)}, next))

def refresh_fence(+eligible: Bool, +ordinal: Nat, +document: Document, +world: M.World(), +state: State) -> Decision:
  refresh_scoped_fence(eligible && source_scope_document(document, namespace(state)), ordinal, document, world, state)

def refresh_fences(+fences: +List<Fence>, +document: Document, +world: M.World(), +state: State) -> Decision:
  match fences:
    case Nil{}: Decision{state, Nil{}}
    case Con{Fence{+ordinal, +eligible, +code, +closed, +source_visible}, +rest}:
      +decision_9: Decision = refresh_fence(eligible, ordinal, document, world, state)
      +next: State = result_state(decision_9)
      +effects: +List<Effect> = result_effects(decision_9)
      append_result(effects, refresh_fences(rest, document, world, next))

def refresh_documents(+values: +List<Document>, +world: M.World(), +state: State) -> Decision:
  match values:
    case Nil{}: Decision{state, Nil{}}
    case Con{+document, +rest}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      +decision_10: Decision = refresh_fences(fences, document, world, state)
      +next: State = result_state(decision_10)
      +effects: +List<Effect> = result_effects(decision_10)
      append_result(effects, refresh_documents(rest, world, next))

def refresh(+world: M.World(), +state: State) -> Decision:
  refresh_documents(documents(state), world, state)


def forget_effects(+documents: +List<Document>) -> +List<Effect>:
  match documents:
    case Nil{}: Nil{}
    case Con{+document, +rest}: ForgetMarkdown{document_key(document)} <> forget_effects(rest)

def task_present(+found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{+task}: True{}


def prune_one(+present: Bool, +document: Document, +state: State) -> Decision:
  match present:
    case True{}: Decision{state, Nil{}}
    case False{}:
      +decision_14: Decision = remove_old(document, state)
      +next: State = result_state(decision_14)
      +effects: +List<Effect> = result_effects(decision_14)
      Decision{with_documents(without(documents(next), document_key(document)), forget_retained(document_key(document), next)), List.append(&2, Effect, [ForgetMarkdown{document_key(document)}], effects)}

def source_present(+viewer: Maybe<&2, Nat>, +world: M.World()) -> Bool:
  match viewer:
    case None{}: True{}
    case Some{task}: task_present(Tasks.find(Commands.entries(world), task))

def prune(+values: +List<Document>, +world: M.World(), +state: State) -> Decision:
  match values:
    case Nil{}: Decision{state, Nil{}}
    case Con{+document, +rest}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      +decision_15: Decision = prune_one(source_present(source_viewer(source), world), document, state)
      +next: State = result_state(decision_15)
      +effects: +List<Effect> = result_effects(decision_15)
      append_result(effects, prune(rest, world, next))

def source_operation(+source: Code.Source) -> Nat:
  match source:
    case Code.SharedDocument{+namespace, +owner}: 0n
    case Code.Generated{+namespace, +viewer, D.OutputOrigin{+producer, +operation, +part, +mode}, +complete}: operation
    case Code.StreamingPart{+task, +operation, +part}: operation
    case Code.Message{+task, +message}: message

def source_part(+source: Code.Source) -> Nat:
  match source:
    case Code.SharedDocument{+namespace, +owner}: 0n
    case Code.Generated{+namespace, +viewer, D.OutputOrigin{+producer, +operation, +part, +mode}, +complete}: part
    case Code.StreamingPart{+task, +operation, +part}: part
    case Code.Message{+task, +message}: 0n

def document_newer(+left: Document, +right: Document) -> Bool:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = left
  Document{+other, +other_text, +other_epoch, +other_revision, +other_ending, +other_prefix, +other_fences, +other_active} = right
  Nat.is_lt(source_operation(other), source_operation(source)) ||
    (Nat.is_eq(source_operation(other), source_operation(source)) && Nat.is_lt(source_part(other), source_part(source)))

def insert_document_at_front(+front: Bool, +value: Document, +old: Document, +rest: +List<Document>, +fallback: +List<Document>) -> +List<Document>:
  match front:
    case True{}: value <> old <> rest
    case False{}: old <> fallback

def insert_newest(+values: +List<Document>, +value: Document) -> +List<Document>:
  match values:
    case Nil{}: [value]
    case Con{+old, +rest}: insert_document_at_front(document_newer(value, old), value, old, rest, insert_newest(rest, value))

def newest(+values: +List<Document>) -> +List<Document>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, +rest}: insert_newest(newest(rest), value)

def retain_document_if(+keep: Bool, +document: Document, +rest: +List<Document>) -> +List<Document>:
  match keep:
    case True{}: document <> rest
    case False{}: rest

def interrupted_documents(+values: +List<Document>, +entries: +List<RetainedEntry>) -> +List<Document>:
  match values:
    case Nil{}: Nil{}
    case Con{+document, +rest}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      retain_document_if(same_ending(ending, UI.Interrupted{}) && entry_dormant(entries, document_key(document)), document, interrupted_documents(rest, entries))

def count_for(+counts: +List<Discarded>, +task: Nat) -> Nat:
  match counts:
    case Nil{}: 0n
    case Con{Discarded{+current, +count}, +rest}: Bool.pick(Nat, Nat.is_eq(current, task), count, count_for(rest, task))

def keep_count(+keep: Bool, +count: Discarded, +rest: +List<Discarded>) -> +List<Discarded>:
  match keep:
    case True{}: count <> rest
    case False{}: rest

def without_count(+counts: +List<Discarded>, +task: Nat) -> +List<Discarded>:
  match counts:
    case Nil{}: Nil{}
    case Con{Discarded{+current, +count}, +rest}: keep_count(Bool.not(Nat.is_eq(current, task)), Discarded{current, count}, without_count(rest, task))

def increment_count(+counts: +List<Discarded>, +task: Nat) -> +List<Discarded>:
  Discarded{task, 1n+count_for(counts, task)} <> without_count(counts, task)

def discarded_value(+value: Retention, +task: Nat) -> Nat:
  Retention{+entries, +discarded} = value
  count_for(discarded, task)

def discarded(+task: Nat, +state: State) -> Nat:
  discarded_value(retention(state), task)

def increment_discarded_value(+value: Retention, +task: Nat, +state: State) -> State:
  Retention{+entries, +discarded} = value
  with_retention(Retention{entries, increment_count(discarded, task)}, state)

def increment_discarded(+task: Nat, +state: State) -> State:
  increment_discarded_value(retention(state), task, state)

def clear_discarded_value(+value: Retention, +task: Nat, +state: State) -> State:
  Retention{+entries, +discarded} = value
  with_retention(Retention{entries, without_count(discarded, task)}, state)

def clear_discarded(+task: Nat, +state: State) -> State:
  clear_discarded_value(retention(state), task, state)


def archive_result(+result: Decision, +document: Document) -> Decision:
  Decision{+state, +effects} = result
  +key: String = document_key(document)
  Decision{save_entry(RetainedEntry{key, True{}, False{}, True{}}, with_documents(save(documents(state), inactive_document(document)), state)),
    List.append(&2, Effect, effects, [ForgetMarkdown{key}])}

def archive(+document: Document, +state: State) -> Decision:
  archive_result(remove_old(document, state), document)

def live_retention_allowed(+allowed: Bool, +document: Document, +state: State) -> Decision:
  match allowed:
    case True{}: Decision{state, Nil{}}
    case False{}: archive(document, state)

def retained_task_limit() -> Nat:
  16n

def retained_session_limit() -> Nat:
  64n

def retained_archive_bytes() -> Nat:
  4194304n

def optional_count_for(+counts: +List<Discarded>, +viewer: Maybe<&2, Nat>) -> Nat:
  match viewer:
    case None{}: 0n
    case Some{task}: count_for(counts, task)

def increment_optional_count(+counts: +List<Discarded>, +viewer: Maybe<&2, Nat>) -> +List<Discarded>:
  match viewer:
    case None{}: counts
    case Some{task}: increment_count(counts, task)

def bound_live(+values: +List<Document>, +counts: +List<Discarded>, +total: Nat, +state: State) -> Decision:
  match values:
    case Nil{}: Decision{state, Nil{}}
    case Con{+document, +rest}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      +already_archived: Bool = entry_archived(retained_entries(retention(state)), document_key(document))
      +admitted: Bool = Bool.not(already_archived) && Nat.is_lt(total, retained_session_limit()) && Nat.is_lt(optional_count_for(counts, source_viewer(source)), retained_task_limit())
      +result: Decision = live_retention_allowed(already_archived || admitted, document, state)
      append_result(result_effects(result), bound_live(rest,
        Bool.pick(+List<Discarded>, admitted, increment_optional_count(counts, source_viewer(source)), counts),
        Bool.pick(Nat, admitted, 1n+total, total), result_state(result)))

def archive_discarded(+result: Decision, +task: Nat) -> Decision:
  Decision{+state, +effects} = result
  Decision{increment_discarded(task, state), effects}

def archive_optional_discarded(+result: Decision, +viewer: Maybe<&2, Nat>) -> Decision:
  match viewer:
    case None{}: result
    case Some{task}: archive_discarded(result, task)

def bound_archive_one(+admitted: Bool, +document: Document, +state: State) -> Decision:
  match admitted:
    case True{}: Decision{state, Nil{}}
    case False{}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      archive_optional_discarded(discard_found(Some{document}, state), source_viewer(source))

def archive_documents(+values: +List<Document>, +entries: +List<RetainedEntry>) -> +List<Document>:
  match values:
    case Nil{}: Nil{}
    case Con{+document, +rest}: retain_document_if(entry_archived(entries, document_key(document)), document, archive_documents(rest, entries))

def bound_archives(+values: +List<Document>, +bytes: Nat, +state: State) -> Decision:
  match values:
    case Nil{}: Decision{state, Nil{}}
    case Con{+document, +rest}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      +size: Nat = J.utf8_length(text)
      +admitted: Bool = Nat.is_le((bytes + size : Nat), retained_archive_bytes())
      +result: Decision = bound_archive_one(admitted, document, state)
      append_result(result_effects(result), bound_archives(rest, Bool.pick(Nat, admitted, (bytes + size : Nat), bytes), result_state(result)))

def bound_archives_current(+state: State) -> Decision:
  bound_archives(newest(archive_documents(documents(state), retained_entries(retention(state)))), 0n, state)

def bound_retention(+state: State) -> Decision:
  +result: Decision = bound_live(newest(interrupted_documents(documents(state), retained_entries(retention(state)))), Nil{}, 0n, state)
  append_result(result_effects(result), bound_archives_current(result_state(result)))

def dismiss_checked(+allowed: Bool, +key: String, +state: State) -> Decision:
  match allowed:
    case False{}: Decision{state, Nil{}}
    case True{}: discard_found(find(documents(state), key), state)

def dismiss(+key: String, +state: State) -> Decision:
  dismiss_checked(entry_dormant(retained_entries(retention(state)), key), key, state)

def toggle_archive_checked(+allowed: Bool, +key: String, +state: State) -> State:
  match allowed:
    case False{}: state
    case True{}: save_entry(RetainedEntry{key, True{}, Bool.not(entry_visible(retained_entries(retention(state)), key)), True{}}, state)

def toggle_archive(+key: String, +state: State) -> State:
  toggle_archive_checked(entry_archived(retained_entries(retention(state)), key), key, state)

def present_nat(+values: +List<Nat>, +value: Nat) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{+current, +rest}: Nat.is_eq(current, value) || present_nat(rest, value)

def add_viewer(+values: +List<Nat>, +value: Nat) -> +List<Nat>:
  Bool.pick(+List<Nat>, present_nat(values, value), values, value <> values)

def add_optional_viewer(+viewers: +List<Nat>, +viewer: Maybe<&2, Nat>) -> +List<Nat>:
  match viewer:
    case None{}: viewers
    case Some{task}: add_viewer(viewers, task)

def document_viewers(+values: +List<Document>, +viewers: +List<Nat>) -> +List<Nat>:
  match values:
    case Nil{}: viewers
    case Con{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}, +rest}: document_viewers(rest, add_optional_viewer(viewers, source_viewer(source)))

def preview_viewers(+values: +List<Live.Output>, +viewers: +List<Nat>) -> +List<Nat>:
  match values:
    case Nil{}: viewers
    case Con{Live.Output{+task, +operation, +parts}, +rest}: preview_viewers(rest, add_viewer(viewers, task))

def current_viewer(+viewer: Maybe<&2, Nat>, +values: +List<Nat>) -> +List<Nat>:
  match viewer:
    case None{}: values
    case Some{+task}: add_viewer(values, task)

def reconcile_found(+found: Maybe<&2, D.Task>, +viewer: Nat, +previews: +List<Live.Output>, +world: M.World(), +state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{+task}:
      +history: Decision = observe_messages(D.history_messages(D.task_history(task), Nil{}), viewer, state)
      append_result(result_effects(history), preview_outputs(Live.for_task(previews, viewer), viewer, world, result_state(history)))

def reconcile_viewers(+viewers: +List<Nat>, +previews: +List<Live.Output>, +world: M.World(), +state: State) -> Decision:
  match viewers:
    case Nil{}: Decision{state, Nil{}}
    case Con{+viewer, +rest}:
      +result: Decision = reconcile_found(Tasks.find(Commands.entries(world), viewer), viewer, previews, world, state)
      append_result(result_effects(result), reconcile_viewers(rest, previews, world, result_state(result)))

def viewer_matches(+viewer: Maybe<&2, Nat>, +task: Nat) -> Bool:
  match viewer:
    case None{}: False{}
    case Some{+current}: Nat.is_eq(current, task)

def same_viewer(+left: Maybe<&2, Nat>, +right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case Some{a} Some{b}: Nat.is_eq(a, b)
    case _ _: False{}

def exposed_documents(+values: +List<Document>, +viewer: Maybe<&2, Nat>, +entries: +List<RetainedEntry>) -> +List<Document>:
  match values:
    case Nil{}: Nil{}
    case Con{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}, +rest}:
      Document{source, text, epoch, revision, ending, observed_prefix, fences, same_viewer(viewer, source_viewer(source)) && Bool.not(entry_archived(entries, Code.source_key(source)))} <> exposed_documents(rest, viewer, entries)

def reconcile_exposed(+viewer: Maybe<&2, Nat>, +world: M.World(), +state: State) -> Decision:
  refresh(world, with_documents(exposed_documents(documents(state), viewer, retained_entries(retention(state))), state))

def reconcile_bounded(+viewer: Maybe<&2, Nat>, +world: M.World(), +state: State) -> Decision:
  +bounded: Decision = bound_retention(state)
  append_result(result_effects(bounded), reconcile_exposed(viewer, world, result_state(bounded)))

def reconcile_dormant(+viewer: Maybe<&2, Nat>, +world: M.World(), +state: State) -> Decision:
  +retained: Decision = retain_interrupted(documents(state), world, state)
  append_result(result_effects(retained), reconcile_bounded(viewer, world, result_state(retained)))

def reconcile_available(+viewer: Maybe<&2, Nat>, +previews: +List<Live.Output>, +world: M.World(), +state: State) -> Decision:
  +viewers: +List<Nat> = current_viewer(viewer, preview_viewers(previews, document_viewers(documents(state), Nil{})))
  +known: Decision = reconcile_viewers(viewers, previews, world, with_documents(deactivate_all(documents(state)), state))
  append_result(result_effects(known), reconcile_dormant(viewer, world, result_state(known)))

def reconcile(+viewer: Maybe<&2, Nat>, +previews: +List<Live.Output>, +world: M.World(), +state: State) -> Decision:
  +retained: Decision = prune(documents(state), world, state)
  append_result(result_effects(retained), reconcile_available(viewer, previews, world, result_state(retained)))

def viewer_exposed(+viewers: +List<Nat>, +viewer: Maybe<&2, Nat>) -> Bool:
  match viewer:
    case None{}: False{}
    case Some{task}: present_nat(viewers, task)

def exposed_visible_documents(values: +List<Document>, +viewers: +List<Nat>, +entries: +List<RetainedEntry>) -> +List<Document>:
  match values:
    case Nil{}: Nil{}
    case Con{Document{+source, text, epoch, revision, ending, observed_prefix, fences, active}, rest}:
      Document{source, text, epoch, revision, ending, observed_prefix, fences, viewer_exposed(viewers, source_viewer(source)) && Bool.not(entry_archived(entries, Code.source_key(source)))} <> exposed_visible_documents(rest, viewers, entries)

def expose_visible(+viewers: +List<Nat>, +world: M.World(), +state: State) -> Decision:
  refresh(world, with_documents(exposed_visible_documents(documents(state), viewers, retained_entries(retention(state))), state))

def reconcile_visible_bounded(+viewers: +List<Nat>, +world: M.World(), +state: State) -> Decision:
  +bounded: Decision = bound_retention(state)
  append_result(result_effects(bounded), expose_visible(viewers, world, result_state(bounded)))

def reconcile_visible_dormant(+viewers: +List<Nat>, +world: M.World(), +state: State) -> Decision:
  +retained: Decision = retain_interrupted(documents(state), world, state)
  append_result(result_effects(retained), reconcile_visible_bounded(viewers, world, result_state(retained)))

def reconcile_visible_available(+viewers: +List<Nat>, +previews: +List<Live.Output>, +world: M.World(), +state: State) -> Decision:
  +all: +List<Nat> = preview_viewers(previews, document_viewers(documents(state), viewers))
  +known: Decision = reconcile_viewers(all, previews, world, with_documents(deactivate_all(documents(state)), state))
  append_result(result_effects(known), reconcile_visible_dormant(viewers, world, result_state(known)))

def reconcile_visible(+viewers: +List<Nat>, +previews: +List<Live.Output>, +world: M.World(), +state: State) -> Decision:
  +retained: Decision = prune(documents(state), world, state)
  append_result(result_effects(retained), reconcile_visible_available(viewers, previews, world, result_state(retained)))


def environment_same(+same: Bool, +namespace: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: State) -> Decision:
  match same state:
    case True{} State{+previous, +old_sequence, +old_fresh, +old_allowed, +display_ready, +documents, +core, +next_epoch, +retention}: Decision{State{namespace, sequence, fresh, allowed, display_ready, documents, core, next_epoch, retention}, Nil{}}
    case False{} State{+previous, +old_sequence, +old_fresh, +old_allowed, +display_ready, +documents, +core, +next_epoch, +retention}: Decision{State{namespace, sequence, fresh, allowed, True{}, Nil{}, Core.initial(), next_epoch, Retention{Nil{}, Nil{}}}, forget_effects(documents)}

def environment_current(+current: Bool, +store: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: State) -> Decision:
  match current:
    case False{}: Decision{state, Nil{}}
    case True{}: environment_same(String.eq(store, namespace(state)), store, sequence, fresh, allowed, state)

def environment(+store: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: State) -> Decision:
  State{+previous, +old_sequence, +old_fresh, +old_allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  environment_current(Bool.not(String.eq(store, previous)) || Nat.is_le(old_sequence, sequence), store, sequence, fresh, allowed, state)

def display(+ready: Bool, +state: State) -> State:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  State{namespace, sequence, fresh, allowed, ready, documents, core, next_epoch, retention}

def observation_valid(+observation: FenceObservation, +document: Document) -> Bool:
  FenceObservation{+key, +epoch, +revision, +ordinal, +kind, +info, +info_complete, +code, +closed, +input_prefix} = observation
  Document{+source, +text, +expected_epoch, +current_revision, +ending, +observed_prefix, +fences, +active} = document
  Nat.is_eq(epoch, expected_epoch) && Nat.is_le(revision, current_revision) &&
    Nat.is_le(observed_prefix, String.length(input_prefix)) && prefix(input_prefix, text)

def replace_fence(+same: Bool, +old: Fence, +rest: +List<Fence>, +value: Fence, +fallback: +List<Fence>) -> +List<Fence>:
  match same:
    case True{}:
      Fence{+old_ordinal, +old_eligible, +old_code, +old_closed, +retained_visibility} = old
      Fence{+ordinal, +eligible, +code, +closed, +visibility} = value
      Fence{ordinal, eligible, code, closed, retained_visibility} <> rest
    case False{}: old <> fallback

def save_fence(+fences: +List<Fence>, +value: Fence) -> +List<Fence>:
  match fences:
    case Nil{}: [value]
    case Con{Fence{+ordinal, +eligible, +code, +closed, +source_visible}, +rest}:
      Fence{+target, +e, +c, +d, +v} = value
      replace_fence(Nat.is_eq(ordinal, target), Fence{ordinal, eligible, code, closed, source_visible}, rest, value, save_fence(rest, value))

def fence_ending(+caught_up: Bool, +ending: UI.Ending) -> UI.Ending:
  match caught_up:
    case True{}: ending
    case False{}: UI.Open{}

def accepted_input(+eligible: Bool, +event: UI.Input, +state: State) -> Decision:
  match eligible:
    case False{}: Decision{state, Nil{}}
    case True{}: input(event, state)

def accepted_fence(+eligible: Bool, +observation: FenceObservation, +document: Document, +state: State) -> Decision:
  FenceObservation{+key, +epoch, +revision, +ordinal, +kind, +info, +info_complete, +code, +closed, +input_prefix} = observation
  Document{+source, +text, +current_epoch, +current_revision, +ending, +observed_prefix, +fences, +active} = document
  +next_document: Document = Document{source, text, current_epoch, current_revision, ending, String.length(input_prefix), save_fence(fences, Fence{ordinal, eligible, code, closed, False{}}), active}
  +next: State = with_documents(save(documents(state), next_document), state)
  accepted_input(eligible, UI.SourceChanged{owner(source, ordinal, current_epoch), code, closed,
    fence_ending(SafeText.string_equal(input_prefix, text), ending), external(next_document, next)}, next)

def fence_monotonic_found(+found: Bool, +eligible: Bool, +code: String, +closed: Bool, +previous: Fence) -> Bool:
  match found previous:
    case False{} _: True{}
    case True{} Fence{+ordinal, +previous_eligible, +previous_code, +previous_closed, +source_visible}:
      prefix(previous_code, code) && (Bool.not(previous_closed) || (closed && SafeText.string_equal(previous_code, code))) && (Bool.not(previous_eligible) || eligible)

def fence_monotonic(+fences: +List<Fence>, +ordinal: Nat, +eligible: Bool, +code: String, +closed: Bool) -> Bool:
  match fences:
    case Nil{}: True{}
    case Con{+previous, +rest}:
      Fence{+current, +e, +c, +d, +v} = previous
      fence_monotonic_found(Nat.is_eq(current, ordinal), eligible, code, closed, previous) && fence_monotonic(rest, ordinal, eligible, code, closed)

def fence_eligible_count(+fences: +List<Fence>) -> Nat:
  match fences:
    case Nil{}: 0n
    case Con{Fence{+ordinal, True{}, +code, +closed, +source_visible}, +rest}: 1n+fence_eligible_count(rest)
    case Con{+fence, +rest}: fence_eligible_count(rest)

def ordinal_eligible(+fences: +List<Fence>, +ordinal: Nat) -> Bool:
  match fences:
    case Nil{}: False{}
    case Con{Fence{+current, +eligible, +code, +closed, +source_visible}, +rest}: (Nat.is_eq(current, ordinal) && eligible) || ordinal_eligible(rest, ordinal)

def observe_monotonic(+monotonic: Bool, +eligible: Bool, +observation: FenceObservation, +document: Document, +state: State) -> Decision:
  match monotonic:
    case False{}: Decision{state, Nil{}}
    case True{}: accepted_fence(eligible, observation, document, state)

def observe_checked(+valid: Bool, +observation: FenceObservation, +document: Document, +state: State) -> Decision:
  match valid:
    case False{}: Decision{state, Nil{}}
    case True{}:
      FenceObservation{+key, +epoch, +revision, +ordinal, +kind, +info, +info_complete, +code, +closed, +input_prefix} = observation
      Document{+source, +text, +current_epoch, +current_revision, +ending, +observed_prefix, +fences, +active} = document
      +eligible: Bool = Core.eligible_fence(interactive_source(source), kind, info, info_complete) && (ordinal_eligible(fences, ordinal) || Nat.is_lt(fence_eligible_count(fences), 16n))
      observe_monotonic(fence_monotonic(fences, ordinal, eligible, code, closed), eligible, observation, document, state)


def observe_found(+found: Maybe<&2, Document>, +observation: FenceObservation, +state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{+document}: observe_checked(source_scope_document(document, namespace(state)) && observation_valid(observation, document) && Bool.not(entry_archived(retained_entries(retention(state)), document_key(document))), observation, document, state)

def observe(+observation: FenceObservation, +state: State) -> Decision:
  FenceObservation{+key, +epoch, +revision, +ordinal, +kind, +info, +info_complete, +code, +closed, +input_prefix} = observation
  observe_found(find(documents(state), key), observation, state)

def fence_scenes(+fences: +List<Fence>, +source: Code.Source, +epoch: Nat, +core: UI.State) -> +List<BlockScene>:
  match fences:
    case Nil{}: Nil{}
    case Con{Fence{+ordinal, +eligible, +code, +closed, +source_visible}, +rest}:
      match eligible:
        case True{}: BlockScene{Code.Identity{source, ordinal}, Core.observe(owner(source, ordinal, epoch), core)} <> fence_scenes(rest, source, epoch, core)
        case False{}: fence_scenes(rest, source, epoch, core)

def found_scenes(+found: Maybe<&2, Document>, +core: UI.State) -> +List<BlockScene>:
  match found:
    case None{}: Nil{}
    case Some{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}}: fence_scenes(fences, source, epoch, core)

def scenes_allowed(+allowed: Bool, +found: Maybe<&2, Document>, +core: UI.State) -> +List<BlockScene>:
  match allowed:
    case False{}: Nil{}
    case True{}: found_scenes(found, core)

def scenes(+source: Code.Source, +state: State) -> +List<BlockScene>:
  scenes_allowed(Bool.not(entry_archived(retained_entries(retention(state)), Code.source_key(source))), find(documents(state), Code.source_key(source)), core(state))

def ended_source(+source: Code.Source) -> Code.Source:
  match source:
    case Code.Generated{+namespace, +viewer, +origin, +complete}: Code.Generated{namespace, viewer, origin, True{}}
    case other: other

def source_only(source: Code.Source) -> Code.Source:
  ended_source(source)

def retained_item(+archived: Bool, +visible: Bool, +document: Document) -> RetainedPart:
  Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
  RetainedPart{Bool.pick(Code.Source, archived, source_only(source), Bool.pick(Code.Source, same_ending(ending, UI.Interrupted{}), ended_source(source), source)), text, archived,
    Bool.not(archived) || visible, Bool.pick(String, archived, "未完成显示已收起", Bool.pick(String, same_ending(ending, UI.Interrupted{}), "生成未完成（仅在本次会话保留）", "输出同步中（仅在本次会话保留）"))}

def retained_part(+keep: Bool, +document: Document, +entries: +List<RetainedEntry>, +rest: +List<RetainedPart>) -> +List<RetainedPart>:
  match keep:
    case True{}: retained_item(entry_archived(entries, document_key(document)), entry_visible(entries, document_key(document)), document) <> rest
    case False{}: rest

def retained_values(+values: +List<Document>, +viewer: Nat, +entries: +List<RetainedEntry>) -> +List<RetainedPart>:
  match values:
    case Nil{}: Nil{}
    case Con{+document, +rest}:
      Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active} = document
      retained_part(viewer_matches(source_viewer(source), viewer) && entry_dormant(entries, document_key(document)), document, entries, retained_values(rest, viewer, entries))

def dormant_documents(+values: +List<Document>, +entries: +List<RetainedEntry>) -> +List<Document>:
  match values:
    case Nil{}: Nil{}
    case Con{+document, +rest}: retain_document_if(entry_dormant(entries, document_key(document)), document, dormant_documents(rest, entries))

def retained(+viewer: Nat, +state: State) -> +List<RetainedPart>:
  retained_values(newest(dormant_documents(documents(state), retained_entries(retention(state)))), viewer, retained_entries(retention(state)))


def fence_visibility(+fences: +List<Fence>, +ordinal: Nat) -> Bool:
  match fences:
    case Nil{}: False{}
    case Con{Fence{+current, +eligible, +code, +closed, +visible}, +rest}:
      (Nat.is_eq(current, ordinal) && visible) || fence_visibility(rest, ordinal)

def found_visibility(+found: Maybe<&2, Document>, +ordinal: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}}: fence_visibility(fences, ordinal)

def source_visible(+identity: Code.Identity, +state: State) -> Bool:
  Code.Identity{+source, +ordinal} = identity
  found_visibility(find(documents(state), Code.source_key(source)), ordinal)

def toggle_fence(+fences: +List<Fence>, +ordinal: Nat) -> +List<Fence>:
  match fences:
    case Nil{}: Nil{}
    case Con{Fence{+current, +eligible, +code, +closed, +visible}, +rest}:
      Fence{current, eligible, code, closed, Bool.xor(Nat.is_eq(current, ordinal), visible)} <> toggle_fence(rest, ordinal)

def toggle_found(+found: Maybe<&2, Document>, +ordinal: Nat, +state: State) -> State:
  match found:
    case None{}: state
    case Some{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}}:
      with_documents(save(documents(state), Document{source, text, epoch, revision, ending, observed_prefix, toggle_fence(fences, ordinal), active}), state)

def toggle_source(+identity: Code.Identity, +state: State) -> State:
  Code.Identity{+source, +ordinal} = identity
  toggle_found(find(documents(state), Code.source_key(source)), ordinal, state)


def task_if_owned(+owned: Bool, +task: Maybe<&2, Nat>, +fallback: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match owned:
    case True{}: task
    case False{}: fallback

def owning_task(+store: String, +values: +List<Document>, +expected: UI.Owner) -> Maybe<&2, Nat>:
  match values:
    case Nil{}: None{}
    case Con{Document{+source, +text, +epoch, +revision, +ending, +observed_prefix, +fences, +active}, +rest}:
      task_if_owned(source_scope(source, store) && active && external_source(source) && owner_matches(fences, source, epoch, expected), source_viewer(source), owning_task(store, rest, expected))

def current_owning_task(+expected: UI.Owner, +state: State) -> Maybe<&2, Nat>:
  owning_task(namespace(state), documents(state), expected)

def fresh(+state: State) -> Bool:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  fresh && allowed

def allowed(+state: State) -> Bool:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  allowed


def found_source(found: Maybe<&2, Document>) -> Bool:
  match found:
    case None{}: False{}
    case Some{document}: True{}

def source_known(+source: Code.Source, +state: State) -> Bool:
  found_source(find(documents(state), Code.source_key(source)))






# Shared definitions have no Markdown transport. The declaration and its complete
# fence are admitted together, then use the same parser, reducer and source refresh.
def publish_shared(+document: Document, +world: M.World(), +state: State) -> Decision:
  Document{+source, +text, +epoch, +revision, +ending, +observed, +fences, +active} = document
  +registered: State = with_documents(save(documents(state), document), state)
  +result: Decision = input(UI.SourceChanged{owner(source, 0n, epoch), text, True{}, UI.Complete{}, external(document, registered)}, registered)
  append_result(result_effects(result), refresh(world, result_state(result)))

def replace_shared(+source: Code.Source, +text: String, +revision: Nat, +world: M.World(), +state: State) -> Decision:
  State{+namespace, +sequence, +fresh, +allowed, +display_ready, +documents, +core, +next_epoch, +retention} = state
  publish_shared(Document{source, text, next_epoch, revision, UI.Complete{}, String.length(text), [Fence{0n, True{}, text, True{}, False{}}], True{}}, world,
    State{namespace, sequence, fresh, allowed, display_ready, documents, core, 1n+next_epoch, retention})

def shared_unchanged(+same: Bool, +previous: Document, +source: Code.Source, +text: String, +revision: Nat, +world: M.World(), +state: State) -> Decision:
  match same:
    case True{}: publish_shared(reactivate(previous), world, state)
    case False{}:
      +removed: Decision = remove_old(previous, state)
      append_result(result_effects(removed), replace_shared(source, text, revision, world, result_state(removed)))

def shared_existing(+found: Maybe<&2, Document>, +source: Code.Source, +text: String, +revision: Nat, +world: M.World(), +state: State) -> Decision:
  match found:
    case None{}: replace_shared(source, text, revision, world, state)
    case Some{+previous}:
      Document{+old_source, +old_text, +epoch, +old_revision, +ending, +observed, +fences, +active} = previous
      shared_unchanged(SafeText.string_equal(old_text, text), previous, source, text, revision, world, state)

def shared(+owner: String, +text: String, +revision: Nat, +world: M.World(), +state: State) -> Decision:
  +source: Code.Source = Code.SharedDocument{namespace(state), owner}
  shared_existing(find(documents(state), Code.source_key(source)), source, text, revision, world, state)

def shared_owner_found(+found: Maybe<&2, Document>, +expected: UI.Owner) -> Bool:
  match found:
    case None{}: False{}
    case Some{Document{+source, text, +epoch, revision, ending, observed, +fences, active}}:
      active && owner_matches(fences, source, epoch, expected)

def shared_owner(+expected: UI.Owner, +owner: String, +state: State) -> Bool:
  +source: Code.Source = Code.SharedDocument{namespace(state), owner}
  shared_owner_found(find(documents(state), Code.source_key(source)), expected)
