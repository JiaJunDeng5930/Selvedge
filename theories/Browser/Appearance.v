From Stdlib Require Import String List Bool Arith.
From Selvedge.Browser Require Import Typography Layout Enclosure.
From Selvedge.Interaction.Presentation Require Import Roles Information.
From Selvedge.Interaction Require Appearance.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Inductive paint := Outline | Filled.
Record symbol := Symbol { symbol_name : string; symbol_path : string; symbol_paint : paint }.

(* Preserve the established control artwork independently of layout and domain state. *)
Definition symbols : list symbol := [
  Symbol "tag" "M3 3h7l7 7-7 7-7-7ZM7 7h.01" Outline;
  Symbol "user" "M13 6a3 3 0 1 1-6 0a3 3 0 1 1 6 0M4 17v-2a6 6 0 0 1 12 0v2" Outline;
  Symbol "bot" "M6 6h8a3 3 0 0 1 3 3v6H3V9a3 3 0 0 1 3-3ZM10 6V3M7 10h.01M13 10h.01M7 13h6" Outline;
  Symbol "search" "M14 8a6 6 0 1 1-12 0 6 6 0 0 1 12 0Zm-1.5 4.5L18 18" Outline;
  Symbol "clock" "M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0ZM10 5v5l3 2" Outline;
  Symbol "hand" "M12.6683 4.16699C12.6683 3.84391 12.4065 3.58203 12.0834 3.58203C11.7603 3.58203 11.4984 3.84391 11.4984 4.16699V7.91699L11.4847 8.05078C11.4227 8.35375 11.1547 8.58203 10.8334 8.58203C10.4662 8.58203 10.1685 8.28411 10.1683 7.91699V3.75C10.1683 3.42691 9.90646 3.16504 9.58337 3.16504C9.26029 3.16504 8.99841 3.42691 8.99841 3.75V7.91699C8.99824 8.28411 8.70053 8.58203 8.33337 8.58203C7.96621 8.58203 7.66851 8.28411 7.66833 7.91699V5C7.66833 4.67691 7.40646 4.41504 7.08337 4.41504C6.76029 4.41504 6.49841 4.67691 6.49841 5V9.30371C6.53326 9.3429 6.56715 9.38359 6.59998 9.42578L8.02478 11.2588C8.25005 11.5486 8.19821 11.9659 7.90857 12.1914C7.6187 12.4169 7.20048 12.365 6.97498 12.0752L5.55017 10.2432C5.15812 9.7391 4.41813 9.73637 4.01501 10.1924C4.04396 10.426 4.11486 10.8323 4.25525 11.3486C4.44664 12.0525 4.75404 12.9113 5.21619 13.7383C6.14103 15.3931 7.62465 16.835 10.0004 16.835C12.8545 16.8348 15.1682 14.5211 15.1683 11.667V6.25C15.1683 5.92691 14.9065 5.66504 14.5834 5.66504C14.2603 5.66504 13.9984 5.92691 13.9984 6.25V9.16699C13.9982 9.53411 13.7005 9.83203 13.3334 9.83203C12.9662 9.83203 12.6685 9.53411 12.6683 9.16699V4.16699ZM13.9984 4.42578C14.1828 4.36671 14.3794 4.33496 14.5834 4.33496C15.641 4.33496 16.4984 5.19237 16.4984 6.25V11.667C16.4982 15.2557 13.589 18.1649 10.0004 18.165C6.95953 18.165 5.10939 16.2734 4.05505 14.3867C3.52774 13.4431 3.1843 12.4787 2.97205 11.6982C2.76447 10.9349 2.66834 10.2954 2.66833 10C2.66833 9.87959 2.70117 9.76148 2.76306 9.6582C3.28988 8.78018 4.26555 8.40372 5.16833 8.56152V5C5.16833 3.94237 6.02575 3.08496 7.08337 3.08496C7.31706 3.08496 7.54039 3.12845 7.74744 3.20508C7.98218 2.41297 8.7151 1.83496 9.58337 1.83496C10.1836 1.83496 10.7186 2.11176 11.0697 2.54395C11.3639 2.35978 11.7107 2.25195 12.0834 2.25195C13.141 2.25195 13.9984 3.10937 13.9984 4.16699V4.42578Z" Filled;
  Symbol "shield-code" "M9.06543 1.95123C9.66107 1.69076 10.3389 1.69071 10.9346 1.95123L15.9346 4.13873C16.7832 4.51008 17.3311 5.34917 17.3311 6.27545V10.5528C17.3309 14.6017 14.0489 17.8847 10 17.8848C5.95108 17.8846 2.66813 14.6017 2.66797 10.5528V6.27545C2.66797 5.34924 3.21695 4.51012 4.06543 4.13873L9.06543 1.95123ZM10.4014 3.16998C10.1456 3.05814 9.85444 3.05819 9.59863 3.16998L4.59863 5.35748C4.23427 5.51708 3.99805 5.87764 3.99805 6.27545V10.5528C3.99821 13.8671 6.68563 16.5546 10 16.5547C13.3144 16.5546 16.0008 13.8671 16.001 10.5528V6.27545C16.001 5.87756 15.7658 5.51703 15.4014 5.35748L10.4014 3.16998Z M13.4678 11.4318L13.333 11.4182H10.833C10.466 11.4183 10.1682 11.7162 10.168 12.0832C10.168 12.4504 10.4659 12.7481 10.833 12.7482H13.333L13.4678 12.7346C13.7706 12.6724 13.9981 12.4044 13.9981 12.0832C13.9979 11.7621 13.7706 11.494 13.4678 11.4318Z M7.65336 12.426C7.46431 12.7406 7.05607 12.8424 6.74125 12.6535C6.42646 12.4646 6.32395 12.0563 6.51274 11.7414L7.55668 10.0002L6.51274 8.25899C6.32395 7.94412 6.42646 7.53583 6.74125 7.34688C7.05607 7.15799 7.46431 7.25975 7.65336 7.57442L8.90336 9.6584C9.0296 9.86893 9.0296 10.1315 8.90336 10.342L7.65336 12.426Z" Filled;
  Symbol "shield" "M9.06543 1.95123C9.66107 1.69076 10.3389 1.69071 10.9346 1.95123L15.9346 4.13873C16.7832 4.51008 17.3311 5.34917 17.3311 6.27545V10.5528C17.3309 14.6017 14.0489 17.8847 10 17.8848C5.95108 17.8846 2.66813 14.6017 2.66797 10.5528V6.27545C2.66797 5.34924 3.21695 4.51012 4.06543 4.13873L9.06543 1.95123ZM10.4014 3.16998C10.1456 3.05814 9.85444 3.05819 9.59863 3.16998L4.59863 5.35748C4.23427 5.51708 3.99805 5.87764 3.99805 6.27545V10.5528C3.99821 13.8671 6.68563 16.5546 10 16.5547C13.3144 16.5546 16.0008 13.8671 16.001 10.5528V6.27545C16.001 5.87756 15.7658 5.51703 15.4014 5.35748L10.4014 3.16998Z M10.8883 13.1116C10.8883 13.6025 10.4903 14.0005 9.99936 14.0005C9.50844 14.0005 9.11047 13.6025 9.11047 13.1116C9.11047 12.6207 9.50844 12.2227 9.99936 12.2227C10.4903 12.2227 10.8883 12.6207 10.8883 13.1116Z M10.5169 10.8949L11.1135 7.31519C11.2283 6.62672 10.6974 6 9.99941 6C9.30145 6 8.77053 6.62672 8.88528 7.31519L9.4819 10.8949C9.52406 11.1479 9.74294 11.3333 9.99941 11.3333C10.2559 11.3333 10.4748 11.1479 10.5169 10.8949Z" Filled;
  Symbol "eye" "M 1.71833 10.29 a 0.833333 0.833333 0 0 1 0 -0.58 8.95833 8.95833 0 0 1 16.5633 0 0.833333 0.833333 0 0 1 0 0.58 8.95833 8.95833 0 0 1 -16.5633 0 M12.5 10a2.5 2.5 0 1 0-5 0a2.5 2.5 0 1 0 5 0" Outline;
  Symbol "globe" "M18.3333 10a8.3333 8.3333 0 1 0-16.6666 0a8.3333 8.3333 0 1 0 16.6666 0 M 10 1.66667 a 12.0833 12.0833 0 0 0 0 16.6667 12.0833 12.0833 0 0 0 0 -16.6667 M 1.66667 10 h 16.6667" Outline;
  Symbol "globe-off" "M18.3333 10a8.3333 8.3333 0 1 0-16.6666 0a8.3333 8.3333 0 1 0 16.6666 0 M 10 1.66667 a 12.0833 12.0833 0 0 0 0 16.6667 12.0833 12.0833 0 0 0 0 -16.6667 M 1.66667 10 h 16.6667 M3 3L17 17" Outline;
  Symbol "chevron-right" "M7.5 4.5 L13 10 L7.5 15.5" Outline;
  Symbol "chevron-down" "M4.5 7.5 L10 13 L15.5 7.5" Outline;
  Symbol "stop-square" "M6 5h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z" Outline;
  Symbol "pause-bars" "M7 5v10M13 5v10" Outline;
  Symbol "play-triangle" "m7 4 9 6-9 6Z" Outline;
  Symbol "close-cross" "m5 5 10 10M15 5 5 15" Outline;
  Symbol "more-dots" "M4 10h.01M10 10h.01M16 10h.01" Outline;
  Symbol "menu-lines" "M3 5h14M3 10h14M3 15h14" Outline;
  Symbol "sidebar" "M3 4h14v12H3ZM7 4v12" Outline;
  Symbol "sidebar-close" "M3 4h14v12H3ZM7 4v12 M13 7l-3 3 3 3" Outline;
  Symbol "home" "M2 9 10 2l8 7M4 8v10h12V8M8 18v-6h4v6" Outline;
  Symbol "folder" "M2.5 6V4.5h5l2 2h8V16h-15Z" Outline;
  Symbol "conversation" "M3 3.5h14v10H8l-5 3Z" Outline;
  Symbol "columns" "M3 3h14v14H3ZM7.7 3v14M12.3 3v14" Outline;
  Symbol "agents" "M13 9a3 3 0 1 0-6 0 3 3 0 0 0 6 0ZM4 17v-1a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v1" Outline;
  Symbol "plus" "M10 3v14M3 10h14" Outline;
  Symbol "pencil" "m12.5 3 4.5 4.5-9 9-5 1 1-5ZM10.5 5l4.5 4.5" Outline;
  Symbol "branch" "M6 4v12M6 11h4a4 4 0 0 0 4-4V4M4 2h4v4H4ZM4 14h4v4H4ZM12 2h4v4h-4Z" Outline;
  Symbol "compact" "M3 5h14M3 10h10M3 15h7m3-2 3 3 3-3M16 10v6" Outline;
  Symbol "settings" "M8.4 2h3.2l.5 2.1 1.7 1 2.1-.6 1.6 2.8-1.6 1.5v2.4l1.6 1.5-1.6 2.8-2.1-.6-1.7 1-.5 2.1H8.4l-.5-2.1-1.7-1-2.1.6-1.6-2.8 1.6-1.5V8.8L2.5 7.3l1.6-2.8 2.1.6 1.7-1L8.4 2ZM13 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" Outline;
  Symbol "filter-funnel" "M3 4h14l-5.3 6.1v5.1l-3.4 1.8v-6.9L3 4Z" Outline;
  Symbol "inspector" "M3 3h14v14H3ZM12 3v14M5.5 6h4M5.5 10h4M5.5 14h4" Outline;
  Symbol "inspector-close" "M3 3h14v14H3ZM12 3v14M5.5 6h4M5.5 10h4M5.5 14h4 M7 7l3 3-3 3" Outline;
  Symbol "copy-sheets" "M7 7h10v10H7ZM13 4V3H3v10h1" Outline;
  Symbol "wrap-lines" "M3 5h14M3 10h11a3 3 0 0 1 0 6h-4m2-2-2 2 2 2M3 15h3" Outline;
  Symbol "warning" "m10 2 8 15H2ZM10 7v4M10 14h.01" Outline;
  Symbol "spinner" "M10 2a8 8 0 1 1-8 8" Outline;
  Symbol "trash" "M3 5h14M7 5V3h6v2M5 5l1 12h8l1-12M8 8v6M12 8v6" Outline;
  Symbol "archive-box" "M3 3h14v4H3ZM4 7v10h12V7M8 10h4" Outline;
  Symbol "restore" "M3 4v5h5M3 9a7 7 0 1 1 0 4" Outline;
  Symbol "pin" "m7 2 7 3-2 4 1 3-8-3 3-1ZM8 10l-4 7" Outline;
  Symbol "refresh" "M16 7a7 7 0 0 0-12-1M16 3v4h-4M4 13a7 7 0 0 0 12 1M4 17v-4h4" Outline;
  Symbol "undo" "M7 5 3 9l4 4M3 9h8a5 5 0 0 1 5 5" Outline;
  Symbol "download" "M10 2v11m-4-4 4 4 4-4M3 13v4h14v-4" Outline;
  Symbol "preview" "M2 10s3-6 8-6 8 6 8 6-3 6-8 6-8-6-8-6Zm10.5 0a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0Z" Outline;
  Symbol "paperclip" "m7 10 5-5a3 3 0 0 1 4 4l-8 8a4 4 0 0 1-6-6l8-8m-3 7 5-5" Outline;
  Symbol "grip" "M7 4h.01M13 4h.01M7 10h.01M13 10h.01M7 16h.01M13 16h.01" Outline;
  Symbol "arrow-up" "M9.33467 16.6663V4.93978L4.6374 9.63704L4.1667 9.16634L3.69599 8.69661L9.52998 2.86263L9.63447 2.77767C9.8925 2.60753 10.2433 2.63564 10.4704 2.86263L16.3034 8.69661L16.3884 8.80111C16.5588 9.05922 16.5306 9.40982 16.3034 9.63704C16.0762 9.86414 15.7255 9.89242 15.4675 9.722L15.363 9.63704L10.6647 4.9388V16.6663C10.6647 17.0336 10.367 17.3314 9.99971 17.3314C9.63259 17.3312 9.33467 17.0335 9.33467 16.6663ZM4.6374 9.63704C4.3777 9.89674 3.95569 9.89674 3.69599 9.63704C3.43657 9.37744 3.43668 8.95628 3.69599 8.69661L4.6374 9.63704Z" Filled;
  Symbol "arrow-down" "M9.33467 3.3337V15.06022L4.6374 10.36296L4.1667 10.83366L3.69599 11.30339L9.52998 17.13737L9.63447 17.22233C9.8925 17.39247 10.2433 17.36436 10.4704 17.13737L16.3034 11.30339L16.3884 11.19889C16.5588 10.94078 16.5306 10.59018 16.3034 10.36296C16.0762 10.13586 15.7255 10.10758 15.4675 10.278L15.363 10.36296L10.6647 15.0612V3.3337C10.6647 2.9664 10.367 2.6686 9.99971 2.6686C9.63259 2.6688 9.33467 2.9665 9.33467 3.3337ZM4.6374 10.36296C4.3777 10.10326 3.95569 10.10326 3.69599 10.36296C3.43657 10.62256 3.43668 11.04372 3.69599 11.30339L4.6374 10.36296Z" Filled;
  Symbol "idle-circle" "M16 10a6 6 0 1 1-12 0 6 6 0 0 1 12 0" Outline;
  Symbol "check" "m4 10 4 4 8-8" Outline;
  Symbol "status-backlog" "M17 10a7 7 0 1 1-14 0a7 7 0 1 1 14 0M7 10h6" Outline;
  Symbol "status-todo" "M17 10a7 7 0 1 1-14 0a7 7 0 1 1 14 0" Outline;
  Symbol "status-in-progress" "M10 3a7 7 0 1 1-7 7M10 6v4l3 2" Outline;
  Symbol "status-in-review" "M3 10s3-5 7-5 7 5 7 5-3 5-7 5-7-5-7-5ZM12 10a2 2 0 1 1-4 0a2 2 0 1 1 4 0" Outline;
  Symbol "status-completed" "M17 10a7 7 0 1 1-14 0a7 7 0 1 1 14 0M6 10l3 3 5-6" Outline;
  Symbol "status-blocked" "M17 10a7 7 0 1 1-14 0a7 7 0 1 1 14 0M5 5l10 10" Outline;
  Symbol "priority-no-priority" "M4 10h.01M10 10h.01M16 10h.01" Outline;
  Symbol "priority-low" "M5 15v-4" Outline;
  Symbol "priority-medium" "M5 15v-4M10 15V8" Outline;
  Symbol "priority-high" "M5 15v-4M10 15V8M15 15V4" Outline;
  Symbol "priority-urgent" "M10 4v8M10 16h.01" Outline
].

