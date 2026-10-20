import ./features/idle.bend as IdleCreation
import ./conversation/speech.bend as Speech
import Base
import ./search/MODEL.bend as SearchModel
import ./search/PROGRAM.bend as Search
import ../features/titles/STATE.bend as Titles
import ../features/compaction/SPEC.bend as Compaction
import ../bendlib/categories.bend as Categories
import ./features/STATE.bend as FeatureState
import ./features/CODEC.bend as FeatureCodec
import ./features/resolution.bend as FeatureResolution
import ./features/operations.bend as FeatureOps
import ./features/SPEC.bend as FeatureSpec
import ./features/MODEL.bend as F
import ./features/work-state.bend as WorkState
import ../bendlib/effects.bend as Effects
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ../bendlib/equality.bend as Same
import ./MODEL.bend as M
import ../bendlib/json.bend as J
import ./tasks/PROGRAM.bend as T
import ./tasks/side-conversation.bend as Side
import ./tasks/side-contract.bend as SideRequirements
import ./execution/OPERATIONS.bend as Ops
import ./INVARIANTS.bend as I
import ../bendlib/stdlib.bend as Std
import ./workspace/WORKSPACE.bend as Workspace
import ./workspace/PROJECTS.bend as Projects
import ./transport/schema.bend as Schema
import ./approval/MODEL.bend as Approvals
import ./reasoning/SPEC.bend as RequiredReasoning
import ./reasoning/context.bend as ReasoningContext
import ./reasoning/MODEL.bend as Reasoning

# A command denotes a resolved operation, not permission to make any safe change.
# Resolution owns every command precondition. The operation's meaning fixes the
# complete post-world, reply and effect list, before bounded scheduling/commit.
# The host cannot submit an Operation: only MODEL.Command crosses the wire.
type Operation is Data:
  ConfigureExecution{task: D.Task, configuration: D.ExecutionConfiguration}
  Refuse{code: String, reason: String}
  StartIdle{profile: D.Profile, reasoning: String, selection: Workspace.Selection, work: Maybe<&2, Nat>, create_worktree: Bool}
  RecordSpeech{task: D.Task, session: String, item: String, speaker: D.SpeechSpeaker, completion: D.SpeechCompletion, text: String}
  DelegateSpeech{task: D.Task, session: String, identity: String, mode: String, message: String}
  ReplaySpeech{result: J.Json}
  Start{profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection}
  Deliver{task: D.Task, message: D.UserContent}
  Steer{task: D.Task, message: D.UserContent}
  Cancel{task: D.Task, operation: D.Operation()}
  Control{task: D.Task, request: D.Control, next: D.Status}
  Branch{parent: D.Task, count: Nat, messages: +List<D.UserContent>, selection: Workspace.Selection}
  OpenSideConversation{parent: D.Task, message: D.UserContent}
  ReturnSideConversation{side: D.Task, parent: D.Task, after: Nat, through: Nat, transcript: D.UserContent}
  Summarize{task: D.Task}
  Checkpoint{task: D.Task, summary: String}
  Observe{query: M.Query}
  StoreProject{project_id: Nat, project: D.Project, next_id: U32}
  RemoveProject{project_id: Nat}
  Review{resolution: Approvals.Resolution}
  FeatureOperation{operation: FeatureOps.Operation}

def admitted(operation: Operation) -> Bool:
  match operation:
    case Refuse{code, reason}: False{}
    case _: True{}

def entries(world: M.World()) -> +List<D.Task>:
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  tasks

def settings(world: M.World()) -> D.Environment:
  C.Frame{+task_state, +board} = world
  environment = D.state_environment(task_state)
  environment

def configured(environment: D.Environment) -> +List<D.Profile>:
  D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins, instructions} = environment
  profiles

def permitted_operation(-predicate: Operation -> Bool, member: Categories.Membership<Operation, Categories.holds(Operation, predicate)>) -> Operation:
  Categories.Membership{operation, evidence} = member
  operation

def operation_admission(-predicate: Operation -> Bool, result: Maybe<&1, Categories.Membership<Operation, Categories.holds(Operation, predicate)>>, code: String, reason: String) -> Operation:
  match result:
    case Some{member}: permitted_operation(predicate, member)
    case None{}: Refuse{code, reason}

def require(predicate: Operation -> Bool, operation: Operation, code: String, reason: String) -> Operation:
  operation_admission(predicate, Categories.admit(Operation, predicate, operation), code, reason)

def start_permitted(operation: Operation) -> Bool:
  match operation:
    case Start{profile, reasoning, +message, selection}: D.profile_permitted(profile, reasoning) && D.content_nonempty(message) && D.content_valid(message)
    case _: False{}

def input_permitted(operation: Operation) -> Bool:
  match operation:
    case Deliver{task, +message}: D.content_valid(message) && D.content_nonempty(message) && D.accepts_input(D.task_status(task))
    case Steer{task, +message}: D.content_valid(message) && D.content_nonempty(message) && D.accepts_input(D.task_status(task))
    case _: False{}

def cancel_permitted(operation: Operation) -> Bool:
  match operation:
    case Cancel{task, action}: D.accepts_input(D.task_status(task))
    case _: False{}

def checkpoint_permitted(operation: Operation) -> Bool:
  match operation:
    case Checkpoint{+task, text}:
      +context = D.task_history(task)
      Bool.not(D.operations_pending(D.task_operations(task))) && D.valid_summary(text) && I.settled_calls(context, context)
    case _: False{}

def task_selection(+task: D.Task) -> Workspace.Selection:
  Workspace.Selection{D.task_context(task), D.task_guidance(task)}

def environment_selection(environment: D.Environment) -> Workspace.Selection:
  D.Environment{catalog, profiles, max_fork, max_descendants, +guidance, plugins, instructions} = environment
  Workspace.Selection{Workspace.defaults(guidance), guidance}

def project_settings(base: Result<&2, &2, String, Workspace.Selection>, options: J.Json,
  profile: D.Profile, profiles: +List<D.Profile>) -> Result<&2, &2, String, Workspace.Selection>:
  match base:
    case Fail{reason}: Fail{reason}
    case Done{Workspace.Selection{context, guidance}}: Workspace.resolve(options, context, guidance, profile, profiles)

def selected_settings(+options: J.Json, base: Workspace.Selection, profile: D.Profile, +world: M.World()) -> Result<&2, &2, String, Workspace.Selection>:
  Workspace.Selection{context, guidance} = base
  project_settings(Projects.select(J.get(options, "project_id"), context, guidance, Projects.registry(F.State(), world)),
    options, profile, configured(settings(world)))

def start_selection(selection: Result<&2, &2, String, Workspace.Selection>, +profile: D.Profile,
  +reasoning: String, +message: D.UserContent) -> Operation:
  match selection:
    case Fail{reason}: Refuse{"invalid_settings", reason}
    case Done{selection}:
      require(start_permitted, Start{profile, reasoning, message, selection},
        "invalid_arguments", "Create requires a nonempty message and a permitted reasoning effort. Adaptive endpoints accept only auto.")

