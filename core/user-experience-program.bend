import Base
import ./user-experience.bend as E
import ../MODEL.bend as M
import ../PROGRAM.bend as Program

def step(input: E.Input, application: E.Application) -> E.Decision:
  match input:
    case E.ContentInput{identity, input}: E.content_input(identity, input, application)
    case E.PreviewObserved{observation}: E.observe_preview(observation, application)
    case E.UserInput{input}: E.user(input, application)
    case E.RuntimeInput{+input}:
      E.Application{program, session} = application
      E.native_result(Program.transition(input, program), session, None{}, M.durable(input))
    case E.ProgramObserved{program}: E.observe_program(program, application)
    case E.CommandCompleted{program, result, completion}: E.complete_command(program, result, completion, application)
    case E.DirectoriesObserved{ticket, result}: E.observed(ticket, result, application)
    case E.ClockObserved{now}:
      E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, previous, next, pending, previews, code_blocks, next_layer}} = application
      E.local(program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, Nil{})
