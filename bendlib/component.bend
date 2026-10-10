import Base
import ./json.bend as J

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

def lift(-S: Data, -R: Data, -E: Data, -F: Data,
  step: S -> Decision<S, E>, encode: +List<E> -> +List<F>, frame: Frame<S, R>) -> Decision<Frame<S, R>, F>:
  Frame{state, rest} = frame
  attach(S, R, E, F, encode, step(state), rest)

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

def lift_refinement(-S: Data, -R: Data, -E: Data, -F: Data,
  -actual: S -> Decision<S, E>, -spec: S -> Decision<S, E>,
  -encode: +List<E> -> +List<F>, -state: S, -rest: R,
  evidence: {actual(state) == spec(state) : Decision<S, E>}) ->
  {lift(S, R, E, F, actual, encode, Frame{state, rest}) ==
   lift(S, R, E, F, spec, encode, Frame{state, rest}) : Decision<Frame<S, R>, F>}:
  Equal.cong(Decision<S, E>, Decision<Frame<S, R>, F>,
    decision => attach(S, R, E, F, encode, decision, rest), actual(state), spec(state), evidence)

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
