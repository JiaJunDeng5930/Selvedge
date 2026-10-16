import Base
import ../DOMAIN.bend as D
import ./PROGRAM.bend as Tasks
import ../workspace/WORKSPACE.bend as Workspace

# The shared storage primitive has an independent, complete state equation.
# Frame preservation alone would allow silently discarding the supplied task.
def required_update(+task: D.Task, +state: D.State) -> D.State:
  D.with_state_tasks(Tasks.replace(D.state_tasks(state), task), state)

# Required context order is independent of the task update implementation.
def initial_global(snapshot: Maybe<&2, D.InstructionSnapshot>, history: D.History) -> D.History:
  match snapshot:
    case None{}: history
    case Some{D.InstructionSnapshot{path, revision, content}}:
      D.HistoryNode{history, D.ContextMessage{D.global_context(path, revision, content)}}

def initial_project(project: D.ProjectContext, history: D.History) -> D.History:
  match project:
    case D.NoProject{}: history
    case D.ProjectContext{workspace, revision, content}: D.HistoryNode{history, D.ContextMessage{D.project_guidance_context(workspace, revision, content)}}

def initial_history(instructions: D.InitialInstructions, project: D.ProjectContext, context: D.TaskContext,
  profile: D.Profile, reasoning: String, message: String, history: D.History) -> D.History:
  D.InitialInstructions{configured, global} = instructions
  D.HistoryNode{D.HistoryNode{initial_project(project, initial_global(global,
    D.HistoryNode{history, D.ContextMessage{D.configured_context(configured)}})),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}}


def selected_model_history(context: D.TaskContext, guidance: D.ProjectContext, model: D.Model, history: D.History) -> D.History:
  D.Model{profile, reasoning} = model
  D.HistoryNode{D.select_project_history(guidance, history),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}

def selected_history(changed: Bool, selection: Workspace.Selection, +parent: D.Task) -> D.History:
  match changed selection:
    case False{} _: D.task_history(parent)
    case True{} Workspace.Selection{context, guidance}:
      selected_model_history(context, guidance, Tasks.task_model(D.task_contract(parent)), D.task_history(parent))