def workspace_permitted(+world: M.World(), operation: Operation) -> Bool:
  match operation:
    case StartIdle{profile, reasoning, Workspace.Selection{context, guidance}, work, create_worktree}: FeatureState.workspace_available(Workspace.workspace(context), world)
    case Start{profile, reasoning, message, Workspace.Selection{context, guidance}}: FeatureState.workspace_available(Workspace.workspace(context), world)
    case Branch{task, count, messages, Workspace.Selection{context, guidance}}: FeatureState.workspace_available(Workspace.workspace(context), world)
    case _: True{}

def available_workspace(operation: Operation, +world: M.World()) -> Operation:
  require(value => workspace_permitted(world, value), operation, "worktree_unavailable", "This managed worktree is not ready. Select an available workspace or wait for its operation to finish.")

def selected(profile: Maybe<&2, D.Profile>, reasoning: String, message: D.UserContent, options: J.Json, +world: M.World()) -> Operation:
  match profile:
    case None{}: Refuse{"unknown_profile", "Select a configured model profile"}
    case Some{+profile}:
      available_workspace(start_selection(selected_settings(options, environment_selection(settings(world)), profile, world),
        profile, D.profile_selection(reasoning, profile), message), world)

def idle_work_allowed(work: Maybe<&2, Nat>, world: M.World()) -> Bool:
  match work:
    case None{}: True{}
    case Some{id}: WorkState.exists(id, world)

def idle_selection(selection: Result<&2, &2, String, Workspace.Selection>, +profile: D.Profile, +reasoning: String, +work: Maybe<&2, Nat>, +create_worktree: Bool, +world: M.World()) -> Operation:
  match selection:
    case Fail{reason}: Refuse{"invalid_settings", reason}
    case Done{+selection}:
      Bool.pick(Operation, D.profile_permitted(profile, reasoning) && idle_work_allowed(work, world) && (Bool.not(create_worktree) || D.nonempty(IdleCreation.primary(selection))), StartIdle{profile, reasoning, selection, work, create_worktree},
        Refuse{"invalid_arguments", "Idle task creation requires permitted reasoning, an existing selected Work, and a primary workspace when creating a worktree"})

def selected_idle(profile: Maybe<&2, D.Profile>, reasoning: String, options: J.Json, work: Maybe<&2, Nat>, create_worktree: Bool, +world: M.World()) -> Operation:
  match profile:
    case None{}: Refuse{"unknown_profile", "Select a configured model profile"}
    case Some{+profile}:
      available_workspace(idle_selection(selected_settings(options, environment_selection(settings(world)), profile, world),
        profile, D.profile_selection(reasoning, profile), work, create_worktree, world), world)

def transcript_existing(found: Maybe<&2, D.Message>, +task: D.Task, +session: String, +item: String, +speaker: D.SpeechSpeaker, +completion: D.SpeechCompletion, +text: String) -> Operation:
  match found:
    case None{}:
      Bool.pick(Operation, D.accepts_input(D.task_status(task)), RecordSpeech{task, session, item, speaker, completion, text},
        Refuse{"task_archived", "An archived task cannot accept a new speech transcript"})
    case Some{D.SpeechTranscript{owner, source, key, actual_speaker, actual_completion, actual_text}}:
      Bool.pick(Operation, String.eq(D.speech_speaker_name(actual_speaker), D.speech_speaker_name(speaker)) &&
        String.eq(D.speech_completion_name(actual_completion), D.speech_completion_name(completion)) && String.eq(actual_text, text),
        ReplaySpeech{Speech.transcript_result(D.task_id(task), session, item, True{})},
        Refuse{"speech_conflict", "A transcript identity already has different committed content"})
    case Some{other}: Refuse{"speech_conflict", "The transcript identity belongs to another record"}

def record_speech_task(found: Maybe<&2, D.Task>, +session: String, +item: String, +speaker: String, +completion: String, +text: String) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      Bool.pick(Operation, D.nonempty(session) && D.nonempty(item) && D.nonempty(text) &&
        (String.eq(speaker, "user") || String.eq(speaker, "assistant")) &&
        (String.eq(completion, "completed") || String.eq(completion, "interrupted")),
        transcript_existing(Speech.transcript(D.task_history(task), D.task_id(task), session, item), task, session, item,
          Bool.pick(D.SpeechSpeaker, String.eq(speaker, "assistant"), D.SpeechAssistant{}, D.SpeechUser{}),
          Bool.pick(D.SpeechCompletion, String.eq(completion, "interrupted"), D.SpeechInterrupted{}, D.SpeechCompleted{}), text),
        Refuse{"invalid_arguments", "A final transcript requires stable session and item identities, valid speaker and completion, and nonempty text"})

def delegation_existing(found: Maybe<&2, D.Message>, +task: D.Task, +session: String, +identity: String, +mode: String, +text: String) -> Operation:
  match found:
    case None{}:
      Bool.pick(Operation, D.accepts_input(D.task_status(task)), DelegateSpeech{task, session, identity, mode, text},
        Refuse{"task_archived", "An archived task cannot accept a new voice delegation"})
    case Some{D.SpeechDelegationReceipt{owner, source, key, actual_mode, actual_text}}:
      Bool.pick(Operation, String.eq(actual_mode, mode) && String.eq(actual_text, text),
        ReplaySpeech{Speech.delegation_result(D.task_id(task), session, identity, True{})},
        Refuse{"speech_conflict", "A delegation identity already has different committed content"})
    case Some{other}: Refuse{"speech_conflict", "The delegation identity belongs to another record"}

def delegate_speech_task(found: Maybe<&2, D.Task>, +session: String, +identity: String, +mode: String, +text: String) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      Bool.pick(Operation, D.nonempty(session) && D.nonempty(identity) && D.nonempty(text) &&
        (String.eq(mode, "send") || String.eq(mode, "steer")),
        delegation_existing(Speech.delegation(D.task_history(task), D.task_id(task), session, identity), task, session, identity, mode, text),
        Refuse{"invalid_arguments", "A voice delegation requires stable session and delegation identities, a nonempty instruction, and send or steer mode"})

def branch_selection(selection: Result<&2, &2, String, Workspace.Selection>, parent: D.Task,
  count: Nat, messages: +List<D.UserContent>) -> Operation:
  match selection:
    case Fail{reason}: Refuse{"invalid_settings", reason}
    case Done{selection}: Branch{parent, count, messages, selection}

def configure_branch(operation: Operation, options: J.Json, +world: M.World()) -> Operation:
  match operation:
    case Branch{+parent, count, messages, base}:
      available_workspace(branch_selection(selected_settings(options, base, D.model_profile(D.task_model(parent)), world), parent, count, messages), world)
    case other: other

def selected_contract(selection: Workspace.Selection, contract: D.Contract) -> D.Contract:
  Workspace.Selection{context, guidance} = selection
  D.Contract{model, tools, max_fork, max_descendants, plugins, previous_context} = contract
  D.Contract{model, tools, max_fork, max_descendants, plugins, context}

