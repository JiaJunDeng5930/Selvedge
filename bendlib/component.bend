import Base
import ./json.bend as J
import ./categories.bend as Categories

# Products keep an operation's state separate from the context it cannot see.
type Frame<-S: Data, -R: Data> is Data:
  Frame{local: S, rest: R}

# A component decision retains the reply and the ordered effects, not just state.

type Decision<-S: Data, -E: Data> is Data:
  Decision{state: S, reply: J.Json, effects: +List<E>}

def local(-S: Data, -R: Data, frame: Frame<S, R>) -> S:
  Frame{state, rest} = frame
  state

def rest(-S: Data, -R: Data, frame: Frame<S, R>) -> R:
  Frame{state, rest} = frame
  rest

def replace(-S: Data, -R: Data, state: S, frame: Frame<S, R>) -> Frame<S, R>:
  Frame{previous, rest} = frame
  Frame{state, rest}

def map_local(-S: Data, -R: Data, update: S -> S, frame: Frame<S, R>) -> Frame<S, R>:
  Frame{state, rest} = frame
  Frame{update(state), rest}

def map_rest(-S: Data, -R: Data, update: R -> R, frame: Frame<S, R>) -> Frame<S, R>:
  Frame{state, rest} = frame
  Frame{state, update(rest)}

def attach(-S: Data, -R: Data, -E: Data, -F: Data,
  encode: +List<E> -> +List<F>, decision: Decision<S, E>, rest: R) -> Decision<Frame<S, R>, F>:
  Decision{state, reply, effects} = decision
  Decision{Frame{state, rest}, reply, encode(effects)}


def remaining(-S: Data, -R: Data, -E: Data, decision: Decision<Frame<S, R>, E>) -> R:
  Decision{Frame{state, rest}, reply, effects} = decision
  rest

def project(-S: Data, -R: Data, -E: Data, decision: Decision<Frame<S, R>, E>) -> Decision<S, E>:
  Decision{Frame{state, rest}, reply, effects} = decision
  Decision{state, reply, effects}

def encode_decision(-S: Data, -E: Data, -F: Data, encode: +List<E> -> +List<F>, decision: Decision<S, E>) -> Decision<S, F>:
  Decision{state, reply, effects} = decision
  Decision{state, reply, encode(effects)}

def attach_frame(-S: Data, -R: Data, -E: Data, -F: Data,
  -encode: +List<E> -> +List<F>, decision: Decision<S, E>, -rest: R) ->
  {remaining(S, R, F, attach(S, R, E, F, encode, decision, rest)) == rest : R}:
  match decision:
    case Decision{state, reply, effects}: {==}

def attach_project(-S: Data, -R: Data, -E: Data, -F: Data,
  -encode: +List<E> -> +List<F>, decision: Decision<S, E>, -rest: R) ->
  {project(S, R, F, attach(S, R, E, F, encode, decision, rest)) == encode_decision(S, E, F, encode, decision) : Decision<S, F>}:
  match decision:
    case Decision{state, reply, effects}: {==}


def map_frame(-S: Data, -R: Data, -update: S -> S, -state: S, -untouched: R) ->
  {rest(S, R, map_local(S, R, update, Frame{state, untouched})) == untouched : R}:
  {==}

def replace_frame(-S: Data, -R: Data, -value: S, frame: Frame<S, R>) ->
  {rest(S, R, replace(S, R, value, frame)) == rest(S, R, frame) : R}:
  match frame:
    case Frame{previous, untouched}: {==}

def replace_local(-S: Data, -R: Data, -value: S, frame: Frame<S, R>) ->
  {local(S, R, replace(S, R, value, frame)) == value : S}:
  match frame:
    case Frame{previous, untouched}: {==}


# Construction evidence covers the intended write and the complete opaque frame.
type Replacement<-S: Data, -R: Data> is Data:
  Replacement{source: Frame<S, R>, value: S, result: Frame<S, R>}

def replacement_written(-S: Data, -R: Data, observation: Replacement<S, R>) -> Type:
  Replacement{source, value, result} = observation
  {local(S, R, result) == value : S}

def replacement_preserved(-S: Data, -R: Data, observation: Replacement<S, R>) -> Type:
  Replacement{source, value, result} = observation
  {rest(S, R, result) == rest(S, R, source) : R}

def replacement_category(-S: Data, -R: Data, observation: Replacement<S, R>) -> Type:
  Categories.intersection(Replacement<S, R>, replacement_written(S, R), replacement_preserved(S, R), observation)

def replacement_is_written(-S: Data, -R: Data) -> Categories.Inclusion<Replacement<S, R>, replacement_category(S, R), replacement_written(S, R)>:
  Categories.intersection_first(Replacement<S, R>, replacement_written(S, R), replacement_preserved(S, R))

