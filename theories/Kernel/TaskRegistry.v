From Stdlib Require Import List NArith Bool Sorting.Mergesort.
From Selvedge.Foundation Require IndexedRegistry IndexedRegistryProofs.
From Selvedge.Foundation Require Utf8.
From Selvedge.Kernel Require Import Domain.
From Selvedge.Kernel Require Runnable WorkspaceUses.
Import ListNotations.
Open Scope N_scope.

Module Slots := IndexedRegistry.Slots.
Definition key := IndexedRegistry.key.

Definition active_candidate (value : task) :=
 task_busy value || match task_queued value with [] => false | _ => true end.

Definition side_candidate (value : task) :=
 match task_side_parent value with Some _ => negb (task_archived value) | None => false end.

Definition notification_candidate (value : task) :=
 match contract_plugins (task_contract value) with [] => false | _ => true end.

Definition title_candidate (issued : Slots.t unit) (id : N) (value : task) :=
 match Slots.find (key id) issued with
 | Some _ => false
 | None => negb (task_archived value) && Utf8.nonblank (first_request (task_history value)) end.

Definition index_at (id : N) (source : Slots.t task) := Slots.find (key id) source.
Definition eligible (accepts : task -> bool) (value : option task) :=
 match value with Some current => if accepts current then value else None | None => None end.

Definition agrees (accepts : task -> bool) (rows : IndexedRegistry.t task) (scope : Slots.t task) :=
 forall id, index_at id scope = eligible accepts (IndexedRegistry.lookup id rows).

Record t := Registry {
 rows : IndexedRegistry.t task;
 active : Slots.t task;
 runnable : Slots.t task;
 side_conversations : Slots.t task;
 notification_recipients : Slots.t task;
 issued_titles : Slots.t unit;
 title_requests : Slots.t task;
 workspace_uses : WorkspaceUses.t;
 active_agrees : agrees active_candidate rows active;
 runnable_agrees : agrees Runnable.candidate rows runnable;
 side_conversations_agree : agrees side_candidate rows side_conversations;
 notification_recipients_agree : agrees notification_candidate rows notification_recipients;
 title_requests_agree : forall id, index_at id title_requests =
   eligible (title_candidate issued_titles id) (IndexedRegistry.lookup id rows);
 workspace_uses_agree : WorkspaceUses.agrees rows workspace_uses
}.

Lemma empty_scope_agrees accepts : agrees accepts IndexedRegistry.empty (Slots.empty task).
Proof. intros id. unfold index_at, IndexedRegistry.lookup. cbn [IndexedRegistry.empty IndexedRegistry.entries].
 now rewrite !Slots.gempty. Qed.

Definition empty_with_issued_titles issued : t :=
 Registry IndexedRegistry.empty (Slots.empty task) (Slots.empty task) (Slots.empty task) (Slots.empty task)
  issued (Slots.empty task) WorkspaceUses.empty
  (empty_scope_agrees active_candidate) (empty_scope_agrees Runnable.candidate)
  (empty_scope_agrees side_candidate)
  (empty_scope_agrees notification_candidate) (fun id => empty_scope_agrees (title_candidate issued id) id) WorkspaceUses.empty_agrees.
Definition empty := empty_with_issued_titles (Slots.empty unit).

Definition index_task (accepts : task -> bool) id current (scope : Slots.t task) :=
 if accepts current then Slots.add (key id) current scope else
 match index_at id scope with None => scope | Some _ => Slots.remove (key id) scope end.
Lemma index_task_at accepts id current scope :
 index_at id (index_task accepts id current scope) = eligible accepts (Some current).
Proof.
 unfold index_task, eligible, index_at; destruct (accepts current).
 - apply Slots.gss.
 - destruct (Slots.find (key id) scope) eqn:Found; [apply Slots.grs|exact Found].
Qed.
Lemma index_task_at_other accepts id current scope other :
 id <> other -> index_at other (index_task accepts id current scope) = index_at other scope.
Proof.
 intros Different. assert (Distinguished : key other <> key id).
 { intros Same; apply Different; symmetry; now apply IndexedRegistry.key_injective. }
 unfold index_task, index_at. destruct (accepts current).
 - now apply Slots.gso.
 - destruct (Slots.find (key id) scope); [now apply Slots.gro|reflexivity].
Qed.

