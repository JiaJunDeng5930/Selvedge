import Base
import ./locality-proof.bend as Local
import ../features/MODEL.bend as F
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ./MODEL.bend as R
import ./CONTRACT.bend as A
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./context.bend as Context
import ../execution/OPERATIONS.bend as Ops
import ../tasks/PROGRAM.bend as T
import ../../bendlib/json.bend as J

def A.route_meaning(policy, lease):
  Local.route_meaning(policy, lease)

def A.start_meaning(task, world):
  Local.start_meaning(F.State(), F.Effect, task, world)

def selection_meaning(+accepted: Bool, +effort: String, +generations: Nat, +task: D.Task) ->
  {Actual.chosen(accepted, effort, generations, task) == Spec.selection(accepted, effort, generations, task) : D.Task}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def outcome_meaning(+outcome: R.Outcome, +task: D.Task) ->
  {Actual.observed(outcome, task) == Spec.outcome(outcome, task) : D.Task}:
  match outcome:
    case R.Chosen{+effort, +generations}:
      selection_meaning(R.accepts(Context.task_policy(task), effort, generations), effort, generations, task)
    case R.EvaluationFailed{reason}: {==}

def fresh_meaning(+current: Bool, +outcome: R.Outcome, +task: D.Task) ->
  {Actual.revision_matches(current, outcome, task) == Spec.fresh(current, outcome, task) : D.Task}:
  match current:
    case True{}: outcome_meaning(outcome, task)
    case False{}: {==}

def A.completion_meaning(revision, outcome, task):
  fresh_meaning(Nat.is_eq(revision, D.history_length(D.task_history(task))), outcome, task)

def contract_frame(effort: String, remaining: Nat, +task: D.Task) ->
  {D.task_contract(Context.generation(effort, remaining, task)) == D.task_contract(task) : D.Contract}:
  match task:
    case D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def A.reasoning_boundary():
  A.ReasoningBoundary{
    A.route_meaning, A.start_meaning, A.completion_meaning,
    (lease => {==}),
    (effort => remaining => {==}),
    (effort => remaining => {==}),
    (evaluator => efforts => baseline => transport => maximum => effort => generations => {==}),
    (history => owner => record_owner => effort => remaining => sampling => {==}),
    (effort => remaining => {==}),
    (outcome => task => {==}),
    (expected => revision => task => ticket => outcome => {==}),
    (phase => task => ticket => outcome => {==}),
    (history => text => owner => {==}),
    (history => call => value => owner => {==}),
    (history => text => owner => {==}),
    (history => summary => owner => {==}),
    (history => summary => {==}),
    (evaluator => efforts => baseline => maximum => effective => {==}),
    (effort => remaining => owner => history => {==}),
    (effort => remaining => owner => history => {==}),
    (history => {==}), contract_frame,
    (secret => summary => tail => {==}),
    (secret => {==}), (id => value => error => tail => {==})}
