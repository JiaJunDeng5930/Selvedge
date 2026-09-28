import Base
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ../BOARD.bend as B
import ./surface.bend as S
import ./json.bend as J
import ./board-navigation.bend as Navigation
import ./board-view.bend as BoardView

# View assembly receives the task surface at the actual interaction boundary;
# feature views never import UI (which would create a renderer dependency cycle).
def navigation() -> S.Node:
  S.Composition{"workspaces", "board-navigation", J.Object{[J.Field{"actions", J.Array{BoardView.navigation_actions(B.ThreadsPane{})}}]}, Nil{}}

def screen_pane(
  threads: M.ViewState -> M.World() -> J.Json -> S.Node,
  embedded: Maybe<&2, Nat> -> Maybe<&2, Nat> -> M.World() -> +List<S.Node>,
  notices: Bool -> J.Json -> +List<S.Node>,
  pane: B.Pane, +state: M.ViewState, +world: M.World(), +reply: J.Json) -> S.Node:
  match pane:
    case B.ThreadsPane{}: threads(state, world, reply)
    case _:
      M.ViewState{selected, after, tasks_after, profile, +cursor} = state
      S.Group{"selvedge", "board-screen", "", List.append(&2, S.Node, notices(J.boolean(J.get(reply, "ok")), reply),
        [S.Composition{"board", "task-board", BoardView.screen(F.board_cursor(cursor), profile, world),
          embedded(BoardView.active_task(Navigation.dialog_of(F.board_cursor(cursor)), world), after, world)}])}

def screen(
  threads: M.ViewState -> M.World() -> J.Json -> S.Node,
  embedded: Maybe<&2, Nat> -> Maybe<&2, Nat> -> M.World() -> +List<S.Node>,
  notices: Bool -> J.Json -> +List<S.Node>,
  +state: M.ViewState, world: M.World(), reply: J.Json) -> S.Node:
  M.ViewState{selected, after, tasks_after, profile, cursor} = state
  screen_pane(threads, embedded, notices, Navigation.pane_of(F.board_cursor(cursor)), state, world, reply)
