import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../../bendlib/component.bend as Component
import ./speech-contract.bend as Requirements
import ../tasks/CONTRACT.bend as TaskRequirements
import ../tasks/PROOF.bend as TaskProof

# These equations concern the actual append and task-input functions. Complete
# command, invocation and committed-input refinement remains in protocol/PROOF.
def Requirements.transcript_changes_only_history(session, item, speaker, completion, text, id, lineage, contract, current, status, history, queued, phase, operations, notified):
  {==}

def Requirements.transcript_committed_operation(task, session, item, speaker, completion, text, world):
  {==}

def Requirements.transcript_never_schedules(id, session, item, speaker, completion, text, decision):
  match decision:
    case Component.Decision{world, reply, effects}: ({==}, {==})

def Requirements.idle_creation_never_schedules(profile, reasoning, settings, work, tree, decision):
  match decision:
    case Component.Decision{world, reply, effects}: ({==}, {==})

def Requirements.delegation_send_is_ordinary_input(session, identity, text, task):
  {==}

def Requirements.delegation_steer_is_ordinary_input(session, identity, text, task):
  {==}

def Requirements.delegation_send_committed_operation(task, session, identity, message, world):
  {==}

def Requirements.replay_changes_nothing(result, world):
  {==}

def idle_context_meaning(+configured: Maybe<&2, D.HistoryContext>, +global: Maybe<&2, D.HistoryContext>, +project: Maybe<&2, D.HistoryContext>,
  +context: D.TaskContext, +profile: D.Profile, +reasoning: String, +history: D.History) ->
  {D.HistoryNode{D.history_initial_context(project, D.history_initial_context(global, D.history_initial_context(configured, history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}} ==
   D.HistoryNode{TaskRequirements.initial_context(project, TaskRequirements.initial_context(global, TaskRequirements.initial_context(configured, history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}} : D.History}:
  Equal.cong(D.History, D.History,
    prefix => D.HistoryNode{prefix, D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}},
    D.history_initial_context(project, D.history_initial_context(global, D.history_initial_context(configured, history))),
    TaskRequirements.initial_context(project, TaskRequirements.initial_context(global, TaskRequirements.initial_context(configured, history))),
    TaskProof.initial_contexts_meaning(configured, global, project, history))

def Requirements.idle_initial_history_has_no_input(instructions, project, profile, reasoning, tools, max_fork, max_descendants, plugins, context, history):
  match instructions project:
    case D.InitialInstructions{configured, None{}} D.NoProject{}:
      idle_context_meaning(D.configured_context(configured), None{}, None{}, context, profile, reasoning, history)
    case D.InitialInstructions{configured, None{}} D.ProjectContext{root, path, revision, content}:
      idle_context_meaning(D.configured_context(configured), None{}, D.project_guidance_context(root, path, revision, content), context, profile, reasoning, history)
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.NoProject{}:
      idle_context_meaning(D.configured_context(configured), D.global_context(path, revision, content), None{}, context, profile, reasoning, history)
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.ProjectContext{root, project_path, project_revision, project_content}:
      idle_context_meaning(D.configured_context(configured), D.global_context(path, revision, content), D.project_guidance_context(root, project_path, project_revision, project_content), context, profile, reasoning, history)

def Requirements.replayed_delegation_never_schedules(id, session, identity, text, mode, world):
  {==}