Definition find_symbol name := find (fun value => String.eqb name (symbol_name value)) symbols.

Inductive flow := BlockFlow | ColumnFlow | RowFlow | SplitRowFlow.
Inductive alignment := Leading | Centered | Trailing | Stretch.
Inductive overflow := ContentFlow | ScrollFlow | CodeOverflow | SingleLineOverflow.
Inductive surface_paint :=
| CanvasPaint | NavigationPaint | ContentPaint | FloatingPaint | InsetPaint
| FieldPaint | EmbeddedPaint | QuietActionPaint | PrimaryActionPaint
| DestructiveActionPaint | ChoicePaint (selected : bool).
Inductive phase := Rest | Hovered | Pressed.

Definition token name := String.append "var(" (String.append name ")").
Definition primary_text := token "--color-token-text-primary".
Definition secondary_text := token "--color-token-text-secondary".
Definition theme (configured : Selvedge.Interaction.Appearance.appearance) (system_dark : bool) :=
  match configured with
  | Selvedge.Interaction.Appearance.SystemAppearance => system_dark
  | Selvedge.Interaction.Appearance.LightAppearance => false
  | Selvedge.Interaction.Appearance.DarkAppearance => true end.
Definition theme_name configured system_dark := if theme configured system_dark then "dark" else "light".
Inductive wash_strength := SubtleWash | EmphasizedWash.
Definition selected_wash strength :=
  let opacity := match strength with SubtleWash => "0.05" | EmphasizedWash => "0.10" end in
  String.append "var(--lightningcss-light, rgba(0, 0, 0, "
    (String.append opacity (String.append "))var(--lightningcss-dark, rgba(255, 255, 255, "
      (String.append opacity "))"))).
