From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Kernel Require Streams.
From Selvedge.Interaction Require CodeSource Origin.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Browser Require AuditReading DocumentState DocumentPublication.
From Selvedge.Browser.Session Require Input State Navigation.
From Selvedge.Browser.Scene Require Surface.
From Selvedge.Browser.Presentation Require Projection.
Import ListNotations.
Open Scope string_scope.
Module S := Surface.
Module D := DocumentState.

Record part_update := PartUpdate {
  updated_view : task_view;
  updated_reader_generation : N;
  updated_preview : S.node Input.input
}.

Definition edit_coordinates event := match event with
 |Streams.Delta key index _|Streams.Snapshot key index _=>Some(key,index)
 |_=>None end.

Definition visible_part context key index :=
 output<-D.current_preview context key;;
 part<-find(fun part=>N.eqb(fst part)index)(Streams.output_parts output);;
 Some(output,part).

Definition make_preview context state part :=
 let source:=AuditReading.preview_source context (fst part) (fst (snd part)) in
 @AuditReading.preview_node Input.input (State.document_retention state) source (snd (snd part)) [].

(** This projection replaces only the preview element and its Markdown stream.
    Authored components mount independently inside retained Markdown targets.
    Appending within the same document lifetime preserves those mounts. *)
Definition retains_preview (before after : S.node Input.input) :=
 String.eqb(S.node_key before)(S.node_key after) &&
 match S.node_children before,S.node_children after with
 |[],[]=>match S.node_meaning before,S.node_meaning after with
   |S.RichText _ _,S.RichText _ _=>true
   |S.PublishedText previous,S.PublishedText next=>
     N.eqb(DocumentPublication.published_epoch previous)(DocumentPublication.published_epoch next)
   |_,_=>false end
 |_,_=>false end.

Definition document_key context (part:Streams.live_output * (N * string)) :=
 match AuditReading.preview_source context (fst part)(fst(snd part)) with
 |CodeSource.Generated namespace viewer origin _=>Some(Origin.content_key namespace viewer origin)
 |_=>None end.

Definition edit_part snapshot (before after : State.state) key index :=
 let previous:=Projection.document_context snapshot before in
 let next:=Projection.document_context snapshot after in
 old_part<-visible_part previous key index;; new_part<-visible_part next key index;;
 if String.eqb(snd(snd old_part))(snd(snd new_part))then None else
 let old_preview:=make_preview previous before old_part in
 let new_preview:=make_preview next after new_part in
 if retains_preview old_preview new_preview then
   let views:=filter(fun view=>N.eqb (task_view_task view)(Streams.stream_task key) &&
     match Read.find_task(task_view_task view)snapshot with Some _=>true|None=>false end)(D.context_views next)in
   Some(document_key next new_part,
    map(fun view=>PartUpdate view (State.reader_generation(Navigation.reader_for after(task_view_task view)))
      (AuditReading.in_view view new_preview))views)
 else None.