def selected_execution(+selection: Workspace.Selection, +parent: D.Task) -> D.Task:
  +contract = selected_contract(selection, D.effective_contract(parent))
  D.with_execution(D.execution_configuration(contract), D.with_contract(contract, parent))

def record_selection(changed: Bool, +selection: Workspace.Selection, +parent: D.Task) -> D.Task:
  match changed:
    case False{}: selected_execution(selection, parent)
    case True{}:
      Workspace.Selection{+context, guidance} = selection
      +model = D.task_model(parent)
      D.append_context(D.TaskSettings{context, D.profile_key(D.model_profile(model)), D.model_selection(model)},
        D.selected_project(guidance, selected_execution(selection, parent)))

def selected_parent(+selection: Workspace.Selection, +parent: D.Task) -> D.Task:
  Workspace.Selection{context, guidance} = selection
  record_selection(Bool.not(Same.project(guidance, D.task_guidance(parent)) &&
    Same.task_context(context, D.task_context(parent))), selection, parent)

def recipient(found: Maybe<&2, D.Task>, +message: D.UserContent) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      require(input_permitted, Deliver{task, message},
        "invalid_arguments", "The message must be nonempty and the target must not be archived")

def steering(found: Maybe<&2, D.Task>, +message: D.UserContent) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      require(input_permitted, Steer{task, message},
        "invalid_arguments", "Steering requires a nonempty instruction and a nonarchived task")

def cancellable(found: Maybe<&2, D.Operation()>, +task: D.Task) -> Operation:
  match found:
    case None{}: Refuse{"operation_not_found", "The operation is not in flight for this task"}
    case Some{operation}:
      require(cancel_permitted, Cancel{task, operation}, "task_archived", "An archived task cannot be changed")

def cancellation(found: Maybe<&2, D.Task>, ticket: Nat) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: cancellable(Ops.find(D.task_operations(task), ticket), task)

def permitted(next: Maybe<&2, D.Status>, task: D.Task, request: D.Control) -> Operation:
  match next:
    case None{}: Refuse{"invalid_transition", "This lifecycle transition is not permitted"}
    case Some{status}: Control{task, request, status}

def controlled(found: Maybe<&2, D.Task>, +request: D.Control) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: permitted(D.control(D.task_status(task), request), task, request)

def per_fork(contract: D.Contract) -> Nat:
  D.Contract{model, tools, max_fork, max_descendants, plugins, context} = contract
  max_fork

def branch_count_valid(+count: Nat, parent: D.Task) -> Bool:
  Nat.is_le(1n, count) && Nat.is_le(count, per_fork(D.task_contract(parent)))

def branch_messages_valid(count: Nat, +messages: +List<D.UserContent>) -> Bool:
  +size = List.length(&2, D.UserContent, messages)
  (Nat.is_eq(size, 0n) || Nat.is_eq(size, count)) && D.contents_valid(messages)

def branch_capacity_valid(+count: Nat, +parent: D.Task, world: M.World()) -> Bool:
  T.ancestors_fit(D.task_id(parent) <> D.task_lineage(parent), entries(world), count)

def branch_parent_valid(status: D.Status, phase: D.Phase) -> Bool:
  match status phase:
    case D.Active{} D.Idle{}: True{}
    case _ _: False{}

def branch_fits(+count: Nat, messages: +List<D.UserContent>, +parent: D.Task, +world: M.World()) -> Bool:
  FeatureState.execution_allowed(D.task_id(parent), world) && branch_count_valid(count, parent) && branch_messages_valid(count, messages) && branch_capacity_valid(count, parent, world)

def branch_permitted(+world: M.World(), operation: Operation) -> Bool:
  match operation:
    case Branch{parent, count, messages, selection}: branch_fits(count, messages, parent, world)
    case _: False{}

def branch_ready_eligible(eligible: Bool, +parent: D.Task,
  +count: Nat, +messages: +List<D.UserContent>, world: M.World()) -> Operation:
  match eligible:
    case True{}:
      require(operation => branch_permitted(world, operation), Branch{parent, count, messages, task_selection(parent)},
        "resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid")
    case False{}: Refuse{"task_busy", "A manual fork requires an active, idle task"}

def branch_ready(status: D.Status, phase: D.Phase, parent: D.Task,
  count: Nat, messages: +List<D.UserContent>, world: M.World()) -> Operation:
  branch_ready_eligible(branch_parent_valid(status, phase), parent, count, messages, world)

def branched(found: Maybe<&2, D.Task>, count: Nat, messages: +List<D.UserContent>, world: M.World()) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+parent}: branch_ready(D.task_status(parent), D.task_phase(parent), parent, count, messages, world)

def side_open_permitted(+world: M.World(), operation: Operation) -> Bool:
  match operation:
    case OpenSideConversation{+parent, message}:
      D.content_valid(message) && D.accepts_input(D.task_status(parent)) && branch_fits(1n, Nil{}, parent, world)
    case _: False{}

def open_side(found: Maybe<&2, D.Task>, message: D.UserContent, +world: M.World()) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The parent task does not exist"}
    case Some{parent}:
      require(operation => side_open_permitted(world, operation), OpenSideConversation{parent, message},
        "side_unavailable", "A side conversation requires a non-archived parent and available descendant capacity")

# DEFENSE: An independently growing side history can exceed the configured serialization budget; refuse without advancing its return cursor.
def side_return_encoded(encoded: Result<&2, &2, String, String>, +side: D.Task, parent: D.Task, +after: Nat, through: Nat) -> Operation:
  match encoded:
    case Fail{reason}: Refuse{"output_limit", "The complete side conversation transcript exceeds the encoding bound"}
    case Done{text}: ReturnSideConversation{side, parent, after, through, Side.returned_message(text, Side.suffix(side, after))}

def side_return_content(messages: +List<D.Message>, +side: D.Task, +parent: D.Task, +after: Nat, +through: Nat, world: M.World()) -> Operation:
  match messages:
    case Nil{}: Refuse{"no_side_content", "This side conversation has no new content to return"}
    case Con{message, rest}:
      side_return_encoded(Side.return_text(D.state_render_budget(C.local(D.State, F.State(), world)), side, D.task_id(parent), after, through),
        side, parent, after, through)

def side_return_available(allowed: Bool, +side: D.Task, +parent: D.Task, +start: Nat, world: M.World()) -> Operation:
  match allowed:
    case False{}: Refuse{"task_archived", "Returning side conversation content requires non-archived source and parent tasks"}
    case True{}:
      +after = SideRequirements.return_cursor(D.task_history(side), D.task_id(side), start)
      side_return_content(Side.suffix(side, after), side, parent, after, D.history_length(D.task_history(side)), world)

def executable_operation(allowed: Bool, operation: Operation) -> Operation:
  match allowed:
    case True{}: operation
    case False{}: Refuse{"worktree_creation_failed", "Worktree creation failed. Archive this task and create a new task to retry; this task cannot execute in the original workspace."}

