import Base
import ./transport/schema.bend as Schema
import ./features/STATE.bend as FeatureState
import ../bendlib/effects.bend as Effects
import ./features/MODEL.bend as F
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ./reasoning/MODEL.bend as Reasoning
import ./reasoning/context.bend as ReasoningContext
import ./MODEL.bend as M
import ./tasks/PROGRAM.bend as T
import ./execution/OPERATIONS.bend as Ops
import ../bendlib/equality.bend as Same
import ../bendlib/json.bend as J
import ./approval/HOOKS.bend as Hooks
import ./workspace/WORKSPACE.bend as Workspace
import ./workspace/PROJECTS.bend as Projects
import ./approval/MODEL.bend as Approvals

# A world is an append-only registry of tasks, whose ancestry is a forest.
# These predicates are executed by PROGRAM's admission boundary and named by
# LAWS. They are requirements about actual values, not a second task simulator.
def missing_tool(found: Maybe<&2, D.Tool>) -> Bool:
  match found:
    case None{}: True{}
    case Some{tool}: False{}

def unique_tools(tools: +List<D.Tool>) -> Bool:
  match tools:
    case Nil{}: True{}
    case Con{+tool, +rest}:
      D.nonempty(D.tool_name(tool)) && missing_tool(T.find_tool(rest, D.tool_name(tool))) && unique_tools(rest)

def missing_profile(found: Maybe<&2, D.Profile>) -> Bool:
  match found:
    case None{}: True{}
    case Some{profile}: False{}

def unique_profiles(profiles: +List<D.Profile>) -> Bool:
  match profiles:
    case Nil{}: True{}
    case Con{D.Profile{+key, provider, name, policy, options}, +rest}:
      D.profile_valid(D.Profile{key, provider, name, policy, options}) &&
        missing_profile(D.find_profile(rest, key)) && unique_profiles(rest)

def project_context(project: D.ProjectContext) -> Bool:
  Workspace.valid_guidance(project)

def environment(environment: D.Environment) -> Bool:
  D.Environment{+catalog, profiles, max_fork, max_descendants, project, +plugins} = environment
  Hooks.valid(plugins) && Hooks.routes(catalog, plugins) && project_context(project) && unique_tools(catalog) && unique_profiles(profiles) &&
    Nat.is_le(1n, max_fork) && Nat.is_le(1n, max_descendants)

def contract(contract: D.Contract) -> Bool:
  D.Contract{D.Model{+profile, reasoning, +project}, +tools, max_fork, max_descendants, +plugins, +context} = contract
  Workspace.valid_context(context) && Workspace.guidance_member(Workspace.primary(Workspace.workspace(context)), project) &&
    Hooks.valid(plugins) && Hooks.routes(tools, plugins) && project_context(project) &&
    D.profile_valid(profile) && D.profile_permitted(profile, reasoning) &&
    unique_tools(tools) && Nat.is_le(1n, max_fork) && Nat.is_le(1n, max_descendants)

def lineage_parent(found: Maybe<&2, D.Task>, child: Nat, tail: +List<Nat>, contract: D.Contract, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+parent}:
      Nat.is_lt(D.task_id(parent), child) && Same.naturals(tail, D.task_lineage(parent)) &&
        Same.inherited_contract(budget, contract, D.task_contract(parent))

def lineage(lineage: +List<Nat>, child: Nat, contract: D.Contract, tasks: +List<D.Task>, budget: Nat) -> Bool:
  match lineage:
    case Nil{}: True{}
    case Con{parent, tail}: lineage_parent(T.find(tasks, parent), child, tail, contract, budget)

def has_output(history: D.History, +id: String) -> Bool:
  match history:
    case D.EmptyHistory{}: False{}
    case D.HistoryNode{previous, D.FunctionOutput{call_id, value, error}}:
      String.eq(call_id, id) || has_output(previous, id)
    case D.HistoryNode{previous, D.ForkResult{owner, call_id, branch}}:
      String.eq(call_id, id) || has_output(previous, id)
    case D.HistoryNode{previous, other}: has_output(previous, id)

def has_attempt(attempts: +List<D.Attempt>, +id: String) -> Bool:
  match attempts:
    case Nil{}: False{}
    case Con{attempt, rest}: String.eq(T.call_id(D.attempt_call(attempt)), id) || has_attempt(rest, id)

def open_call(call: D.Call, +history: D.History) -> Bool:
  +id = T.call_id(call)
  T.history_has_call(history, id) && Bool.not(has_output(history, id))

def attempts(pending: +List<D.Attempt>, +history: D.History) -> Bool:
  match pending:
    case Nil{}: True{}
    case Con{attempt, +rest}:
      +call = D.attempt_call(attempt)
      open_call(call, history) && Bool.not(has_attempt(rest, T.call_id(call))) && attempts(rest, history)

