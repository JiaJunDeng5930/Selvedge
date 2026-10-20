From Stdlib Require Import NArith ZArith.
From Stdlib Require Export Extraction ExtrOcamlBasic ExtrOcamlNativeString ExtrOcamlNatBigInt ExtrOcamlZBigInt.
Extraction Language OCaml.
(** Peano elimination overflowed the JS stack on ordinary surrogate escapes.
    These standard arbitrary-precision representations preserve natural and
    signed integer values; no machine-integer bounds are assumed. *)
Extract Constant N.of_nat => "(fun n -> n)".
Extract Constant N.to_nat => "(fun n -> n)".
Extract Constant Pos.of_succ_nat => "Big_int_Z.succ_big_int".
Extract Constant Pos.to_nat => "(fun n -> n)".
Extract Constant Z.of_nat => "(fun n -> n)".
Extract Constant Z.to_nat => "(fun n -> Big_int_Z.max_big_int Big_int_Z.zero_big_int n)".
Extract Constant Nat.div => "(fun n d -> if Big_int_Z.sign_big_int d = 0 then Big_int_Z.zero_big_int else Big_int_Z.div_big_int n d)".
Extract Constant Nat.modulo => "(fun n d -> if Big_int_Z.sign_big_int d = 0 then n else Big_int_Z.mod_big_int n d)".
