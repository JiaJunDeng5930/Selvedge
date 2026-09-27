import Base
import ./MODEL.bend as M
import ./bendlib/tasks.bend as T
import ./bendlib/operations.bend as Ops
import ./bendlib/equality.bend as Same
import ./bendlib/json.bend as J
import ./HOOKS.bend as Hooks
import ./WORKSPACE.bend as Workspace
import ./PROJECTS.bend as Projects

# A world is an append-only registry of tasks, whose ancestry is a forest.
# These predicates are executed by PROGRAM's admission boundary and named by
# LAWS. They are requirements about actual values, not a second task simulator.

def missing_tool(found: Maybe<&2, M.Tool>) -> Bool:
  match found:
    case None{}: True{}
    case Some{tool}: False{}

def unique_tools(tools: +List<M.Tool>) -> Bool:
  match tools:
    case Nil{}: True{}
    case Con{+tool, +rest}:
      M.nonempty(M.tool_name(tool)) && missing_tool(T.find_tool(rest, M.tool_name(tool))) && unique_tools(rest)

def missing_profile(found: Maybe<&2, M.Profile>) -> Bool:
  match found:
    case None{}: True{}
    case Some{profile}: False{}

def unique_profiles(profiles: +List<M.Profile>) -> Bool:
  match profiles:
    case Nil{}: True{}
    case Con{M.Profile{+key, provider, name}, +rest}:
      M.nonempty(key) && M.nonempty(provider) && M.nonempty(name) &&
        missing_profile(M.find_profile(rest, key)) && unique_profiles(rest)

def project_context(project: M.ProjectContext) -> Bool:
  Workspace.valid_guidance(project)

def environment(environment: M.Environment) -> Bool:
  M.Environment{+catalog, profiles, max_fork, max_descendants, project, +plugins} = environment
  Hooks.valid(plugins) && Hooks.routes(catalog, plugins) && project_context(project) && unique_tools(catalog) && unique_profiles(profiles) &&
    Nat.is_le(1n, max_fork) && Nat.is_le(1n, max_descendants)

def contract(contract: M.Contract) -> Bool:
  M.Contract{M.Model{M.Profile{key, provider, name}, reasoning, +project}, +tools, max_fork, max_descendants, +plugins, +context} = contract
  Workspace.valid_context(context) && Workspace.guidance_member(Workspace.primary(Workspace.workspace(context)), project) &&
    Hooks.valid(plugins) && Hooks.routes(tools, plugins) && project_context(project) && M.nonempty(key) && M.nonempty(provider) && M.nonempty(name) && M.nonempty(reasoning) &&
    unique_tools(tools) && Nat.is_le(1n, max_fork) && Nat.is_le(1n, max_descendants)

def lineage_parent(found: Maybe<&2, M.Task>, child: Nat, tail: +List<Nat>, contract: M.Contract, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+parent}:
      Nat.is_lt(M.task_id(parent), child) && Same.naturals(tail, M.task_lineage(parent)) &&
        Same.inherited_contract(budget, contract, M.task_contract(parent))

def lineage(lineage: +List<Nat>, child: Nat, contract: M.Contract, tasks: +List<M.Task>, budget: Nat) -> Bool:
  match lineage:
    case Nil{}: True{}
    case Con{parent, tail}: lineage_parent(T.find(tasks, parent), child, tail, contract, budget)

def has_output(history: M.History, +id: String) -> Bool:
  match history:
    case M.EmptyHistory{}: False{}
    case M.HistoryNode{previous, M.FunctionOutput{call_id, value, error}}:
      String.eq(call_id, id) || has_output(previous, id)
    case M.HistoryNode{previous, M.ForkResult{owner, call_id, branch}}:
      String.eq(call_id, id) || has_output(previous, id)
    case M.HistoryNode{previous, other}: has_output(previous, id)

def has_attempt(attempts: +List<M.Attempt>, +id: String) -> Bool:
  match attempts:
    case Nil{}: False{}
    case Con{attempt, rest}: String.eq(T.call_id(M.attempt_call(attempt)), id) || has_attempt(rest, id)

def open_call(call: M.Call, +history: M.History) -> Bool:
  +id = T.call_id(call)
  T.history_has_call(history, id) && Bool.not(has_output(history, id))