def callable(names: +List<String>, +tools: +List<D.Tool>) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{+name, +rest}:
      Bool.not(missing_tool(T.find_tool(tools, name))) && Bool.not(Schema.contains(rest, name)) && callable(rest, tools)

def phase(status: D.Status, phase: D.Phase, +history: D.History, tools: +List<D.Tool>, next_ticket: Nat) -> Bool:
  match status phase:
    case D.Archived{} D.Idle{}: True{}
    case D.Archived{} _: False{}
    case _ D.Idle{}: True{}
    case _ D.CompactionReady{}: True{}
    case _ D.Ready{pending}: attempts(pending, history)
    case _ D.ModelPending{ticket, names}: Nat.is_lt(ticket, next_ticket) && callable(names, tools)
    case _ D.ReasoningPending{ticket, revision}: Nat.is_lt(ticket, next_ticket) && Nat.is_le(revision, D.history_length(history))
    case _ D.SummaryPending{ticket, resume}: Nat.is_lt(ticket, next_ticket)
    case _ D.HookPending{ticket, reference, call, pending, remaining}:
      Nat.is_lt(ticket, next_ticket) && attempts(D.CheckedAttempt{call, reference <> pending} <> remaining, history)

def ticket_is(phase: D.Phase, ticket: Nat) -> Bool:
  match phase:
    case D.ModelPending{expected, callable}: Nat.is_eq(expected, ticket)
    case D.ReasoningPending{expected, revision}: Nat.is_eq(expected, ticket)
    case D.SummaryPending{expected, resume}: Nat.is_eq(expected, ticket)
    case D.HookPending{expected, reference, call, pending, remaining}: Nat.is_eq(expected, ticket)
    case _: False{}

def operation_ticket(operations: +List<D.Operation()>, +ticket: Nat) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{+operation, rest}:
      Nat.is_eq(Ops.ticket(operation), ticket) || Nat.is_eq(Ops.callback(operation), ticket) || operation_ticket(rest, ticket)

def operation_call(operations: +List<D.Operation()>, +id: String) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{operation, rest}: String.eq(T.call_id(Ops.call(operation)), id) || operation_call(rest, id)

def original_call(history: D.History, +call: D.Call, +budget: Nat) -> Bool:
  match history:
    case D.EmptyHistory{}: False{}
    case D.HistoryNode{previous, D.FunctionCall{original}}:
      Same.call(budget, original, call) || original_call(previous, call, budget)
    case D.HistoryNode{previous, other}: original_call(previous, call, budget)

# Announcements are historical snapshots. A pending review may later be running
# or processing a result without rewriting the already-published tool output.

def announced_value(+value: J.Json, +operation: D.Operation(), +policy: D.ApprovalPolicy, +budget: Nat) -> Bool:
  Same.json(budget, value, Ops.running(Ops.with_stage(D.Executing{}, operation))) ||
    (Bool.not(Workspace.full_access(policy)) && Approvals.requested(T.call_arguments(Ops.call(operation))) &&
      (Same.json(budget, value, Ops.running(Ops.with_stage(D.ApprovalPending{Approvals.reviewer(policy)}, operation))) ||
        Same.json(budget, value, Ops.running(Ops.with_stage(D.ApprovalGranted{Approvals.reviewer(policy)}, operation)))))

def running_output(history: D.History, +operation: D.Operation(), +policy: D.ApprovalPolicy, +budget: Nat) -> Bool:
  match history:
    case D.EmptyHistory{}: False{}
    case D.HistoryNode{previous, D.FunctionOutput{id, value, error}}:
      (String.eq(id, T.call_id(Ops.call(operation))) && Bool.not(error) && announced_value(value, operation, policy, budget)) ||
        running_output(previous, operation, policy, budget)
    case D.HistoryNode{previous, other}: running_output(previous, operation, policy, budget)

def operation_history(announced: Bool, operation: D.Operation(), history: D.History, policy: D.ApprovalPolicy, budget: Nat) -> Bool:
  match announced:
    case False{}: open_call(Ops.call(operation), history)
    case True{}: running_output(history, operation, policy, budget)

def phase_has_call(phase: D.Phase, id: String) -> Bool:
  match phase:
    case D.Ready{attempts}: has_attempt(attempts, id)
    case D.HookPending{ticket, reference, call, pending, remaining}: has_attempt(D.CheckedAttempt{call, reference <> pending} <> remaining, id)
    case _: False{}

def review_right(+call: D.Call, reviewer: D.ApprovalReviewer, contract: D.Contract) -> Bool:
  String.eq(T.call_name(call), "bash") && Approvals.requested(T.call_arguments(call)) && Approvals.valid_request(T.call_arguments(call)) &&
    Approvals.bound(Workspace.approval(D.contract_context(contract)), reviewer)