Definition foreground value :=
  match value with
  | PrimaryActionPaint => token "--color-text-primary-solid"
  | DestructiveActionPaint => token "--color-text-danger-ghost"
  | _ => primary_text
  end.
Definition background value state :=
  match value with
  | CanvasPaint => token "--app-color-background-surface"
  | NavigationPaint => token "--color-token-side-bar-background"
  | ContentPaint | FieldPaint => token "--color-token-main-surface-primary"
  | FloatingPaint => token "--color-token-dropdown-background"
  | InsetPaint => token "--color-surface-secondary"
  | EmbeddedPaint => "transparent"
  | QuietActionPaint => token (match state with
      | Rest => "--app-color-background-button-tertiary"
      | Hovered => "--app-color-background-button-tertiary-hover"
      | Pressed => "--app-color-background-button-tertiary-active" end)
  | PrimaryActionPaint => token (match state with
      | Rest => "--color-background-primary-solid"
      | Hovered => "--color-background-primary-solid-hover"
      | Pressed => "--color-background-primary-solid-active" end)
  | DestructiveActionPaint => match state with
      | Rest => "transparent"
      | Hovered => token "--color-background-danger-ghost-hover"
      | Pressed => token "--color-background-danger-ghost-active" end
  | ChoicePaint selected => match state with
      | Pressed => token "--app-color-background-button-tertiary-active"
      | Rest => if selected then selected_wash SubtleWash else "transparent"
      | Hovered => if selected then selected_wash EmphasizedWash else token "--color-token-list-hover-background"
      end
  end.