def attempts(pending: +List<M.Attempt>, +history: M.History) -> Bool:
  match pending:
    case Nil{}: True{}
    case Con{attempt, +rest}:
      +call = M.attempt_call(attempt)
      open_call(call, history) && Bool.not(has_attempt(rest, T.call_id(call))) && attempts(rest, history)

def callable(names: +List<String>, +tools: +List<M.Tool>) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{+name, +rest}:
      Bool.not(missing_tool(T.find_tool(tools, name))) && Bool.not(T.has_name(rest, name)) && callable(rest, tools)

def phase(status: M.Status, phase: M.Phase, +history: M.History, tools: +List<M.Tool>, next_ticket: Nat) -> Bool:
  match status phase:
    case M.Archived{} M.Idle{}: True{}
    case M.Archived{} _: False{}
    case _ M.Idle{}: True{}
    case _ M.CompactionReady{}: True{}
    case _ M.Ready{pending}: attempts(pending, history)
    case _ M.ModelPending{ticket, names}: Nat.is_lt(ticket, next_ticket) && callable(names, tools)
    case _ M.SummaryPending{ticket, resume}: Nat.is_lt(ticket, next_ticket)
    case _ M.HookPending{ticket, reference, call, pending, remaining}:
      Nat.is_lt(ticket, next_ticket) && attempts(M.CheckedAttempt{call, reference <> pending} <> remaining, history)

def ticket_is(phase: M.Phase, ticket: Nat) -> Bool:
  match phase:
    case M.ModelPending{expected, callable}: Nat.is_eq(expected, ticket)
    case M.SummaryPending{expected, resume}: Nat.is_eq(expected, ticket)
    case M.HookPending{expected, reference, call, pending, remaining}: Nat.is_eq(expected, ticket)
    case _: False{}

def operation_ticket(operations: +List<M.Operation()>, +ticket: Nat) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{+operation, rest}:
      Nat.is_eq(Ops.ticket(operation), ticket) || Nat.is_eq(Ops.callback(operation), ticket) || operation_ticket(rest, ticket)

def operation_call(operations: +List<M.Operation()>, +id: String) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{operation, rest}: String.eq(T.call_id(Ops.call(operation)), id) || operation_call(rest, id)

def original_call(history: M.History, +call: M.Call, +budget: Nat) -> Bool:
  match history:
    case M.EmptyHistory{}: False{}
    case M.HistoryNode{previous, M.FunctionCall{original}}:
      Same.call(budget, original, call) || original_call(previous, call, budget)
    case M.HistoryNode{previous, other}: original_call(previous, call, budget)

def running_output(history: M.History, +operation: M.Operation(), +budget: Nat) -> Bool:
  match history:
    case M.EmptyHistory{}: False{}
    case M.HistoryNode{previous, M.FunctionOutput{id, value, error}}:
      (String.eq(id, T.call_id(Ops.call(operation))) && Bool.not(error) && Same.json(budget, value, Ops.running(operation))) ||
        running_output(previous, operation, budget)
    case M.HistoryNode{previous, other}: running_output(previous, operation, budget)

def operation_history(announced: Bool, operation: M.Operation(), history: M.History, budget: Nat) -> Bool:
  match announced:
    case False{}: open_call(Ops.call(operation), history)
    case True{}: running_output(history, operation, budget)

def phase_has_call(phase: M.Phase, id: String) -> Bool:
  match phase:
    case M.Ready{attempts}: has_attempt(attempts, id)
    case M.HookPending{ticket, reference, call, pending, remaining}: has_attempt(M.CheckedAttempt{call, reference <> pending} <> remaining, id)
    case _: False{}

def result_right(stage: M.OperationStage, +operation: M.Operation(), rest: +List<M.Operation()>, phase: M.Phase,
  history: M.History, owner: Nat, contract: M.Contract, next_ticket: Nat, budget: Nat) -> Bool:
  match stage:
    case M.Executing{}: True{}
    case M.ResultPending{+ticket, plugin, pending, value, error}:
      Nat.is_lt(Ops.ticket(operation), ticket) && Nat.is_lt(ticket, next_ticket) &&
        Bool.not(ticket_is(phase, ticket)) && Bool.not(operation_ticket(rest, ticket)) &&
        Hooks.result_corresponds(history, owner, Ops.ticket(operation), Ops.call(operation), value, error,
          plugin <> pending, contract, budget)