def result_right(stage: D.OperationStage, +operation: D.Operation(), rest: +List<D.Operation()>, phase: D.Phase,
  history: D.History, owner: Nat, contract: D.Contract, next_ticket: Nat, budget: Nat) -> Bool:
  match stage:
    case D.Executing{}: True{}
    case D.ApprovalPending{reviewer}: review_right(Ops.call(operation), reviewer, contract)
    case D.ApprovalGranted{+reviewer}:
      review_right(Ops.call(operation), reviewer, contract) &&
        Approvals.grant_corresponds(history, owner, Ops.ticket(operation), Ops.call(operation), reviewer, budget)
    case D.ElevatedExecuting{+ticket, +reviewer}:
      Nat.is_lt(Ops.ticket(operation), ticket) && Nat.is_lt(ticket, next_ticket) &&
        Bool.not(ticket_is(phase, ticket)) && Bool.not(operation_ticket(rest, ticket)) &&
        review_right(Ops.call(operation), reviewer, contract) &&
        Approvals.grant_corresponds(history, owner, Ops.ticket(operation), Ops.call(operation), reviewer, budget)
    case D.ResultPending{+ticket, plugin, pending, value, error}:
      Nat.is_lt(Ops.ticket(operation), ticket) && Nat.is_lt(ticket, next_ticket) &&
        Bool.not(ticket_is(phase, ticket)) && Bool.not(operation_ticket(rest, ticket)) &&
        Hooks.result_corresponds(history, owner, Ops.ticket(operation), Ops.call(operation), value, error,
          plugin <> pending, contract, budget)

def operation_rights(operations: +List<D.Operation()>, +phase: D.Phase, +history: D.History,
  +owner: Nat, +contract: D.Contract, +next_ticket: Nat, +budget: Nat) -> Bool:
  match operations:
    case Nil{}: True{}
    case Con{+operation, +rest}:
      Nat.is_lt(Ops.ticket(operation), next_ticket) && Bool.not(ticket_is(phase, Ops.ticket(operation))) &&
        Bool.not(operation_ticket(rest, Ops.ticket(operation))) && Bool.not(operation_call(rest, T.call_id(Ops.call(operation)))) &&
        Bool.not(phase_has_call(phase, T.call_id(Ops.call(operation)))) &&
        Hooks.corresponds(history, owner, Ops.call(operation), Nil{}, contract, budget) &&
        result_right(Ops.stage(operation), operation, rest, phase, history, owner, contract, next_ticket, budget) &&
        Bool.not(missing_tool(T.find_tool(T.task_tools(contract), T.call_name(Ops.call(operation))))) &&
        operation_history(Ops.announced(operation), operation, history, Workspace.approval(D.contract_context(contract)), budget) &&
        operation_rights(rest, phase, history, owner, contract, next_ticket, budget)

def checked_attempts(attempts: +List<D.Attempt>, +history: D.History, +owner: Nat, +contract: D.Contract, +budget: Nat) -> Bool:
  match attempts:
    case Nil{}: True{}
    case Con{D.CheckedAttempt{call, pending}, rest}:
      Hooks.corresponds(history, owner, call, pending, contract, budget) && checked_attempts(rest, history, owner, contract, budget)
    case Con{other, rest}: checked_attempts(rest, history, owner, contract, budget)

def checked_phase(phase: D.Phase, +history: D.History, +owner: Nat, +contract: D.Contract, +budget: Nat) -> Bool:
  match phase:
    case D.Ready{attempts}: checked_attempts(attempts, history, owner, contract, budget)
    case D.ModelPending{ticket, callable}:
      ReasoningContext.valid_sample(D.model_reasoning(T.task_model(contract)), owner, history)
    case D.ReasoningPending{ticket, revision}: Reasoning.automatic(D.model_reasoning(T.task_model(contract)))
    case D.HookPending{ticket, reference, +call, pending, remaining}:
      Bool.not(missing_tool(T.find_tool(T.task_tools(contract), T.call_name(call)))) &&
        Hooks.corresponds(history, owner, call, reference <> pending, contract, budget) && checked_attempts(remaining, history, owner, contract, budget)
    case _: True{}

def results_only(operations: +List<D.Operation()>) -> Bool:
  match operations:
    case Nil{}: True{}
    case Con{operation, rest}: Bool.not(Ops.executing(Ops.stage(operation))) && results_only(rest)

def operation_status(status: D.Status, operations: +List<D.Operation()>) -> Bool:
  match status:
    case D.Archived{}: results_only(operations)
    case _: True{}

def has_ticket(tasks: +List<D.Task>, +ticket: Nat) -> Bool:
  match tasks:
    case Nil{}: False{}
    case Con{+task, rest}:
      ticket_is(D.task_phase(task), ticket) || operation_ticket(D.task_operations(task), ticket) || has_ticket(rest, ticket)

