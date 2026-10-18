import Base
import ./MODEL.bend as E
import ../../harness/MODEL.bend as M
import ../../harness/PROGRAM.bend as Program

def step(input: E.Input, +application: E.Application) -> E.Decision:
  match input:
    case E.DismissRetained{key}: E.dismiss_retained(key, application)
    case E.ToggleArchived{key}: E.toggle_archived(key, application)
    case E.ClearDiscarded{task}: E.clear_discarded(task, application)
    case E.InteractiveInput{input}: E.interactive_input(input, application)
    case E.InteractiveEnvironmentObserved{namespace, sequence, fresh, allowed}: E.interactive_environment(namespace, sequence, fresh, allowed, application)
    case E.InteractiveFenceObserved{observation}: E.interactive_fence(observation, application)
    case E.InteractiveSynchronize{}: E.interactive_synchronize(application)
    case E.ToggleInteractiveSource{identity}: E.toggle_interactive_source(identity, application)
    case E.ContentInput{identity, input}: E.content_input(identity, input, application)
    case E.PreviewObserved{observation}: E.observe_preview(observation, application)
    case E.UserInput{input}: E.user(input, application)
    case E.RuntimeInput{+input}:
      +program = E.program(application)
      session = E.session(application)
      E.native_result(Program.transition(input, program), session, None{}, M.durable(input))
    case E.ProgramObserved{program}: E.observe_program(program, application)
    case E.CommandCompleted{program, result, completion}: E.complete_command(program, result, completion, application)
    case E.DirectoriesObserved{ticket, result}: E.observed(ticket, result, application)
    case E.ModelPreferenceRestored{profile, reasoning}: E.restore_preference(profile, reasoning, application)
    case E.WorkspaceGitObserved{ticket, available}: E.workspace_git_observed(ticket, available, application)
    case E.ClockObserved{now}:
      +program = E.program(application)
      +observed_session = E.session(application)
      E.local(program, E.with_now(now, observed_session), Nil{})
