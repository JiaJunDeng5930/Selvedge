From Stdlib Require Import String List Bool NArith.
From MetaRocq.Template Require Import All.
From Selvedge.Foundation Require Registry TextJson.
Import ListNotations MonadNotation.
Local Open Scope string_scope.
Local Open Scope list_scope.
Set Universe Polymorphism.

Inductive op := Map | Filter | FlatMap | Reverse | Length | Take | Drop | Find
 | Exists | Forall | Head | Last | Dedup | Indexed
 | Render | Parse | TextEqual | Zip | LeftFold | RightFold.

Definition op_name (o : op) : Stdlib.Strings.String.string :=
  match o with
  | Map => "map" | Filter => "filter" | FlatMap => "flat_map" | Reverse => "rev"
  | Length => "length" | Take => "firstn" | Drop => "skipn" | Find => "find"
  | Exists => "existsb" | Forall => "forallb" | Head => "hd_error" | Last => "last"
  | Dedup => "nodup" | Indexed => "indexed"
  | Render => "render_json" | Parse => "parse_json"
  | TextEqual => "string_eqb" | Zip => "combine" | LeftFold => "fold_left"
  | RightFold => "fold_right"
  end.

Definition operators := list (kername * op).
Definition at_head (known : operators) (body : term) : option op :=
  match body with
  | tConst name _ => option_map snd (find (fun p => eq_kername name (fst p)) known)
  | _ => None
  end.
Record origin := Origin { operation : op; binding_uses : option nat }.
Definition producer known locals body :=
  match body with
  | tApp head _ => option_map (fun value => Origin value None) (at_head known head)
  | tRel index => nth index locals None
  | _ => None
  end.
Definition feeds (src sink : op) : bool :=
  match src, sink with
  | Map, Length | Filter, Length | Indexed, Length | Reverse, Length
  | Map, Head | Filter, Head | FlatMap, Head | Reverse, Head
  | Filter, Find | Map, Find | Filter, Exists | Map, Exists
  | Filter, Forall | Map, Forall | Reverse, Last
  | Map, Map | Filter, Map | Indexed, Map | Map, Filter | Map, FlatMap
  | Zip, Map | Zip, Filter | Filter, Filter | FlatMap, Filter
  | Reverse, Reverse | Take, Take | Drop, Drop
  | Map, LeftFold | Filter, LeftFold | Map, RightFold | Filter, RightFold
  | Map, Dedup | Dedup, Length | Take, Length | Drop, Length
  | Render, Parse | Render, TextEqual => true
  | _,_ => false
  end.
Definition inputs sink (args : list term) :=
  match sink, List.rev args with
  | LeftFold, _ :: values :: _ | RightFold, values :: _ => [values]
  | Last, _ :: values :: _ => [values]
  | TextEqual, rhs :: lhs :: _ => [lhs;rhs]
  | _, value :: _ => [value]
  | _, _ => []
  end.

Record finding := Found { upstream : origin; downstream : op }.
Definition local_find known locals body :=
  match body with
  | tApp f args =>
      match at_head known f with
      | Some sink =>
          flat_map (fun arg =>
            match producer known locals arg with
            | Some src => if feeds src.(operation) sink then [Found src sink] else []
            | None => []
            end) (inputs sink args)
      | None => []
      end
  | _ => []
  end.

(* Count computational references to the producer, including consumers that
   match none of the patterns. Each binder shifts the de Bruijn coordinate. *)
Fixpoint references index body : nat :=
  match body with
  | tRel target => if Nat.eqb index target then 1 else 0
  | tApp f args => references index f + fold_right Nat.add 0 (map (references index) args)
  | tLambda _ _ inner => references (S index) inner
  | tLetIn _ rhs _ inner => references index rhs + references (S index) inner
  | tCast inner _ _ | tProj _ inner => references index inner
  | tCase _ _ scrutinee branches =>
      references index scrutinee +
      fold_right Nat.add 0 (map (fun b => references (List.length b.(bcontext) + index) b.(bbody)) branches)
  | tFix defs _ | tCoFix defs _ =>
      fold_right Nat.add 0 (map (fun d => references (List.length defs + index) d.(dbody)) defs)
  | tArray _ terms default _ =>
      references index default + fold_right Nat.add 0 (map (references index) terms)
  | tEvar _ args => fold_right Nat.add 0 (map (references index) args)
  | _ => 0
  end.