def operation_rights(operations: +List<M.Operation()>, +phase: M.Phase, +history: M.History,
  +owner: Nat, +contract: M.Contract, +next_ticket: Nat, +budget: Nat) -> Bool:
  match operations:
    case Nil{}: True{}
    case Con{+operation, +rest}:
      Nat.is_lt(Ops.ticket(operation), next_ticket) && Bool.not(ticket_is(phase, Ops.ticket(operation))) &&
        Bool.not(operation_ticket(rest, Ops.ticket(operation))) && Bool.not(operation_call(rest, T.call_id(Ops.call(operation)))) &&
        Bool.not(phase_has_call(phase, T.call_id(Ops.call(operation)))) &&
        Hooks.corresponds(history, owner, Ops.call(operation), Nil{}, contract, budget) &&
        result_right(Ops.stage(operation), operation, rest, phase, history, owner, contract, next_ticket, budget) &&
        Bool.not(missing_tool(T.find_tool(T.task_tools(contract), T.call_name(Ops.call(operation))))) &&
        operation_history(Ops.announced(operation), operation, history, budget) &&
        operation_rights(rest, phase, history, owner, contract, next_ticket, budget)

def checked_attempts(attempts: +List<M.Attempt>, +history: M.History, +owner: Nat, +contract: M.Contract, +budget: Nat) -> Bool:
  match attempts:
    case Nil{}: True{}
    case Con{M.CheckedAttempt{call, pending}, rest}:
      Hooks.corresponds(history, owner, call, pending, contract, budget) && checked_attempts(rest, history, owner, contract, budget)
    case Con{other, rest}: checked_attempts(rest, history, owner, contract, budget)

def checked_phase(phase: M.Phase, +history: M.History, +owner: Nat, +contract: M.Contract, +budget: Nat) -> Bool:
  match phase:
    case M.Ready{attempts}: checked_attempts(attempts, history, owner, contract, budget)
    case M.HookPending{ticket, reference, +call, pending, remaining}:
      Bool.not(missing_tool(T.find_tool(T.task_tools(contract), T.call_name(call)))) &&
        Hooks.corresponds(history, owner, call, reference <> pending, contract, budget) && checked_attempts(remaining, history, owner, contract, budget)
    case _: True{}

def results_only(operations: +List<M.Operation()>) -> Bool:
  match operations:
    case Nil{}: True{}
    case Con{operation, rest}: Bool.not(Ops.executing(Ops.stage(operation))) && results_only(rest)

def operation_status(status: M.Status, operations: +List<M.Operation()>) -> Bool:
  match status:
    case M.Archived{}: results_only(operations)
    case _: True{}

def has_ticket(tasks: +List<M.Task>, +ticket: Nat) -> Bool:
  match tasks:
    case Nil{}: False{}
    case Con{+task, rest}:
      ticket_is(M.task_phase(task), ticket) || operation_ticket(M.task_operations(task), ticket) || has_ticket(rest, ticket)

def distinct_ticket(phase: M.Phase, tasks: +List<M.Task>) -> Bool:
  match phase:
    case M.ModelPending{ticket, callable}: Bool.not(has_ticket(tasks, ticket))
    case M.SummaryPending{ticket, resume}: Bool.not(has_ticket(tasks, ticket))
    case M.HookPending{ticket, reference, call, pending, remaining}: Bool.not(has_ticket(tasks, ticket))
    case _: True{}

def distinct_operations(operations: +List<M.Operation()>, +tasks: +List<M.Task>) -> Bool:
  match operations:
    case Nil{}: True{}
    case Con{+operation, rest}:
      Bool.not(has_ticket(tasks, Ops.ticket(operation))) && Bool.not(has_ticket(tasks, Ops.callback(operation))) && distinct_operations(rest, tasks)

