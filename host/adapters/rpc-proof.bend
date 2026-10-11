import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ./RPC.bend as Rpc

# Covers the entire supplied operation and original observation, including
# rejection, next coordinates, wire replies and accepted external error values.
def production_correspondence(+operation: String, +source: J.Json) ->
  {Rpc.run(operation, source) == Rpc.meaning(operation, source) : J.Json}:
  {==}

# Production cancellation/response/failed-write cleanup all call Rpc.retired.
# This is the imported finite-map theorem, not a finite protocol replay.
def retirement_removes_authority(+entries: +List<Finite.Entry(Bool)>, +id: Nat) ->
  {Finite.find(~Bool, Rpc.retired(entries, id), id) == None{} : Maybe<&2, Bool>}:
  Finite.removal_absence(~Bool, entries, id)

def correlated_member_authority(+source: J.Json, member: Categories.Membership<J.Json, Categories.holds(J.Json, (message => Rpc.correlation(Rpc.pending(source), message)))>) ->
  Categories.Membership<J.Json, Categories.holds(J.Json, (message => Rpc.correlation(Rpc.pending(source), message)))>:
  member

# An outcome admitted by the actual response constructor carries independent
# correlation and XOR properties of that very same received message.
def response_authority(+source: J.Json, +message: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (message => Rpc.correlation(Rpc.pending(source), message))),
    Categories.holds(J.Json, (value => Rpc.exclusive(value))), message)) ->
  {Rpc.correlation(Rpc.pending(source), message) == True{} : Bool}:
  Categories.project_intersection_first(J.Json,
    Categories.holds(J.Json, (message => Rpc.correlation(Rpc.pending(source), message))),
    Categories.holds(J.Json, (value => Rpc.exclusive(value))), message, evidence)

def response_outcome_exclusive(+source: J.Json, +message: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (message => Rpc.correlation(Rpc.pending(source), message))),
    Categories.holds(J.Json, (value => Rpc.exclusive(value))), message)) ->
  {Rpc.exclusive(message) == True{} : Bool}:
  Categories.project_intersection_second(J.Json,
    Categories.holds(J.Json, (message => Rpc.correlation(Rpc.pending(source), message))),
    Categories.holds(J.Json, (value => Rpc.exclusive(value))), message, evidence)

def absent_response_is_ignored(+source: J.Json) ->
  {Rpc.response_admission(source, None{}) == Rpc.unchanged("ignore", source, Nil{}) : J.Json}:
  {==}

def absent_cancellation_is_ignored(+source: J.Json) ->
  {Rpc.retire_admission(source, None{}) == Rpc.unchanged("ignore", source, Nil{}) : J.Json}:
  {==}

def invalid_outcome_rejects(+source: J.Json, +message: J.Json,
  authority: {Rpc.correlation(Rpc.pending(source), message) == True{} : Bool}) ->
  {Rpc.response_outcome(source, message, authority, None{}) ==
    Rpc.settle_rejection(source, message, authority, Rpc.label(source) ++ " response must have exactly one of result or error") : J.Json}:
  {==}

# These are the actual correlated error admission branches. Neither malformed
# error shapes nor malformed message fields can produce a successful result.
def malformed_error_object_rejects(+source: J.Json, +message: J.Json,
  authority: {Rpc.correlation(Rpc.pending(source), message) == True{} : Bool}) ->
  {Rpc.response_error(source, message, authority, False{}) ==
    Rpc.settle_rejection(source, message, authority, "Malformed " ++ Rpc.label(source) ++ " error response") : J.Json}:
  {==}

def malformed_error_message_rejects(+source: J.Json, +message: J.Json,
  authority: {Rpc.correlation(Rpc.pending(source), message) == True{} : Bool}) ->
  {Rpc.response_error_text(source, message, authority, None{}) ==
    Rpc.settle_rejection(source, message, authority, "Malformed " ++ Rpc.label(source) ++ " error response") : J.Json}:
  {==}
