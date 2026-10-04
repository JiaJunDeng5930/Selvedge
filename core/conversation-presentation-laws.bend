import Base
import ./user-conversation.bend as Actual
import ./user-experience.bend as E
import ../bendlib/domain.bend as D
import ../bendlib/conversation-spec.bend as Spec

# Comparison reflexivity is needed to bind a reader's choice to its own group.
def activity_presentation(values: +List<Actual.VisibleGroup>) -> Bool & String:
  match values:
    case Con{Actual.VisibleActivity{id, attention, expanded, summary, audit, expand, collapse}, rest}: (expanded, summary)
    case _: (False{}, "")

# A deliberate collapse leaves the real failure title in the persistent summary.

def first_identity(values: +List<Actual.Group>) -> Maybe<&2, Nat>:
  match values:
    case Nil{}: None{}
    case Con{Actual.Speech{id, speaker, text, source}, rest}: Some{id}
    case Con{Actual.Activity{id, attention, entries}, rest}: Some{id}

type Requirements is Type:
  Requirements{
    disclosure: @+group:Nat -> @seen:Nat -> @+choice:Bool -> @+attention:Maybe<&2, Nat> -> @+rest:+List<E.Disclosure> ->
      {Actual.expanded(E.Disclosure{group, seen, choice} <> rest, group, attention) == choice : Bool},
    collapsed_attention: @+group:Nat -> @seen:Nat -> @+attention:Maybe<&2, Nat> -> @+entries:+List<Actual.Audit> -> @task:Nat -> @+index:Nat -> @+message:D.Message ->
      @observed:{Actual.latest_failure(entries) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>} ->
      {activity_presentation(Actual.visible([Actual.Activity{group, attention, entries}], task,
        [E.Disclosure{group, seen, False{}}])) ==
        (False{}, "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events") : Bool & String},
    newest_failure: @+entries:+List<Actual.Audit> -> @+index:Nat -> @+message:D.Message -> @+failed:{Actual.audit_failed(message) == True{} : Bool} ->
      {Actual.latest_failure(List.append(&2, Actual.Audit, entries, [Actual.Audit{index, message}])) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>},
    identity: @+index:Nat -> @+failed:Bool -> @+message:D.Message -> @+suffix:+List<D.Message> -> @more:+List<D.Message> ->
      {first_identity(Actual.prepend_audit(index, failed, message,
        Actual.groups(List.append(&2, D.Message, suffix, more), (index + 1n : Nat)))) ==
        first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))) : Maybe<&2, Nat>},
    history: @+messages:+List<D.Message> -> @+offset:Nat ->
      {Spec.sources(Actual.groups(messages, offset)) == messages : +List<D.Message>},
    visible_history: @+groups:+List<Actual.Group> -> @+task:Nat -> @+disclosures:+List<E.Disclosure> ->
      {Spec.visible_sources(Actual.visible(groups, task, disclosures)) == Spec.sources(groups) : +List<D.Message>},
    text: @+messages:+List<D.Message> -> @+offset:Nat -> @task:Nat -> @disclosures:+List<E.Disclosure> ->
      Spec.visible_text_agreement(Actual.visible(Actual.groups(messages, offset), task, disclosures))
  }

law evidence:
  Requirements