def task(task: M.Task, expected_id: Nat, +all: +List<M.Task>, +next_ticket: Nat, +budget: Nat) -> Bool:
  M.Task{+id, ancestors, +frozen, +status, +history, queued, +pending, +operations, notified} = task
  Nat.is_eq(id, expected_id) && contract(frozen) &&
    lineage(ancestors, id, frozen, all, budget) &&
    Nat.is_le(T.descendant_count(all, id), T.contract_limit(frozen)) &&
    phase(status, pending, history, T.task_tools(frozen), next_ticket) &&
    checked_phase(pending, history, id, frozen, budget) &&
    operation_status(status, operations) && Nat.is_le(List.length(&2, M.Operation(), operations), M.operation_limit()) &&
    operation_rights(operations, pending, history, id, frozen, next_ticket, budget)

def tasks(remaining: +List<M.Task>, +expected_id: Nat, +all: +List<M.Task>, +next_task: Nat, +next_ticket: Nat, +budget: Nat) -> Bool:
  match remaining:
    case Nil{}: Nat.is_eq(expected_id, next_task)
    case Con{+entry, +rest}:
      task(entry, expected_id, all, next_ticket, budget) && distinct_ticket(M.task_phase(entry), rest) &&
        distinct_operations(M.task_operations(entry), rest) &&
        tasks(rest, 1n+expected_id, all, next_task, next_ticket, budget)

# Canonical identities imply uniqueness. Each parent is older, exists, and has
# exactly the recorded ancestor tail and contract. Quotas count archived tasks.
# Every outstanding ticket is fresh within the allocation bound and is unique.
def world(world: M.World) -> Bool:
  M.World{+entries, next_task, next_ticket, settings, M.ExecutionLimits{steps, +budget, bytes}, +projects} = world
  Projects.valid(projects) && Projects.tasks_bound(entries, projects) && environment(settings) && Nat.is_le(1n, steps) && Nat.is_le(1n, budget) &&
    Nat.is_lt(0n, U32.to_nat(bytes)) && tasks(entries, 0n, entries, next_task, next_ticket, budget)

def archived(status: M.Status) -> Bool:
  match status:
    case M.Archived{}: True{}
    case _: False{}

def result_call(operations: +List<M.Operation()>, +id: String) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{+operation, rest}:
      (Bool.not(Ops.executing(Ops.stage(operation))) && String.eq(T.call_id(Ops.call(operation)), id)) || result_call(rest, id)

def result_owner(found: Maybe<&2, M.Operation()>) -> Bool:
  match found:
    case None{}: False{}
    case Some{operation}: Bool.not(Ops.executing(Ops.stage(operation)))

def archived_message(message: M.Message, owner: Nat, +operations: +List<M.Operation()>) -> Bool:
  match message:
    case M.AfterRecord{task_id, operation, plugin, outcome}:
      Nat.is_eq(task_id, owner) && result_owner(Ops.find(operations, operation))
    case M.FunctionOutput{id, value, error}: result_call(operations, id)
    case M.OperationResult{operation, id, tool, value, error}:
      result_owner(Ops.find(operations, operation)) && result_call(operations, id)
    case _: False{}

def archived_suffix(count: Nat, history: M.History, +owner: Nat, +operations: +List<M.Operation()>) -> Bool:
  match count history:
    case 0n _: True{}
    case 1n+rest M.HistoryNode{previous, message}:
      archived_message(message, owner, operations) && archived_suffix(rest, previous, owner, operations)
    case _ _: False{}

# Existing task identities, contracts and ancestry cannot be rewritten or
# deleted. History only grows, and archival also seals history and queued input.
def archive_retained(status: M.Status, +previous: M.Task, +candidate: M.Task, +budget: Nat) -> Bool:
  match status:
    case M.Archived{}:
      archived(M.task_status(candidate)) &&
        archived_suffix(Nat.sub(M.history_length(M.task_history(candidate)), M.history_length(M.task_history(previous))),
          M.task_history(candidate), M.task_id(previous), M.task_operations(previous)) &&
        Same.strings(M.task_queue(previous), M.task_queue(candidate))
    case _: True{}

