import Base
import ./TYPES.bend as T
import ./STATE.bend as State
import ./SYNTAX.bend as Syntax
import ./PARSER.bend as Parser

def initial() -> T.State:
  State.initial()

def step(input: T.Input, state: T.State) -> T.Decision:
  State.step(input, state)

def observe(owner: T.Owner, state: T.State) -> T.Scene:
  State.observe(owner, state)

def source_requests(state: T.State) -> +List<T.SourceRequest>:
  State.source_requests(state)

def requests(state: T.State) -> +List<T.SourceRequest>:
  State.source_requests(state)

def eligible_fence(interactive: Bool, kind: String, info: String, complete: Bool) -> Bool:
  Parser.eligible_fence(interactive, kind, info, complete)

def same_owner(left: T.Owner, right: T.Owner) -> Bool:
  Syntax.same_owner(left, right)

def same_identity(left: T.Identity, right: T.Identity) -> Bool:
  Syntax.same_identity(left, right)

def same_event(left: T.EventIdentity, right: T.EventIdentity) -> Bool:
  Syntax.same_event(left, right)

def same_schema(left: T.StateSchema, right: T.StateSchema) -> Bool:
  Syntax.same_schema(left, right)