def side_return_parent(found: Maybe<&2, D.Task>, +side: D.Task, start: Nat, +world: M.World()) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The side conversation's parent task does not exist"}
    case Some{+parent}:
      executable_operation(FeatureState.execution_allowed(D.task_id(parent), world),
        side_return_available(D.accepts_input(D.task_status(parent)) && D.accepts_input(D.task_status(side)), side, parent, start, world))

def side_return_origin(origin: Maybe<&2, D.HistoryContext>, side: D.Task, +world: M.World()) -> Operation:
  match origin:
    case Some{D.SideConversation{owner, parent, start}}:
      side_return_parent(T.find(entries(world), parent), side, start, world)
    case _: Refuse{"not_side_conversation", "The target task is not a side conversation"}

def return_side(found: Maybe<&2, D.Task>, world: M.World()) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The side conversation does not exist"}
    case Some{+side}: side_return_origin(D.task_side_conversation(side), side, world)

def checkpoint_ready(status: D.Status, phase: D.Phase, +task: D.Task, summary: Maybe<&2, String>) -> Operation:
  match status phase summary:
    case D.Archived{} _ _: Refuse{"task_archived", "An archived task cannot be changed"}
    case D.Active{} D.Idle{} None{}: Summarize{task}
    case _ D.Idle{} Some{+text}:
      require(checkpoint_permitted, Checkpoint{task, text},
        "invalid_summary", "A checkpoint requires a nonempty bounded summary, settled tool calls, and no in-flight operations")
    case _ _ _: Refuse{"task_busy", "Model compaction requires an active idle task; a supplied summary requires a nonarchived idle task"}

def compacted(found: Maybe<&2, D.Task>, summary: Maybe<&2, String>) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: checkpoint_ready(D.task_status(task), D.task_phase(task), task, summary)

