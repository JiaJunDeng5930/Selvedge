From Stdlib Require Import String List Bool Ascii.
Import ListNotations.
Open Scope string_scope.

Definition prefix := "chatgpt/".
Definition hash_width : nat := 16.
Definition hex_digit character := let code := nat_of_ascii character in
  (Nat.leb 48 code && Nat.leb code 57) || (Nat.leb 97 code && Nat.leb code 102).
Definition hash_digits value := forallb hex_digit (list_ascii_of_string value).
Definition hash_valid value := Nat.eqb (String.length value) hash_width && hash_digits value.
Definition make hash := prefix ++ hash.
Definition is_namespace value := String.prefix prefix value &&
  hash_valid (substring (String.length prefix) (String.length value) value).
Definition model_key namespace slug := namespace ++ "/" ++ slug.
(** Admitted external slugs contain no tilde, so derived variants occupy a
    separate grammar rather than competing with an advertised model name. *)
Definition auto_key key := key ++ "/~auto".
Definition reviewer_prefix key := key ++ "/~reviewer/".
Definition reviewer_key key hash := reviewer_prefix key ++ hash.
Definition is_profile_key key :=
  let start := String.length prefix in
  String.prefix prefix key && hash_valid (substring start hash_width key) &&
  String.eqb (substring (start + hash_width) 1 key) "/".
