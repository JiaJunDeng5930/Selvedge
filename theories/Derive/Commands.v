From Stdlib Require Import String List Ascii.
From MetaRocq.Template Require Import All.
From Selvedge.Foundation Require Import Schema Numbers.
From Selvedge.Kernel Require Import Commands.
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
Definition field_reference (index : nat) :=
  append "(head " (append (Nat.iter index (fun x => append "(tail " (append x ")")) "values") ")").
Definition payload_source (index : nat) (command : command_spec) : String.string :=
  let name := command_name command in
  let declarations := command_fields command in
  concat [
    line (concat ["Definition "; name; "_schema := command_fields (List.nth "; show_nat index;
      " Selvedge.Kernel.Commands.command_specs (Command """" []))."]);
    match declarations with
    | [] => line (concat ["Definition "; name; "_payload : Type := unit."])
    | _ => line (concat ["Record "; name; "_payload : Type := Build_"; name; " { ";
      join "; " (map (fun item => concat [getter_name name (snd item); " : "; field_type_source (snd item)])
      (indexed 0 declarations)); " }."])
    end;
    line (concat ["Definition "; name; "_from_fields (values : fields "; name; "_schema) : "; name; "_payload := ";
      match declarations with [] => "tt" | _ => concat ["Build_"; name; " ";
        join " " (map (fun item => field_reference (fst item)) (indexed 0 declarations))] end; "."]);
    line (concat ["Definition "; name; "_to_fields (payload : "; name; "_payload) : fields "; name; "_schema := ";
      fold_right (fun field rest => concat ["(@FCons ("; field_source field; ") _ ("; getter_name name field; " payload) "; rest; ")"])
        "FNil" declarations; "."]);
    line (concat ["Definition decode_"; name; " (source : json) : option "; name; "_payload := ";
      "option_map "; name; "_from_fields (Schema.decode "; name; "_schema source)."]);
    line (concat ["Definition encode_"; name; " (payload : "; name; "_payload) : json := ";
      "Schema.encode "; name; "_schema ("; name; "_to_fields payload)."])
  ].
Definition payload_laws_source (command : command_spec) :=
  let name := command_name command in
  concat ["| Cmd_"; name; " payload => "; name; "_schema = [";
    join "; " (map field_source (command_fields command)); "] /\ ";
    name; "_from_fields ("; name; "_to_fields payload) = payload /\ ";
    "Forall (fun link : (option json * option json)%type => fst link = snd link) [";
    join "; " (map (fun item => concat ["(lookup_field """; field_name (snd item);
      """ ("; name; "_to_fields payload), encode_field (List.nth "; show_nat (fst item);
      " "; name; "_schema (Field """" KJson)) ("; getter_name name (snd item); " payload))"])
      (indexed 0 (command_fields command))); "]"].