def project_worktree_preference(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Boolean{create_worktree}: True{}
    case _: False{}

def project_fields(+workspace: J.Json, +guidance: J.Json, create_worktree: J.Json) -> Bool:
  (Workspace.absent(workspace) || Schema.valid(D.workspace_schema(), workspace)) &&
    (Workspace.absent(guidance) || Schema.valid(D.guidance_schema(), guidance)) &&
    project_worktree_preference(create_worktree)

def project_creation_permitted(+workspace: J.Json, +guidance: J.Json, +create_worktree: J.Json, +registry: D.Projects, operation: Operation) -> Bool:
  match operation:
    case StoreProject{id, project, next_id}:
      Schema.valid(D.workspace_schema(), workspace) && project_fields(workspace, guidance, create_worktree) && Projects.valid_project(project) &&
        Nat.is_lt(Projects.count(registry), 256n) && (Projects.next_word(registry) < 4294967295 : U32)
    case _: False{}

def project_update_permitted(+workspace: J.Json, +guidance: J.Json, +create_worktree: J.Json, operation: Operation) -> Bool:
  match operation:
    case StoreProject{id, project, next_id}: project_fields(workspace, guidance, create_worktree) && Projects.valid_project(project)
    case _: False{}

def project_removal_permitted(+world: M.World(), operation: Operation) -> Bool:
  match operation:
    case RemoveProject{+id}:
      Bool.not(Projects.missing(Projects.find(Projects.registry(F.State(), world), id))) && Nat.is_eq(Projects.task_count(entries(world), id), 0n) &&
        Bool.not(FeatureState.project_used(id, world))
    case _: False{}

def create_project(name: String, +workspace: J.Json, +guidance: J.Json, +create_worktree: J.Json, +world: M.World()) -> Operation:
  +project = Projects.proposal(Some{name}, workspace, guidance, create_worktree, D.Project{"", D.Workspace{Nil{}, None{}}, D.NoProject{}, False{}})
  +registry = Projects.registry(F.State(), world)
  +id = Projects.next_id(registry)
  require(operation => project_creation_permitted(workspace, guidance, create_worktree, registry, operation),
    StoreProject{id, project, (Projects.next_word(registry) + 1 : U32)}, "invalid_project", "A project requires a nonempty bounded name, valid workspace defaults, and available project capacity")

def update_project(found: Maybe<&2, D.Project>, id: Nat, name: Maybe<&2, String>, +workspace: J.Json,
  +guidance: J.Json, +create_worktree: J.Json, next_id: U32) -> Operation:
  match found:
    case None{}: Refuse{"project_not_found", "The project does not exist"}
    case Some{previous}:
      +project = Projects.proposal(name, workspace, guidance, create_worktree, previous)
      require(operation => project_update_permitted(workspace, guidance, create_worktree, operation), StoreProject{id, project, next_id},
        "invalid_project", "Project defaults require a valid name, workspace and matching guidance")

def delete_project(+id: Nat, +world: M.World()) -> Operation:
  require(operation => project_removal_permitted(world, operation),
    RemoveProject{id}, "project_not_empty", "The project must exist and have no tasks or board cards before it can be deleted")

def feature_start_result(operation: Operation) -> FeatureResolution.Start:
  match operation:
    case Start{profile, reasoning, message, selection}: FeatureResolution.Start{profile, reasoning, message, selection}
    case Refuse{code, reason}: FeatureResolution.StartRefused{code, reason}
    case _: FeatureResolution.InvalidStart{}

def feature_start(profile: String, reasoning: String, message: D.UserContent, options: J.Json, +world: M.World()) -> FeatureResolution.Start:
  feature_start_result(selected(D.find_profile(configured(settings(world)), profile), reasoning, message, options, world))

def feature_result(resolution: FeatureResolution.Resolution) -> Operation:
  match resolution:
    case FeatureResolution.Refuse{code, reason}: Refuse{code, reason}
    case FeatureResolution.Accept{operation}: FeatureOperation{operation}

# Exhaustiveness is checked by Bend. Client schemas describe MODEL.Command;
# these clauses give each decoded constructor its operational meaning.

def configuration_lease(lease: Reasoning.Lease) -> Bool:
  match lease:
    case Reasoning.NoLease{}: True{}
    case _: False{}

def configuration_quiescent(+task: D.Task) -> Bool:
  D.task_execution_quiescent(task) &&
    configuration_lease(ReasoningContext.lease(D.task_history(task), D.task_id(task)))

def configuration_ready(allowed: Bool, task: D.Task, configuration: D.ExecutionConfiguration) -> Operation:
  match allowed:
    case True{}: ConfigureExecution{task, configuration}
    case False{}: Refuse{"task_busy", "Execution settings require an idle task without queued messages, outstanding operations, scheduled work or a reasoning lease"}

def configuration_policy(valid: Bool, +task: D.Task, configuration: D.ExecutionConfiguration) -> Operation:
  match valid:
    case False{}: Refuse{"invalid_policy", "Execution approval policy requires a configured, valid reviewer profile"}
    case True{}: configuration_ready(configuration_quiescent(task), task, configuration)

def configuration_reasoning(permitted: Bool, +task: D.Task, +profile: D.Profile, +reasoning: String, sandbox: D.Sandbox, +approval: D.ApprovalPolicy) -> Operation:
  match permitted:
    case False{}: Refuse{"invalid_reasoning", "Select a permitted reasoning effort for the execution profile"}
    case True{}:
      model : D.Model = D.Model{profile, reasoning}
      configuration_policy(Workspace.valid_approval(approval), task, D.ExecutionConfiguration{model, sandbox, approval})

def configuration_profile(found: Maybe<&2, D.Profile>, task: D.Task, +reasoning: String, sandbox: D.Sandbox, approval: D.ApprovalPolicy) -> Operation:
  match found:
    case None{}: Refuse{"invalid_profile", "Select a configured model profile"}
    case Some{+profile}: configuration_reasoning(D.profile_valid(profile) && D.profile_permitted(profile, reasoning), task, profile, reasoning, sandbox, approval)

def configuration_review(found: Maybe<&2, D.Profile>) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match found:
    case None{}: Fail{"Approval reviewer is not configured"}
    case Some{profile}: Done{D.ApprovalForMe{profile}}

def configuration_approval(policy: D.ApprovalPolicy, profiles: +List<D.Profile>) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match policy:
    case D.ApprovalForMe{profile}: configuration_review(D.find_profile(profiles, D.profile_key(profile)))
    case other: Done{other}

def configuration_reviewed(policy: Result<&2, &2, String, D.ApprovalPolicy>, task: D.Task, profile: String, reasoning: String, sandbox: D.Sandbox, world: M.World()) -> Operation:
  match policy:
    case Fail{reason}: Refuse{"invalid_policy", reason}
    case Done{approval}: configuration_profile(D.find_profile(configured(settings(world)), profile), task, reasoning, sandbox, approval)

def configure_execution(found: Maybe<&2, D.Task>, profile: String, reasoning: String, sandbox: D.Sandbox, approval: D.ApprovalPolicy, +world: M.World()) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{task}: configuration_reviewed(configuration_approval(approval, configured(settings(world))), task, profile, reasoning, sandbox, world)

def pending_operation(allowed: Bool, operation: Operation) -> Operation:
  match allowed:
    case True{}: operation
    case False{}: Refuse{"worktree_pending", "Wait for worktree creation or archive the task before changing its execution"}

def execution_control_allowed(request: D.Control, id: Nat, world: M.World()) -> Bool:
  match request:
    case D.Archive{}: True{}
    case _: FeatureState.execution_allowed(id, world)

def archive_operation(allowed: Bool, operation: Operation) -> Operation:
  match allowed:
    case True{}: operation
    case False{}: Refuse{"worktree_in_use", "This worktree is shared by other tasks. Archive those tasks before archiving its owner."}

def archival_control_allowed(request: D.Control, id: Nat, world: M.World()) -> Bool:
  match request:
    case D.Archive{}: FeatureState.archive_allowed(id, world)
    case _: True{}

def speech_executable(allowed: Bool, operation: Operation) -> Operation:
  match operation:
    case ReplaySpeech{result}: ReplaySpeech{result}
    case other: executable_operation(allowed, other)

def resolve(command: M.Command, +world: M.World()) -> Operation:
  match command:
    case M.ConfigureTaskExecution{+id, profile, reasoning, sandbox, approval}:
      executable_operation(FeatureState.execution_allowed(id, world), pending_operation(Bool.not(FeatureState.pending_task(id, world)), configure_execution(T.find(entries(world), id), profile, reasoning, sandbox, approval, world)))
    case M.CreateIdle{profile, reasoning, options, work, create_worktree}: selected_idle(D.find_profile(configured(settings(world)), profile), reasoning, options, work, create_worktree, world)
    case M.RecordSpeechTranscript{+id, session, item, speaker, completion, text}:
      record_speech_task(T.find(entries(world), id), session, item, speaker, completion, text)
    case M.AcceptSpeechDelegation{+id, session, identity, message, mode}:
      speech_executable(FeatureState.execution_allowed(id, world), delegate_speech_task(T.find(entries(world), id), session, identity, mode, message))
    case M.Create{profile, reasoning, message, options}:
      selected(D.find_profile(configured(settings(world)), profile), reasoning, message, options, world)
    case M.Send{+id, message}: executable_operation(FeatureState.execution_allowed(id, world), recipient(T.find(entries(world), id), message))
    case M.Steer{+id, message}: executable_operation(FeatureState.execution_allowed(id, world), steering(T.find(entries(world), id), message))
    case M.Cancel{id, ticket}: cancellation(T.find(entries(world), id), ticket)
    case M.ChangeStatus{+id, +control}: archive_operation(archival_control_allowed(control, id, world), executable_operation(execution_control_allowed(control, id, world), pending_operation(FeatureState.control_allowed(control, id, world), controlled(T.find(entries(world), id), control))))
    case M.Fork{+id, count, messages, options}: executable_operation(FeatureState.execution_allowed(id, world), configure_branch(branched(T.find(entries(world), id), count, messages, world), options, world))
    case M.OpenSideConversation{+id, message}:
      executable_operation(FeatureState.execution_allowed(id, world), open_side(T.find(entries(world), id), message, world))
    case M.ReturnSideConversation{+id}:
      executable_operation(FeatureState.execution_allowed(id, world), return_side(T.find(entries(world), id), world))
    case M.Compact{id, summary}: compacted(T.find(entries(world), id), summary)
    case M.Observe{query}: Observe{query}
    case M.CreateProject{name, workspace, guidance, create_worktree}: create_project(name, workspace, guidance, create_worktree, world)
    case M.UpdateProject{+id, name, workspace, guidance, create_worktree}:
      update_project(Projects.find(Projects.registry(F.State(), world), id), id, name, workspace, guidance, create_worktree, Projects.next_word(Projects.registry(F.State(), world)))
    case M.DeleteProject{id}: delete_project(id, world)
    case M.ReviewApproval{id, operation, outcome}:
      Review{Approvals.resolution(F.State(), Approvals.construct_review(F.State(),
        Approvals.ReviewRequest{Approvals.HumanDecision{}, id, operation, outcome, world}))}
    case M.FeatureCommand{command}: feature_result(FeatureResolution.resolve(~feature_start, command, world))

type ConfigurationTarget is Data:
  ConfigurationTarget{task: Nat, configuration: D.ExecutionConfiguration}

def configuration_target(operation: Operation) -> Maybe<&2, ConfigurationTarget>:
  match operation:
    case ConfigureExecution{task, configuration}: Some{ConfigurationTarget{D.task_id(task), configuration}}
    case _: None{}

def configuration_choose(target: Bool, configuration: D.ExecutionConfiguration, before: D.Task) -> D.ExecutionConfiguration:
  match target:
    case True{}: configuration
    case False{}: D.task_execution(before)

def configuration_expected(target: Maybe<&2, ConfigurationTarget>, +before: D.Task) -> D.ExecutionConfiguration:
  match target:
    case None{}: D.task_execution(before)
    case Some{ConfigurationTarget{id, configuration}}:
      configuration_choose(Nat.is_eq(id, D.task_id(before)), configuration, before)

def configuration_retained(before: +List<D.Task>, after: +List<D.Task>, +target: Maybe<&2, ConfigurationTarget>, +budget: Nat) -> Bool:
  match before after:
    case Nil{} _: True{}
    case Con{+before, rest_before} Con{+after, rest_after}:
      Nat.is_eq(D.task_id(before), D.task_id(after)) && Same.execution(budget, configuration_expected(target, before), D.task_execution(after)) &&
        configuration_retained(rest_before, rest_after, target, budget)
    case _ _: False{}

def configuration_input(input: M.Input, +before: M.World()) -> Maybe<&2, ConfigurationTarget>:
  match input:
    case M.UserCommand{M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}}:
      configuration_target(resolve(M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}, before))
    case _: None{}

