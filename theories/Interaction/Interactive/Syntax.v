From Stdlib Require Import String Ascii List Bool Arith.
From Selvedge.Foundation Require Import Json Numbers TextJson Utf8.
From Selvedge.Interaction.Interactive Require Import Bounds Expression Vocabulary.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.
Record attribute := Attribute { attribute_name:string; attribute_value:expr; attribute_source:string }.
Inductive element := Element (tag:string)(attributes:list attribute)(children:list element)(closed:bool).
Record frame := Frame { frame_tag:string; frame_attributes:list attribute; frame_children:list element }.
Record syntax := Syntax {
 roots_reversed:list element; frames:list frame; tail:string; syntax_error:option string;
 sealed:bool; accepted:nat; characters:nat }.
Definition empty := Syntax [] [] "" None false 0 0.
Definition name_char c := alpha c || is_digit c || Ascii.eqb c "-".
Definition valid_id s :=
 match s with EmptyString=>false|String c _=>
 let n:=nat_of_ascii c in (((65<=?n)&&(n<=?90))||((97<=?n)&&(n<=?122)))&&
 (String.length s<=?Bounds.identifier_length)&&forallb name_char(list_ascii_of_string s)end.
(* Bounded tokens can still exceed the physical JavaScript call stack. *)
Fixpoint cut_tag_acc (fuel depth:nat)(quoted escaped:bool)(text:string)
 (reversed:list ascii) : scan string :=
 match fuel with
 | O=>Invalid "Token exceeds its scalar budget"
 | S k=>match text with EmptyString=>More | String c rest=>
   if quoted then
     if escaped then cut_tag_acc k depth true false rest(c::reversed)else
     if Ascii.eqb c "\" then cut_tag_acc k depth true true rest(c::reversed)else
     if Ascii.eqb c """" then cut_tag_acc k depth false false rest(c::reversed)
     else cut_tag_acc k depth true false rest(c::reversed)
   else if Ascii.eqb c """" then cut_tag_acc k depth true false rest(c::reversed)
   else if Ascii.eqb c "{"then cut_tag_acc k(S depth)false false rest(c::reversed)
   else if Ascii.eqb c "}"then match depth with O=>Invalid "Unmatched attribute brace"|S n=>cut_tag_acc k n false false rest(c::reversed)end
   else if Ascii.eqb c ">"&&Nat.eqb depth 0 then Scanned(finish_string(c::reversed))rest
   else cut_tag_acc k depth false false rest(c::reversed)
   end end.