Definition command_chunks (commands : list command_spec) : list String.string :=
  [line "Inductive command : Type :="] ++
  map (fun command => line (concat ["| Cmd_"; command_name command;
    " (payload : "; command_name command; "_payload)"])) commands ++
  [line ".";
   line "(** The catalog checks each actual named getter, independently of the field encoder. *)";
   line "Definition payload_laws (value : command) : Prop := match value with"] ++
  map (fun command => line (payload_laws_source command)) commands ++
  [line "end.";
   line "Definition decode_named (name : string) (source : json) : option command :="] ++
  map (fun command => line (concat ["if String.eqb name """; command_name command;
    """ then option_map Cmd_"; command_name command; " (decode_"; command_name command; " source) else"])) commands ++
  [line "None.";
   line "Definition decode_admitted (source : json) : option command :=";
   line "match source with JObject values => if unique_names (source_keys values) then";
   line "match lookup ""op"" values with Some (JString name) => decode_named name (JObject (remove_field ""op"" values)) | _ => None end else None | _ => None end.";
   line "Definition decode (source : json) : option command :=";
   line "match CommandDeclarations.admit_observed source with";
   line "| Some admitted => decode_admitted (CommandDeclarations.observed_source admitted) | None => None end.";
   line "Lemma decode_observed_declaration : forall source, decode source = if CommandDeclarations.valid true source then decode_admitted source else None.";
   line "Proof. intro source; unfold decode, CommandDeclarations.admit_observed; destruct (Bool.bool_dec (CommandDeclarations.valid true source) true) as [Accepted | Rejected]; cbn [CommandDeclarations.observed_source]; [rewrite Accepted; reflexivity | destruct (CommandDeclarations.valid true source); [contradiction | reflexivity]]. Qed.";
   line "Record admitted_command := AdmittedCommand {";
   line " admitted_source : json;";
   line " admitted_value : command;";
   line " admitted_decoding : decode admitted_source = Some admitted_value";
   line "}.";
   line "Definition admit_decoded (source : json) (decoded : option command)";
   line " (Decoded : decode source = decoded) : option admitted_command :=";
   line " match decoded as result return decode source = result -> option admitted_command with";
   line " | Some value => fun Evidence => Some (AdmittedCommand source value Evidence)";
   line " | None => fun _ => None end Decoded.";
   line "Definition admit (source : json) : option admitted_command :=";
   line " admit_decoded source (decode source) eq_refl.";
   line "Theorem admit_decoded_projects : forall source decoded Decoded,";
   line " option_map admitted_value (admit_decoded source decoded Decoded) = decoded.";
   line "Proof. intros source [value|] Decoded; reflexivity. Qed.";
   line "Theorem admit_projects_decode : forall source,";
   line " option_map admitted_value (admit source) = decode source.";
   line "Proof. intro source; apply admit_decoded_projects. Qed.";
   line "Theorem admit_decoded_retains_source : forall source decoded Decoded admitted,";
   line " admit_decoded source decoded Decoded = Some admitted -> admitted_source admitted = source.";
   line "Proof. intros source [value|] Decoded admitted Accepted; inversion Accepted; reflexivity. Qed.";
   line "Theorem admission_retains_source : forall source admitted,";
   line " admit source = Some admitted -> admitted_source admitted = source.";
   line "Proof. intros source admitted Accepted; eapply admit_decoded_retains_source; exact Accepted. Qed.";
   line "Theorem admitted_command_has_complete_declaration : forall admitted,";
   line " CommandDeclarations.valid true (admitted_source admitted) = true.";
   line "Proof.";
   line " intros [source value Decoded]; cbn.";
   line " rewrite decode_observed_declaration in Decoded.";
   line " destruct (CommandDeclarations.valid true source); [reflexivity | discriminate].";
   line "Qed.";
   line "Definition declared_command (value : command) : command_spec := match value with"] ++
  map (fun item => line (concat ["| Cmd_"; command_name (snd item);
    " _ => List.nth "; show_nat (fst item); " Selvedge.Kernel.Commands.command_specs (Command """" [])"])) (indexed 0 commands) ++
  [line "end.";
   line "Definition declared_payload (value : command) : list (string * json) := match value with"] ++
  map (fun command => line (concat ["| Cmd_"; command_name command;
    " payload => encode_fields ("; command_name command; "_to_fields payload)"])) commands ++
  [line "end.";
   line "Definition encode (value : command) : json := match value with"] ++
  map (fun item => line (concat ["| Cmd_"; command_name (snd item); " payload => Schema.encode_declared (List.nth ";
    show_nat (fst item); " Selvedge.Kernel.Commands.command_specs (Command """" [])) ("; command_name (snd item); "_to_fields payload)"])) (indexed 0 commands) ++
  [line "end.";
   line "Theorem encode_declared_wire : forall value, encode value = JObject ((""op"", JString (command_name (declared_command value))) :: declared_payload value).";
   line "Proof. intros []; reflexivity. Qed.";
   line "Ltac command_payload_case handler := match goal with"] ++
  map (fun command => line (concat ["| [payload : "; command_name command;
    "_payload |- _] => handler "; command_name command; "_schema "; command_name command;
    "_to_fields "; command_name command; "_from_fields Cmd_"; command_name command; " payload"])) commands ++
  [line "end.";
   line "Ltac prove_payload_laws description to_fields from_fields constructor payload := destruct payload; cbn [payload_laws]; repeat constructor.";
   line "Theorem every_command_payload_has_its_declared_fields : forall value, payload_laws value.";
   line "Proof. intros []; command_payload_case prove_payload_laws. Qed.";
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
            line "From Selvedge.Foundation Require Import Json Schema.";
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