# Provider continuation binds the complete current execution configuration.
# Unlike bounded persisted-state validation, this comparison cannot run out of fuel.
def configuration_session_same(left: D.ExecutionConfiguration, right: D.ExecutionConfiguration) -> Bool:
  match left right:
    case D.ExecutionConfiguration{model_a, D.Sandbox{mode_a, network_a}, approval_a} D.ExecutionConfiguration{model_b, D.Sandbox{mode_b, network_b}, approval_b}:
      Same.model(model_a, model_b) &&
        String.eq(D.sandbox_mode_name(mode_a), D.sandbox_mode_name(mode_b)) && Same.booleans(network_a, network_b) && Same.approval(approval_a, approval_b)

def configuration_changed(found: Maybe<&2, D.Task>, configuration: D.ExecutionConfiguration) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: Bool.not(configuration_session_same(D.task_execution(task), configuration))

def configuration_reset_required(target: Maybe<&2, ConfigurationTarget>, before: +List<D.Task>) -> Bool:
  match target:
    case None{}: False{}
    case Some{ConfigurationTarget{id, configuration}}: configuration_changed(T.find(before, id), configuration)

def configuration_reset_target(target: Maybe<&2, ConfigurationTarget>, id: Nat, before: +List<D.Task>) -> Bool:
  match target:
    case None{}: False{}
    case Some{ConfigurationTarget{+expected, configuration}}:
      Nat.is_eq(expected, id) && configuration_changed(T.find(before, expected), configuration)

def configuration_has_reset(effects: +List<M.Effect()>) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{Effects.ResetModelSession{id}, rest}: True{}
    case Con{other, rest}: configuration_has_reset(rest)

def configuration_reset_effects(effects: +List<M.Effect()>, +target: Maybe<&2, ConfigurationTarget>, +before: +List<D.Task>) -> Bool:
  match effects:
    case Nil{}: True{}
    case Con{Effects.ResetModelSession{id}, +rest}:
      configuration_reset_target(target, id, before) && Bool.not(configuration_has_reset(rest)) && configuration_reset_effects(rest, target, before)
    case Con{other, rest}: configuration_reset_effects(rest, target, before)

def configuration_allowed(input: M.Input, +before: M.World(), candidate: M.Decision()) -> Bool:
  C.Decision{after, reply, +effects} = candidate
  +target = configuration_input(input, before)
  configuration_retained(entries(before), entries(after), target, D.state_render_budget(C.local(D.State, F.State(), before))) &&
    configuration_reset_effects(effects, target, entries(before)) &&
    Same.booleans(configuration_reset_required(target, entries(before)), configuration_has_reset(effects))

def id_result(id: Nat) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(id)}]}

def replace(task: D.Task, world: M.World()) -> M.World():
  T.update_world(F.State(), task, world)

def changed(id: Nat, task: D.Task, world: M.World(), effects: +List<M.Effect()>) -> M.Decision():
  C.Decision{replace(task, world), D.success(id_result(id)), effects}

def start_environment(profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection, world: M.World(), environment_value: D.Environment) -> M.Decision():
  match selection world environment_value:
    case Workspace.Selection{context, guidance} C.Frame{+task_state, +board} D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins, instructions}:
      tasks = D.state_tasks(task_state)
      +next_task = D.state_next_task(task_state)
      +contract : D.Contract = D.Contract{D.Model{profile, reasoning}, catalog, max_fork, max_descendants, plugins, context}
      task : D.Task = D.Task{next_task, Nil{}, contract, D.execution_configuration(contract),
        D.Active{}, D.EmptyHistory{}, Nil{}, D.Ready{Nil{}}, Nil{}, True{}}
      task = D.initialize_history(instructions, guidance, message, task)
      C.Decision{C.Frame{D.with_state_next_task(1n+next_task, D.with_state_tasks(List.append(&2, D.Task, tasks, [task]), task_state)), board},
        D.success(id_result(next_task)), Nil{}}

def start(profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  start_environment(profile, reasoning, message, selection, world, D.state_environment(C.local(D.State, F.State(), world)))

def start_idle_environment(profile: D.Profile, reasoning: String, selection: Workspace.Selection, world: M.World(), environment_value: D.Environment) -> M.Decision():
  match selection world environment_value:
    case Workspace.Selection{context, guidance} C.Frame{+task_state, +board} D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins, instructions}:
      +next_task = D.state_next_task(task_state)
      +contract : D.Contract = D.Contract{D.Model{profile, reasoning}, catalog, max_fork, max_descendants, plugins, context}
      task : D.Task = D.initialize_idle_history(instructions, guidance, D.Task{next_task, Nil{}, contract, D.execution_configuration(contract), D.Active{}, D.EmptyHistory{}, Nil{}, D.Idle{}, Nil{}, True{}})
      C.Decision{C.Frame{D.with_state_next_task(1n+next_task, D.with_state_tasks(List.append(&2, D.Task, D.state_tasks(task_state), [task]), task_state)), board}, D.success(id_result(next_task)), Nil{}}

