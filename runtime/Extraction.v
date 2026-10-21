From Stdlib Require Import NArith ZArith.
From Stdlib Require Export Extraction ExtrOcamlBasic ExtrOcamlNativeString ExtrOcamlNatBigInt ExtrOcamlZBigInt.
Extraction Language OCaml.

(* Native strings report their byte length without recursively copying suffixes.
   Convert that representable native length to the exact extracted nat. *)
Extract Constant String.length => "(fun s -> Big_int_Z.big_int_of_int (String.length s))".
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

(* Gallina substring clips both bounds to the available byte string. Clip exact
   natural indices before converting these representable native bounds. *)
Extract Constant String.substring => "(fun start count text -> let length = String.length text in if Big_int_Z.ge_big_int start (Big_int_Z.big_int_of_int length) then String.empty else let offset = Big_int_Z.int_of_big_int start in let available = length - offset in let clipped = Big_int_Z.min_big_int count (Big_int_Z.big_int_of_int available) in String.sub text offset (Big_int_Z.int_of_big_int clipped))".

(* Native byte conversions avoid eight arbitrary-precision bit steps
   on every UTF-8 byte while retaining the standard eight-bit modulo semantics. *)
Extract Constant Ascii.nat_of_ascii => "(fun c -> Big_int_Z.big_int_of_int (Char.code c))".
Extract Constant Ascii.ascii_of_nat => "(fun n -> Char.chr (Big_int_Z.int_of_big_int (Big_int_Z.mod_big_int n (Big_int_Z.big_int_of_int 256))))".
