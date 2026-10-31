From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Programming Require Import ArgumentDeclaration.
From Selvedge.Features Require Import Titles.
Open Scope string_scope.

Local Lemma string_append_length : forall first second,
 String.length (first ++ second) = (String.length first + String.length second)%nat.
Proof. induction first; cbn; intros; congruence. Qed.

Lemma bounded_title_chunks_obey_the_byte_budget : forall parts bytes,
 (N.of_nat (String.length (Titles.bounded parts bytes)) <= bytes)%N.
Proof.
 induction parts as [|[scalar chunk] rest IH]; intros bytes; cbn [Titles.bounded String.length]; [lia|].
 destruct (N.leb (N.of_nat (String.length chunk)) bytes) eqn:Fits; [|cbn [String.length]; lia].
 rewrite string_append_length, Nat2N.inj_add. specialize (IH (bytes - N.of_nat (String.length chunk))%N).
 apply N.leb_le in Fits; lia.
Qed.

Lemma a_title_prompt_obeys_the_declared_byte_bound : forall instruction request,
 (N.of_nat (String.length (Titles.prompt_with instruction request)) <=
  Titles.maximum_instruction_bytes + N.of_nat (String.length Titles.title_format) +
  (Titles.prompt_bytes - N.of_nat (String.length (Titles.instructions ++ Titles.title_format))))%N.
Proof.
 intros [instruction Valid] request.
 unfold Titles.prompt_with, Titles.instruction_text; cbn [proj1_sig].
 unfold ArgumentDeclaration.check_text in Valid.
 destruct (Utf8.scalar_count instruction) as [count|] eqn:Count; [|discriminate].
 cbn in Valid. repeat rewrite andb_true_iff in Valid.
 assert (Bytes : (N.of_nat (String.length instruction) <=? Titles.maximum_instruction_bytes)%N = true) by tauto.
 apply N.leb_le in Bytes.
 rewrite !string_append_length, !Nat2N.inj_add.
 destruct (Utf8.chunks request) as [chunks|] eqn:Chunks.
 - pose proof (bounded_title_chunks_obey_the_byte_budget
     (Titles.trim_both Utf8.whitespace chunks)
     (Titles.prompt_bytes - N.of_nat (String.length (Titles.instructions ++ Titles.title_format)))) as Bound.
   rewrite string_append_length, Nat2N.inj_add in Bound. lia.
 - cbn [String.length]. lia.
Qed.
