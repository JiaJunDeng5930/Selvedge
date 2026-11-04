From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Host Require Import RemoteRelaySession.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Theorem host_frame_admission_matches_negotiation current frame :
 frame_allowed current frame = true <->
 match current with
 | Negotiating _ => frame = RP.HostHello
 | AwaitingGrants _ | Ready _ _ => True
 | _ => False end.
Proof.
 destruct current,frame; cbn; split; intros; try discriminate; tauto.
Qed.

Lemma consumed_digest_absent digest tickets :
 find (fun entry=>String.eqb (ticket_digest entry) digest)
 (filter (fun entry=>negb (String.eqb (ticket_digest entry) digest)) tickets) = None.
Proof.
 induction tickets as [|entry rest IH]; cbn; auto.
 destruct (String.eqb (ticket_digest entry) digest) eqn:Same; cbn; auto.
 now rewrite Same.
Qed.

Definition tickets_of current := match current with Ready _ tickets=>tickets|_=>nil end.

(** Only a successfully consumed credential can authorize a connection; removing
    it before socket acceptance makes that authorization single-use. *)
Theorem successful_consumption_removes_ticket current now grants digest count authority :
 snd (step current (ConsumeTicket now grants digest count)) = TicketConsumed authority ->
 find (fun entry=>String.eqb (ticket_digest entry) digest)
 (tickets_of (fst (step current (ConsumeTicket now grants digest count)))) = None.
Proof.
 destruct current as [g|g|host|host tickets|connection|]; unfold step; cbn [fst snd]; try discriminate.
 destruct (find (fun entry=>String.eqb (ticket_digest entry) digest) tickets) as [selected|];
   [|discriminate].
 destruct (current_ticket now grants selected), (count <? 32); cbn [fst snd tickets_of]; try discriminate.
 intro Consumed. apply consumed_digest_absent.
Qed.

Definition current_authority grants authority : Prop :=
 exists issued, In issued (RP.grant_values grants) /\
 RP.authority_controller issued = RP.authority_controller authority /\
 RP.authority_epoch issued = RP.authority_epoch authority.

Lemma granted_is_current_authority grants authority :
 granted grants authority = true <-> current_authority grants authority.
Proof.
 unfold granted,current_authority. rewrite existsb_exists.
 split; intros [issued [Present Same]]; exists issued; split; [exact Present| |exact Present|].
 - unfold same_grant, RP.same_authority in Same. apply andb_true_iff in Same as [Controller Epoch].
   split; [now apply String.eqb_eq|now apply N.eqb_eq].
 - destruct Same as [Controller Epoch]. unfold same_grant, RP.same_authority.
   rewrite Controller,Epoch,String.eqb_refl,N.eqb_refl. reflexivity.
Qed.

Lemma current_ticket_is_current_authority now grants value :
 current_ticket now grants value = true <->
 now < ticket_expiry value /\ current_authority grants (ticket_grant value).
Proof.
 unfold current_ticket. rewrite andb_true_iff,N.ltb_lt,granted_is_current_authority. reflexivity.
Qed.

Theorem delivery_admits_exactly_current_authority current expected grants host_ready :
 can_deliver current expected grants host_ready = true <->
 exists connection, current = Controller connection /\ host_ready = true /\
 controller_generation connection = expected /\ current_authority grants (connection_grant connection).
Proof.
 destruct current as [g|g|host|host tickets|connection|]; unfold can_deliver; cbn;
 try rewrite andb_false_r;
 try solve [split; [discriminate|intros [other [Impossible _]]; discriminate]].
 rewrite !andb_true_iff,N.eqb_eq,granted_is_current_authority.
 split.
 - intro Allowed. exists connection. auto.
 - intros [other [Same Allowed]]. injection Same as Same. now subst other.
Qed.

Theorem ticket_issuance_admits_exactly_current_bounded_authority current now grants value :
 snd (step current (IssueTicket now grants value)) = TicketIssued <->
 exists host tickets, current = Ready host tickets /\
 N.of_nat (List.length (filter (fun entry => now <? ticket_expiry entry) tickets)) < 8 /\
 now < ticket_expiry value /\ current_authority grants (ticket_grant value).
