From Stdlib Require Import String List Ascii.
From MetaRocq.Template Require Import All.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import Numbers.
From Selvedge.Programming Require Import ArgumentProjection.
From Selvedge.Kernel Require Import Commands CommandDeclarations.
Import ListNotations MonadNotation.
Local Open Scope string_scope.

Definition append := Stdlib.Strings.String.append.
Definition newline := Stdlib.Strings.String.String (ascii_of_nat 10) Stdlib.Strings.String.EmptyString.
Definition line (text : String.string) := append text newline.
Fixpoint join (separator : String.string) (parts : list String.string) : String.string :=
  match parts with
  | [] => ""
  | part :: [] => part
  | part :: rest => append part (append separator (join separator rest))
  end.
Fixpoint indexed {A} (index : nat) (values : list A) : list (nat * A) :=
  match values with [] => [] | value :: rest => (index,value) :: indexed (S index) rest end.
Definition concat (parts : list String.string) := join "" parts.
Fixpoint kind_source (description : kind) : String.string :=
  match description with
  | KText => "KText" | KBool => "KBool" | KNatural => "KNatural"
  | KInteger => "KInteger" | KDecimal => "KDecimal" | KJson => "KJson"
  | KArray element => concat ["(KArray "; kind_source element; ")"]
  | KOptional element => concat ["(KOptional "; kind_source element; ")"]
  | KEnum first rest => concat ["(KEnum """; first; """ [";
      join "; " (map (fun value => concat [""""; value; """"]) rest); "])"]
  end.
Definition field_source (field : field_spec) :=
  concat [if field_omittable field then "OmittableField """ else "Field """;
    field_name field; """ "; kind_source (field_kind field)].
Definition field_type_source (field : field_spec) :=
  let value := concat ["denote "; kind_source (field_kind field)] in
  if field_omittable field then concat ["option ("; value; ")"] else value.
Definition getter_name (name : String.string) (field : field_spec) := concat [name; "_"; field_name field].
Definition argument_reference (index : nat) :=
  concat ["(fst "; Nat.iter (S index) (fun source => concat ["(snd ";source;")"]) "values"; ")"].
Definition admitted_getter_name (name : String.string) (field : field_spec) :=
 concat [getter_name name field; "_admitted"].
Definition payload_source (index : nat) (command : command_spec) : String.string :=
  let name := command_name command in
  let declarations := command_fields command in
  concat [
    line (concat ["Definition "; name; "_schema := command_fields (List.nth "; show_nat index;
      " Selvedge.Kernel.Commands.command_specs (Command """" []))."]);
    line (concat ["Definition "; name; "_input_declaration := CommandDeclarations.command_arguments true (List.nth "; show_nat index;
      " Selvedge.Kernel.Commands.command_declarations (DeclareCommand KernelChange TaskExcluded (WireCommand """" [])))."]);
    line (concat ["Definition "; name; "_payload := CommandPayload.t "; name; "_schema "; name; "_input_declaration true."]);
    line (concat ["Definition "; name; "_proposal := CommandPayload.t "; name; "_schema "; name; "_input_declaration false."]);
    line (concat ["Definition Build_"; name; " "; join " " (map (fun field => concat ["(proposed_"; getter_name name field; " : "; field_type_source field; ")"]) declarations);
      " : "; name; "_proposal := CommandPayload.propose ";
      fold_right (fun field rest => concat ["(@FCons ("; field_source field; ") _ proposed_"; getter_name name field; " "; rest; ")"])
        "FNil" declarations; "."]);
    line (concat ["Definition Admit_"; name; " := @CommandPayload.admit "; name; "_schema "; name; "_input_declaration."]);
    concat (map (fun item => concat [
      line (concat ["Definition "; admitted_getter_name name (snd item); " (payload : "; name; "_payload) := let values := proj1_sig (CommandPayload.values payload) in "; argument_reference (fst item); "."]);
      line (concat ["Definition "; getter_name name (snd item); " (payload : "; name; "_payload) := ArgumentProjection.field ("; field_source (snd item);
        ") (List.nth "; show_nat (S (fst item)); " "; name;
        "_input_declaration (Arguments.Argument """" (Arguments.Scalar KJson) false """")) eq_refl (";
        admitted_getter_name name (snd item); " payload)."])
      ]) (indexed 0 declarations))
  ].
Definition command_chunks (commands : list command_spec) : list String.string :=
  [line "Inductive command_value (admitted : bool) : Type :="] ++
  map (fun command => line (concat ["| Cmd_"; command_name command;
    " (payload : CommandPayload.t "; command_name command; "_schema "; command_name command; "_input_declaration admitted)"])) commands ++
  [line "."] ++
  map (fun command => line (concat ["Arguments Cmd_"; command_name command; " {admitted}."])) commands ++
  [line "Definition command := command_value true.";
   line "Definition proposal := command_value false.";
   line "(** The generated interpretation consumes admitted fields directly. Its field";
   line "    projections must typecheck against the owning declaration. *)";
   line "Definition command_interpretations : CommandDeclarations.interpretations true Selvedge.Kernel.Commands.command_declarations command :=";
   line (fold_right (fun command rest => concat ["((fun arguments => Cmd_"; command_name command;
     " (Admit_"; command_name command; " arguments)), ";rest;")"]) "tt" commands ++ ".");
   line "Definition admitted_command := CommandDeclarations.observed_command.";
   line "Definition admit := CommandDeclarations.admit_observed.";
   line "Definition admitted_value := CommandDeclarations.interpret true Selvedge.Kernel.Commands.command_declarations command_interpretations.";
   line "Definition decode (source : json) : option command := option_map admitted_value (admit source).";
   line "Theorem admit_projects_decode : forall source, option_map admitted_value (admit source) = decode source.";
   line "Proof. reflexivity. Qed.";
   line "Definition declared_command {admitted} (value : command_value admitted) : command_spec := match value with"] ++
  map (fun item => line (concat ["| Cmd_"; command_name (snd item);
    " _ => List.nth "; show_nat (fst item); " Selvedge.Kernel.Commands.command_specs (Command """" [])"])) (indexed 0 commands) ++
  [line "end.";
   line "Definition encode {admitted} (value : command_value admitted) : json := match value with"] ++
  map (fun item => line (concat ["| Cmd_"; command_name (snd item); " payload => CommandPayload.encode (List.nth "; show_nat (fst item); " Selvedge.Kernel.Commands.command_specs (Command """" [])) payload"])) (indexed 0 commands) ++
  [line "end.";
   line "Record handler_table (A : Type) := Handlers {"] ++
  map (fun command => line (concat [" handle_"; command_name command; " : "; command_name command; "_payload -> A;"])) commands ++
  [line "}."; line "Arguments Handlers {A}."] ++
  map (fun command => line (concat ["Arguments handle_"; command_name command; " {A}."])) commands ++
  [line "Definition dispatch {A : Type} (handlers : handler_table A) (value : command) : A := match value with"] ++
  map (fun command => line (concat ["| Cmd_"; command_name command; " payload => handle_"; command_name command; " handlers payload"])) commands ++
  [line "end."].

Fixpoint emit_chunks (chunks : list String.string) : TemplateMonad unit :=
  match chunks with
  | [] => tmReturn tt
  | chunk :: rest =>
      text <- tmEval lazy (bytestring.String.of_string chunk) ;;
      tmMsg text ;;
      emit_chunks rest
  end.

Fixpoint emit_payloads (commands : list (nat * command_spec)) : TemplateMonad unit :=
  match commands with
  | [] => tmReturn tt
  | (index, command) :: rest =>
      text <- tmEval lazy (bytestring.String.of_string (payload_source index command)) ;;
      tmMsg text ;;
      emit_payloads rest
  end.

(** Read the actual declaration through Template Rocq, then emit a standalone
    Gallina module. It is checked again without importing this metaprogram. *)
Definition generate_commands : TemplateMonad unit :=
  quoted <- tmQuote Selvedge.Kernel.Commands.command_specs ;;
  match quoted with
  | tConst name _ =>
      declaration <- tmQuoteConstant name false ;;
      match declaration.(cst_body) with
      | Some body =>
          commands <- tmUnquoteTyped (list command_spec) body ;;
          commands <- tmEval all commands ;;
          tmMsg (bytestring.String.of_string "SELVDERIVE_BEGIN") ;;
          tmMsg (bytestring.String.of_string (concat [line "From Stdlib Require Import String List.";
            line "From Selvedge.Foundation Require Import Json.";
            line "From Selvedge.Programming Require Import Schema Arguments ArgumentProjection CommandPayload.";
            line "From Selvedge.Kernel Require Import Commands CommandDeclarations.";
            line "Import ListNotations."; line "Open Scope string_scope."])) ;;
          emit_payloads (indexed 0 commands) ;;
          emit_chunks (command_chunks commands) ;;
          tmMsg (bytestring.String.of_string "SELVDERIVE_END")
      | None => tmFail (bytestring.String.of_string "Command declaration has no executable body")
      end
  | _ => tmFail (bytestring.String.of_string "Command declaration must be a constant")
  end.
MetaRocq Run generate_commands.
