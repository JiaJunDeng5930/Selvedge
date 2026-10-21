From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson Utf8.
From Selvedge.Foundation Require Export Arguments.
From Selvedge.Kernel Require Import Images ApprovalProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive native_tool := Bash | ReadProcess | WriteProcess | ReadImage.
Definition required_text name description := Argument name (Scalar KText) true description None.
Definition optional_text name description := Argument name (Scalar KText) false description None.
Definition optional_natural name description minimum maximum :=
  Argument name (Scalar KNatural) false description (Some (minimum,maximum)).
Definition operation_argument := Argument "operation_id" (Scalar KNatural) true "Bash operation identity in this task" (Some (0,4294967295)).
Definition dimensions := [optional_natural "cols" "PTY columns; supply with rows" 1 65535;
  optional_natural "rows" "PTY rows; supply with cols" 1 65535].
Definition argument_specs (tool : native_tool) : list argument_spec :=
  match tool with
  | Bash => [required_text "command" "Command to run";
      optional_natural "timeout_ms" "Optional deadline in milliseconds; omitted means no deadline" 100 1800000;
      Argument "mode" (Scalar (KEnum "pipe" ["pty"])) false "Process transport" None] ++ dimensions ++
    [Argument "sandbox_permissions" (Scalar (KEnum "use_default" ["require_escalated"])) false "Sandbox permission request" None;
      optional_text "justification" ("Required for require_escalated: explain the necessary sandbox exception; at most " ++ show_natural ApprovalProtocol.reason_bytes ++ " UTF-8 bytes");
      optional_natural "max_output_length" "Maximum retained Unicode code points; latest content replaces older output" 1 65536]
  | ReadProcess => [operation_argument;optional_text "cursor" "Absolute Unicode code point cursor as a decimal string; default 0"]
  | WriteProcess => [operation_argument;optional_text "input" "Text to write; PTY accepts terminal control characters";
      Argument "eof" (Scalar KBool) false "Close pipe stdin after writing input; unavailable in PTY mode" None] ++ dimensions
  | ReadImage => [required_text "path" "Local image path, relative to the task workspace or absolute";
      Argument "detail" (Scalar Images.detail_kind) false "Image detail" None]
  end.
Definition argument_schema (tool : native_tool) : schema :=
  Arguments.argument_schema (argument_specs tool).
Definition get_argument (source : json) (name : string) := match field name source with Some value => value | None => JNull end.
Definition has_argument (source : json) (name : string) := has_field name source.
Definition paired_dimensions (source : json) := Bool.eqb (has_argument source "cols") (has_argument source "rows").
Definition defaulted_mode (source : json) := match string_field "mode" source with Some mode => mode | None => "pipe" end.
Definition tool_constraints (tool : native_tool) (source : json) :=
  match tool with
  | Bash =>
    match string_field "command" source with Some command =>
      Utf8.well_formed command && Utf8.no_nul command && negb (String.eqb command "") &&
      paired_dimensions source && (negb (has_argument source "cols") || String.eqb (defaulted_mode source) "pty") &&
      (match string_field "sandbox_permissions" source with
       | Some permissions => negb (String.eqb permissions "require_escalated") ||
         match string_field "justification" source with
         | Some text => ApprovalProtocol.valid_justification text | None => false end
       | None => true end)
    | None => false end
  | ReadProcess =>
    match string_field "cursor" source with None => true | Some cursor =>
      match parse_natural cursor with Some n => n <=? 9007199254740991 | None => false end end
  | WriteProcess => paired_dimensions source &&
    match string_field "input" source with None => true | Some input => Utf8.well_formed input end
  | ReadImage => match string_field "path" source with
      Some path => Utf8.nonblank path && Utf8.well_formed path && Utf8.no_nul path | None => false end
  end.
Definition valid_arguments (tool : native_tool) (source : json) :=
  Arguments.valid (argument_specs tool) source && tool_constraints tool source.
Definition arguments (tool : native_tool) := { source : json | valid_arguments tool source = true }.
Definition decode_arguments (tool : native_tool) (source : json) : option (arguments tool) :=
  match valid_arguments tool source as valid return valid_arguments tool source = valid -> option (arguments tool) with
  | true => fun proof => Some (exist _ source proof)
  | false => fun _ => None
  end eq_refl.

Definition json_schema (tool : native_tool) := Arguments.json_schema (argument_specs tool).
Definition tool_name (tool : native_tool) :=
  match tool with Bash => "bash" | ReadProcess => "read_process" | WriteProcess => "write_process" | ReadImage => "read_image" end.
Definition find_native_tool (name : string) :=
  find (fun tool => String.eqb (tool_name tool) name) [Bash;ReadProcess;WriteProcess;ReadImage].
