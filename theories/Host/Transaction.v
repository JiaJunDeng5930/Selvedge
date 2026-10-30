From Stdlib Require Import List Bool NArith.
Import ListNotations.
Open Scope N_scope.

Inductive phase := Idle | KernelPending | ReplayPending | CommitPending | Committed | Retired.
Record state := State { current : phase; generation : N }.
Definition initial := State Idle 0.
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
          (State (if replay then ReplayPending else KernelPending) next,
            [if replay then Replay next else Request next])
      | _ => (s, [RejectDefinite])
      end
  | WorkerResult request durable =>
      if N.eqb request (generation s) then
        match current s with
        | KernelPending => if durable then (State CommitPending (generation s), [Commit])
            else (State Committed (generation s), [Resolve])
        | ReplayPending => (State Committed (generation s), [Resolve])
        | _ => (s, []) end
      else (s, [])
  | InputRejected request =>
      match current s with
      | KernelPending | ReplayPending => if N.eqb request (generation s) then
          (State Idle (generation s), [RejectDefinite]) else (s, [])
      | _ => (s, [])
      end
  | CommitAck =>
      match current s with
      | CommitPending => (State Committed (generation s), [Publish; Resolve])
      | _ => (s, [])
      end
  | Finish =>
      match current s with
      | Committed => (State Idle (generation s), [])
      | _ => (s, [])
      end
  | CommitRejected => (State Retired (generation s), [RejectDefinite; Retire])
  | CommitUnknown => (State Retired (generation s), [RejectUnknown; Retire])
  | WorkerFailed => (State Retired (generation s), [RejectDefinite; Retire])
  | Close => (State Retired (generation s), [Retire])
  end.

Theorem publication_requires_commit_ack s o :
  In Publish (snd (step s o)) -> o = CommitAck /\ current s = CommitPending.
Proof.
  destruct s as [p g]; destruct o; destruct p;
    repeat match goal with b : bool |- _ => destruct b end;
    simpl; repeat match goal with |- context [N.eqb ?x ?y] => destruct (N.eqb x y) end;
    simpl; intuition discriminate.
Qed.
