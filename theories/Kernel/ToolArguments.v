From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson Utf8.
From Selvedge.Kernel Require Import Images ApprovalProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive native_tool := Bash | ReadProcess | WriteProcess | ReadImage.
Record argument_spec := Argument {
  argument_name : string;
  argument_kind : kind;
  argument_description : string;
  argument_bounds : option (N * N)
}.
Definition required_text name description := Argument name KText description None.
Definition optional_text name description := Argument name (KOptional KText) description None.
Definition optional_natural name description minimum maximum :=
  Argument name (KOptional KNatural) description (Some (minimum,maximum)).
Definition operation_argument := Argument "operation_id" KNatural "Bash operation identity in this task" (Some (0,4294967295)).
Definition dimensions := [optional_natural "cols" "PTY columns; supply with rows" 1 65535;
  optional_natural "rows" "PTY rows; supply with cols" 1 65535].
Definition argument_specs (tool : native_tool) : list argument_spec :=
  match tool with
  | Bash => [required_text "command" "Command to run";
      optional_natural "timeout_ms" "Optional deadline in milliseconds; omitted means no deadline" 100 1800000;
      Argument "mode" (KOptional (KEnum "pipe" ["pty"])) "Process transport" None] ++ dimensions ++
    [Argument "sandbox_permissions" (KOptional (KEnum "use_default" ["require_escalated"])) "Sandbox permission request" None;
      optional_text "justification" ("Required for require_escalated: explain the necessary sandbox exception; at most " ++ show_natural ApprovalProtocol.reason_bytes ++ " UTF-8 bytes");
      optional_natural "max_output_length" "Maximum retained Unicode code points; latest content replaces older output" 1 65536]
  | ReadProcess => [operation_argument;optional_text "cursor" "Absolute Unicode code point cursor as a decimal string; default 0"]
  | WriteProcess => [operation_argument;optional_text "input" "Text to write; PTY accepts terminal control characters";
      Argument "eof" (KOptional KBool) "Close pipe stdin after writing input; unavailable in PTY mode" None] ++ dimensions
  | ReadImage => [required_text "path" "Local image path, relative to the task workspace or absolute";
      Argument "detail" (KOptional Images.detail_kind) "Image detail" None]
  end.
Definition argument_schema (tool : native_tool) : schema :=
  map (fun argument => Field argument.(argument_name) argument.(argument_kind)) (argument_specs tool).
Definition optional_kind (kind : kind) := match kind with KOptional _ => true | _ => false end.
Definition get_argument (source : json) (name : string) := match field name source with Some value => value | None => JNull end.
Definition numeric_bounds (value : json) (bounds : N * N) :=
  match as_number value with Some text => match parse_natural text with
    | Some n => (fst bounds <=? n) && (n <=? snd bounds) | None => false end | None => false end.
Definition argument_valid (source : json) (argument : argument_spec) :=
  match field argument.(argument_name) source with
  | None => optional_kind argument.(argument_kind)
  | Some value =>
    (* DEFENSE: Explicit null is not an omitted optional tool argument. *)
    negb (is_null value) && match argument.(argument_bounds) with
      | None => true | Some bounds => numeric_bounds value bounds end
  end.
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
  match Schema.decode (argument_schema tool) source with
  | Some _ => forallb (argument_valid source) (argument_specs tool) && tool_constraints tool source
  | None => false
  end.
Definition arguments (tool : native_tool) := { source : json | valid_arguments tool source = true }.
Definition decode_arguments (tool : native_tool) (source : json) : option (arguments tool) :=
  match valid_arguments tool source as valid return valid_arguments tool source = valid -> option (arguments tool) with
  | true => fun proof => Some (exist _ source proof)
  | false => fun _ => None
  end eq_refl.

Definition kind_schema := SchemaJson.kind_schema.
Definition argument_json (argument : argument_spec) :=
  (* Native optional arguments may be omitted; a present null is rejected. *)
  let present_kind := match argument.(argument_kind) with KOptional element => element | kind => kind end in
  let fields := (kind_schema present_kind ++ [("description",JString argument.(argument_description))])%list in
  JObject (
    match argument.(argument_bounds) with
    | None => fields
    | Some (minimum,maximum) => set_field "minimum" (JNumber (show_natural minimum))
        (set_field "maximum" (JNumber (show_natural maximum)) fields)
    end).
Definition json_schema (tool : native_tool) := JObject [
  ("type",JString "object");("additionalProperties",JBool false);
  ("properties",JObject (map (fun argument => (argument.(argument_name),argument_json argument)) (argument_specs tool)));
  ("required",JArray (map (fun argument => JString argument.(argument_name))
    (filter (fun argument => negb (optional_kind argument.(argument_kind))) (argument_specs tool))))].
Definition tool_name (tool : native_tool) :=
  match tool with Bash => "bash" | ReadProcess => "read_process" | WriteProcess => "write_process" | ReadImage => "read_image" end.
Definition find_native_tool (name : string) :=
  find (fun tool => String.eqb (tool_name tool) name) [Bash;ReadProcess;WriteProcess;ReadImage].
