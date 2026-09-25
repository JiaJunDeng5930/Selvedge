import Base
import ./MODEL.bend as M
import ./bendlib/tasks.bend as T
import ./bendlib/equality.bend as Same
import ./bendlib/json.bend as J

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
  match project:
    case M.NoProject{}: True{}
    case M.ProjectContext{+workspace, +revision, +instructions}:
      M.nonempty(workspace) && Nat.is_le(J.utf8_length(workspace), 4096n) &&
        Nat.is_le(J.utf8_length(instructions), M.project_limit()) &&
        ((String.eq(revision, "absent") && String.eq(instructions, "")) || Nat.is_eq(J.utf8_length(revision), 64n))

def environment(environment: M.Environment) -> Bool:
  M.Environment{catalog, profiles, max_fork, max_descendants, project} = environment
  project_context(project) && unique_tools(catalog) && unique_profiles(profiles) &&
    Nat.is_le(1n, max_fork) && Nat.is_le(1n, max_descendants)

def contract(contract: M.Contract) -> Bool:
  M.Contract{M.Model{M.Profile{key, provider, name}, reasoning, project}, tools, max_fork, max_descendants} = contract
  project_context(project) && M.nonempty(key) && M.nonempty(provider) && M.nonempty(name) && M.nonempty(reasoning) &&
    unique_tools(tools) && Nat.is_le(1n, max_fork) && Nat.is_le(1n, max_descendants)

def lineage_parent(found: Maybe<&2, M.Task>, child: Nat, tail: +List<Nat>, contract: M.Contract, budget: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+parent}:
      Nat.is_lt(M.task_id(parent), child) && Same.naturals(tail, M.task_lineage(parent)) &&
        Same.contract(budget, contract, M.task_contract(parent))

def lineage(lineage: +List<Nat>, child: Nat, contract: M.Contract, tasks: +List<M.Task>, budget: Nat) -> Bool:
  match lineage:
    case Nil{}: True{}
    case Con{parent, tail}: lineage_parent(T.find(tasks, parent), child, tail, contract, budget)

def has_output(history: M.History, +id: String) -> Bool:
  match history:
    case M.EmptyHistory{}: False{}
    case M.HistoryNode{previous, M.FunctionOutput{call_id, value, error}}:
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
    case _ M.ToolPending{ticket, +call, +remaining}:
      Nat.is_lt(ticket, next_ticket) && open_call(call, history) &&
        Bool.not(has_attempt(remaining, T.call_id(call))) && attempts(remaining, history)

def ticket_is(phase: M.Phase, ticket: Nat) -> Bool:
  match phase:
    case M.ModelPending{expected, callable}: Nat.is_eq(expected, ticket)
    case M.SummaryPending{expected, resume}: Nat.is_eq(expected, ticket)
    case M.ToolPending{expected, call, remaining}: Nat.is_eq(expected, ticket)
    case _: False{}

def has_ticket(tasks: +List<M.Task>, +ticket: Nat) -> Bool:
  match tasks:
    case Nil{}: False{}
    case Con{task, rest}: ticket_is(M.task_phase(task), ticket) || has_ticket(rest, ticket)

def distinct_ticket(phase: M.Phase, tasks: +List<M.Task>) -> Bool:
  match phase:
    case M.ModelPending{ticket, callable}: Bool.not(has_ticket(tasks, ticket))
    case M.SummaryPending{ticket, resume}: Bool.not(has_ticket(tasks, ticket))
    case M.ToolPending{ticket, call, remaining}: Bool.not(has_ticket(tasks, ticket))
    case _: True{}

def task(task: M.Task, expected_id: Nat, +all: +List<M.Task>, next_ticket: Nat, budget: Nat) -> Bool:
  M.Task{+id, ancestors, +frozen, status, history, queued, pending} = task
  Nat.is_eq(id, expected_id) && contract(frozen) &&
    lineage(ancestors, id, frozen, all, budget) &&
    Nat.is_le(T.descendant_count(all, id), T.contract_limit(frozen)) &&
    phase(status, pending, history, T.task_tools(frozen), next_ticket)

def tasks(remaining: +List<M.Task>, +expected_id: Nat, +all: +List<M.Task>, +next_task: Nat, +next_ticket: Nat, +budget: Nat) -> Bool:
  match remaining:
    case Nil{}: Nat.is_eq(expected_id, next_task)
    case Con{+entry, +rest}:
      task(entry, expected_id, all, next_ticket, budget) && distinct_ticket(M.task_phase(entry), rest) &&
        tasks(rest, 1n+expected_id, all, next_task, next_ticket, budget)

# Canonical identities imply uniqueness. Each parent is older, exists, and has
# exactly the recorded ancestor tail and contract. Quotas count archived tasks.
# Every outstanding ticket is fresh within the allocation bound and is unique.
def world(world: M.World) -> Bool:
  M.World{+entries, next_task, next_ticket, settings, M.ExecutionLimits{steps, +budget, bytes}} = world
  environment(settings) && Nat.is_le(1n, steps) && Nat.is_le(1n, budget) &&
    Nat.is_lt(0n, U32.to_nat(bytes)) && tasks(entries, 0n, entries, next_task, next_ticket, budget)

def archived(status: M.Status) -> Bool:
  match status:
    case M.Archived{}: True{}
    case _: False{}

def archive_retained(status: M.Status, +previous: M.Task, +candidate: M.Task, +budget: Nat) -> Bool:
  match status:
    case M.Archived{}:
      archived(M.task_status(candidate)) && Same.history(budget, M.task_history(previous), M.task_history(candidate)) &&
        Same.strings(M.task_queue(previous), M.task_queue(candidate))
    case _: True{}

