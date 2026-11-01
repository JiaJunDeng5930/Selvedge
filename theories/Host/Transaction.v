From Stdlib Require Import List Bool.
Import ListNotations.

Inductive state := Idle | KernelPending | CommitPending | Committed | Retired.
Definition initial := Idle.
Inductive observation :=
| Begin | WorkerResult (durable : bool)
| InputRejected | WorkerFailed | CommitAck | CommitRejected
| CommitUnknown | Finish.
Inductive primitive := Commit | Publish | Resolve | RejectDefinite | RejectUnknown | Retire.
Definition step (s : state) (o : observation) : state * list primitive :=
  match o with
  | Begin =>
      match s with
      | Idle => (KernelPending, [])
      | _ => (s, [RejectDefinite])
      end
  | WorkerResult durable =>
      match s with
      | KernelPending => if durable then (CommitPending, [Commit])
          else (Committed, [Resolve])
      | _ => (s, []) end
  | InputRejected =>
      match s with
      | KernelPending => (Idle, [RejectDefinite])
      | _ => (s, [])
      end
  | CommitAck =>
      match s with
      | CommitPending => (Committed, [Publish; Resolve])
      | _ => (s, [])
      end
  | Finish =>
      match s with
      | Committed => (Idle, [])
      | _ => (s, [])
      end
  | CommitRejected => (Retired, [RejectDefinite; Retire])
  | CommitUnknown => (Retired, [RejectUnknown; Retire])
  | WorkerFailed => (Retired, [RejectDefinite; Retire])
  end.

Theorem publication_requires_commit_ack s o :
  In Publish (snd (step s o)) -> o = CommitAck /\ s = CommitPending.
Proof.
  destruct s; destruct o;
    repeat match goal with b : bool |- _ => destruct b end;
    simpl; intuition discriminate.
Qed.