Proof.
 destruct current as [g|g|host|host tickets|connection|]; unfold step; cbn [snd];
 try solve [split; [discriminate|intros [other [entries [Impossible _]]]; discriminate]].
 set (live := filter (fun entry => now <? ticket_expiry entry) tickets).
 assert (Issued : (if (N.of_nat (List.length live) <? 8) && current_ticket now grants value
     then TicketIssued else TicketRejected (if current_ticket now grants value then TicketLimit else HostOffline)) = TicketIssued <->
     (N.of_nat (List.length live) <? 8) && current_ticket now grants value = true).
 { destruct ((N.of_nat (List.length live) <? 8) && current_ticket now grants value);
   split; intros; try reflexivity; discriminate. }
 rewrite Issued,andb_true_iff,N.ltb_lt,current_ticket_is_current_authority.
 unfold live.
 split.
 - intro Allowed. exists host,tickets. auto.
 - intros [other [entries [Same Allowed]]]. injection Same as Host Entries. now subst other entries.
Qed.

Theorem issued_tickets_respect_capacity current now grants value next :
 step current (IssueTicket now grants value) = (next,TicketIssued) ->
 exists host tickets, next = Ready host tickets /\ N.of_nat (List.length tickets) <= 8.
Proof.
 destruct current as [g|g|host|host tickets|connection|]; unfold step; cbn beta iota zeta; try discriminate.
 set (live := filter (fun entry => now <? ticket_expiry entry) tickets).
 destruct ((N.of_nat (List.length live) <? 8) && current_ticket now grants value) eqn:Allowed;
   cbn beta iota zeta; try discriminate.
 intro Issued. injection Issued as Next. subst next.
 exists host,(live ++ [value]). split; [reflexivity|].
 apply andb_true_iff in Allowed as [Space _]. apply N.ltb_lt in Space.
 rewrite length_app,Nat2N.inj_add.
 change (N.of_nat (List.length live) + 1 <= 8). lia.
Qed.

Theorem ticket_consumption_admits_exactly_current_bounded_authority current now grants digest count authority :
 snd (step current (ConsumeTicket now grants digest count)) = TicketConsumed authority <->
 exists host tickets selected, current = Ready host tickets /\
 find (fun entry => String.eqb (ticket_digest entry) digest) tickets = Some selected /\
 now < ticket_expiry selected /\ current_authority grants (ticket_grant selected) /\
 count < 32 /\ ticket_grant selected = authority.
Proof.
 destruct current as [g|g|host|host tickets|connection|]; unfold step; cbn [snd];
 try solve [split; [discriminate|intros [other [entries [selected [Impossible _]]]]; discriminate]].
 destruct (find (fun entry => String.eqb (ticket_digest entry) digest) tickets) as [chosen|] eqn:Selected;
   cbn [snd].
 - assert (Consumed : snd (if current_ticket now grants chosen then
       if count <? 32 then
         (Ready host (filter (fun entry=>negb (String.eqb (ticket_digest entry) digest)) tickets),
          TicketConsumed (ticket_grant chosen))
       else (Ready host tickets,TicketRejected ConnectionLimit)
       else (Ready host tickets,TicketRejected InvalidTicket)) = TicketConsumed authority <->
       current_ticket now grants chosen = true /\ (count <? 32) = true /\ ticket_grant chosen = authority).
   { split.
     - destruct (current_ticket now grants chosen) eqn:Current; [|discriminate].
       destruct (count <? 32) eqn:Capacity; [|discriminate].
       intro Consumed. injection Consumed as Same. auto.
     - intros [Current [Capacity Same]]. now rewrite Current,Capacity,Same. }
   rewrite Consumed,current_ticket_is_current_authority,N.ltb_lt.
   split.
   + intros [[Fresh Authorized] [Capacity Same]].
     exists host,tickets,chosen. repeat split; assumption || reflexivity.
   + intros [other [entries [selected [Same [Found [Fresh [Authorized [Capacity Grant]]]]]]]].
     injection Same as Host Entries. subst other entries. rewrite Selected in Found.
     injection Found as Chosen. subst selected. auto.
 - split; [discriminate|].
   intros [other [entries [selected [Same [Found _]]]]].
   injection Same as Host Entries. subst other entries. rewrite Selected in Found. discriminate.
Qed.

Theorem replaced_pairing_cannot_be_delivered current now revision expiry :
 (match pairing_of current with
 | Some previous=>N.eqb previous.(pairing_revision) revision | None=>false end) = false ->
 snd (step current (DeliverPairing now revision expiry)) = Decision Deny.
Proof. destruct current; cbn; intro stale; try reflexivity; now rewrite stale. Qed.

Theorem replaced_hash_cannot_install_pairing current now revision value :
 (match pairing_of current with
 | Some previous=>N.eqb previous.(pairing_revision) revision | None=>false end) = false ->
 step current (InstallPairing now revision value) = (current,Decision Deny).
Proof. destruct current; cbn; intro stale; try reflexivity; now rewrite stale. Qed.
