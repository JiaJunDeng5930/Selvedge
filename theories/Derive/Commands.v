From Stdlib Require Import String List Ascii.
From MetaRocq.Template Require Import All.
From Selvedge.Programming Require Import Schema CommandGeneration.
From Selvedge.Foundation Require Import Numbers.
From Selvedge.Programming Require Import ArgumentProjection.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Programming Require Import CommandDeclarations.
Import ListNotations MonadNotation.
Local Open Scope string_scope.

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
            line "From Selvedge.Programming Require Import Schema Arguments ArgumentProjection CommandPayload CommandFields.";
            line "From Selvedge.Kernel Require Import Commands.";
            line "From Selvedge.Programming Require Import CommandDeclarations.";
            line "Import ListNotations."; line "Open Scope string_scope."])) ;;
          emit_payloads (indexed 0 commands) ;;
          emit_chunks (command_chunks commands) ;;
          tmMsg (bytestring.String.of_string "SELVDERIVE_END")
      | None => tmFail (bytestring.String.of_string "Command declaration has no executable body")
      end
  | _ => tmFail (bytestring.String.of_string "Command declaration must be a constant")
  end.
MetaRocq Run generate_commands.