def distinct_ticket(phase: D.Phase, tasks: +List<D.Task>) -> Bool:
  match phase:
    case D.ModelPending{ticket, callable}: Bool.not(has_ticket(tasks, ticket))
    case D.ReasoningPending{ticket, revision}: Bool.not(has_ticket(tasks, ticket))
    case D.SummaryPending{ticket, resume}: Bool.not(has_ticket(tasks, ticket))
    case D.HookPending{ticket, reference, call, pending, remaining}: Bool.not(has_ticket(tasks, ticket))
    case _: True{}

def distinct_operations(operations: +List<D.Operation()>, +tasks: +List<D.Task>) -> Bool:
  match operations:
    case Nil{}: True{}
    case Con{+operation, rest}:
      Bool.not(has_ticket(tasks, Ops.ticket(operation))) && Bool.not(has_ticket(tasks, Ops.callback(operation))) && distinct_operations(rest, tasks)

def task(task: D.Task, expected_id: Nat, +all: +List<D.Task>, +next_ticket: Nat, +budget: Nat) -> Bool:
  D.Task{+id, ancestors, +frozen, +status, +history, queued, +pending, +operations, notified} = task
  Nat.is_eq(id, expected_id) && contract(frozen) &&
    lineage(ancestors, id, frozen, all, budget) &&
    Nat.is_le(T.descendant_count(all, id), T.contract_limit(frozen)) &&
    phase(status, pending, history, T.task_tools(frozen), next_ticket) &&
    checked_phase(pending, history, id, frozen, budget) &&
    operation_status(status, operations) && Nat.is_le(List.length(&2, D.Operation(), operations), D.operation_limit()) &&
    operation_rights(operations, pending, history, id, frozen, next_ticket, budget)

def tasks(remaining: +List<D.Task>, +expected_id: Nat, +all: +List<D.Task>, +next_task: Nat, +next_ticket: Nat, +budget: Nat) -> Bool:
  match remaining:
    case Nil{}: Nat.is_eq(expected_id, next_task)
    case Con{+entry, +rest}:
      task(entry, expected_id, all, next_ticket, budget) && distinct_ticket(D.task_phase(entry), rest) &&
        distinct_operations(D.task_operations(entry), rest) &&
        tasks(rest, 1n+expected_id, all, next_task, next_ticket, budget)

# Canonical identities imply uniqueness. Each parent is older, exists, and has
# exactly the recorded ancestor tail and contract. Quotas count archived tasks.
# Every outstanding ticket is fresh within the allocation bound and is unique.

def feature_tickets(tickets: +List<Nat>, +tasks: +List<D.Task>) -> Bool:
  match tickets:
    case Nil{}: True{}
    case Con{ticket, rest}: Bool.not(has_ticket(tasks, ticket)) && feature_tickets(rest, tasks)

def world_limits(world: M.World(), limits_value: D.ExecutionLimits) -> Bool:
  match world limits_value:
    case C.Frame{+task_state, +board} D.ExecutionLimits{+steps, +budget, +bytes}:
      +entries = D.state_tasks(task_state)
      +next_task = D.state_next_task(task_state)
      +next_ticket = D.state_next_ticket(task_state)
      +settings = D.state_environment(task_state)
      +projects = D.state_projects(task_state)
      FeatureState.valid(C.Frame{task_state, board}) &&
        Projects.valid(projects) && Projects.tasks_bound(entries, projects) && environment(settings) && Nat.is_le(1n, steps) && Nat.is_le(1n, budget) &&
        Nat.is_lt(0n, U32.to_nat(bytes)) && feature_tickets(FeatureState.pending_tickets(board), entries) && tasks(entries, 0n, entries, next_task, next_ticket, budget)

def world(+world: M.World()) -> Bool:
  world_limits(world, D.state_limits(C.local(D.State, F.State(), world)))

def archived(status: D.Status) -> Bool:
  match status:
    case D.Archived{}: True{}
    case _: False{}

def result_call(operations: +List<D.Operation()>, +id: String) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{+operation, rest}:
      (Bool.not(Ops.executing(Ops.stage(operation))) && String.eq(T.call_id(Ops.call(operation)), id)) || result_call(rest, id)

def result_owner(found: Maybe<&2, D.Operation()>) -> Bool:
  match found:
    case None{}: False{}
    case Some{operation}: Bool.not(Ops.executing(Ops.stage(operation)))

