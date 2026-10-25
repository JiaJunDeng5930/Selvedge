From Stdlib Require Import List Bool NArith.
Import ListNotations.
Open Scope N_scope.

Inductive phase := Idle | KernelPending | CommitPending | Committed | Retired.
Record state := State { current : phase; generation : N; replaying : bool }.
Definition initial := State Idle 0 false.
Inductive observation :=
| Begin (replay : bool) | WorkerResult (request : N) (durable : bool)
| InputRejected (request : N) | WorkerFailed | CommitAck | CommitRejected
| CommitUnknown | Finish | Close.
Inductive primitive := Request (request : N) | Replay (request : N)
| Commit | Publish | Resolve | RejectDefinite | RejectUnknown | Retire.
Definition step (s : state) (o : observation) : state * list primitive :=
  match o with
  | Begin replay =>
      match current s with
      | Idle => let next := N.succ (generation s) in
          (State KernelPending next replay, [if replay then Replay next else Request next])
      | _ => (s, [RejectDefinite])
      end
  | WorkerResult request durable =>
      match current s with
      | KernelPending =>
          if N.eqb request (generation s) then
            if durable && negb (replaying s) then
              (State CommitPending (generation s) false, [Commit])
            else (State Committed (generation s) (replaying s), [Resolve])
          else (s, [])
      | _ => (s, [])
      end
  | InputRejected request =>
      match current s with
      | KernelPending => if N.eqb request (generation s) then
          (State Idle (generation s) false, [RejectDefinite]) else (s, [])
      | _ => (s, [])
      end
  | CommitAck =>
      match current s with
      | CommitPending => if replaying s then (State Committed (generation s) true, [Resolve])
          else (State Committed (generation s) false, [Publish; Resolve])
      | _ => (s, [])
      end
  | Finish =>
      match current s with
      | Committed => (State Idle (generation s) false, [])
      | _ => (s, [])
      end
  | CommitRejected => (State Retired (generation s) (replaying s), [RejectDefinite; Retire])
  | CommitUnknown => (State Retired (generation s) (replaying s), [RejectUnknown; Retire])
  | WorkerFailed => (State Retired (generation s) (replaying s), [RejectDefinite; Retire])
  | Close => (State Retired (generation s) (replaying s), [Retire])
  end.

Theorem publication_requires_commit_ack s o :
  In Publish (snd (step s o)) -> o = CommitAck /\ current s = CommitPending.
Proof.
  destruct s as [p g r]; destruct o; destruct p;
    repeat match goal with b : bool |- _ => destruct b end;
    simpl; repeat match goal with |- context [N.eqb ?x ?y] => destruct (N.eqb x y) end;
    simpl; intuition discriminate.
Qed.
Theorem replay_result_never_publishes s request durable :
  ~ In Publish (snd (step s (WorkerResult request durable))).
Proof.
  destruct s as [p g r]; destruct p; simpl; try (destruct (N.eqb _ _));
    try (destruct (durable && negb r)); simpl; intuition discriminate.
Qed.

Theorem replay_never_publishes s o :
  replaying s = true -> ~ In Publish (snd (step s o)).
Proof.
  destruct s as [p g r]; simpl. intros ->. destruct o; destruct p;
    repeat match goal with b : bool |- _ => destruct b end;
    simpl; repeat match goal with |- context [N.eqb ?x ?y] => destruct (N.eqb x y) end;
    simpl; intuition discriminate.
Qed.
