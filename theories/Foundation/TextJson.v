From Stdlib Require Import String Ascii List Bool Arith NArith.
From Selvedge.Foundation Require Import Json Numbers Utf8.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.

Inductive scan (A:Type) :=
| Scanned (value:A) (rest:string)
| More
| Invalid (reason:string).
Arguments Scanned {A} _ _.
Arguments More {A}.
Arguments Invalid {A} _.
Definition scan_map {A B} (f:A->B) (s:scan A) : scan B :=
  match s with Scanned v r => Scanned (f v) r | More => More | Invalid e => Invalid e end.
Definition ascii_code := nat_of_ascii.
Definition byte n := String (ascii_of_nat n) EmptyString.
Definition encoded_scalar (n:nat) (rest:string) : scan string :=
 match Utf8.encode (N.of_nat n) with Some text=>Scanned text rest | None=>Invalid "Invalid Unicode scalar" end.
Definition hex_digit c :=
 let n:=ascii_code c in
 if (48<=?n)&&(n<=?57) then Some(n-48) else
 if (65<=?n)&&(n<=?70) then Some(n-55) else
 if (97<=?n)&&(n<=?102) then Some(n-87) else None.
Fixpoint hex_digits (count acc:nat) (s:string) : scan nat :=
 match count with
 | O=>Scanned acc s
 | S k=>match s with EmptyString=>More | String c r=>
   match hex_digit c with Some d=>hex_digits k (acc*16+d) r | None=>Invalid "Invalid Unicode escape" end end
 end.
Definition escaped_scalar s : scan string :=
 match hex_digits 4 0 s with
 | Scanned hi rest =>
   if (55296<=?hi)&&(hi<=?56319) then
     match rest with
     | String slash (String u rest) =>
       if Ascii.eqb slash "\" && Ascii.eqb u "u" then
         match hex_digits 4 0 rest with
         | Scanned lo rest=>if (56320<=?lo)&&(lo<=?57343)
              then encoded_scalar (65536+(hi-55296)*1024+(lo-56320)) rest
              else Invalid "Unpaired Unicode surrogate"
         | More=>More | Invalid e=>Invalid e end
       else Invalid "Unpaired Unicode surrogate"
     | _=>More end
   else if (56320<=?hi)&&(hi<=?57343) then Invalid "Unpaired Unicode surrogate"
   else encoded_scalar hi rest
 | More=>More | Invalid e=>Invalid e end.
Definition finish_string reversed:=String.string_of_list_ascii(List.rev_append reversed []).
Fixpoint push_string s reversed:=match s with EmptyString=>reversed|String c rest=>push_string rest(c::reversed)end.
Fixpoint quoted_acc (fuel:nat) (s:string) (reversed:list ascii) : scan string :=
 match fuel with
 | O=>Invalid "String token exceeds its budget"
 | S k=>match s with
   | EmptyString=>More
   | String c r=>
     if Ascii.eqb c """" then Scanned(finish_string reversed)r else
     if ascii_code c <? 32 then Invalid "Control character in quoted string" else
     if Ascii.eqb c "\" then
       match r with
       | EmptyString=>More
       | String e rest=>
         let decoded :=
           if Ascii.eqb e "u" then escaped_scalar rest else
           if Ascii.eqb e """" || Ascii.eqb e "\" || Ascii.eqb e "/" then Scanned (String e "") rest else
           if Ascii.eqb e "b" then Scanned (byte 8) rest else
           if Ascii.eqb e "f" then Scanned (byte 12) rest else
           if Ascii.eqb e "n" then Scanned (byte 10) rest else
           if Ascii.eqb e "r" then Scanned (byte 13) rest else
           if Ascii.eqb e "t" then Scanned (byte 9) rest else Invalid "Invalid string escape" in
         match decoded with
         | Scanned head tail=>quoted_acc k tail(push_string head reversed)
         | More=>More | Invalid e=>Invalid e end
       end
     else quoted_acc k r(c::reversed)
   end
 end.
