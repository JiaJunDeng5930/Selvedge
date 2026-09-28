import Base
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ../BOARD.bend as B
import ./json.bend as J
import ./board-navigation.bend as Navigation
import ./feature-ui.bend as Actual
import ./feature-frame.bend as FrameProof

def navigation_frame(event: B.Navigation, previous: M.ViewState) ->
  {Actual.remainder(Actual.navigate(F.BoardEvent{event}, previous)) == Actual.remainder(previous) : F.CursorRest()}:
  match previous:
    case M.ViewState{selected, after, tasks_after, profile, +cursor}:
      FrameProof.cursor_frame(Navigation.navigate(event, F.board_cursor(cursor)), cursor)

def submission_frame(command: B.Command, +reply: J.Json, previous: M.ViewState) ->
  {Actual.remainder(Actual.submitted(F.BoardCommand{command}, reply, previous)) == Actual.remainder(previous) : F.CursorRest()}:
  match previous:
    case M.ViewState{selected, after, tasks_after, profile, +cursor}:
      FrameProof.cursor_frame(Navigation.submitted(J.boolean(J.get(reply, "ok")), command, reply, F.board_cursor(cursor)), cursor)
