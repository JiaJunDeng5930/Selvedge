From Stdlib Require Import String Ascii List Bool.
From Selvedge.Kernel Require Import Domain AccountNamespace.
Open Scope string_scope.
Definition codex_auto_review_model := "codex-auto-review".
Definition is_codex_auto_review (value : profile) :=
 String.eqb (profile_provider value) "chatgpt" && String.eqb (profile_model value) codex_auto_review_model.

Definition account_prefix := AccountNamespace.prefix.
Definition hash_digit := AccountNamespace.hex_digit.
Definition chatgpt_account_hash_digits := AccountNamespace.hash_digits.
Definition chatgpt_account_profile_key := AccountNamespace.is_profile_key.
Definition generated_account_prefix (value : string) :=
 if chatgpt_account_profile_key value then String.substring 0 (String.length AccountNamespace.prefix + AccountNamespace.hash_width + 1) value else "".
Definition valid_reviewer_profile (value : profile) :=
 negb (String.eqb (profile_reasoning value) "auto") &&
 match profile_policy value with
 | AdaptivePolicy _ => false
 | FixedReasoning => match profile_reasoning_options value with
   | nil => negb (String.eqb (profile_reasoning value) "")
   | options => List.existsb (String.eqb (profile_reasoning value)) options end end.
Definition default_reviewer (value : profile) (catalog : list profile) :=
 if String.eqb (profile_provider value) "chatgpt" then
 let fallback := if chatgpt_account_profile_key (Domain.profile_key value) then
  match List.find (fun candidate => String.eqb (Domain.profile_key candidate)
    (String.append (String.substring 0 (String.length AccountNamespace.prefix + AccountNamespace.hash_width + 1) (Domain.profile_key value)) codex_auto_review_model)) catalog with
  | Some candidate => if is_codex_auto_review candidate && valid_reviewer_profile candidate then candidate else value
  | None => value end else value in
 let prefix := AccountNamespace.reviewer_prefix (Domain.profile_key value) in
 match List.find (fun candidate =>
   let suffix := String.substring (String.length prefix) (String.length (Domain.profile_key candidate)) (Domain.profile_key candidate) in
   String.prefix prefix (Domain.profile_key candidate) && AccountNamespace.hash_valid suffix && is_codex_auto_review candidate && valid_reviewer_profile candidate) catalog with
 | Some reviewer => reviewer | None => fallback end
 else value.