Definition quoted_body fuel s:=quoted_acc fuel s [].
Definition quoted fuel s := match s with
 | EmptyString=>More
 | String c r=>if Ascii.eqb c """" then quoted_body fuel r else Invalid "Expected a quoted JSON string" end.
Definition whitespace c := existsb (Ascii.eqb c) [" "%char; "009"%char; "010"%char; "013"%char].
Fixpoint trim_left s := match s with String c r=>if whitespace c then trim_left r else s | _=>s end.
Fixpoint take_while_acc(p:ascii->bool)(s:string)(reversed:list ascii):string*string:=
 match s with EmptyString=>(finish_string reversed,"")|String c rest=>
 if p c then take_while_acc p rest(c::reversed)else(finish_string reversed,s)end.
Definition take_while p s:=take_while_acc p s [].
Definition number_char c := is_digit c || existsb (Ascii.eqb c) ["-"%char;"+"%char;"."%char;"e"%char;"E"%char].
Fixpoint drop_prefix prefix source : option string :=
 match prefix,source with
 | EmptyString,_=>Some source
 | String a p,String b s=>if Ascii.eqb a b then drop_prefix p s else None
 | _,_=>None end.
Definition keyword {A} (name:string) (value:A) (s:string) : scan A := match drop_prefix name s with
 | Some rest=>Scanned value rest | None=>Invalid "Invalid JSON literal" end.
Fixpoint json_value (fuel:nat) (s:string) : scan json :=
 match fuel with
 | O=>Invalid "JSON nesting or token budget exceeded"
 | S k=>let s:=trim_left s in match s with
   | EmptyString=>More
   | String c r=>
    if Ascii.eqb c """" then scan_map JString (quoted_body k r) else
    if Ascii.eqb c "[" then
      let fix items (left:nat) (text:string) (reversed:list json) : scan (list json) :=
        match left with
        | O=>Invalid "JSON array exceeds budget"
        | S n=>let text:=trim_left text in
          match text with
          | EmptyString=>More
          | String c r=>if Ascii.eqb c "]" then Scanned(List.rev_append reversed [])r else
            match json_value k text with
            | Scanned value rest=>let rest:=trim_left rest in
              match rest with
              | EmptyString=>More
              | String c r=>if Ascii.eqb c "]" then Scanned(List.rev_append(value::reversed)[])r else
                if Ascii.eqb c "," then
                  match trim_left r with
                  | String c _=>if Ascii.eqb c "]" then Invalid "Trailing array comma"
                    else items n r(value::reversed)
                  | _=>More end
                else Invalid "Expected array separator" end
            | More=>More | Invalid e=>Invalid e end
          end end in scan_map JArray (items k r [])
    else if Ascii.eqb c "{" then
      let fix members (left:nat) (seen:list string) (text:string) (reversed:list(string*json)) : scan (list(string*json)) :=
        match left with
        | O=>Invalid "JSON object exceeds budget"
        | S n=>let text:=trim_left text in
          match text with
          | EmptyString=>More
          | String c r=>if Ascii.eqb c "}" then Scanned(List.rev_append reversed [])r else
            match quoted k text with
            | Scanned key rest=>if existsb (String.eqb key) seen then Invalid "Duplicate object key" else
              match trim_left rest with
              | EmptyString=>More
              | String c r=>if Ascii.eqb c ":" then
                match json_value k r with
                | Scanned value rest=>match trim_left rest with
                  | EmptyString=>More
                  | String c r=>if Ascii.eqb c "}" then Scanned(List.rev_append((key,value)::reversed)[])r else
                    if Ascii.eqb c "," then
                      match trim_left r with
                      | String c _=>if Ascii.eqb c "}" then Invalid "Trailing object comma"
                        else members n(key::seen)r((key,value)::reversed)
                      | _=>More end
                    else Invalid "Expected object separator" end
                | More=>More | Invalid e=>Invalid e end
                else Invalid "Expected object colon" end
            | More=>More | Invalid e=>Invalid e end
          end end in scan_map JObject (members k [] r [])
    else if Ascii.eqb c "t" then keyword "true" (JBool true) s else
    if Ascii.eqb c "f" then keyword "false" (JBool false) s else
    if Ascii.eqb c "n" then keyword "null" JNull s else
    let '(number,rest):=take_while number_char s in
    if number_lexeme number then Scanned (JNumber number) rest else Invalid "Invalid JSON number"
   end end.
(* DEFENSE: The public JSON entry receives untrusted bytes; invalid UTF-8 cannot become a domain string. *)
Definition parse_json (s:string) : option json :=
 if Utf8.well_formed s then match json_value (S(String.length s)) s with
 | Scanned value rest=>if String.eqb (trim_left rest) "" then Some value else None
 | _=>None end else None.

Definition utf8_count (s:string) : option nat := option_map (@List.length N) (Utf8.decode s).
Definition within_scalars maximum s := match utf8_count s with Some n=>(n<=?maximum) | None=>false end.

Definition hex_char n := ascii_of_nat (if n <? 10 then 48+n else 87+n).
Definition escape_char c : string :=
 if Ascii.eqb c """" then "\""" else
 if Ascii.eqb c "\" then "\\" else
 if ascii_code c <? 32 then
   "\u00" ++ String (hex_char (ascii_code c/16)) (String (hex_char (ascii_code c mod 16)) "")
 else String c "".
Fixpoint escape_acc s reversed:=match s with EmptyString=>String.concat ""(List.rev_append reversed [])
 |String c rest=>escape_acc rest(escape_char c::reversed)end.
Definition escape_string s:=escape_acc s [].
Definition quote s := """"++escape_string s++"""".
Fixpoint render_json (value:json) : string :=
 match value with
 | JNull=>"null" | JBool true=>"true" | JBool false=>"false"
 | JNumber s=>s | JString s=>quote s
 | JArray values=>"["++String.concat "," (List.rev_append(fold_left(fun reversed value=>render_json value::reversed)values[])[])++"]"
 | JObject fields=>"{"++String.concat "," (List.rev_append(fold_left(fun reversed kv=>(quote(fst kv)++":"++render_json(snd kv))::reversed)fields[])[])++"}" end.