def replacement_is_preserved(-S: Data, -R: Data) -> Categories.Inclusion<Replacement<S, R>, replacement_category(S, R), replacement_preserved(S, R)>:
  Categories.intersection_second(Replacement<S, R>, replacement_written(S, R), replacement_preserved(S, R))

def construct_replace(-S: Data, -R: Data, +value: S, +source: Frame<S, R>) -> Categories.Membership<Replacement<S, R>, replacement_category(S, R)>:
  result = replace(S, R, value, source)
  Categories.Membership{Replacement{source, value, result}, Categories.Intersection{replace_local(S, R, value, source), replace_frame(S, R, value, source)}}

def constructed_replacement(-S: Data, -R: Data, member: Categories.Membership<Replacement<S, R>, replacement_category(S, R)>) -> Frame<S, R>:
  Categories.Membership{Replacement{source, value, result}, evidence} = member
  result

# The encoder indexes the complete decision property without becoming state.
type Attachment<-S: Data, -R: Data, -E: Data, -F: Data> is Data:
  Attachment{decision: Decision<S, E>, untouched: R, result: Decision<Frame<S, R>, F>}

def attached_frame(-S: Data, -R: Data, -E: Data, -F: Data, -encode: +List<E> -> +List<F>, observation: Attachment<S, R, E, F>) -> Type:
  Attachment{decision, untouched, result} = observation
  {remaining(S, R, F, result) == untouched : R}

def attached_decision(-S: Data, -R: Data, -E: Data, -F: Data, -encode: +List<E> -> +List<F>, observation: Attachment<S, R, E, F>) -> Type:
  Attachment{decision, untouched, result} = observation
  {project(S, R, F, result) == encode_decision(S, E, F, encode, decision) : Decision<S, F>}

def attached_category(-S: Data, -R: Data, -E: Data, -F: Data, -encode: +List<E> -> +List<F>, observation: Attachment<S, R, E, F>) -> Type:
  Categories.intersection(Attachment<S, R, E, F>, attached_frame(S, R, E, F, encode), attached_decision(S, R, E, F, encode), observation)

def attachment_preserves_frame(-S: Data, -R: Data, -E: Data, -F: Data, -encode: +List<E> -> +List<F>) -> Categories.Inclusion<Attachment<S, R, E, F>, attached_category(S, R, E, F, encode), attached_frame(S, R, E, F, encode)>:
  Categories.intersection_first(Attachment<S, R, E, F>, attached_frame(S, R, E, F, encode), attached_decision(S, R, E, F, encode))

def attachment_preserves_decision(-S: Data, -R: Data, -E: Data, -F: Data, -encode: +List<E> -> +List<F>) -> Categories.Inclusion<Attachment<S, R, E, F>, attached_category(S, R, E, F, encode), attached_decision(S, R, E, F, encode)>:
  Categories.intersection_second(Attachment<S, R, E, F>, attached_frame(S, R, E, F, encode), attached_decision(S, R, E, F, encode))

def construct_attach(-S: Data, -R: Data, -E: Data, -F: Data,
  encode: +List<E> -> +List<F>, +decision: Decision<S, E>, +untouched: R) -> Categories.Membership<Attachment<S, R, E, F>, attached_category(S, R, E, F, encode)>:
  result = attach(S, R, E, F, encode, decision, untouched)
  Categories.Membership{Attachment{decision, untouched, result}, Categories.Intersection{attach_frame(S, R, E, F, encode, decision, untouched), attach_project(S, R, E, F, encode, decision, untouched)}}

def constructed_attachment(-S: Data, -R: Data, -E: Data, -F: Data, -encode: +List<E> -> +List<F>, member: Categories.Membership<Attachment<S, R, E, F>, attached_category(S, R, E, F, encode)>) -> Decision<Frame<S, R>, F>:
  Categories.Membership{Attachment{decision, untouched, result}, evidence} = member
  result

def lift(-S: Data, -R: Data, -E: Data, -F: Data,
  step: S -> Decision<S, E>, encode: +List<E> -> +List<F>, frame: Frame<S, R>) -> Decision<Frame<S, R>, F>:
  Frame{state, rest} = frame
  constructed_attachment(S, R, E, F, encode, construct_attach(S, R, E, F, encode, step(state), rest))


def lift_refinement(-S: Data, -R: Data, -E: Data, -F: Data,
  -actual: S -> Decision<S, E>, -spec: S -> Decision<S, E>,
  -encode: +List<E> -> +List<F>, -state: S, -rest: R,
  evidence: {actual(state) == spec(state) : Decision<S, E>}) ->
  {lift(S, R, E, F, actual, encode, Frame{state, rest}) ==
   lift(S, R, E, F, spec, encode, Frame{state, rest}) : Decision<Frame<S, R>, F>}:
  Equal.cong(Decision<S, E>, Decision<Frame<S, R>, F>,
    decision => attach(S, R, E, F, encode, decision, rest), actual(state), spec(state), evidence)