Definition replace_if_present (id : N) (current : task) (table : t) : t.
Proof.
 destruct (N.ltb_spec0 id (IndexedRegistry.next (rows table))) as [Present|]; [|exact table].
 refine (Registry (IndexedRegistry.put id current (rows table))
  (index_task active_candidate id current (active table))
  (index_task Runnable.candidate id current (runnable table))
  (index_task side_candidate id current (side_conversations table))
  (index_task notification_candidate id current (notification_recipients table))
  (issued_titles table) (index_task (title_candidate (issued_titles table) id) id current (title_requests table))
  (WorkspaceUses.replace_task id (IndexedRegistry.lookup id (rows table)) current (workspace_uses table)) _ _ _ _ _
  (WorkspaceUses.replace_agrees _ _ _ _ (workspace_uses_agree table) Present)).
 all: intros other; destruct (N.eq_dec id other) as [Same|Different].
 all: try (subst other; rewrite index_task_at, IndexedRegistryProofs.lookup_put_present by exact Present; reflexivity).
 all: rewrite index_task_at_other, IndexedRegistryProofs.lookup_put_other by exact Different.
 - apply active_agrees.
 - apply runnable_agrees.
 - apply side_conversations_agree.
 - apply notification_recipients_agree.
 - apply title_requests_agree.
Defined.

Definition append (current : task) (table : t) : t.
Proof.
 pose (id := IndexedRegistry.next (rows table)).
 refine (Registry (IndexedRegistry.append current (rows table))
  (index_task active_candidate id current (active table))
  (index_task Runnable.candidate id current (runnable table))
  (index_task side_candidate id current (side_conversations table))
  (index_task notification_candidate id current (notification_recipients table))
  (issued_titles table) (index_task (title_candidate (issued_titles table) id) id current (title_requests table))
  (WorkspaceUses.update true id (WorkspaceUses.task_addresses current) (workspace_uses table)) _ _ _ _ _
  (WorkspaceUses.append_agrees _ _ _ (workspace_uses_agree table))).
 all: intros other; destruct (N.eq_dec id other) as [Same|Different].
 all: try (subst other; unfold id; rewrite index_task_at, IndexedRegistryProofs.lookup_append_new; reflexivity).
 all: rewrite index_task_at_other by exact Different.
 all: rewrite IndexedRegistryProofs.lookup_append_before by (fold id; intros Same; apply Different; symmetry; exact Same).
 - apply active_agrees.
 - apply runnable_agrees.
 - apply side_conversations_agree.
 - apply notification_recipients_agree.
 - apply title_requests_agree.
Defined.

Definition title_started (id : N) (table : t) : t.
Proof.
 refine (Registry (rows table) (active table) (runnable table) (side_conversations table) (notification_recipients table)
   (Slots.add (key id) tt (issued_titles table)) (Slots.remove (key id) (title_requests table)) (workspace_uses table)
   (active_agrees table) (runnable_agrees table)
   (side_conversations_agree table) (notification_recipients_agree table) _ (workspace_uses_agree table)).
 intro other. unfold index_at, title_candidate.
 destruct (N.eq_dec id other) as [Same|Different].
 - subst other. rewrite Slots.grs, Slots.gss. now destruct (IndexedRegistry.lookup id (rows table)).
 - assert (Address : key other <> key id).
   { intro Same; apply Different; symmetry; now apply IndexedRegistry.key_injective. }
   rewrite Slots.gro, Slots.gso by exact Address. apply title_requests_agree.
Defined.

Definition extend (tasks : list task) (table : t) :=
 fold_left (fun current task => append task current) tasks table.
Definition from_list (tasks : list task) := extend tasks empty.

Lemma rows_replace id task table :
 rows (replace_if_present id task table) = IndexedRegistry.put id task (rows table).
Proof.
 unfold replace_if_present. destruct (N.ltb_spec0 id (IndexedRegistry.next (rows table))) as [|Absent].
 - reflexivity.
 - unfold IndexedRegistry.put. destruct (N.ltb_spec0 id (IndexedRegistry.next (rows table)));
     [contradiction|reflexivity].
Qed.

Lemma rows_extend tasks table : rows (extend tasks table) = IndexedRegistry.extend tasks (rows table).
Proof.
 revert table. induction tasks as [|task rest IH]; intro table; [reflexivity|].
 change (rows (extend rest (append task table)) =
   IndexedRegistry.extend rest (IndexedRegistry.append task (rows table))).
 now rewrite IH.
Qed.

Module IdentityOrder.
 Definition t := (N * task)%type.
 Definition leb (left right : t) := N.leb (fst left) (fst right).
 Lemma leb_total : forall left right, leb left right = true \/ leb right left = true.
 Proof.
  intros left right. unfold leb. destruct (N.le_ge_cases (fst left) (fst right));
   [left|right]; now apply N.leb_le.
 Qed.
End IdentityOrder.
Module Ordered := Mergesort.Sort IdentityOrder.

Definition selected_entries (scope : Slots.t task) :=
 Ordered.sort (map (fun '(address,current) => (N.pred (N.pos address), current)) (Slots.elements scope)).
