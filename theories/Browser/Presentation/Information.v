From Stdlib Require Import String.
Open Scope string_scope.

Inductive text_role :=
| IntroductionTitle | SurfaceTitle | GroupTitle | NavigationCaption
| FieldLabel | FieldValue | OptionLabel | Description | Status.

Definition role_name role :=
  match role with
  | IntroductionTitle => "introduction-title"
  | SurfaceTitle => "surface-title"
  | GroupTitle => "group-title"
  | NavigationCaption => "navigation-caption"
  | FieldLabel => "field-label"
  | FieldValue => "field-value"
  | OptionLabel => "option-label"
  | Description => "description"
  | Status => "status"
  end.
