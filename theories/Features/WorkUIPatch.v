From Stdlib Require Import String List Bool Ascii NArith.
From Selvedge.Foundation Require Import Utf8.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Inductive result (A:Type) := Done (value:A) | Fail (reason:string).
Arguments Done {A}. Arguments Fail {A}.
Record hunk := Hunk { before : list string; after : list string }.
Inductive patch := Add (lines:list string) | Update (hunks:list hunk) | Delete.
Definition invalid := "Use one Add, Update or Delete File operation for work-ui.dsl inside *** Begin Patch and *** End Patch; update hunks start with @@ and use exact context, - and + lines.".
Fixpoint reverse_text (source reversed:string) := match source with EmptyString=>reversed | String c rest=>reverse_text rest (String c reversed) end.
Fixpoint split_acc (source current:string) (lines:list string) := match source with
 | EmptyString=>rev (reverse_text current ""::lines)
 | String c rest=>if Ascii.eqb c "010"%char then split_acc rest "" (reverse_text current ""::lines) else split_acc rest (String c current) lines end.
Definition split (source:string) := split_acc source "" [].
Definition strip_cr (line:string) := let n:=String.length line in if String.eqb (String.substring (n-1) 1 line) (String "013"%char "") then String.substring 0 (n-1) line else line.
Definition finished (lines:list string) := forallb (String.eqb "") lines.
Fixpoint additions (lines acc:list string) : result patch := match lines with
 | []=>Fail invalid
 | line::rest=>if String.eqb line "*** End Patch" then if finished rest then Done (Add (rev acc)) else Fail invalid
 else match line with String c tail=>if Ascii.eqb c "+"%char then additions rest (tail::acc) else Fail invalid | _=>Fail invalid end end.
Definition header (line:string) := String.eqb line "@@" || String.prefix "@@ " line.
Definition finish (b a:list string) := Hunk (rev b) (rev a).
Fixpoint updates (lines b a:list string) (acc:list hunk) : result patch := match lines with
 | []=>Fail invalid
 | line::rest=>if String.eqb line "*** End Patch" then if finished rest then Done (Update (rev (finish b a::acc))) else Fail invalid
 else if header line then updates rest [] [] (finish b a::acc)
 else match line with String c tail=>
 if Ascii.eqb c " "%char then updates rest (tail::b) (tail::a) acc
 else if Ascii.eqb c "-"%char then updates rest (tail::b) a acc
 else if Ascii.eqb c "+"%char then updates rest b (tail::a) acc else Fail invalid
 | _=>Fail invalid end end.
Definition parse (lines:list string) :result patch := match lines with
 | begin_::operation::rest=>if String.eqb begin_ "*** Begin Patch" then
 if String.eqb operation "*** Add File: work-ui.dsl" then additions rest []
 else if String.eqb operation "*** Update File: work-ui.dsl" then match rest with head::tail=>if header head then updates tail [] [] [] else Fail invalid | _=>Fail invalid end
 else if String.eqb operation "*** Delete File: work-ui.dsl" then match rest with finish_::tail=>if String.eqb finish_ "*** End Patch" && finished tail then Done Delete else Fail invalid | _=>Fail invalid end else Fail invalid else Fail invalid
 | _=>Fail invalid end.
Fixpoint consume (wanted source:list string) :option (list string) := match wanted,source with
 | [],_=>Some source | head::tail,actual::rest=>if String.eqb head actual then consume tail rest else None | _,_=>None end.
Fixpoint seek (wanted source prefix:list string) :option (list string*list string) := match consume wanted source with
 | Some tail=>Some (rev prefix,tail)
 | None=>match source with []=>None | head::rest=>seek wanted rest (head::prefix) end end.
Fixpoint apply_hunks (hunks:list hunk) (source:list string) :result (list string) := match hunks with
 | []=>Done source
 | hunk::rest=>match seek (before hunk) source [] with
 | None=>Fail "Patch context does not match the current Work UI source."
 | Some (prefix,tail)=>match apply_hunks rest tail with Fail why=>Fail why | Done remainder=>Done (prefix++after hunk++remainder) end end end.
Definition source_lines (source:string) := if String.eqb source "" then [] else split source.
Definition realize (edit:patch) (source:string) :result string := match edit with
 | Add lines=>if String.eqb source "" then Done (String.concat (String "010"%char "") lines) else Fail "Add File requires an empty Work UI. Use Update File to edit the existing source."
 | Delete=>Done ""
 | Update hunks=>match apply_hunks hunks (source_lines source) with Done lines=>Done (String.concat (String "010"%char "") lines) | Fail why=>Fail why end end.
Definition scalar_bound (limit:nat) (source:string) := match Utf8.scalar_count source with Some count=>Nat.leb count limit | None=>false end.
Definition apply (source patch_source:string) :result string :=
 if scalar_bound 200000 patch_source then match parse (map strip_cr (split patch_source)) with
 | Fail why=>Fail why | Done edit=>match realize edit source with Fail why=>Fail why | Done updated=>if scalar_bound 100000 updated then Done updated else Fail "Work UI source cannot exceed 100000 characters." end end
 else Fail "A Work UI patch cannot exceed 200000 characters.".
