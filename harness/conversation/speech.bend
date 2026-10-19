import Base
import ../DOMAIN.bend as D
import ../tasks/PROGRAM.bend as Tasks
import ../../bendlib/json.bend as J

def selected(same: Bool, entry: D.Message, rest: Maybe<&2, D.Message>) -> Maybe<&2, D.Message>:
  match same:
    case True{}: Some{entry}
    case False{}: rest


# Receipt ownership is the accepting task, not the task that inherited its history.
def transcript(history: D.History, +owner: Nat, +session: String, +item: String) -> Maybe<&2, D.Message>:
  match history:
    case D.EmptyHistory{}: None{}
    case D.HistoryNode{previous, D.SpeechTranscript{+actual, +source, +identity, speaker, completion, text}}:
      selected(Nat.is_eq(actual, owner) && String.eq(source, session) && String.eq(identity, item),
        D.SpeechTranscript{actual, source, identity, speaker, completion, text}, transcript(previous, owner, session, item))
    case D.HistoryNode{previous, other}: transcript(previous, owner, session, item)

def delegation(history: D.History, +owner: Nat, +session: String, +identity: String) -> Maybe<&2, D.Message>:
  match history:
    case D.EmptyHistory{}: None{}
    case D.HistoryNode{previous, D.SpeechDelegationReceipt{+actual, +source, +key, mode, text}}:
      selected(Nat.is_eq(actual, owner) && String.eq(source, session) && String.eq(key, identity),
        D.SpeechDelegationReceipt{actual, source, key, mode, text}, delegation(previous, owner, session, identity))
    case D.HistoryNode{previous, other}: delegation(previous, owner, session, identity)

def transcript_result(owner: Nat, session: String, item: String, replayed: Bool) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(owner)}, J.Field{"session_id", J.Text{session}}, J.Field{"item_id", J.Text{item}}, J.Field{"recorded", J.Boolean{True{}}}, J.Field{"replayed", J.Boolean{replayed}}]}

def delegation_result(owner: Nat, session: String, identity: String, replayed: Bool) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(owner)}, J.Field{"session_id", J.Text{session}}, J.Field{"delegation_id", J.Text{identity}}, J.Field{"accepted", J.Boolean{True{}}}, J.Field{"replayed", J.Boolean{replayed}}]}

def record(session: String, item: String, speaker: D.SpeechSpeaker, completion: D.SpeechCompletion, text: String, +task: D.Task) -> D.Task:
  D.append_message(D.SpeechTranscript{D.task_id(task), session, item, speaker, completion, text}, task)

def delivered(steer: Bool, text: String, task: D.Task) -> D.Task:
  match steer:
    case True{}: Tasks.steer(text, task)
    case False{}: Tasks.receive(text, task)

# The ordinary input is accepted before its receipt is appended. Both are one
# immutable task value in the command's single committed journal decision.
def accepted(session: String, identity: String, +mode: String, +text: String, +task: D.Task) -> D.Task:
  receipt : D.Message = D.SpeechDelegationReceipt{D.task_id(task), session, identity, mode, text}
  D.append_message(receipt, delivered(String.eq(mode, "steer"), text, task))