Definition navigation_feedback_properties selected : list (string * string) :=
  [("background","var(--navigation-background, var(--navigation-rest-background))");
   ("--navigation-rest-background",background (ChoicePaint selected) Rest);
   ("--navigation-hover-background",background (ChoicePaint selected) Hovered)].

Record chrome := Chrome {
  chrome_paint : surface_paint; chrome_border : string;
  chrome_border_width : nat; chrome_radius : nat; chrome_shadow : bool
}.
Record frame := Frame { padding_inline : nat; padding_block : nat; frame_gap : nat }.
Record style := Style {
  style_chrome : chrome; style_alignment : alignment; style_flow : flow;
  style_overflow : overflow; style_frame : frame;
  style_minimum_height : nat; style_maximum_percent : nat;
  style_interactive : bool; style_activity_text : bool
}.
Definition chrome_for paint border width radius shadow := Chrome paint border width radius shadow.
Definition clear_chrome := chrome_for EmbeddedPaint "transparent" 0 0 false.
Definition fields paint border width radius shadow align organization spilling inline block gap minimum maximum interactive activity :=
  Style (chrome_for paint border width radius shadow) align organization spilling
    (Frame inline block gap) minimum maximum interactive activity.
Definition enclosure_fields paint border width radius shadow align organization spilling profile gap minimum maximum interactive activity :=
  let area := Enclosure.spacing profile in
  fields paint border width radius shadow align organization spilling
    (Enclosure.inline_inset area) (Enclosure.block_inset area) gap minimum maximum interactive activity.