# Existing task identities, contracts and ancestry cannot be rewritten or
# deleted. History only grows, and archival also seals history and queued input.
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
    case M.World{before, id_before, ticket_before, env_before, M.ExecutionLimits{steps_before, +budget_before, bytes_before}}
         M.World{after, id_after, ticket_after, env_after, M.ExecutionLimits{steps_after, budget_after, bytes_after}}:
      Nat.is_le(id_before, id_after) && Nat.is_le(ticket_before, ticket_after) &&
        Nat.is_eq(steps_before, steps_after) && Nat.is_eq(budget_before, budget_after) &&
        Nat.is_eq(U32.to_nat(bytes_before), U32.to_nat(bytes_after)) && retained(before, after, budget_before)

def found_archived(found: Maybe<&2, M.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: archived(M.task_status(task))

def cancellation_authorized(found: Maybe<&2, M.Task>) -> Bool:
  match found:
    case Some{M.Task{id, lineage, contract, M.Stopped{}, history, queued, M.Idle{}}}: True{}
    case Some{M.Task{id, lineage, contract, M.Archived{}, history, queued, M.Idle{}}}: True{}
    case _: False{}

def keep_effect(cancelled: Bool, effect: M.Effect, rest: +List<M.Effect>) -> +List<M.Effect>:
  match cancelled:
    case True{}: rest
    case False{}: effect <> rest

# Several internal steps share one commit. An archive later in that decision
# withdraws an earlier, still-unexecuted intent; cancelling it after dispatch
# would unnecessarily cross the external-effect boundary.
def live_effects(effects: +List<M.Effect>, +tasks: +List<M.Task>) -> +List<M.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{M.RequestModel{+id, ticket, model, history, tools, callable}, rest}:
      keep_effect(found_archived(T.find(tasks, id)), M.RequestModel{id, ticket, model, history, tools, callable}, live_effects(rest, tasks))
    case Con{M.RequestSummary{+id, ticket, model, history}, rest}:
      keep_effect(found_archived(T.find(tasks, id)), M.RequestSummary{id, ticket, model, history}, live_effects(rest, tasks))
    case Con{M.ExecuteTool{+id, ticket, tool, call}, rest}:
      keep_effect(found_archived(T.find(tasks, id)), M.ExecuteTool{id, ticket, tool, call}, live_effects(rest, tasks))
    case Con{other, rest}: other <> live_effects(rest, tasks)

def model_effect(found: Maybe<&2, M.Task>, ticket: Nat, model: M.Model, sent_history: M.History,
  tools: +List<M.Tool>, callable: +List<String>, +budget: Nat) -> Bool:
  match found:
    case Some{M.Task{id, lineage, +contract, M.Active{}, history, queued, M.ModelPending{expected, allowed}}}:
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
    case Some{M.Task{id, lineage, contract, M.Active{}, history, queued, M.SummaryPending{expected, resume}}}:
      Nat.is_eq(ticket, expected) && Same.model(model, T.task_model(contract)) &&
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

def tool_effect(found: Maybe<&2, M.Task>, ticket: Nat, tool: M.Tool, call: M.Call, +budget: Nat) -> Bool:
  match found:
    case Some{M.Task{id, lineage, contract, status, history, queued, M.ToolPending{expected, pending, remaining}}}:
      runs_tools(status) && Nat.is_eq(ticket, expected) && Same.call(budget, call, pending) &&
        tool_member(T.task_tools(contract), tool, budget)
    case _: False{}

def has_effect_ticket(effects: +List<M.Effect>, +ticket: Nat) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{M.RequestModel{id, other, model, history, tools, callable}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{M.RequestSummary{id, other, model, history}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{M.ExecuteTool{id, other, tool, call}, rest}:
      Nat.is_eq(other, ticket) || has_effect_ticket(rest, ticket)
    case Con{other, rest}: has_effect_ticket(rest, ticket)

# A dispatched effect must describe the final pending phase exactly, have a
# freshly allocated correlation ticket, and occur only once in this decision.
def effects(pending: +List<M.Effect>, +tasks: +List<M.Task>, +first_ticket: Nat, +budget: Nat) -> Bool:
  match pending:
    case Nil{}: True{}
    case Con{M.RequestModel{id, +ticket, model, history, tools, callable}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        model_effect(T.find(tasks, id), ticket, model, history, tools, callable, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.RequestSummary{id, +ticket, model, history}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        summary_effect(T.find(tasks, id), ticket, model, history, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.ExecuteTool{id, +ticket, tool, call}, +rest}:
      Nat.is_le(first_ticket, ticket) && Bool.not(has_effect_ticket(rest, ticket)) &&
        tool_effect(T.find(tasks, id), ticket, tool, call, budget) && effects(rest, tasks, first_ticket, budget)
    case Con{M.CancelTask{id}, rest}:
      cancellation_authorized(T.find(tasks, id)) && effects(rest, tasks, first_ticket, budget)
    case Con{M.ContinueScheduling{}, rest}: effects(rest, tasks, first_ticket, budget)

def decision(previous: M.World, candidate: M.Decision) -> Bool:
  match previous candidate:
    case M.World{before, id_before, +ticket_before, env_before, M.ExecutionLimits{+steps, +budget, +bytes}}
         M.Decision{M.World{+after, +id_after, +ticket_after, +env_after, +limits_after}, reply, pending}:
      change(M.World{before, id_before, ticket_before, env_before, M.ExecutionLimits{steps, budget, bytes}}, M.World{after, id_after, ticket_after, env_after, limits_after}) &&
        effects(pending, after, ticket_before, budget)
