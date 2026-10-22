From Stdlib Require Import String List ZArith.
From Selvedge.Foundation Require Import Numbers.
Import ListNotations.
Open Scope string_scope.
Definition fraction_digits:nat:=6.
Definition decimal_scale:Z:=Z.pow 10 (Z.of_nat fraction_digits).
Definition decimal_limit:Z:=(1000000000*decimal_scale)%Z.
Definition number_spelling:nat:=18.
Definition identifier_length:nat:=64.
Definition token_scalars:nat:=8192.
Definition parser_turn:nat:=256.
Definition fence_scalars:nat:=131072.
Definition nesting:nat:=32.
Definition declarations:nat:=128.
Definition syntax_components:nat:=1024.
Definition expanded_components:nat:=4096.
Definition string_scalars:nat:=16384.
Definition collection_items:nat:=4096.
Definition record_fields:nat:=64.
Definition evaluation_steps:nat:=100000.
Definition raw_scalars:nat:=16384.
Definition snapshot_scalars:nat:=262144.
Definition table_columns:nat:=16.
Definition table_page:nat:=100.
Definition table_max_page_index:nat:=Nat.div (Nat.pred collection_items) table_page.
Definition last_table_page_index (row_count:nat):nat:=
 Nat.min table_max_page_index (Nat.div (Nat.pred row_count) table_page).
Definition chart_points:nat:=512.
Definition graph_nodes:nat:=128.
Definition graph_edges:nat:=512.
Definition interactive_fences_per_document:nat:=16.
Definition stored_documents:nat:=100.
Definition stored_bytes:nat:=5242880.
Definition retained_per_task:nat:=16.
Definition retained_per_session:nat:=64.
Definition retained_source_bytes:nat:=4194304.
Definition limits:list(string*nat):=[("fractional digits",fraction_digits);("number spelling scalars",number_spelling);
 ("identifier characters",identifier_length);("token/expression scalars",token_scalars);("tokens per scheduled parser turn",parser_turn);
 ("fence scalars",fence_scalars);("nesting depth",nesting);("declarations",declarations);("parsed components",syntax_components);
 ("expanded components",expanded_components);("string scalars",string_scalars);("collection items",collection_items);("record fields",record_fields);
 ("shared evaluation steps",evaluation_steps);("raw editor scalars",raw_scalars);("snapshot scalars",snapshot_scalars);
 ("table columns",table_columns);("table rows per page",table_page);("plotted chart points",chart_points);("graph nodes",graph_nodes);("graph edges",graph_edges);("eligible fences per document",interactive_fences_per_document);("stored documents",stored_documents);("stored bytes",stored_bytes);("retained interrupted outputs per task",retained_per_task);("retained interrupted outputs per session",retained_per_session);("retained source bytes per session",retained_source_bytes)].
Definition text:=String.concat "; "(map(fun item=>fst item++"="++show_nat(snd item))limits).
