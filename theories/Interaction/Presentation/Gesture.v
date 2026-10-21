From Stdlib Require Import String.
Open Scope string_scope.

Inductive gesture :=
| Press | Change | Key | Selection | Search | Filter | Attach | Directory
| ConfirmDirectory | SelectBoardProfile | Place | Dismiss.

Definition gesture_name value :=
  match value with
  | Key => "key" | Press => "press" | Change => "change" | Selection => "selection" | Search => "search"
  | Filter => "filter" | Attach => "attach" | Directory => "directory"
  | ConfirmDirectory => "confirm-directory"
  | SelectBoardProfile => "select-board-profile"
  | Place => "place" | Dismiss => "dismiss"
  end.

Definition decode_gesture value :=
  if String.eqb value "press" then Some Press else
  if String.eqb value "change" then Some Change else
  if String.eqb value "key" then Some Key else
  if String.eqb value "selection" then Some Selection else
  if String.eqb value "search" then Some Search else
  if String.eqb value "filter" then Some Filter else
  if String.eqb value "attach" then Some Attach else
  if String.eqb value "directory" then Some Directory else
  if String.eqb value "confirm-directory" then Some ConfirmDirectory else
  if String.eqb value "select-board-profile" then Some SelectBoardProfile else
  if String.eqb value "place" then Some Place else
  if String.eqb value "dismiss" then Some Dismiss else None.
