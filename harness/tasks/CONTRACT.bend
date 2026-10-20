import Base
import ../DOMAIN.bend as D
import ./PROGRAM.bend as Tasks
import ../workspace/WORKSPACE.bend as Workspace

# Storage replaces each matching identity and retains every unrelated task.
# The independent fold carries the supplied task beside the output sequence.
def required_entry(same: Bool, previous: D.Task, task: D.Task) -> D.Task:
  match same:
    case True{}: task
    case False{}: previous

def required_step(+previous: D.Task, state: (D.Task & +List<D.Task>)) -> (D.Task & +List<D.Task>):
  (+task, tasks) = state
  (task, required_entry(Nat.is_eq(D.task_id(previous), D.task_id(task)), previous, task) <> tasks)

def required_fold(task: D.Task, tasks: +List<D.Task>) -> (D.Task & +List<D.Task>):
  List.foldr(~&2, ~D.Task, ~(D.Task & +List<D.Task>), ~(previous => state => required_step(previous, state)), tasks, (task, Nil{}))

def required_entries(state: (D.Task & +List<D.Task>)) -> +List<D.Task>:
  (task, tasks) = state
  tasks

def required_tasks(task: D.Task, tasks: +List<D.Task>) -> +List<D.Task>:
  required_entries(required_fold(task, tasks))

def required_update(+task: D.Task, +state: D.State) -> D.State:
  D.with_state_tasks(required_tasks(task, D.state_tasks(state)), state)

# Required initial context history is defined independently of task mutation.
def initial_context(context: Maybe<&2, D.HistoryContext>, history: D.History) -> D.History:
  match context:
    case None{}: history
    case Some{context}: D.HistoryNode{history, D.ContextMessage{context}}

# Required context order is independent of the task update implementation.
def initial_global(snapshot: Maybe<&2, D.InstructionSnapshot>, history: D.History) -> D.History:
  match snapshot:
    case None{}: history
    case Some{D.InstructionSnapshot{path, revision, content}}:
      initial_context(D.global_context(path, revision, content), history)

def initial_project(project: D.ProjectContext, history: D.History) -> D.History:
  match project:
    case D.NoProject{}: history
    case D.ProjectContext{workspace, path, revision, content}: initial_context(D.project_guidance_context(workspace, path, revision, content), history)

def initial_history(instructions: D.InitialInstructions, project: D.ProjectContext, context: D.TaskContext,
  profile: D.Profile, reasoning: String, message: D.UserContent, history: D.History) -> D.History:
  D.InitialInstructions{configured, global} = instructions
  D.HistoryNode{D.HistoryNode{initial_project(project, initial_global(global,
    initial_context(D.configured_context(configured), history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}}


def selected_model_history(+context: D.TaskContext, guidance: D.ProjectContext, model: D.Model, history: D.History) -> D.History:
  D.Model{profile, reasoning} = model
  D.HistoryNode{D.select_project_history(context, guidance, history),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}

def selected_history(changed: Bool, selection: Workspace.Selection, +parent: D.Task) -> D.History:
  match changed selection:
    case False{} _: D.task_history(parent)
    case True{} Workspace.Selection{context, guidance}:
      selected_model_history(context, guidance, D.task_model(parent), D.task_history(parent))

# Outputs are the nonempty assistant messages that this accepted ordinary reply
# contributes to history. A tool continuation has no completed reply output.
def output_text(nonempty: Bool, text: String, rest: +List<String>) -> +List<String>:
  match nonempty:
    case True{}: text <> rest
    case False{}: rest

def assistant_outputs(messages: +List<D.Message>) -> +List<String>:
  match messages:
    case Nil{}: Nil{}
    case Con{D.AssistantMessage{+origin, +text}, rest}:
      output_text(Bool.not(String.is_empty(text)), text, assistant_outputs(rest))
    case Con{other, rest}: assistant_outputs(rest)

def normal_output_messages(calls: +List<D.Call>, messages: +List<D.Message>) -> +List<String>:
  match calls:
    case Nil{}: assistant_outputs(messages)
    case Con{call, rest}: Nil{}

def reply_outputs(outcome: D.Outcome) -> +List<String>:
  match outcome:
    case D.ModelReply{+items}:
      normal_output_messages(Tasks.item_calls(items), Tasks.item_messages(0n, 0n, D.Plain{}, items))
    case _: Nil{}

# Output delivery is authorized by the same reply admission as the history write.
# A rejected reply contributes neither assistant output nor graph deliveries.
def permitted_outputs(accepted: Bool, outcome: D.Outcome) -> +List<String>:
  match accepted:
    case True{}: reply_outputs(outcome)
    case False{}: Nil{}

def accepted_reply_outputs(+outcome: D.Outcome, allowed: +List<String>, task: D.Task) -> +List<String>:
  match outcome:
    case D.ModelReply{+items}:
      permitted_outputs(Tasks.model_reply_permitted(allowed, task, Tasks.ModelReplyCandidate{items}), D.ModelReply{items})
    case _: Nil{}

# An idle task freezes the same context as an ordinary task, without inventing
# an instruction or a model request before the first real input arrives.
def initial_idle_history(instructions: D.InitialInstructions, project: D.ProjectContext, context: D.TaskContext,
  profile: D.Profile, reasoning: String, history: D.History) -> D.History:
  D.InitialInstructions{configured, global} = instructions
  D.HistoryNode{initial_project(project, initial_global(global,
    initial_context(D.configured_context(configured), history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}