Definition partition_fields part organization spilling gap :=
  let area := Enclosure.partition part in
  fields EmbeddedPaint "transparent" 0 0 false Stretch organization spilling
    (Enclosure.inline_inset area) (Enclosure.block_inset area) gap 0 100 false false.
Definition base_style := fields EmbeddedPaint "transparent" 0 0 false Stretch BlockFlow ContentFlow 0 0 0 0 100 false false.
Definition button_style paint := enclosure_fields paint "transparent" 0 8 false Stretch RowFlow ContentFlow Enclosure.TextControl (Enclosure.separation Enclosure.InlineControls) 32 100 true false.
Definition navigation_style selected gap radius := enclosure_fields (ChoicePaint selected) "transparent" 0 radius false
  Stretch RowFlow ContentFlow Enclosure.NavigationRow gap 32 100 true true.
Definition role_style (role : Roles.role) :=
  match role with
  | Roles.GlobalNavigation _ => fields NavigationPaint "transparent" 0 0 false Stretch ColumnFlow ScrollFlow 4 8 4 0 100 false false
  | Roles.GlobalNavigationEntry selected _ => navigation_style selected 4 6
  | Roles.CompactHeader => fields CanvasPaint "transparent" 0 0 false Stretch RowFlow ContentFlow 0 0 0 40 100 false false
  | Roles.CompactWorkScope _ _ | Roles.WorkOverviewButton _ => button_style QuietActionPaint
  | Roles.CompactNavigationEntry selected => navigation_style selected 6 5
  | Roles.WorkTabs => fields NavigationPaint "transparent" 0 0 false Stretch BlockFlow ContentFlow 8 0 0 0 100 false false
  | Roles.WorkTab selected => fields (if selected then CanvasPaint else EmbeddedPaint) "transparent" 0 8 false Leading BlockFlow SingleLineOverflow 12 8 0 40 100 true false
  | Roles.Navigation => fields NavigationPaint "transparent" 0 0 false Stretch ColumnFlow ScrollFlow 8 8 4 0 100 false false
  | Roles.NavigationEntry selected => navigation_style selected 6 5
  | Roles.NavigationHeader => fields EmbeddedPaint "transparent" 0 0 false Stretch RowFlow ContentFlow 0 4 8 36 100 false false
  | Roles.Main => fields CanvasPaint "transparent" 0 0 false Stretch ColumnFlow ScrollFlow 0 0 0 0 100 false false
  | Roles.Heading => fields EmbeddedPaint "transparent" 0 0 false Stretch SplitRowFlow ContentFlow 0 0 8 46 100 false false
  | Roles.Timeline => fields EmbeddedPaint "transparent" 0 0 false Stretch ColumnFlow ContentFlow 0 0 16 0 100 false false
  | Roles.Activity => fields EmbeddedPaint "transparent" 0 0 false Stretch ColumnFlow ContentFlow 0 0 4 0 100 false true
  | Roles.UserMessage => enclosure_fields InsetPaint "transparent" 0 16 false Trailing BlockFlow ContentFlow Enclosure.UserMessage 0 0 70 false false
  | Roles.AssistantMessage => fields EmbeddedPaint "transparent" 0 0 false Leading BlockFlow ContentFlow 0 0 0 0 100 false false
  | Roles.Composer => enclosure_fields ContentPaint (token "--color-token-border-default") 1 16 true Stretch ColumnFlow ContentFlow Enclosure.Composer 4 0 100 false false
  | Roles.ComposerActions => fields EmbeddedPaint "transparent" 0 0 false Trailing SplitRowFlow ContentFlow 0 0 Layout.composer_clearance 32 100 false false
  | Roles.DialogActions => partition_fields Enclosure.Footer RowFlow ContentFlow (Enclosure.separation Enclosure.DialogActions)
  | Roles.DialogHeader => partition_fields Enclosure.Header ColumnFlow ContentFlow 0
  | Roles.DialogBody => partition_fields Enclosure.Body ColumnFlow ScrollFlow (Enclosure.separation Enclosure.DialogSections)
  | Roles.Approval => enclosure_fields ContentPaint (token "--color-token-editor-warning-foreground") 1 12 false Stretch ColumnFlow ContentFlow Enclosure.Approval 8 0 100 false false
  | Roles.Toolbar => fields EmbeddedPaint "transparent" 0 0 false Stretch RowFlow ContentFlow 0 0 4 32 100 false false
  | Roles.CodeBlock => enclosure_fields InsetPaint (token "--color-token-border-default") 1 8 false Stretch ColumnFlow CodeOverflow Enclosure.CodeBlock 4 0 100 false false
  | Roles.ApprovalQueue => fields EmbeddedPaint "transparent" 0 0 false Stretch ColumnFlow ScrollFlow 0 0 8 0 100 false false
  | Roles.Section => fields EmbeddedPaint "transparent" 0 0 false Stretch ColumnFlow ContentFlow 0 0 12 0 100 false false
  | Roles.Dialog => fields ContentPaint (token "--color-token-border-default") 1 16 true Stretch ColumnFlow ContentFlow 0 0 0 0 100 false false
  | Roles.Menu => enclosure_fields FloatingPaint (token "--color-token-border-default") 1 12 true Stretch ColumnFlow ScrollFlow Enclosure.Menu (Enclosure.separation Enclosure.MenuItems) 0 100 false false
  | Roles.Details => enclosure_fields ContentPaint (token "--color-token-border-default") 1 0 false Stretch ColumnFlow ScrollFlow Enclosure.Details (Enclosure.separation Enclosure.Sections) 0 100 false false
  | Roles.Card => enclosure_fields ContentPaint (token "--color-token-border-default") 1 9 true Stretch ColumnFlow ContentFlow Enclosure.Card (Enclosure.separation Enclosure.CardSections) 0 100 false false
  | Roles.PrimaryButton => button_style PrimaryActionPaint
  | Roles.DestructiveButton => button_style DestructiveActionPaint
  | Roles.SelectedButton => button_style (ChoicePaint true)
  | Roles.Button => button_style QuietActionPaint
  | Roles.Field => enclosure_fields FieldPaint (token "--color-token-input-border") 1 8 false Stretch BlockFlow ContentFlow Enclosure.Field 0 32 100 true false
  | Roles.CompactNavigationMenu | Roles.WorkTabGroup | Roles.WorkChoiceRow
  | Roles.NavigationCollection | Roles.NavigationSection | Roles.Content | Roles.Alert => base_style
  end.