def start_idle(profile: D.Profile, reasoning: String, selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  start_idle_environment(profile, reasoning, selection, world, settings(world))

def speech_effects(mode: String, +task: D.Task) -> +List<M.Effect()>:
  Bool.pick(+List<M.Effect()>, String.eq(mode, "steer"), T.steering_effects(F.Effect, D.task_phase(task), D.task_id(task)), Nil{})

def status_change(next: D.Status, +task: D.Task, world: M.World()) -> M.Decision():
  match next:
    case D.Archived{}:
      FeatureState.archived_task(D.task_id(task), C.Decision{Compaction.cancelled_world(task, replace(T.archive(task), world)), D.success(id_result(D.task_id(task))), [Effects.CancelTask{D.task_id(task)}]})
    case status: changed(D.task_id(task), T.promote(D.with_status(status, task)), world, Nil{})

def lifecycle(request: D.Control, next: D.Status, +task: D.Task, world: M.World()) -> M.Decision():
  match request:
    case D.Interrupt{}: C.Decision{Compaction.cancelled_world(task, replace(T.interrupt(task), world)), D.success(id_result(D.task_id(task))), [Effects.CancelTask{D.task_id(task)}]}
    case _: status_change(next, task, world)

def initial_message(message: Maybe<&2, D.UserContent>, history: D.History) -> D.History:
  match message:
    case None{}: history
    case Some{text}: D.HistoryNode{history, D.UserMessage{text}}

def child_selected(+id: Nat, +parent: D.Task, +contract: D.Contract, call_id: String, branch: Nat, remaining: +List<D.Attempt>, message: Maybe<&2, D.UserContent>) -> D.Task:
  D.Task{id, D.task_id(parent) <> D.task_lineage(parent), contract, D.execution_configuration(contract), D.Active{},
    initial_message(message, D.child_history(Ops.inherited(parent), id, call_id, branch)), Nil{}, D.Ready{D.inherit_attempts(remaining)}, Nil{}, True{}}

def child(id: Nat, +parent: D.Task, call_id: String, branch: Nat, remaining: +List<D.Attempt>, message: Maybe<&2, D.UserContent>) -> D.Task:
  child_selected(id, parent, D.effective_contract(parent), call_id, branch, remaining, message)

type Children is Data:
  Children{tasks: +List<D.Task>, next_id: Nat}

def prepend(task: D.Task, children: Children) -> Children:
  Children{rest, end} = children
  Children{task <> rest, end}

def children(count: Nat, +next_id: Nat, +branch: Nat, +parent: D.Task, +call_id: String,
  +remaining: +List<D.Attempt>, +messages: +List<D.UserContent>) -> Children:
  match count:
    case 0n: Children{Nil{}, next_id}
    case 1n+p:
      prepend(child(next_id, parent, call_id, branch, remaining, List.head(&2, D.UserContent, messages)),
        children(p, 1n+next_id, 1n+branch, parent, call_id, remaining, List.tail(&2, D.UserContent, messages)))

def identity(task: D.Task) -> J.Json:
  J.nat(D.task_id(task))

def identities(tasks: +List<D.Task>) -> +List<J.Json>:
  Std.map(~D.Task, ~J.Json, ~identity, tasks)

def branch_call(ticket: Nat, count: Nat, messages: +List<D.UserContent>) -> D.Call:
  D.Call{"manual-fork-" ++ Nat.show(ticket), "fork_task",
    J.Object{[J.Field{"child_count", J.nat(count)}, J.Field{"messages", J.Array{D.content_values(messages)}}]}}

def branch_commit(built: Children, +parent: D.Task, call_id: String, world: M.World()) -> M.Decision():
  Children{+spawned, end} = built
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  next_ticket = D.state_next_ticket(task_state)
  caller = T.promote(D.with_notified(True{}, D.with_phase(D.Ready{Nil{}}, D.with_history(D.branch_history(D.task_history(parent), call_id, 0n), parent))))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+next_ticket, D.with_state_next_task(end, D.with_state_tasks(List.append(&2, D.Task, T.replace(tasks, caller), spawned), task_state))), board},
    D.success(J.Object{[J.Field{"children", J.Array{identities(spawned)}}]}), Nil{}}

def branch(+task: D.Task, +count: Nat, +messages: +List<D.UserContent>, selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  +next_task = D.state_next_task(task_state)
  +next_ticket = D.state_next_ticket(task_state)
  +call = branch_call(next_ticket, count, messages)
  +parent = D.append_message(D.FunctionCall{call}, task)
  branch_commit(children(count, next_task, 1n, selected_parent(selection, parent), T.call_id(call), Nil{}, messages), parent, T.call_id(call), world)

def side_opened(+parent: D.Task, +message: D.UserContent, world: M.World()) -> M.Decision():
  C.Frame{+task_state, board} = world
  +id = D.state_next_task(task_state)
  child = SideRequirements.initial_message(Bool.not(D.content_nonempty(message)), message, SideRequirements.required_child(id, parent))
  C.Decision{C.Frame{D.with_state_next_task(1n+id, D.with_state_tasks(List.append(&2, D.Task, D.state_tasks(task_state), [child]), task_state)), board},
    D.success(J.Object{[J.Field{"task_id", J.nat(id)}, J.Field{"parent_task_id", J.nat(D.task_id(parent))}]}), Nil{}}

def side_returned(+side: D.Task, +parent: D.Task, +after: Nat, +through: Nat, transcript: D.UserContent, world: M.World()) -> M.Decision():
  C.Decision{replace(D.append_context(D.SideReturnCursor{D.task_id(side), through}, side), replace(T.receive(transcript, parent), world)),
    D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(parent))}, J.Field{"side_task_id", J.nat(D.task_id(side))},
      J.Field{"after", J.nat(after)}, J.Field{"through", J.nat(through)}]}), Nil{}}

def summarize(task: D.Task, world: M.World()) -> M.Decision():
  RequiredReasoning.observe_context(F.State(), F.Effect, task, D.SummaryContext{}, world)

def task_work_summary_value(value: J.Json, work: Maybe<&2, Nat>) -> J.Json:
  match value:
    case J.Object{fields}: J.Object{J.Field{"work_id", J.optional_nat(work)} <> fields}
    case value: value

def task_work_summary(+task: D.Task, +world: M.World()) -> J.Json:
  task_work_summary_value(Titles.summary(task, world), WorkState.task_work(task, world))

def task_work_summaries(tasks: +List<D.Task>, +world: M.World()) -> +List<J.Json>:
  match tasks:
    case Nil{}: Nil{}
    case Con{task, rest}: task_work_summary(task, world) <> task_work_summaries(rest, world)

def task_work_page(fields: +List<J.Field>, +task: D.Task, +world: M.World()) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{"task", value}, rest}: J.Field{"task", task_work_summary_value(value, WorkState.task_work(task, world))} <> rest
    case Con{field, rest}: field <> task_work_page(rest, task, world)

def task_work_page_value(value: J.Json, task: D.Task, world: M.World()) -> J.Json:
  match value:
    case J.Object{fields}: D.success(J.Object{task_work_page(fields, task, world)})
    case value: D.success(value)

def page_checked(valid: Bool, +task: D.Task, after: Nat, limit: Nat, +world: M.World()) -> J.Json:
  match valid:
    case False{}: D.failure("invalid_page", "The page requires 1..100 messages and an offset on the task history")
    case True{}: task_work_page_value(Titles.page(task, after, limit, world), task, world)

def page(found: Maybe<&2, D.Task>, +after: Nat, +limit: Nat, world: M.World()) -> J.Json:
  match found:
    case None{}: D.failure("task_not_found", "The target task does not exist")
    case Some{+task}:
      page_checked(Nat.is_le(1n, limit) && Nat.is_le(limit, 100n) && Nat.is_le(after, D.history_length(D.task_history(task))), task, after, limit, world)

def listing_environment(+world: M.World(), environment_value: D.Environment) -> J.Json:
  match world environment_value:
    case C.Frame{+task_state, +board} D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins, instructions}:
      tasks = D.state_tasks(task_state)
      D.success(J.Object{[J.Field{"tasks", J.Array{task_work_summaries(tasks, world)}},
        J.Field{"profiles", J.Array{D.profiles_json(profiles)}}, J.Field{"tools", J.Array{D.tools_json(catalog)}},
        J.Field{"plugins", D.plugins_json(plugins)}, J.Field{"compaction", FeatureCodec.compaction_json(board)},
        J.Field{"max_fork", J.nat(max_fork)}, J.Field{"max_descendants", J.nat(max_descendants)}]})

