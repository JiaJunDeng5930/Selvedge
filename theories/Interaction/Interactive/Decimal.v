From Stdlib Require Import String Ascii List Bool NArith ZArith.
From Selvedge.Foundation Require Import Numbers TextJson.
From Selvedge.Interaction.Interactive Require Import Bounds.
Open Scope string_scope.
Open Scope Z_scope.
Definition scale : Z := Bounds.decimal_scale.
Definition limit : Z := Bounds.decimal_limit.
Definition decimal := { n:Z | Z.abs n <= limit }.
Definition units (d:decimal) : Z := proj1_sig d.
Definition checked (n:Z) : option decimal :=
 match Z_le_dec (Z.abs n) limit with left proof=>Some(exist _ n proof) | right _=>None end.
Definition whole_valid s :=
 match s with EmptyString=>false | String c r=>
   if Ascii.eqb c "0" then String.eqb r "" else forallb is_digit (list_ascii_of_string s) end.
Fixpoint split_dot s : option (string*option string) :=
 match s with
 | EmptyString=>Some("",None)
 | String c r=>if Ascii.eqb c "." then Some("",Some r) else
   match split_dot r with Some(a,b)=>Some(String c a,b) | None=>None end end.
Definition parse (text:string) : option decimal :=
 let '(negative,unsigned):=match text with String c r=>if Ascii.eqb c "-" then (true,r) else (false,text) | _=>(false,text) end in
 if (String.length text <=? Bounds.number_spelling)%nat then
 match split_dot unsigned with
 | Some(whole,fraction)=>
   let fraction:=match fraction with None=>"" | Some s=>s end in
   let has_dot:=existsb (Ascii.eqb ".") (list_ascii_of_string unsigned) in
   if whole_valid whole && (String.length fraction <=? Bounds.fraction_digits)%nat &&
     forallb is_digit (list_ascii_of_string fraction) && (negb has_dot || negb(String.eqb fraction "")) then
     match parse_natural whole, if String.eqb fraction "" then Some 0%N else parse_natural fraction with
     | Some w,Some f=>let magnitude:=Z.of_N w*scale+Z.of_N f*Z.pow 10 (Z.of_nat(Bounds.fraction_digits-String.length fraction)) in
         checked (if negative then -magnitude else magnitude)
     | _,_=>None end
   else None
 | None=>None end else None.
Fixpoint trim_zero (s:string) : string :=
 match s with EmptyString=>"" | String c r=>let tail:=trim_zero r in
  if String.eqb tail "" && Ascii.eqb c "0" then "" else String c tail end.
Fixpoint zeros n := match n with O=>"" | S k=>"0"++zeros k end.
Definition render (n:Z) : string :=
 let absolute:=Z.abs n in
 let whole:=show_integer (Z.quot absolute scale) in
 let fractional:=show_integer (Z.rem absolute scale) in
 let fractional:=trim_zero (zeros (Bounds.fraction_digits-String.length fractional)++fractional) in
 (if n <? 0 then "-" else "")++whole++(if String.eqb fractional "" then "" else "."++fractional).
Definition text (d:decimal) := render(units d).
Definition rounded_division (numerator denominator:Z) : option Z :=
 if denominator =? 0 then None else
 let n:=Z.abs numerator in let d:=Z.abs denominator in
 let q:=Z.quot n d in let r:=Z.rem n d in
 let q:=if d <=? 2*r then q+1 else q in
 Some(if xorb (numerator <? 0) (denominator <? 0) then -q else q).
Definition binary (op:string) (left right:decimal) : option decimal :=
 let a:=units left in let b:=units right in
 if String.eqb op "+" then checked(a+b) else
 if String.eqb op "-" then checked(a-b) else
 if String.eqb op "*" then match rounded_division (a*b) scale with Some x=>checked x | _=>None end else
 if String.eqb op "/" then match rounded_division (a*scale) b with Some x=>checked x | _=>None end else
 if String.eqb op "%" then
   if (Z.rem a scale =? 0)&&(Z.rem b scale =? 0)&&negb(b =? 0) then checked(Z.rem a b) else None
 else None.
Definition integral d := Z.rem (units d) scale =? 0.
Definition compare (op:string) a b :=
 let a:=units a in let b:=units b in
 if String.eqb op "<" then a <? b else if String.eqb op "<=" then a <=? b else
 if String.eqb op ">" then b <? a else if String.eqb op ">=" then b <=? a else
 if String.eqb op "==" then a =? b else if String.eqb op "!=" then negb(a =? b) else false.
Definition round (places:nat) d : option decimal :=
 if (places <=? Bounds.fraction_digits)%nat then
 let quantum:=Z.pow 10 (Z.of_nat(Bounds.fraction_digits-places)) in
 match rounded_division (units d) quantum with Some n=>checked(n*quantum) | None=>None end
 else None.
Definition on_grid value anchor step :=
 (0 <? units step) && (Z.rem (units value-units anchor) (units step) =? 0).
Definition zero : decimal := exist _ 0%Z (proj1 (Z.leb_le (Z.abs 0) limit) eq_refl).
Definition one : decimal := exist _ scale (proj1 (Z.leb_le (Z.abs scale) limit) eq_refl).
