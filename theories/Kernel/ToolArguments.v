From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import SchemaJson Utf8.
From Selvedge.Programming Require Export Arguments.
From Selvedge.Kernel Require Import Images ApprovalProtocol.
From Selvedge.Host Require Process.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.

Definition nonempty_text := D.Text (D.TextConstraints 1 D.maximum_natural
 D.maximum_natural true false false None).

Inductive native_tool := Bash | ReadProcess | WriteProcess | ReadImage.
Definition required_text name description := Argument name (Scalar KText) true description.
Definition optional_text name description := Argument name (Scalar KText) false description.
Definition optional_natural name description minimum maximum :=
  Arguments.with_bounds (minimum,maximum) (Argument name (Scalar KNatural) false description).
Definition operation_argument := Arguments.with_bounds (0,4294967295)
 (Argument "operation_id" (Scalar KNatural) true "Bash operation identity in this task").
Definition dimensions := [optional_natural "cols" "PTY columns; supply with rows" 1 65535;
  optional_natural "rows" "PTY rows; supply with cols" 1 65535].
Definition argument_specs (tool : native_tool) : list argument_spec :=
  match tool with
  | Bash => [Arguments.with_declaration nonempty_text (required_text "command" "Command to run");
      optional_natural "timeout_ms" "Optional deadline in milliseconds; omitted means no deadline" 100 1800000;
      Argument "mode" (Scalar (KEnum "pipe" ["pty"])) false "Process transport"] ++ dimensions ++
    [Argument "sandbox_permissions" (Scalar (KEnum "use_default" ["require_escalated"])) false "Sandbox permission request";
      optional_text "justification" ("Required for require_escalated: explain the necessary sandbox exception; at most " ++ show_natural ApprovalProtocol.reason_bytes ++ " UTF-8 bytes");
      optional_natural "max_output_length" "Maximum retained Unicode code points; latest content replaces older output" 1 65536]
  | ReadProcess => [operation_argument;optional_text "cursor" "Absolute Unicode code point cursor as a decimal string; default 0"]
  | WriteProcess => [operation_argument;optional_text "input" "Text to write; PTY accepts terminal control characters";
      Argument "eof" (Scalar KBool) false "Close pipe stdin after writing input; unavailable in PTY mode"] ++ dimensions
  | ReadImage => [Arguments.with_declaration nonempty_text (required_text "path" "Local image path, relative to the task workspace or absolute");
      Argument "detail" (Scalar Images.detail_kind) false "Image detail"]
  end.
(** Primitive effects keep their admitted values. A terminal resize is one
    optional pair, and only a PTY transport can carry it. *)
Inductive permission_request := UseDefault
 | RequireEscalated (justification : D.denote ApprovalProtocol.justification_declaration).
Definition permission_of
 (requested : option (Schema.denote (KEnum "use_default" ["require_escalated"])))
 (justification : option (D.denote D.text)) : option permission_request :=
 match requested with
 | Some requested => if String.eqb (proj1_sig requested) "require_escalated" then
   match justification with
   | Some text => option_map RequireEscalated
       (D.admit (D.check_text ApprovalProtocol.justification_constraints) (proj1_sig text))
   | None => None end
   else Some UseDefault
 | None => Some UseDefault end.
Definition mode_of (requested : option (Schema.denote (KEnum "pipe" ["pty"]))) :=
 match requested with Some requested =>
   if String.eqb (proj1_sig requested) "pty" then Process.Pty else Process.Pipe
 | None => Process.Pipe end.
Record bash_parameters := BashParameters {
 bash_command : D.denote nonempty_text;
 bash_timeout : option (D.denote (D.Natural 100 1800000));
 bash_transport : Process.transport;
 bash_permission : permission_request;
 bash_maximum : option (D.denote (D.Natural 1 65536))
}.
Definition operation_identity := D.denote (D.Natural 0 4294967295).
Definition cursor_declaration := D.Natural 0 9007199254740991.
Definition process_cursor := D.denote cursor_declaration.
Definition decode_cursor (source : option (D.denote D.text)) : option process_cursor :=
 match source with
 | None => Some (exist _ 0 eq_refl)
 | Some source => match parse_natural (proj1_sig source) with
   | Some cursor => D.admit (D.in_bounds 0 9007199254740991) cursor
   | None => None end
 end.
Record read_parameters := ReadParameters { read_operation : operation_identity; read_cursor : process_cursor }.
Record write_parameters := WriteParameters {
 write_operation : operation_identity;
 write_input : option (D.denote D.text);
 write_eof : option bool;
 write_size : option Process.terminal_size
}.
Record image_parameters := ImageParameters {
 image_path : D.denote nonempty_text;
 image_detail : option (Schema.denote Images.detail_kind)
}.
Definition arguments (tool : native_tool) : Set := match tool with
 | Bash => bash_parameters | ReadProcess => read_parameters
 | WriteProcess => write_parameters | ReadImage => image_parameters end.
Definition construct (tool : native_tool) : Arguments.parsed_arguments (argument_specs tool) -> option (arguments tool) :=
 match tool as tool return Arguments.parsed_arguments (argument_specs tool) -> option (arguments tool) with
 | Bash => fun fields =>
   let '(command,(timeout,(mode,(cols,(rows,(permissions,(justification,(maximum,_)))))))) := proj1_sig fields in
   match Process.paired_size cols rows, permission_of permissions justification with
   | Some size,Some permissions => option_map
       (fun transport => BashParameters command timeout transport permissions maximum)
       (Process.prepare_transport (mode_of mode) size)
   | _,_ => None end
 | ReadProcess => fun fields => let '(operation,(cursor,_)) := proj1_sig fields in
   option_map (ReadParameters operation) (decode_cursor cursor)
 | WriteProcess => fun fields => let '(operation,(input,(eof,(cols,(rows,_))))) := proj1_sig fields in
   option_map (WriteParameters operation input eof) (Process.paired_size cols rows)
 | ReadImage => fun fields => let '(path,(detail,_)) := proj1_sig fields in Some (ImageParameters path detail)
 end.
Definition decode_arguments (tool : native_tool) (source : json) : option (arguments tool) :=
 match Arguments.decode_arguments (argument_specs tool) source with
 | Some fields => construct tool fields | None => None end.
Definition valid_arguments (tool : native_tool) (source : json) :=
 D.present (decode_arguments tool source).

Definition json_schema (tool : native_tool) := Arguments.json_schema (argument_specs tool).
Definition tool_name (tool : native_tool) :=
  match tool with Bash => "bash" | ReadProcess => "read_process" | WriteProcess => "write_process" | ReadImage => "read_image" end.
Definition find_native_tool (name : string) :=
  find (fun tool => String.eqb (tool_name tool) name) [Bash;ReadProcess;WriteProcess;ReadImage].
