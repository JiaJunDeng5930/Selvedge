import Base
import ./stdlib.bend as Std
import ./theory.bend as Theory

# Proof-carrying standard structures. Their indices bind the actual carrier and
# operations; a name or a comment is not evidence of any algebraic property.
type Semigroup<-A: Data, -join: A -> A -> A> is Type:
  Associative{associates: @x:A -> @y:A -> @z:A -> {join(join(x, y), z) == join(x, join(y, z)) : A}}

type Monoid<-A: Data, -empty: A, -join: A -> A -> A> is Type:
  Monoid{semigroup: Semigroup<A, join>,
    left_identity: @x:A -> {join(empty, x) == x : A},
    right_identity: @x:A -> {join(x, empty) == x : A}}

type Homomorphism<-A: Data, -B: Data, -emptyA: A, -joinA: A -> A -> A,
  -emptyB: B, -joinB: B -> B -> B, -transform: A -> B> is Type:
  Homomorphism{source: Monoid<A, emptyA, joinA>, target: Monoid<B, emptyB, joinB>,
    preserves_empty: {transform(emptyA) == emptyB : B},
    preserves_join: @first:A -> @second:A -> {transform(joinA(first, second)) == joinB(transform(first), transform(second)) : B}}

type RightAction<-S: Data, -E: Data, -empty: E, -join: E -> E -> E, -act: S -> E -> S> is Type:
  RightAction{events: Monoid<E, empty, join>,
    identity: @state:S -> {act(state, empty) == state : S},
    composition: @state:S -> @first:E -> @second:E ->
      {act(state, join(first, second)) == act(act(state, first), second) : S}}

type Projection<-A: Data, -project: A -> A> is Type:
  Projection{idempotent: @value:A -> {project(project(value)) == project(value) : A}}

# Exact refinement is a forward simulation with the identity state abstraction.
# The response includes the post-state, reply, and effects, not only state safety.
type Refinement<-S: Data, -I: Data, -O: Data, -specification: I -> S -> O, -implementation: I -> S -> O> is Type:
  Refinement{exact: @input:I -> @state:S -> {implementation(input, state) == specification(input, state) : O}}

type InvariantSystem<-S: Data, -I: Data, -initial: S, -step: S -> I -> S, -valid: S -> Bool> is Type:
  InvariantSystem{initial_valid: {valid(initial) == True{} : Bool},
    preserves: @state:S -> @input:I -> {valid(state) == True{} : Bool} -> {valid(step(state, input)) == True{} : Bool}}

type ReadOnly<-S: Data, -Q: Data, -R: Data, -E: Data, -observe: Q -> S -> R, -next: R -> S, -effects: R -> +List<E>> is Type:
  ReadOnly{unchanged: @query:Q -> @state:S -> {next(observe(query, state)) == state : S},
    no_effects: @query:Q -> @state:S -> {effects(observe(query, state)) == Nil{} : +List<E>}}

def append(-A: Data, first: +List<A>, second: +List<A>) -> +List<A>:
  List.append(&2, A, first, second)

# Only the correspondence to Base.append is local. The certificates came from
# existing Stdlib terms; this module contains no induction over standard algebra.
def list_monoid(-A: Data) -> Monoid<+List<A>, Nil{}, append(A)>:
  Monoid{Associative{(first => second => third => Theory.append_associative(A, first, second, third))},
    (items => {==}), (items => Std.app_nil_r(A, items))}

def act(~S: Data, ~E: Data, ~step: S -> E -> S, state: S, events: +List<E>) -> S:
  List.foldl(~&2, ~E, ~S, ~step, events, state)

def list_action(~S: Data, ~E: Data, ~step: S -> E -> S) ->
  RightAction<S, +List<E>, Nil{}, append(E), act(~S, ~E, ~step)>:
  RightAction{list_monoid(E), (state => {==}),
    (state => first => second => Std.fold_left_app(~S, ~E, ~step, first, second, state))}

def mapped(~A: Data, ~B: Data, ~f: A -> B, items: +List<A>) -> +List<B>:
  Std.map(~A, ~B, ~f, items)

def list_homomorphism(~A: Data, ~B: Data, ~f: A -> B) ->
  Homomorphism<+List<A>, +List<B>, Nil{}, append(A), Nil{}, append(B), mapped(~A, ~B, ~f)>:
  Homomorphism{list_monoid(A), list_monoid(B), {==},
    (first => second => Std.map_app(~A, ~B, ~f, first, second))}

def map_identity(~A: Data, +items: +List<A>) ->
  {mapped(~A, ~A, ~(item => item), items) == items : +List<A>}:
  Std.map_id(~A, items)

def map_composition(~A: Data, ~B: Data, ~C: Data, ~f: A -> B, ~g: B -> C, +items: +List<A>) ->
  {mapped(~B, ~C, ~g, mapped(~A, ~B, ~f, items)) == mapped(~A, ~C, ~(item => g(f(item))), items) : +List<C>}:
  Std.map_map(~A, ~B, ~C, ~f, ~g, items)

# Consumers use the actual structure evidence, rather than reaching behind the
# application into a second, privately re-proved theorem library.
def associative(-A: Data, -join: A -> A -> A, semigroup: Semigroup<A, join>, +x: A, +y: A, +z: A) ->
  {join(join(x, y), z) == join(x, join(y, z)) : A}:
  Associative{evidence} = semigroup
  evidence(x, y, z)

def monoid_associative(-A: Data, -empty: A, -join: A -> A -> A, monoid: Monoid<A, empty, join>, +x: A, +y: A, +z: A) ->
  {join(join(x, y), z) == join(x, join(y, z)) : A}:
  Monoid{semigroup, left, right} = monoid
  associative(A, join, semigroup, x, y, z)

def action_composition(-S: Data, -E: Data, -empty: E, -join: E -> E -> E, -act: S -> E -> S,
  action: RightAction<S, E, empty, join, act>, +state: S, +first: E, +second: E) ->
  {act(state, join(first, second)) == act(act(state, first), second) : S}:
  RightAction{events, identity, composition} = action
  composition(state, first, second)

def homomorphism_join(-A: Data, -B: Data, -emptyA: A, -joinA: A -> A -> A,
  -emptyB: B, -joinB: B -> B -> B, -transform: A -> B,
  mapping: Homomorphism<A, B, emptyA, joinA, emptyB, joinB, transform>, +first: A, +second: A) ->
  {transform(joinA(first, second)) == joinB(transform(first), transform(second)) : B}:
  Homomorphism{source, target, empty, join} = mapping
  join(first, second)