Definition flow_properties value : list (string * string) :=
  match value with
  | BlockFlow => [("display","block")]
  | ColumnFlow => [("display","flex"); ("flex-direction","column")]
  | RowFlow => [("display","flex"); ("flex-direction","row")]
  | SplitRowFlow => [("display","flex"); ("flex-direction","row"); ("justify-content","space-between")]
  end.
Definition alignment_properties value : list (string * string) :=
  match value with
  | Leading => [("align-items","flex-start"); ("text-align","start")]
  | Centered => [("align-items","center"); ("text-align","center")]
  | Trailing => [("align-items","flex-end"); ("text-align","end")]
  | Stretch => [("align-items","stretch"); ("text-align","start")]
  end.
Definition overflow_properties value : list (string * string) :=
  match value with
  | ContentFlow => []
  | ScrollFlow => [("overflow-y","auto"); ("min-block-size","0")]
  | CodeOverflow => [("overflow-x","auto")]
  | SingleLineOverflow => [("overflow","hidden"); ("text-overflow","ellipsis"); ("white-space","nowrap")]
  end.
Definition overflow_attributes value text : list (string * string) :=
  match value with SingleLineOverflow => [("title",text)] | _ => [] end.
Definition adaptive_width_limit percent :=
  if Nat.ltb percent 100 then
    String.append "calc-size(min-content,min(100%,max(size,"
      (String.append (Numbers.show_nat percent) "%)))")
  else String.append (Numbers.show_nat percent) "%".
