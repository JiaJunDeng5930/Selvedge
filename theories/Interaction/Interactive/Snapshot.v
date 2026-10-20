From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects Numbers Schema TextJson Utf8.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction.Interactive Require Import Bounds Expression Syntax Local Registry Types State Paths Codec.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition root_id b := match Syntax.roots b.(syntax) with
 | Element "ui" attrs _ _::_ => Registry.lexical_id attrs | _=>None end.
Definition storage_key b := TextJson.render_json (JArray [JString "selvedge-interactive-1";
 JString b.(block_owner).(owner_key); JString (match root_id b with Some id=>id|None=>""end)]).
Definition ready b prepared :=
 (match b.(block_ending) with Complete=>true|_=>false end) && b.(fence_closed) && b.(syntax).(sealed) &&
 (match b.(syntax).(syntax_error) with None=>true|_=>false end) && negb prepared.(fatal).
Definition encode_local l := JObject [("id",JString l.(local_id));("schema",schema_json l);("value",canonical l)].
Definition payload b prepared nodes := JObject [("format",JString "selvedge-interactive-1");
 ("owner",JString b.(block_owner).(owner_key));("ui",match root_id b with Some id=>JString id|None=>JNull end);
 ("definition",JString b.(source));("locals",JArray(map encode_local b.(locals)));
 ("views",Codec.encode_views(Paths.persistent_views prepared nodes b.(views)))].
Definition restore_local declared value :=
 id <- string_field "id" value;; schema <- field "schema" value;; value <- field "value" value;;
 if String.eqb id declared.(local_id) && JsonObjects.equivalent schema (schema_json declared)
 then Local.assign declared value else None.
Fixpoint restore_locals declared values := match declared,values with
 | [],[]=>Some []
 | l::rest,value::tail=>l <- restore_local l value;;rest <- restore_locals rest tail;;Some(l::rest)
 | _,_=>None end.
Definition decode b prepared value : option (list local * list(string*view_state)) :=
 if TextJson.within_scalars Bounds.snapshot_scalars(TextJson.render_json value)then
 format <- string_field "format" value;;owner <- string_field "owner" value;;ui <- string_field "ui" value;;
 definition <- string_field "definition" value;;expected_ui <- root_id b;;
 if String.eqb format "selvedge-interactive-1" && String.eqb owner b.(block_owner).(owner_key) &&
    String.eqb ui expected_ui && String.eqb definition b.(source)
 then values <- array_field "locals" value;;locals <- restore_locals b.(locals) values;;
   encoded_views <- field "views" value;;views <- Codec.decode_views encoded_views;;
   if forallb (Paths.declared prepared) views then Some(locals,views) else None
 else None else None.
Definition save b prepared nodes :=
 if ready b prepared then
 let value:=payload b prepared nodes in
 if TextJson.within_scalars Bounds.snapshot_scalars (TextJson.render_json value)
 then (State.with_notice None b,[SaveSnapshot b.(block_owner) (storage_key b) b.(revision) value])
 (* DEFENSE: Canonical user state can exceed the persistent entry limit while
    remaining valid in memory; keep the edit and report that no write occurred. *)
 else (State.with_notice (Some "本地状态超过保存上限；当前输入仍保留，但尚未保存。") b,[])
 else (b,[]).
Definition request b prepared :=
 match b.(restore_state) with
 | Unrequested => if ready b prepared && negb b.(edited) then
   (State.with_restoration (LoadingSnapshot b.(revision)) b,
    [LoadSnapshot b.(block_owner) (storage_key b) b.(source) b.(revision)]) else (b,[])
 | _=>(b,[]) end.
Definition restore_admitted b prepared definition callback_revision :=
 match b.(restore_state) with
 | LoadingSnapshot requested =>
   N.eqb requested callback_revision && N.eqb callback_revision b.(revision) && negb b.(edited) &&
      String.eqb definition b.(source) && ready b prepared
 | _=>false end.
Definition restore b prepared definition callback_revision value :=
 if restore_admitted b prepared definition callback_revision then
   let b:=State.with_restoration RestorationSettled b in
   match value with
   | None => (b,[])
   | Some raw => match Codec.bind(TextJson.parse_json raw)(fun entry=>Codec.bind(field "payload"entry)(decode b prepared))with
     | Some(locals,views)=>(State.with_views views (State.with_locals locals b),[])
     (* DEFENSE: Browser storage can contain a corrupt or obsolete entry. Admit
        the complete entry before applying any value, then remove invalid data. *)
     | None=>(State.with_notice (Some "本地保存的状态无效，已忽略并移除。") b,
       [RemoveSnapshot b.(block_owner) (storage_key b)]) end
   end else (b,[]).
