From Stdlib Require Import String Ascii List Bool Arith NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import TextJson Utf8.
From Selvedge.Interaction.Interactive Require Import Bounds Builtins Decimal.
From Selvedge.Programming Require Import Outcome Metered.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.
Inductive token := Literal (value:json) | Name (name:string) | Symbol (name:string).
Definition alpha c := let n:=nat_of_ascii c in ((65<=?n)&&(n<=?90))||((97<=?n)&&(n<=?122))||Ascii.eqb c "_".
Definition alphanumeric c := alpha c || is_digit c.
Definition is_symbol sym t := match t with Symbol s=>String.eqb sym s | _=>false end.
Definition paired s := existsb (String.eqb s) ["==";"!=";"<=";">=";"&&";"||"].
Fixpoint tokenize_acc (fuel:nat) (source:string) (reversed:list token) : outcome(list token) :=
 match fuel with
 | O=>if String.eqb(trim_left source) "" then Good(List.rev_append reversed []) else Error "Expression token budget exceeded"
 | S k=>let source:=trim_left source in match source with
   | EmptyString=>Good(List.rev_append reversed [])
   | String c r=>
     if Ascii.eqb c """" then
       match quoted (S(String.length source)) source with
       | Scanned value rest=>tokenize_acc k rest(Literal(JString value)::reversed)
       | _=>Error "Invalid expression string" end
     else if alpha c then
       let '(name,rest):=take_while alphanumeric source in
       tokenize_acc k rest((if String.eqb name "true" then Literal(JBool true) else
              if String.eqb name "false" then Literal(JBool false) else
              if String.eqb name "null" then Literal JNull else Name name)::reversed)
     else if is_digit c then
       let '(number,rest):=take_while (fun c=>is_digit c||Ascii.eqb c ".") source in
       match Decimal.parse number with
       |Some d=>tokenize_acc k rest(Literal(JNumber(Decimal.text d))::reversed)
       |None=>Error "Invalid fixed decimal literal" end
     else
       let '(operator,rest):=match r with
       | String d rest=>let two:=String c (String d "") in if paired two then (two,rest) else (String c "",r)
       | _=>(String c "",r) end in
       if existsb (String.eqb operator) ["==";"!=";"<=";">=";"&&";"||";"!";"-";"+";"*";"/";"%";"<";">";"?";":";".";",";"(";")";"[";"]";"{";"}"]
       then tokenize_acc k rest(Symbol operator::reversed)
       else Error "Unknown expression token"
   end end.
Definition tokenize fuel source:=tokenize_acc fuel source [].
Inductive expr :=
| Value (value:json) | InvalidExpression(reason:string) | Reference (name:string)
| Unary (operator:string) (argument:expr)
| Binary (operator:string) (lhs rhs:expr)
| Conditional (test yes no:expr)
| Access (value key:expr)
| Array (items:list expr) | Record (fields:list(string*expr))
| Call (name:string) (arguments:list expr).
Definition precedence op :=
 if String.eqb op "||" then 1 else if String.eqb op "&&" then 2 else
 if existsb (String.eqb op) ["==";"!="] then 3 else
 if existsb (String.eqb op) ["<";"<=";">";">="] then 4 else
 if existsb (String.eqb op) ["+";"-"] then 5 else
 if existsb (String.eqb op) ["*";"/";"%"] then 6 else 0.
Fixpoint expression (fuel minimum:nat) (tokens:list token) : outcome(expr*list token) :=
 match fuel with
 | O=>Error "Expression depth or token limit"
 | S k=>p <-? prefix k tokens ;; let '(lhs,rest):=p in suffix k minimum lhs rest
 end
with prefix (fuel:nat) (tokens:list token) : outcome(expr*list token) :=
 match fuel with
 | O=>Error "Expression depth or token limit"
 | S k=>match tokens with
   | Literal v::rest=>Good(Value v,rest)
   | Name name::Symbol "("::rest=>args <-? sequence k ")" rest ;; let '(args,rest):=args in Good(Call name args,rest)
   | Name name::rest=>Good(Reference name,rest)
   | Symbol "!"::rest=>p <-? expression k 7 rest ;; let '(arg,rest):=p in Good(Unary "!" arg,rest)
   | Symbol "-"::rest=>p <-? expression k 7 rest ;; let '(arg,rest):=p in Good(Unary "-" arg,rest)
   | Symbol "("::rest=>p <-? expression k 0 rest ;; let '(v,rest):=p in
      match rest with Symbol ")"::rest=>Good(v,rest) | _=>Error "Expected closing parenthesis" end
   | Symbol "["::rest=>p <-? sequence k "]" rest ;; let '(items,rest):=p in Good(Array items,rest)
   | Symbol "{"::rest=>p <-? record_fields k [] rest ;; let '(fields,rest):=p in Good(Record fields,rest)
   | _=>Error "Expected expression"
   end end
with suffix (fuel minimum:nat) (lhs:expr) (tokens:list token) : outcome(expr*list token) :=
 match fuel with
 | O=>Error "Expression depth or token limit"
 | S k=>match tokens with
   | Symbol "."::Name name::rest=>suffix k minimum (Access lhs (Value(JString name))) rest
   | Symbol "["::rest=>p <-? expression k 0 rest ;; let '(index,rest):=p in
      match rest with Symbol "]"::rest=>suffix k minimum (Access lhs index) rest | _=>Error "Expected index close" end
   | Symbol "?"::rest=>if minimum =? 0 then
      a <-? expression k 0 rest ;; let '(yes,rest):=a in
      match rest with Symbol ":"::rest=>b <-? expression k 0 rest ;; let '(no,rest):=b in Good(Conditional lhs yes no,rest)
      | _=>Error "Expected conditional colon" end else Good(lhs,tokens)
   | Symbol operator::rest=>let p:=precedence operator in
      if (0 <? p)&&(minimum <=? p) then
        rhs <-? expression k (S p) rest ;; let '(rhs,rest):=rhs in suffix k minimum (Binary operator lhs rhs) rest
      else Good(lhs,tokens)
   | _=>Good(lhs,tokens)
   end end
with sequence (fuel:nat) (closing:string) (tokens:list token) : outcome(list expr*list token) :=
 match fuel with
 | O=>Error "Expression collection budget"
 | S k=>match tokens with
   | Symbol s::rest=>if String.eqb s closing then Good([],rest) else
      p <-? expression k 0 tokens ;; let '(v,rest):=p in
      match rest with
      | Symbol s::rest=>if String.eqb s closing then Good([v],rest) else
          if String.eqb s "," then
          match rest with Symbol s::_=>if String.eqb s closing then Good([v],List.tl rest) else
            tail <-? sequence k closing rest ;; let '(vs,rest):=tail in Good(v::vs,rest)
          | _=>tail <-? sequence k closing rest ;; let '(vs,rest):=tail in Good(v::vs,rest) end
          else Error "Expected collection separator"
      | _=>Error "Unclosed expression collection" end
   | _=>p <-? expression k 0 tokens ;; let '(v,rest):=p in
      match rest with
      | Symbol s::rest=>if String.eqb s closing then Good([v],rest) else
        if String.eqb s "," then
          match rest with Symbol t::_=>if String.eqb t closing then Good([v],List.tl rest) else tail <-? sequence k closing rest ;; let '(vs,rest):=tail in Good(v::vs,rest)
          | _=>tail <-? sequence k closing rest ;; let '(vs,rest):=tail in Good(v::vs,rest)end
        else Error "Expected collection separator"
      | _=>Error "Unclosed expression collection" end
   end end
with record_fields (fuel:nat) (seen:list string) (tokens:list token) : outcome(list(string*expr)*list token) :=
 match fuel with
 | O=>Error "Expression record budget"
 | S k=>match tokens with
   | Symbol "}"::rest=>Good([],rest)
   | Name name::Symbol ":"::rest | Literal(JString name)::Symbol ":"::rest=>
     if existsb (String.eqb name) seen then Error "Duplicate expression record key" else
     p <-? expression k 0 rest ;; let '(v,rest):=p in
     match rest with
     | Symbol "}"::rest=>Good([(name,v)],rest)
     | Symbol ","::rest=>match rest with Symbol "}"::rest=>Good([(name,v)],rest)
        | _=>tail <-? record_fields k (name::seen) rest ;; let '(fields,rest):=tail in Good((name,v)::fields,rest)end
     | _=>Error "Expected record separator" end
   | _=>Error "Expected static record key" end end.
Definition parse source : outcome expr :=
 if within_scalars Bounds.token_scalars source then
 tokens <-? tokenize Bounds.token_scalars source ;; p <-? expression Bounds.token_scalars 0 tokens ;;
 let '(value,rest):=p in match rest with []=>Good value | _=>Error "Trailing expression tokens" end
 else Error "Expression scalar limit".

Definition decimal_value j := match j with JNumber s=>Decimal.parse s | _=>None end.
Definition decimal_json d := JNumber(Decimal.text d).
Fixpoint same_value (fuel:nat) (a b:json) : bool :=
 match fuel with O=>false | S k=>match a,b with
 | JNull,JNull=>true | JBool a,JBool b=>Bool.eqb a b
 | JNumber a,JNumber b=>match Decimal.parse a,Decimal.parse b with Some a,Some b=>Z.eqb(Decimal.units a)(Decimal.units b) | _,_=>false end
 | JString a,JString b=>String.eqb a b
 | JArray a,JArray b=>Nat.eqb(List.length a)(List.length b)&&forallb (fun pair=>same_value k (fst pair)(snd pair)) (combine a b)
 | JObject a,JObject b=>Nat.eqb(List.length a)(List.length b)&&forallb(fun pair=>match lookup(fst pair)b with Some v=>same_value k (snd pair)v | None=>false end)a
 | _,_=>false end end.
Fixpoint value_cost (fuel:nat) (v:json) : nat :=
 match fuel with O=>1 | S k=>match v with
 | JString s=>S(String.length s) | JNumber s=>S(String.length s)
 | JArray xs=>S(fold_left(fun n x=>n+value_cost k x)xs 0)
 | JObject xs=>S(fold_left(fun n x=>n+String.length(fst x)+value_cost k (snd x))xs 0)
 | _=>1 end end.
Definition spend budget cost := if cost <=? budget then Good(budget-cost) else Error "Expression evaluation budget exceeded".
Fixpoint path_parts (s:string) : list string :=
 match s with EmptyString=>[""] | String c r=>
 if Ascii.eqb c "." then ""::path_parts r else
 match path_parts r with []=>[String c ""] | h::t=>String c h::t end end.
Fixpoint field_path (parts:list string) (value:json) : json :=
 match parts with []=>value | key::rest=>
 match value with JObject fs=>match lookup key fs with Some v=>field_path rest v | None=>JNull end | _=>JNull end end.
Definition get_path path value := field_path(path_parts path)value.
Definition scalar v := match v with JNull|JBool _|JNumber _|JString _=>true | _=>false end.
Definition as_small maximum value :=
 match decimal_value value with
 | Some d=>if Decimal.integral d && Z.leb 0 (Decimal.units d) && Z.leb (Decimal.units d) (Z.of_nat maximum*Decimal.scale)
   then Some(Z.to_nat(Z.quot(Decimal.units d)Decimal.scale)) else None
 | _=>None end.
Definition access_value container key :=
 match container,key with
 | JObject fs,JString name=>Good(match lookup name fs with Some v=>v | None=>JNull end)
 | JArray values,_=>match decimal_value key with
   |Some index=>if Decimal.integral index&&Z.leb 0(Decimal.units index)then
      if Z.ltb(Decimal.units index)(Z.of_nat(List.length values)*Decimal.scale)then
        Good(nth(Z.to_nat(Z.quot(Decimal.units index)Decimal.scale))values JNull)else Good JNull
      else Error "List index must be a nonnegative integer"
   |None=>Error "List index must be a nonnegative integer"end
 | _,_=>Error "Field access requires a record or list" end.
Definition unary_value op value :=
 if String.eqb op "!" then match value with JBool b=>Good(JBool(negb b)) | _=>Error "Boolean operand required" end else
 if String.eqb op "-" then d <-? from_option "Numeric operand required" (decimal_value value) ;;
   n <-? from_option "Decimal overflow" (Decimal.checked(-Decimal.units d)%Z) ;; Good(decimal_json n)
 else Error "Unknown unary operator".
Definition binary_value op a b :=
 if String.eqb op "==" then Good(JBool(same_value 33 a b)) else
 if String.eqb op "!=" then Good(JBool(negb(same_value 33 a b))) else
 if String.eqb op "+" then
   match a,b with JString a,JString b=>if within_scalars Bounds.string_scalars(a++b)then Good(JString(a++b))else Error "String value limit"
   | _,_=>da <-? from_option "Numeric operands required" (decimal_value a) ;;
     db <-? from_option "Numeric operands required" (decimal_value b) ;;
     d <-? from_option "Decimal overflow" (Decimal.binary op da db) ;; Good(decimal_json d) end
 else if existsb(String.eqb op)["<";"<=";">";">="] then
   da <-? from_option "Numeric order requires numbers" (decimal_value a) ;;
   db <-? from_option "Numeric order requires numbers" (decimal_value b) ;; Good(JBool(Decimal.compare op da db))
 else if existsb(String.eqb op)["-";"*";"/";"%"]then
   da <-? from_option "Numeric operands required" (decimal_value a) ;;
   db <-? from_option "Numeric operands required" (decimal_value b) ;;
   d <-? from_option "Decimal overflow or invalid divisor" (Decimal.binary op da db) ;; Good(decimal_json d)
 else Error "Unknown binary operator".
Definition order_values a b : outcome comparison :=
 match a,b with
 | JString a,JString b=>Good(String.compare a b)
 | JNumber _,JNumber _=>da <-? from_option "Invalid sort number"(decimal_value a);;
   db <-? from_option "Invalid sort number"(decimal_value b);;Good(Z.compare(Decimal.units da)(Decimal.units db))
 | _,_=>Error "Sort keys must have one string or number type" end.
Definition met_charge cost:metered unit:=fun budget=>
 if cost<=?budget then(Good tt,budget-cost)else(Error "Expression evaluation budget exceeded",0).
Fixpoint insert_metered(path:string)(descending:bool)(value:json)(xs:list json):metered(list json):=
 match xs with []=>_ <-! met_lift(order_values(get_path path value)(get_path path value));;met_return[value]|x::rest=>
 _ <-! met_charge(S(value_cost 33(get_path path value)+value_cost 33(get_path path x)));;
 order <-! met_lift(order_values(get_path path value)(get_path path x));;
 if match order with Lt=>negb descending|Eq=>true|Gt=>descending end then met_return(value::xs)else
 ys <-! insert_metered path descending value rest;;met_return(x::ys)end.
Fixpoint sort_metered path descending xs:metered(list json):=
 match xs with []=>met_return[]|x::rest=>ys <-! sort_metered path descending rest;;insert_metered path descending x ys end.
Fixpoint sum_metered path xs acc:metered Decimal.decimal:=
 match xs with []=>met_return acc|x::rest=>
 _ <-! met_charge(S(value_cost 33(get_path path x)));;
 d <-! met_lift(from_option "sum field must be numeric"(decimal_value(get_path path x)));;
 n <-! met_lift(from_option "sum overflow"(Decimal.binary "+"acc d));;sum_metered path rest n end.
Fixpoint filter_metered path wanted xs:metered(list json):=
 match xs with []=>met_return[]|x::rest=>
 _ <-! met_charge(S(value_cost 33 wanted+value_cost 33(get_path path x)));;
 ys <-! filter_metered path wanted rest;;met_return(if same_value 33 wanted(get_path path x)then x::ys else ys)end.
(* Rendering can use this compatibility view; evaluators retain the budget on errors. *)
Definition sort_values path descending xs budget:=let '(result,remaining):=sort_metered path descending xs budget in
 match result with Good values=>Good(values,remaining)|Error reason=>Error reason end.
Fixpoint group_whole s : string :=
 match s with EmptyString=>"" | String c r=>
 String c (if (negb(String.eqb r ""))&&Nat.eqb(String.length r mod 3)0 then ","++group_whole r else group_whole r)end.
Definition formatted d style : outcome string :=
 let n:=Decimal.units d in
 match Builtins.decode_format style with
 |Some selected=>match selected with
 |Builtins.DecimalFormat|Builtins.PercentFormat=>
   let percent:=match selected with Builtins.PercentFormat=>true|_=>false end in
   let n:=if percent then (n*100)%Z else n in
   let s:=Decimal.render(Z.abs n)in
   match Decimal.split_dot s with
   | Some(w,f)=>Good((if Z.ltb n 0 then "-"else "")++group_whole w++
       (match f with Some s=>"."++s|_=>""end)++(if percent then "%"else ""))
   | None=>Error "Invalid decimal format"end
 |Builtins.UsdFormat|Builtins.CnyFormat=>
   cents <-? from_option "Invalid currency"(Decimal.rounded_division(Z.abs n)10000);;
   let fraction:=show_integer(Z.rem cents 100)in
   Good((if Z.ltb n 0 then "-"else "")++(match selected with Builtins.UsdFormat=>"$"|_=>"¥"end)++
    group_whole(show_integer(Z.quot cents 100))++"."++Decimal.zeros(2-String.length fraction)++fraction)end
 |None=>Error "Unknown number format"end.
Definition valid_field_path path:=
 forallb(fun part=>negb(String.eqb part ""))(path_parts path).
Definition records_only xs:=forallb(fun value=>match value with JObject _=>true|_=>false end)xs.
Definition builtin_body (kind:Builtins.builtin) args : metered json :=
 match kind,args with
 |Builtins.Length,[JString s]=>n <-! met_lift(from_option "Malformed UTF-8"(Utf8.scalar_count s));;met_return(JNumber(show_nat n))
 |Builtins.Length,[JArray xs]|Builtins.Count,[JArray xs]=>met_return(JNumber(show_nat(List.length xs)))
 |Builtins.Minimum,[a;b]|Builtins.Maximum,[a;b]=>
   da <-! met_lift(from_option "Numeric arguments required"(decimal_value a));;
   db <-! met_lift(from_option "Numeric arguments required"(decimal_value b));;
   met_return(decimal_json(if if match kind with Builtins.Minimum=>true|_=>false end then Decimal.compare "<="da db else Decimal.compare ">="da db then da else db))
 |Builtins.Absolute,[v]=>d <-! met_lift(from_option "Numeric argument required"(decimal_value v));;
   r <-! met_lift(from_option "Decimal overflow"(Decimal.checked(Z.abs(Decimal.units d))));;met_return(decimal_json r)
 |Builtins.Round,[v;p]=>d <-! met_lift(from_option "Numeric argument required"(decimal_value v));;
   p <-! met_lift(from_option "round precision must be 0..6"(as_small Bounds.fraction_digits p));;
   r <-! met_lift(from_option "round failure"(Decimal.round p d));;met_return(decimal_json r)
 |Builtins.Clamp,[v;lo;hi]=>d <-! met_lift(from_option "Numeric argument required"(decimal_value v));;
   lo <-! met_lift(from_option "Numeric argument required"(decimal_value lo));;
   hi <-! met_lift(from_option "Numeric argument required"(decimal_value hi));;
   if Decimal.compare ">"lo hi then met_fail "clamp lower bound exceeds upper bound"else
   met_return(decimal_json(if Decimal.compare "<"d lo then lo else if Decimal.compare ">"d hi then hi else d))
 |Builtins.Sum,[JArray xs;JString path]=>if valid_field_path path&&records_only xs then
   sum <-! sum_metered path xs Decimal.zero;;met_return(decimal_json sum)else met_fail "sum requires records and a field path"
 |Builtins.Filter,[JArray xs;JString path;wanted]=>if valid_field_path path&&records_only xs&&scalar wanted then
   xs <-! filter_metered path wanted xs;;met_return(JArray xs)else met_fail "filter requires records, field path and scalar comparison"
 |Builtins.Sort,[JArray xs;JString path;JString direction]=>
   match Builtins.decode_sort direction with
   |Some order=>if valid_field_path path&&records_only xs then
     xs <-! sort_metered path(match order with Builtins.Descending=>true|_=>false end)xs;;met_return(JArray xs)
     else met_fail "sort requires records, field path and asc or desc direction"
   |None=>met_fail "sort requires records, field path and asc or desc direction"end
 |Builtins.Take,[JArray xs;n]=>n <-! met_lift(from_option "take count must be 0..4096"(as_small Bounds.collection_items n));;met_return(JArray(firstn n xs))
 |Builtins.Text,[JNull]=>met_return(JString "")
 |Builtins.Text,[JString s]=>met_return(JString s)
 |Builtins.Text,[JBool value]=>met_return(JString(if value then "true"else "false"))
 |Builtins.Text,[JNumber _ as value]=>d <-! met_lift(from_option "text requires a finite fixed decimal"(decimal_value value));;
   met_return(JString(Decimal.text d))
 |Builtins.Format,[v;JString style]=>d <-! met_lift(from_option "format requires a number"(decimal_value v));;
   s <-! met_lift(formatted d style);;met_return(JString s)
 |Builtins.Working,[JNull]|Builtins.AwaitingHuman,[JNull]=>met_return(JBool false)
 |Builtins.Working,[JObject fs]|Builtins.AwaitingHuman,[JObject fs]=>
   met_lift(match lookup "working"fs,lookup "awaitingHuman"fs with
   |Some(JBool working),Some(JBool awaiting)=>Good(JBool(match kind with Builtins.Working=>working|_=>awaiting end))
   |_,_=>Error "Task record requires working and awaitingHuman Boolean facts"end)
 |_,_=>met_fail "Invalid built-in arguments"end.
Definition builtin name args : metered json:=
 _ <-! met_charge(S(fold_left(fun n x=>n+value_cost 33 x)args 0));;
 kind <-! met_lift(from_option "Unknown built-in"(Builtins.decode name));;builtin_body kind args.
Inductive task :=
| Visit (value:expr) (environment:list(string*outcome json)) (depth:nat)
| ApplyUnary (op:string)
| AfterLeft (op:string)(rhs:expr)(environment:list(string*outcome json))(depth:nat)
| ApplyBinary (op:string)(lhs:json)
| Choose (yes no:expr)(environment:list(string*outcome json))(depth:nat)
| AfterContainer (index:expr)(environment:list(string*outcome json))(depth:nat)
| ApplyAccess (container:json)
| BuildArray (count:nat)
| BuildRecord (keys:list string)
| ApplyCall (name:string)(count:nat)
| RequireBoolean
| Validate(pending:list(nat*json))(result:json).
Fixpoint visits (expressions:list expr) environment depth :=
 match expressions with []=>[]|e::rest=>Visit e environment depth::visits rest environment depth end.
Definition checked_tasks value tail:=Validate[(S Bounds.nesting,value)]value::tail.
Definition evaluation := (outcome json * nat)%type.
Definition next_evaluation := (nat * list task * list json)%type.
Definition resume budget tasks values : evaluation + next_evaluation := inr(budget,tasks,values).
Definition evaluation_step (budget:nat) (head:task) (tail:list task) (values:list json)
 : evaluation + next_evaluation :=
   match head with
   | Visit expression env depth=>if Bounds.nesting <? depth then inl(Error "Expression depth limit",budget)else
     match expression with
     | Value v=>resume budget(checked_tasks v tail)values
     | InvalidExpression reason=>inl(Error reason,budget)
     | Reference name=>match find(fun kv=>String.eqb name(fst kv))env with
       | Some(_,Good v)=>resume budget(checked_tasks v tail)values|Some(_,Error reason)=>inl(Error("Dependency error: "++reason),budget)
       | None=>inl(Error("Unknown binding: "++name),budget)end
     | Unary op value=>resume budget(Visit value env(S depth)::ApplyUnary op::tail)values
     | Binary op a b=>resume budget(Visit a env(S depth)::AfterLeft op b env(S depth)::tail)values
     | Conditional test yes no=>resume budget(Visit test env(S depth)::Choose yes no env(S depth)::tail)values
     | Access container index=>resume budget(Visit container env(S depth)::AfterContainer index env(S depth)::tail)values
     | Array xs=>resume budget(visits xs env(S depth)++BuildArray(List.length xs)::tail)values
     | Record fs=>resume budget(visits(map snd fs)env(S depth)++BuildRecord(map fst fs)::tail)values
     | Call name xs=>resume budget(visits xs env(S depth)++ApplyCall name(List.length xs)::tail)values
     end
   | ApplyUnary op=>match values with v::rest=>match unary_value op v with Good v=>resume budget(checked_tasks v tail)rest|Error e=>inl(Error e,budget)end|_=>inl(Error "Unary stack",budget)end
   | AfterLeft op rhs env depth=>match values with
     | lhs::rest=>
       if String.eqb op "&&"||String.eqb op "||"then match lhs with
       | JBool b=>if Bool.eqb b (String.eqb op "||")then resume budget tail(lhs::rest)
         else resume budget(Visit rhs env depth::RequireBoolean::tail)rest
       | _=>inl(Error "Boolean operand required",budget)end
       else resume budget(Visit rhs env depth::ApplyBinary op lhs::tail)rest
     | _=>inl(Error "Binary stack",budget)end
   | ApplyBinary op lhs=>match values with rhs::rest=>
       match spend budget(value_cost 33 lhs+value_cost 33 rhs)with
       | Error e=>inl(Error e,0)
       | Good remaining_budget=>match binary_value op lhs rhs with Good v=>resume remaining_budget(checked_tasks v tail)rest|Error e=>inl(Error e,remaining_budget)end end
       | _=>inl(Error "Binary stack",budget)end
   | Choose yes no env depth=>match values with JBool b::rest=>resume budget(Visit(if b then yes else no)env depth::tail)rest|_=>inl(Error "Conditional requires Bool",budget)end
   | AfterContainer index env depth=>match values with v::rest=>resume budget(Visit index env depth::ApplyAccess v::tail)rest|_=>inl(Error "Access stack",budget)end
   | ApplyAccess container=>match values with key::rest=>match access_value container key with Good v=>resume budget(checked_tasks v tail)rest|Error e=>inl(Error e,budget)end|_=>inl(Error "Access stack",budget)end
   | BuildArray n=>if n<=?List.length values then
       let result:=rev(firstn n values)in
       if n<=?Bounds.collection_items then resume budget(checked_tasks(JArray result)tail)(skipn n values)else inl(Error "Collection item limit",budget)
       else inl(Error "Array stack",budget)
   | BuildRecord keys=>if List.length keys<=?List.length values then
       if List.length keys<=?Bounds.record_fields then resume budget(checked_tasks(JObject(combine keys(rev(firstn(List.length keys)values))))tail)(skipn(List.length keys)values)
       else inl(Error "Record field limit",budget)else inl(Error "Record stack",budget)
   | ApplyCall name count=>if count<=?List.length values then
       match builtin name(rev(firstn count values))budget with
       | (Good v,remaining_budget)=>resume remaining_budget(checked_tasks v tail)(skipn count values)
       | (Error e,remaining_budget)=>inl(Error e,remaining_budget)end
       else inl(Error "Call stack",budget)
   | RequireBoolean=>match values with JBool _::_=>resume budget tail values|_=>inl(Error "Boolean operand required",budget)end
   (* DEFENSE: live world fields can exceed the authored language's value limits. *)
   | Validate pending result=>match pending with
     | []=>resume budget tail(result::values)
     | (depth,value)::rest=>match depth with O=>inl(Error "Value nesting limit",budget)|S depth=>
       let continue pending:=resume budget(Validate pending result::tail)values in
       match value with
       | JNull|JBool _=>continue rest
       | JNumber spelling=>match Decimal.parse spelling with Some _=>continue rest|None=>inl(Error "Invalid fixed decimal value",budget)end
       | JString text=>if within_scalars Bounds.string_scalars text then continue rest else inl(Error "String value limit",budget)
       | JArray xs=>if List.length xs<=?Bounds.collection_items then continue(List.app(map(fun value=>(depth,value))xs)rest)else inl(Error "Collection item limit",budget)
       | JObject fs=>if (List.length fs<=?Bounds.record_fields)&&Schema.unique_names(map fst fs)
          then continue(List.app(map(fun field=>(depth,snd field))fs)rest)else inl(Error "Record field limit or duplicate key",budget)
       end end end
   end.
(* Keep the extracted driver directly tail recursive across all task variants. *)
Fixpoint run (fuel budget:nat) (tasks:list task) (values:list json) : evaluation :=
 match tasks with
 |[]=>match values with [v]=>(Good v,budget)|_=>(Error "Expression result stack",budget)end
 |head::tail=>match fuel with
   |O=>(Error "Expression evaluation budget exceeded",0)
   |S fuel=>if Nat.eqb budget 0 then(Error "Expression evaluation budget exceeded",0)else
     match evaluation_step (Nat.pred budget) head tail values with
     |inl result=>result
     |inr(remaining,tasks,values)=>run fuel remaining tasks values end
   end end.
Definition evaluate budget env e := run budget budget [Visit e env 0] [].
Definition evaluate_source budget env source :=match parse source with Good e=>evaluate budget env e|Error e=>(Error e,budget)end.
Fixpoint numeric_literal (fuel:nat)(e:expr):bool:=match fuel with
 |O=>false|S k=>match e with Value(JNumber _)=>true|Unary "-"value=>numeric_literal k value|_=>false end end.
Fixpoint is_literal (fuel:nat)(e:expr):bool:=
 match fuel with O=>false|S k=>match e with
 | Value _=>true|Unary "-"value=>numeric_literal k value
 | Array xs=>forallb(is_literal k)xs|Record fs=>forallb(fun kv=>is_literal k(snd kv))fs
 | _=>false end end.
Definition literal source :=e <-? parse source;;if is_literal 33 e then
 match evaluate Bounds.evaluation_steps [] e with (Good v,_)=>Good v|(Error e,_)=>Error e end else Error "Declaration attribute must be a literal".
