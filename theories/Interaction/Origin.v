From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.
Inductive output_mode := Plain | InteractiveV1.
Record output_origin := OutputOrigin { producer:N; operation:N; part:N; mode:output_mode }.
Definition interactive_origin origin := match mode origin with Plain=>false|InteractiveV1=>true end.
Definition namespace_character c := let n:=nat_of_ascii c in
 (Nat.leb 48 n&&Nat.leb n 57)||(Nat.leb 97 n&&Nat.leb n 102).
Fixpoint namespace_characters s := match s with EmptyString=>true|String c rest=>namespace_character c&&namespace_characters rest end.
Definition valid_namespace s:=Nat.eqb(String.length s)32&&namespace_characters s.
Definition encode_mode m:=match m with Plain=>"plain"|InteractiveV1=>"interactive-v1"end.
Definition decode_mode s:=match s with "plain"=>Some Plain|"interactive-v1"=>Some InteractiveV1|_=>None end.
Definition encode_origin o:=JObject[("producer_task",number(producer o));("operation",number(operation o));("part",number(part o));("mode",JString(encode_mode(mode o)))].
Definition decode_origin j:=p<-natural_field "producer_task" j;;o<-natural_field "operation" j;;i<-natural_field "part" j;;m<-bind(string_field "mode" j)decode_mode;;Some(OutputOrigin p o i m).
Definition same_origin a b:=N.eqb(producer a)(producer b)&&N.eqb(operation a)(operation b)&&N.eqb(part a)(part b)&&String.eqb(encode_mode(mode a))(encode_mode(mode b)).
Definition content_key namespace viewer origin:=
  show_nat(String.length namespace)++":"++namespace++"/viewer/"++show_natural viewer++"/producer/"++show_natural(producer origin)++"/operation/"++show_natural(operation origin)++"/part/"++show_natural(part origin)++"/"++encode_mode(mode origin).
Definition observation_origin namespace viewer origin:=JObject(("namespace",JString namespace)::("viewing_task",number viewer)::object_fields(encode_origin origin)).
Definition external_allowed connected visible viewer origin :=
  connected && visible && N.eqb viewer(producer origin) && match mode origin with Plain=>false|InteractiveV1=>true end.
Theorem inherited_content_cannot_send : forall connected visible viewer origin,
  viewer<>producer origin -> external_allowed connected visible viewer origin=false.
Proof. intros. unfold external_allowed. destruct(N.eqb viewer(producer origin))eqn:E.
- apply N.eqb_eq in E;congruence.
- now rewrite andb_false_r. Qed.
Theorem plain_content_cannot_send : forall connected visible viewer p o i,
  external_allowed connected visible viewer(OutputOrigin p o i Plain)=false.
Proof. intros;unfold external_allowed;simpl;apply andb_false_r. Qed.