Definition cut_tag fuel depth quoted escaped text:=cut_tag_acc fuel depth quoted escaped text [].
Fixpoint cut_brace_acc(fuel depth:nat)(quoted escaped:bool)(text:string)
 (reversed:list ascii):scan string:=
 match fuel with O=>Invalid "Expression token budget"|S k=>match text with
 | EmptyString=>More|String c rest=>
   if quoted then
     cut_brace_acc k depth
       (if escaped then true else negb(Ascii.eqb c """"))
       (if escaped then false else Ascii.eqb c "\")rest(c::reversed)
   else if Ascii.eqb c """"then cut_brace_acc k depth true false rest(c::reversed)
   else if Ascii.eqb c "{"then cut_brace_acc k(S depth)false false rest(c::reversed)
   else if Ascii.eqb c "}"then match depth with O=>Scanned(finish_string reversed)rest|S n=>cut_brace_acc k n false false rest(c::reversed)end
   else cut_brace_acc k depth false false rest(c::reversed)
   end end.
Definition cut_brace fuel depth quoted escaped text:=cut_brace_acc fuel depth quoted escaped text [].
Inductive tag_token := StartTag(tag:string)(attrs:list attribute)(leaf:bool)|EndTag(tag:string).
Fixpoint tag_attributes(fuel:nat)(seen:list string)(text:string):outcome(list attribute*bool):=
 match fuel with O=>Error "Attribute count limit"|S k=>
 let text:=trim_left text in
 if String.eqb text ">"then Good([],false)else if String.eqb text "/>"then Good([],true)else
 let '(name,rest):=take_while name_char text in
 if String.eqb name ""||existsb(String.eqb name)seen then Error "Empty or duplicate attribute"else
 match trim_left rest with
 | String equals rest=>if Ascii.eqb equals "="then
    let rest:=trim_left rest in
    let value:=match rest with
      | String c rest=>if Ascii.eqb c "{"then
          match cut_brace(S(String.length rest))0 false false rest with
          | Scanned source rest=>match Expression.parse source with Good value=>Good(value,source,rest)|Error e=>Good(InvalidExpression e,source,rest)end
          | _=>Error "Invalid braced expression"end
        else match TextJson.quoted(S(String.length rest)) (String c rest)with
          | Scanned value rest=>Good(Value(JString value),TextJson.quote value,rest)
          | _=>Error "Attribute requires a JSON string or expression"end
      | _=>Error "Missing attribute value"end in
    p <-? value;;let '(value,source,rest):=p in
    p <-? tag_attributes k(name::seen)rest;;let '(attributes,leaf):=p in
    Good(Attribute name value source::attributes,leaf)
   else Error "Expected attribute equals"
 | _=>Error "Incomplete attribute"end end.
Definition parse_tag(text:string):outcome tag_token:=
 match text with
 | String opening rest=>if Ascii.eqb opening "<"then
   match rest with
   | String slash rest=>if Ascii.eqb slash "/"then
       let '(tag,rest):=take_while name_char rest in
       if negb(String.eqb tag "")&&String.eqb(trim_left rest) ">"then Good(EndTag tag)else Error "Invalid closing tag"
     else let '(tag,rest):=take_while name_char(String slash rest)in
       if String.eqb tag ""then Error "Missing tag name"else
       p <-? tag_attributes 65 [] rest;;let '(attrs,leaf):=p in
       if leaf_tag tag&&negb leaf then Error "Leaf elements and declarations must be self-closing"else Good(StartTag tag attrs leaf)
   | _=>Error "Incomplete tag"end
   else Error "Text nodes are not allowed in the UI language"
 | _=>Error "Empty tag"end.
Definition fail reason s := Syntax s.(roots_reversed)s.(frames)s.(tail)(Some reason)s.(sealed)s.(accepted)s.(characters).
Definition add_element e s :=
 match s.(frames)with
 | []=>Syntax(e::s.(roots_reversed))[]s.(tail)s.(syntax_error)s.(sealed)s.(accepted)s.(characters)
 | frame::rest=>Syntax s.(roots_reversed)(Frame frame.(frame_tag)frame.(frame_attributes)(e::frame.(frame_children))::rest)
    s.(tail)s.(syntax_error)s.(sealed)s.(accepted)s.(characters)end.
Definition consume_token token rest s :=
 let next:=Syntax s.(roots_reversed)s.(frames)rest s.(syntax_error)s.(sealed)(S s.(accepted))s.(characters)in
 match token with
 | StartTag tag attrs true=>if s.(accepted)<?Bounds.syntax_components then add_element(Element tag attrs [] true)next else fail "Component count limit"s
 | StartTag tag attrs false=>
   if (List.length s.(frames)<?Bounds.nesting)&&(s.(accepted)<?Bounds.syntax_components) then
     Syntax s.(roots_reversed)(Frame tag attrs []::s.(frames))rest s.(syntax_error)s.(sealed)(S s.(accepted))s.(characters)
   else fail "Component nesting or count limit"s
 | EndTag tag=>match s.(frames)with
   | []=>fail "Closing tag has no open container"s
   | frame::outer=>if String.eqb tag frame.(frame_tag)then
      add_element(Element tag frame.(frame_attributes)(rev frame.(frame_children))true)
       (Syntax s.(roots_reversed)outer rest s.(syntax_error)s.(sealed)s.(accepted)s.(characters))
     else fail "Mismatched closing tag"s end end.
Fixpoint turn(fuel:nat)(s:syntax):syntax:=
 match s.(syntax_error),s.(sealed)with
 | None,false=>match fuel with O=>s|S k=>
   let text:=trim_left s.(tail)in
   if String.eqb text ""then Syntax s.(roots_reversed)s.(frames)""None false s.(accepted)s.(characters)else
   match text with
   | String opening _=>if Ascii.eqb opening "<"then
     match cut_tag(S(String.length text))0 false false text with
     | More=>if within_scalars Bounds.token_scalars text then s else fail "Token scalar limit"s
     | Invalid e=>fail e s
     | Scanned token rest=>if within_scalars Bounds.token_scalars token then
       match parse_tag token with Good token=>turn k(consume_token token rest s)|Error e=>fail e s end
       else fail "Token scalar limit"s end
     else fail "Text nodes are not allowed in the UI language"s
   | _=>s end
   end
 | _,_=>s end.
Definition append suffix s :=
 match s.(syntax_error),s.(sealed)with
 | None,false=>match Utf8.scalar_count suffix with
   | Some n=>if s.(characters)+n<=?Bounds.fence_scalars then
      turn Bounds.parser_turn(Syntax s.(roots_reversed)s.(frames)(s.(tail)++suffix)None false s.(accepted)(s.(characters)+n))
     else fail "Fence scalar limit"s
   | None=>fail "Invalid UTF-8 in fence"s end
 | _,_=>s end.
Definition pending s :=
 match s.(syntax_error)with Some _=>false|None=>
 match cut_tag(S(String.length s.(tail)))0 false false(trim_left s.(tail))with Scanned _ _=>true|_=>false end end.
Definition finish s :=
 if pending s then s else
 match s.(syntax_error)with Some _=>s|None=>
 if String.eqb(trim_left s.(tail))""&&Nat.eqb(List.length s.(frames))0 then
 Syntax s.(roots_reversed)s.(frames)s.(tail)None true s.(accepted)s.(characters)
 else fail "Definition ended with an incomplete tag or container"s end.
Fixpoint open_tree(stack:list frame)(child:option element):option element:=
 match stack with []=>child|frame::rest=>
 let children:=List.app (rev frame.(frame_children)) (match child with Some child=>[child]|None=>[]end) in
 open_tree rest(Some(Element frame.(frame_tag)frame.(frame_attributes)children false))end.
Definition roots s :=List.app (rev s.(roots_reversed)) (match open_tree s.(frames)None with Some root=>[root]|None=>[]end).
Definition attr name attrs :=find(fun a=>String.eqb a.(attribute_name)name)attrs.
Definition literal_attr name attrs :=match attr name attrs with
 | Some a=>if is_literal 33 a.(attribute_value)then
   match evaluate Bounds.evaluation_steps [] a.(attribute_value)with (Good v,_)=>Good v|(Error e,_)=>Error e end
   else Error("Literal attribute required: "++name)
 | None=>Error("Missing attribute: "++name)end.

Definition valid_binding s:=valid_id s&&
 match Expression.tokenize (S Bounds.identifier_length) s with Good[Name _]=>true|_=>false end.