# Archival seals new work. A self-archive invocation may still own its result
# callback: only that already-owned receipt suffix may be appended afterwards.
def retained(previous: +List<M.Task>, candidate: +List<M.Task>, +budget: Nat) -> Bool:
  match previous candidate:
    case Nil{} _: True{}
    case Con{+before, rest_before} Con{+after, rest_after}:
      Nat.is_eq(M.task_id(before), M.task_id(after)) &&
        Same.naturals(M.task_lineage(before), M.task_lineage(after)) &&
        Same.contract(budget, M.task_contract(before), M.task_contract(after)) &&
        Same.history_extends(budget, M.task_history(before), M.task_history(after)) &&
        archive_retained(M.task_status(before), before, after, budget) && retained(rest_before, rest_after, budget)
    case _ _: False{}

def change(previous: M.World, candidate: M.World) -> Bool:
  match previous candidate:
    case M.World{before, id_before, ticket_before, env_before, M.ExecutionLimits{steps_before, +budget_before, bytes_before}, projects_before}
         M.World{after, id_after, ticket_after, env_after, M.ExecutionLimits{steps_after, budget_after, bytes_after}, projects_after}:
      Nat.is_le(Projects.next_id(projects_before), Projects.next_id(projects_after)) &&
        Nat.is_le(id_before, id_after) && Nat.is_le(ticket_before, ticket_after) &&
        Nat.is_eq(steps_before, steps_after) && Nat.is_eq(budget_before, budget_after) &&
        Nat.is_eq(U32.to_nat(bytes_before), U32.to_nat(bytes_after)) && retained(before, after, budget_before)