def archived_message(message: D.Message, owner: Nat, +operations: +List<D.Operation()>) -> Bool:
  match message:
    case D.AfterRecord{task_id, operation, plugin, outcome}:
      Nat.is_eq(task_id, owner) && result_owner(Ops.find(operations, operation))
    case D.FunctionOutput{id, value, error}: result_call(operations, id)
    case D.OperationResult{operation, id, tool, value, error}:
      result_owner(Ops.find(operations, operation)) && result_call(operations, id)
    case _: False{}

def archived_suffix(count: Nat, history: D.History, +owner: Nat, +operations: +List<D.Operation()>) -> Bool:
  match count history:
    case 0n _: True{}
    case 1n+rest D.HistoryNode{previous, message}:
      archived_message(message, owner, operations) && archived_suffix(rest, previous, owner, operations)
    case _ _: False{}

# Existing task identities, contracts and ancestry cannot be rewritten or
# deleted. History only grows, and archival also seals history and queued input.

def archive_retained(status: D.Status, +previous: D.Task, +candidate: D.Task, +budget: Nat) -> Bool:
  match status:
    case D.Archived{}:
      archived(D.task_status(candidate)) &&
        archived_suffix(Nat.sub(D.history_length(D.task_history(candidate)), D.history_length(D.task_history(previous))),
          D.task_history(candidate), D.task_id(previous), D.task_operations(previous)) &&
        Same.strings(D.task_queue(previous), D.task_queue(candidate))
    case _: True{}

# Archival seals new work. A self-archive invocation may still own its result
# callback: only that already-owned receipt suffix may be appended afterwards.

def retained(previous: +List<D.Task>, candidate: +List<D.Task>, +budget: Nat) -> Bool:
  match previous candidate:
    case Nil{} _: True{}
    case Con{+before, rest_before} Con{+after, rest_after}:
      Nat.is_eq(D.task_id(before), D.task_id(after)) &&
        Same.naturals(D.task_lineage(before), D.task_lineage(after)) &&
        Same.contract(budget, D.task_contract(before), D.task_contract(after)) &&
        Same.history_extends(budget, D.task_history(before), D.task_history(after)) &&
        archive_retained(D.task_status(before), before, after, budget) && retained(rest_before, rest_after, budget)
    case _ _: False{}

def change_limits(previous: M.World(), candidate: M.World(), limits_value1: D.ExecutionLimits, limits_value2: D.ExecutionLimits) -> Bool:
  match previous candidate limits_value1 limits_value2:
    case C.Frame{+task_state, +board_before} C.Frame{+task_state_2, +board_after} D.ExecutionLimits{steps_after, budget_after, bytes_after} D.ExecutionLimits{steps_before, +budget_before, bytes_before}:
      after = D.state_tasks(task_state_2)
      id_after = D.state_next_task(task_state_2)
      ticket_after = D.state_next_ticket(task_state_2)
      projects_after = D.state_projects(task_state_2)
      before = D.state_tasks(task_state)
      id_before = D.state_next_task(task_state)
      ticket_before = D.state_next_ticket(task_state)
      projects_before = D.state_projects(task_state)
      FeatureState.evolution(board_before, board_after) && Nat.is_le(Projects.next_id(projects_before), Projects.next_id(projects_after)) &&
        Nat.is_le(id_before, id_after) && Nat.is_le(ticket_before, ticket_after) &&
        Nat.is_eq(steps_before, steps_after) && Nat.is_eq(budget_before, budget_after) &&
        Nat.is_eq(U32.to_nat(bytes_before), U32.to_nat(bytes_after)) && retained(before, after, budget_before)

def change(+previous: M.World(), +candidate: M.World()) -> Bool:
  change_limits(previous, candidate, D.state_limits(C.local(D.State, F.State(), candidate)), D.state_limits(C.local(D.State, F.State(), previous)))

