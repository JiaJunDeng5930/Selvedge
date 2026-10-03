import Base
import ../core/user-conversation.bend as Actual
import ../core/user-experience.bend as E
import ../bendlib/domain.bend as D
import ../bendlib/conversation-spec.bend as Spec
import ../bendlib/proofs/conversation.bend as History

# Comparison reflexivity is needed to bind a reader's choice to its own group.
def same_group(+group: Nat) -> {Nat.is_eq(group, group) == True{} : Bool}:
  match group:
    case 0n: {==}
    case 1n+previous: same_group(previous)

def explicit_disclosure(+group: Nat, seen: Nat, +choice: Bool,
  +attention: Maybe<&2, Nat>, +rest: +List<E.Disclosure>) ->
  {Actual.expanded(E.Disclosure{group, seen, choice} <> rest, group, attention) == choice : Bool}:
  Equal.cong(Bool, Bool,
    hit => Actual.choose_expanded(hit, choice, Actual.expanded(rest, group, attention)),
    Nat.is_eq(group, group), True{}, same_group(group))

def failure_summary(+entries: +List<Actual.Audit>, +index: Nat, +message: D.Message,
  observed: {Actual.latest_failure(entries) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>}) ->
  {Actual.activity_summary(entries) ==
    "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events" : String}:
  Equal.cong(Maybe<&2, Actual.Audit>, String,
    failure => Actual.summarized_activity(failure, entries),
    Actual.latest_failure(entries), Some{Actual.Audit{index, message}}, observed)

def last_failure(+entries: +List<Actual.Audit>, +index: Nat, +message: D.Message,
  +failed: {Actual.audit_failed(message) == True{} : Bool}) ->
  {Actual.latest_failure(List.append(&2, Actual.Audit, entries, [Actual.Audit{index, message}])) ==
    Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>}:
  match entries:
    case Nil{}:
      Equal.cong(Bool, Maybe<&2, Actual.Audit>,
        flag => Actual.failure_candidate(flag, Actual.Audit{index, message}),
        Actual.audit_failed(message), True{}, failed)
    case Con{Actual.Audit{head_index, +head_message}, +rest}:
      Equal.cong(Maybe<&2, Actual.Audit>, Maybe<&2, Actual.Audit>,
        later => Actual.prefer_failure(later, Actual.failure_candidate(Actual.audit_failed(head_message), Actual.Audit{head_index, head_message})),
        Actual.latest_failure(List.append(&2, Actual.Audit, rest, [Actual.Audit{index, message}])),
        Some{Actual.Audit{index, message}}, last_failure(rest, index, message, failed))

def activity_presentation(values: +List<Actual.VisibleGroup>) -> Bool & String:
  match values:
    case Con{Actual.VisibleActivity{id, attention, expanded, summary, audit, expand, collapse}, rest}: (expanded, summary)
    case _: (False{}, "")

# A deliberate collapse leaves the real failure title in the persistent summary.
def collapsed_attention_law(-group: Nat, -seen: Nat, -attention: Maybe<&2, Nat>,
  -entries: +List<Actual.Audit>, -task: Nat, -index: Nat, -message: D.Message,
  -observed: {Actual.latest_failure(entries) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>}) -> Type:
  {activity_presentation(Actual.visible([Actual.Activity{group, attention, entries}], task,
    [E.Disclosure{group, seen, False{}}])) ==
    (False{}, "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events") : Bool & String}

def collapsed_failure(+group: Nat, seen: Nat, +attention: Maybe<&2, Nat>,
  +entries: +List<Actual.Audit>, task: Nat, +index: Nat, +message: D.Message,
  observed: {Actual.latest_failure(entries) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>}) ->
  collapsed_attention_law(group, seen, attention, entries, task, index, message, observed):
  Equal.trans(Bool & String,
    activity_presentation(Actual.visible([Actual.Activity{group, attention, entries}], task, [E.Disclosure{group, seen, False{}}])),
    (False{}, Actual.activity_summary(entries)),
    (False{}, "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events"),
    Equal.cong(Bool, Bool & String, expanded => (expanded, Actual.activity_summary(entries)),
      Actual.expanded([E.Disclosure{group, seen, False{}}], group, attention), False{},
      explicit_disclosure(group, seen, False{}, attention, Nil{})),
    Equal.cong(String, Bool & String, summary => (False{}, summary), Actual.activity_summary(entries),
      "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events",
      failure_summary(entries, index, message, observed)))

