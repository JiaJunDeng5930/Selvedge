import Base
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ../BOARD.bend as B
import ./json.bend as J
import ./board-navigation.bend as Navigation

# Task/project interactions are cursor operations at the assembly boundary.
def select_task(+cursor: F.Cursor()) -> F.Cursor():
  F.with_board_cursor(Navigation.with_pane(B.ThreadsPane{}, F.board_cursor(cursor)), cursor)

def project_submitted(ok: Bool, +cursor: F.Cursor()) -> F.Cursor():
  F.with_board_cursor(Navigation.project_submitted(ok, F.board_cursor(cursor)), cursor)

def profile_after(event: B.Navigation, profile: String) -> String:
  match event:
    case B.OpenDialog{B.AgentDialog{id}}: ""
    case _: profile

def navigate(event: F.Navigation, previous: M.ViewState) -> M.ViewState:
  match event previous:
    case F.BoardEvent{+event} M.ViewState{selected, after, tasks_after, profile, +cursor}:
      M.ViewState{selected, after, tasks_after, profile_after(event, profile),
        F.with_board_cursor(Navigation.navigate(event, F.board_cursor(cursor)), cursor)}

def submitted(command: F.Command, +reply: J.Json, previous: M.ViewState) -> M.ViewState:
  match command previous:
    case F.BoardCommand{command} M.ViewState{selected, after, tasks_after, profile, +cursor}:
      M.ViewState{selected, after, tasks_after, profile,
        F.with_board_cursor(Navigation.submitted(J.boolean(J.get(reply, "ok")), command, reply, F.board_cursor(cursor)), cursor)}

def remainder(state: M.ViewState) -> F.CursorRest():
  M.ViewState{selected, after, tasks_after, profile, cursor} = state
  F.cursor_rest(cursor)