Definition style_properties env value : list (string * string) :=
  let root := Layout.root_font_size_milli env in
  let scale := fun value : nat => value in
  let chrome := style_chrome value in
  let paint := chrome_paint chrome in
  let frame := style_frame value in
  flow_properties (style_flow value) ++ alignment_properties (style_alignment value) ++
  overflow_properties (style_overflow value) ++
  [("min-inline-size","0"); ("box-sizing","border-box");
   ("color",if style_interactive value then "var(--control-current-color, var(--control-rest-color))" else foreground paint);
   ("background",if style_interactive value then "var(--control-current-background, var(--control-rest-background))" else background paint Rest);
   ("border-color",chrome_border chrome); ("border-style","solid");
   ("border-width",Typography.px (chrome_border_width chrome));
   ("border-radius",Typography.px (scale (chrome_radius chrome)));
   ("padding-inline",Typography.px (scale (padding_inline frame)));
   ("padding-block",Typography.px (scale (padding_block frame)));
   ("gap",Typography.px (scale (frame_gap frame)));
   ("max-inline-size",adaptive_width_limit (style_maximum_percent value))] ++
  (if Nat.eqb (style_minimum_height value) 0 then [] else
    [("min-block-size",Typography.px (Nat.max (style_minimum_height value) (scale (style_minimum_height value))))]) ++
  (if chrome_shadow chrome then [("box-shadow","var(--shadow-sm)")] else []) ++
  (if style_interactive value then
    [("--control-rest-color",foreground paint); ("--control-rest-background",background paint Rest);
     ("--control-hover-color",foreground paint); ("--control-hover-background",background paint Hovered);
     ("--control-pressed-color",foreground paint); ("--control-pressed-background",background paint Pressed);
     ("--control-disabled-opacity","0.4"); ("--control-focus-ring",token "--color-token-focus-border");
     ("--control-focus-width","2px"); ("--control-focus-offset","-4px");
     ("font-weight","500"); ("cursor","pointer")]
   else []) ++
  (if style_activity_text value then Typography.properties root Typography.ActivityPrimary Typography.Regular else []).

Definition role_typography env role : list (string * string) :=
  let root := Layout.root_font_size_milli env in
  let set := Typography.properties root in
  match role with
  | Roles.GlobalNavigation _ | Roles.GlobalNavigationEntry _ _ => set Typography.ActivitySupport Typography.Regular
  | Roles.CompactHeader | Roles.CompactWorkScope _ _ | Roles.CompactNavigationMenu
  | Roles.CompactNavigationEntry _ | Roles.Navigation | Roles.NavigationEntry _
  | Roles.WorkTabGroup | Roles.WorkTabs => set Typography.ActivityPrimary Typography.Regular
  | Roles.WorkOverviewButton _ | Roles.WorkTab _ => set Typography.ActivityPrimary Typography.Medium
  | Roles.NavigationHeader => set Typography.Body Typography.Medium
  | Roles.Heading => set Typography.Title Typography.Medium
  | Roles.WorkChoiceRow | Roles.UserMessage | Roles.AssistantMessage | Roles.Composer
  | Roles.Field | Roles.Dialog | Roles.Menu | Roles.Details | Roles.Toolbar
  | Roles.DialogActions | Roles.DialogHeader | Roles.DialogBody | Roles.ComposerActions => set Typography.Body Typography.Regular
  | Roles.Activity => set Typography.Support Typography.Regular
  | Roles.CodeBlock => set Typography.CodeBody Typography.Regular
  | Roles.Button | Roles.PrimaryButton | Roles.DestructiveButton | Roles.SelectedButton => set Typography.Body Typography.Medium
  | Roles.Alert => set Typography.Body Typography.Regular
  | _ => [] end.
Definition alert_color_properties :=
  [("color",token "--color-text-danger");("overflow-wrap","anywhere")].
Definition alert_properties env := role_typography env Roles.Alert ++ alert_color_properties.
Definition role_properties env role := style_properties env (role_style role) ++
  (match role with Roles.Alert=>alert_properties env|_=>role_typography env role end) ++
  match role with
  | Roles.Activity => [("color",secondary_text)]
  | Roles.Toolbar => [("justify-content","flex-start")]
  | Roles.GlobalNavigation _ =>
      [("padding-inline",Typography.px (Typography.scaled (Layout.root_font_size_milli env) 4));
       ("padding-block",Typography.px (Typography.scaled (Layout.root_font_size_milli env) 8));
       ("gap",Typography.px (Typography.scaled (Layout.root_font_size_milli env) 4))]
  | Roles.DialogHeader => [("flex","none"); ("min-inline-size","0")]
  | Roles.DialogBody => [("flex","1 1 auto"); ("min-inline-size","0")]
  | Roles.DialogActions => [("flex","none"); ("justify-content","flex-start")]
  | Roles.WorkTab _ => [("--control-disabled-opacity","0.5")]
  | Roles.Button | Roles.PrimaryButton | Roles.DestructiveButton | Roles.SelectedButton =>
      [("justify-content","center"); ("min-inline-size",Typography.px Layout.base_motor_minimum)]
  | _ => [] end.