def first_identity(values: +List<Actual.Group>) -> Maybe<&2, Nat>:
  match values:
    case Nil{}: None{}
    case Con{Actual.Speech{id, speaker, text, source}, rest}: Some{id}
    case Con{Actual.Activity{id, attention, entries}, rest}: Some{id}

def audit_identity(+index: Nat, failed: Bool, message: D.Message, tail: +List<Actual.Group>) ->
  {first_identity(Actual.prepend_audit(index, failed, message, tail)) == Some{index} : Maybe<&2, Nat>}:
  match tail:
    case Nil{}: {==}
    case Con{Actual.Speech{id, speaker, text, source}, rest}: {==}
    case Con{Actual.Activity{id, attention, entries}, rest}: {==}

# The oldest audit occurrence owns the run even after its suffix grows.
def identity_law(-index: Nat, -failed: Bool, -message: D.Message, -suffix: +List<D.Message>,
  -more: +List<D.Message>) -> Type:
  {first_identity(Actual.prepend_audit(index, failed, message,
    Actual.groups(List.append(&2, D.Message, suffix, more), (index + 1n : Nat)))) ==
    first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))) : Maybe<&2, Nat>}

def appended_run_identity(+index: Nat, +failed: Bool, +message: D.Message,
  +suffix: +List<D.Message>, more: +List<D.Message>) ->
  identity_law(index, failed, message, suffix, more):
  Equal.trans(Maybe<&2, Nat>,
    first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(List.append(&2, D.Message, suffix, more), (index + 1n : Nat)))),
    Some{index}, first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))),
    audit_identity(index, failed, message, Actual.groups(List.append(&2, D.Message, suffix, more), (index + 1n : Nat))),
    Equal.sym(Maybe<&2, Nat>, first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))),
      Some{index}, audit_identity(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))))

type Requirements is Type:
  Requirements{
    disclosure: @+group:Nat -> @seen:Nat -> @+choice:Bool -> @+attention:Maybe<&2, Nat> -> @+rest:+List<E.Disclosure> ->
      {Actual.expanded(E.Disclosure{group, seen, choice} <> rest, group, attention) == choice : Bool},
    collapsed_attention: @+group:Nat -> @seen:Nat -> @+attention:Maybe<&2, Nat> -> @+entries:+List<Actual.Audit> -> @task:Nat -> @+index:Nat -> @+message:D.Message ->
      @observed:{Actual.latest_failure(entries) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>} ->
      collapsed_attention_law(group, seen, attention, entries, task, index, message, observed),
    newest_failure: @+entries:+List<Actual.Audit> -> @+index:Nat -> @+message:D.Message -> @+failed:{Actual.audit_failed(message) == True{} : Bool} ->
      {Actual.latest_failure(List.append(&2, Actual.Audit, entries, [Actual.Audit{index, message}])) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>},
    identity: @+index:Nat -> @+failed:Bool -> @+message:D.Message -> @+suffix:+List<D.Message> -> @more:+List<D.Message> ->
      identity_law(index, failed, message, suffix, more),
    history: @+messages:+List<D.Message> -> @+offset:Nat ->
      {Spec.sources(Actual.groups(messages, offset)) == messages : +List<D.Message>},
    visible_history: @+groups:+List<Actual.Group> -> @+task:Nat -> @+disclosures:+List<E.Disclosure> ->
      {Spec.visible_sources(Actual.visible(groups, task, disclosures)) == Spec.sources(groups) : +List<D.Message>},
    text: @+messages:+List<D.Message> -> @+offset:Nat -> @task:Nat -> @disclosures:+List<E.Disclosure> ->
      Spec.visible_text_agreement(Actual.visible(Actual.groups(messages, offset), task, disclosures))
  }

def evidence() -> Requirements:
  Requirements{
    group => seen => choice => attention => rest => explicit_disclosure(group, seen, choice, attention, rest),
    group => seen => attention => entries => task => index => message => observed => collapsed_failure(group, seen, attention, entries, task, index, message, observed),
    entries => index => message => failed => last_failure(entries, index, message, failed),
    index => failed => message => suffix => more => appended_run_identity(index, failed, message, suffix, more),
    messages => offset => History.grouped_history(messages, offset),
    groups => task => disclosures => History.visible_history(groups, task, disclosures),
    messages => offset => task => disclosures => History.observed_text(messages, offset, task, disclosures)
  }
