From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8.
Import ListNotations.
Open Scope string_scope.

Inductive phase := Starting | Running | Draining | Completed.
Inductive mode := Pipe | Pty.
Record failure := Failure { failure_code : string; failure_message : string }.
Record state := State {
  process_phase : phase;
  stdin_open : bool;
  write_busy : bool;
  output_drained : bool;
  process_reason : option failure
}.
Definition initial := State Starting true false false None.
Definition public_status (current : phase) :=
  match current with Starting => "starting" | Running | Draining => "running" | Completed => "completed" end.
Definition active (current : state) :=
  match current.(process_phase) with Completed => false | _ => true end.
Definition with_reason current reason :=
  State current.(process_phase) current.(stdin_open) current.(write_busy) current.(output_drained)
    (match current.(process_reason) with Some existing => Some existing | None => Some reason end).
Definition cancelled := Failure "cancelled" "The task was cancelled".
Inductive event := Started | ShellExited | OutputDrained | InputClosed | WriteFinished | Finished | Failed.
Definition observe (current : state) (input : event) :=
  match input with
  | Started => match current.(process_phase) with
    | Starting => State Running current.(stdin_open) current.(write_busy) current.(output_drained) current.(process_reason)
    | _ => current end
  | ShellExited => match current.(process_phase) with
    | Running => State Draining false current.(write_busy) current.(output_drained) current.(process_reason)
    | _ => current end
  | OutputDrained => State current.(process_phase) current.(stdin_open) current.(write_busy) true current.(process_reason)
  | InputClosed => State current.(process_phase) false current.(write_busy) current.(output_drained) current.(process_reason)
  | WriteFinished => State current.(process_phase) current.(stdin_open) false current.(output_drained) current.(process_reason)
  | Finished => match current.(process_phase),current.(output_drained) with
    | Draining,true => State Completed false current.(write_busy) true current.(process_reason)
    | _,_ => current end
  | Failed => State Completed false current.(write_busy) current.(output_drained) current.(process_reason)
  end.
Definition reserve_write (current : state) : failure + state :=
  if current.(write_busy) then inl (Failure "process_input_busy" "Another input write is still pending for this process")
  else inr (State current.(process_phase) current.(stdin_open) true current.(output_drained) current.(process_reason)).
Definition admit_write (current : state) (terminal : mode) (eof resize_cols resize_rows : bool) : option failure :=
  match current.(process_phase) with
  | Running =>
    if negb current.(stdin_open) then Some (Failure "process_stdin_closed" "The process input is closed")
    else if match terminal with Pty => eof | Pipe => false end
      then Some (Failure "process_input_invalid" "PTY input cannot be closed; send a terminal control character instead")
    else if match terminal with Pipe => resize_cols || resize_rows | Pty => false end
      then Some (Failure "process_input_invalid" "Pipe processes do not have a terminal size")
    else if xorb resize_cols resize_rows
      then Some (Failure "process_input_invalid" "Terminal columns and rows must be supplied together")
    else None
  | _ => Some (Failure "process_stdin_closed" "The process input is closed")
  end.

(** One scalar tail is shared by pipe and terminal observations. Cursors count
    all decoded scalars, including the prefix no longer retained in memory. *)
(** The IO decoder supplies scalar counts. The model returns exact slice
    instructions for the physical scalar buffer instead of copying its contents
    through the control ABI on every chunk. *)
Record tail := Tail { retained : nat; total : N }.
Definition empty_tail := Tail 0 0.
Definition keep_new capacity added := Nat.min capacity added.
Definition keep_old capacity current added := Nat.min current.(retained) (capacity - keep_new capacity added).
Definition append_tail capacity current added :=
  Tail (keep_old capacity current added + keep_new capacity added)
    (current.(total) + N.of_nat added).
Definition drop_old capacity current added := (current.(retained) - keep_old capacity current added)%nat.
Definition drop_new capacity added := (added - keep_new capacity added)%nat.
Definition tail_start current := (current.(total) - N.of_nat current.(retained))%N.
Definition read_start current cursor := N.max (N.min cursor current.(total)) (tail_start current).
Definition omitted current cursor := (tail_start current - N.min cursor current.(total))%N.
Definition read_offset current cursor := (read_start current cursor - tail_start current)%N.

Record registry_entry := Entry { entry_key : string; entry_mode : mode; entry_failure : option failure }.
Record registry := Registry { entries : list registry_entry; completed : list string }.
Definition empty_registry := Registry [] [].
Definition register current key terminal :=
  Registry (Entry key terminal None :: current.(entries)) current.(completed).
Definition lookup current key := find (fun entry => String.eqb entry.(entry_key) key) current.(entries).
Definition failed current key reason := Registry
  (map (fun entry => if String.eqb entry.(entry_key) key
     then Entry key entry.(entry_mode) (Some reason) else entry) current.(entries)) current.(completed).
Definition completion_queue current key := (current.(completed) ++ [key])%list.
Definition retired current key := firstn (List.length (completion_queue current key) - 64) (completion_queue current key).
Definition complete current key :=
  let old := retired current key in
  Registry (filter (fun entry => negb (existsb (String.eqb entry.(entry_key)) old)) current.(entries))
    (skipn (List.length (completion_queue current key) - 64) (completion_queue current key)).