Definition push_unknown count locals := repeat (@None origin) count ++ locals.
Definition value_of_uses count := match count with None => 0 | Some n => n end.
Fixpoint walk known locals body : list finding :=
  local_find known locals body ++
  match body with
  | tApp f args => walk known locals f ++ flat_map (walk known locals) args
  | tLambda _ _ inner => walk known (None :: locals) inner
  | tLetIn _ rhs _ inner =>
      let bound := option_map (fun src => Origin src.(operation)
        (Some (Nat.max (references 0 inner) (value_of_uses src.(binding_uses))))) (producer known locals rhs) in
      walk known locals rhs ++ walk known (bound :: locals) inner
  | tCast inner _ _ | tProj _ inner => walk known locals inner
  | tCase _ _ scrutinee branches =>
      walk known locals scrutinee ++
      flat_map (fun b => walk known (push_unknown (List.length b.(bcontext)) locals) b.(bbody)) branches
  | tFix defs _ | tCoFix defs _ =>
      flat_map (fun def => walk known (push_unknown (List.length defs) locals) def.(dbody)) defs
  | tArray _ terms default _ => flat_map (walk known locals) terms ++ walk known locals default
  | tEvar _ args => flat_map (walk known locals) args
  | _ => []
  end.

Definition output_finding name item : TemplateMonad unit :=
  let count := item.(upstream).(binding_uses) in
  let msg := Stdlib.Strings.String.concat " "
   ["HIT"; bytestring.String.to_string (string_of_kername name);
    op_name item.(upstream).(operation); op_name item.(downstream);
    match count with Some _ => "let" | None => "nested" end] in
  tmMsg (bytestring.String.of_string msg) ;;
  uses <- tmEval cbv (match count with Some n => n | None => 1 end) ;;
  tmPrint uses.
Fixpoint emit name items : TemplateMonad unit :=
  match items with
  | item :: rest => output_finding name item ;; emit name rest
  | [] => tmReturn tt
  end.
Fixpoint scan_defs known owner members (body_count : nat) : TemplateMonad nat :=
  match members with
  | [] => tmReturn body_count
  | ConstRef name :: rest =>
      if eq_kername name (owner, snd name) then
      declaration <- tmQuoteConstant name false ;;
      match declaration.(cst_body) with
      | Some body =>
          found <- tmEval lazy (walk known [] body) ;;
          emit name found ;;
          scan_defs known owner rest (S body_count)
      | None => scan_defs known owner rest body_count
      end
      else scan_defs known owner rest body_count
  | _ :: rest => scan_defs known owner rest body_count
  end.
Definition scan_module known (name : Stdlib.Strings.String.string) : TemplateMonad unit :=
  let identifier := bytestring.String.of_string name in
  owners <- tmLocateModule identifier ;;
  match owners with
  | owner :: _ =>
      members <- tmQuoteModule identifier ;;
      count <- scan_defs known owner members 0 ;;
      tmMsg (bytestring.String.of_string (("MODULE " ++ name)%string)) ;;
      tmPrint count
  | [] => tmFail identifier
  end.

Definition quote_one {A : Type} (value : A) (label : op) : TemplateMonad (kername * op) :=
  quoted <- tmQuote value ;;
  match quoted with
  | tConst name _ => tmReturn (name,label)
  | _ => tmFail (bytestring.String.of_string "expected a global constant")
  end.
Fixpoint scan_modules known (modules : list Stdlib.Strings.String.string) : TemplateMonad unit :=
  match modules with
  | [] => tmReturn tt
  | name :: rest => scan_module known name ;; scan_modules known rest
  end.
Fixpoint quote_operators (entries : list (TemplateMonad (kername * op))) :
 TemplateMonad operators :=
  match entries with
  | [] => tmReturn []
  | entry :: rest =>
      operator <- entry ;;
      operators <- quote_operators rest ;;
      tmReturn (operator :: operators)
  end.
Definition scan_project (modules : list Stdlib.Strings.String.string) : TemplateMonad unit :=
  tmBind (quote_operators
    [quote_one (@List.map) Map; quote_one (@List.filter) Filter;
     quote_one (@List.flat_map) FlatMap; quote_one (@List.rev) Reverse;
     quote_one (@List.length) Length; quote_one (@List.firstn) Take;
     quote_one (@List.skipn) Drop; quote_one (@List.find) Find;
     quote_one (@List.existsb) Exists; quote_one (@List.forallb) Forall;
     quote_one (@List.hd_error) Head; quote_one (@List.last) Last;
     quote_one (@List.nodup) Dedup; quote_one (@Registry.indexed) Indexed;
     quote_one TextJson.render_json Render; quote_one TextJson.parse_json Parse;
     quote_one Stdlib.Strings.String.eqb TextEqual; quote_one (@List.combine) Zip;
     quote_one (@List.fold_left) LeftFold; quote_one (@List.fold_right) RightFold])
    (fun known => scan_modules known modules).
