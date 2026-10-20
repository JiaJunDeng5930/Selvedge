import Base
import ../DOMAIN.bend as D
import ./side-contract.bend as Spec
import ./side-conversation.bend as Side

def child(+id: Nat, +parent: D.Task) ->
  {Side.child(id, parent) == Spec.required_child(id, parent) : D.Task}:
  {==}

def initial_message(+empty: Bool, +message: D.UserContent, +task: D.Task) ->
  {Side.initial_message(empty, message, task) == Spec.initial_message(empty, message, task) : D.Task}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def opened(+id: Nat, +parent: D.Task, +message: D.UserContent) ->
  {Side.opened(id, parent, message) == Spec.initial_message(Bool.not(D.content_nonempty(message)), message, Spec.required_child(id, parent)) : D.Task}:
  Equal.trans(D.Task,
    Side.opened(id, parent, message),
    Side.initial_message(Bool.not(D.content_nonempty(message)), message, Spec.required_child(id, parent)),
    Spec.initial_message(Bool.not(D.content_nonempty(message)), message, Spec.required_child(id, parent)),
    Equal.cong(D.Task, D.Task, (task => Side.initial_message(Bool.not(D.content_nonempty(message)), message, task)),
      Side.child(id, parent), Spec.required_child(id, parent), child(id, parent)),
    initial_message(Bool.not(D.content_nonempty(message)), message, Spec.required_child(id, parent)))

def content(+messages: +List<D.Message>) ->
  {Side.content(messages) == Spec.required_content(messages) : +List<D.Message>}:
  match messages:
    case Nil{}: {==}
    case Con{+message, +rest}:
      Equal.cong(+List<D.Message>, +List<D.Message>, (tail => Spec.retained(Spec.content(message), message, tail)),
        Side.content(rest), Spec.required_content(rest), content(rest))

def side_instructions_excluded(owner: Nat, parent: Nat, start: Nat) ->
  {Spec.content(D.ContextMessage{D.SideConversation{owner, parent, start}}) == False{} : Bool}:
  {==}

def return_bookkeeping_excluded(owner: Nat, through: Nat) ->
  {Spec.content(D.ContextMessage{D.SideReturnCursor{owner, through}}) == False{} : Bool}:
  {==}
