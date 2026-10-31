From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs.
From Selvedge.Kernel Require Import DeferredCommit.
From Selvedge.Features Require Import Chatgpt.

Definition input (decoded : option Inputs.input) : option Commands.chatgpt_exec_payload :=
 match decoded with
 | Some (UserCommand (Commands.Cmd_chatgpt_exec request)) => Some request
 | _ => None end.
Definition candidate (request : Commands.chatgpt_exec_payload) (before : world) :=
 DeferredCommit.continue_result before (Chatgpt.handle_chatgpt_exec_result request None before).
Definition packet (request : Commands.chatgpt_exec_payload) (raw : json) (before : world) :=
 DeferredCommit.packet (Some (UserCommand (Commands.Cmd_chatgpt_exec request))) before
  (candidate request before).
