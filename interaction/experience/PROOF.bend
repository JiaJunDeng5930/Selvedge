import Base
import ./CONTRACT.bend as Rule
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../bendlib/equality-proof.bend as Same
import ../../harness/transport/schema.bend as Schema

def duplicate_rejection(compatible: Bool, rest: Bool) ->
  {P.admitted_candidate(compatible, True{}, rest) == False{} : Bool}:
  match compatible:
    case True{}: {==}
    case False{}: {==}

def selected_equation(+decision: M.Decision, +candidate: M.Value) ->
  {P.selected(decision, candidate) == P.observed_selection(Rule.subject_field(P.decision_subject(decision)), P.decision_observation(decision), candidate) : Bool}:
  match decision:
    case M.Decision{M.Subject{editor, field}, observation, question, alternatives, availability}: {==}

def choose_equation(+decision: M.Decision, +candidate: M.Value) ->
  {P.choose(decision, candidate) == P.choose_admitted(P.admitted_value(P.decision_alternatives(decision), candidate), P.decision_subject(decision), P.decision_observation(decision)) : Maybe<&2, U.Input>}:
  match decision:
    case M.Decision{subject, observation, question, alternatives, availability}: {==}

def model_selection(+profile: D.Profile, +effort: String) ->
  {P.model_intent(profile, effort) == P.permitted_model(D.profile_permitted(profile, P.model_effort(D.profile_permitted(profile, effort), effort, profile)), Rule.profile_key(profile), P.model_effort(D.profile_permitted(profile, effort), effort, profile)) : Maybe<&2, U.Edit>}:
  match profile:
    case D.Profile{key, provider, name, policy, options}: {==}

def supporting_subjects(+support: M.Support) ->
  {P.support_subjects(support) == P.subjects(P.support_fields(support), Rule.identity_editor(P.support_identity(support))) : +List<M.Subject>}:
  match support:
    case M.Support{M.ActionIdentity{editor, revision}, fields}: {==}

def head_contains(+key: String, +seen: +List<String>) -> {Schema.contains(key <> seen, key) == True{} : Bool}:
  Equal.cong(Bool, Bool, (same => same || Schema.contains(seen, key)), String.eq(key, key), True{}, Same.same_string(key))

def duplicate_input(label: String, explanation: String, +value: M.Value, +rest: +List<M.Alternative>, +subject: M.Subject, +observation: Forms.Observed, +seen: +List<String>) ->
  {P.admissible(M.Alternative{label, explanation, value} <> rest, subject, observation, P.value_key(value) <> seen) == False{} : Bool}:
  +compatible: Bool = P.has_intent(P.canonical(subject, observation, value))
  +remaining: Bool = P.admissible(rest, subject, observation, P.value_key(value) <> P.value_key(value) <> seen)
  Equal.trans(Bool,
    P.admitted_candidate(compatible, Schema.contains(P.value_key(value) <> seen, P.value_key(value)), remaining),
    P.admitted_candidate(compatible, True{}, remaining), False{},
    Equal.cong(Bool, Bool, (duplicate => P.admitted_candidate(compatible, duplicate, remaining)), Schema.contains(P.value_key(value) <> seen, P.value_key(value)), True{}, head_contains(P.value_key(value), seen)),
    duplicate_rejection(compatible, remaining))
def Rule.experience_evidence():
  Rule.Requirements{
    +subject => observation => question => alternatives => {==},
    subject => +observation => question => alternatives => {==},
    subject => observation => +question => alternatives => {==},
    +subject => +observation => question => +alternatives => {==},
    +subject => +observation => question => +alternatives => {==},
    subject => observation => question => {==},
    subject => observation => question => candidate => {==},
    compatible => rest => duplicate_rejection(compatible, rest),
    duplicate => rest => {==},
    label => explanation => +value => rest => subject => observation => +seen => duplicate_input(label, explanation, value, rest, subject, observation, seen),
    label => explanation => +value => rest => +candidate => {==},
    values => {==},
    {==},
    label => explanation => +value => rest => +subject => +observation => +seen => {==},
    +decision => +candidate => selected_equation(decision, candidate),
    +decision => +candidate => choose_equation(decision, candidate),
    subject => observation => {==},
    +subject => +observation => +value => {==},
    +editor => +field => +observation => +value => {==},
    intent => {==},
    +editor => +field => +observation => +value => {==},
    {==},
    +task => {==},
    +project => {==},
    +task => {==},
    +editor => {==},
    +editor => {==},
    +editor => {==},
    +editor => +field => {==},
    +editor => +revision => {==},
    +editor => {==},
    +editor => +first => +rest => {==},
    editor => object => {==},
    +editor => field => +rest => +object => {==},
    +object => editor => {==},
    object => +editor => {==},
    {==},
    +task => {==},
    +project => {==},
    +task => {==},
    +editor => {==},
    +editor => {==},
    +editor => {==},
    origin => project => workspace => +sandbox => approval => guidance => +mode => {==},
    origin => project => workspace => +sandbox => approval => guidance => +enabled => {==},
    origin => project => workspace => sandbox => approval => guidance => +choice => {==},
    origin => project => workspace => +sandbox => approval => guidance => +mode => {==},
    origin => project => workspace => +sandbox => approval => guidance => +network => {==},
    origin => project => workspace => sandbox => +approval => guidance => +choice => {==},
    +current => effort => +key => provider => name => policy => options => {==},
    profile => +current => +effort => {==},
    roots => +primary => +path => {==},
    observation => value => {==},
    observation => value => {==},
    old => +network => +mode => {==},
    +mode => old => +network => {==},
    +profile => +effort => model_selection(profile, effort),
    +profile => old => +effort => {==},
    +roots => primary => +path => {==},
    task => observation => value => {==},
    task => observation => value => {==},
    editor => +workspace => {==},
    +editor => workspace => {==},
    editor => +workspace => {==},
    editor => +workspace => +path => {==},
    +editor => +workspace => {==},
    +collection => +path => {==},
    +editor => +workspace => +path => {==},
    +editor => revision => pending => {==},
    editor => revision => +pending => {==},
    +editor => +revision => pending => {==},
    +editor => revision => pending => {==},
    +editor => revision => pending => {==},
    +editor => revision => pending => {==},
    +editor => +revision => pending => fields => {==},
    +editor => revision => pending => +fields => {==},
    +support => supporting_subjects(support),
    +field => {==},
    task => +field => {==},
    field => {==},
    task => {==},
    {==},
    +editor => +revision => +reason => {==}}