def found_archived(found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: archived(D.task_status(task))

def cancellation_authorized(found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case Some{D.Task{id, lineage, contract, D.Stopped{}, history, queued, D.Idle{}, operations, notified}}: True{}
    case Some{D.Task{id, lineage, contract, D.Archived{}, history, queued, D.Idle{}, operations, notified}}: True{}
    case _: False{}

def retired_ticket(found: Maybe<&2, D.Task>, +ticket: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+task}:
      Bool.not(ticket_is(D.task_phase(task), ticket)) && Bool.not(operation_ticket(D.task_operations(task), ticket))

def explicitly_cancelled(effects: +List<M.Effect()>, +id: Nat, +ticket: Nat) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{Effects.CancelTask{target}, rest}: Nat.is_eq(target, id) || explicitly_cancelled(rest, id, ticket)
    case Con{Effects.CancelTicket{target, expected}, rest}:
      (Nat.is_eq(target, id) && Nat.is_eq(expected, ticket)) || explicitly_cancelled(rest, id, ticket)
    case Con{other, rest}: explicitly_cancelled(rest, id, ticket)

def keep_effect(cancelled: Bool, effect: M.Effect(), rest: +List<M.Effect()>) -> +List<M.Effect()>:
  match cancelled:
    case True{}: rest
    case False{}: effect <> rest

# Several internal steps share one commit. An archive later in that decision
# withdraws an earlier, still-unexecuted intent; cancelling it after dispatch
# would unnecessarily cross the external-effect boundary.

def after_ticket(found: Maybe<&2, D.Operation()>, ticket: Nat) -> Bool:
  match found:
    case Some{(id, D.OperationBody{call, announced, D.ResultPending{expected, plugin, pending, value, error}})}: Nat.is_eq(ticket, expected)
    case _: False{}

def after_pending(found: Maybe<&2, D.Task>, operation: Nat, ticket: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: after_ticket(Ops.find(D.task_operations(task), operation), ticket)

def retained_effects(effects: +List<M.Effect()>, +cancellations: +List<M.Effect()>, +tasks: +List<D.Task>) -> +List<M.Effect()>:
  match effects:
    case Nil{}: Nil{}
    case Con{Effects.RequestModel{+id, +ticket, model, history, tools, callable, context}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        Effects.RequestModel{id, ticket, model, history, tools, callable, context}, retained_effects(rest, cancellations, tasks))
    case Con{Effects.RequestReasoning{+id, +ticket, model, history}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        Effects.RequestReasoning{id, ticket, model, history}, retained_effects(rest, cancellations, tasks))
    case Con{Effects.RequestSummary{+id, +ticket, model, history, context}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        Effects.RequestSummary{id, ticket, model, history, context}, retained_effects(rest, cancellations, tasks))
    case Con{Effects.ExecuteTool{+id, +ticket, tool, call, context, access}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        Effects.ExecuteTool{id, ticket, tool, call, context, access}, retained_effects(rest, cancellations, tasks))
    case Con{Effects.RequestApproval{+id, +ticket, reviewer, call, context, history}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        Effects.RequestApproval{id, ticket, reviewer, call, context, history}, retained_effects(rest, cancellations, tasks))
    case Con{Effects.CheckTool{+id, +ticket, reference, tool, call}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        Effects.CheckTool{id, ticket, reference, tool, call}, retained_effects(rest, cancellations, tasks))
    case Con{Effects.CheckResult{+id, +ticket, +operation, plugin, call, value, error}, rest}:
      keep_effect(Bool.not(after_pending(T.find(tasks, id), operation, ticket)),
        Effects.CheckResult{id, ticket, operation, plugin, call, value, error}, retained_effects(rest, cancellations, tasks))
    case Con{other, rest}: other <> retained_effects(rest, cancellations, tasks)

def live_effects(+effects: +List<M.Effect()>, tasks: +List<D.Task>) -> +List<M.Effect()>:
  retained_effects(effects, effects, tasks)

def model_effect(found: Maybe<&2, D.Task>, ticket: Nat, model: D.Model, sent_history: D.History,
  tools: +List<D.Tool>, callable: +List<String>, +budget: Nat) -> Bool:
  match found:
    case Some{D.Task{id, lineage, +contract, D.Active{}, +history, queued, D.ModelPending{expected, allowed}, operations, notified}}:
      Nat.is_eq(ticket, expected) && Same.model(model, T.task_model(contract)) &&
        ReasoningContext.valid_sample(D.model_reasoning(T.task_model(contract)), id, history) &&
        Same.history(budget, sent_history, D.context_history(history)) && Same.tools(budget, tools, T.task_tools(contract)) && Same.strings(callable, allowed)
    case _: False{}

def reasoning_effect(found: Maybe<&2, D.Task>, ticket: Nat, +model: D.Model, sent_history: D.History, +budget: Nat) -> Bool:
  match found:
    case Some{D.Task{id, lineage, contract, D.Active{}, +history, queued, D.ReasoningPending{expected, revision}, operations, notified}}:
      Nat.is_eq(ticket, expected) && Nat.is_eq(revision, D.history_length(history)) &&
        Reasoning.automatic(D.model_reasoning(model)) && Same.model(model, T.task_model(contract)) && Same.history(budget, sent_history, history)
    case _: False{}

def settled_calls(remaining: D.History, +whole: D.History) -> Bool:
  match remaining:
    case D.EmptyHistory{}: True{}
    case D.HistoryNode{previous, D.FunctionCall{D.Call{id, name, arguments}}}:
      has_output(whole, id) && settled_calls(previous, whole)
    case D.HistoryNode{previous, other}: settled_calls(previous, whole)

# A context cut cannot strand a tool call on the omitted side of a checkpoint.
# The same admission certificate used for all effects enforces this precondition.

def summary_effect(found: Maybe<&2, D.Task>, ticket: Nat, model: D.Model, +sent_history: D.History, +budget: Nat) -> Bool:
  match found:
    case Some{D.Task{id, lineage, contract, D.Active{}, history, queued, D.SummaryPending{expected, resume}, operations, notified}}:
      Bool.not(D.operations_pending(operations)) && Nat.is_eq(ticket, expected) && Same.model(model, T.task_model(contract)) &&
        Same.history(budget, sent_history, D.context_history(history)) && settled_calls(sent_history, sent_history)
    case _: False{}

def tool_member(tools: +List<D.Tool>, +tool: D.Tool, +budget: Nat) -> Bool:
  match tools:
    case Nil{}: False{}
    case Con{entry, rest}: Same.tool(budget, entry, tool) || tool_member(rest, tool, budget)

def runs_tools(status: D.Status) -> Bool:
  match status:
    case D.Active{}: True{}
    case D.Stopped{}: True{}
    case _: False{}

def operation_effect(found: Maybe<&2, D.Operation()>, call: D.Call, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+operation}: Ops.executing(Ops.stage(operation)) && Same.call(budget, call, Ops.call(operation))

def result_effect(found: Maybe<&2, D.Operation()>, ticket: Nat, plugin: D.PluginRef, call: D.Call, value: J.Json, error: Bool, +budget: Nat) -> Bool:
  match found:
    case Some{(operation, D.OperationBody{current_call, announced, D.ResultPending{expected, reference, pending, current_value, current_error}})}:
      Nat.is_eq(ticket, expected) && D.plugin_same(plugin, reference) && Same.call(budget, call, current_call) &&
        Same.json(budget, value, current_value) && Same.booleans(error, current_error)
    case _: False{}

def after_effect(found: Maybe<&2, D.Task>, operation: Nat, ticket: Nat, plugin: D.PluginRef, call: D.Call, value: J.Json, error: Bool, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: result_effect(Ops.find(D.task_operations(task), operation), ticket, plugin, call, value, error, budget)

def tool_effect(found: Maybe<&2, D.Task>, ticket: Nat, tool: D.Tool, call: D.Call, +budget: Nat) -> Bool:
  match found:
    case Some{D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}}:
      runs_tools(status) && operation_effect(Ops.find_callback(operations, ticket), call, budget) &&
        tool_member(T.task_tools(contract), tool, budget)
    case _: False{}

def hook_effect(found: Maybe<&2, D.Task>, ticket: Nat, plugin: D.PluginRef, +tool: D.Tool, +call: D.Call, +budget: Nat) -> Bool:
  match found:
    case Some{D.Task{id, lineage, contract, status, history, queued, D.HookPending{expected, reference, current, pending, remaining}, operations, notified}}:
      runs_tools(status) && Nat.is_eq(ticket, expected) && D.plugin_same(plugin, reference) && Same.call(budget, call, current) &&
        String.eq(D.tool_name(tool), T.call_name(call)) && tool_member(T.task_tools(contract), tool, budget)
    case _: False{}

def feature_ticket_matches(found: Maybe<&2, Nat>, ticket: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{other}: Nat.is_eq(other, ticket)

def has_effect_ticket(effects: +List<M.Effect()>, +ticket: Nat) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{Effects.RequestModel{id, other, model, history, tools, callable, context}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{Effects.RequestReasoning{id, other, model, history}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{Effects.FeatureEffect{effect}, rest}:
      feature_ticket_matches(FeatureState.effect_ticket(effect), ticket) || has_effect_ticket(rest, ticket)
    case Con{Effects.RequestSummary{id, other, model, history, context}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{Effects.RequestApproval{id, other, reviewer, call, context, history}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{Effects.ExecuteTool{id, other, tool, call, context, access}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{Effects.CheckTool{id, other, reference, tool, call}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{Effects.CheckResult{id, other, operation, reference, call, value, error}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{other, rest}: has_effect_ticket(rest, ticket)

# A dispatched effect must describe the final pending phase exactly, have a
# freshly allocated correlation ticket, and occur only once in this decision.

def context_effect(found: Maybe<&2, D.Task>, context: D.TaskContext, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: Same.json(budget, D.task_context_json(context), D.task_context_json(D.task_context(task)))

def operation_access(found: Maybe<&2, D.Operation()>, access: D.ExecutionAccess, context: D.TaskContext) -> Bool:
  match found:
    case Some{(id, D.OperationBody{call, announced, D.Executing{}})}:
      String.eq(D.access_name(access), D.access_name(Workspace.default_access(context)))
    case Some{(id, D.OperationBody{call, announced, D.ElevatedExecuting{ticket, reviewer}})}:
      String.eq(D.access_name(access), "unrestricted")
    case _: False{}

def default_access_effect(found: Maybe<&2, D.Task>, ticket: Nat, access: D.ExecutionAccess) -> Bool:
  match found:
    case None{}: False{}
    case Some{+task}: operation_access(Ops.find_callback(D.task_operations(task), ticket), access, D.task_context(task))

def review_operation(found: Maybe<&2, D.Operation()>, profile: D.Profile, call: D.Call, budget: Nat) -> Bool:
  match found:
    case Some{(id, D.OperationBody{actual_call, announced, D.ApprovalPending{D.ModelReviewer{actual_profile}}})}:
      Workspace.profile_same(profile, actual_profile) && Same.call(budget, call, actual_call)
    case _: False{}

def review_effect(found: Maybe<&2, D.Task>, ticket: Nat, profile: D.Profile, call: D.Call, history: D.History, +budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+task}:
      review_operation(Ops.find(D.task_operations(task), ticket), profile, call, budget) &&
        Same.history_extends(budget, history, D.task_history(task))

def feature_ticket_fresh(found: Maybe<&2, Nat>, rest: +List<M.Effect()>, first: Nat) -> Bool:
  match found:
    case None{}: True{}
    case Some{+ticket}: Nat.is_le(first, ticket) && Bool.not(has_effect_ticket(rest, ticket))

def effects(pending: +List<M.Effect()>, +tasks: +List<D.Task>, +first_ticket: Nat, +budget: Nat) -> Bool:
  match pending:
    case Nil{}: True{}
    case Con{Effects.NotifyPlugins{events}, rest}: effects(rest, tasks, first_ticket, budget)
    case Con{Effects.RequestModel{+id, +ticket, model, history, tools, callable, context}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        context_effect(T.find(tasks, id), context, budget) && model_effect(T.find(tasks, id), ticket, model, history, tools, callable, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.RequestReasoning{id, +ticket, model, history}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        reasoning_effect(T.find(tasks, id), ticket, model, history, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.FeatureEffect{effect}, +rest}:
      feature_ticket_fresh(FeatureState.effect_ticket(effect), rest, first_ticket) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.RequestSummary{+id, +ticket, model, history, context}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        context_effect(T.find(tasks, id), context, budget) && summary_effect(T.find(tasks, id), ticket, model, history, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.ExecuteTool{+id, +ticket, tool, call, context, access}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        context_effect(T.find(tasks, id), context, budget) && default_access_effect(T.find(tasks, id), ticket, access) &&
        tool_effect(T.find(tasks, id), ticket, tool, call, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.RequestApproval{+id, +ticket, reviewer, call, context, history}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        context_effect(T.find(tasks, id), context, budget) && review_effect(T.find(tasks, id), ticket, reviewer, call, history, budget) &&
        effects(rest, tasks, first_ticket, budget)
    case Con{Effects.CheckTool{id, +ticket, reference, tool, call}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        hook_effect(T.find(tasks, id), ticket, reference, tool, call, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.CheckResult{id, +ticket, operation, reference, call, value, error}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        after_effect(T.find(tasks, id), operation, ticket, reference, call, value, error, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.CancelTask{id}, rest}:
      cancellation_authorized(T.find(tasks, id)) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.CancelTicket{id, ticket}, rest}:
      retired_ticket(T.find(tasks, id), ticket) && effects(rest, tasks, first_ticket, budget)
    case Con{Effects.ContinueScheduling{}, rest}: effects(rest, tasks, first_ticket, budget)

def profiles(environment: D.Environment) -> +List<D.Profile>:
  D.Environment{catalog, profiles, forks, descendants, project, plugins} = environment
  profiles

def feature_effects(effects: +List<M.Effect()>, +state: F.State(), +profiles: +List<D.Profile>) -> Bool:
  match effects:
    case Nil{}: True{}
    case Con{Effects.FeatureEffect{effect}, rest}:
      FeatureState.effect_valid(effect, state, profiles) && feature_effects(rest, state, profiles)
    case Con{other, rest}: feature_effects(rest, state, profiles)

def decision_limits(previous: M.World(), candidate: M.Decision(), limits_value: D.ExecutionLimits) -> Bool:
  match previous candidate limits_value:
    case C.Frame{+task_state, +board_before} C.Decision{C.Frame{+task_state_2, +board_after}, reply, +pending} D.ExecutionLimits{+steps, +budget, +bytes}:
      +after = D.state_tasks(task_state_2)
      +env_after = D.state_environment(task_state_2)
      +ticket_before = D.state_next_ticket(task_state)
      change(C.Frame{task_state, board_before}, C.Frame{task_state_2, board_after}) &&
        effects(pending, after, ticket_before, budget) && feature_effects(pending, board_after, profiles(env_after))

def decision(+previous: M.World(), candidate: M.Decision()) -> Bool:
  decision_limits(previous, candidate, D.state_limits(C.local(D.State, F.State(), previous)))