def found_archived(found: Maybe<&2, M.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: archived(M.task_status(task))

def cancellation_authorized(found: Maybe<&2, M.Task>) -> Bool:
  match found:
    case Some{M.Task{id, lineage, contract, M.Stopped{}, history, queued, M.Idle{}, operations, notified}}: True{}
    case Some{M.Task{id, lineage, contract, M.Archived{}, history, queued, M.Idle{}, operations, notified}}: True{}
    case _: False{}

def retired_ticket(found: Maybe<&2, M.Task>, +ticket: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+task}:
      Bool.not(ticket_is(M.task_phase(task), ticket)) && Bool.not(operation_ticket(M.task_operations(task), ticket))

def explicitly_cancelled(effects: +List<M.Effect>, +id: Nat, +ticket: Nat) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{M.CancelTask{target}, rest}: Nat.is_eq(target, id) || explicitly_cancelled(rest, id, ticket)
    case Con{M.CancelTicket{target, expected}, rest}:
      (Nat.is_eq(target, id) && Nat.is_eq(expected, ticket)) || explicitly_cancelled(rest, id, ticket)
    case Con{other, rest}: explicitly_cancelled(rest, id, ticket)

def keep_effect(cancelled: Bool, effect: M.Effect, rest: +List<M.Effect>) -> +List<M.Effect>:
  match cancelled:
    case True{}: rest
    case False{}: effect <> rest

# Several internal steps share one commit. An archive later in that decision
# withdraws an earlier, still-unexecuted intent; cancelling it after dispatch
# would unnecessarily cross the external-effect boundary.
def after_ticket(found: Maybe<&2, M.Operation()>, ticket: Nat) -> Bool:
  match found:
    case Some{(id, M.OperationBody{call, announced, M.ResultPending{expected, plugin, pending, value, error}})}: Nat.is_eq(ticket, expected)
    case _: False{}

def after_pending(found: Maybe<&2, M.Task>, operation: Nat, ticket: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: after_ticket(Ops.find(M.task_operations(task), operation), ticket)

def retained_effects(effects: +List<M.Effect>, +cancellations: +List<M.Effect>, +tasks: +List<M.Task>) -> +List<M.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{M.RequestModel{+id, +ticket, model, history, tools, callable, context}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        M.RequestModel{id, ticket, model, history, tools, callable, context}, retained_effects(rest, cancellations, tasks))
    case Con{M.RequestSummary{+id, +ticket, model, history, context}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        M.RequestSummary{id, ticket, model, history, context}, retained_effects(rest, cancellations, tasks))
    case Con{M.ExecuteTool{+id, +ticket, tool, call, context, access}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        M.ExecuteTool{id, ticket, tool, call, context, access}, retained_effects(rest, cancellations, tasks))
    case Con{M.CheckTool{+id, +ticket, reference, tool, call}, rest}:
      keep_effect(found_archived(T.find(tasks, id)) || explicitly_cancelled(cancellations, id, ticket),
        M.CheckTool{id, ticket, reference, tool, call}, retained_effects(rest, cancellations, tasks))
    case Con{M.CheckResult{+id, +ticket, +operation, plugin, call, value, error}, rest}:
      keep_effect(Bool.not(after_pending(T.find(tasks, id), operation, ticket)),
        M.CheckResult{id, ticket, operation, plugin, call, value, error}, retained_effects(rest, cancellations, tasks))
    case Con{other, rest}: other <> retained_effects(rest, cancellations, tasks)

def live_effects(+effects: +List<M.Effect>, tasks: +List<M.Task>) -> +List<M.Effect>:
  retained_effects(effects, effects, tasks)

def model_effect(found: Maybe<&2, M.Task>, ticket: Nat, model: M.Model, sent_history: M.History,
  tools: +List<M.Tool>, callable: +List<String>, +budget: Nat) -> Bool:
  match found:
    case Some{M.Task{id, lineage, +contract, M.Active{}, history, queued, M.ModelPending{expected, allowed}, operations, notified}}:
      Nat.is_eq(ticket, expected) && Same.model(model, T.task_model(contract)) &&
        Same.history(budget, sent_history, M.context_history(history)) && Same.tools(budget, tools, T.task_tools(contract)) && Same.strings(callable, allowed)
    case _: False{}

def settled_calls(remaining: M.History, +whole: M.History) -> Bool:
  match remaining:
    case M.EmptyHistory{}: True{}
    case M.HistoryNode{previous, M.FunctionCall{M.Call{id, name, arguments}}}:
      has_output(whole, id) && settled_calls(previous, whole)
    case M.HistoryNode{previous, other}: settled_calls(previous, whole)

# A context cut cannot strand a tool call on the omitted side of a checkpoint.
# The same admission certificate used for all effects enforces this precondition.
def summary_effect(found: Maybe<&2, M.Task>, ticket: Nat, model: M.Model, +sent_history: M.History, +budget: Nat) -> Bool:
  match found:
    case Some{M.Task{id, lineage, contract, M.Active{}, history, queued, M.SummaryPending{expected, resume}, operations, notified}}:
      Bool.not(M.operations_pending(operations)) && Nat.is_eq(ticket, expected) && Same.model(model, T.task_model(contract)) &&
        Same.history(budget, sent_history, M.context_history(history)) && settled_calls(sent_history, sent_history)
    case _: False{}

def tool_member(tools: +List<M.Tool>, +tool: M.Tool, +budget: Nat) -> Bool:
  match tools:
    case Nil{}: False{}
    case Con{entry, rest}: Same.tool(budget, entry, tool) || tool_member(rest, tool, budget)

def runs_tools(status: M.Status) -> Bool:
  match status:
    case M.Active{}: True{}
    case M.Stopped{}: True{}
    case _: False{}

def operation_effect(found: Maybe<&2, M.Operation()>, call: M.Call, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+operation}: Ops.executing(Ops.stage(operation)) && Same.call(budget, call, Ops.call(operation))

def result_effect(found: Maybe<&2, M.Operation()>, ticket: Nat, plugin: M.PluginRef, call: M.Call, value: J.Json, error: Bool, +budget: Nat) -> Bool:
  match found:
    case Some{(operation, M.OperationBody{current_call, announced, M.ResultPending{expected, reference, pending, current_value, current_error}})}:
      Nat.is_eq(ticket, expected) && M.plugin_same(plugin, reference) && Same.call(budget, call, current_call) &&
        Same.json(budget, value, current_value) && Same.booleans(error, current_error)
    case _: False{}

def after_effect(found: Maybe<&2, M.Task>, operation: Nat, ticket: Nat, plugin: M.PluginRef, call: M.Call, value: J.Json, error: Bool, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: result_effect(Ops.find(M.task_operations(task), operation), ticket, plugin, call, value, error, budget)

def tool_effect(found: Maybe<&2, M.Task>, ticket: Nat, tool: M.Tool, call: M.Call, +budget: Nat) -> Bool:
  match found:
    case Some{M.Task{id, lineage, contract, status, history, queued, phase, operations, notified}}:
      runs_tools(status) && operation_effect(Ops.find(operations, ticket), call, budget) &&
        tool_member(T.task_tools(contract), tool, budget)
    case _: False{}

def hook_effect(found: Maybe<&2, M.Task>, ticket: Nat, plugin: M.PluginRef, +tool: M.Tool, +call: M.Call, +budget: Nat) -> Bool:
  match found:
    case Some{M.Task{id, lineage, contract, status, history, queued, M.HookPending{expected, reference, current, pending, remaining}, operations, notified}}:
      runs_tools(status) && Nat.is_eq(ticket, expected) && M.plugin_same(plugin, reference) && Same.call(budget, call, current) &&
        String.eq(M.tool_name(tool), T.call_name(call)) && tool_member(T.task_tools(contract), tool, budget)
    case _: False{}

def has_effect_ticket(effects: +List<M.Effect>, +ticket: Nat) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{M.RequestModel{id, other, model, history, tools, callable, context}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{M.RequestSummary{id, other, model, history, context}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{M.ExecuteTool{id, other, tool, call, context, access}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{M.CheckTool{id, other, reference, tool, call}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{M.CheckResult{id, other, operation, reference, call, value, error}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{other, rest}: has_effect_ticket(rest, ticket)

# A dispatched effect must describe the final pending phase exactly, have a
# freshly allocated correlation ticket, and occur only once in this decision.
def context_effect(found: Maybe<&2, M.Task>, context: M.TaskContext, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: Same.json(budget, M.task_context_json(context), M.task_context_json(M.task_context(task)))

def default_access_effect(found: Maybe<&2, M.Task>, access: M.ExecutionAccess) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: String.eq(M.access_name(access), M.access_name(Workspace.default_access(M.task_context(task))))

def effects(pending: +List<M.Effect>, +tasks: +List<M.Task>, +first_ticket: Nat, +budget: Nat) -> Bool:
  match pending:
    case Nil{}: True{}
    case Con{M.NotifyPlugins{events}, rest}: effects(rest, tasks, first_ticket, budget)
    case Con{M.RequestModel{+id, +ticket, model, history, tools, callable, context}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        context_effect(T.find(tasks, id), context, budget) && model_effect(T.find(tasks, id), ticket, model, history, tools, callable, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.RequestSummary{+id, +ticket, model, history, context}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        context_effect(T.find(tasks, id), context, budget) && summary_effect(T.find(tasks, id), ticket, model, history, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.ExecuteTool{+id, +ticket, tool, call, context, access}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        context_effect(T.find(tasks, id), context, budget) && default_access_effect(T.find(tasks, id), access) &&
        tool_effect(T.find(tasks, id), ticket, tool, call, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.CheckTool{id, +ticket, reference, tool, call}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        hook_effect(T.find(tasks, id), ticket, reference, tool, call, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.CheckResult{id, +ticket, operation, reference, call, value, error}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        after_effect(T.find(tasks, id), operation, ticket, reference, call, value, error, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.CancelTask{id}, rest}:
      cancellation_authorized(T.find(tasks, id)) && effects(rest, tasks, first_ticket, budget)
    case Con{M.CancelTicket{id, ticket}, rest}:
      retired_ticket(T.find(tasks, id), ticket) && effects(rest, tasks, first_ticket, budget)
    case Con{M.ContinueScheduling{}, rest}: effects(rest, tasks, first_ticket, budget)

def decision(previous: M.World, candidate: M.Decision) -> Bool:
  match previous candidate:
    case M.World{before, id_before, +ticket_before, env_before, M.ExecutionLimits{+steps, +budget, +bytes}, projects_before}
         M.Decision{M.World{+after, +id_after, +ticket_after, +env_after, +limits_after, projects_after}, reply, pending}:
      change(M.World{before, id_before, ticket_before, env_before, M.ExecutionLimits{steps, budget, bytes}, projects_before}, M.World{after, id_after, ticket_after, env_after, limits_after, projects_after}) &&
        effects(pending, after, ticket_before, budget)