Definition role_properties_at env (activity : bool) role := role_properties env role ++
  if activity then
  Typography.properties (Layout.root_font_size_milli env)
    (match role with Roles.Activity | Roles.GlobalNavigation _ | Roles.GlobalNavigationEntry _ _ => Typography.ActivitySupport
     | _ => Typography.ActivityPrimary end)
    (match role with Roles.Button | Roles.PrimaryButton | Roles.DestructiveButton | Roles.SelectedButton
     | Roles.NavigationHeader | Roles.WorkTab _ | Roles.WorkOverviewButton _ => Typography.Medium
     | _ => Typography.Regular end) ++
  match role with
  | Roles.DialogHeader | Roles.DialogBody | Roles.DialogActions =>
      Layout.group_properties env true ++ [("padding-inline","0"); ("padding-block","0")]
  | _ => [] end else [].

Definition information_properties env activity role :=
  Typography.properties (Layout.root_font_size_milli env)
    (Typography.information_tier activity role) (Typography.information_emphasis role) ++
  [("color",match role with
    | Information.NavigationCaption | Information.Description | Information.Status => secondary_text
    | _ => primary_text end); ("min-inline-size","0")].

Definition rich_properties env parent strength : list (string * string) :=
  let root := Layout.root_font_size_milli env in
  flat_map (fun '(name, tier, strength) =>
    [(String.append "--rich-" (String.append name "-font"),Typography.font_family tier);
     (String.append "--rich-" (String.append name "-size"),Typography.px (Typography.size root tier));
     (String.append "--rich-" (String.append name "-line"),Typography.px (Typography.line_height root tier));
     (String.append "--rich-" (String.append name "-weight"),Numbers.show_nat (Typography.weight strength))])
    [("title",Typography.Title,Typography.Strong); ("section",Typography.Section,Typography.Medium);
     ("body",parent,strength); ("body-strong",parent,Typography.Strong);
     ("support",Typography.Support,Typography.Medium); ("code",Typography.CodeBody,Typography.Regular)] ++
  [("--rich-strong-weight",Numbers.show_nat (Typography.weight Typography.Strong))].

Inductive markdown_kind := PublishedMarkdown | EmbeddedMarkdown.
Record rich_policy := RichPolicy {
  rich_code_frame : frame; rich_code_chrome : chrome;
  rich_block_gap : nat; rich_list_indent : nat
}.
Definition markdown_policy env parent kind :=
  match kind with
  | PublishedMarkdown =>
      let body := Typography.size (Layout.root_font_size_milli env) parent in
      RichPolicy (Frame 12 12 4)
        (chrome_for InsetPaint (token "--color-token-border-default") 1 8 false) body (2 * body)
  | EmbeddedMarkdown => RichPolicy (Frame 8 8 8) clear_chrome 12 24 end.
Definition markdown_properties env parent kind : list (string * string) :=
  let policy := markdown_policy env parent kind in
  let frame := rich_code_frame policy in let chrome := rich_code_chrome policy in
  rich_properties env parent Typography.Regular ++
  [("--physical-code-padding-inline",Typography.px (padding_inline frame));
   ("--physical-code-padding-block",Typography.px (padding_block frame));
   ("--physical-code-gap",Typography.px (frame_gap frame));
   ("--physical-code-color",foreground (chrome_paint chrome));
   ("--physical-code-background",background (chrome_paint chrome) Rest);
   ("--physical-code-border-width",Typography.px (chrome_border_width chrome));
   ("--physical-code-border-color",chrome_border chrome);
   ("--physical-code-border-radius",Typography.px (chrome_radius chrome));
   ("--physical-code-box-shadow",if chrome_shadow chrome then "var(--shadow-sm)" else "none");
   ("--physical-toolbar-height",match kind with PublishedMarkdown => "auto" | EmbeddedMarkdown => "0px" end);
   ("--physical-block-gap",Typography.px (rich_block_gap policy));
   ("--physical-list-indent",Typography.px (rich_list_indent policy));
   ("--physical-code-white-space","pre"); ("--physical-code-overflow-wrap","normal")].

Definition root_properties env : list (string * string) :=
  Typography.properties (Layout.root_font_size_milli env) Typography.Body Typography.Regular ++
  [("color",primary_text); ("background",background CanvasPaint Rest);
   ("--layout-clearance",Typography.px (Layout.clearance env));
   ("--control-help-delay","300ms");
   ("--native-focus-ring",token "--color-token-focus-border");
   ("--native-focus-width","2px"); ("--native-focus-offset","-4px")] ++
  rich_properties env Typography.Body Typography.Regular.
