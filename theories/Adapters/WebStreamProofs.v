From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Import Common WebStream.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem production_sse_scanner_is_independent_of_feed_boundaries : forall first second reversed bytes work maximum,
  WebStream.scan (List.app first second) reversed bytes work maximum =
    let '(next_reversed,next_bytes,next_work) := WebStream.scan first reversed bytes work maximum in
    WebStream.scan second next_reversed next_bytes next_work maximum.
Proof.
 intros;unfold WebStream.scan;rewrite fold_left_app.
 destruct (fold_left (WebStream.scan_character maximum) first (reversed,bytes,work)) as [[r b] w];reflexivity.
Qed.

Theorem production_sse_crlf_finishes_only_one_line : forall reversed bytes work maximum,
 WebStream.after_cr (WebStream.current work) = true -> WebStream.stream_error work = "" ->
 WebStream.scan_character maximum (reversed,bytes,work) (10,"
") = (reversed,bytes,WebStream.set_after_cr work false).
Proof.
 intros reversed bytes work maximum after_cr clean.
 unfold WebStream.scan_character;cbn [snd];rewrite clean,after_cr;reflexivity.
Qed.

Theorem production_sse_cr_finishes_the_line_without_waiting_for_another_chunk :
 forall reversed bytes work maximum,
 WebStream.stream_error work = "" ->
 let next := WebStream.set_after_cr
   (WebStream.process_line (string_of_list_ascii (rev_append reversed []))
     (WebStream.set_after_cr work false) maximum) true in
 WebStream.scan_character maximum (reversed,bytes,work) (13,WebStream.carriage_return) =
   if String.eqb (WebStream.stream_error next) "" then ([],0,next) else (reversed,bytes,next).
Proof.
 intros reversed bytes work maximum clean;cbv beta zeta.
 unfold WebStream.scan_character;cbn [snd];rewrite clean.
 cbn [WebStream.carriage_return String.eqb Ascii.eqb].
 now rewrite andb_false_r.
Qed.

(** The scanner carries a local byte count only while consuming a chunk.  Its
    relation to the actual reversed bytes lets the public result inherit the
    configured line limit without trusting a serialized counter. *)
Definition sse_buffer_within maximum (buffer : (list Ascii.ascii * N) * WebStream.stream_work) :=
 let '(reversed,bytes,work) := buffer in
 N.of_nat (List.length reversed) = bytes /\
 (WebStream.stream_error work = "" -> bytes <= maximum).
Local Lemma encoded_string_length : forall value,
 List.length (list_ascii_of_string value) = String.length value.
Proof. induction value;cbn;congruence. Qed.
Local Lemma decoded_string_length : forall bytes,
 String.length (string_of_list_ascii bytes) = List.length bytes.
Proof. induction bytes;cbn;congruence. Qed.
Local Lemma reversed_bytes_length : forall (bytes reversed : list Ascii.ascii),
 List.length (fold_left (fun result byte => byte :: result) bytes reversed) =
 (List.length bytes + List.length reversed)%nat.
Proof.
 induction bytes as [|byte bytes IH];intros reversed;cbn;[reflexivity|].
 rewrite IH;cbn;lia.
Qed.
Lemma sse_character_preserves_line_budget : forall maximum buffer character,
 sse_buffer_within maximum buffer ->
 sse_buffer_within maximum (WebStream.scan_character maximum buffer character).
Proof.
 intros maximum [[reversed bytes] work] [code character] [consistent bounded].
 unfold WebStream.scan_character;cbn.
 destruct (negb (String.eqb (WebStream.stream_error work) "")) eqn:failed.
 - split;assumption.
 - destruct (WebStream.after_cr (WebStream.current work) && String.eqb character "
") eqn:paired_lf.
   + unfold sse_buffer_within,WebStream.set_after_cr;cbn;split;assumption.
   + destruct (String.eqb character "
" || String.eqb character WebStream.carriage_return) eqn:newline.
     * destruct (String.eqb (WebStream.stream_error
       (WebStream.process_line (string_of_list_ascii (rev_append reversed []))
         (WebStream.set_after_cr work false) maximum)) "") eqn:accepted.
       -- split;[reflexivity|intros _;apply N.le_0_l].
       -- split;[exact consistent|intros empty;apply String.eqb_neq in accepted;contradiction].
     * destruct (bytes + N.of_nat (String.length character) <=? maximum) eqn:within;
       unfold sse_buffer_within,WebStream.set_after_cr;cbn;split.
       -- rewrite reversed_bytes_length,encoded_string_length,Nat2N.inj_add,consistent;apply N.add_comm.
       -- intros _;now apply N.leb_le in within.
       -- rewrite reversed_bytes_length,encoded_string_length,Nat2N.inj_add,consistent;apply N.add_comm.
       -- discriminate.
Qed.
Lemma sse_scan_preserves_line_budget : forall characters maximum reversed bytes work,
 sse_buffer_within maximum (reversed,bytes,work) ->
 sse_buffer_within maximum (WebStream.scan characters reversed bytes work maximum).
Proof.
 induction characters as [|character characters IH];intros maximum reversed bytes work within;[exact within|].
 unfold WebStream.scan;cbn [fold_left].
 destruct (WebStream.scan_character maximum (reversed,bytes,work) character) as [[next bytes'] work'] eqn:step.
 change (sse_buffer_within maximum (WebStream.scan characters next bytes' work' maximum)).
 apply IH;rewrite <- step;now apply sse_character_preserves_line_budget.
Qed.
Lemma sse_initial_line_budget : forall state maximum,
 let initial := WebStream.StreamWork state [] "" in
 let admitted := if N.of_nat (String.length (WebStream.pending state)) <=? maximum
   then initial else WebStream.stream_fail initial "SSE line exceeds the configured limit" in
 sse_buffer_within maximum
   (fold_left (fun result byte => byte :: result) (list_ascii_of_string (WebStream.pending state)) [],
    N.of_nat (String.length (WebStream.pending state)),admitted).
Proof.
 intros state maximum;unfold sse_buffer_within.
 destruct (N.of_nat (String.length (WebStream.pending state)) <=? maximum) eqn:within;cbn;split.
 - rewrite reversed_bytes_length,encoded_string_length,Nat.add_0_r;reflexivity.
 - intros _;now apply N.leb_le in within.
 - rewrite reversed_bytes_length,encoded_string_length,Nat.add_0_r;reflexivity.
 - discriminate.
Qed.

Theorem production_successful_sse_step_respects_line_byte_limit : forall state chunk maximum value,
 WebStream.sse_step state chunk false maximum = success value -> get value "error" = JNull ->
 N.of_nat (String.length (str (get value "state") "pending")) <= maximum.
Proof.
 intros state chunk maximum value accepted no_error.
 unfold WebStream.sse_step in accepted.
 destruct (Utf8.chunks chunk) as [characters|] eqn:characters_valid;[|discriminate].
 pose proof (sse_initial_line_budget state maximum) as initial.
 pose proof (sse_scan_preserves_line_budget characters _ _ _ _ initial) as scanned.
 destruct (WebStream.scan characters
   (fold_left (fun result byte => byte :: result) (list_ascii_of_string (WebStream.pending state)) [])
   (N.of_nat (String.length (WebStream.pending state)))
   (if N.of_nat (String.length (WebStream.pending state)) <=? maximum
     then WebStream.StreamWork state [] ""
     else WebStream.stream_fail (WebStream.StreamWork state [] "") "SSE line exceeds the configured limit")
   maximum) as [[reversed bytes] work] eqn:scan_result.
 unfold sse_buffer_within in scanned;destruct scanned as [consistent bounded].
 unfold WebStream.work_json in accepted;cbn in accepted.
 destruct (String.eqb (WebStream.stream_error work) "") eqn:empty_error.
 - apply String.eqb_eq in empty_error.
   inversion accepted;subst value;cbn.
   rewrite decoded_string_length,rev_append_rev,List.app_nil_r,length_rev,consistent.
   now apply bounded.
 - inversion accepted;subst value;discriminate no_error.
Qed.
