From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 Json.
From Selvedge.Programming Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Definition maximum_characters : nat := 36.
Definition prompt_bytes : N := 960.
Definition response_title_bytes : N := 4096.
Definition maximum_instruction_bytes : N := 4096.
Definition instructions : string :=
 "Generate a concise, single-line task title of at most 36 characters and under five words where possible. Start with an imperative verb. Capitalize only the first word unless the user's language, proper nouns, acronyms, or code terms require otherwise. Preserve ticket references exactly. Write in the user's language. Do not use quotes, markdown, or trailing punctuation. Do not answer the request.".
Definition title_format : string := "
Return only a JSON object with exactly one string field: title.

User prompt:
".
Definition title_whitespace (code : N) :=
 (Utf8.whitespace code && negb(N.eqb code 65279)) || N.eqb code 133.
Definition quote (code : N) := existsb (N.eqb code) [34%N; 39%N; 96%N; 8216%N; 8217%N; 8220%N; 8221%N].
Fixpoint trim_left (predicate : N -> bool) (values : list (N * string)) :=
 match values with [] => [] | (code,_) :: rest =>
 if predicate code then trim_left predicate rest else values end.
Definition trim_both (predicate : N -> bool) (values : list (N * string)) :=
 List.rev_append (trim_left predicate (List.rev_append (trim_left predicate values) [])) [].
Definition collapse_spaces (values : list (N * string)) (pending : bool) : list (N * string) :=
 (* Reverse accumulation preserves pending whitespace without one extracted
    stack frame per scalar in an admitted message or model title reply. *)
 let fix collect (remaining : list (N * string)) (space : bool) (reversed : list (N * string)) :=
   match remaining with
   | [] => List.rev_append reversed []
   | (code,bytes) :: rest =>
     if title_whitespace code then collect rest true reversed
     else collect rest false
       ((code,bytes) :: (if space then (32%N," ") :: reversed else reversed))
   end in
 collect values pending [].
Definition normalize (text : string) : string :=
 (* DEFENSE: External model title replies may contain malformed UTF-8; they
    cannot become a title or be truncated inside an encoded scalar. *)
 match Utf8.chunks text with
 | None => ""
 | Some source =>
   let unquoted := trim_both (fun code => title_whitespace code || quote code) source in
   let collapsed := collapse_spaces unquoted false in
   let clean := List.rev_append (trim_left (fun code => title_whitespace code ||
     existsb (N.eqb code) [46%N; 63%N; 33%N]) (List.rev_append collapsed [])) [] in
   Utf8.render_chunks (firstn maximum_characters clean)
 end.
Definition instruction_declaration := ArgumentDeclaration.bounded_text maximum_instruction_bytes.
Definition instruction := ArgumentDeclaration.denote instruction_declaration.
Definition instruction_text (value : instruction) := proj1_sig value.
Definition default_instructions : instruction.
Proof. refine (exist _ instructions _). vm_compute. reflexivity. Defined.
Definition valid_instructions (text : string) :=
 ArgumentDeclaration.check instruction_declaration (JString text).

Definition title_field_schema := Selvedge.Foundation.Json.JObject [
 ("type",Selvedge.Foundation.Json.JString "string");
 ("minLength",Selvedge.Foundation.Json.JNumber "1");
 ("maxLength",Selvedge.Foundation.Json.JNumber "36")].
Definition output_schema (capture:bool) := Selvedge.Foundation.Json.JObject [
 ("type",Selvedge.Foundation.Json.JString "object");
 ("properties",Selvedge.Foundation.Json.JObject
 (("title",title_field_schema)::if capture then [("description",Selvedge.Foundation.Json.JObject [("type",Selvedge.Foundation.Json.JString "string")])] else []));
 ("required",Selvedge.Foundation.Json.JArray
 (Selvedge.Foundation.Json.JString "title"::if capture then [Selvedge.Foundation.Json.JString "description"] else []));
 ("additionalProperties",Selvedge.Foundation.Json.JBool false)].

Fixpoint bounded (parts:list (N*string)) (bytes:N) :string := match parts with
 | []=>"" | (_,chunk)::rest=>let length:=N.of_nat (String.length chunk) in
 if N.leb length bytes then String.append chunk (bounded rest (bytes-length)) else "" end.
Definition prompt_with (instruction : instruction) (request : string) :=
 let budget:=prompt_bytes - N.of_nat (String.length (String.append instructions title_format)) in
 let text:=match Utf8.chunks request with Some chunks=>bounded (trim_both Utf8.whitespace chunks) budget | None=>"" end in
 String.append (instruction_text instruction) (String.append title_format text).
Definition capture_format := "
Return only a JSON object with exactly two string fields: title and description. Write a clear actionable description. Preserve the user's requirements, language and constraints. Do not invent requirements or claim completion.

Title/request preview:
".
Definition board_prompt (instruction : instruction) (title description:string) (retitle:bool) :=
 if retitle then prompt_with instruction (String.append title (String.append "

" description))
 else String.append (instruction_text instruction) (String.append capture_format (String.append title (String.append "

Original user request:
" description))).

Definition preview (request:string) := match Utf8.chunks request with
 | Some chunks=>Utf8.render_chunks (firstn 96 (trim_both Utf8.whitespace chunks))
 | None=>"" end.
