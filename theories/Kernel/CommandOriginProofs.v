From Stdlib Require Import List NArith.
From Selvedge.Kernel Require Import State Tasks CommandHandlers.
Module G := Selvedge.Generated.Commands.
Module D := Selvedge.Kernel.Commands.

Theorem task_excluded_commands_are_read_only_rejections_at_every_handler_entry :
 forall command caller invocation before,
 D.task_command_allowed (Selvedge.Programming.Schema.command_name (G.declared_command command)) = false ->
 CommandHandlers.query command (Some caller) before = Some CommandHandlers.origin_failure /\
 CommandHandlers.execute command (Some invocation) before =
   Decision before CommandHandlers.origin_failure nil.
Proof.
 intros command caller invocation before excluded.
 unfold CommandHandlers.query, CommandHandlers.execute, CommandHandlers.interpret,
   CommandHandlers.task_origin, D.origin_allowed.
 rewrite excluded;split;reflexivity.
Qed.