def listing(+world: M.World()) -> J.Json:
  listing_environment(world, D.state_environment(C.local(D.State, F.State(), world)))

def search_sources(tasks: +List<D.Task>, +world: M.World()) -> +List<SearchModel.Source>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}:
      SearchModel.Source{task, task_work_summary(task, world), WorkState.task_work(task, world)} <> search_sources(rest, world)

def search_project_exists(project: Maybe<&2, Nat>, world: M.World()) -> Bool:
  match project:
    case None{}: True{}
    case Some{id}: Bool.not(Projects.missing(Projects.find(Projects.registry(F.State(), world), id)))

def search_work_exists(work: Maybe<&2, Nat>, world: M.World()) -> Bool:
  match work:
    case None{}: True{}
    case Some{id}: WorkState.exists(id, world)

def search_scoped(project_exists: Bool, work_exists: Bool, query: String, project: Maybe<&2, Nat>, work: Maybe<&2, Nat>, after: Nat, limit: Nat, +world: M.World()) -> J.Json:
  match project_exists work_exists:
    case False{} _: D.failure("project_not_found", "The project does not exist")
    case True{} False{}: D.failure("work_not_found", "The Work does not exist")
    case True{} True{}: Search.execute(search_sources(entries(world), world), query, project, work, after, limit)

def search_history(query: String, +project: Maybe<&2, Nat>, +work: Maybe<&2, Nat>, after: Nat, limit: Nat, +world: M.World()) -> J.Json:
  search_scoped(search_project_exists(project, world), search_work_exists(work, world), query, project, work, after, limit, world)

def query(query: M.Query, +world: M.World()) -> J.Json:
  match query:
    case M.Read{id, after, limit}: page(T.find(entries(world), id), after, limit, world)
    case M.Search{query, project, work, after, limit}: search_history(query, project, work, after, limit, world)
    case M.ListTasks{}: listing(world)
    case M.Describe{}: D.success(M.description())
    case M.ListProjects{}: D.success(J.Array{Projects.summaries(Projects.entries(Projects.registry(F.State(), world)), entries(world))})
    case M.ReadProject{+id}: Projects.detail(id, Projects.find(Projects.registry(F.State(), world), id))
    case M.FeatureQuery{query}: FeatureState.query(query, world)

def configuration_effects(same: Bool, id: Nat) -> +List<M.Effect()>:
  match same:
    case True{}: Nil{}
    case False{}: [Effects.ResetModelSession{id}]

def configured_history(same: Bool, +task: D.Task, configuration: D.ExecutionConfiguration) -> D.Task:
  match same:
    case True{}: D.with_execution(configuration, task)
    case False{}:
      +updated = D.with_execution(configuration, task)
      D.append_context(D.TaskSettings{D.task_context(updated), D.task_profile(updated), D.task_reasoning(updated)}, updated)

def configured_task(+task: D.Task, +configuration: D.ExecutionConfiguration, world: M.World()) -> M.Decision():
  changed(D.task_id(task), configured_history(configuration_session_same(D.task_execution(task), configuration), task, configuration), world,
    configuration_effects(configuration_session_same(D.task_execution(task), configuration), D.task_id(task)))

def meaning(operation: Operation, +world: M.World()) -> M.Decision():
  match operation:
    case ConfigureExecution{task, configuration}: configured_task(task, configuration, world)
    case Refuse{code, reason}: C.Decision{world, D.failure(code, reason), Nil{}}
    case Review{resolution}: Approvals.meaning_calculation(F.State(), F.Effect, resolution, world)
    case StartIdle{profile, reasoning, +selection, work, create_worktree}: IdleCreation.required(work, create_worktree, selection, world, start_idle(profile, reasoning, selection, world))
    case ReplaySpeech{result}: C.Decision{world, D.success(result), Nil{}}
    case RecordSpeech{+task, +session, +item, speaker, completion, text}:
      C.Decision{replace(Speech.record(session, item, speaker, completion, text, task), world), D.success(Speech.transcript_result(D.task_id(task), session, item, False{})), Nil{}}
    case DelegateSpeech{+task, +session, +identity, +mode, message}:
      C.Decision{replace(Speech.accepted(session, identity, mode, message, task), world), D.success(Speech.delegation_result(D.task_id(task), session, identity, False{})), speech_effects(mode, task)}
    case Start{profile, reasoning, message, selection}: start(profile, reasoning, message, selection, world)
    case FeatureOperation{operation}: FeatureSpec.meaning(~start, operation, world)
    case Deliver{+task, message}:
      C.Decision{replace(T.receive(message, task), world), D.success(id_result(D.task_id(task))), Nil{}}
    case Steer{+task, message}:
      C.Decision{replace(T.steer(message, task), world), D.success(id_result(D.task_id(task))),
        T.steering_effects(F.Effect, D.task_phase(task), D.task_id(task))}
    case Cancel{+task, +operation}:
      C.Decision{replace(T.promote(Ops.cancelled(operation, task)), world),
        D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(task))}, J.Field{"operation_id", J.nat(Ops.ticket(operation))}]}),
        [Effects.CancelTicket{D.task_id(task), Ops.callback(operation)}]}
    case Control{task, request, next}: lifecycle(request, next, task, world)
    case Branch{task, count, messages, selection}: branch(task, count, messages, selection, world)
    case OpenSideConversation{parent, message}: side_opened(parent, message, world)
    case ReturnSideConversation{side, parent, after, through, transcript}: side_returned(side, parent, after, through, transcript, world)
    case Summarize{task}: summarize(task, world)
    case Checkpoint{+task, summary}: Compaction.meaning(Compaction.supplied(summary, task, world), world)
    case Observe{request}: C.Decision{world, query(request, world), Nil{}}
    case StoreProject{+id, project, next_id}:
      C.Decision{Projects.store(F.State(), Projects.put(id, project, Projects.registry(F.State(), world), next_id), world),
        D.success(J.Object{[J.Field{"project_id", J.nat(id)}]}), Nil{}}
    case RemoveProject{+id}:
      C.Decision{Projects.store(F.State(), Projects.remove(id, Projects.registry(F.State(), world)), world),
        D.success(J.Object{[J.Field{"project_id", J.nat(id)}]}), Nil{}}

def command(+request: M.Command, +world: M.World()) -> M.Decision():
  meaning(resolve(request, world), world)

def output_send(target: Nat, message: String, +world: M.World()) -> M.Decision():
  command(M.Send{target, D.text_content(message)}, world)


type CommandRequest is Data:
  CommandRequest{command: M.Command, world: M.World()}

def command_resolution(request: CommandRequest) -> Operation:
  CommandRequest{command, world} = request
  resolve(command, world)

def ConstructedCommand() -> Type:
  Categories.Membership<Categories.Construction<CommandRequest, Operation>,
    Categories.constructed_by(CommandRequest, Operation, command_resolution)>

def construct_command(command: M.Command, world: M.World()) -> ConstructedCommand():
  Categories.construct(CommandRequest, Operation, command_resolution, CommandRequest{command, world})
